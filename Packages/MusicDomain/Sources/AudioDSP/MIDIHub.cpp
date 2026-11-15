#include "MIDIHub.hpp"
#include <new>
extern "C" {
LGMIDIHub *lg_midi_create(){return new(std::nothrow) LGMIDIHub();}
void lg_midi_destroy(LGMIDIHub*h){delete h;}
void lg_midi_configure(LGMIDIHub*h,uint32_t handle,int track,int instrument,int channels){
    const int slot=int(handle&255);if(!h||handle<256||slot>=16||track<0||track>=8||instrument<0||instrument>3)return;
    h->connections[slot].routing.store(uint32_t(channels&65535)|(uint32_t(track)<<16)|(uint32_t(instrument)<<20));h->connections[slot].handle.store(handle,std::memory_order_release);h->panic.fetch_or(1u<<slot);
}
void lg_midi_disconnect(LGMIDIHub*h,int slot){if(!h||slot<0||slot>=16)return;h->connections[slot].handle.store(0,std::memory_order_release);h->panic.fetch_or(1u<<slot);}
int lg_midi_push(LGMIDIHub*h,uint32_t handle,uint64_t time,const uint8_t*bytes,int count){
    const int slot=int(handle&255);if(!h||slot>=16||handle<256||!bytes||count<1)return 0;
    if(h->connections[slot].handle.load(std::memory_order_acquire)!=handle)return 0;
    if(count>1024){h->dropped.fetch_add(1);h->connections[slot].handle.store(0,std::memory_order_release);h->panic.fetch_or(1u<<slot);return 0;}
    for(int offset=0;offset<count;offset+=256){MIDIRawPacket p;p.time=time;p.handle=handle;p.count=uint16_t(std::min(256,count-offset));std::copy(bytes+offset,bytes+offset+p.count,p.bytes.begin());if(!h->packets.push(p)){h->dropped.fetch_add(1);h->connections[slot].handle.store(0,std::memory_order_release);h->panic.fetch_or(1u<<slot);return 0;}}
    return 1;
}
int lg_midi_monitor_pop(LGMIDIHub*h,LGMIDIEvent*events,int capacity){if(!h||!events||capacity<1||capacity>512)return 0;int count=0;while(count<capacity&&h->monitor.pop(events[count]))count++;return count;}
uint64_t lg_midi_late(LGMIDIHub*h){return h?h->late.load():0;}
uint64_t lg_midi_dropped(LGMIDIHub*h){return h?h->dropped.load():0;}
}
