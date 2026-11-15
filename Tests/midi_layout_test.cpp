#include "GrillaKernel.h"
#include "MIDIHub.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>
#include <thread>

static thread_local bool realtime=false;
static std::atomic<unsigned> realtimeAllocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(realtime)realtimeAllocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void*operator new(std::size_t size,const std::nothrow_t&)noexcept{if(realtime)realtimeAllocations++;return std::malloc(size?size:1);}
[[gnu::noinline]] void*operator new[](std::size_t size,const std::nothrow_t&tag)noexcept{return ::operator new(size,tag);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,const std::nothrow_t&)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,const std::nothrow_t&)noexcept{std::free(p);}

static constexpr std::array<uint64_t,2> originalKeys{{11,22}};
static constexpr std::array<int32_t,2> originalRoles{{0,2}},originalChannels{{0,1}};
static constexpr std::array<uint64_t,3> expandedKeys{{22,33,11}};
static constexpr std::array<int32_t,3> expandedRoles{{2,3,0}},expandedChannels{{1,2,0}};
static constexpr std::array<int32_t,8> legacyChannels{{0,9,1,2,3,4,5,6}};
static void original(LGMIDIHub*h){h->adoptLayout(nullptr,0,originalKeys.data(),originalRoles.data(),originalChannels.data(),2,[](int){});}
static void expand(LGMIDIHub*h){realtime=true;h->adoptLayout(originalKeys.data(),2,expandedKeys.data(),expandedRoles.data(),expandedChannels.data(),3,[](int){assert(false);});realtime=false;}
static void push(LGMIDIHub*h,uint32_t handle,uint64_t time,uint8_t status,uint8_t a,uint8_t b){const uint8_t bytes[]={status,a,b};assert(lg_midi_push(h,handle,time,bytes,3));}

static void keyedFutureInput(){
    auto*h=lg_midi_create();original(h);
    lg_midi_configure_track(h,256,22,1,2,65535);
    lg_midi_configure(h,257,0,0,65535); // Legacy binding acquires the old track's key.
    push(h,256,200,0x90,64,110);push(h,256,201,0xb0,64,127);push(h,256,202,0x80,64,0);
    push(h,257,203,0x90,72,100);
    h->prepare([](int){});assert(h->count==4);expand(h);
    int count=0;h->due(203,1,[&](const LGMIDIEvent&e){assert(e.track==(e.source==0?0:2));assert(e.instrument==(e.source==0?2:0));count++;});assert(count==4);
    assert(lg_midi_connected(h,256)&&lg_midi_connected(h,257));
    // Removing the UUID invalidates its already decoded future notes, sustain,
    // and releases. They must never be retargeted to the new index occupant.
    push(h,256,400,0x90,65,110);push(h,256,401,0xb0,64,0);push(h,256,402,0x80,65,0);h->prepare([](int){});
    const uint64_t keys[]={33,11};const int32_t roles[]={3,0},channels[]={2,0};int cleared=0;
    h->adoptLayout(expandedKeys.data(),3,keys,roles,channels,2,[&](int source){cleared|=1<<source;});assert(cleared==1);
    h->due(500,1,[&](const LGMIDIEvent&){assert(false);});assert(h->count==0);
    // A newly queued packet for a currently absent UUID is safely ignored too.
    push(h,256,600,0x90,67,100);h->prepare([](int){});h->due(600,1,[&](const LGMIDIEvent&){assert(false);});
    // Restoring that UUID permits new input without reconnecting its device.
    h->adoptLayout(keys,2,expandedKeys.data(),expandedRoles.data(),expandedChannels.data(),3,[](int){});
    push(h,256,700,0x90,69,100);h->prepare([](int){});count=0;h->due(700,1,[&](const LGMIDIEvent&e){assert(e.track==0&&e.instrument==2);count++;});assert(count==1);
    lg_midi_destroy(h);
}

static void staleBindingPackets(){
    auto*h=lg_midi_create();original(h);lg_midi_configure_track(h,256,11,0,0,65535);
    push(h,256,10,0xb0,74,100);push(h,256,1000,0x90,60,100);h->prepare([](int){});h->due(10,1,[](const LGMIDIEvent&){});
    push(h,256,20,0x90,61,100); // Still in the raw queue when binding changes.
    // Even an explicitly reused handle has a new configuration version.
    lg_midi_configure_track(h,256,22,1,2,65535);
    LGMIDIEvent events[8];assert(lg_midi_monitor_pop(h,events,8)==0);
    h->due(1000,1,[](const LGMIDIEvent&){assert(false);});h->prepare([](int){});h->due(1000,1,[](const LGMIDIEvent&){assert(false);});
    // A partial running-status message cannot continue across target changes.
    const uint8_t partial[]={0x90,62};assert(lg_midi_push(h,256,2000,partial,2));h->prepare([](int){});
    lg_midi_configure_track(h,256,11,0,0,65535);const uint8_t tail[]={110};assert(lg_midi_push(h,256,2000,tail,1));h->prepare([](int){});h->due(2000,1,[](const LGMIDIEvent&){assert(false);});
    push(h,256,2001,0x90,63,110);h->prepare([](int){});int applied=0;h->due(2001,1,[&](const LGMIDIEvent&e){assert(e.track==0&&e.a==63);applied++;});assert(applied==1);
    // Monitor entries also belong to the old endpoint, never a reused slot.
    lg_midi_disconnect(h,0);lg_midi_configure_track(h,512,22,1,2,65535);assert(lg_midi_monitor_pop(h,events,8)==0);
    assert(!lg_midi_push(h,256,3000,tail,1));lg_midi_destroy(h);
}

static void outputMapAndWorkerRace(){
    auto*h=lg_midi_create();const auto epoch=lg_midi_output_configure(h,legacyChannels.data(),8,1);const auto before=h->outputConfiguration();
    original(h);expand(h);const auto after=h->outputConfiguration();assert((before>>32)==(after>>32));assert(uint32_t(after)==0x21);
    assert(h->outputOn(before,100,0,60,100)==1); // The callback cached the old map.
    LGMIDIOutput events[8];assert(lg_midi_output_pop(h,events,8)==1);assert(events[0].status==0x91&&events[0].epoch==epoch);
    // An asynchronous endpoint selection finishing after project adoption may
    // provide obsolete channels. Its destination epoch is valid, its map is not.
    const auto next=lg_midi_output_configure(h,legacyChannels.data(),8,1);assert(next!=epoch);assert(uint32_t(h->outputConfiguration())==0x21);
    h->resetOutputRefs();assert(h->outputOn(h->outputConfiguration(),101,1,61,100)==2);assert(lg_midi_output_pop(h,events,8)==1);assert(events[0].status==0x92&&events[0].epoch==next);
    // Disabling the endpoint must still win over the authoritative channel map.
    lg_midi_output_configure(h,nullptr,0,0);assert(h->outputOn(h->outputConfiguration(),102,0,62,100)==-1);assert(lg_midi_output_pop(h,events,8)==0);lg_midi_destroy(h);
    // Legacy users without project snapshots retain their supplied channel map.
    h=lg_midi_create();lg_midi_output_configure(h,legacyChannels.data(),8,1);assert(h->outputOn(h->outputConfiguration(),0,1,36,100)==9);lg_midi_destroy(h);
}

static void staleEndpointActivation(){
    auto*h=lg_midi_create();original(h);
    const auto stale=lg_midi_output_configure(h,nullptr,0,0);
    const auto none=lg_midi_output_configure(h,nullptr,0,0);assert(none!=stale);
    // Deterministically complete an older queued selection after the user chose
    // None. A stale worker cannot resurrect the endpoint or its old channel map.
    uint32_t activated=1;std::thread worker([&]{activated=lg_midi_output_activate(h,stale,legacyChannels.data(),8,1);});worker.join();
    assert(activated==0&&lg_midi_output_active_epoch(h)==0);
    expand(h);assert(lg_midi_output_activate(h,stale,legacyChannels.data(),8,1)==0);
    const auto current=lg_midi_output_configure(h,nullptr,0,0);
    assert(lg_midi_output_activate(h,current,legacyChannels.data(),8,1)==current);
    assert(lg_midi_output_active_epoch(h)==current&&uint32_t(h->outputConfiguration())==0x21);
    assert(lg_midi_output_activate(h,current,legacyChannels.data(),8,1)==0);
    assert(lg_midi_output_activate(h,0,legacyChannels.data(),8,1)==0);
    assert(lg_midi_output_activate(h,current,nullptr,0,1)==0);
    // Generation zero is reserved for disabled/failure even after wraparound.
    h->outputGeneration.store(0x7ffffffe);assert(lg_midi_output_configure(h,nullptr,0,0)==0x7fffffff);
    assert(lg_midi_output_configure(h,nullptr,0,0)==1);lg_midi_destroy(h);
}

static void render(LGKernel*k,LGMIDIHub*h,uint64_t time,int frames,float*l,float*r){realtime=true;lg_render_midi(k,h,time,48000,l,r,frames);realtime=false;for(int i=0;i<frames;i++)assert(std::isfinite(l[i])&&std::isfinite(r[i]));}
static void advance(LGKernel*k,LGMIDIHub*h,uint64_t origin,int frames){std::array<float,1024>l{},r{};while(frames){const int n=std::min(frames,1024);render(k,h,origin+lg_clock(k),n,l.data(),r.data());frames-=n;}}
static const std::array<LGProjectTrack,2> beforeTracks{{{{0,-1,1},2,0,0,11},{{0,1,1},2,2,1,22}}};
static const std::array<LGProjectTrack,3> afterTracks{{{{0,-1,1},2,2,1,22},{{-61,0,0},2,3,2,33},{{0,1,1},2,0,0,11}}};
static void exactKernelBoundary(){
    auto*k=lg_create(48000);auto*h=lg_midi_create();const uint64_t origin=100000;
    const auto epoch=lg_midi_output_configure(h,legacyChannels.data(),8,1);lg_midi_configure_track(h,256,11,0,0,65535);
    const LGNote old={0,15360,60,100,0,-1,0},next={3840,960,67,100,0,-1,2};
    assert(lg_submit_project(k,&old,1,240,0,15360,1,1,1,beforeTracks.data(),2,0,0,0));lg_play(k,1);advance(k,h,origin,1000);
    LGMIDIOutput events[16];assert(lg_midi_output_pop(h,events,16)==1);assert(events[0].status==0x90&&events[0].epoch==epoch);
    assert(lg_submit_project(k,&next,1,240,0,15360,1,2,2,afterTracks.data(),3,0,0,0));
    // Decode the first boundary note in an earlier callback; handover must keep
    // its UUID and apply it after adopting the new layout, on this exact sample.
    push(h,256,origin+48000,0x90,72,110);advance(k,h,origin,47000);assert(lg_revision(k)==1);
    std::array<float,512>l{},r{};render(k,h,origin+48000,512,l.data(),r.data());assert(lg_revision(k)==2&&lg_playing(k));
    const int count=lg_midi_output_pop(h,events,16);assert(count==2);assert(events[0].status==0x80&&events[0].a==60);assert(events[1].status==0x91&&events[1].a==67);
    for(int i=0;i<count;i++)assert(events[i].hostTime==origin+48000&&events[i].epoch==epoch);
    LGMIDIEvent input[8];assert(lg_midi_monitor_pop(h,input,8)==1);assert(input[0].hostTime==origin+48000&&input[0].track==2&&input[0].instrument==0&&input[0].a==72);
    // No control-thread reconfigure or monitor poll was required for routing.
    assert(lg_midi_connected(h,256));lg_destroy(k);lg_midi_destroy(h);
}

static void heldSustainAndDeletedSource(){
    auto*k=lg_create(48000);auto*h=lg_midi_create();const uint64_t origin=200000;
    lg_midi_configure_track(h,256,11,0,0,65535);assert(lg_submit_project(k,nullptr,0,240,0,15360,1,1,1,beforeTracks.data(),2,0,0,0));lg_play(k,1);
    push(h,256,origin,0x90,60,110);push(h,256,origin+100,0xb0,64,127);push(h,256,origin+101,0x80,60,0);advance(k,h,origin,1000);
    const LGProjectTrack survivor={{0,1,1},2,2,1,22};assert(lg_submit_project(k,nullptr,0,240,0,15360,1,2,2,&survivor,1,0,0,0));
    push(h,256,origin+48000,0x90,72,110);push(h,256,origin+48001,0xb0,64,0);advance(k,h,origin,47000+512);
    std::array<float,2048>l{},r{};render(k,h,origin+lg_clock(k),2048,l.data(),r.data());assert(lg_revision(k)==2&&lg_playing(k));for(int i=0;i<2048;i++)assert(l[i]==0&&r[i]==0);
    LGMIDIEvent input[8];const int n=lg_midi_monitor_pop(h,input,8);assert(n==3);for(int i=0;i<n;i++)assert(input[i].hostTime<origin+48000);assert(lg_midi_connected(h,256));lg_destroy(k);lg_midi_destroy(h);
}

static void immediateOffWhileLayoutPending(){
    auto*k=lg_create(48000);auto*h=lg_midi_create();const uint64_t origin=300000;
    lg_midi_output_configure(h,legacyChannels.data(),8,1);lg_midi_configure_track(h,256,11,0,0,65535);
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,1,1,beforeTracks.data(),2,0,0,0));lg_play(k,1);advance(k,h,origin,1000);
    const LGNote next={3840,960,67,100,0,-1,2};assert(lg_submit_project(k,&next,1,240,0,15360,1,2,2,afterTracks.data(),3,0,0,0));
    push(h,256,origin+1000,0x90,72,110);push(h,256,origin+1001,0xb0,64,127);push(h,256,origin+1002,0x80,72,0);
    push(h,256,origin+48000,0x90,74,110);advance(k,h,origin,512);
    LGMIDIEvent input[8];assert(lg_midi_monitor_pop(h,input,8)==3);assert(lg_revision(k)==1);
    const auto stale=lg_midi_output_configure(h,nullptr,0,0);
    lg_midi_disconnect(h,0);lg_midi_output_configure(h,nullptr,0,0);
    assert(lg_midi_output_activate(h,stale,legacyChannels.data(),8,1)==0);
    const uint8_t blocked[]={0x90,75,100};assert(!lg_midi_push(h,256,origin+1512,blocked,3));
    std::array<float,1024>l{},r{};render(k,h,origin+1512,1024,l.data(),r.data());
    assert(lg_revision(k)==1&&lg_playing(k)&&lg_midi_output_active_epoch(h)==0);
    for(int i=512;i<1024;i++)assert(l[i]==0&&r[i]==0); // Its bounded 8 ms release ends before the bar.
    advance(k,h,origin,48000-int(lg_clock(k))+512);assert(lg_revision(k)==2);
    render(k,h,origin+lg_clock(k),1024,l.data(),r.data());float left=0,right=0;for(int i=0;i<1024;i++){left+=std::abs(l[i]);right+=std::abs(r[i]);}
    assert(left>0.01f&&right==0); // New project uses its new bus, never stale input.
    LGMIDIOutput events[8];assert(lg_midi_output_pop(h,events,8)==0);
    assert(lg_midi_monitor_pop(h,input,8)==0&&!lg_midi_connected(h,256)&&lg_midi_output_active_epoch(h)==0);
    lg_destroy(k);lg_midi_destroy(h);
}

static void concurrentEndpointSelection(){
    auto*h=lg_midi_create();original(h);std::atomic<bool>done{false};
    std::thread control([&]{for(int i=0;i<10000;i++)lg_midi_output_configure(h,legacyChannels.data(),8,1);done.store(true,std::memory_order_release);});
    int iterations=0;while(!done.load(std::memory_order_acquire)||iterations<10000){
        realtime=true;
        if(iterations%2)h->adoptLayout(expandedKeys.data(),3,originalKeys.data(),originalRoles.data(),originalChannels.data(),2,[](int){});
        else h->adoptLayout(originalKeys.data(),2,expandedKeys.data(),expandedRoles.data(),expandedChannels.data(),3,[](int){});
        realtime=false;assert(uint32_t(h->outputConfiguration())==(iterations%2?0x10u:0x21u));iterations++;
    }
    control.join();lg_midi_destroy(h);
}

int main(){keyedFutureInput();staleBindingPackets();outputMapAndWorkerRace();staleEndpointActivation();exactKernelBoundary();heldSustainAndDeletedSource();immediateOffWhileLayoutPending();concurrentEndpointSelection();assert(realtimeAllocations.load()==0);std::cout<<"MIDI live layout: UUID input/future/sustain safety, stale packet generations, exact boundary output/input, immediate Off during pending layouts, conditional endpoint activation, legacy routing and zero realtime allocations passed\n";}
