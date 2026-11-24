#include "MIDIHub.hpp"
#include <new>
static void configureConnection(LGMIDIHub*h,uint32_t handle,uint64_t identity,int track,int instrument,int channels,bool keyboard=false){
    const int slot=int(handle&255);if(!h||handle<256||slot>=16||track<0||track>=8||instrument<0||instrument>3)return;
    auto &connection=h->connections[size_t(slot)];
    connection.configuration.fetch_add(1,std::memory_order_acq_rel);
    connection.routing.store(uint32_t(channels&65535)|(uint32_t(track)<<16)|(uint32_t(instrument)<<20)|(keyboard?screenKeyboardRoute:0u),std::memory_order_relaxed);
    connection.identity.store(identity,std::memory_order_relaxed);connection.handle.store(handle,std::memory_order_release);
    connection.configuration.fetch_add(1,std::memory_order_release);h->panic.fetch_or(1u<<slot);
}
extern "C" {
LGMIDIHub *lg_midi_create(){return new(std::nothrow) LGMIDIHub();}
void lg_midi_destroy(LGMIDIHub*h){delete h;}
void lg_midi_configure(LGMIDIHub*h,uint32_t handle,int track,int instrument,int channels){
    configureConnection(h,handle,0,track,instrument,channels);
}
void lg_midi_configure_track(LGMIDIHub*h,uint32_t handle,uint64_t identity,int track,int instrument,int channels){if(identity)configureConnection(h,handle,identity,track,instrument,channels);}
void lg_midi_configure_keyboard(LGMIDIHub*h,uint32_t handle,uint64_t identity,int track,int instrument){
    if(identity)configureConnection(h,handle,identity,track,instrument,65535,true);
}
void lg_midi_disconnect(LGMIDIHub*h,int slot){if(!h||slot<0||slot>=16)return;h->connections[slot].handle.store(0,std::memory_order_release);h->panic.fetch_or(1u<<slot);}
int lg_midi_push(LGMIDIHub*h,uint32_t handle,uint64_t time,const uint8_t*bytes,int count){
    const int slot=int(handle&255);if(!h||slot>=16||handle<256||!bytes||count<1)return 0;
    const auto configuration=h->connections[slot].configuration.load(std::memory_order_acquire);
    if(configuration&1||!h->currentBinding(slot,handle,configuration))return 0;
    if(count>1024){lg_midi_input_overflow(h,handle);return 0;}
    for(int offset=0;offset<count;offset+=256){MIDIRawPacket p;p.time=time;p.handle=handle;p.configuration=configuration;p.count=uint16_t(std::min(256,count-offset));std::copy(bytes+offset,bytes+offset+p.count,p.bytes.begin());if(!h->currentBinding(slot,handle,configuration))return 0;if(!h->packets.push(p)){lg_midi_input_overflow(h,handle);return 0;}}
    return 1;
}
int lg_midi_monitor_pop(LGMIDIHub*h,LGMIDIEvent*events,int capacity){if(!h||!events||capacity<1||capacity>512)return 0;int count=0;MIDIMonitored event;for(int n=0;n<512&&count<capacity&&h->monitor.pop(event);n++){if(event.handle&&!h->currentBinding(event.event.source,event.handle,event.configuration))continue;events[count++]=event.event;}return count;}
uint64_t lg_midi_late(LGMIDIHub*h){return h?h->late.load():0;}
uint64_t lg_midi_dropped(LGMIDIHub*h){return h?h->dropped.load():0;}
int lg_midi_connected(LGMIDIHub*h,uint32_t handle){const int slot=int(handle&255);return h&&slot<16&&handle>=256&&h->connections[slot].handle.load()==handle;}
void lg_midi_input_overflow(LGMIDIHub*h,uint32_t handle){const int slot=int(handle&255);if(!h||slot>=16||handle<256)return;if(h->connections[slot].handle.compare_exchange_strong(handle,0)){h->dropped.fetch_add(1);h->panic.fetch_or(1u<<slot);}}
uint32_t lg_midi_output_configure(LGMIDIHub*h,const int32_t*channels,int count,int enabled){
    if(!h||(count!=0&&count!=8)||(count==8&&!channels)||(enabled&&count!=8))return 0;
    uint32_t packed=0;for(int i=0;i<count&&i<8;i++){if(channels[i]<0||channels[i]>15)return 0;packed|=uint32_t(channels[i])<<(i*4);}
    const auto layout=h->projectOutputChannels.load(std::memory_order_acquire);if(layout&(1ull<<32))packed=uint32_t(layout);
    uint32_t generation=(h->outputGeneration.fetch_add(1)+1)&0x7fffffffu;
    if(!generation)generation=(h->outputGeneration.fetch_add(1)+1)&0x7fffffffu;
    h->outputError.store(0);h->outputState.store((uint64_t(generation)<<33)|(uint64_t(enabled!=0)<<32)|packed,std::memory_order_release);return generation;
}
uint32_t lg_midi_output_activate(LGMIDIHub*h,uint32_t generation,const int32_t*channels,int count,int enabled){
    if(!h||!generation||generation>0x7fffffffu||(count!=0&&count!=8)||(count==8&&!channels)||(enabled&&count!=8))return 0;
    uint32_t packed=0;for(int i=0;i<count;i++){if(channels[i]<0||channels[i]>15)return 0;packed|=uint32_t(channels[i])<<(i*4);}
    const auto layout=h->projectOutputChannels.load(std::memory_order_acquire);if(layout&(1ull<<32))packed=uint32_t(layout);
    auto expected=h->outputState.load(std::memory_order_acquire);
    if(uint32_t(expected>>33)!=generation||(expected&(1ull<<32)))return 0;
    const auto desired=(uint64_t(generation)<<33)|(uint64_t(enabled!=0)<<32)|packed;
    if(!h->outputState.compare_exchange_strong(expected,desired,std::memory_order_acq_rel))return 0;
    h->outputError.store(0);return generation;
}
uint32_t lg_midi_output_active_epoch(LGMIDIHub*h){if(!h)return 0;const auto state=h->outputState.load(std::memory_order_acquire);return state&(1ull<<32) ? uint32_t(state>>33):0;}
int lg_midi_output_pop(LGMIDIHub*h,LGMIDIOutput*events,int capacity){if(!h||!events||capacity<1||capacity>512)return 0;int count=0;while(count<capacity&&h->output.pop(events[count]))count++;return count;}
int lg_midi_output_error(LGMIDIHub*h){return h?h->outputError.load():0;}
void lg_midi_output_failed(LGMIDIHub*h,int error){if(h)h->outputError.store(error);}
void lg_midi_output_sent(LGMIDIHub*h,int count){if(h&&count>0)h->outputSent.fetch_add(uint64_t(count));}
uint64_t lg_midi_output_count(LGMIDIHub*h){return h?h->outputSent.load():0;}
int lg_midi_probe_pop(LGMIDIHub*h,LGMIDIEvent*events,int capacity){if(!h)return 0;h->prepare([](int){});h->due(UINT64_MAX,0,[](const LGMIDIEvent&){});return lg_midi_monitor_pop(h,events,capacity);}
}
