import Foundation
import CoreMIDI
import AudioDSP
import MusicDomain
import Observation
import Darwin

final class MIDIHubHandle:@unchecked Sendable {
    let pointer:OpaquePointer
    init(){pointer=lg_midi_create()!}
    deinit{lg_midi_destroy(pointer)}
}
struct MIDIEndpoint:Identifiable,Equatable {
    let id:Int32;let name:String;let reference:MIDIEndpointRef
}
private enum MIDICallbacks {
    nonisolated private static func push(_ packets:UnsafePointer<MIDIPacketList>,handle:UInt32,hub:MIDIHubHandle){
        if packets.pointee.numPackets>256{lg_midi_input_overflow(hub.pointer,handle);return}
        let first=UnsafeRawPointer(packets).advanced(by:MemoryLayout<MIDIPacketList>.offset(of:\.packet)!).assumingMemoryBound(to:MIDIPacket.self)
        var packet=first
        for _ in 0..<min(256,packets.pointee.numPackets){
            let bytes=UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
            _ = lg_midi_push(hub.pointer,handle,packet.pointee.timeStamp,bytes,Int32(packet.pointee.length));packet=UnsafePointer(MIDIPacketNext(packet))
        }
    }
    nonisolated static func input(_ hub:MIDIHubHandle)->MIDIReadBlock {
        { @Sendable packets,connection in guard let connection else{return};push(packets,handle:UInt32(truncatingIfNeeded:UInt(bitPattern:connection)),hub:hub) }
    }
    nonisolated static func probe(_ hub:MIDIHubHandle)->MIDIReadBlock {
        { @Sendable packets,_ in push(packets,handle:256,hub:hub) }
    }
    nonisolated static func notifications(_ owner:MIDIController)->MIDINotifyBlock {
        { @Sendable [weak owner] _ in Task{ @MainActor in owner?.endpointsChanged()} }
    }
}
@MainActor @Observable final class MIDIController {
    let hub:MIDIHubHandle
    var sources:[MIDIEndpoint]=[];var destinations:[MIDIEndpoint]=[]
    var error:String?;var lastMessage="No MIDI input yet";var late:UInt64=0;var dropped:UInt64=0;var outputSent:UInt64=0
    var isFixture=false;var fixtureOutputID:Int32?;var fixtureReceivedNotes=0
    @ObservationIgnored private let fixtureProbe=MIDIHubHandle()
    @ObservationIgnored private var fixtureDestination=MIDIEndpointRef()
    @ObservationIgnored private var fixtureSource=MIDIEndpointRef()
    var learning:MIDIMapping.Target?;var learningTrack:UUID?
    @ObservationIgnored var onConfigurationChange:(()->Void)?
    @ObservationIgnored private var lastConfiguration:MIDISettings?
    @ObservationIgnored var onLearn:((MIDIMapping)->Void)?
    @ObservationIgnored var onControl:((MIDIMapping,Double)->Void)?
    @ObservationIgnored private var client=MIDIClientRef()
    @ObservationIgnored private var input=MIDIPortRef()
    @ObservationIgnored private var outputWorker:MIDIOutputWorker?
    @ObservationIgnored private var configuredOutput=MIDIEndpointRef()
    @ObservationIgnored private var outputChannels:[Int32]=[]
    @ObservationIgnored private var generation:UInt32=0
    @ObservationIgnored private var connections:[Int32:(endpoint:MIDIEndpointRef,slot:Int,handle:UInt32)]=[:]
    @ObservationIgnored private var settings=MIDISettings()
    @ObservationIgnored private var configuredTrack:Int = -1
    @ObservationIgnored private var configuredInstrument:Int = -1
    @ObservationIgnored private var configuredChannel:Int?
    @ObservationIgnored private var buffer=[LGMIDIEvent](repeating:LGMIDIEvent(),count:512)
    init(hub:MIDIHubHandle){self.hub=hub}
    func prepare(){
        guard client==0 else{return}
        var status=MIDIClientCreateWithBlock("La Grilla" as CFString,&client,MIDICallbacks.notifications(self))
        if status==noErr{status=MIDIInputPortCreateWithBlock(client,"Input" as CFString,&input,MIDICallbacks.input(hub))}
        if status != noErr{error="MIDI could not start (\(status)).";if client != 0{MIDIClientDispose(client)};client=0;input=0;return}
        var output=MIDIPortRef();let outputStatus=MIDIOutputPortCreate(client,"Output" as CFString,&output)
        if outputStatus==noErr{outputWorker=MIDIOutputWorker(hub:hub,port:output)}else{error="MIDI output could not start (\(outputStatus))."}
        refresh()
    }
    private func endpoint(_ ref:MIDIEndpointRef)->MIDIEndpoint? {
        var id:Int32=0;guard MIDIObjectGetIntegerProperty(ref,kMIDIPropertyUniqueID,&id)==noErr else{return nil}
        var name:Unmanaged<CFString>?;_ = MIDIObjectGetStringProperty(ref,kMIDIPropertyDisplayName,&name)
        return MIDIEndpoint(id:id,name:name?.takeRetainedValue() as String? ?? "MIDI device",reference:ref)
    }
    func endpointsChanged(){lastConfiguration=nil;refresh();onConfigurationChange?()}
    func retry(){lastConfiguration=nil;outputChannels=[];error=nil}
    private func channels(_ project:Project)->[Int32]{
        var result=[Int32](repeating:0,count:8);var melody:Int32=2
        for (i,track) in project.tracks.enumerated(){switch track.role{case .harmony:result[i]=0;case .drums:result[i]=9;case .bass:result[i]=1;case .melody:result[i]=melody;melody+=1}}
        return result
    }
    func refresh(){
        sources=(0..<MIDIGetNumberOfSources()).compactMap{endpoint(MIDIGetSource($0))}
        destinations=(0..<MIDIGetNumberOfDestinations()).compactMap{endpoint(MIDIGetDestination($0))}
        if configuredOutput != 0,!destinations.contains(where:{$0.reference==configuredOutput}){outputWorker?.select(0,channels:[]);configuredOutput=0;lastConfiguration=nil}
        for (id,connection) in connections where !sources.contains(where:{$0.id==id && $0.reference==connection.endpoint}){disconnect(id)}
    }
    func configure(_ value:MIDISettings,project:Project){
        let track=project.tracks.firstIndex{$0.id==value.trackID} ?? 0,instrument=project.tracks[track].role.instrument
        let channelMap=channels(project)
        if lastConfiguration==value,configuredTrack==track,configuredInstrument==instrument,channelMap==outputChannels{return}
        settings=value
        if client==0 && !value.enabled && value.outputID==nil{return}
        prepare();guard input != 0 else{return};refresh();lastConfiguration=value
        let output=destinations.first{$0.id==value.outputID}?.reference ?? 0
        if output != configuredOutput || outputChannels != channelMap{outputWorker?.select(output,channels:channelMap);configuredOutput=output;outputChannels=channelMap}
        let changed=track != configuredTrack || instrument != configuredInstrument || value.channel != configuredChannel
        if changed{for id in Array(connections.keys){disconnect(id)}}
        configuredTrack=track;configuredInstrument=instrument;configuredChannel=value.channel
        let wanted=value.enabled ? Set(value.inputIDs):[]
        for id in Array(connections.keys) where !wanted.contains(id){disconnect(id)}
        for source in sources where wanted.contains(source.id) && connections[source.id]==nil {
            guard let slot=(0..<16).first(where:{index in !connections.values.contains{$0.slot==index}})else{continue}
            generation &+= 1;if generation==0 || generation>0x00ff_ffff{generation=1};let handle=generation<<8|UInt32(slot)
            lg_midi_configure(hub.pointer,handle,Int32(track),Int32(instrument),value.channel.map{Int32(1<<$0)} ?? 65535)
            let status=MIDIPortConnectSource(input,source.reference,UnsafeMutableRawPointer(bitPattern:UInt(handle)))
            if status==noErr{connections[source.id]=(source.reference,slot,handle)}else{lg_midi_disconnect(hub.pointer,Int32(slot));error="Could not connect \(source.name) (\(status))."}
        }
    }
    private func disconnect(_ id:Int32){guard let connection=connections.removeValue(forKey:id)else{return};MIDIPortDisconnectSource(input,connection.endpoint);lg_midi_disconnect(hub.pointer,Int32(connection.slot))}
    func createFixture()->Int32? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting")else{return nil};prepare();guard client != 0 else{return nil}
        if fixtureSource==0{let status=MIDISourceCreate(client,"La Grilla virtual QA keyboard" as CFString,&fixtureSource);guard status==noErr else{error="Virtual MIDI source failed (\(status)).";return nil}}
        if fixtureDestination==0{
            lg_midi_configure(fixtureProbe.pointer,256,0,0,65535)
            let status=MIDIDestinationCreateWithBlock(client,"La Grilla virtual QA output" as CFString,&fixtureDestination,MIDICallbacks.probe(fixtureProbe))
            if status != noErr{error="Virtual MIDI destination failed (\(status)).";return nil}
        }
        fixtureOutputID=endpoint(fixtureDestination)?.id;isFixture=true;refresh();return endpoint(fixtureSource)?.id
    }
    func sendFixture(){
        guard fixtureSource != 0 else{return};var list=MIDIPacketList()
        var info=mach_timebase_info_data_t();mach_timebase_info(&info);let now=mach_absolute_time(),later=now+UInt64(200_000_000*Double(info.denom)/Double(info.numer))
        withUnsafeMutablePointer(to:&list){pointer in
            var packet=MIDIPacketListInit(pointer)
            for (time,bytes) in [(now,[UInt8(0x90),72,108]),(now,[UInt8(0xb0),74,80]),(later,[UInt8(0x80),72,0])]{
                packet=bytes.withUnsafeBufferPointer{MIDIPacketListAdd(pointer,MemoryLayout<MIDIPacketList>.size,packet,time,$0.count,$0.baseAddress!)}
            }
            _ = MIDIReceived(fixtureSource,pointer)
        }
    }
    deinit{if fixtureDestination != 0{MIDIEndpointDispose(fixtureDestination)};if fixtureSource != 0{MIDIEndpointDispose(fixtureSource)};if input != 0{MIDIPortDispose(input)};if client != 0{MIDIClientDispose(client)}}
    func panic(){for id in Array(connections.keys){disconnect(id)};outputWorker?.select(configuredOutput,channels:outputChannels);learning=nil}
    func isConnected(_ id:Int32)->Bool{connections[id] != nil}
    func poll(replaying:Bool){
        late=lg_midi_late(hub.pointer);dropped=lg_midi_dropped(hub.pointer);outputSent=lg_midi_output_count(hub.pointer)
        for id in Array(connections.keys){if let connection=connections[id],lg_midi_connected(hub.pointer,connection.handle)==0{disconnect(id);error="MIDI input paused after an overload. Tap Refresh & reconnect."}}
        if lg_midi_output_error(hub.pointer) != 0{error="MIDI output paused after a send error or overload. Tap Refresh & reconnect."}
        let count=buffer.withUnsafeMutableBufferPointer{lg_midi_monitor_pop(hub.pointer,$0.baseAddress,Int32($0.count))}
        for event in buffer.prefix(Int(count)) {
            let source=connections.first{$0.value.slot==event.source}?.key
            if event.status==9{lastMessage="Ch \(event.channel+1) · note \(event.a) · velocity \(event.b)"}
            guard event.status==11,event.a != 64,event.a<120,let source,!replaying else{continue}
            lastMessage="Ch \(event.channel+1) · CC \(event.a) = \(event.b)"
            if let learning {
                let mapping=MIDIMapping(sourceID:source,channel:Int(event.channel),controller:Int(event.a),target:learning,trackID:learningTrack)
                self.learning=nil;learningTrack=nil;onLearn?(mapping)
            }else if let mapping=settings.mapping(sourceID:source,channel:Int(event.channel),controller:Int(event.a)){onControl?(mapping,mapping.value(Int(event.b)))}
        }
        if isFixture{let count=buffer.withUnsafeMutableBufferPointer{lg_midi_probe_pop(fixtureProbe.pointer,$0.baseAddress,Int32($0.count))};fixtureReceivedNotes+=buffer.prefix(Int(count)).filter{$0.status==9}.count}
    }
}
