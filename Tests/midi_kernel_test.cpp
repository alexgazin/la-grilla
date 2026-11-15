#include "GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <vector>
#include <iostream>
int main(){
 auto*k=lg_create(48000);auto*h=lg_midi_create();assert(lg_submit(k,nullptr,0,120,0,3840,1,1));lg_midi_configure(h,256,0,0,65535);
 uint8_t note[]={0x90,60,110},pedal[]={0xb0,64,127},off[]={0x80,60,0},release[]={0xb0,64,0};
 assert(lg_midi_push(h,256,100,note,3));assert(lg_midi_push(h,256,200,pedal,3));assert(lg_midi_push(h,256,300,off,3));assert(lg_midi_push(h,256,800,release,3));
 lg_perform_begin(k,1,1,1,96000);std::vector<float> l(512),r(512),capturedL,capturedR;
 for(int pos=0;pos<1536;pos+=512){lg_render_midi(k,h,pos,48000,l.data(),r.data(),512);capturedL.insert(capturedL.end(),l.begin(),l.end());capturedR.insert(capturedR.end(),r.begin(),r.end());}
 for(int i=0;i<100;i++){assert(capturedL[i]==0);}
 float held=0;for(int i=500;i<800;i++)held=std::max(held,std::abs(capturedL[i]));assert(held>0.01f);for(int i=1200;i<1536;i++)assert(capturedL[i]==0);
 lg_perform_record_stop(k);lg_render_midi(k,h,1536,48000,l.data(),r.data(),512);
 std::vector<LGPerformanceEvent> events(512);int count=lg_perform_pop(k,events.data(),512);assert(count==5);assert(events[1].kind==10&&events[1].frame==100);assert(events[2].kind==12&&events[2].frame==200);assert(events[3].kind==11&&events[3].frame==300);assert(events[4].kind==12&&events[4].frame==800);events[0].a=0;events[0].b=3840;
 auto*replay=lg_create(48000);assert(lg_submit(replay,nullptr,0,120,0,3840,1,1));assert(lg_perform_replay_submit(replay,events.data(),count,1536,2));lg_perform_begin(replay,1,2,0,0);
 float difference=0;for(int pos=0;pos<1536;){int n=std::min(257,1536-pos);lg_render(replay,l.data(),r.data(),n);for(int i=0;i<n;i++)difference=std::max(difference,std::max(std::abs(l[i]-capturedL[pos+i]),std::abs(r[i]-capturedR[pos+i])));pos+=n;}assert(difference<1e-6f);
 // Input continues across source-loop boundaries and disconnect releases that source.
 lg_midi_push(h,256,100,note,3);lg_render_midi(k,h,2048,48000,l.data(),r.data(),512);assert(lg_midi_late(h)>0);lg_midi_disconnect(h,0);lg_render_midi(k,h,2560,48000,l.data(),r.data(),512);lg_render_midi(k,h,3072,48000,l.data(),r.data(),512);for(float f:l)assert(f==0);
 lg_midi_configure(h,768,0,0,65535);lg_midi_configure(h,257,2,2,65535);lg_mix(k,0,0,-1,1);lg_mix(k,2,0,1,1);
 uint8_t other[]={0x90,67,110};lg_midi_push(h,768,4000,note,3);lg_midi_push(h,257,4000,other,3);
 for(int i=0;i<10;i++)lg_render_midi(k,h,4000+i*512,48000,l.data(),r.data(),512);
 lg_midi_disconnect(h,0);for(int i=0;i<10;i++)lg_render_midi(k,h,9120+i*512,48000,l.data(),r.data(),512);
 float leftPeak=0,rightPeak=0;for(int i=0;i<512;i++){leftPeak=std::max(leftPeak,std::abs(l[i]));rightPeak=std::max(rightPeak,std::abs(r[i]));}assert(leftPeak<1e-5f&&rightPeak>0.001f);
 lg_destroy(replay);lg_destroy(k);lg_midi_destroy(h);std::cout<<"MIDI sample timestamps, sustain/NoteOff, source disconnect and finite take PCM replay passed\n";
}
