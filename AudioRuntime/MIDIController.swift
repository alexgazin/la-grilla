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
    private(set) var fixtureRequested=false
    private(set) var lastStartupStage:String?
    private(set) var lastStartupStatus:OSStatus?
    @ObservationIgnored private var startupErrorStage:String?
    @ObservationIgnored private var startupErrorMessage:String?
    @ObservationIgnored private var fixtureInputID:Int32?
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
    @ObservationIgnored private var outputNeedsRefresh=true
    @ObservationIgnored private var keyboardConnection: (slot: Int, handle: UInt32, track: UUID)?
    @ObservationIgnored private var generation:UInt32=0
    @ObservationIgnored private var connections:[Int32:(endpoint:MIDIEndpointRef,slot:Int,handle:UInt32)]=[:]
    @ObservationIgnored private var settings=MIDISettings()
    @ObservationIgnored private var configuredIdentity:UInt64=0
    @ObservationIgnored private var configuredChannel:Int?
    @ObservationIgnored private var buffer=[LGMIDIEvent](repeating:LGMIDIEvent(),count:512)
    init(hub:MIDIHubHandle){self.hub=hub}
    func prepare(){
        // An explicit reconnect retries only missing resources. A failed input
        // or output port must not make a healthy client permanently unretryable.
        guard client==0 || input==0 || outputWorker==nil else{return}
        if client==0 {
            var created=MIDIClientRef()
            let status=MIDIClientCreateWithBlock("La Grilla" as CFString,&created,MIDICallbacks.notifications(self))
            guard status==noErr else{
                if created != 0{MIDIClientDispose(created)}
                failStartup("client",status:status,message:String(format:NSLocalizedString("MIDI could not start (%d).",comment:"MIDI input startup error"),status));return
            }
            client=created
        }
        if input==0 {
            var created=MIDIPortRef()
            let status=MIDIInputPortCreateWithBlock(client,"Input" as CFString,&created,MIDICallbacks.input(hub))
            guard status==noErr else{
                if created != 0{MIDIPortDispose(created)}
                failStartup("input-port",status:status,message:String(format:NSLocalizedString("MIDI could not start (%d).",comment:"MIDI input startup error"),status));return
            }
            input=created
        }
        if outputWorker==nil {
            var output=MIDIPortRef()
            let status=MIDIOutputPortCreate(client,"Output" as CFString,&output)
            guard status==noErr else{
                if output != 0{MIDIPortDispose(output)}
                failStartup("output-port",status:status,message:String(format:NSLocalizedString("MIDI output could not start (%d).",comment:"MIDI output startup error"),status));refresh();return
            }
            outputWorker=MIDIOutputWorker(hub:hub,port:output)
        }
        if let stage=startupErrorStage,["client","input-port","output-port"].contains(stage){clearStartupError()}
        refresh()
    }
    private func failStartup(_ stage:String,status:OSStatus,message:String){
        lastStartupStage=stage;lastStartupStatus=status;startupErrorStage=stage;startupErrorMessage=message;error=message
    }
    private func clearStartupError(){
        if error==startupErrorMessage{error=nil}
        startupErrorStage=nil;startupErrorMessage=nil
    }
    private func endpoint(_ ref:MIDIEndpointRef)->MIDIEndpoint? {
        guard endpointIsOnline(ref) else{return nil}
        var id:Int32=0;guard MIDIObjectGetIntegerProperty(ref,kMIDIPropertyUniqueID,&id)==noErr else{return nil}
        var name:Unmanaged<CFString>?;_ = MIDIObjectGetStringProperty(ref,kMIDIPropertyDisplayName,&name)
        return MIDIEndpoint(id:id,name:name?.takeRetainedValue() as String? ?? "MIDI device",reference:ref)
    }
    private func endpointIsOnline(_ ref:MIDIEndpointRef)->Bool {
        var offline:Int32=0
        if MIDIObjectGetIntegerProperty(ref,kMIDIPropertyOffline,&offline)==noErr,offline != 0{return false}
        var entity=MIDIEntityRef(),device=MIDIDeviceRef()
        // Virtual endpoints have no hardware entity/device and remain usable.
        if MIDIEndpointGetEntity(ref,&entity)==noErr,entity != 0,
           MIDIEntityGetDevice(entity,&device)==noErr,device != 0,
           MIDIObjectGetIntegerProperty(device,kMIDIPropertyOffline,&offline)==noErr{return offline==0}
        return true
    }
    func endpointsChanged(){lastConfiguration=nil;refresh();onConfigurationChange?()}
    func retry(){lastConfiguration=nil;outputNeedsRefresh=true;error=nil;startupErrorStage=nil;startupErrorMessage=nil}
    /// The same stable key is embedded in the audio project snapshot. Track
    /// indices are deliberately excluded: editing their order must not reconnect
    /// a keyboard or let a queued packet play a different track.
    nonisolated static func trackIdentity(_ id:UUID)->UInt64 {
        var value:UInt64=14_695_981_039_346_656_037
        var bytes=id.uuid
        withUnsafeBytes(of:&bytes){for byte in $0{value=(value ^ UInt64(byte)) &* 1_099_511_628_211}}
        return value==0 ? 1:value
    }
    private func channels(_ tracks:[Track])->[Int32]{
        var result=[Int32](repeating:0,count:8);var melody:Int32=2
        for (i,track) in tracks.prefix(8).enumerated(){switch track.role{case .harmony:result[i]=0;case .drums:result[i]=9;case .bass:result[i]=1;case .melody:result[i]=melody;melody+=1}}
        return result
    }
    func refresh(){
        sources=(0..<MIDIGetNumberOfSources()).compactMap{endpoint(MIDIGetSource($0))}
        destinations=(0..<MIDIGetNumberOfDestinations()).compactMap{endpoint(MIDIGetDestination($0))}
        if configuredOutput != 0,!destinations.contains(where:{$0.reference==configuredOutput}){outputWorker?.select(0,channels:[]);configuredOutput=0;lastConfiguration=nil}
        for (id,connection) in connections where !sources.contains(where:{$0.id==id && $0.reference==connection.endpoint}){disconnect(id)}
    }
    func configure(_ value:MIDISettings,project:Project){
        configure(value,tracks:project.tracks)
    }
    func configure(_ value:MIDISettings,tracks:[Track]){
        guard let first=tracks.first else{return}
        let target=value.trackID ?? first.id
        let track=tracks.firstIndex{$0.id==target} ?? 0,instrument=tracks.first(where:{$0.id==target})?.role.instrument ?? 0
        let identity=Self.trackIdentity(target),channelMap=channels(tracks)
        if lastConfiguration==value,configuredIdentity==identity,channelMap==outputChannels,!outputNeedsRefresh{return}
        settings=value
        if client==0 && !value.enabled && value.outputID==nil{return}
        prepare();guard input != 0 else{return};refresh();lastConfiguration=value
        let output=destinations.first{$0.id==value.outputID}?.reference ?? 0
        // Project channel changes are published by the audio snapshot itself at
        // its exact boundary. Only endpoint selection/retry changes the worker's
        // destination epoch and flushes queued output.
        if output != configuredOutput || outputNeedsRefresh{outputWorker?.select(output,channels:channelMap);configuredOutput=output;outputNeedsRefresh=false}
        outputChannels=channelMap
        let changed=identity != configuredIdentity || value.channel != configuredChannel
        if changed{for id in Array(connections.keys){disconnect(id)}}
        configuredIdentity=identity;configuredChannel=value.channel
        let wanted=value.enabled ? Set(value.inputIDs):[]
        for id in Array(connections.keys) where !wanted.contains(id){disconnect(id)}
        for source in sources where wanted.contains(source.id) && connections[source.id]==nil {
            guard let slot = availableSlot else { continue }
            let handle = nextHandle(for: slot)
            lg_midi_configure_track(hub.pointer,handle,identity,Int32(track),Int32(instrument),value.channel.map{Int32(1<<$0)} ?? 65535)
            let status=MIDIPortConnectSource(input,source.reference,UnsafeMutableRawPointer(bitPattern:UInt(handle)))
            if status==noErr{connections[source.id]=(source.reference,slot,handle)}else{lg_midi_disconnect(hub.pointer,Int32(slot));error=String(format:NSLocalizedString("Could not connect %@ (%d).",comment:"MIDI device connection error"),source.name,status)}
        }
    }
    private var availableSlot: Int? {
        (0..<16).first { slot in
            keyboardConnection?.slot != slot && !connections.values.contains { $0.slot == slot }
        }
    }

    private func nextHandle(for slot: Int) -> UInt32 {
        generation = generation % 0x00ff_ffff + 1
        return generation << 8 | UInt32(slot)
    }

    func playKey(_ pitch: Int, down: Bool, track: Track, index: Int) -> Bool {
        guard (0...127).contains(pitch), (0..<8).contains(index) else { return false }
        if keyboardConnection?.track != track.id {
            guard down else { return false }
            releaseKeyboard()
            guard let slot = availableSlot else { return false }
            let handle = nextHandle(for: slot)
            lg_midi_configure_keyboard(hub.pointer, handle, Self.trackIdentity(track.id),
                                       Int32(index), Int32(track.role.instrument))
            keyboardConnection = (slot, handle, track.id)
        }
        guard let connection = keyboardConnection else { return false }
        let bytes: [UInt8] = [down ? 0x90 : 0x80, UInt8(pitch), down ? 96 : 0]
        let accepted = bytes.withUnsafeBufferPointer {
            lg_midi_push(hub.pointer, connection.handle, mach_absolute_time(), $0.baseAddress, 3) != 0
        }
        if !accepted { releaseKeyboard() }
        return accepted
    }

    func releaseKeyboard() {
        guard let connection = keyboardConnection else { return }
        lg_midi_disconnect(hub.pointer, Int32(connection.slot))
        keyboardConnection = nil
    }

    private func disconnect(_ id:Int32){guard let connection=connections.removeValue(forKey:id)else{return};MIDIPortDisconnectSource(input,connection.endpoint);lg_midi_disconnect(hub.pointer,Int32(connection.slot))}
    func createFixture()->Int32? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting")else{return nil}
        fixtureRequested=true;prepare();guard client != 0,input != 0,outputWorker != nil else{return nil}
        if fixtureSource==0{
            var created=MIDIEndpointRef()
            let status=MIDISourceCreate(client,"La Grilla virtual QA keyboard" as CFString,&created)
            guard status==noErr else{if created != 0{MIDIEndpointDispose(created)};failStartup("fixture-source",status:status,message:String(format:NSLocalizedString("Virtual MIDI source failed (%d).",comment:"Virtual MIDI test source error"),status));return nil}
            fixtureSource=created
        }
        if fixtureDestination==0{
            lg_midi_configure(fixtureProbe.pointer,256,0,0,65535)
            var created=MIDIEndpointRef()
            let status=MIDIDestinationCreateWithBlock(client,"La Grilla virtual QA output" as CFString,&created,MIDICallbacks.probe(fixtureProbe))
            guard status==noErr else{if created != 0{MIDIEndpointDispose(created)};failStartup("fixture-destination",status:status,message:String(format:NSLocalizedString("Virtual MIDI destination failed (%d).",comment:"Virtual MIDI test destination error"),status));return nil}
            fixtureDestination=created
        }
        guard let source=endpoint(fixtureSource),let destination=endpoint(fixtureDestination)else{return nil}
        fixtureInputID=source.id;fixtureOutputID=destination.id;isFixture=true
        if let stage=startupErrorStage,["fixture-source","fixture-destination"].contains(stage){clearStartupError()}
        refresh();return source.id
    }
    /// Read-only QA state from actual CoreMIDI resources and received packets.
    /// No endpoint, connection, learned mapping or output receipt is synthesized.
    var fixtureReadiness:String {
        let sourceOnline=sources.contains{$0.id==fixtureInputID && $0.reference==fixtureSource}
        let destinationOnline=destinations.contains{$0.id==fixtureOutputID && $0.reference==fixtureDestination}
        let connected=fixtureInputID.map{settings.enabled && settings.inputIDs.contains($0) && connections[$0]?.endpoint==fixtureSource} ?? false
        let selected=destinationOnline && outputWorker != nil && configuredOutput==fixtureDestination && fixtureDestination != 0 && settings.outputID==fixtureOutputID
        let mapped=fixtureInputID.flatMap{settings.mapping(sourceID:$0,channel:0,controller:74)}?.target == .filter
        return "requested=\(fixtureRequested ? 1:0);source=\(sourceOnline ? 1:0);input=\(connected ? 1:0);output=\(selected ? 1:0);received=\(fixtureReceivedNotes);mapping=\(mapped ? 1:0);learning=\(learning == .filter ? 1:0);learningActive=\(learning==nil ? 0:1);error=\(error==nil ? 0:1);lastFailureStage=\(lastStartupStage ?? "none");lastFailureStatus=\(lastStartupStatus.map{String($0)} ?? "none")"
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
    func suspend(){for id in Array(connections.keys){disconnect(id)};outputWorker?.suspend();configuredOutput=0;lastConfiguration=nil;learning=nil}
    func isConnected(_ id:Int32)->Bool{connections[id] != nil}
    func poll(replaying:Bool){
        late=lg_midi_late(hub.pointer);dropped=lg_midi_dropped(hub.pointer);outputSent=lg_midi_output_count(hub.pointer)
        for id in Array(connections.keys){if let connection=connections[id],lg_midi_connected(hub.pointer,connection.handle)==0{disconnect(id);error=NSLocalizedString("MIDI input paused after an overload. Tap Refresh & reconnect.",comment:"MIDI input overload recovery")}}
        if lg_midi_output_error(hub.pointer) != 0{error=NSLocalizedString("MIDI output paused after a send error or overload. Tap Refresh & reconnect.",comment:"MIDI output overload recovery")}
        let count=buffer.withUnsafeMutableBufferPointer{lg_midi_monitor_pop(hub.pointer,$0.baseAddress,Int32($0.count))}
        for event in buffer.prefix(Int(count)) {
            let source=connections.first{$0.value.slot==event.source}?.key
            if event.status==9{lastMessage=String(format:NSLocalizedString("Ch %d · note %d · velocity %d",comment:"MIDI activity"),event.channel+1,event.a,event.b)}
            guard event.status==11,event.a != 64,event.a<120,let source,!replaying else{continue}
            lastMessage=String(format:NSLocalizedString("Ch %d · CC %d = %d",comment:"MIDI activity"),event.channel+1,event.a,event.b)
            if let learning {
                let mapping=MIDIMapping(sourceID:source,channel:Int(event.channel),controller:Int(event.a),target:learning,trackID:learningTrack)
                self.learning=nil;learningTrack=nil;onLearn?(mapping)
            }else if let mapping=settings.mapping(sourceID:source,channel:Int(event.channel),controller:Int(event.a)){onControl?(mapping,mapping.value(Int(event.b)))}
        }
        if isFixture{let count=buffer.withUnsafeMutableBufferPointer{lg_midi_probe_pop(fixtureProbe.pointer,$0.baseAddress,Int32($0.count))};fixtureReceivedNotes+=buffer.prefix(Int(count)).filter{$0.status==9}.count}
    }
}
