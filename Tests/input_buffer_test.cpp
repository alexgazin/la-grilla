#include "GrillaInput.h"
#include <algorithm>
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <new>
#include <thread>
#include <vector>

static std::atomic<uint64_t> allocations{0};
static std::atomic<bool> countAllocations{false};
void *operator new(std::size_t count){if(countAllocations.load())++allocations;if(void *p=std::malloc(count))return p;throw std::bad_alloc();}
void *operator new[](std::size_t count){return ::operator new(count);}
void operator delete(void *p)noexcept{std::free(p);}
void operator delete[](void *p)noexcept{std::free(p);}
void operator delete(void *p,std::size_t)noexcept{std::free(p);}
void operator delete[](void *p,std::size_t)noexcept{std::free(p);}

int main(){
    assert(!lg_input_create(0,256,0,1e9,100));
    assert(!lg_input_create(48000,0,0,1e9,100));
    assert(!lg_input_create(48000,256,0,1e9,48000*31));
    auto *prepared=lg_input_create(8000,128,UINT64_MAX,8000,64);assert(prepared);
    float preflight[64]={};const float *preflightChannel[1]={preflight};
    assert(lg_input_push(prepared,preflightChannel,1,64,0,100)==0);
    assert(!lg_input_arm_limit(prepared,200,65));
    assert(lg_input_arm_limit(prepared,200,37)&&!lg_input_arm(prepared,300));
    assert(lg_input_push(prepared,preflightChannel,1,64,0,200)==37);
    assert(lg_input_state(prepared).frames==37&&lg_input_state(prepared).finished);lg_input_destroy(prepared);
    // A scheduled start can split a hardware buffer; the first accepted timestamp
    // and retained samples must refer to the same frame, never the count-in.
    auto *scheduled=lg_input_create(8000,256,1000,8000,10);assert(scheduled);
    float left[16],right[16],out[256];for(int i=0;i<16;++i){left[i]=float(i);right[i]=float(i+2);}
    const float *planar[2]={left,right};
    assert(lg_input_push(scheduled,planar,2,16,0,992)==8);
    auto state=lg_input_state(scheduled);assert(state.firstHostTime==1000&&state.frames==8&&!state.finished);
    assert(lg_input_pop(scheduled,out,256)==8);for(int i=0;i<8;++i)assert(out[i]==float(i+9));
    assert(lg_input_push(scheduled,planar,2,16,0,1008)==2);
    assert(lg_input_state(scheduled).finished&&lg_input_state(scheduled).frames==10);
    assert(lg_input_pop(scheduled,out,256)==2);lg_input_destroy(scheduled);
    // Interleaved input is downmixed without an additional audio engine or monitor.
    auto *interleaved=lg_input_create(48000,64,0,1e9,4);float stereo[8]={1,3,-1,1,0.5f,-0.5f,2,4};const float *packed[1]={stereo};
    assert(lg_input_push(interleaved,packed,2,4,1,100)==4);assert(lg_input_pop(interleaved,out,256)==4);
    assert(out[0]==2&&out[1]==0&&out[2]==0&&out[3]==3);lg_input_destroy(interleaved);
    // A stalled file/recognition worker is bounded; it produces an explicit
    // reproducible prefix and overflow rather than overwriting unread audio.
    auto *bounded=lg_input_create(48000,64,0,1e9,1000);float block[80];for(int i=0;i<80;++i)block[i]=float(i);const float *mono[1]={block};
    countAllocations=true;assert(lg_input_push(bounded,mono,1,80,0,100)==64);countAllocations=false;
    assert(allocations==0);state=lg_input_state(bounded);assert(state.overflow&&state.finished&&state.frames==64);
    assert(lg_input_pop(bounded,out,256)==64);for(int i=0;i<64;++i)assert(out[i]==float(i));
    assert(lg_input_push(bounded,mono,1,1,0,200)==0);lg_input_destroy(bounded);
    auto *invalid=lg_input_create(48000,64,0,1e9,64);block[3]=std::numeric_limits<float>::quiet_NaN();
    assert(lg_input_push(invalid,mono,1,8,0,1)==8);assert(lg_input_state(invalid).invalidInput&&lg_input_state(invalid).finished);
    assert(lg_input_pop(invalid,out,256)==8&&out[3]==0);lg_input_destroy(invalid);
    // Actual concurrent SPSC producer/consumer: all frames remain ordered with
    // non-dividing callback/drain sizes and wrap-around of the bounded storage.
    constexpr uint32_t total=240000;auto *concurrent=lg_input_create(48000,4096,0,1e9,total);assert(concurrent);
    std::atomic<bool> good{true};std::thread consumer([&]{float samples[173];uint32_t next=0;while(next<total){const auto n=lg_input_pop(concurrent,samples,173);for(uint32_t i=0;i<n;++i)if(samples[i]!=float(next+i))good=false;next+=n;if(n==0)std::this_thread::yield();}});
    float values[127];uint32_t next=0;
    while(next<total){if(lg_input_state(concurrent).queuedFrames>3500){std::this_thread::yield();continue;}const auto count=std::min(127u,total-next);for(uint32_t i=0;i<count;++i)values[i]=float(next+i);const float *channel[1]={values};assert(lg_input_push(concurrent,channel,1,count,0,next+1)==count);next+=count;}
    consumer.join();assert(good&&lg_input_state(concurrent).frames==total&&!lg_input_state(concurrent).overflow);lg_input_destroy(concurrent);
    std::cout<<"Shared input: timed frame gating, mono downmix, finite capture, explicit overflow, invalid PCM, ordered concurrent SPSC and zero callback allocations passed\n";
}
