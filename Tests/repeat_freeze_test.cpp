#include "PerformanceFX.hpp"
#include <cassert>
#include <iostream>
// The legacy eager-copy algorithm is a test reference, never linked into the app.
struct EagerRepeatReference {
 double sr;int capacity,write=0,size=0,phase=0,seam=0;bool wanted=false;float mix=0,ramp;
 std::array<std::vector<float>,8> history,frozen;std::array<float,8> last{},edge{};
 explicit EagerRepeatReference(double rate):sr(rate),capacity(int(std::ceil(rate*4))+1),ramp(float(1-std::exp(-1/(rate*.005)))){for(auto &b:history)b.resize(capacity);for(auto &b:frozen)b.resize(capacity);}
 void begin(int ticks,double bpm){size=int(std::round(ticks/960.0*60/bpm*sr));phase=seam=0;wanted=true;int start=(write+capacity-size)%capacity;for(int t=0;t<8;t++)for(int i=0;i<size;i++)frozen[t][i]=history[t][(start+i)%capacity];}
 void process(float *buses){mix+=((wanted?1.f:0.f)-mix)*ramp;if(!wanted&&mix<.00001f){size=0;mix=0;}for(int t=0;t<8;t++)history[t][write]=buses[t];write=(write+1)%capacity;if(!size)return;int fade=std::max(1,int(sr*.003));for(int t=0;t<8;t++){float sample=frozen[t][phase];if(seam>0){float amount=float(seam)/fade;sample=sample*(1-amount)+edge[t]*amount;}last[t]=sample;buses[t]=buses[t]*(1-mix)+sample*mix;}if(seam>0)seam--;if(++phase>=size){phase=0;seam=fade;edge=last;}}
};
int main(){
 for(double rate:{44100.,48000.,96000.,192000.}){
  PerformanceFX actual(rate);EagerRepeatReference reference(rate);float a[8],b[8],difference=0;
  const int second=int(rate),total=second*18;
  for(int frame=0;frame<total;frame++){
   if(frame==second*4){assert(actual.beginRepeat(1920,40));reference.begin(1920,40);}
   if(frame==second*14){actual.releaseRepeat();reference.wanted=false;}
   if(frame==second*15){assert(actual.beginRepeat(240,123));reference.begin(240,123);}
   if(frame==second*17){actual.releaseRepeat();reference.wanted=false;}
   for(int track=0;track<8;track++)a[track]=b[track]=float(((frame*(track+1))%10007)-5003)/10007;
   actual.processBuses(a,true);reference.process(b);
   for(int track=0;track<8;track++)difference=std::max(difference,std::abs(a[track]-b[track]));
  }
  assert(difference<1e-6f);
 }
 std::cout<<"Incremental repeat freeze matches the eager reference through long holds, releases and fresh captures at 44.1–192 kHz\n";
}
