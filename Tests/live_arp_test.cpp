// I15 live arpeggiator: the first note sounds at once, then each step lands on
// the transport grid; up / down / up-down / as-played orders and octaves are
// exact (checked through MIDI output note-ons); updating the held notes keeps
// the timing; count 0 stops.
#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
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
        assert(!lg_arp(k,202,nullptr,1,240,0,1,100)&&!lg_arp(k,202,single,1,200,0,1,100)&&!lg_arp(k,202,single,1,240,6,1,100)&&!lg_arp(k,202,high,1,240,0,1,100)&&!lg_arp(k,0,single,1,240,0,1,100));
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
    {   // I16 pitch bend: zero is bit-identical; +12 semitones doubles the pitch of the bent track only.
        auto render=[](float semis,float mod,bool call){
            auto*k=lg_create(48000);
            std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,3,2,202}}};
            LGNote note{0,3840,57,100,1,-1,3};assert(lg_submit_project(k,&note,1,120,0,3840*2,0,1,1,tracks.data(),2,-3,0,0));
            lg_seek(k,0);std::vector<float> l(48000),r(48000);lg_render(k,l.data(),r.data(),1);lg_play(k,1);
            if(call)lg_pitch_bend(k,202,semis,mod);
            for(int pos=0;pos<48000;pos+=512)lg_render(k,l.data()+pos,r.data()+pos,std::min(512,48000-pos));
            lg_destroy(k);return l;
        };
        auto crossings=[](const std::vector<float>&v){int c=0;for(size_t i=9601;i<33600;i++)if(v[i-1]<0&&v[i]>=0)c++;return c;};
        const auto plain=render(0,0,false),zero=render(0,0,true),octave=render(12,0,true),vibrato=render(0,1,true);
        assert(plain==zero);
        const double ratio=double(crossings(octave))/double(crossings(plain));
        assert(std::abs(ratio-2)<0.05);
        assert(vibrato!=plain&&std::abs(double(crossings(vibrato))/double(crossings(plain))-1)<0.03);
    }
    {   // I29: a custom pattern — note indices, a rest that keeps the grid, an octave up.
        auto*h=lg_midi_create();auto*k=kernel(h);lg_seek(k,0);uint64_t time=100000;run(k,h,time,1);lg_play(k,1);
        const int32_t bad[]={3*16},badNote[]={-2};assert(!lg_arp_pattern(k,bad,1)&&!lg_arp_pattern(k,badNote,1)&&!lg_arp_pattern(k,nullptr,2));
        const int32_t pattern[]={0,2,-1,1+16};
        assert(lg_arp_pattern(k,pattern,4));
        const int32_t chord[]={67,60,64};
        assert(lg_arp(k,202,chord,3,480,4,1,90));
        auto hits=run(k,h,time,12000*7+10);
        const int expected[]={60,67,76,60,67,76};
        assert(hits.size()==6);
        for(size_t i=0;i<6;i++)assert(hits[i].pitch==expected[i]);
        for(size_t i=1;i<6;i++)assert((hits[i].time-100001)%12000==0);
        assert(hits[2].time-hits[1].time==24000&&hits[5].time-hits[4].time==24000);   // the rests
        // A new pattern takes over on the same grid; an empty one silences mode 4.
        const int32_t up[]={0,1};assert(lg_arp_pattern(k,up,2));
        auto next=run(k,h,time,12000*2);assert(next.size()==2);
        assert(lg_arp_pattern(k,nullptr,0));auto silent=run(k,h,time,12000*2);assert(silent.empty());
        lg_destroy(k);lg_midi_destroy(h);
    }

    {   // 55: a quarter-note rate, a random order that only plays held notes and restarts the
        // same way, and the gate that shortens each note within its step.
        auto*h=lg_midi_create();auto*k=kernel(h);lg_seek(k,0);uint64_t time=100000;run(k,h,time,1);lg_play(k,1);
        const int32_t chord[]={60,64,67,71};
        assert(lg_arp(k,202,chord,4,960,0,1,90));
        auto quarters=run(k,h,time,24000*3+10);
        assert(quarters.size()==4);for(size_t i=1;i<4;i++)assert((quarters[i].time-100001)%24000==0&&quarters[i].time-quarters[i-1].time==24000);
        lg_arp(k,202,nullptr,0,0,0,1,0);run(k,h,time,100);
        assert(lg_arp(k,202,chord,4,240,5,2,90));
        auto first=run(k,h,time,6000*15+10);
        assert(first.size()==16);
        bool ascending=true;
        for(size_t i=0;i<first.size();i++){
            const int p=first[i].pitch;assert(p==60||p==64||p==67||p==71||p==72||p==76||p==79||p==83);
            if(i>0&&first[i].pitch<first[i-1].pitch)ascending=false;
        }
        assert(!ascending);
        lg_arp(k,202,nullptr,0,0,0,1,0);run(k,h,time,100);
        assert(lg_arp(k,202,chord,4,240,5,2,90));
        auto again=run(k,h,time,6000*15+10);
        assert(again.size()==16);for(size_t i=0;i<16;i++)assert(again[i].pitch==first[i].pitch);
        lg_arp(k,202,nullptr,0,0,0,1,0);run(k,h,time,100);
        lg_destroy(k);lg_midi_destroy(h);
    }
    {   // Gate: rejected out of range; a shorter gate gives a shorter sounding note (rendered audio).
        auto*k0=lg_create(48000);assert(!lg_arp_gate(k0,0.05f)&&!lg_arp_gate(k0,1.5f)&&!lg_arp_gate(k0,NAN)&&lg_arp_gate(k0,1.0f));lg_destroy(k0);
        auto sounding=[](float gate){
            auto*k=lg_create(48000);
            std::array<LGProjectTrack,2> tracks{{{{-6,0,1},2,0,0,101},{{-6,0,1},2,3,2,202}}};
            LGNote marker{0,1,0,1,0,-1,0};assert(lg_submit_project(k,&marker,1,120,0,3840*4,1,1,1,tracks.data(),2,-3,0,0));
            assert(lg_arp_gate(k,gate));
            std::vector<float> l(512),r(512);lg_seek(k,0);lg_render(k,l.data(),r.data(),1);lg_play(k,1);
            const int32_t one[]={69};assert(lg_arp(k,202,one,1,960,0,1,100));
            // Count blocks with sound during the first quarter-note step (24000 frames).
            int loud=0;for(int pos=0;pos<24000;pos+=512){lg_render(k,l.data(),r.data(),512);float peak=0;for(float v:l)peak=std::max(peak,std::fabs(v));if(peak>0.01f)loud++;}
            lg_destroy(k);return loud;
        };
        const int short_=sounding(0.25f),long_=sounding(1.0f);
        assert(short_>0&&long_>short_+15);
    }

    std::printf("Arpeggio pattern: note indices, rests keep the grid, octave steps, a new pattern on the same grid, empty silences\n");
    std::printf("Pitch bend: zero is bit-identical, +12 semitones doubles the pitch, vibrato keeps the centre pitch\n");
    std::printf("Live arpeggiator (55): quarter-note steps, a random order of held notes that restarts the same way, gate rejects out-of-range values and shortens notes\n");
    std::printf("Live arpeggiator: immediate first note then exact grid steps; up over two octaves, down, up-down and as-played orders; held-note changes keep the timing; stop is silent\n");
}
