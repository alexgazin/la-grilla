#include "GrillaKernel.h"
#include <array>
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <new>
#include <thread>

static thread_local bool rendering=false;
static std::atomic<unsigned> allocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(rendering)allocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}
static void render(LGKernel*k,uint64_t host,double rate=1e9,int frames=480){std::array<float,1024>l{},r{};assert(frames<=1024);rendering=true;lg_render_midi(k,nullptr,host,rate,l.data(),r.data(),frames);rendering=false;}
static LGOutputTiming read(LGKernel*k){LGOutputTiming value{};assert(lg_output_timing_read(k,&value));return value;}

static void exactSpacingVariableBuffersAndPause(){
    auto*k=lg_create(48000);const auto epoch=lg_output_timing_begin(k);assert(epoch==1);
    render(k,1'000'000'000);auto value=read(k);assert(value.epoch==epoch&&value.callbacks==1&&value.comparedCallbacks==0&&value.inheritedAnchor==0&&value.baselineFrames==480&&value.baselineBufferNanoseconds==10'000'000);
    render(k,1'010'000'000,1e9,240);render(k,1'015'000'000,1e9,960);render(k,1'035'000'000,1e9,480);
    value=read(k);assert(value.callbacks==4&&value.comparedCallbacks==3&&value.maxExcessNanoseconds==0&&value.maxIntervalNanoseconds==20'000'000);
    const auto clock=lg_clock(k);
    // A preserved sample clock advances just one buffer after a real host-time
    // pause. The gap metric must expose the missing 80 ms anyway.
    render(k,1'125'000'000);value=read(k);assert(lg_clock(k)==clock+480);assert(value.maxExcessNanoseconds==80'000'000&&value.maxIntervalNanoseconds==90'000'000);
    render(k,1'135'000'000);value=read(k);assert(value.maxExcessNanoseconds==80'000'000&&value.callbacks==6&&value.comparedCallbacks==5);lg_destroy(k);
}

static void epochKeepsThePreRestartAnchor(){
    auto*k=lg_create(48000);render(k,2'000'000'000);render(k,2'010'000'000);
    const auto first=lg_output_timing_begin(k);auto value=read(k);assert(value.epoch==0);
    // Request while output is paused. Resetting the old host anchor along with
    // the counters would erase exactly the first resumed callback's gap.
    render(k,2'120'000'000);value=read(k);assert(value.epoch==first&&value.inheritedAnchor==1&&value.callbacks==1&&value.comparedCallbacks==1&&value.maxExcessNanoseconds==100'000'000);
    const auto second=lg_output_timing_begin(k),third=lg_output_timing_begin(k);assert(second==first+1&&third==second+1);
    render(k,2'130'000'000,1e9,240);value=read(k);assert(value.epoch==third&&value.inheritedAnchor==1&&value.callbacks==1&&value.comparedCallbacks==1&&value.maxExcessNanoseconds==0&&value.baselineFrames==480);
    const auto fourth=lg_output_timing_begin(k);render(k,2'135'000'000);value=read(k);assert(value.epoch==fourth&&value.baselineFrames==240&&value.baselineBufferNanoseconds==5'000'000&&value.maxExcessNanoseconds==0);lg_destroy(k);
}

static void backwardsRateChangeAndOffline(){
    auto*k=lg_create(48000);render(k,3'000'000'000);const auto epoch=lg_output_timing_begin(k);
    render(k,3'010'000'000);render(k,3'005'000'000);render(k,3'005'000'000);auto value=read(k);
    assert(value.epoch==epoch&&value.nonIncreasingTimestamps==2&&value.callbacks==3&&value.comparedCallbacks==1&&value.maxExcessNanoseconds==0);
    render(k,3'015'000'000,24e6);value=read(k);assert(value.clockRateChanges==1&&value.comparedCallbacks==1);
    render(k,3'015'240'000,24e6);value=read(k);assert(value.comparedCallbacks==2&&value.maxExcessNanoseconds==0); // 240k ticks = 10ms
    const auto before=value;render(k,0);render(k,0,0);render(k,3'265'000'000,0);render(k,3'265'000'000,std::numeric_limits<double>::quiet_NaN(),0);
    value=read(k);assert(value.callbacks==before.callbacks&&value.epoch==before.epoch&&value.maxExcessNanoseconds==before.maxExcessNanoseconds);
    const auto next=lg_output_timing_begin(k);render(k,0);assert(read(k).epoch==epoch);render(k,3'015'480'000,24e6);value=read(k);assert(value.epoch==next&&value.inheritedAnchor==1&&value.maxExcessNanoseconds==0);
    assert(!lg_output_timing_begin(nullptr)&&!lg_output_timing_read(nullptr,&value)&&!lg_output_timing_read(k,nullptr));lg_destroy(k);
}

static void arbitraryTimebaseAndUnchangedPCM(){
    for(double sampleRate:{44100.,48000.,96000.}){
        auto*k=lg_create(sampleRate);auto*reference=lg_create(sampleRate);LGNote note={0,15360,60,110,0,-1,0};
        for(auto*engine:{k,reference}){assert(lg_submit(engine,&note,1,120,0,15360,1,1));lg_play(engine,1);}
        const int frames=int(sampleRate/100);assert(lg_output_timing_begin(k));std::array<float,1024> l{},r{},expectedL{},expectedR{};float energy=0;
        for(int block=0;block<12;block++){
            rendering=true;lg_render_midi(k,nullptr,24'000'000+uint64_t(block)*240'000,24e6,l.data(),r.data(),frames);lg_render(reference,expectedL.data(),expectedR.data(),frames);rendering=false;
            for(int i=0;i<frames;i++){assert(l[i]==expectedL[i]&&r[i]==expectedR[i]);energy+=std::abs(l[i]);}
        }
        const auto value=read(k);assert(value.callbacks==12&&value.comparedCallbacks==11&&value.baselineBufferNanoseconds==10'000'000&&value.maxExcessNanoseconds==0&&energy>0.1f);assert(lg_clock(k)==lg_clock(reference)&&lg_tick(k)==lg_tick(reference)&&lg_playing(k));lg_destroy(reference);lg_destroy(k);
    }
}

static void concurrentEpochsAndCoherentBoundedReads(){
    auto*k=lg_create(48000);std::atomic<bool>done{false};uint64_t host=1'000'000;uint64_t lastRequested=0;int coherent=0;
    assert(lg_output_timing_begin(k));render(k,host++,48000,1);
    std::thread audio([&]{int callbacks=0;while(!done.load(std::memory_order_acquire)||callbacks<2000){render(k,host++,48000,1);callbacks++;}});
    for(int i=0;i<5000;i++){
        lastRequested=lg_output_timing_begin(k);LGOutputTiming value{};
        if(lg_output_timing_read(k,&value)&&value.epoch>0){coherent++;assert(value.epoch<=lastRequested&&value.callbacks>=value.comparedCallbacks&&value.baselineFrames==1&&value.baselineBufferNanoseconds==20833&&value.maxExcessNanoseconds==0&&value.nonIncreasingTimestamps==0&&value.clockRateChanges==0);}
    }
    done.store(true,std::memory_order_release);audio.join();render(k,host,48000,1);const auto value=read(k);assert(value.epoch==lastRequested&&value.callbacks>=1&&value.maxExcessNanoseconds==0);assert(coherent>0);lg_destroy(k);
}

int main(){exactSpacingVariableBuffersAndPause();epochKeepsThePreRestartAnchor();backwardsRateChangeAndOffline();arbitraryTimebaseAndUnchangedPCM();concurrentEpochsAndCoherentBoundedReads();assert(allocations==0);std::cout<<"Output timing: real host spacing, variable buffer durations, retained restart/epoch anchor, backward/rate discontinuities, offline exclusion, unchanged PCM, concurrent bounded snapshots and zero render allocations passed\n";}
