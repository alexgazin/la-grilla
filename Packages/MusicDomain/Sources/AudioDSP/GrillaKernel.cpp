#include "GrillaKernel.h"
#include "PerformanceFX.hpp"
#include "PerformanceRuntime.hpp"
#include "MIDIHub.hpp"
#include "Equalizer.hpp"
#include "Reverb.hpp"
#include <complex>
#include <atomic>
#include <cmath>
#include <algorithm>
#include <array>
#include <vector>
#include <limits>
constexpr int MaxNotes=32768, MaxTracks=8, Master=8, Buses=9, MaxVoices=64, LegacyKitFrames=48000;
constexpr double Pi=3.14159265358979323846;
struct LGSampleBank {
    std::atomic<int> references{1};
    int rate;
    bool ringsOut;
    std::vector<int16_t> pcm;
    std::array<LGSampleZone,128> nearest{};
};
namespace {
template<size_t N>
void replaceBanks(std::array<LGSampleBank*,N>& owned,LGSampleBank *const *banks){
    for(size_t i=0;i<N;i++){
        auto *next=banks?banks[i]:nullptr;
        if(owned[i]==next)continue;
        if(next)next->references.fetch_add(1,std::memory_order_relaxed);
        lg_sample_release(owned[i]);
        owned[i]=next;
    }
}
}
struct Snapshot {
    EQDesk eq{};
    std::atomic<int> state{0}, revision{-1};
    std::array<LGNote,MaxNotes> notes{};
    int count=0,start=0,end=15360,trackCount=0;
    double bpm=120;
    bool loop=true,hasProjectMix=false;
    uint64_t layoutToken=0,mixSequence=0;
    std::array<float,Buses> gain{},pan{};
    std::array<int32_t,MaxTracks> preset{},instruments{},midiChannels{};
    std::array<uint64_t,MaxTracks> trackKeys{};
    float filter=0,delay=0;
    std::array<LGSampleBank*,MaxTracks> sampleInstruments{};
    std::array<LGSampleBank*,16> samplePads{};
    ~Snapshot(){replaceBanks(sampleInstruments,nullptr);replaceBanks(samplePads,nullptr);}
    const LGSampleBank *sampleAt(int track,int pad) const {
        if(pad>=0&&pad<16)return samplePads[pad];
        return track>=0&&track<MaxTracks?sampleInstruments[track]:nullptr;
    }
};
struct MixSnapshot {EQDesk eq{};std::atomic<int> state{0};std::atomic<uint64_t> revision{0};int musicRevision=-1;std::array<float,Buses> gain{},pan{};float filter=0,delay=0;};
struct Voice { bool on=false; int pitch=0,track=0,pad=-1,instrument=0; double phase=0,age=0,duration=0; float velocity=0,level=0;int sourceKey=-1;bool keyDown=false;bool outputAllowed=true;int outputChannel=-1,outputPitch=0;uint32_t outputEpoch=0;uint64_t outputEndFrame=0;int presetVersion=1;double phaseStep=0,decayStep=1,decay=1;uint64_t ageFrames=0;float lastSample=0;double playbackRatio=1,attack=0.004,toneAlpha=1;float toneState=0;std::array<double,4> partials{};
    const LGSampleBank *sample=nullptr;
    LGSampleZone zone{};
    double sampleCursor=0;
};

static float sampleFrame(Voice& voice){
    const auto &zone=voice.zone;
    constexpr int crossfade=256;
    auto &cursor=voice.sampleCursor;
    if(cursor>=zone.frames){
        if(zone.loopStart<=0)return 0;
        const int begin=zone.loopStart+crossfade;
        cursor=begin+std::fmod(cursor-zone.frames,zone.frames-begin);
    }
    const auto read=[&](double position){
        const int index=int(position),next=std::min(zone.frames-1,index+1);
        const auto *pcm=voice.sample->pcm.data()+zone.offset;
        return (pcm[index]+(pcm[next]-pcm[index])*float(position-index))/32768.f;
    };
    float value=read(cursor);
    if(zone.loopStart>0&&cursor>=zone.frames-crossfade){
        const double offset=cursor-(zone.frames-crossfade);
        const float weight=float(offset/crossfade);
        value=value*(1-weight)+read(zone.loopStart+offset)*weight;
    }
    cursor+=voice.playbackRatio;
    return value;
}
// Build 44: the built-in keybed has no listening gain of its own. A key played
// live, the recorded note and the offline WAV share one gain structure:
// velocity -> instrument -> track fader -> master.
struct Retirement {float sample=0;int track=0,remaining=0,total=1;};
struct Input { int value=0,velocity=100,track=0,instrument=0; bool preview=false;uint64_t identity=0; };
struct OutputTimingMeter {
    static_assert(std::atomic<uint64_t>::is_always_lock_free&&std::atomic<uint32_t>::is_always_lock_free,"Output timing publication requires lock-free atomics");
    std::atomic<uint64_t> request{0},sequence{0},epoch{0},callbacks{0},comparedCallbacks{0};
    std::atomic<uint64_t> maxExcess{0},maxInterval{0},baselineBuffer{0},nonIncreasing{0},rateChanges{0};
    std::atomic<uint32_t> baselineFrames{0},inheritedAnchor{0};
    // One render owner. The published fields above are atomic so bounded
    // control-thread snapshot reads never race a resetting measurement.
    LGOutputTiming measured{};uint64_t publication=0,lastHost=0;int lastFrames=0;double lastRate=0;bool anchored=false;
    static uint64_t nanoseconds(long double value){
        if(!(value>0))return 0;
        const long double rounded=std::floor(value+0.5L);
        return !std::isfinite(rounded)||rounded>=static_cast<long double>(UINT64_MAX)?UINT64_MAX:static_cast<uint64_t>(rounded);
    }
    static void increment(uint64_t &value){if(value!=UINT64_MAX)++value;}
    void observe(uint64_t host,double rate,int frames,double sampleRate){
        if(host==0||!std::isfinite(rate)||rate<=0||frames<=0)return;
        const uint64_t requested=request.load(std::memory_order_acquire);
        if(requested!=0){
            if(measured.epoch!=requested){
                measured={};measured.epoch=requested;measured.inheritedAnchor=anchored?1:0;
                measured.baselineFrames=uint32_t(anchored?lastFrames:frames);
                measured.baselineBufferNanoseconds=nanoseconds(static_cast<long double>(measured.baselineFrames)*1e9L/sampleRate);
            }
            increment(measured.callbacks);
            if(anchored){
                if(host<=lastHost)increment(measured.nonIncreasingTimestamps);
                if(rate!=lastRate)increment(measured.clockRateChanges);
                if(host>lastHost&&rate==lastRate){
                    const long double spacing=static_cast<long double>(host-lastHost)*1e9L/rate;
                    const long double expected=static_cast<long double>(lastFrames)*1e9L/sampleRate;
                    increment(measured.comparedCallbacks);
                    measured.maxIntervalNanoseconds=std::max(measured.maxIntervalNanoseconds,nanoseconds(spacing));
                    measured.maxExcessNanoseconds=std::max(measured.maxExcessNanoseconds,nanoseconds(spacing-expected));
                }
            }
            // Single-writer, bounded atomic stores only. Sequential consistency
            // gives the reader a coherent versioned snapshot without RT CAS,
            // locks, allocation or a retry loop on the output callback.
            sequence.store(++publication);
            epoch.store(measured.epoch);callbacks.store(measured.callbacks);comparedCallbacks.store(measured.comparedCallbacks);
            maxExcess.store(measured.maxExcessNanoseconds);maxInterval.store(measured.maxIntervalNanoseconds);baselineBuffer.store(measured.baselineBufferNanoseconds);
            nonIncreasing.store(measured.nonIncreasingTimestamps);rateChanges.store(measured.clockRateChanges);
            baselineFrames.store(measured.baselineFrames);inheritedAnchor.store(measured.inheritedAnchor);
            sequence.store(++publication);
        }
        // Never clear this anchor merely because the control thread requested
        // a new epoch. In particular, retain it through an engine stop/start.
        lastHost=host;lastFrames=frames;lastRate=rate;anchored=true;
    }
    bool read(LGOutputTiming *result)const {
        if(!result)return false;
        for(int attempt=0;attempt<4;attempt++){
            const auto before=sequence.load();if(before&1)continue;
            LGOutputTiming value{};value.epoch=epoch.load();value.callbacks=callbacks.load();value.comparedCallbacks=comparedCallbacks.load();
            value.maxExcessNanoseconds=maxExcess.load();value.maxIntervalNanoseconds=maxInterval.load();value.baselineBufferNanoseconds=baselineBuffer.load();
            value.nonIncreasingTimestamps=nonIncreasing.load();value.clockRateChanges=rateChanges.load();value.baselineFrames=baselineFrames.load();value.inheritedAnchor=inheritedAnchor.load();
            if(sequence.load()==before){*result=value;return true;}
        }
        return false;
    }
};
struct LGKernel {
    LGMIDIHub *renderHub=nullptr;uint64_t hostNow=0,outputState=0;
    OutputTimingMeter outputTiming;
    double sr; PerformanceFX fx;PerformanceRuntime performance;std::array<float,Buses> capturedGain{},capturedPan{};float capturedFilter=0,capturedDelay=0;std::atomic<float> filterTarget{0},delayTarget{0}; std::array<Snapshot,3> slots; int current=-1;
    std::array<MixSnapshot,3> mixSlots;std::atomic<uint64_t> mixSerial{0},mixPublished{0};uint64_t mixApplied=0,mixSelection=0;std::atomic<bool> panicRequest{false};
    std::array<Voice,MaxVoices> voices{};std::array<bool,256> sustain{};
    std::array<Retirement,MaxVoices*2> retirements{};
    int kitFrames;std::array<std::vector<float>,16> kit,kitV2;std::array<std::atomic<int>,Buses> presets;
    std::array<Input,256> input{}; std::atomic<unsigned> write{0},read{0}; std::atomic<int> overflow{0};
    std::atomic<int> countRequest{0},countRemaining{0}; int counting=0;
    std::atomic<int> command{0},seek{-1},playing{0},applied{-1},metro{0},tailOnEnd{0};
    // Ideas I5 · I10 · I56 · I57 · I59 (control thread writes, audio reads).
    std::atomic<float> metroGain{1};std::atomic<int> metroAccent{1},metroSound{0};
    std::array<std::array<std::atomic<int>,16>,MaxTracks> choke{};std::array<std::atomic<float>,MaxTracks> sidechainDepth{},drive{};std::array<std::atomic<int>,MaxTracks> crush{};
    std::atomic<int> limiterOn{0};std::atomic<float> limiterCeiling{0.891f};
    float scEnv=0;int scHold=0;
    std::array<std::atomic<float>,MaxTracks> reverbSend{};SendReverb reverb;
    std::atomic<int> repeatPad{-1},repeatStep{240},repeatVelocity{100};std::atomic<uint32_t> repeatSerial{0};uint32_t repeatSeen=0;double repeatNextTick=-1,repeatFrames=0;
    void repeatTick(){
        const int pad=repeatPad.load(std::memory_order_acquire);
        if(pad<0)return;
        const uint32_t serial=repeatSerial.load(std::memory_order_acquire);
        const int step=repeatStep.load(std::memory_order_relaxed);
        bool fire=false;
        if(active&&current>=0){
            const double tick=position.load(std::memory_order_relaxed),half=0.5*ticksPerFrame();
            if(serial!=repeatSeen||tick+step<repeatNextTick){repeatSeen=serial;repeatNextTick=std::floor((tick+half)/step+1)*step;}
            if(tick>=repeatNextTick-half){fire=true;repeatNextTick+=step;}
        }else{
            const double bpm=current>=0?slots[current].bpm:120,frames=step/960.0*60/bpm*sr;
            if(serial!=repeatSeen){repeatSeen=serial;repeatFrames=frames;}
            if(--repeatFrames<=0){fire=true;repeatFrames+=frames;}
        }
        if(!fire)return;
        const int track=roleTrack(1,1);if(track<0)return;
        const int velocity=repeatVelocity.load(std::memory_order_relaxed);
        performance.emit(8,track,float(velocity),pad,1);trigger(36,velocity,track,pad,1,1);
    }
    static constexpr int LimiterMax=256;
    std::array<float,LimiterMax> limL{},limR{},limReq{},limGain{};int limPos=0,limLength=0;float limG1=1,limCoef=0;double limSum=0;bool limWasOn=false;
    void click(bool downbeat){
        static constexpr int pitches[3][2]={{96,84},{103,91},{84,72}};
        const int sound=std::clamp(metroSound.load(std::memory_order_relaxed),0,2);
        const bool accent=downbeat&&metroAccent.load(std::memory_order_relaxed)!=0;
        const int velocity=std::clamp(int(std::lround(65*metroGain.load(std::memory_order_relaxed))),1,127);
        trigger(pitches[sound][accent?0:1],velocity,Master,-1,0,0.035);
    }
    void dynamics(float *buses){
        // Sidechain envelope: 10 ms attack hold after each kick, ~120 ms release.
        if(scHold>0){scEnv+=(1-scEnv)*float(1-std::exp(-1/(sr*0.002)));--scHold;}else if(scEnv>0){scEnv*=float(std::exp(-1/(sr*0.12)));if(scEnv<1e-5f)scEnv=0;}
        for(int t=0;t<MaxTracks;t++){
            const float depth=sidechainDepth[t].load(std::memory_order_relaxed);
            if(depth>0&&scEnv>0)buses[t]*=1-(1-std::pow(10.f,-depth/20))*scEnv;
            const float amount=drive[t].load(std::memory_order_relaxed);
            if(amount>0){const float g=1+9*amount;buses[t]=std::tanh(g*buses[t])/g*(1+amount);}
            const int bits=crush[t].load(std::memory_order_relaxed);
            if(bits>0){const float steps=float(1<<(bits-1));buses[t]=std::round(buses[t]*steps)/steps;}
        }
    }
    bool limit(float &left,float &right){
        // Look-ahead peak limiter. The delay line is always written, so the
        // disabled path returns the input untouched (bit-identical). Enabled:
        // the required gain is held at its minimum over the look-ahead window,
        // released over ~80 ms and box-averaged over the same window. Each
        // averaged gain is at most the gain the delayed sample needs, and the
        // final min() makes that exact despite rounding.
        if(limLength==0){limLength=std::clamp(int(std::lround(sr*0.0015)),8,LimiterMax-2);limReq.fill(1);limGain.fill(1);limSum=limLength+1;limCoef=float(1-std::exp(-1/(sr*0.08)));}
        const float ceiling=limiterCeiling.load(std::memory_order_relaxed);
        const float peak=std::max(std::abs(left),std::abs(right));
        limPos=(limPos+1)%LimiterMax;
        limL[limPos]=left;limR[limPos]=right;limReq[limPos]=peak>ceiling?ceiling/peak:1.f;
        if(limiterOn.load(std::memory_order_relaxed)==0){
            if(limWasOn){limGain.fill(1);limSum=limLength+1;limG1=1;limWasOn=false;}
            return false;
        }
        limWasOn=true;
        float hold=1;for(int i=0;i<=limLength;i++)hold=std::min(hold,limReq[(limPos-i+LimiterMax)%LimiterMax]);
        limG1=std::min(hold,limG1+(1-limG1)*limCoef);
        const int oldest=(limPos-limLength-1+LimiterMax)%LimiterMax,out=(limPos-limLength+LimiterMax)%LimiterMax;
        limSum+=double(limG1)-double(limGain[oldest]);limGain[limPos]=limG1;
        const float gain=std::min(float(limSum/double(limLength+1)),limReq[out]);
        left=limL[out]*gain;right=limR[out]*gain;
        return true;
    }

    std::atomic<double> position{0}; std::atomic<uint64_t> clock{0};
    std::array<std::atomic<float>,Buses> gains, pans, meters; std::array<float,Buses> smooth{}, smoothPan{};std::array<float,MaxTracks> panValue{},panLeft{},panRight{};
    bool active=false,pendingInitialPlay=false; double origin=0; uint64_t elapsed=0,rendered=0; double previous=-1; long long cycle=0; int cursor=0; int lastBeat=-1;
    uint64_t trackLayoutToken=0;std::array<uint64_t,MaxTracks> trackLayoutKeys{};int trackLayoutCount=0;float lastLeft=0,lastRight=0,layoutFadeLeft=0,layoutFadeRight=0;int layoutFadeRemaining=0,layoutFadeTotal=1;
    explicit LGKernel(double rate):sr(rate),fx(rate),kitFrames(int(std::ceil(rate))),reverb(rate) {
        panValue.fill(std::numeric_limits<float>::quiet_NaN());
        for(int i=0;i<Buses;i++){presets[i].store(1);gains[i].store(i==Master?0.708f:0.5f);pans[i].store(0);meters[i].store(0);smooth[i]=gains[i].load(); }
        auto generate=[&](std::array<std::vector<float>,16>&bank,int frames){
        uint32_t noise=0x4c47524c;
        for(int pad=0;pad<16;pad++) {
            bank[pad].resize(frames);
            double low=0;
            for(int f=0;f<frames;f++) {
                double t=f/sr; noise^=noise<<13;noise^=noise>>17;noise^=noise<<5; double n=double(noise)/2147483648.0-1;
                double x=0;
                if(pad==0) x=std::sin(2*Pi*(48*t+7*(1-std::exp(-t*35))))*std::exp(-t*12);
                else if(pad==1||pad==4||pad==5) x=(n*0.72+std::sin(2*Pi*(pad==5?420:185)*t)*0.28)*std::exp(-t*(pad==5?55:18));
                else if(pad==2||pad==3||pad==9||pad==10||pad==11||pad==14) {low+=0.18*(n-low);x=(n-low)*std::exp(-t*(pad==3?9:pad==9?4:pad==2?65:22));}
                else x=(std::sin(2*Pi*(95+(pad-6)*44)*t)+0.18*n)*std::exp(-t*(pad==12?20:12));
                bank[pad][f]=float(x*0.5*std::min(1.0,t*2000));
            }
        }
        };generate(kit,LegacyKitFrames);if(kitFrames!=LegacyKitFrames)generate(kitV2,kitFrames);
    }
    void endOutput(Voice &v){if(renderHub&&v.outputChannel>=0&&v.outputEpoch==uint32_t(outputState>>33))renderHub->outputOff(outputState,hostNow,v.outputChannel,v.outputPitch);v.outputChannel=-1;}
    void startOutput(Voice &v){if(!renderHub||!v.outputAllowed)return;const auto remainingFrames=uint64_t(std::max(0.0,std::round((v.duration-v.age)*sr)));if(remainingFrames==0)return;constexpr int map[16]={36,38,42,46,39,37,45,47,50,49,51,54,56,75,70,82};v.outputPitch=v.pad>=0?map[v.pad]:v.pitch;v.outputEpoch=uint32_t(outputState>>33);v.outputEndFrame=rendered+remainingFrames;v.outputChannel=renderHub->outputOn(outputState,hostNow,v.track,v.outputPitch,int(v.velocity*127+0.5f));}
    void retire(const Voice &v){
        if(!v.on||(!v.sample&&v.presetVersion<2)||v.lastSample==0)return;
        auto *tail=&*std::min_element(retirements.begin(),retirements.end(),[](const auto &a,const auto &b){return std::abs(a.sample)*a.remaining/a.total<std::abs(b.sample)*b.remaining/b.total;});
        const int count=std::max(1,int(std::ceil(sr*0.003)));*tail={v.lastSample,v.track,count,count};
    }
    void silence(bool all=false){for(auto &v:voices)if(all||v.sourceKey<0){if(!all)retire(v);endOutput(v);v.on=false;}if(all){sustain.fill(false);for(auto &tail:retirements)tail.remaining=0;layoutFadeRemaining=0;}}
    Voice *trigger(int pitch,int velocity,int track,int pad,int instrument,double duration,bool output=true){
        if(pad==2)for(auto &v:voices)if(v.on&&v.pad==3){if(v.presetVersion>=2){retire(v);endOutput(v);v.on=false;}else{v.duration=std::min(v.duration,v.age+0.004);}}
        if(pad>=0&&track>=0&&track<MaxTracks){
            const int group=choke[track][pad].load(std::memory_order_relaxed);
            if(group>0)for(auto &v:voices)if(v.on&&v.track==track&&v.pad>=0&&v.pad!=pad&&choke[track][v.pad].load(std::memory_order_relaxed)==group){retire(v);endOutput(v);v.on=false;}
            if(pad==0)scHold=std::max(1,int(sr*0.01));
        }
        Voice *v=nullptr; for(auto &x:voices)if(!x.on){v=&x;break;}
        if(!v) v=&*std::min_element(voices.begin(),voices.end(),[](auto&a,auto&b){return a.level<b.level;});
        retire(*v);endOutput(*v);*v=Voice{true,pitch,track,pad,instrument,0,0,duration,float(velocity/127.0),0};v->outputAllowed=output;v->presetVersion=presets[track].load(std::memory_order_relaxed);
        v->phaseStep=440*std::pow(2.,(pitch-69)/12.)/sr;
        if(v->presetVersion>=2){if(pad>=0)v->duration=kitFrames/sr;v->decayStep=std::exp(-(instrument==2?1.5:0.7)/sr);}
        if(v->presetVersion>=3){
            const bool warm=v->presetVersion==3;
            if(pad>=0){
                // Derive each kit from the existing rate-correct bank. Per-voice
                // pitch and tone state need no extra sample banks or RT memory.
                v->playbackRatio=warm?0.92:1.10;
                v->duration=std::ceil(kitFrames/v->playbackRatio)/sr;
                const double cutoff=pad==0?900:(pad==2||pad==3?4800:2600);
                v->toneAlpha=1-std::exp(-2*Pi*std::min(sr*0.4,cutoff)/sr);
                if(!warm)v->attack=0.002;
            }else{
                const double second=warm?(instrument==2?0.06:0.10):(instrument==3?0.48:0.38);
                const double third=warm?0:(instrument==2?0.16:0.22);
                const std::array<double,4> weights={1,second,third,warm?0:0.08};
                for(int harmonic=1;harmonic<=4;harmonic++)v->partials[harmonic-1]=weights[harmonic-1]*std::clamp((0.49-v->phaseStep*harmonic)/0.04,0.0,1.0);
                v->attack=warm?0.006:0.0025;
                const double decay=warm?(instrument==2?0.9:0.45):(instrument==2?1.7:1.1);
                v->decayStep=std::exp(-decay/sr);
            }
        }
        if(current>=0){
            v->sample=slots[current].sampleAt(track,pad);
            if(v->sample){
                v->zone=v->sample->nearest[pad>=0?0:pitch];
                v->playbackRatio=double(v->sample->rate)/sr;
                if(pad>=0)v->duration=double(v->zone.frames)/v->sample->rate;
                else {
                    v->playbackRatio*=std::exp2(double(pitch-v->zone.pitch)/12);
                    if(v->sample->ringsOut)v->duration=std::min(8.,double(v->zone.frames)/(sr*v->playbackRatio));
                }
            }
        }
        startOutput(*v);return v;
    }
    void midiClear(int source,bool capture=true){
        for(auto &v:voices)if(v.on&&v.sourceKey>=0&&v.sourceKey/16==source){endOutput(v);v.duration=std::min(v.duration,v.age+0.008);}
        for(int channel=0;channel<16;channel++)sustain[source*16+channel]=false;
        if(capture)performance.emit(13,-1,0,0,source);
    }
    void midiEvent(const LGMIDIEvent &e,bool capture=true){
        const int key=e.source*16+e.channel;
        if(e.status==9){
            if(e.instrument==1){
                constexpr int map[16]={36,38,42,46,39,37,45,47,50,49,51,54,56,75,70,82};int pad=-1;
                for(int i=0;i<16;i++)if(map[i]==e.a){pad=i;break;}
                if(pad>=0){trigger(36,e.b,e.track,pad,1,1,!capture);if(capture)performance.emit(8,e.track,float(e.b),pad);}return;
            }
            for(auto &v:voices)if(v.on&&v.sourceKey==key&&v.pitch==e.a){endOutput(v);v.duration=std::min(v.duration,v.age+0.008);}
            auto *voice=trigger(e.a,e.b,e.track,-1,e.instrument,1e9,!capture);voice->sourceKey=key;voice->keyDown=true;
            if(capture)performance.emit(10,e.track,float(e.b),e.a,key,e.instrument);
        }else if(e.status==8){
            if(e.instrument==1)return;
            for(auto &v:voices)if(v.on&&v.sourceKey==key&&v.pitch==e.a){v.keyDown=false;if(!sustain[key]){endOutput(v);v.duration=std::min(v.duration,v.age+0.008);}}
            if(capture)performance.emit(11,e.track,0,e.a,key,e.instrument);
        }else if(e.status==11&&e.a==64){
            sustain[key]=e.b>=64;if(!sustain[key])for(auto &v:voices)if(v.on&&v.sourceKey==key&&!v.keyDown){endOutput(v);v.duration=std::min(v.duration,v.age+0.008);}
            if(capture)performance.emit(12,-1,sustain[key]?1.f:0.f,0,key);
        }else if(e.status==11&&(e.a==120||e.a==123)){midiClear(e.source,capture);}
    }
    int roleTrack(int instrument,int fallback) const {
        if(current>=0&&slots[current].hasProjectMix){const auto &s=slots[current];for(int i=0;i<s.trackCount;i++)if(s.instruments[i]==instrument)return i;return -1;}
        return fallback;
    }
    int identityTrack(uint64_t identity)const {
        if(current>=0&&slots[current].hasProjectMix){const auto &s=slots[current];for(int i=0;i<s.trackCount;i++)if(s.trackKeys[i]==identity)return i;}
        return -1;
    }
    double ticksPerFrame() { return current<0?0:slots[current].bpm*960/(60*sr); }
    void resetCursor(double tick){cursor=0;cycle=0;origin=tick;elapsed=0;previous=tick-1;lastBeat=-1;silence();
        if(current<0) return;
        auto&s=slots[current];
        while(cursor<s.count&&s.notes[cursor].tick<tick){auto&n=s.notes[cursor];if(active&&n.pad<0&&n.tick+n.duration>tick)trigger(n.pitch,n.velocity,n.track,-1,n.instrument,(std::min(n.tick+n.duration,s.end)-tick)/960*60/s.bpm);cursor++;}
    }
    bool performAction(PerformanceControl control){
        if(current<0){return false;}auto &s=slots[current];
        if(control.kind==1){s.start=control.a;s.end=control.b;s.loop=true;resetCursor(s.start);position.store(s.start);return true;}
        if(control.kind==2){double tick=origin+elapsed*ticksPerFrame()-cycle*(s.end-s.start);double target=s.start+std::fmod(std::fmod(tick-s.start+control.value*960,s.end-s.start)+(s.end-s.start),s.end-s.start);resetCursor(target);position.store(target);return true;}
        if(control.kind==3){if(control.value==0){bool was=fx.repeating();fx.releaseRepeat();return was;}return fx.beginRepeat(int(control.value),s.bpm);}
        return false;
    }
    std::array<EQChannel,10> eqChannels{};
    void applyEQ(const EQDesk& desk,bool reset=false){
        const int frames=std::max(1,int(sr*0.008));
        for(int i=0;i<10;i++)eqChannels[i].set(desk[std::min(i,Master)],frames,reset);
    }
    void adoptMix(){
        int chosen=-1;uint64_t best=mixSelection;const int musical=current<0?-1:slots[current].revision.load(std::memory_order_relaxed);
        for(int i=0;i<3;i++)if(mixSlots[i].state.load(std::memory_order_acquire)==2){
            // Claim before reading the non-atomic payload; a producer may replace
            // a ready slot. Future transactions remain ready for music adoption.
            int ready=2;if(!mixSlots[i].state.compare_exchange_strong(ready,3,std::memory_order_acq_rel))continue;
            const auto revision=mixSlots[i].revision.load(std::memory_order_relaxed);const int target=mixSlots[i].musicRevision;
            if(target>=0&&target<musical){mixSlots[i].state.store(0,std::memory_order_release);continue;}
            if(target>=0&&target!=musical){mixSlots[i].state.store(2,std::memory_order_release);continue;}
            if(revision<=mixSelection){mixSlots[i].state.store(0,std::memory_order_release);continue;}
            if(revision>best){if(chosen>=0)mixSlots[chosen].state.store(0,std::memory_order_release);best=revision;chosen=i;}
            else mixSlots[i].state.store(0,std::memory_order_release);
        }
        if(chosen<0){return;}auto &slot=mixSlots[chosen];
        const auto revision=slot.revision.load(std::memory_order_relaxed);
        if(revision>mixSelection){applyEQ(slot.eq);for(int t=0;t<Buses;t++){gains[t].store(slot.gain[t]);pans[t].store(slot.pan[t]);}filterTarget.store(slot.filter);delayTarget.store(slot.delay);mixSelection=revision;mixApplied=std::max(mixApplied,revision);mixPublished.store(mixApplied,std::memory_order_release);}
        slot.state.store(0,std::memory_order_release);
    }
    void adopt(bool force,double tick){
        int chosen=-1,best=applied.load(std::memory_order_relaxed);
        for(int i=0;i<3;i++)if(slots[i].state.load(std::memory_order_acquire)==2){int rev=slots[i].revision.load();if(rev>=best){best=rev;chosen=i;}}
        if(chosen<0)return;
        // Match note scheduling's nearest-sample boundary rule. At 44.1 kHz the
        // exact bar can be represented as 3839.9999999999995; truncating that
        // value otherwise defers a project by one sample.
        const double halfSample=0.5*ticksPerFrame();
        if(!force && current>=0 && int((tick+halfSample)/3840)==int((std::max(0.0,previous)+halfSample)/3840))return;
        int ready=2;if(!slots[chosen].state.compare_exchange_strong(ready,3,std::memory_order_acq_rel))return;
        // A control producer may have replaced this ready slot after the scan.
        // Recheck the claimed generation before releasing the current project.
        if(slots[chosen].revision.load(std::memory_order_relaxed)<applied.load(std::memory_order_relaxed)){slots[chosen].state.store(0,std::memory_order_release);return;}
        if(current>=0){
            auto &previousSlot=slots[current];const auto &nextSlot=slots[chosen];
            // Voices borrow their PCM from the current claimed snapshot. Stop
            // changed routes before a control thread can reclaim that slot.
            // Identical routes keep ringing and remain owned by the next slot.
            if(previousSlot.sampleInstruments!=nextSlot.sampleInstruments||previousSlot.samplePads!=nextSlot.samplePads){
                for(auto &voice:voices)if(voice.on&&previousSlot.sampleAt(voice.track,voice.pad)!=nextSlot.sampleAt(voice.track,voice.pad)){
                    retire(voice);endOutput(voice);voice.on=false;voice.sample=nullptr;
                }
            }
            previousSlot.state.store(0,std::memory_order_release);
        }
        // A future project's control can predate the last old-project control.
        // Its ordering floor is local to this music generation, while the
        // public publication high-water mark remains monotonic.
        current=chosen;auto&s=slots[current];mixSelection=0;
        if(!s.hasProjectMix)applyEQ(s.eq);
        if(s.hasProjectMix){
            const bool changed=s.layoutToken!=trackLayoutToken||s.trackCount!=trackLayoutCount||s.trackKeys!=trackLayoutKeys;
            if(changed){
                const bool fade=active;const float oldLeft=lastLeft,oldRight=lastRight;
                // A held MIDI note belongs to its old track index. Clear it and
                // sustain rather than silently moving it onto a different track.
                silence(true);
                if(fx.repeating())performance.emit(3,-1,0);
                fx.resetTrackHistory();performance.repeatTicks.store(0);
                if(fade){layoutFadeLeft=oldLeft;layoutFadeRight=oldRight;layoutFadeTotal=std::max(1,int(std::ceil(sr*0.003)));layoutFadeRemaining=layoutFadeTotal;}
            }
            applyEQ(s.eq,changed);
            for(int t=0;t<Buses;t++){gains[t].store(s.gain[t]);pans[t].store(s.pan[t]);if(changed){smooth[t]=s.gain[t];smoothPan[t]=s.pan[t];}}
            for(int t=0;t<MaxTracks;t++)presets[t].store(s.preset[t],std::memory_order_relaxed);
            filterTarget.store(s.filter);delayTarget.store(s.delay);mixSelection=s.mixSequence;mixApplied=std::max(mixApplied,s.mixSequence);mixPublished.store(mixApplied,std::memory_order_release);
            adoptMix();
            if(renderHub){
                renderHub->adoptLayout(trackLayoutKeys.data(),trackLayoutCount,s.trackKeys.data(),s.instruments.data(),s.midiChannels.data(),s.trackCount,[&](int source){midiClear(source);});
                const auto next=renderHub->outputConfiguration();
                if((next>>32)!=(outputState>>32)){renderHub->resetOutputRefs();for(auto &voice:voices)voice.outputChannel=-1;}
                outputState=next;
            }
            trackLayoutToken=s.layoutToken;trackLayoutKeys=s.trackKeys;trackLayoutCount=s.trackCount;
        }
        resetCursor(tick>=s.start && tick<s.end ? tick : s.start);
        applied.store(s.revision.load(std::memory_order_relaxed),std::memory_order_release);
    }
};
static bool validNotes(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end){
    if(!k||(count>0&&!notes)||count<0||count>MaxNotes||!std::isfinite(bpm)||bpm<40||bpm>240||start<0||end<=start||end>245760)return false;
    for(int n=0;n<count;n++)if(notes[n].tick<0||notes[n].duration<=0||notes[n].duration>245760||notes[n].tick>245760-notes[n].duration||notes[n].pitch<0||notes[n].pitch>127||notes[n].track<0||notes[n].track>=MaxTracks||notes[n].pad < -1||notes[n].pad>15||notes[n].instrument<0||notes[n].instrument>3||notes[n].velocity<1||notes[n].velocity>127)return false;
    return true;
}
static bool validMix(LGKernel*k,const LGTrackMix*tracks,int count,float masterDB,float filter,float delay){
    if(!k||count<0||count>MaxTracks||(count>0&&!tracks)||!std::isfinite(masterDB)||masterDB< -61||masterDB>6||!std::isfinite(filter)||filter< -1||filter>1||!std::isfinite(delay)||delay<0||delay>0.5)return false;
    for(int i=0;i<count;i++)if(!std::isfinite(tracks[i].gainDB)||tracks[i].gainDB< -61||tracks[i].gainDB>6||!std::isfinite(tracks[i].pan)||tracks[i].pan< -1||tracks[i].pan>1||tracks[i].audible<0||tracks[i].audible>1)return false;
    return true;
}
static float mixGain(float db,int audible=1){return audible&&db> -61?std::pow(10.f,std::clamp(db,-60.f,6.f)/20):0;}
static int submitSnapshot(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev,uint64_t layoutToken,const LGProjectTrack*tracks,int trackCount,float masterDB,float filter,float delay,bool project,LGSampleBank *const *instruments=nullptr,LGSampleBank *const *pads=nullptr,const LGEQBand *eq=nullptr){
    if(!validNotes(k,notes,count,bpm,start,end)||(project&&(loop<0||loop>1)))return 0;
    if(project){
        if(rev<0||rev<k->applied.load(std::memory_order_acquire)||layoutToken==0||trackCount<0||trackCount>MaxTracks||(trackCount>0&&!tracks)||!validMix(k,nullptr,0,masterDB,filter,delay))return 0;
        for(int i=0;i<trackCount;i++){
            const auto &track=tracks[i];if(!validMix(k,&track.mix,1,masterDB,filter,delay)||track.presetVersion<1||track.presetVersion>4||track.instrument<0||track.instrument>3||track.midiChannel<0||track.midiChannel>15||track.identity==0)return 0;
            for(int j=0;j<i;j++)if(tracks[j].identity==track.identity)return 0;
        }
        for(int n=0;n<count;n++)if(notes[n].track>=trackCount)return 0;
    }
    EQDesk desk{}; if(!eqPrepare(eq,k->sr,desk))return 0;
    for(auto&s:k->slots){int expected=0;if(!s.state.compare_exchange_strong(expected,1)){expected=2;if(!s.state.compare_exchange_strong(expected,1))continue;}
        if(count>0){std::copy(notes,notes+count,s.notes.begin());}s.count=count;s.bpm=bpm;s.start=start;s.end=end;s.loop=loop;s.hasProjectMix=project;s.eq=desk;
        replaceBanks(s.sampleInstruments,instruments);replaceBanks(s.samplePads,pads);
        if(project){
            s.gain.fill(0);s.pan.fill(0);s.preset.fill(1);s.trackKeys.fill(0);s.instruments.fill(0);s.midiChannels.fill(0);s.trackCount=trackCount;
            for(int t=0;t<trackCount;t++){s.gain[t]=mixGain(tracks[t].mix.gainDB,tracks[t].mix.audible);s.pan[t]=tracks[t].mix.pan;s.preset[t]=tracks[t].presetVersion;s.trackKeys[t]=tracks[t].identity;s.instruments[t]=tracks[t].instrument;s.midiChannels[t]=tracks[t].midiChannel;}
            s.gain[Master]=mixGain(masterDB);s.filter=filter;s.delay=delay;s.layoutToken=layoutToken;s.mixSequence=k->mixSerial.fetch_add(1)+1;
        }
        std::sort(s.notes.begin(),s.notes.begin()+count,[](auto&a,auto&b){return a.tick<b.tick;});
        s.revision.store(rev);s.state.store(2,std::memory_order_release);return 1;
    }return 0;
}
static int publishMix(LGKernel*k,const LGTrackMix*tracks,int count,float masterDB,float filter,float delay,int musicRevision,const LGEQBand *eq=nullptr){
    if(!validMix(k,tracks,count,masterDB,filter,delay))return 0;
    EQDesk desk{}; if(!eqPrepare(eq,k->sr,desk))return 0;
    // Keep a pending generation's controls when a current-generation update
    // arrives: use empty storage before replacing an unconsumed transaction.
    for(int pass=0;pass<3;pass++)for(auto &slot:k->mixSlots){
        // The serialized producer is the only payload writer, so inspecting
        // the target here is safe; rendering only changes ownership flags.
        if(pass==1&&slot.musicRevision!=musicRevision)continue;
        int expected=pass==0?0:2;if(!slot.state.compare_exchange_strong(expected,1))continue;
        slot.eq=desk;slot.gain.fill(0);slot.pan.fill(0);
        for(int i=0;i<count;i++){slot.gain[i]=mixGain(tracks[i].gainDB,tracks[i].audible);slot.pan[i]=tracks[i].pan;}
        slot.gain[Master]=mixGain(masterDB);slot.filter=filter;slot.delay=delay;slot.musicRevision=musicRevision;
        slot.revision.store(k->mixSerial.fetch_add(1)+1);slot.state.store(2,std::memory_order_release);return 1;
    }return 0;
}
extern "C" {
double lg_eq_response(const LGEQBand* b,double rate,double frequency){
    if(!b||!(rate>=8000)||frequency<=0)return 0;
    const auto z=std::polar(1.0,-2*Pi*frequency/rate);double db=0;
    for(int i=0;i<4;i++){
        const auto c=eqDesign(b[i],rate);
        db+=20*std::log10(std::max(1e-10,std::abs((c.b0+c.b1*z+c.b2*z*z)/(1.+c.a1*z+c.a2*z*z))));
    }
    return db;
}
int lg_submit_project_eq(LGKernel*k,const LGNote*n,int count,double bpm,int start,int end,int loop,int rev,uint64_t token,const LGProjectTrack*t,int tc,float master,float filter,float delay,LGSampleBank *const *in,LGSampleBank *const *pads,const LGEQBand* eq){
    return submitSnapshot(k,n,count,bpm,start,end,loop,rev,token,t,tc,master,filter,delay,true,in,pads,eq);
}
int lg_submit_samples_eq(LGKernel*k,const LGNote*n,int count,double bpm,int start,int end,int loop,int rev,LGSampleBank *const *in,LGSampleBank *const *pads,const LGEQBand* eq){
    return submitSnapshot(k,n,count,bpm,start,end,loop,rev,0,nullptr,0,0,0,0,false,in,pads,eq);
}
int lg_mix_revision_eq(LGKernel*k,const LGTrackMix*t,int count,float master,float filter,float delay,int rev,const LGEQBand* eq){
    return rev<0?0:publishMix(k,t,count,master,filter,delay,rev,eq);
}
LGSampleBank *lg_sample_create(int32_t rate,const LGSampleZone *zones,int32_t count,const int16_t *pcm,int32_t frames){
    return lg_sample_create_with_release(rate,zones,count,pcm,frames,0);
}
LGSampleBank *lg_sample_create_with_release(int32_t rate,const LGSampleZone *zones,int32_t count,const int16_t *pcm,int32_t frames,int32_t ringsOut){
    if(rate<8000||rate>48000||count<1||count>128||frames<32||frames>3999000||!zones||!pcm)return nullptr;
    int previous=-1;
    for(int i=0;i<count;i++){
        const auto &zone=zones[i];
        if((ringsOut && zone.loopStart!=0)||zone.pitch<=previous||zone.pitch>127||zone.offset<0||zone.frames<32||zone.frames>rate*8||
           zone.frames>frames||zone.offset>frames-zone.frames||zone.loopStart<0||
           (zone.loopStart&&(zone.frames<1025||zone.loopStart>zone.frames-1024)))return nullptr;
        previous=zone.pitch;
    }
    try{
        auto pcmCopy=std::vector<int16_t>(pcm,pcm+frames);
        auto *bank=new LGSampleBank;
        bank->rate=rate;bank->ringsOut=ringsOut!=0;bank->pcm=std::move(pcmCopy);
        int nearest=0;
        for(int pitch=0;pitch<128;pitch++){
            while(nearest+1<count&&std::abs(zones[nearest+1].pitch-pitch)<std::abs(zones[nearest].pitch-pitch))nearest++;
            bank->nearest[pitch]=zones[nearest];
        }
        return bank;
    }catch(...){return nullptr;}
}
void lg_sample_release(LGSampleBank *bank){if(bank&&bank->references.fetch_sub(1,std::memory_order_acq_rel)==1)delete bank;}
LGKernel*lg_create(double sr){
    if(!std::isfinite(sr)||sr<8000||sr>192000)return nullptr;
    // Swift callers treat a null result as a recoverable preparation failure.
    // Catch the whole constructor: nothrow new alone does not cover allocations
    // made by the DSP's vector members during construction.
    try{return new LGKernel(sr);}catch(...){return nullptr;}
}
void lg_destroy(LGKernel*k){delete k;}
int lg_submit(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev){
    return submitSnapshot(k,notes,count,bpm,start,end,loop,rev,0,nullptr,0,0,0,0,false);
}
int lg_submit_project(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev,uint64_t layoutToken,const LGProjectTrack*tracks,int trackCount,float masterDB,float filter,float delay){return submitSnapshot(k,notes,count,bpm,start,end,loop,rev,layoutToken,tracks,trackCount,masterDB,filter,delay,true);}
int lg_submit_project_samples(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev,uint64_t layoutToken,const LGProjectTrack*tracks,int trackCount,float masterDB,float filter,float delay,LGSampleBank *const *instruments,LGSampleBank *const *pads){return submitSnapshot(k,notes,count,bpm,start,end,loop,rev,layoutToken,tracks,trackCount,masterDB,filter,delay,true,instruments,pads);}
int lg_submit_samples(LGKernel*k,const LGNote*notes,int count,double bpm,int start,int end,int loop,int rev,LGSampleBank *const *instruments,LGSampleBank *const *pads){return submitSnapshot(k,notes,count,bpm,start,end,loop,rev,0,nullptr,0,0,0,0,false,instruments,pads);}
int lg_snapshot_generations(LGKernel*k,int32_t*revisions,int capacity){
    if(!k||!revisions||capacity<1)return 0;
    int count=0;
    // The serialized producer cannot replace slot payloads during this call.
    // Adoption changes ownership flags, but never these atomic revision IDs.
    // Include free slots too: a handover during the read cannot hide a layout.
    for(const auto &slot:k->slots){const int revision=slot.revision.load(std::memory_order_acquire);if(revision<0)continue;bool seen=false;for(int i=0;i<count;i++)if(revisions[i]==revision)seen=true;if(!seen&&count<capacity)revisions[count++]=revision;}
    return count;
}
void lg_countin(LGKernel*k,int frames){k->countRequest.store(frames);}
int lg_countremaining(LGKernel*k){return k->countRemaining.load();}
void lg_play(LGKernel*k,int play){k->command.store(play?1:-1,std::memory_order_release);}
void lg_restart(LGKernel*k){k->command.store(2,std::memory_order_release);}
void lg_seek(LGKernel*k,int tick){if(tick>=0)k->seek.store(std::min(245760,tick));}
static int enqueue(LGKernel*k,Input value){unsigned w=k->write.load(std::memory_order_relaxed),r=k->read.load(std::memory_order_acquire);if(w-r>=256){k->overflow.fetch_add(1);return 0;}k->input[w%256]=value;k->write.store(w+1,std::memory_order_release);return 1;}
int lg_pad_repeat(LGKernel*k,int pad,int step,int velocity){
    if(!k||pad< -1||pad>15)return 0;
    if(pad<0){k->repeatPad.store(-1,std::memory_order_release);return 1;}
    if(step!=120&&step!=160&&step!=240&&step!=320&&step!=480)return 0;
    k->repeatStep.store(step,std::memory_order_relaxed);k->repeatVelocity.store(std::clamp(velocity,1,127),std::memory_order_relaxed);
    k->repeatSerial.fetch_add(1,std::memory_order_acq_rel);k->repeatPad.store(pad,std::memory_order_release);return 1;
}
int lg_pad(LGKernel*k,int pad,int velocity){if(pad<0||pad>15)return 0;return enqueue(k,{pad,std::clamp(velocity,1,127),1,1,false});}
void lg_note_preview(LGKernel*k,int pitch,int track,int instrument){if(pitch>=0&&pitch<=127&&track>=0&&track<MaxTracks&&instrument>=0&&instrument<=3)enqueue(k,{pitch,95,track,instrument,true});}
int lg_note_preview_track(LGKernel*k,int pitch,uint64_t identity){return k&&pitch>=0&&pitch<=127&&identity!=0?enqueue(k,{pitch,95,-1,0,true,identity}):0;}
void lg_preview(LGKernel*k,int pitch){if(pitch>=0&&pitch<=127)enqueue(k,{pitch,95,-1,0,true});}
void lg_mix(LGKernel*k,int t,float db,float pan,int audible){if(t<0||t>=MaxTracks||!std::isfinite(db)||!std::isfinite(pan))return;k->gains[t].store(audible&&db> -61?std::pow(10.f,std::clamp(db,-60.f,6.f)/20):0);k->pans[t].store(std::clamp(pan,-1.f,1.f));}
int lg_mix_snapshot(LGKernel*k,const LGTrackMix*tracks,int count,float masterDB,float filter,float delay){
    return publishMix(k,tracks,count,masterDB,filter,delay,-1);
}
int lg_mix_snapshot_for_revision(LGKernel*k,const LGTrackMix*tracks,int count,float masterDB,float filter,float delay,int revision){return revision<0?0:publishMix(k,tracks,count,masterDB,filter,delay,revision);}
uint64_t lg_mix_revision(LGKernel*k){return k->mixPublished.load(std::memory_order_acquire);}
int lg_preset_version(LGKernel*k,int track,int version){if(!k||track<0||track>=MaxTracks||version<1||version>4)return 0;k->presets[track].store(version,std::memory_order_release);return 1;}
void lg_master(LGKernel*k,float db){if(std::isfinite(db))k->gains[Master].store(db> -61?std::pow(10.f,std::clamp(db,-60.f,6.f)/20):0);}
void lg_effects(LGKernel*k,float filter,float delay){if(std::isfinite(filter)&&std::isfinite(delay)){k->filterTarget.store(std::clamp(filter,-1.f,1.f));k->delayTarget.store(std::clamp(delay,0.f,0.5f));}}
void lg_perform_begin(LGKernel*k,int token,int epoch,int recording,uint64_t limit){
    if(token<1||token>8||epoch<=0||(recording&&(limit==0||double(limit)>k->sr*384)))return;
    k->performance.requestToken.store(token);k->performance.requestEpoch.store(epoch);k->performance.requestCapture.store(recording?1:0);k->performance.requestLimit.store(limit);k->command.store(3,std::memory_order_release);
}
int lg_perform_replay_submit(LGKernel*k,const LGPerformanceEvent*events,int count,uint64_t duration,int epoch){
    if(!events||count<1||count>16384||duration==0||double(duration)>k->sr*384||epoch<=0||events[0].frame!=0||events[0].kind!=1)return 0;
    uint64_t previous=0;int sameFrame=0;
    for(int i=0;i<count;i++){
        const auto &e=events[i];if(e.frame<previous||e.frame>duration||!std::isfinite(e.value))return 0;
        sameFrame=e.frame==previous?sameFrame+1:1;if(sameFrame>512)return 0;previous=e.frame;
        if(e.kind==1){if(e.token<1||e.token>8||e.a<0||e.b<=e.a||e.b>245760||e.a%3840||e.b%3840)return 0;}
        else if(e.kind==2){if(e.value!=1&&e.value!=-1&&e.value!=4&&e.value!=-4)return 0;}
        else if(e.kind==3){if(e.value!=0&&e.value!=240&&e.value!=480&&e.value!=960&&e.value!=1920)return 0;}
        else if(e.kind==4){if(e.value < -1||e.value>1)return 0;}
        else if(e.kind==5){if(e.value<0||e.value>0.5)return 0;}
        else if(e.kind==6){if(e.track<0||e.track>8||e.value<0||e.value>2)return 0;}
        else if(e.kind==7){if(e.track<0||e.track>=8||e.value < -1||e.value>1)return 0;}
        else if(e.kind==8){if(e.a<0||e.a>15||e.value<1||e.value>127)return 0;}
        else if(e.kind==9){if(e.a<0||e.a>127||e.b<0||e.b>3||e.track<0||e.track>=8||e.value<1||e.value>127)return 0;}
        else if(e.kind==10||e.kind==11){if(e.track<0||e.track>=8||e.a<0||e.a>127||e.b<0||e.b>=256||e.token<0||e.token>3||e.value<0||e.value>127||(e.kind==10&&e.value<1))return 0;}
        else if(e.kind==12){if(e.b<0||e.b>=256||(e.value!=0&&e.value!=1))return 0;}
        else if(e.kind==13){if(e.b<0||e.b>=16)return 0;}
        else return 0;
    }
    return k->performance.submitReplay(events,count,duration,epoch);
}
uint64_t lg_perform_queue(LGKernel*k,int kind,float value,int start,int end,int token){
    if(!std::isfinite(value))return 0;
    if(kind==1){if(token<0||token>8||(token!=0&&(start<0||end<=start||end>245760||start%3840!=0||end%3840!=0)))return 0;}
    else if(kind==2){if(value!=1&&value!=-1&&value!=4&&value!=-4)return 0;}
    else if(kind==3){if(value!=0&&value!=240&&value!=480&&value!=960&&value!=1920)return 0;}
    else return 0;
    const uint64_t seq=k->performance.queue({kind,start,end,token,value});if(!seq)k->overflow.fetch_add(1);return seq;
}
uint64_t lg_perform_ack(LGKernel*k){return k->performance.ack();}
int lg_perform_pop(LGKernel*k,LGPerformanceEvent*events,int capacity){return k->performance.pop(events,capacity);}
void lg_perform_record_stop(LGKernel*k){k->performance.requestStop.store(1);}
int lg_perform_mode(LGKernel*k){return k->performance.mode.load();}
int lg_perform_recording(LGKernel*k){return k->performance.recording.load();}
int lg_perform_epoch(LGKernel*k){return k->performance.publishedEpoch.load();}
int lg_perform_active_token(LGKernel*k){return k->performance.activeToken.load();}
int lg_perform_pending_token(LGKernel*k){return k->performance.queuedToken.load();}
int lg_perform_repeat(LGKernel*k){return k->performance.repeatTicks.load();}
int lg_perform_error(LGKernel*k){return k->performance.error.load();}
int lg_perform_warning(LGKernel*k){return k->performance.warning.load();}
uint64_t lg_perform_clock(LGKernel*k){return k->performance.clock.load();}
uint64_t lg_perform_duration(LGKernel*k){return k->performance.duration.load();}
// The caller must stop/join its render engine before finalizing a paused kernel.
void lg_perform_finalize_paused(LGKernel*k){k->performance.stop();k->performance.publish();k->active=false;k->pendingInitialPlay=false;k->playing.store(0);k->silence(true);k->fx.reset();k->reverb.reset();}
float lg_gain_target(LGKernel*k,int t){return t>=0&&t<Buses?k->gains[t].load():0;}
float lg_pan_target(LGKernel*k,int t){return t>=0&&t<Buses?k->pans[t].load():0;}
float lg_filter_target(LGKernel*k){return k->filterTarget.load();}
float lg_delay_target(LGKernel*k){return k->delayTarget.load();}
void lg_panic(LGKernel*k){k->panicRequest.store(true,std::memory_order_release);k->command.store(-1);}
void lg_tail_on_end(LGKernel*k,int enabled){k->tailOnEnd.store(enabled);}
void lg_metronome(LGKernel*k,int on){k->metro.store(on);}
int lg_metronome_config(LGKernel*k,float gainDB,int accent,int sound){
    if(!k||!std::isfinite(gainDB)||gainDB< -24||gainDB>6||accent<0||accent>1||sound<0||sound>2)return 0;
    k->metroGain.store(std::pow(10.f,gainDB/20));k->metroAccent.store(accent);k->metroSound.store(sound);return 1;
}
int lg_dynamics(LGKernel*k,const LGTrackDynamics*tracks,int count,int limiter,float ceilingDB){
    if(!k||count<0||count>MaxTracks||(count>0&&!tracks)||limiter<0||limiter>1||!std::isfinite(ceilingDB)||ceilingDB< -12||ceilingDB> -0.2f)return 0;
    for(int t=0;t<count;t++){
        const auto &d=tracks[t];
        if(!std::isfinite(d.sidechainDB)||d.sidechainDB<0||d.sidechainDB>12||!std::isfinite(d.reverbSend)||d.reverbSend<0||d.reverbSend>1||!std::isfinite(d.drive)||d.drive<0||d.drive>1||(d.crushBits!=0&&(d.crushBits<4||d.crushBits>16)))return 0;
        for(int pad=0;pad<16;pad++)if(d.choke[pad]<0||d.choke[pad]>8)return 0;
    }
    for(int t=0;t<MaxTracks;t++){
        const bool set=t<count;
        for(int pad=0;pad<16;pad++)k->choke[t][pad].store(set?tracks[t].choke[pad]:0,std::memory_order_relaxed);
        k->sidechainDepth[t].store(set?tracks[t].sidechainDB:0,std::memory_order_relaxed);
        k->drive[t].store(set?tracks[t].drive:0,std::memory_order_relaxed);
        k->crush[t].store(set?tracks[t].crushBits:0,std::memory_order_relaxed);
        k->reverbSend[t].store(set?tracks[t].reverbSend:0,std::memory_order_relaxed);
    }
    k->limiterCeiling.store(std::pow(10.f,ceilingDB/20));k->limiterOn.store(limiter);return 1;
}
int lg_limiter_latency(LGKernel*k){return k&&k->limiterOn.load()?std::clamp(int(std::lround(k->sr*0.0015)),8,LGKernel::LimiterMax-2):0;}
uint64_t lg_output_timing_begin(LGKernel*k){if(!k)return 0;const uint64_t old=k->outputTiming.request.load(std::memory_order_relaxed);if(old==UINT64_MAX)return 0;k->outputTiming.request.store(old+1,std::memory_order_release);return old+1;}
int lg_output_timing_read(LGKernel*k,LGOutputTiming*timing){return k&&k->outputTiming.read(timing)?1:0;}
void lg_render_midi(LGKernel*k,LGMIDIHub*hub,uint64_t hostTime,double hostTicksPerSecond,float*l,float*r,int frames){
    k->outputTiming.observe(hostTime,hostTicksPerSecond,frames,k->sr);
    k->renderHub=hub;k->hostNow=hostTime;
    bool outputChanged=false;
    if(hub){const auto state=hub->outputConfiguration();if((state>>32)!=(k->outputState>>32)){outputChanged=true;hub->resetOutputRefs();for(auto &voice:k->voices)voice.outputChannel=-1;}k->outputState=state;}
    const double hostPerSample=hostTicksPerSecond/k->sr;
    if(hub)hub->prepare([&](int source){k->midiClear(source);});
    k->adoptMix();const bool panic=k->panicRequest.exchange(false,std::memory_order_acq_rel);if(panic){k->filterTarget.store(0);k->delayTarget.store(0);}
    int cmd=k->command.exchange(0);
    // A producer can temporarily own the only ready initial snapshot. Keep one
    // ordinary Play request until adoption succeeds on a later callback; never
    // spin on the publisher. New commands/Panic replace that deferred intent.
    if(panic||cmd!=0)k->pendingInitialPlay=false;
    if(cmd==1&&k->current<0)k->pendingInitialPlay=true;
    if(panic||cmd<0||cmd==2||cmd==3){k->performance.stop();k->active=false;k->counting=0;k->countRequest.store(0);k->countRemaining.store(0);k->fx.reset();k->reverb.reset();k->silence(true);if(hub)hub->outputEvent(k->outputState,k->hostNow,0,0,0);k->read.store(k->write.load());}
    // An explicit seek is already a discontinuity, so use the newest complete
    // project before interpreting its range. This also handles seeking beyond
    // an old one-bar loop into a newly extended arrangement.
    int seek=k->seek.exchange(-1);const int previousProject=k->current;
    k->adopt(!k->active||seek>=0,seek>=0?seek:k->position.load());
    if(seek>=0){if(k->current==previousProject||k->origin!=seek)k->resetCursor(seek);k->position.store(seek);}
    if((cmd>0||k->pendingInitialPlay)&&k->current>=0){auto&s=k->slots[k->current];double p=k->position.load();k->active=true;k->pendingInitialPlay=false;k->resetCursor(p>=s.end?s.start:std::max(p,double(s.start)));}
    // A queued project carries FX too; Panic must still win over that payload.
    if(panic){k->filterTarget.store(0);k->delayTarget.store(0);}
    float gainTargets[Buses],panTargets[Buses];
    for(int t=0;t<Buses;t++){gainTargets[t]=k->gains[t].load();panTargets[t]=k->pans[t].load();}
    const float filter=k->filterTarget.load(),delay=k->delayTarget.load();
    k->fx.prepare(filter,delay,k->current<0?120:k->slots[k->current].bpm);
    if(cmd==2||cmd==3){k->fx.reset();k->reverb.reset();}
    if(cmd==3&&k->current>=0){
        k->slots[k->current].loop=true;
        k->performance.begin(k->performance.requestToken.load(),k->performance.requestEpoch.load(),k->performance.requestCapture.load()!=0,k->performance.requestLimit.load());
        for(int t=0;t<Buses;t++){k->smooth[t]=gainTargets[t];k->smoothPan[t]=panTargets[t];k->capturedGain[t]=gainTargets[t];k->capturedPan[t]=panTargets[t];}
        k->capturedFilter=filter;k->capturedDelay=delay;
    }
    k->performance.consume([&](PerformanceControl control){return k->performAction(control);});
    // Chase only voices that survive Stop/Panic, seeks and queued section actions.
    if(outputChanged)for(auto &voice:k->voices)if(voice.on)k->startOutput(voice);
    if(k->performance.enabled){
        for(int t=0;t<Buses;t++){if(gainTargets[t]!=k->capturedGain[t])k->performance.emit(6,t,gainTargets[t]);if(panTargets[t]!=k->capturedPan[t])k->performance.emit(7,t,panTargets[t]);}
        if(filter!=k->capturedFilter){k->performance.emit(4,-1,filter);}if(delay!=k->capturedDelay){k->performance.emit(5,-1,delay);}
    }
    for(int t=0;t<Buses;t++){k->capturedGain[t]=gainTargets[t];k->capturedPan[t]=panTargets[t];}k->capturedFilter=filter;k->capturedDelay=delay;
    // Count-in needs the adopted tempo too. Retain its request while the first
    // snapshot is unavailable instead of indexing slots[-1] or advancing it.
    int request=k->current>=0?k->countRequest.exchange(0):0;if(request>0)k->counting=request;
    unsigned rd=k->read.load(),wr=k->write.load(std::memory_order_acquire);
    float peak[Buses]={};const float ramp=float(1-std::exp(-1/(k->sr*0.005)));
    for(int f=0;f<frames;f++){
        k->hostNow=hostTime+uint64_t(double(f)*hostPerSample);
        // Release old gates before scheduling a retrigger at this same sample.
        for(auto &voice:k->voices)if(voice.on&&voice.outputChannel>=0&&k->rendered>=voice.outputEndFrame)k->endOutput(voice);
        if(k->active&&k->performance.enabled){
            bool replay=k->performance.replayDue([&](const LGPerformanceEvent &event){
                if(event.kind>=1&&event.kind<=3){k->performAction({event.kind,event.a,event.b,event.token,event.value});}
                else if(event.kind==4){k->filterTarget.store(event.value);k->fx.prepare(event.value,k->delayTarget.load(),k->slots[k->current].bpm);}
                else if(event.kind==5){k->delayTarget.store(event.value);k->fx.prepare(k->filterTarget.load(),event.value,k->slots[k->current].bpm);}
                else if(event.kind==6){gainTargets[event.track]=event.value;k->gains[event.track].store(event.value);}
                else if(event.kind==7){panTargets[event.track]=event.value;k->pans[event.track].store(event.value);}
                else if(event.kind==8){k->trigger(36,int(event.value),event.track,event.a,1,1);}
                else if(event.kind==9){k->trigger(event.a,int(event.value),event.track,-1,event.b,0.65);}
                else if(event.kind==10||event.kind==11){k->midiEvent({0,event.b/16,event.kind==10?9:8,event.b%16,event.a,int(event.value),event.track,event.token},false);}
                else if(event.kind==12){k->midiEvent({0,event.b/16,11,event.b%16,64,event.value>0?127:0,0,0},false);}
                else if(event.kind==13){k->midiClear(event.b,false);}
                else if(event.kind==99){k->active=false;k->fx.releaseRepeat();if(k->tailOnEnd.load()){for(auto &voice:k->voices)if(voice.on&&voice.pad<0)voice.duration=std::min(voice.duration,voice.age+0.008);}else{k->silence(true);k->fx.reset();k->reverb.reset();}}
            });
            if(!replay)k->performance.due(k->ticksPerFrame(),[&](PerformanceControl control){return k->performAction(control);});
        }
        if(k->counting>0){int beatFrames=int(k->sr*60/k->slots[k->current].bpm);if(k->counting%beatFrames==0)k->click(k->counting>beatFrames*3);k->counting--;k->countRemaining.store(k->counting);}
        else if(k->active&&k->current>=0){
            auto*s=&k->slots[k->current];double tp=k->ticksPerFrame();double raw=k->origin+k->elapsed*tp;double tick=raw-k->cycle*(s->end-s->start);bool looped=false;
            if(tick>=s->end-0.5*tp){if(s->loop){k->cycle++;tick-=s->end-s->start;k->cursor=0;k->silence();while(k->cursor<s->count&&s->notes[k->cursor].tick<s->start)k->cursor++;k->lastBeat=-1;looped=true;}else{k->active=false;if(!k->tailOnEnd.load()){k->silence(true);k->fx.reset();k->reverb.reset();}tick=s->end;}}
            int old=k->current;k->adopt(looped||!k->active,tick);if(k->current!=old){
                s=&k->slots[k->current];tick=k->origin;tp=k->ticksPerFrame();
                // Adoption can occur inside a render block. Refresh local mix
                // targets here, not a buffer later, so the new notes cannot use
                // the preceding layout's gain/pan or FX for even one sample.
                for(int t=0;t<Buses;t++){gainTargets[t]=k->gains[t].load();panTargets[t]=k->pans[t].load();}
                k->fx.prepare(k->filterTarget.load(),k->delayTarget.load(),s->bpm);
            }
            if(k->active){
                while(k->cursor<s->count&&s->notes[k->cursor].tick<=tick+0.5*tp){auto&n=s->notes[k->cursor++];if(n.tick>=s->start&&n.tick<s->end)k->trigger(n.pitch,n.velocity,n.track,n.pad,n.instrument,n.pad>=0?LegacyKitFrames/k->sr:std::min(n.duration,s->end-n.tick)/960.0*60/s->bpm);}
                int beat=int(tick/960);if(beat!=k->lastBeat){if(k->metro.load())k->click(beat%4==0);k->lastBeat=beat;}
                k->position.store(tick,std::memory_order_relaxed);k->previous=tick;k->elapsed++;
            }else k->position.store(tick);
        }
        k->repeatTick();
        if(f==0){while(rd<wr){auto v=k->input[rd++%256];if(v.identity){v.track=k->identityTrack(v.identity);if(v.track>=0)v.instrument=k->slots[k->current].instruments[v.track];}else if(!v.preview)v.track=k->roleTrack(1,1);else if(v.track<0)v.track=k->roleTrack(0,0);if(v.track<0)continue;k->performance.emit(v.preview?9:8,v.track,float(v.velocity),v.value,v.instrument);k->trigger(v.preview?v.value:36,v.velocity,v.track,v.preview?-1:v.value,v.instrument,v.preview?0.65:1);}k->read.store(rd,std::memory_order_release);}
        // Boundary-time input belongs to the newly adopted layout. Applying it
        // before adoption would create an old-index voice and then clear it.
        if(hub)hub->dueWithOrigin(hostTime+uint64_t(double(f)*hostPerSample),uint64_t(std::max(1.0,hostPerSample)),[&](const LGMIDIEvent &event,bool){if(!k->performance.replaying())k->midiEvent(event,true);});
        for(int t=0;t<Buses;t++){k->smooth[t]+=(gainTargets[t]-k->smooth[t])*ramp;k->smoothPan[t]+=(panTargets[t]-k->smoothPan[t])*ramp;}
        float left=0,right=0;float buses[Buses]={};
        for(auto&v:k->voices)if(v.on){
            float sample=0;const double remaining=v.duration-v.age;
            if(remaining<=0){k->endOutput(v);v.on=false;continue;}
            if(v.sample){
                sample=sampleFrame(v)*v.velocity*float(std::min(1.,v.age/0.001)*std::min(1.,remaining/0.008));
                v.age=double(++v.ageFrames)/k->sr;
                v.lastSample=sample;v.level=std::abs(sample);
                buses[v.track]+=sample;
                continue;
            }
            if(v.pad>=0){const auto &bank=v.presetVersion>=2&&k->kitFrames!=LegacyKitFrames?k->kitV2:k->kit;int frame=v.presetVersion>=3?int(double(v.ageFrames)*v.playbackRatio):v.presetVersion>=2?int(v.ageFrames):int(v.age*k->sr);if(frame>=int(bank[v.pad].size())){k->endOutput(v);v.on=false;continue;}sample=bank[v.pad][frame];if(v.presetVersion>=3){v.toneState+=float(v.toneAlpha)*(sample-v.toneState);sample=v.presetVersion==3?v.toneState:float((sample+0.65*(sample-v.toneState))*0.85);}}
            else {v.phase+=v.phaseStep;if(v.phase>=1)v.phase-=1;if(v.presetVersion<=2){sample=float((std::sin(2*Pi*v.phase)+(v.instrument==3?0.35:0.22)*std::sin(4*Pi*v.phase)+(v.instrument==3?0.12*std::sin(6*Pi*v.phase):0))*0.17);}else{const double sine=std::sin(2*Pi*v.phase),cosine=std::cos(2*Pi*v.phase),second=2*sine*cosine;sample=float((v.partials[0]*sine+v.partials[1]*second+v.partials[2]*sine*(3-4*sine*sine)+v.partials[3]*2*second*(1-2*sine*sine))*0.17);}}
            double envelope=std::min(1.,v.age/(v.presetVersion>=3?v.attack:0.004))*std::min(1.,remaining/0.008);if(v.pad<0)envelope*=v.presetVersion>=2?v.decay:std::exp(-v.age*(v.instrument==2?1.5:0.7));
            sample*=float(envelope)*v.velocity;v.level=std::abs(sample);if(v.presetVersion>=2){v.age=double(++v.ageFrames)/k->sr;v.decay*=v.decayStep;}else{v.age+=1/k->sr;}
            v.lastSample=sample;
            buses[v.track]+=sample;
        }
        for(auto &tail:k->retirements)if(tail.remaining>0){const float value=tail.sample*float(tail.remaining)/float(tail.total);buses[tail.track]+=value;--tail.remaining;}
        k->dynamics(buses);
        k->fx.processBuses(buses,k->active);
        float send=0;
        for(int t=0;t<MaxTracks;t++){
            const float amp=k->eqChannels[t].process(buses[t])*k->smooth[t];
            if(k->panValue[t]!=k->smoothPan[t]){const float angle=(k->smoothPan[t]+1)*float(Pi/4);k->panLeft[t]=std::cos(angle);k->panRight[t]=std::sin(angle);k->panValue[t]=k->smoothPan[t];}
            left+=amp*k->panLeft[t];right+=amp*k->panRight[t];peak[t]=std::max(peak[t],std::abs(amp));
            send+=amp*k->reverbSend[t].load(std::memory_order_relaxed);
        }
        if(k->reverb.active(send))k->reverb.process(send,left,right);
        k->fx.process(left,right);
        left=k->eqChannels[Master].process(left);right=k->eqChannels[Master+1].process(right);
        const float cue=buses[Master]*0.65f*0.7071067812f;left+=cue;right+=cue;
        left*=k->smooth[Master];right*=k->smooth[Master];float masterPeak=std::max(std::abs(left),std::abs(right));
        if(k->layoutFadeRemaining>0){const float weight=float(k->layoutFadeRemaining)/float(k->layoutFadeTotal);left=left*(1-weight)+k->layoutFadeLeft*weight;right=right*(1-weight)+k->layoutFadeRight*weight;--k->layoutFadeRemaining;}
        if(k->limit(left,right))masterPeak=std::max(std::abs(left),std::abs(right));
        peak[Master]=std::max(peak[Master],masterPeak);
        l[f]=std::clamp(left,-0.98f,0.98f);r[f]=std::clamp(right,-0.98f,0.98f);k->lastLeft=l[f];k->lastRight=r[f];k->rendered++;k->performance.advance(k->active);
    }
    for(int t=0;t<Buses;t++)k->meters[t].store(std::max(peak[t],k->meters[t].load()*float(std::exp(-double(frames)/(k->sr*0.12)))));
    k->performance.publish();k->clock.store(k->rendered);k->playing.store(k->active?1:0);
}
double lg_tick(LGKernel*k){return k->position.load();}uint64_t lg_clock(LGKernel*k){return k->clock.load();}
int lg_playing(LGKernel*k){return k->playing.load();}int lg_revision(LGKernel*k){return k->applied.load();}
float lg_meter(LGKernel*k,int t){return t>=0&&t<Buses?k->meters[t].load():0;}
int lg_overflows(LGKernel*k){return k->overflow.load();}
void lg_render(LGKernel*k,float*l,float*r,int frames){lg_render_midi(k,nullptr,0,0,l,r,frames);}

}
