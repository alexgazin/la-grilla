// Build 44: the same keyboard phrase must reach the output at the same level
// live (built-in keybed through the MIDI hub), after recording (sequenced note)
// and in the offline WAV path (same kernel, lg_render without a hub).
// `--report` prints peaks/RMS as JSON without asserting, for the evidence table.
#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

namespace {
constexpr double rate=48000;
constexpr int heldFrames=24000;          // 0.5 s held phrase note at 120 BPM = 960 ticks
constexpr int measureFrames=19200;       // compare the sustained part only, before any release ramp
struct Level {double peak=0,rms=0;};
struct Case {const char*name;int instrument;int preset;bool sample;double samplePeak;};

double db(double v){return v>0?20*std::log10(v):-200;}
Level measure(const std::vector<float>&v){
    Level l;double sum=0;for(int i=0;i<measureFrames;i++){l.peak=std::max(l.peak,double(std::abs(v[i])));sum+=double(v[i])*v[i];}
    l.rms=std::sqrt(sum/measureFrames);return l;
}
LGSampleBank*quietBank(double peak){
    // An imported multisample recorded quietly (for example a soft SoundFont zone).
    std::vector<int16_t> pcm(32000);
    for(std::size_t i=0;i<pcm.size();i++){const double t=double(i)/32000;pcm[i]=int16_t(std::lround(32767*peak*std::sin(2*M_PI*261.63*t)*std::exp(-t*0.4)));}
    const LGSampleZone zone={60,0,int(pcm.size()),0};
    return lg_sample_create(32000,&zone,1,pcm.data(),int(pcm.size()));
}
void submit(LGKernel*k,const Case&c,const LGNote*notes,int count,LGSampleBank*bank,int revision){
    std::array<LGProjectTrack,4> tracks{};
    for(int i=0;i<4;i++)tracks[i]={{-6,0,1},c.preset,i,i,uint64_t(100+i)};
    std::array<LGSampleBank*,8> instruments{};std::array<LGSampleBank*,16> pads{};
    if(bank)instruments[size_t(c.instrument)]=bank;
    assert(lg_submit_project_samples(k,notes,count,120,0,3840*4,0,revision,1,tracks.data(),4,-3,0,0,instruments.data(),pads.data()));
}
std::vector<float> render(LGKernel*k,LGMIDIHub*hub,int frames){
    std::vector<float> out(static_cast<size_t>(frames));std::array<float,256> l{},r{};
    for(int pos=0;pos<frames;){const int n=std::min(256,frames-pos);
        if(hub)lg_render_midi(k,hub,uint64_t(pos),rate,l.data(),r.data(),n);else lg_render(k,l.data(),r.data(),n);
        for(int i=0;i<n;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));out[size_t(pos+i)]=l[i];}pos+=n;}
    return out;
}
// Live: the built-in keybed path used by MIDIController.playKey.
std::vector<float> live(const Case&c,int velocity,const std::vector<int>&pitches){
    auto*k=lg_create(rate);auto*hub=lg_midi_create();LGSampleBank*bank=c.sample?quietBank(c.samplePeak):nullptr;
    submit(k,c,nullptr,0,bank,1);
    // Adopt the project layout through the hub so the keybed resolves its track UUID.
    {std::array<float,1> a{},b{};lg_render_midi(k,hub,0,rate,a.data(),b.data(),1);}
    lg_midi_configure_keyboard(hub,256,uint64_t(100+c.instrument),c.instrument,c.instrument);
    for(int p:pitches){const uint8_t on[]={0x90,uint8_t(p),uint8_t(velocity)};assert(lg_midi_push(hub,256,1,on,3));}
    auto out=render(k,hub,heldFrames);
    if(bank){lg_sample_release(bank);}
    lg_destroy(k);lg_midi_destroy(hub);return out;
}
// Recorded / WAV: the phrase saved as notes and played by the sequencer.
std::vector<float> sequenced(const Case&c,int velocity,const std::vector<int>&pitches,bool withKick=false){
    auto*k=lg_create(rate);LGSampleBank*bank=c.sample?quietBank(c.samplePeak):nullptr;
    std::vector<LGNote> notes;for(int p:pitches)notes.push_back({0,960,p,velocity,c.instrument,-1,c.instrument});
    if(withKick)notes.push_back({0,960,36,127,1,0,1});
    std::sort(notes.begin(),notes.end(),[](auto&x,auto&y){return x.tick<y.tick;});
    submit(k,c,notes.data(),int(notes.size()),bank,1);lg_seek(k,0);std::array<float,1> a{},b{};lg_render(k,a.data(),b.data(),1);lg_play(k,1);
    auto out=render(k,nullptr,heldFrames);
    if(bank){lg_sample_release(bank);}
    lg_destroy(k);return out;
}
}

int main(int argc,char**argv){
    const bool report=argc==2&&std::string(argv[1])=="--report";
    const std::array<Case,4> cases={{
        {"piano-synth",0,2,false,0},{"soft-attack-warm",3,3,false,0},{"bass",2,2,false,0},{"imported-quiet-sample",3,2,true,0.12}}};
    // The built-in keybed and a recorded phrase share one velocity constant.
    constexpr int keyboardVelocity=100;
    double worst=0;
    if(report)std::printf("[\n");
    for(std::size_t i=0;i<cases.size();i++){
        const auto&c=cases[i];
        const Level liveSingle=measure(live(c,keyboardVelocity,{60}));
        const Level recSingle=measure(sequenced(c,keyboardVelocity,{60}));
        const Level liveChord=measure(live(c,keyboardVelocity,{60,64,67,71}));
        const Level recChord=measure(sequenced(c,keyboardVelocity,{60,64,67,71}));
        const Level withBeat=measure(sequenced(c,keyboardVelocity,{60,64,67,71},true));
        const double single=db(liveSingle.peak)-db(recSingle.peak),chord=db(liveChord.peak)-db(recChord.peak);
        worst=std::max({worst,std::abs(single),std::abs(chord)});
        if(report)std::printf("  {\"timbre\":\"%s\",\"velocity\":%d,\"liveSinglePeakDBFS\":%.2f,\"recordedSinglePeakDBFS\":%.2f,\"singleDeltaDB\":%.2f,"
                              "\"liveChordPeakDBFS\":%.2f,\"recordedChordPeakDBFS\":%.2f,\"chordDeltaDB\":%.2f,\"chordWithKickPeakDBFS\":%.2f,\"liveSingleRMSDBFS\":%.2f,\"recordedSingleRMSDBFS\":%.2f}%s\n",
                              c.name,keyboardVelocity,db(liveSingle.peak),db(recSingle.peak),single,db(liveChord.peak),db(recChord.peak),chord,db(withBeat.peak),db(liveSingle.rms),db(recSingle.rms),i+1<cases.size()?",":"");
        // Headroom: a four-note chord plus a full-velocity kick at default
        // track/master gain stays below full scale.
        if(!report)assert(withBeat.peak<0.98);
    }
    if(report){std::printf("]\n");return 0;}
    // Same velocity, same track gain and master: live and recorded match.
    assert(worst<0.1);
    std::printf("Keyboard level: live keybed, recorded phrase and offline render match within %.3f dB for synth, soft-attack, bass and quiet imported sample; chord+kick keeps headroom\n",worst);
}
