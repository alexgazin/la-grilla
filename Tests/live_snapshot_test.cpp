#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <new>
#include <thread>
#include <vector>

static thread_local bool insideRender=false;
static std::atomic<unsigned> renderAllocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(insideRender)renderAllocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}
static void block(LGKernel*k,float*l,float*r,int frames){insideRender=true;lg_render(k,l,r,frames);insideRender=false;}
static void advance(LGKernel*k,int frames){std::array<float,1024> l{},r{};while(frames>0){const int count=std::min(frames,int(l.size()));block(k,l.data(),r.data(),count);for(int i=0;i<count;i++)assert(std::isfinite(l[i])&&std::isfinite(r[i]));frames-=count;}}
static float gain(float db){return std::pow(10.f,db/20);}
static std::array<LGTrackMix,2> mix(int active,float db=0,float pan=0){std::array<LGTrackMix,2> value{};for(int i=0;i<2;i++)value[i]={db,pan,i==active};return value;}
static int project(LGKernel*k,const LGNote*notes,int count,const std::array<LGTrackMix,2>&m,int revision,uint64_t layout,float filter=0,float delay=0,const int32_t*presets=nullptr,double bpm=120,const int32_t*roles=nullptr){const int32_t current[2]={2,2},instruments[2]={0,3};std::array<LGProjectTrack,2> tracks{};for(int i=0;i<2;i++)tracks[i]={m[i],(presets?presets:current)[i],(roles?roles:instruments)[i],i,uint64_t(i+1)};return lg_submit_project(k,notes,count,bpm,0,15360,1,revision,layout,tracks.data(),2,0,filter,delay);}

static void atomicBoundary(double rate){
    auto*k=lg_create(rate);auto*reference=lg_create(rate);const LGNote oldNote={0,15360,60,110,0,-1,0},newNote={0,15360,72,110,1,-1,3};
    const auto before=mix(0,0,-1),after=mix(1,0,1);
    assert(project(k,&oldNote,1,before,1,1));lg_play(k,1);advance(k,int(rate));
    const auto firstClock=lg_clock(k);assert(lg_revision(k)==1&&lg_playing(k));assert(lg_gain_target(k,0)==1&&lg_gain_target(k,1)==0);
    assert(project(k,&newNote,1,after,2,2));advance(k,int(rate));
    assert(lg_revision(k)==1&&lg_playing(k));assert(lg_clock(k)==firstClock+uint64_t(rate));assert(lg_gain_target(k,0)==1&&lg_gain_target(k,1)==0);assert(lg_pan_target(k,0)==-1);
    // The boundary falls at the first sample of this whole 1024-frame block.
    // A buffer-late mix update would now render the new note with the old gain.
    std::array<float,1024> l{},r{},expectedL{},expectedR{};block(k,l.data(),r.data(),int(l.size()));
    assert(lg_revision(k)==2&&lg_playing(k));assert(lg_gain_target(k,0)==0&&lg_gain_target(k,1)==1&&lg_pan_target(k,1)==1);
    assert(std::abs(lg_tick(k)-(3840+1023*120*960/(60*rate)))<0.1);
    assert(project(reference,&newNote,1,after,2,2));lg_seek(reference,3840);lg_play(reference,1);block(reference,expectedL.data(),expectedR.data(),int(l.size()));
    const int fade=int(std::ceil(rate*0.003));float energy=0;
    for(int i=fade;i<int(l.size());i++){assert(std::abs(l[i]-expectedL[i])<1e-6f);assert(std::abs(r[i]-expectedR[i])<1e-6f);energy+=std::abs(r[i]);}
    assert(energy>0.01f);lg_destroy(reference);lg_destroy(k);
}

static void versionedControls(){
    auto*k=lg_create(48000);const LGNote a={0,15360,60,100,0,-1,0},b={0,15360,67,100,1,-1,3};const auto old=mix(0),pending=mix(1,-6,0.25f),latest=mix(1,-12,0.75f);
    assert(project(k,&a,1,old,1,1));lg_play(k,1);advance(k,48000);
    assert(project(k,&b,1,pending,2,2,0.25f,0.125f));assert(lg_mix_snapshot_for_revision(k,latest.data(),2,0,-0.5f,0.25f,2));
    // A later control update for the old project cannot make a previously
    // published future-project control look stale when that project adopts.
    for(int i=0;i<8;i++)assert(lg_mix_snapshot_for_revision(k,old.data(),2,0,0,0,1));
    advance(k,48000);assert(lg_revision(k)==1&&lg_gain_target(k,0)==1&&lg_gain_target(k,1)==0&&lg_filter_target(k)==0&&lg_delay_target(k)==0);
    advance(k,1);assert(lg_revision(k)==2&&lg_playing(k));assert(std::abs(lg_gain_target(k,1)-gain(-12))<1e-6f&&lg_pan_target(k,1)==0.75f);assert(lg_filter_target(k)==-0.5f&&lg_delay_target(k)==0.25f);
    assert(lg_mix_snapshot_for_revision(k,old.data(),2,0,1,0.5f,1));advance(k,32);assert(lg_gain_target(k,0)==0&&lg_filter_target(k)==-0.5f);
    // A newer future mix cannot leak into the current track layout.
    assert(lg_mix_snapshot_for_revision(k,old.data(),2,0,1,0.5f,3));advance(k,128);assert(lg_gain_target(k,0)==0&&lg_filter_target(k)==-0.5f);
    // Latest musical revision wins; an obsolete future mix is discarded.
    assert(project(k,&a,1,old,3,3,0.25f,0));assert(project(k,&b,1,pending,4,4,-0.25f,0.125f));advance(k,96000);assert(lg_revision(k)==4&&lg_playing(k));assert(lg_gain_target(k,0)==0&&std::abs(lg_gain_target(k,1)-gain(-6))<1e-6f&&lg_filter_target(k)==-0.25f);
    assert(!project(k,&a,1,old,2,2));
    // Stop adopts the pending model silently; Panic clears pending-project FX.
    assert(project(k,&a,1,old,5,5,1,0.5f));lg_play(k,0);std::array<float,128> l{},r{};block(k,l.data(),r.data(),128);assert(lg_revision(k)==5&&!lg_playing(k));for(float v:l)assert(v==0);for(float v:r)assert(v==0);
    assert(project(k,&a,1,old,6,6,1,0.5f));lg_panic(k);block(k,l.data(),r.data(),128);assert(lg_revision(k)==6&&!lg_playing(k)&&lg_filter_target(k)==0&&lg_delay_target(k)==0);for(float v:l)assert(v==0);for(float v:r)assert(v==0);
    assert(project(k,&a,1,old,7,7,1,0.5f));lg_panic(k);lg_play(k,1);block(k,l.data(),r.data(),128);assert(lg_filter_target(k)==0&&lg_delay_target(k)==0);
    lg_destroy(k);
}

static void presetBoundary(){
    auto*k=lg_create(96000);const int32_t legacy[2]={1,1},current[2]={2,2},roles[2]={0,1};const auto m=mix(1);const LGNote cymbal={3840,120,36,110,1,9,1};
    assert(project(k,nullptr,0,m,1,1,0,0,legacy,240,roles));lg_play(k,1);advance(k,9600);
    assert(project(k,&cymbal,1,m,2,1,0,0,current,240,roles));assert(lg_pad(k,9,110));advance(k,70000);
    std::array<float,1024> l{},r{};block(k,l.data(),r.data(),1024);for(float v:l)assert(v==0); // pending v2 must not extend the old v1 preview
    const auto clock=lg_clock(k);advance(k,96000-int(clock));assert(lg_revision(k)==1);
    advance(k,72000);assert(lg_revision(k)==2);block(k,l.data(),r.data(),1024);float energy=0;for(float v:l)energy+=std::abs(v);assert(energy>0.0001f); // v2 one-shot is still sounding at 0.75s
    lg_destroy(k);
}

static void reorderedPads(){
    auto*k=lg_create(48000);
    const std::array<LGProjectTrack,2> original{{{{-61,-1,0},2,0,0,11},{{0,1,1},2,1,9,22}}};
    const std::array<LGProjectTrack,3> expanded{{{{0,-1,1},2,1,9,22},{{-61,1,0},2,2,1,33},{{-61,1,0},2,0,0,11}}};
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,1,1,original.data(),2,0,0,0));lg_play(k,1);advance(k,4800);
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,2,2,expanded.data(),3,0,0,0));assert(lg_pad(k,0,110));
    std::array<float,1024> l{},r{};block(k,l.data(),r.data(),1024);float left=0,right=0;for(int i=0;i<1024;i++){left+=std::abs(l[i]);right+=std::abs(r[i]);}assert(left<1e-5f&&right>0.1f&&lg_revision(k)==1);
    advance(k,48000-int(lg_clock(k))+512);assert(lg_revision(k)==2&&lg_playing(k));assert(lg_pad(k,0,110));block(k,l.data(),r.data(),1024);left=right=0;for(int i=0;i<1024;i++){left+=std::abs(l[i]);right+=std::abs(r[i]);}assert(left>0.1f&&right<1e-5f);
    // Removing the drum track while stopped also clears old-index one-shots.
    const LGProjectTrack onlyBass={{0,1,1},2,2,1,33};assert(lg_submit_project(k,nullptr,0,240,0,15360,1,3,3,&onlyBass,1,0,0,0));lg_play(k,0);block(k,l.data(),r.data(),1024);assert(lg_revision(k)==3&&!lg_playing(k));assert(lg_pad(k,0,110));block(k,l.data(),r.data(),1024);for(int i=0;i<1024;i++)assert(l[i]==0&&r[i]==0);
    // Stopped audition uses the adopted order as well, without starting clock.
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,4,4,expanded.data(),3,0,0,0));assert(lg_pad(k,0,110));block(k,l.data(),r.data(),1024);left=right=0;for(int i=0;i<1024;i++){left+=std::abs(l[i]);right+=std::abs(r[i]);}assert(left>0.1f&&right<1e-5f&&!lg_playing(k));
    advance(k,48000);lg_preview(k,60);block(k,l.data(),r.data(),1024);for(int i=0;i<1024;i++)assert(l[i]==0&&r[i]==0); // harmony is now muted at index2; do not audition through audible drum index0
    lg_destroy(k);
}

static void oneBarLoopAndSeek(){
    auto*k=lg_create(48000);const LGProjectTrack a={{0,-1,1},2,0,0,7},b={{0,1,1},2,3,2,8};const LGNote note={0,3840,60,100,0,-1,0};
    assert(lg_submit_project(k,&note,1,240,0,3840,1,1,1,&a,1,0,0,0));lg_play(k,1);advance(k,24000);
    assert(lg_submit_project(k,&note,1,240,0,3840,1,2,2,&b,1,0,0,0));advance(k,24000);assert(lg_revision(k)==1);advance(k,1);assert(lg_revision(k)==2&&lg_playing(k)&&lg_tick(k)==0);
    // A boundary seek adopts once without issuing Stop or resetting the clock.
    assert(lg_submit_project(k,&note,1,240,0,15360,1,3,3,&a,1,0,0,0));const auto before=lg_clock(k);lg_seek(k,3840);advance(k,1);assert(lg_revision(k)==3&&lg_playing(k)&&lg_tick(k)==3840&&lg_clock(k)==before+1);
    lg_destroy(k);
}

static void frozenHistoryLayout(){
    auto*k=lg_create(48000);const LGNote note={0,15360,60,110,0,-1,0};
    const std::array<LGProjectTrack,2> old{{{{0,-1,1},2,0,0,11},{{-61,1,0},2,2,1,22}}},next{{{{0,1,1},2,2,1,22},{{-61,-1,0},2,0,0,11}}};
    assert(lg_submit_project(k,&note,1,240,0,15360,1,1,1,old.data(),2,0,0,0));lg_perform_begin(k,1,1,0,0);advance(k,24000);assert(lg_perform_queue(k,3,960,0,0,0));advance(k,1);assert(lg_perform_repeat(k)==960);
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,2,2,next.data(),2,0,0,0));advance(k,48000-int(lg_clock(k))+1024);assert(lg_revision(k)==2&&lg_playing(k));
    std::array<float,1024> l{},r{};block(k,l.data(),r.data(),1024);for(int i=0;i<1024;i++)assert(l[i]==0&&r[i]==0);assert(lg_perform_repeat(k)==0);lg_destroy(k);
}

static void keyedPreviewAndRoutingRetention(){
    auto*k=lg_create(48000);const std::array<LGProjectTrack,2> before{{{{0,-1,1},2,0,0,11},{{-61,1,0},2,2,1,22}}},after{{{{-61,-1,0},2,2,1,22},{{0,1,1},2,0,0,11}}};
    assert(lg_submit_project(k,nullptr,0,240,0,15360,1,1,1,before.data(),2,0,0,0));advance(k,1);
    // The control thread sees the old index, then audio adopts a new one before
    // consuming the queued preview. Its stable key must still play on the right.
    assert(lg_note_preview_track(k,60,11));assert(lg_submit_project(k,nullptr,0,240,0,15360,1,2,2,after.data(),2,0,0,0));
    std::array<float,1024> l{},r{};block(k,l.data(),r.data(),1024);float left=0,right=0;for(int i=0;i<1024;i++){left+=std::abs(l[i]);right+=std::abs(r[i]);}assert(left<1e-5f&&right>0.1f);
    assert(lg_note_preview_track(k,60,11));const LGProjectTrack survivor={{0,-1,1},2,2,1,22};assert(lg_submit_project(k,nullptr,0,240,0,15360,1,3,3,&survivor,1,0,0,0));block(k,l.data(),r.data(),1024);for(int i=0;i<1024;i++)assert(l[i]==0&&r[i]==0);
    assert(!lg_note_preview_track(k,60,0)&&!lg_note_preview_track(k,128,11)&&!lg_note_preview_track(nullptr,60,11));
    int32_t generations[3]={};const int count=lg_snapshot_generations(k,generations,3);assert(count>=1&&count<=3);assert(std::find(generations,generations+count,lg_revision(k))!=generations+count);assert(!lg_snapshot_generations(nullptr,generations,3)&&!lg_snapshot_generations(k,nullptr,3)&&!lg_snapshot_generations(k,generations,0));
    lg_destroy(k);
}

static void validation(){
    auto*k=lg_create(48000);auto m=mix(0);const LGNote note={0,960,60,100,0,-1,0};
    std::array<LGProjectTrack,2> tracks{{{m[0],2,0,0,1},{m[1],2,3,1,2}}};
    assert(!lg_submit_project(nullptr,&note,1,120,0,3840,1,1,1,tracks.data(),2,0,0,0));
    assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,0,tracks.data(),2,0,0,0));
    assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,nullptr,2,0,0,0));
    auto invalid=tracks;invalid[1].presetVersion=5;assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,invalid.data(),2,0,0,0));
    invalid=tracks;invalid[1].identity=1;assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,invalid.data(),2,0,0,0));
    invalid=tracks;invalid[1].identity=0;assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,invalid.data(),2,0,0,0));
    invalid=tracks;invalid[1].instrument=4;assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,invalid.data(),2,0,0,0));
    invalid=tracks;invalid[1].midiChannel=16;assert(!lg_submit_project(k,&note,1,120,0,3840,1,1,1,invalid.data(),2,0,0,0));
    auto bad=m;bad[1].pan=std::numeric_limits<float>::quiet_NaN();assert(!project(k,&note,1,bad,1,1));bad=m;bad[0].audible=2;assert(!project(k,&note,1,bad,1,1));
    const LGNote wrongTrack={0,960,60,100,2,-1,0};assert(!project(k,&wrongTrack,1,m,1,1));assert(!lg_mix_snapshot_for_revision(k,m.data(),2,0,0,0,-1));
    lg_destroy(k);
}

static void concurrentOwnership(){
    auto*k=lg_create(48000);auto first=mix(1,0,0.5f);LGNote n={0,15360,64,100,1,-1,3};assert(project(k,&n,1,first,1,1,0.5f,0.25f));lg_play(k,1);advance(k,512);
    std::atomic<bool> done{false};
    std::thread producer([&]{for(int revision=2;revision<=2000;revision++){const bool even=revision%2==0;auto m=mix(even?0:1,0,even?-0.5f:0.5f);const LGNote note={0,15360,60+revision%24,100,even?0:1,-1,3};while(!project(k,&note,1,m,revision,uint64_t(revision),even?-0.5f:0.5f,even?0.125f:0.25f)){}}done.store(true,std::memory_order_release);});
    std::array<float,257> l{},r{};int renders=0;
    while(!done.load(std::memory_order_acquire)||renders<4000){block(k,l.data(),r.data(),int(l.size()));const int revision=lg_revision(k);const bool even=revision%2==0;assert(lg_gain_target(k,0)==(even?1:0)&&lg_gain_target(k,1)==(even?0:1));assert(lg_pan_target(k,0)==(even?-0.5f:0.5f));assert(lg_filter_target(k)==(even?-0.5f:0.5f)&&lg_delay_target(k)==(even?0.125f:0.25f));for(float value:l)assert(std::isfinite(value)&&std::abs(value)<=0.98f);renders++;}
    producer.join();advance(k,96000);assert(lg_revision(k)==2000&&lg_playing(k));lg_destroy(k);
}

int main(){
    validation();for(double rate:{44100.,48000.,96000.,192000.})atomicBoundary(rate);versionedControls();presetBoundary();reorderedPads();oneBarLoopAndSeek();frozenHistoryLayout();keyedPreviewAndRoutingRetention();concurrentOwnership();assert(renderAllocations.load()==0);
    std::cout<<"Live project snapshots: exact music/mix/preset boundary, phase-preserving layout changes, stereo de-click, revision-scoped controls, Stop/Panic, 2,000 concurrent publications and zero render allocations passed\n";
}
