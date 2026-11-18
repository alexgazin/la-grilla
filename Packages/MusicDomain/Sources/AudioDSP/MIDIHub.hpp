#pragma once
#include "include/GrillaMIDI.h"
#include <array>
#include <atomic>
#include <algorithm>
#include <cstddef>

template<class T,size_t Capacity> class MIDIProducerQueue {
    struct Cell{std::atomic<size_t> sequence{0};T value{};};
    std::array<Cell,Capacity> cells{};std::atomic<size_t> write{0};size_t read=0;
public:
    MIDIProducerQueue(){for(size_t i=0;i<Capacity;i++)cells[i].sequence.store(i);}
    bool push(const T &value){
        size_t pos=write.load(std::memory_order_relaxed);
        for(int attempt=0;attempt<4;attempt++){
            auto &cell=cells[pos%Capacity];const auto sequence=cell.sequence.load(std::memory_order_acquire);
            if(sequence<pos)return false;
            if(sequence==pos&&write.compare_exchange_weak(pos,pos+1,std::memory_order_relaxed)){
                cell.value=value;cell.sequence.store(pos+1,std::memory_order_release);return true;
            }
            pos=write.load(std::memory_order_relaxed);
        }
        return false;
    }
    bool pop(T &value){auto &cell=cells[read%Capacity];if(cell.sequence.load(std::memory_order_acquire)!=read+1)return false;value=cell.value;cell.sequence.store(read+Capacity,std::memory_order_release);read++;return true;}
};
template<class T,size_t Capacity> class MIDIConsumerQueue {
    std::array<T,Capacity> values{};std::atomic<uint64_t> write{0},read{0};
public:
    bool push(const T &value){auto w=write.load(std::memory_order_relaxed);if(w-read.load(std::memory_order_acquire)>=Capacity)return false;values[w%Capacity]=value;write.store(w+1,std::memory_order_release);return true;}
    bool pop(T &value){auto r=read.load(std::memory_order_relaxed);if(r==write.load(std::memory_order_acquire))return false;value=values[r%Capacity];read.store(r+1,std::memory_order_release);return true;}
};
struct MIDIRawPacket{uint64_t time=0;uint32_t handle=0,configuration=0;uint16_t count=0;std::array<uint8_t,256> bytes{};};
struct MIDIParserState{uint8_t status=0,used=0,needed=0;std::array<uint8_t,2> data{};bool sysex=false;};
constexpr uint32_t screenKeyboardRoute = 1u << 24;
struct MIDIConnection{std::atomic<uint32_t> handle{0},routing{0},configuration{0};std::atomic<uint64_t> identity{0};};
struct MIDIPending{LGMIDIEvent event{};uint64_t order=0,identity=0;uint32_t handle=0,configuration=0;bool screenKeyboard=false;};
struct MIDIMonitored{LGMIDIEvent event{};uint32_t handle=0,configuration=0;};
struct LGMIDIHub {
    MIDIProducerQueue<MIDIRawPacket,1024> packets;
    MIDIConsumerQueue<MIDIMonitored,512> monitor;
    std::array<MIDIConnection,16> connections{};std::array<MIDIParserState,16> parsers{};
    std::array<uint32_t,16> parserConfiguration{},parserHandle{},renderConfiguration{},renderHandle{};
    std::array<uint64_t,16> renderIdentity{};
    // Keys and instruments have one owner: the audio thread adopting snapshots.
    std::array<uint64_t,8> trackKeys{};std::array<int32_t,8> trackInstruments{};int trackCount=0;
    // Bit 32 marks an authoritative project map. The control worker can never
    // overwrite these nibbles with a stale index map during endpoint selection.
    std::atomic<uint64_t> projectOutputChannels{0};
    std::atomic<uint32_t> panic{0};std::atomic<uint64_t> late{0},dropped{0};
    std::array<MIDIPending,2048> future{};size_t count=0;uint64_t order=0;
    MIDIConsumerQueue<LGMIDIOutput,4096> output;
    std::atomic<uint64_t> outputState{0},outputSent{0};std::atomic<uint32_t> outputGeneration{0};std::atomic<int> outputError{0};
    std::array<std::array<uint16_t,128>,16> outputRefs{};
    uint64_t outputConfiguration()const {
        const auto destination=outputState.load(std::memory_order_acquire);
        const auto layout=projectOutputChannels.load(std::memory_order_acquire);
        return layout&(1ull<<32) ? (destination&~0xffffffffull)|uint32_t(layout):destination;
    }
    bool currentBinding(int slot,uint32_t handle,uint32_t configuration)const {
        return slot>=0&&slot<16&&connections[slot].handle.load(std::memory_order_acquire)==handle&&connections[slot].configuration.load(std::memory_order_acquire)==configuration;
    }
    bool resolve(uint64_t identity,int &track,int &instrument)const {
        for(int i=0;i<trackCount;i++)if(trackKeys[size_t(i)]==identity){track=i;instrument=trackInstruments[size_t(i)];return true;}
        return false;
    }
    uint64_t inputIdentity(int slot,uint32_t handle,uint32_t configuration,uint64_t requested,int fallback){
        if(requested)return requested;
        if(!(projectOutputChannels.load(std::memory_order_acquire)&(1ull<<32)))return 0;
        if(renderHandle[size_t(slot)]!=handle||renderConfiguration[size_t(slot)]!=configuration){
            renderHandle[size_t(slot)]=handle;renderConfiguration[size_t(slot)]=configuration;
            renderIdentity[size_t(slot)]=fallback>=0&&fallback<trackCount ? trackKeys[size_t(fallback)]:0;
        }
        return renderIdentity[size_t(slot)];
    }
    template<class Clear> void adoptLayout(const uint64_t*oldKeys,int oldCount,const uint64_t*keys,const int32_t*instruments,const int32_t*channels,int newCount,Clear clear){
        if(!keys||!instruments||!channels||newCount<0||newCount>8||oldCount<0||oldCount>8)return;
        uint32_t packed=0;
        for(int i=0;i<newCount;i++){trackKeys[size_t(i)]=keys[i];trackInstruments[size_t(i)]=instruments[i];packed|=uint32_t(channels[i]&15)<<(i*4);}
        for(int i=newCount;i<8;i++){trackKeys[size_t(i)]=0;trackInstruments[size_t(i)]=0;}
        trackCount=newCount;
        for(int slot=0;slot<16;slot++){
            auto &connection=connections[size_t(slot)];const auto configuration=connection.configuration.load(std::memory_order_acquire);
            if(configuration&1)continue;
            const auto handle=connection.handle.load(std::memory_order_acquire),routing=connection.routing.load(std::memory_order_relaxed);
            const auto requested=connection.identity.load(std::memory_order_relaxed);
            std::atomic_thread_fence(std::memory_order_acquire);
            if(!handle||!currentBinding(slot,handle,configuration))continue;
            if(renderHandle[size_t(slot)]!=handle||renderConfiguration[size_t(slot)]!=configuration){
                const int oldTrack=int((routing>>16)&15);
                renderHandle[size_t(slot)]=handle;renderConfiguration[size_t(slot)]=configuration;
                renderIdentity[size_t(slot)]=requested ? requested:(oldKeys&&oldTrack<oldCount ? oldKeys[oldTrack]:(oldTrack<newCount ? keys[oldTrack]:0));
            }
            int track=0,instrument=0;
            if(!resolve(requested ? requested:renderIdentity[size_t(slot)],track,instrument))clear(slot);
        }
        // Decode may precede adoption within this callback. Preserve a boundary
        // event for the same UUID, rather than losing it or keeping its old index.
        size_t next=0;
        for(size_t i=0;i<count;i++){
            auto event=future[i];
            if(!event.identity){const int oldTrack=event.event.track;event.identity=oldKeys&&oldTrack>=0&&oldTrack<oldCount ? oldKeys[oldTrack]:oldTrack>=0&&oldTrack<newCount ? keys[oldTrack]:0;}
            int track=0,instrument=0;
            if(!event.identity||!resolve(event.identity,track,instrument))continue;
            event.event.track=track;event.event.instrument=instrument;future[next++]=event;
        }
        count=next;std::make_heap(future.begin(),future.begin()+count,later);
        projectOutputChannels.store((1ull<<32)|packed,std::memory_order_release);
    }
    void resetOutputRefs(){for(auto &channel:outputRefs)channel.fill(0);}
    void outputEvent(uint64_t state,uint64_t time,int status,int a,int b){
        if(!(state&(1ull<<32)))return;
        if(!output.push({time,uint32_t(state>>33),status,a,b}))outputError.store(-1000,std::memory_order_release);
    }
    int outputOn(uint64_t state,uint64_t time,int track,int pitch,int velocity){
        if(!(state&(1ull<<32))||track<0||track>=8)return -1;
        const auto layout=projectOutputChannels.load(std::memory_order_acquire);
        const auto channels=layout&(1ull<<32) ? uint32_t(layout):uint32_t(state);
        const int channel=int((channels>>(track*4))&15);outputRefs[channel][pitch]++;
        outputEvent(state,time,0x90|channel,pitch,velocity);return channel;
    }
    void outputOff(uint64_t state,uint64_t time,int channel,int pitch){
        if(channel<0||channel>=16){return;}auto &count=outputRefs[channel][pitch];
        if(count>0&&--count==0)outputEvent(state,time,0x80|channel,pitch,0);
    }
    static bool later(const MIDIPending&a,const MIDIPending&b){return a.event.hostTime==b.event.hostTime?a.order>b.order:a.event.hostTime>b.event.hostTime;}
    void schedule(LGMIDIEvent event,uint64_t identity=0,uint32_t handle=0,uint32_t configuration=0,bool screenKeyboard=false){if(count==future.size()){dropped.fetch_add(1);if(handle&&connections[event.source].handle.compare_exchange_strong(handle,0))panic.fetch_or(1u<<event.source);return;}future[count++]={event,order++,identity,handle,configuration,screenKeyboard};std::push_heap(future.begin(),future.begin()+count,later);}
    void decode(const MIDIRawPacket &packet){
        const int slot=int(packet.handle&255);if(slot>=16||packet.configuration&1||!currentBinding(slot,packet.handle,packet.configuration))return;
        auto &connection=connections[size_t(slot)];const auto routing=connection.routing.load(std::memory_order_relaxed);const auto requested=connection.identity.load(std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_acquire);
        if(!currentBinding(slot,packet.handle,packet.configuration))return;
        if(parserConfiguration[size_t(slot)]!=packet.configuration||parserHandle[size_t(slot)]!=packet.handle){parsers[size_t(slot)]={};parserConfiguration[size_t(slot)]=packet.configuration;parserHandle[size_t(slot)]=packet.handle;}
        auto &p=parsers[size_t(slot)];const auto identity=inputIdentity(slot,packet.handle,packet.configuration,requested,int((routing>>16)&15));
        for(int i=0;i<packet.count;i++){
            const uint8_t byte=packet.bytes[size_t(i)];
            if(byte>=0xf8){if(byte==0xff)panic.fetch_or(1u<<slot);continue;}
            if(byte&0x80){
                p.used=0;
                if(byte>=0xf0){p.status=byte;p.sysex=byte==0xf0;p.needed=byte==0xf2?2:(byte==0xf1||byte==0xf3?1:0);continue;}
                p.sysex=false;p.status=byte;p.needed=(byte&0xe0)==0xc0?1:2;continue;
            }
            if(p.sysex||p.status==0||p.needed==0)continue;
            p.data[p.used++]=byte;if(p.used<p.needed)continue;p.used=0;
            const int status=p.status>>4,channel=p.status&15;
            if(status>=0xf){p.status=0;p.needed=0;continue;}
            if(!(routing&(1u<<channel)))continue;
            if(status==8||status==9||status==11){LGMIDIEvent event{packet.time,slot,status==9&&p.data[1]==0?8:status,channel,p.data[0],p.data[1],int((routing>>16)&15),int((routing>>20)&3)};if(identity){int track=0,instrument=0;if(resolve(identity,track,instrument)){event.track=track;event.instrument=instrument;}}schedule(event,identity,packet.handle,packet.configuration,(routing & screenKeyboardRoute) != 0);}
        }
    }
    template<class Clear> void prepare(Clear clear){
        auto bits=panic.exchange(0,std::memory_order_acq_rel);
        for(int slot=0;slot<16;slot++)if(bits&(1u<<slot)){parsers[slot]={};clear(slot);size_t next=0;for(size_t i=0;i<count;i++)if(future[i].event.source!=slot)future[next++]=future[i];count=next;}
        if(bits)std::make_heap(future.begin(),future.begin()+count,later);
        MIDIRawPacket packet;for(int i=0;i<128&&packets.pop(packet);i++)decode(packet);
    }
    template<class Apply> void due(uint64_t hostTime,uint64_t oneSample,Apply apply){
        dueWithOrigin(hostTime,oneSample,[&](const LGMIDIEvent &event,bool){ apply(event); });
    }
    template<class Apply> void dueWithOrigin(uint64_t hostTime,uint64_t oneSample,Apply apply){
        // Bounded work even under a controller flood. Remaining events become late,
        // are counted, and NoteOff protection is supplied by per-source panic.
        for(int n=0;n<64&&count&&future[0].event.hostTime<=hostTime;n++){
            std::pop_heap(future.begin(),future.begin()+count,later);const auto pending=future[--count];auto event=pending.event;
            if(pending.handle&&!currentBinding(event.source,pending.handle,pending.configuration))continue;
            if(pending.identity){int track=0,instrument=0;if(!resolve(pending.identity,track,instrument))continue;event.track=track;event.instrument=instrument;}
            if(event.hostTime&&hostTime>event.hostTime+oneSample)late.fetch_add(1,std::memory_order_relaxed);
            apply(event,pending.screenKeyboard);if(!monitor.push({event,pending.handle,pending.configuration}))dropped.fetch_add(1,std::memory_order_relaxed);
        }
    }
};
