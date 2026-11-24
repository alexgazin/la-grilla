// I37 track automation: level (dB) and pan follow their points linearly in ticks while playing,
// independent of the render block size (live = export), and a muted track stays silent.
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr int Rate=48000;
LGSampleBank*tone(){
    std::vector<int16_t> pcm(48000);
    for(size_t i=0;i<pcm.size();i++)pcm[i]=int16_t(12000*std::sin(2*3.14159265358979*i/96.0));   // 500 Hz, whole periods
    const LGSampleZone zone={60,0,int(pcm.size()),9600};
    return lg_sample_create(Rate,&zone,1,pcm.data(),int(pcm.size()));
}

LGKernel*kernel(LGSampleBank*bank,bool audible=true){
    auto*k=lg_create(Rate);
    std::array<LGSampleBank*,8> instruments{};std::array<LGSampleBank*,16> pads{};instruments[0]=bank;
    std::array<LGProjectTrack,1> tracks={{{{0,0,audible?1:0},2,3,0,11}}};
    const LGNote note={0,3840*4,60,100,0,-1,3};
    assert(lg_submit_project_samples(k,&note,1,120,0,3840*4,0,1,1,tracks.data(),1,0,0,0,instruments.data(),pads.data()));
    return k;
}

/// Renders `frames` in blocks of `block` and returns both channels.
void render(LGKernel*k,int frames,int block,std::vector<float>&left,std::vector<float>&right){
    left.assign(size_t(frames),0);right.assign(size_t(frames),0);
    for(int pos=0;pos<frames;pos+=block){const int n=std::min(block,frames-pos);lg_render(k,left.data()+pos,right.data()+pos,n);}
}

double rms(const std::vector<float>&v,int from,int count){double s=0;for(int i=from;i<from+count;i++)s+=double(v[size_t(i)])*v[size_t(i)];return std::sqrt(s/count);}
}

int main(){
    auto*bank=tone();assert(bank);
    {   // Bad lanes are refused.
        auto*k=kernel(bank);
        const LGAutomationPoint unordered[]={{960,0},{960,-6}},loud[]={{0,7}},wide[]={{0,1.5f}};
        assert(!lg_track_automation(k,0,0,unordered,2)&&!lg_track_automation(k,0,0,loud,1)&&!lg_track_automation(k,0,1,wide,1));
        assert(!lg_track_automation(k,8,0,loud,0)&&!lg_track_automation(k,0,2,loud,0));
        lg_destroy(k);
    }
    // At 120 BPM one tick is 25 frames: tick 960 = frame 24000.
    const LGAutomationPoint level[]={{0,0},{1920,-20}};
    std::vector<float> plainL,plainR,autoL,autoR,blockL,blockR;
    {   // Level: 0 dB → −20 dB over two beats, −10 dB half way, then held.
        auto*reference=kernel(bank);lg_play(reference,1);render(reference,Rate*2,512,plainL,plainR);lg_destroy(reference);
        auto*k=kernel(bank);assert(lg_track_automation(k,0,0,level,2));lg_play(k,1);render(k,Rate*2,512,autoL,autoR);lg_destroy(k);
        const double start=rms(autoL,2400,960)/rms(plainL,2400,960),middle=rms(autoL,23520,960)/rms(plainL,23520,960),end=rms(autoL,60000,960)/rms(plainL,60000,960);
        assert(std::abs(start-std::pow(10,-1.2/20))<0.02);         // tick ≈ 115 → −1.2 dB
        assert(std::abs(middle-std::pow(10,-10/20.0))<0.02);
        assert(std::abs(end-0.1)<0.005);
    }
    {   // The same lane rendered in blocks of 64 instead of 512 is identical (live = export).
        auto*k=kernel(bank);assert(lg_track_automation(k,0,0,level,2));lg_play(k,1);render(k,Rate*2,64,blockL,blockR);lg_destroy(k);
        for(size_t i=0;i<blockL.size();i++)assert(std::abs(blockL[i]-autoL[i])<1e-6f);
    }
    {   // Pan: hard left → hard right; equal in the middle.
        const LGAutomationPoint pan[]={{0,-1},{1920,1}};
        auto*k=kernel(bank);assert(lg_track_automation(k,0,1,pan,2));lg_play(k,1);render(k,Rate*2,512,autoL,autoR);
        assert(rms(autoR,1200,480)<0.12*rms(autoL,1200,480));
        assert(std::abs(rms(autoL,23760,480)/rms(autoR,23760,480)-1)<0.06);
        assert(rms(autoL,60000,480)<0.02*rms(autoR,60000,480));
        // Clearing the lane returns to the mixer's centre pan.
        assert(lg_track_automation(k,0,1,nullptr,0));render(k,9600,512,autoL,autoR);
        assert(std::abs(rms(autoL,4800,960)/rms(autoR,4800,960)-1)<0.02);
        lg_destroy(k);
    }
    {   // A muted track stays silent whatever its level lane says.
        auto*k=kernel(bank,false);assert(lg_track_automation(k,0,0,level,2));lg_play(k,1);render(k,Rate,512,autoL,autoR);
        assert(rms(autoL,0,Rate)==0&&rms(autoR,0,Rate)==0);
        lg_destroy(k);
    }
    lg_sample_release(bank);
    std::printf("Track automation: level and pan follow their points in ticks, block size does not change the result, clearing returns to the mixer, mute wins\n");
}
