#include "../AudioRuntime/GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
int main(){
 auto*k=lg_create(48000); std::vector<float> l(512),r(512);
 LGNote n[]={{0,3840,60,100,0,-1},{3840,3840,57,100,0,-1},{0,120,36,100,1,0}};
 assert(lg_submit(k,n,3,120,0,15360,1,1));lg_play(k,1);float peak=0;
 for(int i=0;i<750;i++){lg_render(k,l.data(),r.data(),512);for(float f:l){assert(std::isfinite(f));peak=std::max(peak,std::abs(f));}}
 assert(peak>0.02&&peak<=0.98);assert(lg_tick(k)>15359&&lg_tick(k)<15360);
 lg_render(k,l.data(),r.data(),512);assert(lg_tick(k)<30);assert(lg_revision(k)==1);
 assert(lg_submit(k,n,3,100,0,15360,1,2));lg_render(k,l.data(),r.data(),512);assert(lg_revision(k)==1);
 for(int i=0;i<200;i++){lg_render(k,l.data(),r.data(),512);}assert(lg_revision(k)==2);
 lg_play(k,0);lg_render(k,l.data(),r.data(),512);for(float f:l)assert(f==0);assert(!lg_playing(k));
 lg_pad(k,0,100);lg_render(k,l.data(),r.data(),512);peak=0;for(float f:l)peak=std::max(peak,std::abs(f));assert(peak>0.001);
 for(int i=0;i<300;i++){lg_pad(k,2,100);}assert(lg_overflows(k)>0);
 lg_play(k,0);lg_render(k,l.data(),r.data(),512);assert(!lg_submit(k,n,3,0,0,1,1,9));lg_destroy(k);
 // Long clock: tick stays derived from a stable sample anchor after 10 minutes.
 k=lg_create(44100); assert(lg_submit(k,n,3,123,0,15360,1,1));lg_play(k,1);
 int frames=44100*60*10;for(int f=0;f<frames;f+=512)lg_render(k,l.data(),r.data(),std::min(512,frames-f));
 double expected=std::fmod((frames-1)*123.0*960/(60*44100),15360);assert(std::abs(lg_tick(k)-expected)<0.1);lg_destroy(k);
 std::cout<<"Kernel: render, loop boundary, pending revision, stop, pad, overflow, 10 minute clock passed\n";
}
