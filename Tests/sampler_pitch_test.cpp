// I31 melodic sampler: a sound recorded at A4 (440 Hz, 32 kHz) plays on other keys within ±5 cents
// through the kernel's sampled-instrument path (resampling by the key's distance from the root).
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double Pi=3.14159265358979323846;
/// Frequency from interpolated upward zero crossings.
double frequency(const std::vector<float>&v,int from,int count,double rate){
    double first=-1,last=-1;int crossings=0;
    for(int i=from+1;i<from+count;i++)if(v[size_t(i-1)]<0&&v[size_t(i)]>=0){
        const double t=i-1+v[size_t(i-1)]/(v[size_t(i-1)]-v[size_t(i)]);
        if(first<0){first=t;}
        last=t;crossings++;
    }
    return crossings>1?(crossings-1)*rate/(last-first):0;
}
double played(LGSampleBank*bank,int pitch){
    auto*k=lg_create(48000);
    std::array<LGSampleBank*,8> instruments{};std::array<LGSampleBank*,16> pads{};instruments[0]=bank;
    std::array<LGProjectTrack,1> tracks={{{{0,0,1},2,3,0,9}}};
    const LGNote note={0,1920,pitch,100,0,-1,3};
    assert(lg_submit_project_samples(k,&note,1,120,0,3840,0,1,1,tracks.data(),1,0,0,0,instruments.data(),pads.data()));
    lg_play(k,1);
    std::vector<float> l(48000),r(48000);for(int pos=0;pos<48000;pos+=512)lg_render(k,l.data()+pos,r.data()+pos,std::min(512,48000-pos));
    lg_destroy(k);
    return frequency(l,4800,24000,48000);
}
}

int main(){
    std::vector<int16_t> pcm(64000);
    for(size_t i=0;i<pcm.size();i++)pcm[i]=int16_t(16000*std::sin(2*Pi*440*double(i)/32000));
    const LGSampleZone zone={69,0,int(pcm.size()),0};
    auto*bank=lg_sample_create_with_release(32000,&zone,1,pcm.data(),int(pcm.size()),1);
    assert(bank);
    for(int pitch:{45,57,62,69,76,81,93}){
        const double expected=440*std::pow(2,(pitch-69)/12.0),measured=played(bank,pitch);
        const double cents=1200*std::log2(measured/expected);
        assert(std::abs(cents)<5);
    }
    lg_sample_release(bank);
    std::printf("Sampler pitch: a 440 Hz sound plays A2…A6 within ±5 cents\n");
}
