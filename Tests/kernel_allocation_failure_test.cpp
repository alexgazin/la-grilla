#include "GrillaKernel.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>

namespace {
// No allocations in the instrumentation itself. Track only allocations made
// while constructing the kernel, including those freed by constructor unwinding.
bool tracking=false,throwNonStandard=false;
std::size_t attempted=0,failAt=0,outstanding=0;
std::array<void*,256> allocated{};
struct InjectedFailure {};
void begin(std::size_t failure=0,bool nonStandard=false){
    assert(outstanding==0);
    allocated.fill(nullptr);attempted=0;failAt=failure;throwNonStandard=nonStandard;tracking=true;
}
void*allocate(std::size_t size){
    if(tracking){
        ++attempted;
        if(failAt==attempted){if(throwNonStandard)throw InjectedFailure{};throw std::bad_alloc();}
    }
    void*pointer=std::malloc(size?size:1);
    if(!pointer)throw std::bad_alloc();
    if(tracking){
        bool recorded=false;
        for(auto &entry:allocated)if(!entry){entry=pointer;recorded=true;break;}
        assert(recorded);++outstanding;
    }
    return pointer;
}
void release(void*pointer)noexcept{
    if(!pointer)return;
    for(auto &entry:allocated)if(entry==pointer){entry=nullptr;assert(outstanding>0);--outstanding;break;}
    std::free(pointer);
}
void verifyRecovery(){
    auto*kernel=lg_create(48000);assert(kernel);
    const LGNote note={0,960,60,100,0,-1,0};
    assert(lg_submit(kernel,&note,1,120,0,3840,1,1));lg_play(kernel,1);
    std::array<float,256> left{},right{};
    lg_render(kernel,left.data(),right.data(),int(left.size()));
    assert(lg_clock(kernel)==left.size());
    float energy=0;
    for(std::size_t i=0;i<left.size();++i){assert(std::isfinite(left[i])&&std::isfinite(right[i]));energy+=std::abs(left[i])+std::abs(right[i]);}
    assert(energy>0);lg_destroy(kernel);
}
}

[[gnu::noinline]] void*operator new(std::size_t size){return allocate(size);}
[[gnu::noinline]] void*operator new[](std::size_t size){return allocate(size);}
[[gnu::noinline]] void operator delete(void*pointer)noexcept{release(pointer);}
[[gnu::noinline]] void operator delete[](void*pointer)noexcept{release(pointer);}
[[gnu::noinline]] void operator delete(void*pointer,std::size_t)noexcept{release(pointer);}
[[gnu::noinline]] void operator delete[](void*pointer,std::size_t)noexcept{release(pointer);}

int main(){
    begin();auto*kernel=lg_create(48000);assert(kernel);
    const auto constructorAllocations=attempted;
    assert(constructorAllocations>1&&outstanding==constructorAllocations);
    lg_destroy(kernel);assert(outstanding==0);tracking=false;
    // Index one fails the outer object. Every later index fails a real nested
    // member allocation, proving that constructor unwinding releases its prefix.
    for(std::size_t allocation=1;allocation<=constructorAllocations;++allocation){
        begin(allocation);kernel=lg_create(48000);
        assert(kernel==nullptr&&attempted==allocation&&outstanding==0);tracking=false;
        verifyRecovery();
    }
    begin(2,true);kernel=lg_create(48000);
    assert(kernel==nullptr&&attempted==2&&outstanding==0);tracking=false;
    verifyRecovery();
    begin();assert(lg_create(0)==nullptr&&lg_create(NAN)==nullptr&&lg_create(INFINITY)==nullptr);
    assert(attempted==0&&outstanding==0);tracking=false;
    std::cout<<"Kernel allocation failure: outer and "<<constructorAllocations-1
             <<" nested failures return null, fully unwind, recover finite timed rendering; non-standard exceptions contained\n";
}
