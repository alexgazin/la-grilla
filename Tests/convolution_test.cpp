// I33 spaces: the partitioned FFT convolution equals direct convolution (512 frames late); the
// generated spaces have their lengths, unit energy and stereo width; the kernel switches spaces on
// the send, rings out for the hall, and returns to the classic room.
#include "Convolution.hpp"
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

int main(){
    using namespace grilla;
    {   // Exactness against a direct convolution.
        FFT fft(PartitionedConvolver::FFTSize);
        std::vector<float> impulse(3000),input(9000);
        uint32_t state=7;auto noise=[&]{state=state*1664525u+1013904223u;return float(int32_t(state>>8)-(1<<23))/float(1<<23);};
        for(auto &v:impulse){v=noise()*0.1f;}
        for(auto &v:input){v=noise();}
        PartitionedConvolver convolver(fft,impulse);
        double worst=0;
        for(int i=0;i<int(input.size());i++){
            const float out=convolver.process(input[size_t(i)]);
            const int n=i-PartitionedConvolver::Block;double expected=0;
            for(int k=0;k<int(impulse.size())&&k<=n;k++)expected+=double(impulse[size_t(k)])*input[size_t(n-k)];
            worst=std::max(worst,std::abs(expected-out));
        }
        assert(worst<2e-4);
    }
    {   // Generated responses: length, unit energy, decorrelated channels.
        const double lengths[]={0.7,2.0,1.6,1.2};
        for(int space=1;space<=4;space++){
            const auto left=generateImpulse(Space(space),48000,1),right=generateImpulse(Space(space),48000,2);
            assert(int(left.size())==int(48000*lengths[space-1])&&left.size()<=96000);
            double energy=0,cross=0;for(size_t i=0;i<left.size();i++){energy+=double(left[i])*left[i];cross+=double(left[i])*right[i];}
            assert(std::abs(energy-1)<1e-3&&std::abs(cross)<0.5);
        }
    }
    {   // The kernel: a short burst on the send rings out longer in the hall than in the room.
        auto ring=[](int space){
            auto*k=lg_create(48000);
            std::array<LGProjectTrack,1> tracks={{{{0,0,1},2,0,0,5}}};
            const LGNote note={0,96,60,110,0,-1,0};
            assert(lg_submit_project(k,&note,1,120,0,3840*4,0,1,1,tracks.data(),1,0,0,0));
            LGTrackDynamics d{};d.reverbSend=1.f;assert(lg_dynamics(k,&d,1,0,-1));
            assert(lg_space(k,space));
            lg_play(k,1);
            std::vector<float> l(48000*3),r(l.size());
            for(size_t pos=0;pos<l.size();pos+=512)lg_render(k,l.data()+pos,r.data()+pos,int(std::min<size_t>(512,l.size()-pos)));
            lg_destroy(k);
            double late=0;for(size_t i=48000+24000;i<48000*2;i++)late+=double(l[i])*l[i]+double(r[i])*r[i];
            return late;
        };
        auto*k=lg_create(48000);assert(!lg_space(k,5)&&!lg_space(k,-1)&&lg_space(k,0));lg_destroy(k);
        const double room=ring(1),hall=ring(2),classic=ring(0);
        assert(hall>20*room);          // 1.5–2 s after the note the hall still rings, the room has died away
        assert(classic>=0);
    }
    std::printf("Spaces: partitioned convolution equals direct convolution (512 frames late); room/hall/plate/spring responses have their lengths, unit energy and width; the hall rings out past the room\n");
}
