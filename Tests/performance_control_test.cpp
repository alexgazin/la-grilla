#include "GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <vector>
#include <iostream>
int main(){
    auto *k=lg_create(48000);std::vector<float> left(512),right(512);
    LGNote notes[]={{0,3840,60,100,0,-1,0},{3840,3840,67,100,0,-1,0}};
    assert(lg_submit(k,notes,2,120,0,3840,1,1));lg_perform_begin(k,1,1,1,480000);
    std::vector<float> capturedL,capturedR;
    auto render=[&](int frames){while(frames>0){int n=std::min(512,frames);lg_render(k,left.data(),right.data(),n);capturedL.insert(capturedL.end(),left.begin(),left.begin()+n);capturedR.insert(capturedR.end(),right.begin(),right.begin()+n);frames-=n;}};
    render(512);assert(lg_perform_mode(k));assert(lg_perform_recording(k));assert(lg_perform_active_token(k)==1);
    auto seq=lg_perform_queue(k,1,0,3840,7680,2);assert(seq);render(512);assert(lg_perform_ack(k)>=seq);assert(lg_perform_pending_token(k)==2);assert(lg_perform_active_token(k)==1);
    assert(lg_perform_queue(k,1,0,0,0,0));render(512);assert(lg_perform_pending_token(k)==0);
    assert(lg_perform_queue(k,1,0,3840,7680,2));assert(lg_perform_queue(k,1,0,0,3840,1));render(512);
    render(96000-2048);assert(lg_perform_active_token(k)==1);render(1);assert(lg_perform_pending_token(k)==0);
    assert(lg_perform_queue(k,1,0,3840,7680,2));render(512);render(192000-96001-512);assert(lg_perform_active_token(k)==1);
    render(1);assert(lg_perform_active_token(k)==2);assert(lg_tick(k)==3840);
    assert(lg_perform_queue(k,2,1,0,0,0));render(24000);assert(lg_tick(k)>5700&&lg_tick(k)<5800);
    lg_effects(k,-0.5f,0.25f);render(512);lg_pad(k,0,110);render(512);
    lg_perform_record_stop(k);render(512);assert(!lg_perform_recording(k));const auto duration=lg_perform_duration(k);assert(duration>192000&&duration<240000);
    std::vector<LGPerformanceEvent> events(512);int count=lg_perform_pop(k,events.data(),512);assert(count>=6);assert(events[0].frame==0&&events[0].kind==1);
    bool launch=false,jump=false,pad=false,filter=false,delay=false;
    for(int i=0;i<count;i++){const auto &event=events[i];assert(event.epoch==1);assert(event.frame<=duration);if(i)assert(event.frame>=events[i-1].frame);if(event.kind==1&&event.token==2){assert(event.frame==192000);launch=true;}if(event.kind==2){assert(event.frame==216000);jump=true;}if(event.kind==8)pad=true;if(event.kind==4)filter=true;if(event.kind==5)delay=true;}
    assert(launch&&jump&&pad&&filter&&delay);
    events[0].a=0;events[0].b=3840;
    auto *replay=lg_create(48000);assert(lg_submit(replay,notes,2,120,0,3840,1,1));assert(lg_perform_replay_submit(replay,events.data(),count,duration,2));lg_perform_begin(replay,1,2,0,0);
    std::vector<float> replayL(257),replayR(257);float maxDifference=0;
    for(uint64_t frame=0;frame<duration;){int n=int(std::min(uint64_t(257),duration-frame));lg_render(replay,replayL.data(),replayR.data(),n);for(int i=0;i<n;i++){maxDifference=std::max(maxDifference,std::abs(replayL[i]-capturedL[size_t(frame)+i]));maxDifference=std::max(maxDifference,std::abs(replayR[i]-capturedR[size_t(frame)+i]));}frame+=uint64_t(n);}
    assert(maxDifference<0.000001f);lg_render(replay,replayL.data(),replayR.data(),257);assert(!lg_playing(replay));assert(lg_perform_clock(replay)==duration);for(float value:replayL)assert(value==0);lg_destroy(replay);
    lg_panic(k);render(512);assert(!lg_perform_mode(k));assert(!lg_playing(k));assert(lg_perform_pending_token(k)==0);for(float f:left)assert(f==0);
    lg_destroy(k);std::cout<<"Perform control: queued cancel/latest-wins, exact bar/beat actions, actual-frame capture, stop and panic passed\n";
}
