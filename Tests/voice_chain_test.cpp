// I32 voice treatment on references: the compressor holds a −6 dBFS sine at threshold + excess/ratio,
// leaves quiet signals alone; the de-esser cuts a 7 kHz hiss band but not a 300 Hz voice tone;
// presets keep the peak under −1 dBFS and cut rumble below the voice.
#include "GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double Pi=3.14159265358979323846;
constexpr int Rate=48000;
std::vector<float> tone(std::initializer_list<std::pair<double,double>> parts,double seconds){
    std::vector<float> v(size_t(seconds*Rate));
    for(size_t i=0;i<v.size();i++){double s=0;for(auto [f,a]:parts)s+=a*std::sin(2*Pi*f*double(i)/Rate);v[i]=float(s);}
    return v;
}
double peakDB(const std::vector<float>&v,size_t from){float p=0;for(size_t i=from;i<v.size();i++)p=std::max(p,std::abs(v[i]));return 20*std::log10(p);}
double band(const std::vector<float>&v,double f,size_t from){
    const double w=2*Pi*f/Rate,c=2*std::cos(w);double s1=0,s2=0;
    for(size_t i=from;i<v.size();i++){const double s=v[i]+c*s1-s2;s2=s1;s1=s;}
    return 10*std::log10((s1*s1+s2*s2-c*s1*s2)/double(v.size()-from));
}
}

int main(){
    {   // Compressor: −6 dBFS in, threshold −18, ratio 4 → −15 dBFS steady state.
        auto x=tone({{1000,0.5}},1.0);
        assert(lg_voice_compress(x.data(),int(x.size()),Rate,-18,4,2,80,0));
        assert(std::abs(peakDB(x,24000)-(-15))<0.5);
        // Below the threshold nothing changes.
        auto quiet=tone({{1000,0.05}},0.5),copy=quiet;
        assert(lg_voice_compress(quiet.data(),int(quiet.size()),Rate,-18,4,2,80,0));
        for(size_t i=0;i<quiet.size();i++)assert(quiet[i]==copy[i]);
        assert(!lg_voice_compress(x.data(),int(x.size()),Rate,-18,0.5f,2,80,0));
    }
    {   // De-esser: a loud 7 kHz band goes down by about the maximum; 300 Hz stays.
        auto x=tone({{300,0.3},{7000,0.3}},1.0);const auto dry=x;
        assert(lg_voice_deess(x.data(),int(x.size()),Rate,5500,-30,9));
        const double hiss=band(x,7000,12000)-band(dry,7000,12000),voice=band(x,300,12000)-band(dry,300,12000);
        assert(hiss< -6&&hiss> -10);
        assert(std::abs(voice)<0.5);
        // Without sibilance the de-esser leaves the voice alone.
        auto plain=tone({{300,0.3}},0.5);const auto before=plain;
        assert(lg_voice_deess(plain.data(),int(plain.size()),Rate,5500,-30,9));
        assert(std::abs(band(plain,300,6000)-band(before,300,6000))<0.1);
    }
    {   // Presets: rumble below the voice is cut, the peak stays under −1 dBFS.
        for(int preset=1;preset<=3;preset++){
            auto x=tone({{40,0.4},{220,0.4},{6500,0.2}},1.0);const auto dry=x;
            assert(lg_voice_treat(x.data(),int(x.size()),Rate,preset));
            assert(peakDB(x,0)<=-0.99);
            assert(band(x,40,12000)-band(x,220,12000)<band(dry,40,12000)-band(dry,220,12000)-6);
        }
        auto x=tone({{220,0.4}},0.1);assert(!lg_voice_treat(x.data(),int(x.size()),Rate,4)&&!lg_voice_treat(x.data(),int(x.size()),Rate,0));
    }
    std::printf("Voice chain: compressor −6 → −15 dBFS at 4:1 from −18, untouched below; de-esser cuts 7 kHz by 6–10 dB, 300 Hz within 0.5 dB; presets cut rumble and stay under −1 dBFS\n");
}
