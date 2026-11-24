// I54 MPE: two notes on two MIDI channels of one controller bend independently (±48 semitones on
// member channels with MPE on), channel pressure shapes only its own note, and without MPE a
// channel bends ±2 semitones.
#include "GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

namespace {
constexpr double Pi=3.14159265358979323846;
double power(const std::vector<float>&v,double frequency,int from,int count){
    const double w=2*Pi*frequency/48000,c=2*std::cos(w);double s1=0,s2=0;
    for(int i=from;i<from+count;i++){const double s=v[size_t(i)]+c*s1-s2;s2=s1;s1=s;}
    return (s1*s1+s2*s2-c*s1*s2)/count;
}
double hz(double pitch){return 440*std::pow(2,(pitch-69)/12);}
struct Rig{LGKernel*k;LGMIDIHub*h;uint64_t time=0;std::vector<float> left;
    explicit Rig(bool mpe){k=lg_create(48000);h=lg_midi_create();assert(lg_submit(k,nullptr,0,120,0,3840,1,1));lg_midi_configure(h,256,0,0,65535);lg_mpe(k,mpe?1:0);}
    ~Rig(){lg_destroy(k);lg_midi_destroy(h);}
    void send(std::initializer_list<uint8_t> bytes){std::vector<uint8_t> b(bytes);assert(lg_midi_push(h,256,time,b.data(),int(b.size())));}
    void render(int frames){left.assign(size_t(frames),0);auto r=std::vector<float>(size_t(frames),0.f);for(int pos=0;pos<frames;pos+=512){const int n=std::min(512,frames-pos);lg_render_midi(k,h,time,48000,left.data()+pos,r.data()+pos,n);time+=uint64_t(n);}}
};
/// 14-bit bend for `semitones` at `range`.
void bend(Rig&rig,int channel,double semitones,double range){const int value=std::min(16383,int(std::lround(8192+8192*semitones/range)));rig.send({uint8_t(0xE0|channel),uint8_t(value&127),uint8_t((value>>7)&127)});}
}

int main(){
    {   // MPE: note 60 on channel 2 bends +5 semitones; note 67 on channel 3 stays.
        Rig rig(true);
        rig.send({0x91,60,100});rig.send({0x92,67,100});rig.render(2400);
        bend(rig,1,5,48);rig.render(9600);
        const double bent=power(rig.left,hz(65),2400,7200),original=power(rig.left,hz(60),2400,7200),other=power(rig.left,hz(67),2400,7200),wrong=power(rig.left,hz(72),2400,7200);
        assert(bent>20*original);            // the first note moved
        assert(other>20*wrong);              // the second did not
        // Pressure 0 on channel 2 makes only that note quieter (0.3 → about −10 dB).
        rig.send({0xD1,0});rig.render(9600);
        const double soft=power(rig.left,hz(65),2400,7200),steady=power(rig.left,hz(67),2400,7200);
        // Both notes decay alike, so compare them with each other: 0.3² ≈ 0.09 in power.
        const double relative=(soft/steady)/(bent/other);
        assert(relative>0.06&&relative<0.13);
        // Bending back to the centre restores the pitch; note-offs end both.
        bend(rig,1,0,48);rig.render(9600);assert(power(rig.left,hz(60),2400,7200)>20*power(rig.left,hz(65),2400,7200));
        rig.send({0x81,60,0});rig.send({0x82,67,0});rig.render(9600);
        for(size_t i=4800;i<rig.left.size();i++)assert(rig.left[i]==0);
    }
    {   // Without MPE a full bend is a whole tone, even on channel 2.
        Rig rig(false);
        rig.send({0x91,60,100});bend(rig,1,2,2);rig.render(12000);
        assert(power(rig.left,hz(62),2400,9600)>20*power(rig.left,hz(60),2400,9600));
    }
    std::printf("MPE: two channels bend independently (±48 with MPE, ±2 without), pressure shapes only its own note, centre restores the pitch\n");
}
