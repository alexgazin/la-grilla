#include "MIDIHub.hpp"
#include <cassert>
#include <vector>
#include <iostream>
int main(){
 auto*h=lg_midi_create();assert(h);lg_midi_configure(h,256,0,0,65535);
 int clears=0;h->prepare([&](int s){assert(s==0);clears++;});assert(clears==1);
 uint8_t bytes[]={0x90,60,100,61,90,0xf8,60,0,0xb0,64,127};assert(lg_midi_push(h,256,1000,bytes,sizeof(bytes)));
 h->prepare([](int){assert(false);});std::vector<LGMIDIEvent> events;
 h->due(999,10,[&](auto e){events.push_back(e);});assert(events.empty());h->due(1000,10,[&](auto e){events.push_back(e);});assert(events.size()==4);assert(events[2].status==8);assert(events[3].status==11);
 uint8_t first[]={0x91,72};uint8_t second[]={110};assert(lg_midi_push(h,256,2000,first,2));assert(lg_midi_push(h,256,2100,second,1));h->prepare([](int){});h->due(2100,10,[&](auto e){assert(e.channel==1&&e.a==72&&e.b==110);});
 lg_midi_disconnect(h,0);h->prepare([&](int){clears++;});assert(clears==2);
 assert(!lg_midi_push(h,256,0,bytes,sizeof(bytes)));h->prepare([](int){});h->due(9999,10,[](auto){assert(false);});
 lg_midi_configure(h,512,0,0,1);h->prepare([](int){});
 uint8_t sysex[]={0xf0,1,2,0xf8,3,0xf7,0x90,64,100};assert(lg_midi_push(h,512,3000,sysex,sizeof(sysex)));h->prepare([](int){});int valid=0;h->due(3000,1,[&](auto e){assert(e.a==64);valid++;});assert(valid==1);
 uint8_t filtered[]={0x91,65,100};lg_midi_push(h,512,4000,filtered,3);h->prepare([](int){});h->due(4000,1,[](auto){assert(false);});
 uint8_t single[]={0x90,66,100};for(int i=0;i<1030;i++)lg_midi_push(h,512,5000,single,3);
 assert(lg_midi_dropped(h)>0);assert(!lg_midi_connected(h,512));h->prepare([&](int){clears++;});h->due(9999,1,[](auto){assert(false);});
 lg_midi_destroy(h);std::cout<<"MIDI bounded parser, running status, packet split, velocity-zero and stale generation passed\n";
}
