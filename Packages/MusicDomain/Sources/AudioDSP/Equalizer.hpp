#pragma once
#include "GrillaKernel.h"
#include <array>
#include <algorithm>
#include <cmath>

// Four cascaded RBJ biquads per strip, designed on the control thread.
struct EQCoefficients {
    double b0=1,b1=0,b2=0,a1=0,a2=0;
    bool operator==(const EQCoefficients& o) const {
        return b0==o.b0&&b1==o.b1&&b2==o.b2&&a1==o.a1&&a2==o.a2;
    }
};
using EQCurve=std::array<EQCoefficients,4>;
using EQDesk=std::array<EQCurve,9>;
inline EQCoefficients eqDesign(const LGEQBand& band,double rate) {
    if(!band.kind) return {};
    const double w=2*3.141592653589793*std::min(double(band.frequency),rate*0.47)/rate;
    const double c=std::cos(w), alpha=std::sin(w)/(2*band.q);
    const double A=std::pow(10.,band.gainDB/40.), beta=2*std::sqrt(A)*alpha;
    double b0,b1,b2,a0,a1,a2;
    switch(band.kind){
    case 1: b0=1+alpha*A;b1=-2*c;b2=1-alpha*A;a0=1+alpha/A;a1=b1;a2=1-alpha/A;break;
    case 2: b0=A*((A+1)-(A-1)*c+beta);b1=2*A*((A-1)-(A+1)*c);b2=A*((A+1)-(A-1)*c-beta);
            a0=(A+1)+(A-1)*c+beta;a1=-2*((A-1)+(A+1)*c);a2=(A+1)+(A-1)*c-beta;break;
    case 3: b0=A*((A+1)+(A-1)*c+beta);b1=-2*A*((A-1)+(A+1)*c);b2=A*((A+1)+(A-1)*c-beta);
            a0=(A+1)-(A-1)*c+beta;a1=2*((A-1)-(A+1)*c);a2=(A+1)-(A-1)*c-beta;break;
    case 4: b0=(1+c)/2;b1=-(1+c);b2=b0;a0=1+alpha;a1=-2*c;a2=1-alpha;break;
    case 5: b0=(1-c)/2;b1=1-c;b2=b0;a0=1+alpha;a1=-2*c;a2=1-alpha;break;
    default:return {};
    }
    if(band.kind<=3&&band.gainDB==0)return {};
    return {b0/a0,b1/a0,b2/a0,a1/a0,a2/a0};
}
inline bool eqPrepare(const LGEQBand* bands, double rate, EQDesk& desk){
    if(!bands){desk={};return true;}
    for(auto &curve:desk)for(auto &c:curve){
        const auto &b=*bands++;
        if(b.kind<0||b.kind>5)return false;
        if(b.kind && (!(b.frequency>=20&&b.frequency<=20000)||!(b.q>=0.25&&b.q<=8)||!(b.gainDB>=-18&&b.gainDB<=18)))return false;
        c=eqDesign(b,rate);
    }
    return true;
}
struct EQCascade {
    EQCurve curve{};
    std::array<double,4> z1{},z2{};
    bool active=false;
    double process(double x){
        if(!active)return x;
        for(size_t i=0;i<curve.size();i++){
            const auto &c=curve[i];
            const double y=x*c.b0+z1[i];
            z1[i]=c.b1*x-c.a1*y+z2[i]; z2[i]=c.b2*x-c.a2*y;
            if(std::abs(z1[i])<1e-24)z1[i]=0;
            if(std::abs(z2[i])<1e-24)z2[i]=0;
            x=y;
        }
        return x;
    }
};
struct EQChannel {
    EQCascade current{},previous{};
    int fade=0,total=1;
    void set(const EQCurve& curve,int frames,bool reset){
        if(!reset&&current.curve==curve)return;
        previous=current;current={};current.curve=curve;
        current.active=curve!=EQCurve{};
        total=frames;fade=reset?0:frames;
    }
    float process(float input){
        const double x=current.process(input);
        if(!fade)return float(x);
        const double weight=double(fade--)/total;
        return float(x+(previous.process(input)-x)*weight);
    }
};
