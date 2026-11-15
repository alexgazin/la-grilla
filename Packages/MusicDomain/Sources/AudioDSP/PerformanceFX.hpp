#pragma once
#include <array>
#include <vector>
#include <algorithm>
#include <cmath>

/// Audio-thread-owned state. Buffers are allocated once by the kernel constructor.
class PerformanceFX {
    double sr;int historySize,delaySize,write=0,available=0,repeatLength=0,repeatPhase=0,seam=0;
    int delayWrite=0,delayAvailable=0,delayFrames=1;
    bool repeatWanted=false;
    float repeatMix=0,filter=0,delayWet=0,coefficientL=1,coefficientH=0.001f;
    float targetFilter=0,targetWet=0,targetL=1,targetH=0.001f,ramp;
    std::array<std::vector<float>,8> history,frozen;
    std::vector<float> delayL,delayR;
    std::array<float,8> lastRepeat{},seamSample{};
    std::array<float,2> low1{},low2{},high1{},high2{};
public:
    explicit PerformanceFX(double rate):sr(rate),historySize(int(std::ceil(rate*4))+1),delaySize(int(std::ceil(rate*2))+1),ramp(float(1-std::exp(-1/(rate*0.005)))),delayL(delaySize),delayR(delaySize) {
        for(auto &bus:history){bus.resize(historySize);}for(auto &bus:frozen){bus.resize(historySize);}
    }
    void reset(){
        write=available=repeatLength=repeatPhase=seam=delayWrite=delayAvailable=0;repeatWanted=false;repeatMix=0;
        low1={};low2={};high1={};high2={};lastRepeat={};seamSample={};filter=targetFilter;delayWet=targetWet;coefficientL=targetL;coefficientH=targetH;
        // Logical validity counters invalidate old ring contents without clearing megabytes in RT.
    }
    void prepare(float value,float wet,double bpm){
        targetFilter=std::clamp(value,-1.f,1.f);targetWet=std::clamp(wet,0.f,0.5f);
        const double low=std::min(sr*0.45,20*std::pow(1000.,1+std::min(0.f,targetFilter)));
        const double high=std::min(sr*0.45,20*std::pow(1000.,std::max(0.f,targetFilter)));
        targetL=float(1-std::exp(-6.283185307179586*low/sr));targetH=float(1-std::exp(-6.283185307179586*high/sr));
        delayFrames=std::clamp(int(std::round(sr*30/bpm)),1,delaySize-1);
    }
    bool beginRepeat(int ticks,double bpm){
        if(ticks!=240&&ticks!=480&&ticks!=960&&ticks!=1920)return false;
        const int frames=int(std::round(double(ticks)/960*60/bpm*sr));
        if(frames<=0||frames>=historySize||available<frames)return false;
        const int start=(write+historySize-frames)%historySize,first=std::min(frames,historySize-start);
        for(int t=0;t<8;t++){std::copy(history[t].begin()+start,history[t].begin()+start+first,frozen[t].begin());if(first<frames)std::copy(history[t].begin(),history[t].begin()+frames-first,frozen[t].begin()+first);}
        repeatLength=frames;repeatPhase=0;repeatWanted=true;seam=0;return true;
    }
    void releaseRepeat(){repeatWanted=false;}
    bool repeating()const{return repeatWanted;}
    int historyFrames()const{return available;}
    void processBuses(float *buses,bool running){
        if(!running)repeatWanted=false;
        repeatMix+=((repeatWanted?1.f:0.f)-repeatMix)*ramp;
        if(!repeatWanted&&repeatMix<0.00001f){repeatLength=0;repeatMix=0;}
        if(running){for(int t=0;t<8;t++)history[t][write]=buses[t];write=(write+1)%historySize;available=std::min(historySize,available+1);}
        if(repeatLength>0){
            const int seamLength=std::max(1,int(sr*0.003));
            for(int t=0;t<8;t++){
                float sample=frozen[t][repeatPhase];
                if(seam>0){float amount=float(seam)/float(seamLength);sample=sample*(1-amount)+seamSample[t]*amount;}
                lastRepeat[t]=sample;buses[t]=buses[t]*(1-repeatMix)+sample*repeatMix;
            }
            if(seam>0)seam--;
            if(++repeatPhase>=repeatLength){repeatPhase=0;seam=seamLength;seamSample=lastRepeat;}
        }
    }
    void process(float &left,float &right){
        filter+=(targetFilter-filter)*ramp;delayWet+=(targetWet-delayWet)*ramp;
        coefficientL+=(targetL-coefficientL)*ramp;coefficientH+=(targetH-coefficientH)*ramp;
        float values[2]={left,right};const float wet=std::min(1.f,std::abs(filter)/0.04f);
        for(int i=0;i<2;i++){
            float dry=values[i];low1[i]+=coefficientL*(dry-low1[i]);low2[i]+=coefficientL*(low1[i]-low2[i]);
            high1[i]+=coefficientH*(dry-high1[i]);float high=dry-high1[i];high2[i]+=coefficientH*(high-high2[i]);high-=high2[i];
            values[i]=dry*(1-wet)+(filter<0?low2[i]:high)*wet;
        }
        const int read=(delayWrite+delaySize-delayFrames)%delaySize;
        const float echoL=delayAvailable>=delayFrames?delayL[read]:0,echoR=delayAvailable>=delayFrames?delayR[read]:0;
        delayL[delayWrite]=values[0]+echoR*0.32f;delayR[delayWrite]=values[1]+echoL*0.32f;
        delayWrite=(delayWrite+1)%delaySize;delayAvailable=std::min(delaySize,delayAvailable+1);
        left=values[0]+echoL*delayWet;right=values[1]+echoR*delayWet;
    }
};
