#pragma once
#include "GrillaKernel.h"
#include <array>
#include <algorithm>
#include <atomic>
#include <cmath>

struct PerformanceControl {int kind=0,a=0,b=0,token=0;float value=0;};
/// Main/control producer -> audio consumer; audio log producer -> main consumer.
class PerformanceRuntime {
    struct Replay {std::atomic<int> state{0},epoch{0};std::array<LGPerformanceEvent,16384> events{};int count=0;uint64_t duration=0;};
    std::array<Replay,3> replaySlots;
    int replaySlot=-1,replayCursor=0;
    std::array<PerformanceControl,64> controls{};
    std::atomic<uint64_t> controlWrite{0},controlRead{0};
    std::array<LGPerformanceEvent,512> log{};
    std::atomic<uint64_t> logWrite{0},logRead{0};
    PerformanceControl pendingSection{};int pendingJump=0,pendingRepeat=0;
    int lastBar=0,lastBeat=0,lastGrid=0,totalEvents=0;
public:
    bool enabled=false,capturing=false;uint64_t frames=0,limit=0;int epoch=0;
    std::atomic<int> requestToken{1},requestEpoch{0},requestCapture{0},requestStop{0};
    std::atomic<uint64_t> requestLimit{0};
    std::atomic<int> mode{0},recording{0},publishedEpoch{0},activeToken{0},queuedToken{0},repeatTicks{0},error{0},warning{0};
    std::atomic<uint64_t> clock{0},duration{0};
    uint64_t queue(PerformanceControl control){
        const uint64_t w=controlWrite.load(std::memory_order_relaxed),r=controlRead.load(std::memory_order_acquire);
        if(w-r>=controls.size())return 0;
        controls[w%controls.size()]=control;controlWrite.store(w+1,std::memory_order_release);return w+1;
    }
    uint64_t ack()const{return controlRead.load(std::memory_order_acquire);}
    void begin(int token,int generation,bool capture,uint64_t maximum){
        if(replaySlot>=0){replaySlots[replaySlot].state.store(0,std::memory_order_release);replaySlot=-1;}
        replayCursor=0;
        if(!capture){for(int i=0;i<3;i++){
            if(replaySlots[i].state.load(std::memory_order_acquire)!=2||replaySlots[i].epoch.load()!=generation)continue;
            int ready=2;if(!replaySlots[i].state.compare_exchange_strong(ready,3,std::memory_order_acq_rel))continue;
            if(replaySlots[i].epoch.load()!=generation){replaySlots[i].state.store(2,std::memory_order_release);continue;}
            replaySlot=i;break;
        }}
        enabled=true;capturing=capture;frames=0;limit=maximum;epoch=generation;totalEvents=0;
        lastBar=lastBeat=lastGrid=0;pendingSection={};pendingJump=pendingRepeat=0;
        controlRead.store(controlWrite.load(std::memory_order_acquire),std::memory_order_release);
        activeToken.store(token);queuedToken.store(0);repeatTicks.store(0);error.store(0);warning.store(0);clock.store(0);duration.store(0);
        publishedEpoch.store(epoch);mode.store(1);recording.store(capture?1:0);requestStop.store(0);
        emit(1,-1,0,0,0,token);
    }
    void finishCapture(){if(capturing){capturing=false;duration.store(frames,std::memory_order_release);recording.store(0,std::memory_order_release);}}
    void stop(){finishCapture();enabled=false;pendingSection={};pendingJump=pendingRepeat=0;queuedToken.store(0);repeatTicks.store(0);mode.store(0);controlRead.store(controlWrite.load(std::memory_order_acquire),std::memory_order_release);}
    void emit(int kind,int track,float value,int a=0,int b=0,int token=0){
        if(!capturing)return;
        if(limit>0&&frames>=limit){error.store(3);finishCapture();return;}
        const uint64_t w=logWrite.load(std::memory_order_relaxed),r=logRead.load(std::memory_order_acquire);
        if(totalEvents>=16384||w-r>=log.size()){error.store(totalEvents>=16384?2:1);finishCapture();return;}
        log[w%log.size()]={frames,epoch,kind,track,a,b,token,value};totalEvents++;logWrite.store(w+1,std::memory_order_release);
    }
    int pop(LGPerformanceEvent *events,int capacity){
        if(!events||capacity<=0)return 0;
        uint64_t r=logRead.load(std::memory_order_relaxed),w=logWrite.load(std::memory_order_acquire);int count=0;
        while(r<w&&count<capacity){events[count++]=log[r++%log.size()];}
        logRead.store(r,std::memory_order_release);return count;
    }
    int submitReplay(const LGPerformanceEvent *events,int count,uint64_t durationFrames,int generation){
        for(auto &slot:replaySlots){int expected=0;if(!slot.state.compare_exchange_strong(expected,1)){expected=2;if(!slot.state.compare_exchange_strong(expected,1))continue;}
            std::copy(events,events+count,slot.events.begin());slot.count=count;slot.duration=durationFrames;slot.epoch.store(generation);slot.state.store(2,std::memory_order_release);return 1;
        }return 0;
    }
    bool replaying()const{return replaySlot>=0;}
    template<class Apply> bool replayDue(Apply apply){
        if(replaySlot<0)return false;
        auto &source=replaySlots[replaySlot];
        if(frames>=source.duration){PerformanceControl end{99,0,0,0,0};apply(LGPerformanceEvent{frames,epoch,end.kind,-1,0,0,0,0});stop();return true;}
        while(replayCursor<source.count&&source.events[replayCursor].frame<=frames){const auto &event=source.events[replayCursor++];apply(event);if(event.kind==1)activeToken.store(event.token);if(event.kind==3)repeatTicks.store(int(event.value));}
        return true;
    }
    template<class Apply> void consume(Apply apply){
        if(requestStop.exchange(0))finishCapture();
        uint64_t r=controlRead.load(std::memory_order_relaxed),w=controlWrite.load(std::memory_order_acquire);
        while(r<w){const auto control=controls[r++%controls.size()];
            if(!enabled)continue;
            if(control.kind==1){pendingSection=control;queuedToken.store(control.token);}
            else if(control.kind==2)pendingJump=int(control.value);
            else if(control.kind==3){
                pendingRepeat=int(control.value);warning.store(0);
                if(pendingRepeat==0){if(apply(control))emit(3,-1,0);repeatTicks.store(0);}
            }
        }
        controlRead.store(r,std::memory_order_release);
    }
    template<class Apply> void due(double ticksPerFrame,Apply apply){
        if(!enabled)return;
        if(capturing&&frames>=limit){error.store(3);finishCapture();}
        const double tick=(double(frames)+0.5)*ticksPerFrame;
        const int bar=int(tick/3840),beat=int(tick/960),grid=int(tick/240);
        if(bar!=lastBar&&pendingSection.token!=0){const auto command=pendingSection;pendingSection={};queuedToken.store(0);if(apply(command)){activeToken.store(command.token);emit(1,-1,0,command.a,command.b,command.token);}}
        if(beat!=lastBeat&&pendingJump!=0){PerformanceControl command{2,0,0,0,float(pendingJump)};pendingJump=0;if(apply(command))emit(2,-1,command.value);}
        if(grid!=lastGrid&&pendingRepeat!=0){PerformanceControl command{3,0,0,0,float(pendingRepeat)};pendingRepeat=0;if(apply(command)){repeatTicks.store(int(command.value));emit(3,-1,command.value);}else{warning.store(1);repeatTicks.store(0);}}
        lastBar=bar;lastBeat=beat;lastGrid=grid;
    }
    void advance(bool running){if(enabled&&running)frames++;}
    void publish(){clock.store(frames,std::memory_order_release);}
};
