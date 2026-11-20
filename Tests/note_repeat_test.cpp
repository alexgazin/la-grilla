// I3 note repeat: a held pad retriggers exactly on the transport grid while
// playing (sample-accurate), free-runs at the tempo when stopped, and stops
// at once when released. Invalid rates are rejected.
#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double rate=48000;
std::vector<int> onsets(const std::vector<float>&v){
    std::vector<int> out;int quiet=0;
    for(int i=0;i<int(v.size());i++){
        const float a=std::abs(v[size_t(i)]);
        if(a>0.002f){if(quiet>int(rate*0.02))out.push_back(i);quiet=0;}else quiet++;
    }
    return out;
}
std::vector<float> render(LGKernel*k,int frames){
    std::vector<float> l(static_cast<size_t>(frames)),r(static_cast<size_t>(frames));
    for(int pos=0;pos<frames;pos+=256){lg_render(k,l.data()+pos,r.data()+pos,std::min(256,frames-pos));}
    return l;
}
LGKernel*kernel(){
    auto*k=lg_create(rate);
    std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,1,9,102}}};
    // One silent marker note keeps a two-bar loop running.
    LGNote note{0,1,60,1,0,-1,0};
    assert(lg_submit_project(k,&note,1,120,0,3840*2,1,1,1,tracks.data(),2,-3,0,0));
    return k;
}
}

int main(){
    {   // Validation.
        auto*k=lg_create(rate);
        assert(!lg_pad_repeat(k,16,240,100)&&!lg_pad_repeat(k,0,200,100)&&!lg_pad_repeat(nullptr,0,240,100));
        assert(lg_pad_repeat(k,-1,0,0));
        lg_destroy(k);
    }
    {   // Playing at 120 BPM: 1/16 = 6000 frames. Start the repeat at tick 100.
        auto*k=kernel();lg_seek(k,0);{std::array<float,1> a{},b{};lg_render(k,a.data(),b.data(),1);}lg_play(k,1);
        const int startFrame=2500;          // ≈ tick 100
        render(k,startFrame);
        assert(lg_pad_repeat(k,2,240,110));
        auto held=render(k,6000*8);
        assert(lg_pad_repeat(k,-1,0,0));
        auto after=render(k,6000*4);
        const auto hits=onsets(held);
        assert(hits.size()==8);
        // Grid ticks 240, 480, … → absolute frames 6000·n; relative to the hold start.
        // The same pad sequenced at ticks 240·n gives the reference onsets
        // (the detector sees the pad's 0.5 ms attack the same way).
        auto*ref=lg_create(rate);
        std::vector<LGNote> grid;for(int n=1;n<=8;n++)grid.push_back({240*n,120,40,110,1,2,1});
        std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,1,9,102}}};
        assert(lg_submit_project(ref,grid.data(),int(grid.size()),120,0,3840*2,1,1,1,tracks.data(),2,-3,0,0));
        lg_seek(ref,0);{std::array<float,1> a{},b{};lg_render(ref,a.data(),b.data(),1);}lg_play(ref,1);
        render(ref,startFrame);
        const auto expected=onsets(render(ref,6000*8));
        assert(expected.size()==8);
        for(size_t i=0;i<hits.size();i++)assert(std::abs(hits[i]-expected[i])<=1);
        lg_destroy(ref);
        // Released: only the decaying tail of the last hit, no new onsets.
        assert(onsets(after).empty());
        lg_destroy(k);
    }
    {   // Stopped transport: free-running 1/8 at 120 BPM = 12000 frames.
        auto*k=kernel();
        assert(lg_pad_repeat(k,2,480,100));
        auto held=render(k,12000*4+100);
        const auto hits=onsets(held);
        assert(hits.size()==4);
        for(size_t i=1;i<hits.size();i++)assert(std::abs((hits[i]-hits[i-1])-12000)<=1);
        lg_destroy(k);
    }
    std::printf("Note repeat: 8 sixteenths within 1 frame of the sequenced grid while playing, free-running eighths when stopped, silent after release\n");
}
