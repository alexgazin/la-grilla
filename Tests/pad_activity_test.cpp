// U37 pad activity: every pad counts how often it sounds, from the song and from live hits, so the
// interface can light the pads that are playing; other pads stay at zero.
#include "GrillaKernel.h"
#include <cassert>
#include <cstdio>
#include <vector>

int main(){
    auto*k=lg_create(48000);
    // 120 BPM: a beat (960 ticks) is half a second. Kick on beats 1 and 2, snare between them.
    const LGNote notes[]={{0,240,36,100,1,0,0},{480,240,38,100,1,2,0},{960,240,36,100,1,0,0}};
    assert(lg_submit(k,notes,3,120,0,3840,0,1));
    for(int pad=0;pad<16;pad++)assert(lg_pad_hits(k,pad)==0);
    lg_play(k,1);
    std::vector<float> l(512),r(512);
    for(int f=0;f<48000*3/4;f+=512)lg_render(k,l.data(),r.data(),512);   // 0.75 s: ticks 0…1440
    assert(lg_pad_hits(k,0)==2);
    assert(lg_pad_hits(k,2)==1);
    assert(lg_pad_hits(k,3)==0);
    // A live hit counts on its own pad.
    assert(lg_pad(k,3,100));
    lg_render(k,l.data(),r.data(),512);
    assert(lg_pad_hits(k,3)==1);
    assert(lg_pad_hits(k,16)==0&&lg_pad_hits(k,-1)==0&&lg_pad_hits(nullptr,0)==0);
    lg_destroy(k);
    std::printf("Pad activity: song and live hits count on their own pads (kick 2, snare 1, live 1), others stay 0\n");
}
