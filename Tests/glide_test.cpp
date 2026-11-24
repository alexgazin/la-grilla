// Beat machine 808 slides: on a sampled melodic track with a glide, a note that starts
// while the previous one still sounds bends that voice to the new pitch instead of
// stacking a second voice. Without a glide both voices sound together.
#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double rate=48000;
LGSampleBank*sineBank(){
    std::vector<int16_t> pcm(64000);
    for(std::size_t i=0;i<pcm.size();i++){const double t=double(i)/32000;pcm[i]=int16_t(std::lround(20000*std::sin(2*M_PI*110.0*t)));}
    const LGSampleZone zone={45,0,int(pcm.size()),0};
    return lg_sample_create(32000,&zone,1,pcm.data(),int(pcm.size()));
}
std::vector<float> play(float glide){
    auto*k=lg_create(rate);auto*bank=sineBank();
    std::array<LGProjectTrack,4> tracks{};for(int i=0;i<4;i++)tracks[i]={{0,0,1},2,i,i,uint64_t(100+i)};
    std::array<LGSampleBank*,8> instruments{};std::array<LGSampleBank*,16> pads{};instruments[3]=bank;
    // A2 held past the start of E3 (overlap = slide), both on track 3.
    std::array<LGNote,2> notes={{{0,1100,45,110,3,-1,3},{960,960,52,110,3,-1,3}}};
    assert(lg_submit_project_samples(k,notes.data(),2,120,0,3840,0,1,1,tracks.data(),4,0,0,0,instruments.data(),pads.data()));
    assert(lg_glide(k,3,glide));
    assert(!lg_glide(k,3,-1)&&!lg_glide(k,9,0.1f));
    lg_seek(k,0);{std::array<float,1> a{},b{};lg_render(k,a.data(),b.data(),1);}lg_play(k,1);
    std::vector<float> out(size_t(rate*1.0));std::array<float,256> l{},r{};
    for(std::size_t pos=0;pos<out.size();){const int n=int(std::min<std::size_t>(256,out.size()-pos));lg_render(k,l.data(),r.data(),n);for(int i=0;i<n;i++){assert(std::isfinite(l[size_t(i)]));out[pos+size_t(i)]=l[size_t(i)];}pos+=size_t(n);}
    lg_sample_release(bank);lg_destroy(k);return out;
}
double peak(const std::vector<float>&v,double from,double to){double p=0;for(std::size_t i=size_t(from*rate);i<size_t(to*rate);i++)p=std::max(p,double(std::abs(v[i])));return p;}
int crossings(const std::vector<float>&v,double from,double to){int c=0;for(std::size_t i=size_t(from*rate)+1;i<size_t(to*rate);i++)if((v[i-1]<0)!=(v[i]<0))c++;return c;}
}

int main(){
    const auto slid=play(0.06f),stacked=play(0);
    // While both notes overlap, two voices sum; the slide keeps one.
    const double one=peak(slid,0.51,0.56),two=peak(stacked,0.51,0.56);
    assert(one>0.01);
    assert(two>1.3*one);
    // After the slide the single voice plays E3 (164.8 Hz): about 2 × 164.8 × 0.25 crossings.
    const int c=crossings(slid,0.70,0.95);
    assert(c>=78&&c<=87);
    std::printf("glide ok: one %.3f two %.3f crossings %d\n",one,two,c);
    return 0;
}
