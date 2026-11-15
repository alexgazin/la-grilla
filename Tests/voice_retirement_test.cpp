#include "GrillaKernel.h"
#include <vector>
#include <cmath>
#include <cassert>
#include <iostream>
int main(){
 for(double rate:{44100.,48000.,96000.,192000.}){
  auto*k=lg_create(rate);lg_preset_version(k,0,2);LGNote n={0,38400,64,110,0,-1,0};assert(lg_submit(k,&n,1,120,0,38400,1,1));lg_play(k,1);
  std::vector<float> l(512),r(512);for(int i=0;i<31;i++)lg_render(k,l.data(),r.data(),512);
  const float previous=l.back();assert(std::abs(previous)>0.00001f);lg_seek(k,3840);lg_render(k,l.data(),r.data(),512);
  assert(std::abs(l[0]-previous)<0.00005f);for(float f:l)assert(std::isfinite(f)&&std::abs(f)<=0.98f);
  // Saturate/steal voices, then choke hats. Retirement storage stays bounded.
  for(int pass=0;pass<40;pass++){for(int i=0;i<80;i++)lg_note_preview(k,40+i%48,0,3);lg_pad(k,3,110);lg_pad(k,2,110);lg_render(k,l.data(),r.data(),512);for(float f:l)assert(std::isfinite(f)&&std::abs(f)<=0.98f);}
  lg_panic(k);lg_render(k,l.data(),r.data(),512);for(float f:l)assert(f==0);for(float f:r)assert(f==0);lg_destroy(k);
 }
 std::cout<<"Voice retirement: v2 seek continuity, bounded stealing/choke tails, and immediate panic silence at 44.1–192 kHz passed\n";
}
