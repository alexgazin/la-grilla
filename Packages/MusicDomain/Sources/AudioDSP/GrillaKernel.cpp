#include "GrillaKernel.h"
#include <atomic>
#include <cmath>
#include <algorithm>
#include <array>
#include <vector>
constexpr int MaxNotes=12000, MaxVoices=64, KitFrames=48000;
constexpr double Pi=3.14159265358979323846;
struct Snapshot { std::atomic<int> state{0}, revision{-1}; std::array<LGNote,MaxNotes> notes{}; int count=0,start=0,end=15360; double bpm=120; bool loop=true; };
struct Voice { bool on=false; int pitch=0,track=0,pad=-1; double phase=0,age=0,duration=0; float velocity=0,level=0; };
struct Input { int value=0,velocity=100; bool preview=false; };
struct LGKernel {
    double sr; std::array<Snapshot,3> slots; int current=-1;
    std::array<Voice,MaxVoices> voices{};
    std::array<std::vector<float>,16> kit;
    std::array<Input,256> input{}; std::atomic<unsigned> write{0},read{0}; std::atomic<int> overflow{0};
    std::atomic<int> countRequest{0},countRemaining{0}; int counting=0;
    std::atomic<int> command{0},seek{-1},playing{0},applied{-1},metro{0},tailOnEnd{0};
    std::atomic<double> position{0}; std::atomic<uint64_t> clock{0};
    std::array<std::atomic<float>,4> gains, pans, meters; std::array<float,4> smooth{}, smoothPan{};
    bool active=false; double origin=0; uint64_t elapsed=0,rendered=0; double previous=-1; long long cycle=0; int cursor=0; int lastBeat=-1;
    explicit LGKernel(double rate):sr(rate) {
        for(int i=0;i<4;i++){ gains[i].store(i==3?0.708f:0.5f);pans[i].store(0);meters[i].store(0);smooth[i]=gains[i].load(); }
        uint32_t noise=0x4c47524c;
        for(int pad=0;pad<16;pad++) {
            kit[pad].resize(KitFrames);
            double low=0;
            for(int f=0;f<KitFrames;f++) {
                double t=f/sr; noise^=noise<<13;noise^=noise>>17;noise^=noise<<5; double n=double(noise)/2147483648.0-1;
                double x=0;
                if(pad==0) x=std::sin(2*Pi*(48*t+7*(1-std::exp(-t*35))))*std::exp(-t*12);
                else if(pad==1||pad==4||pad==5) x=(n*0.72+std::sin(2*Pi*(pad==5?420:185)*t)*0.28)*std::exp(-t*(pad==5?55:18));
                else if(pad==2||pad==3||pad==9||pad==10||pad==11||pad==14) {low+=0.18*(n-low);x=(n-low)*std::exp(-t*(pad==3?9:pad==9?4:pad==2?65:22));}
                else x=(std::sin(2*Pi*(95+(pad-6)*44)*t)+0.18*n)*std::exp(-t*(pad==12?20:12));
                kit[pad][f]=float(x*0.5*std::min(1.0,t*2000));
            }
        }
    }
    void silence(){ for(auto &v:voices)v.on=false; }
    void trigger(int pitch,int velocity,int track,int pad,double duration){
        if(pad==2)for(auto &v:voices)if(v.pad==3)v.duration=std::min(v.duration,v.age+0.004);
        Voice *v=nullptr; for(auto &x:voices)if(!x.on){v=&x;break;}
        if(!v) v=&*std::min_element(voices.begin(),voices.end(),[](auto&a,auto&b){return a.level<b.level;});
        *v=Voice{true,pitch,track,pad,0,0,duration,float(velocity/127.0),0};
    }
    double ticksPerFrame() { return current<0?0:slots[current].bpm*960/(60*sr); }
    void resetCursor(double tick){cursor=0;cycle=0;origin=tick;elapsed=0;previous=tick-1;lastBeat=-1;silence();
        if(current<0) return;
        auto&s=slots[current];
        while(cursor<s.count&&s.notes[cursor].tick<tick){auto&n=s.notes[cursor];if(active&&n.pad<0&&n.tick+n.duration>tick)trigger(n.pitch,n.velocity,n.track,-1,(n.tick+n.duration-tick)/960*60/s.bpm);cursor++;}
    }
    void adopt(bool force,double tick){
        int chosen=-1,best=applied.load(std::memory_order_relaxed);
        for(int i=0;i<3;i++)if(slots[i].state.load(std::memory_order_acquire)==2){int rev=slots[i].revision.load();if(rev>=best){best=rev;chosen=i;}}
        if(chosen<0)return;
        if(!force && current>=0 && int(tick/3840)==int(std::max(0.0,previous)/3840))return;
        int ready=2;if(!slots[chosen].state.compare_exchange_strong(ready,3,std::memory_order_acq_rel))return;
        if(current>=0)slots[current].state.store(0,std::memory_order_release);
        current=chosen;applied.store(slots[chosen].revision.load(std::memory_order_relaxed));auto&s=slots[current];
        resetCursor(tick>=s.start && tick<s.end ? tick : s.start);
    }
};
extern "C" {
LGKernel*lg_create(double sr){return std::isfinite(sr)&&sr>=8000&&sr<=192000 ? new LGKernel(sr) : nullptr;}
void lg_destroy(LGKernel*k){delete k;}
int lg_submit(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev){
    if((count>0&&!notes)||count<0||count>MaxNotes||!std::isfinite(bpm)||bpm<40||bpm>240||start<0||end<=start)return 0;
    for(int n=0;n<count;n++)if(notes[n].tick<0||notes[n].duration<=0||notes[n].pitch<0||notes[n].pitch>127||notes[n].track<0||notes[n].track>2||notes[n].pad < -1||notes[n].pad>15)return 0;
    for(auto&s:k->slots){int expected=0;if(!s.state.compare_exchange_strong(expected,1)){expected=2;if(!s.state.compare_exchange_strong(expected,1))continue;}
        if(count>0){std::copy(notes,notes+count,s.notes.begin());}s.count=count;s.bpm=bpm;s.start=start;s.end=end;s.loop=loop;
        std::sort(s.notes.begin(),s.notes.begin()+count,[](auto&a,auto&b){return a.tick<b.tick;});
        s.revision.store(rev);s.state.store(2,std::memory_order_release);return 1;
    }return 0;
}
void lg_countin(LGKernel*k,int frames){k->countRequest.store(frames);}
int lg_countremaining(LGKernel*k){return k->countRemaining.load();}
void lg_play(LGKernel*k,int play){k->command.store(play?1:-1,std::memory_order_release);}
void lg_seek(LGKernel*k,int tick){k->seek.store(tick);}
static int enqueue(LGKernel*k,Input value){unsigned w=k->write.load(std::memory_order_relaxed),r=k->read.load(std::memory_order_acquire);if(w-r>=256){k->overflow.fetch_add(1);return 0;}k->input[w%256]=value;k->write.store(w+1,std::memory_order_release);return 1;}
int lg_pad(LGKernel*k,int pad,int velocity){if(pad<0||pad>15)return 0;return enqueue(k,{pad,std::clamp(velocity,1,127),false});}
void lg_preview(LGKernel*k,int pitch){if(pitch>=0&&pitch<=127)enqueue(k,{pitch,95,true});}
void lg_mix(LGKernel*k,int t,float db,float pan,int audible){if(t<0||t>2||!std::isfinite(db)||!std::isfinite(pan))return;k->gains[t].store(audible&&db> -61?std::pow(10.f,std::clamp(db,-60.f,6.f)/20):0);k->pans[t].store(std::clamp(pan,-1.f,1.f));}
void lg_master(LGKernel*k,float db){if(std::isfinite(db))k->gains[3].store(db> -61?std::pow(10.f,std::clamp(db,-60.f,6.f)/20):0);}
void lg_tail_on_end(LGKernel*k,int enabled){k->tailOnEnd.store(enabled);}
void lg_metronome(LGKernel*k,int on){k->metro.store(on);}
void lg_render(LGKernel*k,float*l,float*r,int frames){
    int cmd=k->command.exchange(0);if(cmd<0){k->active=false;k->counting=0;k->countRequest.store(0);k->countRemaining.store(0);k->silence();k->read.store(k->write.load());}
    k->adopt(!k->active,k->position.load());
    int seek=k->seek.exchange(-1);if(seek>=0){k->resetCursor(seek);k->position.store(seek);}
    if(cmd>0&&k->current>=0){auto&s=k->slots[k->current];double p=k->position.load();k->active=true;k->resetCursor(p>=s.end?s.start:std::max(p,double(s.start)));}
    int request=k->countRequest.exchange(0);if(request>0)k->counting=request;
    unsigned rd=k->read.load(),wr=k->write.load(std::memory_order_acquire);
    while(rd<wr){auto v=k->input[rd++%256];k->trigger(v.preview?v.value:36,v.velocity,v.preview?0:1,v.preview?-1:v.value,v.preview?0.65:1);}
    k->read.store(rd,std::memory_order_release);
    float peak[4]={};const float ramp=float(1-std::exp(-1/(k->sr*0.005)));
    for(int f=0;f<frames;f++){
        if(k->counting>0){int beatFrames=int(k->sr*60/k->slots[k->current].bpm);if(k->counting%beatFrames==0)k->trigger(k->counting>beatFrames*3?96:84,65,3,-1,0.035);k->counting--;k->countRemaining.store(k->counting);}
        else if(k->active&&k->current>=0){
            auto*s=&k->slots[k->current];double tp=k->ticksPerFrame();double raw=k->origin+k->elapsed*tp;double tick=raw-k->cycle*(s->end-s->start);
            if(tick>=s->end-0.5*tp){if(s->loop){k->cycle++;tick-=s->end-s->start;k->cursor=0;k->silence();while(k->cursor<s->count&&s->notes[k->cursor].tick<s->start)k->cursor++;k->lastBeat=-1;}else{k->active=false;if(!k->tailOnEnd.load())k->silence();tick=s->end;}}
            int old=k->current;k->adopt(false,tick);if(k->current!=old){s=&k->slots[k->current];tick=k->origin;tp=k->ticksPerFrame();}
            if(k->active){
                while(k->cursor<s->count&&s->notes[k->cursor].tick<=tick+0.5*tp){auto&n=s->notes[k->cursor++];if(n.tick>=s->start&&n.tick<s->end)k->trigger(n.pitch,n.velocity,n.track,n.pad,n.pad>=0?KitFrames/k->sr:std::min(n.duration,s->end-n.tick)/960.0*60/s->bpm);}
                int beat=int(tick/960);if(beat!=k->lastBeat){if(k->metro.load())k->trigger(beat%4?84:96,65,3,-1,0.035);k->lastBeat=beat;}
                k->position.store(tick,std::memory_order_relaxed);k->previous=tick;k->elapsed++;
            }else k->position.store(tick);
        }
        for(int t=0;t<4;t++){k->smooth[t]+=(k->gains[t].load(std::memory_order_relaxed)-k->smooth[t])*ramp;k->smoothPan[t]+=(k->pans[t].load(std::memory_order_relaxed)-k->smoothPan[t])*ramp;}
        float left=0,right=0;
        for(auto&v:k->voices)if(v.on){
            float sample=0;const double remaining=v.duration-v.age;
            if(remaining<=0){v.on=false;continue;}
            if(v.pad>=0){int frame=int(v.age*k->sr);if(frame>=KitFrames){v.on=false;continue;}sample=k->kit[v.pad][frame];}
            else {double hz=440*std::pow(2.,(v.pitch-69)/12.);v.phase+=hz/k->sr;if(v.phase>=1)v.phase-=1;sample=float((std::sin(2*Pi*v.phase)+0.22*std::sin(4*Pi*v.phase))*0.17);}
            double envelope=std::min(1.,v.age/0.004)*std::min(1.,remaining/0.008);if(v.pad<0)envelope*=std::exp(-v.age*(v.track==2?1.5:0.7));
            sample*=float(envelope)*v.velocity;v.level=std::abs(sample);v.age+=1/k->sr;
            int t=v.track;float amp=sample*(t==3?0.65f:k->smooth[t]);float angle=(k->smoothPan[t]+1)*float(Pi/4);
            left+=amp*std::cos(angle);right+=amp*std::sin(angle);peak[t]=std::max(peak[t],std::abs(amp));
        }
        left*=k->smooth[3];right*=k->smooth[3];peak[3]=std::max(peak[3],std::max(std::abs(left),std::abs(right)));
        l[f]=std::clamp(left,-0.98f,0.98f);r[f]=std::clamp(right,-0.98f,0.98f);k->rendered++;
    }
    for(int t=0;t<4;t++)k->meters[t].store(std::max(peak[t],k->meters[t].load()*0.85f));
    k->clock.store(k->rendered);k->playing.store(k->active?1:0);
}
double lg_tick(LGKernel*k){return k->position.load();}uint64_t lg_clock(LGKernel*k){return k->clock.load();}
int lg_playing(LGKernel*k){return k->playing.load();}int lg_revision(LGKernel*k){return k->applied.load();}
float lg_meter(LGKernel*k,int t){return t>=0&&t<4?k->meters[t].load():0;}
int lg_overflows(LGKernel*k){return k->overflow.load();}
}
