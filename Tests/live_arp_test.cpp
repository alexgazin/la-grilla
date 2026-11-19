// I15 live arpeggiator: the first note sounds at once, then each step lands on
// the transport grid; up / down / up-down / as-played orders and octaves are
// exact (checked through MIDI output note-ons); updating the held notes keeps
// the timing; count 0 stops.
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <vector>

namespace {
struct Hit {uint64_t time;int pitch;};
std::vector<Hit> run(LGKernel*k,LGMIDIHub*h,uint64_t&time,int frames){
    std::vector<float> l(512),r(512);std::vector<LGMIDIOutput> events(512);std::vector<Hit> hits;
    for(int pos=0;pos<frames;){const int n=std::min(512,frames-pos);lg_render_midi(k,h,time,48000,l.data(),r.data(),n);time+=uint64_t(n);pos+=n;
        const int count=lg_midi_output_pop(h,events.data(),512);for(int i=0;i<count;i++)if((events[i].status&0xF0)==0x90&&events[i].a>0)hits.push_back({events[i].hostTime,events[i].a});}
    return hits;
}
LGKernel*kernel(LGMIDIHub*h){
    auto*k=lg_create(48000);int32_t channels[]={0,9,1,2,3,4,5,6};lg_midi_output_configure(h,channels,8,1);
    std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,3,2,202}}};
    // Silent loop marker on track 0 at pitch 0 (ignored by run()).
    LGNote marker{0,1,0,1,0,-1,0};assert(lg_submit_project(k,&marker,1,120,0,3840*4,1,1,1,tracks.data(),2,-3,0,0));
    return k;
}
}

int main(){
    {
        auto*h=lg_midi_create();auto*k=kernel(h);
        const int32_t single[]={60},high[]={128};
        assert(!lg_arp(k,202,nullptr,1,240,0,1,100)&&!lg_arp(k,202,single,1,200,0,1,100)&&!lg_arp(k,202,single,1,240,4,1,100)&&!lg_arp(k,202,high,1,240,0,1,100)&&!lg_arp(k,0,single,1,240,0,1,100));
        lg_seek(k,0);uint64_t time=100000;run(k,h,time,1);lg_play(k,1);
        run(k,h,time,2499);                                  // ≈ tick 100
        const int32_t chord[]={67,60,64};
        assert(lg_arp(k,202,chord,3,240,0,2,100));             // up, two octaves
        auto hits=run(k,h,time,6000*7+100);
        // First note at once, then grid ticks 240·n → frames 6000·n after the transport origin (host 100001).
        assert(hits.size()==8);
        const int expected[]={60,64,67,72,76,79,60,64};
        for(size_t i=0;i<hits.size();i++){assert(hits[i].pitch==expected[i]);if(i>0)assert(hits[i].time==100001+6000*i);}
        // Changing the held notes keeps the grid.
        const int32_t two[]={62,65};assert(lg_arp(k,202,two,2,240,1,1,100));   // down
        auto next=run(k,h,time,12000);
        assert(next.size()==2&&next[0].time%6000==100001%6000&&next[0].pitch==65&&next[1].pitch==62);
        assert(lg_arp(k,202,nullptr,0,0,0,1,0));auto none=run(k,h,time,12000);assert(none.empty());
        lg_destroy(k);lg_midi_destroy(h);
    }
    {   // Up-down and as-played orders.
        auto*h=lg_midi_create();auto*k=kernel(h);lg_seek(k,0);uint64_t time=100000;run(k,h,time,1);lg_play(k,1);
        const int32_t played[]={64,60,67};
        assert(lg_arp(k,202,played,3,480,2,1,90));
        auto updown=run(k,h,time,12000*5+10);
        const int ping[]={60,64,67,64,60,64};assert(updown.size()==6);for(size_t i=0;i<6;i++)assert(updown[i].pitch==ping[i]);
        lg_arp(k,202,nullptr,0,0,0,1,0);run(k,h,time,100);
        assert(lg_arp(k,202,played,3,480,3,1,90));
        auto order=run(k,h,time,12000*2+10);assert(order.size()==3&&order[0].pitch==64&&order[1].pitch==60&&order[2].pitch==67);
        lg_destroy(k);lg_midi_destroy(h);
    }
    std::printf("Live arpeggiator: immediate first note then exact grid steps; up over two octaves, down, up-down and as-played orders; held-note changes keep the timing; stop is silent\n");
}
