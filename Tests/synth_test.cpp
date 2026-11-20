// I55 synth: off is bit-identical; the envelope follows A/D/S/R (attack rise,
// sustain level, release tail after the note); a lower cutoff removes highs;
// square and saw differ; invalid patches are rejected.
#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double rate=48000;
std::vector<float> render(const LGSynthPatch*patch,int frames,bool call=true,int pitch=57){
    auto*k=lg_create(rate);
    std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,3,2,202}}};
    LGNote note{0,960,pitch,100,1,-1,3};                     // 0.5 s at 120 BPM
    assert(lg_submit_project(k,&note,1,120,0,3840*2,0,1,1,tracks.data(),2,-3,0,0));
    if(call)assert(lg_synth(k,1,patch));
    lg_seek(k,0);std::vector<float> l(static_cast<size_t>(frames)),r(static_cast<size_t>(frames));lg_render(k,l.data(),r.data(),1);lg_play(k,1);
    for(int pos=0;pos<frames;pos+=512)lg_render(k,l.data()+pos,r.data()+pos,std::min(512,frames-pos));
    lg_destroy(k);return l;
}
double rms(const std::vector<float>&v,int a,int b){double s=0;for(int i=a;i<b;i++)s+=double(v[size_t(i)])*v[size_t(i)];return std::sqrt(s/std::max(1,b-a));}
double hf(const std::vector<float>&v,int a,int b){double s=0;for(int i=a+1;i<b;i++){const double d=v[size_t(i)]-v[size_t(i-1)];s+=d*d;}return std::sqrt(s/std::max(1,b-a));}
}

int main(){
    const int frames=int(rate*1.5);
    const auto plain=render(nullptr,frames,false),off=render(nullptr,frames,true);
    assert(plain==off);
    const LGSynthPatch pad{0,0.8f,0.2f,0.2f,0.3f,0.5f,0.4f};
    const auto synth=render(&pad,frames);
    assert(synth!=plain);
    // Attack: quiet at 20 ms, full near 200 ms; sustain ≈ 0.5 of the peak after the decay.
    const double start=rms(synth,0,960),peak=rms(synth,int(rate*0.18),int(rate*0.21)),sustain=rms(synth,int(rate*0.44),int(rate*0.49));
    assert(start<peak*0.2);
    assert(sustain/peak>0.4&&sustain/peak<0.65);
    // Release: still sounding 0.2 s after the note ends (0.5 s), silent after 0.4 s.
    assert(rms(synth,int(rate*0.68),int(rate*0.72))>sustain*0.2);
    assert(rms(synth,int(rate*0.95),int(rate*1.0))<1e-6);
    // Cutoff: a darker patch has much less high-frequency energy at equal level.
    const LGSynthPatch bright{0,1,0,0.002f,0.1f,1,0.05f},dark{0,0.3f,0,0.002f,0.1f,1,0.05f};
    const auto b=render(&bright,frames),d=render(&dark,frames);
    const double bRatio=hf(b,9600,19200)/rms(b,9600,19200),dRatio=hf(d,9600,19200)/rms(d,9600,19200);
    assert(dRatio<bRatio*0.5);
    const LGSynthPatch square{1,1,0,0.002f,0.1f,1,0.05f};assert(render(&square,frames)!=b);
    {auto*k=lg_create(rate);LGSynthPatch bad=pad;bad.wave=3;assert(!lg_synth(k,1,&bad));bad=pad;bad.resonance=1;assert(!lg_synth(k,1,&bad));bad=pad;bad.cutoff=NAN;assert(!lg_synth(k,1,&bad));assert(!lg_synth(k,8,&pad));lg_destroy(k);}
    std::printf("Synth: off bit-identical; attack %.2f, sustain %.2f of peak; release tail then silence; cutoff halves high-frequency energy (%.3f vs %.3f)\n",start/peak,sustain/peak,dRatio,bRatio);
}
