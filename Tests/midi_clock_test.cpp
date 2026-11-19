// I82 MIDI clock out: Start, then 24 clocks per quarter note sample-timed with
// the transport (120 BPM: one clock every 1000 frames at 48 kHz), Stop when the
// transport stops, Song Position + Continue when starting mid-song, nothing when off.
#include "GrillaKernel.h"
#include <cassert>
#include <cstdio>
#include <vector>

namespace {
std::vector<LGMIDIOutput> run(LGKernel*k,LGMIDIHub*h,uint64_t&time,int frames){
    std::vector<float> l(512),r(512);std::vector<LGMIDIOutput> all,events(512);
    for(int pos=0;pos<frames;){const int n=std::min(512,frames-pos);lg_render_midi(k,h,time,48000,l.data(),r.data(),n);time+=uint64_t(n);pos+=n;
        const int count=lg_midi_output_pop(h,events.data(),512);all.insert(all.end(),events.begin(),events.begin()+count);}
    return all;
}
}

int main(){
    int32_t channels[]={0,9,1,2,3,4,5,6};
    {
        auto*k=lg_create(48000);auto*h=lg_midi_create();lg_midi_output_configure(h,channels,8,1);
        LGNote note{0,1,60,1,0,-1,0};assert(lg_submit(k,&note,1,120,0,3840*4,1,1));
        lg_midi_clock_out(k,1);lg_play(k,1);uint64_t time=100000;
        auto events=run(k,h,time,48000);                    // one second = 2 beats
        std::vector<uint64_t> clocks;bool start=false;
        for(auto&e:events){if(e.status==0xFA){assert(clocks.empty()&&e.hostTime==100000);start=true;}if(e.status==0xF8)clocks.push_back(e.hostTime);}
        assert(start&&clocks.size()==48);
        for(size_t i=0;i<clocks.size();i++)assert(clocks[i]==100000+1000*i);
        lg_play(k,0);auto stop=run(k,h,time,512);bool stopped=false;for(auto&e:stop){assert(e.status!=0xF8);stopped|=e.status==0xFC;}assert(stopped);
        // Starting from beat 3: Song Position (in 16ths) then Continue.
        lg_seek(k,1920);lg_play(k,1);auto resume=run(k,h,time,2000);
        int spp=-1;bool cont=false;for(auto&e:resume){if(e.status==0xF2)spp=e.a|(e.b<<7);if(e.status==0xFB){assert(spp>=0);cont=true;}}
        assert(spp==8&&cont);
        // Off: no clock traffic at all.
        lg_midi_clock_out(k,0);auto off=run(k,h,time,4000);for(auto&e:off)assert(e.status!=0xF8&&e.status!=0xFA);
        lg_destroy(k);lg_midi_destroy(h);
    }
    std::printf("MIDI clock: Start + 48 clocks/second at 120 BPM exactly every 1000 frames, Stop, Song Position + Continue mid-song, silent when off\n");
}
