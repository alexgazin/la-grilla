#include "include/GrillaInput.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>
#include <new>

static_assert(std::atomic<uint64_t>::is_always_lock_free,"Input positions must be lock-free");
static_assert(std::atomic<float>::is_always_lock_free,"Input meters must be lock-free");
struct LGInput {
    const double rate,ticksPerSecond;
    const uint32_t capacity;
    std::atomic<uint64_t> start;
    const uint64_t maximumLimit;
    std::atomic<uint64_t> limit;
    std::unique_ptr<float[]> samples;
    alignas(64) std::atomic<uint64_t> written{0};
    alignas(64) std::atomic<uint64_t> read{0};
    std::atomic<uint64_t> total{0},firstHost{0},lastHost{0};
    std::atomic<uint32_t> overflow{0},invalid{0};
    std::atomic<bool> closed{false};
    std::atomic<float> peak{0};
    LGInput(double r,uint32_t c,uint64_t s,double t,uint64_t l):rate(r),ticksPerSecond(t),capacity(c),start(s),maximumLimit(l),limit(l),samples(new float[c]){}
};
extern "C" LGInput *lg_input_create(double rate,uint32_t capacity,uint64_t start,double ticks,uint64_t limit){
    if(!std::isfinite(rate)||rate<8000||rate>192000||capacity<64||capacity>1048576||!std::isfinite(ticks)||ticks<=0||!limit||limit>uint64_t(rate*30.25))return nullptr;
    try{return new LGInput(rate,capacity,start,ticks,limit);}catch(...){return nullptr;}
}
extern "C" void lg_input_destroy(LGInput *input){delete input;}
extern "C" int lg_input_arm_limit(LGInput *input,uint64_t start,uint64_t limit){
    if(!input||input->closed.load()||start>=UINT64_MAX-1||!limit||limit>input->maximumLimit)return 0;
    uint64_t expected=UINT64_MAX;
    if(!input->start.compare_exchange_strong(expected,UINT64_MAX-1,std::memory_order_acq_rel))return 0;
    input->limit.store(limit,std::memory_order_relaxed);input->start.store(start,std::memory_order_release);return 1;
}
extern "C" int lg_input_arm(LGInput *input,uint64_t start){return input?lg_input_arm_limit(input,start,input->maximumLimit):0;}
extern "C" uint32_t lg_input_push(LGInput *input,const void *channelPointers,uint32_t channelCount,uint32_t frames,int interleaved,uint64_t host){
    if(!input||input->closed.load(std::memory_order_acquire))return 0;
    const auto channels=static_cast<const float *const *>(channelPointers);
    input->lastHost.store(host,std::memory_order_relaxed);
    if(!channels||channelCount==0||channelCount>32||frames>65536){input->invalid.store(1);input->closed.store(true,std::memory_order_release);return 0;}
    for(uint32_t channel=0;channel<(interleaved?1:channelCount);++channel)if(!channels[channel]){input->invalid.store(1);input->closed.store(true,std::memory_order_release);return 0;}
    uint32_t skip=0;
    const uint64_t start=input->start.load(std::memory_order_acquire);
    if(host<start){const double elapsed=double(start-host)/input->ticksPerSecond*input->rate;skip=uint32_t(std::min(double(frames),std::ceil(elapsed)));}
    if(skip>=frames)return 0;
    const uint64_t total=input->total.load(std::memory_order_relaxed);
    const uint64_t limit=input->limit.load(std::memory_order_relaxed);
    if(total>=limit){input->closed.store(true,std::memory_order_release);return 0;}
    const uint64_t written=input->written.load(std::memory_order_relaxed),read=input->read.load(std::memory_order_acquire);
    const uint32_t requested=uint32_t(std::min(uint64_t(frames-skip),limit-total));
    const uint32_t count=uint32_t(std::min(uint64_t(requested),uint64_t(input->capacity)-(written-read)));
    float peak=0;
    for(uint32_t index=0;index<count;++index){
        float sample=0;
        for(uint32_t channel=0;channel<channelCount;++channel){
            const float value=interleaved?channels[0][(index+skip)*channelCount+channel]:channels[channel][index+skip];
            if(!std::isfinite(value)){input->invalid.store(1,std::memory_order_relaxed);continue;}
            sample+=value/float(channelCount);
        }
        if(!std::isfinite(sample)){sample=0;input->invalid.store(1,std::memory_order_relaxed);}
        input->samples[(written+index)%input->capacity]=sample;peak=std::max(peak,std::abs(sample));
    }
    if(count&&total==0)input->firstHost.store(host+uint64_t(double(skip)/input->rate*input->ticksPerSecond),std::memory_order_relaxed);
    input->peak.store(peak,std::memory_order_relaxed);
    input->total.store(total+count,std::memory_order_relaxed);
    input->written.store(written+count,std::memory_order_release);
    if(count<requested){input->overflow.store(1,std::memory_order_relaxed);input->closed.store(true,std::memory_order_release);}
    if(total+count==limit||input->invalid.load(std::memory_order_relaxed))input->closed.store(true,std::memory_order_release);
    return count;
}
extern "C" uint32_t lg_input_pop(LGInput *input,float *output,uint32_t capacity){
    if(!input||!output||!capacity)return 0;
    const uint64_t read=input->read.load(std::memory_order_relaxed),written=input->written.load(std::memory_order_acquire);
    const uint32_t count=uint32_t(std::min(uint64_t(capacity),written-read));
    for(uint32_t index=0;index<count;++index)output[index]=input->samples[(read+index)%input->capacity];
    input->read.store(read+count,std::memory_order_release);return count;
}
extern "C" void lg_input_close(LGInput *input){if(input)input->closed.store(true,std::memory_order_release);}
extern "C" LGInputState lg_input_state(const LGInput *input){
    if(!input)return {};
    const uint64_t read=input->read.load(std::memory_order_acquire),written=input->written.load(std::memory_order_acquire);
    return {input->total.load(),input->firstHost.load(),input->lastHost.load(),uint32_t(written-read),input->overflow.load(),input->invalid.load(),input->closed.load()?1u:0u,input->peak.load()};
}
