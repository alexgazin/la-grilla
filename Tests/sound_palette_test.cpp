#include "GrillaKernel.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <new>
#include <string>
#include <vector>

static thread_local bool insideRender=false;
static std::atomic<unsigned> renderAllocations{0};
[[gnu::noinline]] void*operator new(std::size_t size){if(insideRender)renderAllocations++;if(auto*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
[[gnu::noinline]] void*operator new[](std::size_t size){return ::operator new(size);}
[[gnu::noinline]] void operator delete(void*p)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p)noexcept{std::free(p);}
[[gnu::noinline]] void operator delete(void*p,std::size_t)noexcept{std::free(p);}[[gnu::noinline]] void operator delete[](void*p,std::size_t)noexcept{std::free(p);}

static void block(LGKernel*k,float*l,float*r,int count){insideRender=true;lg_render(k,l,r,count);insideRender=false;}
struct CachedKernel {double rate=0;int version=0,revision=0;LGKernel*kernel=nullptr;};
static std::array<CachedKernel,4> kernels{};
static void releaseKernels(){for(auto&entry:kernels){if(entry.kernel)lg_destroy(entry.kernel);entry={};}}
static std::vector<float> sound(double rate,int version,int instrument,int pad=-1,int pitch=60,
                                bool sequenced=false,bool directPreset=false,double seconds=0.18){
    auto found=std::find_if(kernels.begin(),kernels.end(),[&](const auto&entry){return entry.kernel&&entry.rate==rate&&entry.version==version;});
    if(found==kernels.end()){found=std::find_if(kernels.begin(),kernels.end(),[](const auto&entry){return !entry.kernel;});assert(found!=kernels.end());*found={rate,version,0,lg_create(rate)};}
    auto*k=found->kernel;assert(k);lg_panic(k);
    std::array<LGProjectTrack,4> tracks{};
    for(int i=0;i<4;i++)tracks[i]={{0,0,1},directPreset?2:version,i,i,uint64_t(i+1)};
    const LGNote note={0,1920,pitch,100,instrument,pad,instrument};
    assert(lg_submit_project(k,sequenced?&note:nullptr,sequenced?1:0,120,0,3840,0,++found->revision,1,tracks.data(),4,0,0,0));
    lg_seek(k,0);
    std::array<float,1> emptyL{},emptyR{};block(k,emptyL.data(),emptyR.data(),1);
    assert(emptyL[0]==0&&emptyR[0]==0);
    if(directPreset)assert(lg_preset_version(k,instrument,version));
    if(sequenced)lg_play(k,1);
    else if(pad>=0)assert(lg_pad(k,pad,100));
    else lg_note_preview(k,pitch,instrument,instrument);
    const int frames=int(rate*seconds);std::vector<float> result(frames);
    std::array<float,257> left{},right{};
    for(int frame=0;frame<frames;){
        const int count=std::min(frames-frame,int(left.size()));block(k,left.data(),right.data(),count);
        for(int i=0;i<count;i++){assert(std::isfinite(left[i])&&std::isfinite(right[i]));assert(std::abs(left[i])<=0.98f&&std::abs(right[i])<=0.98f);result[frame+i]=left[i];}
        frame+=count;
    }
    return result;
}
static double energy(const std::vector<float>&value){double result=0;for(float x:value)result+=double(x)*x;return result;}
static double shapeDistance(const std::vector<float>&a,const std::vector<float>&b){
    assert(a.size()==b.size());const double ea=energy(a),eb=energy(b);assert(ea>1e-8&&eb>1e-8);
    double difference=0;for(std::size_t i=0;i<a.size();i++){const double x=a[i]/std::sqrt(ea)-b[i]/std::sqrt(eb);difference+=x*x;}return std::sqrt(difference);
}
static void validity(){
    auto*k=lg_create(48000);assert(k);
    for(int version=1;version<=4;version++)assert(lg_preset_version(k,0,version));
    for(int version:{-1,0,5,100}){
        assert(!lg_preset_version(k,0,version));
        const LGProjectTrack invalid={{0,0,1},version,0,0,1};
        assert(!lg_submit_project(k,nullptr,0,120,0,3840,0,1,1,&invalid,1,0,0,0));
    }
    lg_destroy(k);
}
static void distinctPalettes(){
    for(double rate:{44100.0,48000.0,96000.0,192000.0}){
        releaseKernels();
        for(int instrument:{0,2,3}){
            const int pitch=instrument==2?36:instrument==3?72:60;
            const auto classic=sound(rate,2,instrument,-1,pitch),warm=sound(rate,3,instrument,-1,pitch),bright=sound(rate,4,instrument,-1,pitch);
            // Normalize energy first: a volume-only preset cannot pass.
            assert(shapeDistance(classic,warm)>0.08&&shapeDistance(classic,bright)>0.08&&shapeDistance(warm,bright)>0.12);
            for(int version:{3,4}){
                const auto snapshot=sound(rate,version,instrument,-1,pitch),direct=sound(rate,version,instrument,-1,pitch,false,true);
                assert(snapshot==direct);
                for(int extreme:{0,127})assert(energy(sound(rate,version,instrument,-1,extreme))>1e-12);
            }
        }
        for(int pad=0;pad<16;pad++){
            const auto classic=sound(rate,2,1,pad),warm=sound(rate,3,1,pad),bright=sound(rate,4,1,pad);
            assert(shapeDistance(classic,warm)>0.10&&shapeDistance(classic,bright)>0.10&&shapeDistance(warm,bright)>0.15);
            for(int version:{3,4}){
                assert(sound(rate,version,1,pad)==sound(rate,version,1,pad,60,true));
                assert(sound(rate,version,1,pad)==sound(rate,version,1,pad,60,false,true));
            }
        }
    }
    releaseKernels();
}
static void rateCorrectTails(){
    for(double rate:{44100.0,48000.0,96000.0,192000.0}){
        releaseKernels();
        const auto warm=sound(rate,3,1,9,60,false,false,1.2),bright=sound(rate,4,1,9,60,false,false,1.2);
        double warmLate=0,brightLate=0;
        for(int frame=int(rate*1.02);frame<int(rate*1.06);frame++){warmLate+=std::abs(warm[frame]);brightLate+=std::abs(bright[frame]);}
        assert(warmLate>0.001&&brightLate==0);
        for(int frame=int(rate*1.10);frame<int(warm.size());frame++)assert(warm[frame]==0&&bright[frame]==0);
    }
    releaseKernels();
}
static void polyphonyAndRetirement(){
    for(int version:{3,4}){
        auto*k=lg_create(48000);assert(k);
        std::array<LGProjectTrack,4> tracks{};for(int i=0;i<4;i++)tracks[i]={{-18,0,1},version,i,i,uint64_t(i+1)};
        std::array<LGNote,64> notes{};for(int i=0;i<64;i++){const int role=i%4;notes[i]={0,1920,36+i%60,110,role,role==1?i%16:-1,role};}
        assert(lg_submit_project(k,notes.data(),int(notes.size()),120,0,3840,0,1,1,tracks.data(),4,-6,0,0.2f));lg_play(k,1);
        std::array<float,256> l{},r{};double total=0;
        for(int frame=0;frame<48000;frame+=256){
            if(frame%(256*8)==0)for(int pad=0;pad<16;pad++)assert(lg_pad(k,pad,110));
            block(k,l.data(),r.data(),int(l.size()));
            for(int i=0;i<int(l.size());i++){assert(std::isfinite(l[i])&&std::isfinite(r[i]));assert(std::abs(l[i])<=0.98f&&std::abs(r[i])<=0.98f);total+=std::abs(l[i])+std::abs(r[i]);}
        }
        assert(total>1&&lg_overflows(k)==0);lg_panic(k);block(k,l.data(),r.data(),int(l.size()));
        for(int i=0;i<int(l.size());i++)assert(l[i]==0&&r[i]==0);
        lg_destroy(k);
    }
}
static void dumpClassic(){
    for(double rate:{44100.0,48000.0,96000.0,192000.0}){releaseKernels();for(int version:{1,2}){
        for(int instrument:{0,2,3})for(int pitch:{36,84}){const auto value=sound(rate,version,instrument,-1,pitch,false,false,0.08);assert(std::fwrite(value.data(),sizeof(float),value.size(),stdout)==value.size());}
        for(int pad=0;pad<16;pad++){const auto value=sound(rate,version,1,pad,60,false,false,0.08);assert(std::fwrite(value.data(),sizeof(float),value.size(),stdout)==value.size());}
    }}releaseKernels();
}
int main(int argc,char**argv){
    if(argc==2&&std::string(argv[1])=="--dump-classic"){dumpClassic();return 0;}
    validity();distinctPalettes();rateCorrectTails();polyphonyAndRetirement();assert(renderAllocations==0);
    std::cout<<"Sound palettes: Classic/Warm/Bright have distinct normalized waveforms for all roles and 16 pads at44.1–192kHz; live pad/sequencer and snapshot/direct presets match, tails rate-correct, output finite and allocation-free\n";
}
