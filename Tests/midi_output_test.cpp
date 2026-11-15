#include "GrillaKernel.h"
#include <cassert>
#include <algorithm>
#include <vector>
#include <iostream>
// A routing change must never chase a voice cancelled at this callback boundary.
static void destinationBoundary(bool panic, bool expired){
 auto*k=lg_create(48000);auto*h=lg_midi_create();int32_t channels[]={0,9,1,2,3,4,5,6};
 lg_midi_output_configure(h,channels,8,1);
 LGNote note{0,expired?1:240,60,100,0,-1,0};assert(lg_submit(k,&note,1,120,0,3840,0,1));lg_play(k,1);
 std::vector<float> l(512),r(512);std::vector<LGMIDIOutput> events(512);
 const int frames=expired?25:512;lg_render_midi(k,h,100000,48000,l.data(),r.data(),frames);
 assert(lg_midi_output_pop(h,events.data(),512)==1); // Initial NoteOn.
 const auto epoch=lg_midi_output_configure(h,channels,8,1);
 if(!expired){if(panic)lg_panic(k);else lg_play(k,0);}
 lg_render_midi(k,h,100000+frames,48000,l.data(),r.data(),1);
 const int count=lg_midi_output_pop(h,events.data(),512);bool flush=false;
 for(int i=0;i<count;i++){assert(events[i].epoch==epoch);assert((events[i].status&0xf0)!=0x90);flush|=events[i].status==0;}
 if(!expired)assert(flush);
 lg_destroy(k);lg_midi_destroy(h);
}
static void adjacentGates(){
 auto*k=lg_create(48000);auto*h=lg_midi_create();int32_t channels[]={0,9,1,2,3,4,5,6};
 lg_midi_output_configure(h,channels,8,1);
 LGNote notes[]={{0,1,60,100,0,-1,0},{1,1,60,90,0,-1,0}};assert(lg_submit(k,notes,2,120,0,3840,0,1));lg_play(k,1);
 float l[51],r[51];lg_render_midi(k,h,100000,48000,l,r,51);
 LGMIDIOutput events[8];const int count=lg_midi_output_pop(h,events,8);assert(count==4);
 const int status[]={0x90,0x80,0x90,0x80};const uint64_t time[]={100000,100025,100025,100050};
 for(int i=0;i<count;i++){assert(events[i].status==status[i]);assert(events[i].a==60);assert(events[i].hostTime==time[i]);}
 lg_destroy(k);lg_midi_destroy(h);
}
int main(){
 destinationBoundary(false,false);destinationBoundary(true,false);destinationBoundary(false,true);adjacentGates();
 auto*k=lg_create(48000);auto*h=lg_midi_create();int32_t channels[]={0,9,1,2,3,4,5,6};auto epoch=lg_midi_output_configure(h,channels,8,1);assert(epoch);
 LGNote notes[]={{0,240,60,100,0,-1,0},{120,120,37,90,1,5,1}};assert(lg_submit(k,notes,2,120,0,3840,1,1));lg_play(k,1);
 std::vector<float> l(512),r(512);uint64_t time=100000;for(int pos=0;pos<7000;){int n=std::min(512,7000-pos);lg_render_midi(k,h,time+pos,48000,l.data(),r.data(),n);pos+=n;}
 std::vector<LGMIDIOutput> events(512);auto count=lg_midi_output_pop(h,events.data(),512);bool on=false,off=false,drum=false;
 for(int i=0;i<count;i++){auto e=events[i];assert(e.epoch==epoch);if(e.status==0x90&&e.a==60){assert(e.hostTime==100000&&e.b==100);on=true;}if(e.status==0x80&&e.a==60){assert(e.hostTime==106000);off=true;}if(e.status==0x99&&e.a==37){assert(e.hostTime==103000&&e.b==90);drum=true;}}
 assert(on&&off&&drum);
 // Incoming notes are audible locally but never echoed to the output endpoint.
 lg_midi_configure(h,256,0,0,65535);uint8_t input[]={0x90,72,110};assert(lg_midi_push(h,256,107010,input,3));lg_render_midi(k,h,107000,48000,l.data(),r.data(),512);count=lg_midi_output_pop(h,events.data(),512);for(int i=0;i<count;i++)assert(events[i].a!=72);
 // A destination generation change chases active project voices, not input voices.
 auto next=lg_midi_output_configure(h,channels,8,1);assert(next!=epoch);lg_render_midi(k,h,107512,48000,l.data(),r.data(),512);count=lg_midi_output_pop(h,events.data(),512);for(int i=0;i<count;i++){assert(events[i].epoch==next);assert(events[i].a!=72);}
 lg_panic(k);lg_render_midi(k,h,108024,48000,l.data(),r.data(),512);count=lg_midi_output_pop(h,events.data(),512);bool flush=false;for(int i=0;i<count;i++)if(events[i].status==0)flush=true;assert(flush);
 lg_destroy(k);lg_midi_destroy(h);std::cout<<"MIDI output: exact note timestamps, GM/channel routing, NoteOff, destination epochs, no input feedback, panic flush, boundary routing and Off-before-On passed\n";
}
