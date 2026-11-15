#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>
#include <vector>
#include <thread>

static thread_local bool insideStartupRender=false;
static std::atomic<unsigned> startupRenderAllocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(insideStartupRender)startupRenderAllocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}

static float startupRender(LGKernel*k,int frames,bool silent=false){
 std::array<float,1024> left{},right{};assert(frames>0&&frames<=int(left.size()));
 const auto before=lg_clock(k);insideStartupRender=true;lg_render(k,left.data(),right.data(),frames);insideStartupRender=false;
 assert(lg_clock(k)==before+uint64_t(frames));float peak=0;
 for(int i=0;i<frames;i++){assert(std::isfinite(left[i])&&std::isfinite(right[i]));if(silent)assert(left[i]==0&&right[i]==0);peak=std::max(peak,std::max(std::abs(left[i]),std::abs(right[i])));}
 return peak;
}
static void startupAdvance(LGKernel*k,int frames,bool silent=false){while(frames>0){const int count=std::min(frames,1024);startupRender(k,count,silent);frames-=count;}}

static void firstSnapshotPlayAndCountIn(){
 for(const double rate:{44100.0,48000.0,96000.0}){
  auto*k=lg_create(rate);const int position=4800;const LGNote note={position,960,60,100,0,-1,0};
  const LGTrackMix mix={-6,1,1};assert(lg_mix_snapshot(k,&mix,1,0,0,0));
  lg_seek(k,position);lg_countin(k,32);lg_play(k,1);
  for(int i=0;i<8;i++){startupRender(k,257,true);assert(!lg_playing(k)&&lg_revision(k)==-1&&lg_tick(k)==position&&lg_countremaining(k)==0);}
  assert(!lg_submit(k,&note,1,0,3840,7680,0,0));startupRender(k,64,true);
  // Revision zero and a nonzero range are valid legacy inputs. The waiting
  // count-in uses their adopted tempo, then music starts from the held seek.
  assert(lg_submit(k,&note,1,120,3840,7680,0,0));startupRender(k,32,true);
  assert(lg_playing(k)&&lg_revision(k)==0&&lg_tick(k)==position&&lg_countremaining(k)==0);
  assert(std::abs(lg_gain_target(k,0)-std::pow(10.f,-6.f/20))<1e-6f&&lg_pan_target(k,0)==1);
  assert(startupRender(k,512)>0.001f);lg_destroy(k);
 }
}

static void initialPlayCancellation(){
 const LGNote note={0,3840,60,100,0,-1,0};
 for(int cancel=0;cancel<3;cancel++){
  auto*k=lg_create(48000);lg_seek(k,1234);
  if(cancel<2)lg_countin(k,4096);
  lg_play(k,1);startupRender(k,257,true);assert(!lg_playing(k)&&lg_tick(k)==1234);
  if(cancel==0)lg_play(k,0);else if(cancel==1)lg_panic(k);else lg_perform_finalize_paused(k);
  startupRender(k,257,true);assert(lg_countremaining(k)==0);
  assert(lg_submit(k,&note,1,120,0,3840,1,0));startupAdvance(k,4096,true);
  assert(lg_revision(k)==0&&!lg_playing(k)&&lg_tick(k)==1234&&lg_countremaining(k)==0);
  lg_play(k,1);assert(startupRender(k,512)>0.001f&&lg_playing(k));lg_destroy(k);
 }
 // A fresh positive command after Panic still has the same latest-request
 // behavior as an initialized kernel, even before its first project exists.
 auto*k=lg_create(48000);lg_play(k,1);startupRender(k,64,true);lg_panic(k);lg_play(k,1);
 startupRender(k,64,true);assert(lg_submit(k,&note,1,120,0,3840,1,0));
 assert(startupRender(k,512)>0.001f&&lg_playing(k));lg_destroy(k);
}

static void initialEmptyAndFiniteEnd(){
 auto*k=lg_create(48000);lg_play(k,1);startupAdvance(k,1024,true);
 // Empty notes/tracks still form a valid project; silence is not a reason to
 // leave its transport stopped or to restart it after its natural end.
 assert(lg_submit_project(k,nullptr,0,240,0,3840,0,0,1,nullptr,0,0,0,0));
 startupRender(k,64,true);assert(lg_playing(k)&&lg_revision(k)==0&&lg_tick(k)>0);
 startupAdvance(k,48000,true);assert(!lg_playing(k)&&lg_tick(k)==3840);
 assert(lg_submit_project(k,nullptr,0,240,0,3840,0,1,1,nullptr,0,0,0,0));
 startupAdvance(k,4096,true);assert(!lg_playing(k)&&lg_revision(k)==1);lg_destroy(k);

 k=lg_create(48000);lg_seek(k,3840);lg_play(k,1);startupRender(k,64,true);
 const LGNote note={3840,960,60,100,0,-1,0};
 assert(lg_submit(k,&note,1,240,3840,4800,0,0));assert(startupRender(k,512)>0.001f);
 startupAdvance(k,12000);assert(!lg_playing(k)&&lg_tick(k)==4800);
 assert(lg_submit(k,&note,1,240,3840,5760,0,1));startupAdvance(k,4096,true);
 assert(!lg_playing(k)&&lg_revision(k)==1);
 lg_seek(k,3840);startupRender(k,512,true);assert(!lg_playing(k)&&lg_tick(k)==3840);
 lg_play(k,1);assert(startupRender(k,512)>0.001f&&lg_playing(k));lg_destroy(k);
}

static void concurrentInitialPublications(){
 const LGNote note={0,15360,60,110,0,-1,3};
 const LGProjectTrack track={{0,0,1},2,3,2,1};const LGTrackMix finalMix={-12,-1,1};
 for(int trial=0;trial<96;trial++){
  auto*k=lg_create(48000);
  auto publish=[&](const LGNote*notes,int count,int revision){return lg_submit_project(k,notes,count,120,0,15360,1,revision,1,&track,1,0,0,0);};
  assert(publish(&note,1,1));lg_play(k,1);
  std::vector<LGNote> notes(trial%2?1:1024,note);std::atomic<bool> ready{false},go{false};
  // The sole serialized control owner hands over to the producer. Waiting and
  // thread allocation stay outside the measured real-time rendering section.
  std::thread producer([&]{
   ready.store(true,std::memory_order_release);while(!go.load(std::memory_order_acquire))std::this_thread::yield();
   for(int revision=2;revision<=129;revision++)assert(publish(notes.data(),int(notes.size()),revision));
   assert(lg_mix_snapshot_for_revision(k,&finalMix,1,-6,0,0,129));
   if(trial%3==0)lg_play(k,0);else if(trial%3==1)lg_panic(k);
  });
  while(!ready.load(std::memory_order_acquire)){std::this_thread::yield();}
  go.store(true,std::memory_order_release);
  if(trial%4==1)std::this_thread::yield();else if(trial%4==2)std::this_thread::sleep_for(std::chrono::microseconds(10));else if(trial%4==3)std::this_thread::sleep_for(std::chrono::microseconds(50));
  float peak=0;for(int i=0;i<4;i++)peak=std::max(peak,startupRender(k,64));
  producer.join();for(int i=0;i<8;i++)peak=std::max(peak,startupRender(k,257));
  if(trial%3==2)assert(lg_playing(k)&&peak>0.000001f);else{assert(!lg_playing(k));startupRender(k,512,true);}
  // Only after checking the original Play, force latest-layout adoption to
  // inspect its version-scoped mixer. Seek must never repair a lost start.
  lg_seek(k,0);startupRender(k,257,trial%3!=2);assert(lg_revision(k)==129);
  assert(std::abs(lg_gain_target(k,0)-std::pow(10.f,-12.f/20))<1e-6f&&lg_pan_target(k,0)==-1);
  assert(std::abs(lg_gain_target(k,8)-std::pow(10.f,-6.f/20))<1e-6f);
  assert(bool(lg_playing(k))==(trial%3==2));lg_destroy(k);
 }
}

int main(){
 firstSnapshotPlayAndCountIn();initialPlayCancellation();initialEmptyAndFiniteEnd();concurrentInitialPublications();assert(startupRenderAllocations==0);
 assert(lg_create(0)==nullptr);
 auto*k=lg_create(48000); std::vector<float> l(512),r(512);
 LGNote n[]={{0,3840,60,100,0,-1,0},{3840,3840,57,100,0,-1,0},{0,120,36,100,1,0,1}};
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
 // Stop with a pending musical revision must not chase a sounding chord.
 k=lg_create(48000);assert(lg_submit(k,n,3,120,0,15360,1,1));lg_play(k,1);
 for(int i=0;i<40;i++){lg_render(k,l.data(),r.data(),512);}
 assert(lg_submit(k,n,3,120,0,15360,1,2));lg_play(k,0);lg_render(k,l.data(),r.data(),512);
 for(float f:l)assert(f==0);
 lg_seek(k,1000);lg_render(k,l.data(),r.data(),512);for(float f:l)assert(f==0);
 lg_play(k,1);lg_render(k,l.data(),r.data(),512);peak=0;for(float f:l)peak=std::max(peak,std::abs(f));assert(peak>0.001);lg_destroy(k);
 // Long clock: tick stays derived from a stable sample anchor after 10 minutes.
 k=lg_create(44100); assert(lg_submit(k,n,3,123,0,15360,1,1));lg_play(k,1);
 int frames=44100*60*10;for(int f=0;f<frames;f+=512)lg_render(k,l.data(),r.data(),std::min(512,frames-f));
 double expected=std::fmod((frames-1)*123.0*960/(60*44100),15360);assert(std::abs(lg_tick(k)-expected)<0.1);lg_destroy(k);
 k=lg_create(48000); assert(lg_submit(k,n,3,120,0,15360,1,1));lg_play(k,1);
 std::thread producer([&]{for(int revision=2;revision<2000;revision++){while(!lg_submit(k,n,3,120,0,15360,1,revision)){};}});
 for(int i=0;i<4000;i++){lg_render(k,l.data(),r.data(),512);for(float f:l)assert(std::isfinite(f));}
 producer.join();for(int i=0;i<200;i++){lg_render(k,l.data(),r.data(),512);}assert(lg_revision(k)==1999);lg_destroy(k);
 k=lg_create(48000);assert(lg_submit(k,nullptr,0,120,0,15360,1,1));lg_countin(k,96000);lg_play(k,1);lg_play(k,0);lg_render(k,l.data(),r.data(),512);assert(lg_countremaining(k)==0);for(float f:l)assert(f==0);lg_destroy(k);
 // Eighth channel and master have separate controls; bus 3 is an ordinary track.
 k=lg_create(48000);LGNote eighth={0,3840,76,100,7,-1,3};assert(lg_submit(k,&eighth,1,120,0,3840,0,1));
 for(int t=0;t<8;t++){lg_mix(k,t,0,0,t==7);}lg_master(k,0);lg_mix(k,3,-61,0,0);lg_play(k,1);
 peak=0;for(int i=0;i<10;i++){lg_render(k,l.data(),r.data(),512);for(float f:l)peak=std::max(peak,std::abs(f));}
 assert(peak>0.01);assert(lg_meter(k,7)>0.01);assert(lg_meter(k,8)>0.01);assert(lg_meter(k,3)==0);
 lg_mix(k,7,-61,0,0);for(int i=0;i<20;i++)lg_render(k,l.data(),r.data(),512);for(float f:l)assert(std::abs(f)<0.00001);lg_destroy(k);
 // Preview swaps snapshots immediately at a buffer boundary, even at the same song revision.
 k=lg_create(48000);assert(lg_submit(k,n,3,120,0,15360,1,1));lg_play(k,1);lg_render(k,l.data(),r.data(),512);
 LGNote proposal={0,3840,79,100,0,-1,0};assert(lg_submit(k,&proposal,1,120,0,15360,1,2));lg_seek(k,0);lg_restart(k);lg_render(k,l.data(),r.data(),512);assert(lg_revision(k)==2);assert(lg_playing(k));assert(lg_tick(k)<30);lg_destroy(k);
 std::cout<<"Kernel: initial Play/count-in persistence, Stop/Panic cancellation, empty/finite startup, concurrent initial music/mix, zero startup-render allocations, render/loop boundaries and 10 minute clock passed\n";
}
