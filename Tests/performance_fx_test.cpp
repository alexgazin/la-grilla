#include "PerformanceFX.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
int main(){
    for(double rate:{44100.,48000.}){
        PerformanceFX fx(rate);fx.prepare(0,0,120);
        for(int i=0;i<20000;i++){float l=std::sin(i*0.01f),r=-l;const float before=l;fx.process(l,r);assert(l==before&&r==-before);}
    }
    PerformanceFX fx(48000);fx.prepare(0,0.5,120);fx.reset();
    float firstL=0,firstR=0,secondL=0,secondR=0;
    for(int i=0;i<=24000;i++){float l=i==0?1.f:0.f,r=0;fx.process(l,r);if(i==12000){firstL=l;firstR=r;}if(i==24000){secondL=l;secondR=r;}}
    assert(std::abs(firstL-0.5)<0.0001&&firstR==0);assert(secondL==0&&std::abs(secondR-0.16)<0.0001);
    fx.reset();for(int i=0;i<100000;i++){float l=0,r=0;fx.process(l,r);assert(l==0&&r==0);}
    float buses[8]={};assert(!fx.beginRepeat(240,120));
    for(int i=0;i<150000;i++){for(float &value:buses)value=float(i%8000)/8000;fx.processBuses(buses,true);}
    assert(fx.beginRepeat(1920,40));
    for(int i=0;i<6000;i++){for(float &value:buses)value=10;fx.processBuses(buses,true);if(i>5000)for(float value:buses)assert(value<1.001f);}
    fx.releaseRepeat();for(int i=0;i<6000;i++){for(float &value:buses)value=10;fx.processBuses(buses,true);}for(float value:buses)assert(std::abs(value-10)<0.001);
    fx.reset();assert(!fx.repeating());assert(!fx.beginRepeat(960,120));assert(!fx.beginRepeat(3840,120));
    std::cout<<"Performance FX: unity bypass, exact eighth-note stereo echoes, logical reset, bounded two-beat repeat and release passed\n";
}
