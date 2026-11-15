#include "GrillaKernel.h"
#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>
#include <vector>
static thread_local bool insideRender=false;
static std::atomic<unsigned> renderAllocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(insideRender)renderAllocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}
int main(){
 constexpr double rate=48000;constexpr int block=256,seconds=12;
 for(int fixture=1;fixture<=3;fixture++){
  auto*k=lg_create(rate);std::vector<LGNote> notes;const int step=fixture==1?960:fixture==2?240:120,tracks=fixture==1?3:8;
  for(int t=0;t<tracks;t++){lg_preset_version(k,t,2);lg_mix(k,t,-20,float(t%3-1)*0.6f,1);for(int tick=0;tick<64*3840;tick+=step){const bool drum=t==1;notes.push_back({tick,std::min(fixture==1?960:1920,64*3840-tick),48+(tick/step+t)%36,90,t,drum?(tick/step)%16:-1,drum?1:t==2?2:3});}}
  assert(notes.size()<=32768);assert(lg_submit(k,notes.data(),int(notes.size()),123,0,64*3840,1,1));lg_master(k,-6);lg_play(k,1);
  std::vector<float> l(block),r(block);std::vector<double> times;times.reserve(int(rate)*seconds/block+1);float peak=0;
  for(int frame=0;frame<int(rate)*seconds;frame+=block){
   if(fixture==3&&frame%(block*8)==0){for(int i=0;i<16;i++)lg_pad(k,i,100);lg_effects(k,frame%(block*16)?0.8f:-0.8f,0.5f);}
   const auto begin=std::chrono::steady_clock::now();insideRender=true;lg_render(k,l.data(),r.data(),block);insideRender=false;
   times.push_back(std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-begin).count());
   for(int i=0;i<block;i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));peak=std::max({peak,std::abs(l[i]),std::abs(r[i])});}assert(peak<=0.98f);
  }
  assert(lg_overflows(k)==0);assert(renderAllocations==0);lg_panic(k);lg_render(k,l.data(),r.data(),block);for(float f:l)assert(f==0);lg_destroy(k);
  std::sort(times.begin(),times.end());double total=0;for(double t:times)total+=t;
  std::cout<<"{\"fixture\":\"P"<<fixture<<"\",\"hostOnly\":true,\"sampleRate\":"<<rate<<",\"blockFrames\":"<<block<<",\"notes\":"<<notes.size()<<",\"renderedSeconds\":"<<seconds<<",\"meanMicroseconds\":"<<total/times.size()<<",\"p95Microseconds\":"<<times[times.size()*95/100]<<",\"maxMicroseconds\":"<<times.back()<<",\"budgetMicroseconds\":"<<block/rate*1e6<<",\"renderAllocations\":"<<renderAllocations.load()<<",\"peak\":"<<peak<<"}\n";
 }
}
