#include "GrillaKernel.h"
#include <array>
#include <atomic>
#include <cassert>
#include <thread>
#include <iostream>
int main(){
 auto*k=lg_create(48000);std::array<LGTrackMix,8> a{},b{};
 for(int i=0;i<8;i++){a[i]={0,-0.5f,i==0};b[i]={0,0.5f,i==1};}
 assert(lg_mix_snapshot(k,a.data(),8,0,-0.25f,0.125f));float left[32],right[32];lg_render(k,left,right,32);
 assert(lg_gain_target(k,0)==1&&lg_gain_target(k,1)==0);std::atomic<bool> done{false};
 std::thread producer([&]{for(int i=0;i<30000;i++){const auto &value=i%2?a:b;while(!lg_mix_snapshot(k,value.data(),8,0,i%2?-0.25f:0.25f,i%2?0.125f:0.25f)){}}done.store(true);});
 uint64_t previous=0;
 while(!done.load()){
  lg_render(k,left,right,32);auto revision=lg_mix_revision(k);assert(revision>=previous);previous=revision;
  bool first=lg_gain_target(k,0)==1;assert(lg_gain_target(k,1)==(first?0:1));assert(lg_pan_target(k,0)==(first?-0.5f:0.5f));assert(lg_filter_target(k)==(first?-0.25f:0.25f));assert(lg_delay_target(k)==(first?0.125f:0.25f));
 }
 producer.join();lg_render(k,left,right,32);assert(lg_mix_revision(k)==30001);
 // Panic wins over an already queued FX snapshot, even when Play follows before rendering.
 assert(lg_mix_snapshot(k,a.data(),8,0,1,0.5f));lg_panic(k);lg_play(k,1);lg_render(k,left,right,32);assert(lg_filter_target(k)==0&&lg_delay_target(k)==0);
 lg_destroy(k);std::cout<<"Mixer snapshots: coherent gain/pan/FX, 30,000 concurrent publications, monotonic ownership and panic priority passed\n";
}
