// Ideas I5, I10, I56, I57, I59: choke groups, metronome settings, sidechain
// ducking, track drive/bit depth and the master look-ahead limiter. Every
// block is bit-identical when off; each one is measured against that baseline.
#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double rate=48000;
struct Stereo {std::vector<float> l,r;};
using Setup=void(*)(LGKernel*);

LGTrackDynamics none(){LGTrackDynamics d{};return d;}

Stereo run(const std::vector<LGNote>&input,int frames,double bpm,void(*setup)(LGKernel*),float masterDB=-3,int metronome=0){
    auto*k=lg_create(rate);
    std::vector<LGNote> notes=input;std::sort(notes.begin(),notes.end(),[](auto&a,auto&b){return a.tick<b.tick;});
    std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,1,9,101},{{-6,0,1},2,2,1,102}}};
    assert(lg_submit_project(k,notes.data(),int(notes.size()),bpm,0,3840*8,0,1,1,tracks.data(),2,masterDB,0,0));
    if(setup)setup(k);
    lg_metronome(k,metronome);
    lg_seek(k,0);std::array<float,1> a{},b{};lg_render(k,a.data(),b.data(),1);lg_play(k,1);
    Stereo out{std::vector<float>(size_t(frames)),std::vector<float>(size_t(frames))};
    for(int pos=0;pos<frames;pos+=256){const int n=std::min(256,frames-pos);lg_render(k,out.l.data()+pos,out.r.data()+pos,n);}
    for(int i=0;i<frames;i++)assert(std::isfinite(out.l[size_t(i)])&&std::isfinite(out.r[size_t(i)]));
    lg_destroy(k);return out;
}
double rms(const std::vector<float>&v,int from,int to){double s=0;for(int i=from;i<to;i++)s+=double(v[size_t(i)])*v[size_t(i)];return std::sqrt(s/std::max(1,to-from));}
double peak(const std::vector<float>&v,int from,int to){double p=0;for(int i=from;i<to;i++)p=std::max(p,double(std::abs(v[size_t(i)])));return p;}
double db(double x){return 20*std::log10(std::max(1e-12,x));}
int frameOf(int tick,double bpm){return int(std::lround(tick/960.0*60/bpm*rate));}

void zeroDynamics(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};assert(lg_dynamics(k,d.data(),2,0,-1));assert(lg_metronome_config(k,0,1,0));}
void chokeOpenHats(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};d[0].choke[9]=1;d[0].choke[10]=1;assert(lg_dynamics(k,d.data(),2,0,-1));}
void duckBass(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};d[1].sidechainDB=12;assert(lg_dynamics(k,d.data(),2,0,-1));}
void driveBass(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};d[1].drive=1;assert(lg_dynamics(k,d.data(),2,0,-1));}
void crushBass(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};d[1].crushBits=4;assert(lg_dynamics(k,d.data(),2,0,-1));}
void limitMaster(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};assert(lg_dynamics(k,d.data(),2,1,-1));assert(lg_limiter_latency(k)==72);}
void sendHats(LGKernel*k){std::array<LGTrackDynamics,2> d{none(),none()};d[0].reverbSend=0.5f;assert(lg_dynamics(k,d.data(),2,0,-1));}
void sweepOpen(LGKernel*k){LGFilterRamp ramp{0,3840*2,-0.9f,0.f};assert(lg_filter_automation(k,&ramp,1));}
void noSweep(LGKernel*k){assert(lg_filter_automation(k,nullptr,0));}
void quietClick(LGKernel*k){assert(lg_metronome_config(k,-12,1,0));}
void flatClick(LGKernel*k){assert(lg_metronome_config(k,0,0,0));}
}

int main(){
    const double bpm=120;
    // A beat: kick on every quarter, a sustained bass note, and two clap-type pads.
    std::vector<LGNote> beat;
    for(int q=0;q<8;q++)beat.push_back({q*960,240,36,120,0,0,1});
    beat.push_back({0,3840*2,40,110,1,-1,2});
    beat.push_back({1920,120,40,120,0,4,1});beat.push_back({1920+240,120,40,120,0,5,1});
    const int frames=frameOf(3840*2,bpm);

    // Bypass: an explicit all-zero configuration is bit-identical to never calling it.
    auto base=run(beat,frames,bpm,nullptr),zero=run(beat,frames,bpm,zeroDynamics);
    assert(base.l==zero.l&&base.r==zero.r);

    // Validation.
    {auto*k=lg_create(rate);LGTrackDynamics bad=none();bad.crushBits=3;assert(!lg_dynamics(k,&bad,1,0,-1));bad=none();bad.sidechainDB=13;assert(!lg_dynamics(k,&bad,1,0,-1));
     bad=none();bad.choke[0]=9;assert(!lg_dynamics(k,&bad,1,0,-1));assert(!lg_dynamics(k,nullptr,0,1,0));assert(!lg_metronome_config(k,7,1,0));assert(!lg_metronome_config(k,0,1,3));
     assert(lg_limiter_latency(k)==0);lg_destroy(k);}

    // I5 choke: pad 10 silences the still-ringing pad 9 in the same group.
    std::vector<LGNote> hats={{0,120,40,120,0,9,1},{240,120,40,120,0,10,1}};
    auto open=run(hats,frameOf(1920,bpm),bpm,nullptr),choked=run(hats,frameOf(1920,bpm),bpm,chokeOpenHats);
    const int second=frameOf(240,bpm);
    assert(rms(open.l,0,second-8)==rms(choked.l,0,second-8));            // identical before the choke
    std::vector<LGNote> only5={{240,120,40,120,0,10,1}};auto alone=run(only5,frameOf(1920,bpm),bpm,nullptr);
    const int after=second+int(rate*0.01);
    // After the 3 ms retirement only pad 10 is left: equal to pad 10 alone.
    double diff=0;for(int i=after;i<after+4800;i++)diff=std::max(diff,double(std::abs(choked.l[size_t(i)]-alone.l[size_t(i)])));
    assert(diff<1e-6);
    assert(rms(open.l,after,after+4800)>rms(alone.l,after,after+4800)*1.05);

    // I56 sidechain: the bass dips by about the depth right after each kick and recovers.
    std::vector<LGNote> bassOnly={{0,3840*2,40,110,1,-1,2}};
    auto bassWithKick=beat;bassWithKick.erase(std::remove_if(bassWithKick.begin(),bassWithKick.end(),[](auto&n){return n.pad>0;}),bassWithKick.end());
    // Measure the bass alone by subtracting the kick-only render (linear mix).
    std::vector<LGNote> kicks;for(auto&n:bassWithKick)if(n.pad==0)kicks.push_back(n);
    auto kicksOnly=run(kicks,frames,bpm,duckBass),mixed=run(bassWithKick,frames,bpm,duckBass),dry=run(bassOnly,frames,bpm,nullptr);
    std::vector<float> ducked(static_cast<size_t>(frames));for(int i=0;i<frames;i++)ducked[size_t(i)]=mixed.l[size_t(i)]-kicksOnly.l[size_t(i)];
    const int beat2=frameOf(960,bpm);
    const double dip=db(rms(ducked,beat2+int(rate*0.012),beat2+int(rate*0.03)))-db(rms(dry.l,beat2+int(rate*0.012),beat2+int(rate*0.03)));
    const double recover=db(rms(ducked,beat2+int(rate*0.45),beat2+int(rate*0.49)))-db(rms(dry.l,beat2+int(rate*0.45),beat2+int(rate*0.49)));
    assert(dip< -9&&dip> -12.5);
    assert(recover> -0.5);
    // Click-free: no sample-to-sample jump in the ducked bass beyond the dry signal's own slope.
    double maxStep=0,dryStep=0;for(int i=beat2;i<beat2+4800;i++){maxStep=std::max(maxStep,double(std::abs(ducked[size_t(i)]-ducked[size_t(i-1)])));dryStep=std::max(dryStep,double(std::abs(dry.l[size_t(i)]-dry.l[size_t(i-1)])));}
    assert(maxStep<=dryStep*1.05);

    // I57 drive: louder RMS relative to peak (saturation), still bounded.
    auto driven=run(bassOnly,frames,bpm,driveBass);
    const int w0=int(rate*0.2),w1=int(rate*0.6);
    const double crestDry=peak(dry.l,w0,w1)/rms(dry.l,w0,w1),crestDriven=peak(driven.l,w0,w1)/rms(driven.l,w0,w1);
    assert(crestDriven<crestDry*0.97);
    assert(peak(driven.l,0,frames)<0.98);
    // Bit depth: the bass bus is quantized (fewer distinct levels before the fader).
    auto crushed=run(bassOnly,frames,bpm,crushBass);
    std::vector<float> levels(crushed.l.begin()+w0,crushed.l.begin()+w1);std::sort(levels.begin(),levels.end());
    const auto distinct=std::unique(levels.begin(),levels.end())-levels.begin();
    assert(distinct<=40);

    // I59 limiter: a loud mix stays under the -1 dBFS ceiling without hard clipping.
    std::vector<LGNote> loud;
    for(int q=0;q<8;q++){loud.push_back({q*960,240,36,127,0,0,1});loud.push_back({q*960,240,38,127,0,1,1});}
    for(int p:{40,47,52,55,59,64,67,71,74,76,79,83})loud.push_back({0,3840*2,p,127,1,-1,2});
    auto clipped=run(loud,frames,bpm,nullptr,6),limited=run(loud,frames,bpm,limitMaster,6);
    const float ceiling=std::pow(10.f,-1.f/20);
    int atRail=0;for(float v:clipped.l)if(std::abs(v)>=0.98f)atRail++;
    assert(atRail>0);
    for(int i=0;i<frames;i++){assert(std::abs(limited.l[size_t(i)])<=ceiling+1e-6f&&std::abs(limited.r[size_t(i)])<=ceiling+1e-6f);}
    assert(peak(limited.l,0,frames)>ceiling*0.9);

    // I58 send reverb: a dry hit has silence after its decay; with a send the room keeps ringing.
    std::vector<LGNote> hit={{0,120,40,120,0,2,1}};
    auto dryHit=run(hit,frameOf(3840,bpm),bpm,nullptr),wetHit=run(hit,frameOf(3840,bpm),bpm,sendHats);
    const int late0=int(rate*0.4),late1=int(rate*0.6);
    std::vector<float> room(wetHit.l.size());for(size_t i=0;i<room.size();i++)room[i]=wetHit.l[i]-dryHit.l[i];
    const double roomLevel=db(rms(room,2400,14400))-db(rms(dryHit.l,0,2400));
    assert(roomLevel> -16&&roomLevel< -6);                             // a send of 0.5 returns about −11 dB
    assert(rms(dryHit.l,late0,late1)<1e-6&&rms(wetHit.l,late0,late1)>1e-4);
    double lr=0;for(int i=late0;i<late1;i++)lr+=std::abs(wetHit.l[size_t(i)]-wetHit.r[size_t(i)]);
    assert(lr>0);                                                      // decorrelated stereo
    {LGTrackDynamics bad=none();bad.reverbSend=1.5f;auto*k=lg_create(rate);assert(!lg_dynamics(k,&bad,1,0,-1));lg_destroy(k);}

    // I36 filter sweep: the low-pass opens across two bars; none = bit-identical.
    std::vector<LGNote> hats16;for(int i=0;i<32;i++)hats16.push_back({i*240,120,40,110,0,2,1});
    auto open16=run(hats16,frames,bpm,nullptr),none16=run(hats16,frames,bpm,noSweep),swept=run(hats16,frames,bpm,sweepOpen);
    assert(open16.l==none16.l);
    const double early=rms(swept.l,0,frames/4)/rms(open16.l,0,frames/4),late=rms(swept.l,frames*3/4,frames)/rms(open16.l,frames*3/4,frames);
    assert(early<0.3&&late>0.5&&late>early*3);                         // still sweeping in the last quarter
    {auto*k=lg_create(rate);LGFilterRamp bad[2]={{0,100,0,0.5f},{50,200,0,0}};assert(!lg_filter_automation(k,bad,2));bad[0].to=2;assert(!lg_filter_automation(k,bad,1));lg_destroy(k);}

    // I10 metronome: level and accent.
    std::vector<LGNote> silent={{0,1,60,1,1,-1,2}};
    auto clickNormal=run(silent,frameOf(1920,bpm),bpm,nullptr,-3,1),clickQuiet=run(silent,frameOf(1920,bpm),bpm,quietClick,-3,1),clickFlat=run(silent,frameOf(1920,bpm),bpm,flatClick,-3,1);
    const int q1=frameOf(960,bpm);
    const double ratio=peak(clickQuiet.l,q1,q1+2400)/peak(clickNormal.l,q1,q1+2400);
    assert(std::abs(db(ratio)+12)<0.6);
    // Without accent the downbeat equals a later beat (same pitch and level).
    double accentDiff=0,flatDiff=0;
    for(int i=0;i<1600;i++){accentDiff+=std::abs(clickNormal.l[size_t(i+8)]-clickNormal.l[size_t(q1+i+8)]);flatDiff+=std::abs(clickFlat.l[size_t(i+8)]-clickFlat.l[size_t(q1+i+8)]);}
    assert(accentDiff>1&&flatDiff<accentDiff*0.05);

    std::printf("Studio dynamics: bypass bit-identical; send reverb return %.1f dB; filter sweep %.2f -> %.2f of open level; choke leaves only the new pad; sidechain dip %.1f dB, recovery %.2f dB; drive crest %.2f -> %.2f; 4-bit bus %ld levels; limiter peak %.3f <= %.3f (no rail); click -12 dB = %.2f dB\n",
        roomLevel,early,late,dip,recover,crestDry,crestDriven,long(distinct),peak(limited.l,0,frames),double(ceiling),db(ratio));
}
