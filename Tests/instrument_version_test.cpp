#include "GrillaKernel.h"
#include <vector>
#include <cassert>
#include <cmath>
#include <iostream>
float lateCrash(double rate,int version){
 auto*k=lg_create(rate);assert(lg_preset_version(k,1,version));assert(!lg_preset_version(k,1,3));lg_pad(k,9,110);std::vector<float> l(512),r(512);float peak=0;
 for(int frame=0;frame<int(rate);){int count=std::min(512,int(rate)-frame);lg_render(k,l.data(),r.data(),count);for(int i=0;i<count;i++)if(frame+i>int(rate*.3)&&frame+i<int(rate*.4))peak=std::max(peak,std::abs(l[i]));frame+=count;}
 lg_destroy(k);return peak;
}
int main(){
 assert(lateCrash(192000,1)==0);assert(lateCrash(192000,2)>0.001f);assert(lateCrash(96000,2)>0.001f);assert(lateCrash(44100,2)>0.001f);
 std::cout<<"Instrument versions: legacy v1 remains selectable; v2 retains cymbal tails through 44.1–192 kHz and rejects unknown presets\n";
}
