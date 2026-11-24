// I34 layered pads: a pad bank of 2…4 one-shots picks a layer by an equal velocity split or in
// turn (round robin), inside the render without allocations; bad layer tables are refused.
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr int Rate=32000,Frames=1600;            // 50 ms layers
const int periods[]={80,40,20};                   // 400, 800 and 1600 Hz squares

LGSampleBank*layered(int count,int mode){
    std::vector<int16_t> pcm;std::vector<LGSampleZone> zones;
    for(int layer=0;layer<count;layer++){
        zones.push_back({layer,int(pcm.size()),Frames,0});
        for(int i=0;i<Frames;i++)pcm.push_back(int16_t(i%periods[layer]<periods[layer]/2?9000:-9000));
    }
    return lg_sample_create_layers(Rate,zones.data(),count,pcm.data(),int(pcm.size()),mode);
}

LGKernel*kernel(LGSampleBank*bank){
    auto*k=lg_create(48000);
    std::array<LGSampleBank*,8> instruments{};std::array<LGSampleBank*,16> pads{};pads[0]=bank;
    std::array<LGProjectTrack,1> tracks={{{{0,0,1},2,1,9,7}}};
    assert(lg_submit_project_samples(k,nullptr,0,120,0,3840,0,1,1,tracks.data(),1,0,0,0,instruments.data(),pads.data()));
    std::vector<float> l(512),r(512);lg_render(k,l.data(),r.data(),512);
    return k;
}

/// Hits pad 0 and tells which layer sounded from the pitch of the output.
int hit(LGKernel*k,int velocity){
    assert(lg_pad(k,0,velocity));
    std::vector<float> l(4800),r(4800);lg_render(k,l.data(),r.data(),4800);   // 100 ms: the layer ends
    int crossings=0;for(size_t i=1;i<2400;i++)if(l[i-1]<0&&l[i]>=0)crossings++;
    // 50 ms of 400 / 800 / 1600 Hz → about 20 / 40 / 80 upward crossings.
    int best=0;for(int layer=1;layer<3;layer++)if(std::abs(crossings-20*(1<<layer))<std::abs(crossings-20*(1<<best)))best=layer;
    return best;
}
}

int main(){
    {   // Bad tables are refused.
        std::vector<int16_t> pcm(Frames*2,100);
        const LGSampleZone wrong[]={{0,0,Frames,0},{2,Frames,Frames,0}},looped[]={{0,0,Frames,0},{1,Frames,Frames,40}},one[]={{0,0,Frames,0}};
        assert(!lg_sample_create_layers(Rate,wrong,2,pcm.data(),int(pcm.size()),0));
        assert(!lg_sample_create_layers(Rate,looped,2,pcm.data(),int(pcm.size()),0));
        assert(!lg_sample_create_layers(Rate,one,1,pcm.data(),Frames,0));
        assert(!lg_sample_create_layers(Rate,wrong,2,pcm.data(),int(pcm.size()),2));
    }
    {   // Velocity: an equal split of 1…127 into three layers.
        auto*bank=layered(3,0);assert(bank);auto*k=kernel(bank);lg_sample_release(bank);
        assert(hit(k,20)==0&&hit(k,42)==0);
        assert(hit(k,43)==1&&hit(k,84)==1);
        assert(hit(k,86)==2&&hit(k,127)==2);
        lg_destroy(k);
    }
    {   // Round robin: the same strength plays each layer in turn.
        auto*bank=layered(3,1);assert(bank);auto*k=kernel(bank);lg_sample_release(bank);
        const int expected[]={0,1,2,0,1};
        for(int i=0;i<5;i++)assert(hit(k,100)==expected[i]);
        lg_destroy(k);
    }
    std::printf("Pad layers: velocity split picks soft/medium/hard layers, round robin plays them in turn, bad tables are refused\n");
}
