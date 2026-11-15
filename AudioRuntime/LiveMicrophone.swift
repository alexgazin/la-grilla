import AVFoundation
import AudioToolbox
import AudioDSP
import Darwin
import Foundation

enum LiveInputError:Error,LocalizedError {
    case unavailable,unsupportedFormat,overflow,invalidSamples,outputUnavailable
    var errorDescription:String? {
        let key=switch self {
        case .unavailable:"No microphone is available. Check the audio route and retry."
        case .unsupportedFormat:"This microphone format is unavailable. Try another input."
        case .overflow:"Recording stopped because the input could not be saved fast enough. Your previous draft is preserved."
        case .invalidSamples:"The microphone returned invalid audio. Check the input and retry."
        case .outputUnavailable:"The audio route changed. Check the output before recording again."
        }
        return NSLocalizedString(key,comment:"")
    }
}

/// Captured while playAndRecord is active, before cleanup restores playback.
/// Values describe the real route; a zero node format alone is not proof that
/// the host has no microphone. No port UIDs or recorded samples enter this log.
struct LiveInputRouteSnapshot:Codable,Sendable {
    struct EnableIO:Codable,Sendable {
        let scope:UInt32
        let bus:UInt32
        let status:OSStatus?
        let byteCount:UInt32?
        let value:UInt32?
        @MainActor init(unit:AudioUnit?,scope:AudioUnitScope,bus:AudioUnitElement){
            self.scope=scope;self.bus=bus
            guard let unit else{status=nil;byteCount=nil;value=nil;return}
            var raw:UInt32=0,bytes=UInt32(MemoryLayout<UInt32>.size)
            let result=AudioUnitGetProperty(unit,kAudioOutputUnitProperty_EnableIO,scope,bus,&raw,&bytes)
            status=result;byteCount=bytes
            value=result==noErr && bytes==UInt32(MemoryLayout<UInt32>.size) ? raw:nil
        }
        private enum CodingKeys:String,CodingKey{case scope,bus,status,byteCount,value}
        func encode(to encoder:Encoder)throws {
            var fields=encoder.container(keyedBy:CodingKeys.self)
            try fields.encode(scope,forKey:.scope);try fields.encode(bus,forKey:.bus)
            // Failed/unsupported reads and missing units remain explicit nulls;
            // an initialized scratch value must never look like disabled I/O.
            try fields.encode(status,forKey:.status);try fields.encode(byteCount,forKey:.byteCount);try fields.encode(value,forKey:.value)
        }
    }
    struct IOUnit:Codable,Sendable {
        let hostTime:UInt64
        let unitAvailable:Bool
        let inputEnabled:EnableIO
        let outputEnabled:EnableIO
        @MainActor init(_ node:AVAudioIONode){
            hostTime=mach_absolute_time()
            let unit=node.audioUnit;unitAvailable=unit != nil
            // Public read-only queries. AVAudioEngine retains ownership of all
            // initialization, enablement, formats and connections.
            inputEnabled=EnableIO(unit:unit,scope:kAudioUnitScope_Input,bus:1)
            outputEnabled=EnableIO(unit:unit,scope:kAudioUnitScope_Output,bus:0)
        }
    }
    struct Port:Codable,Sendable {
        let type:String
        let name:String
        let channels:Int
        init(_ port:AVAudioSessionPortDescription){type=port.portType.rawValue;name=port.portName;channels=port.channels?.count ?? 0}
    }
    struct Format:Codable,Sendable {
        let sampleRate:Double?
        let channels:Int
        let commonFormat:Int
        let interleaved:Bool
        init(_ format:AVAudioFormat){sampleRate=format.sampleRate.isFinite ? format.sampleRate:nil;channels=Int(format.channelCount);commonFormat=Int(format.commonFormat.rawValue);interleaved=format.isInterleaved}
    }
    let stage:String
    let category:String
    let mode:String
    let sessionSampleRate:Double
    let isInputAvailable:Bool
    let inputs:[Port]
    let availableInputs:[Port]
    let outputs:[Port]
    let inputFormat:Format
    let outputFormat:Format
    let engineRunning:Bool
    let outputUnitBeforeInputNode:IOUnit?
    let inputUnit:IOUnit
    let outputUnit:IOUnit
    var hardwareAbsent:Bool{!isInputAvailable && inputs.isEmpty && availableInputs.isEmpty}
    @MainActor static func capture(_ engine:AVAudioEngine,stage:String,outputUnitBeforeInputNode:IOUnit?=nil)->LiveInputRouteSnapshot {
        let session=AVAudioSession.sharedInstance(),input=engine.inputNode
        return LiveInputRouteSnapshot(stage:stage,category:session.category.rawValue,mode:session.mode.rawValue,sessionSampleRate:session.sampleRate,isInputAvailable:session.isInputAvailable,inputs:session.currentRoute.inputs.map{Port($0)},availableInputs:(session.availableInputs ?? []).map{Port($0)},outputs:session.currentRoute.outputs.map{Port($0)},inputFormat:Format(input.inputFormat(forBus:0)),outputFormat:Format(input.outputFormat(forBus:0)),engineRunning:engine.isRunning,outputUnitBeforeInputNode:outputUnitBeforeInputNode,inputUnit:IOUnit(input),outputUnit:IOUnit(engine.outputNode))
    }
}
struct LiveInputSetupFailure:Error,LocalizedError,Sendable {
    let message:String
    let routes:[LiveInputRouteSnapshot]
    var errorDescription:String?{message}
    var hardwareAbsent:Bool{routes.count==1 && (routes.first.map{$0.stage=="activated-playAndRecord" && $0.hardwareAbsent && $0.category==AVAudioSession.Category.playAndRecord.rawValue} ?? false)}
    init(_ error:Error,routes:[LiveInputRouteSnapshot]){message=error.localizedDescription;self.routes=routes}
}

struct LiveInputReceiver:Sendable {
    let receive:@Sendable(AVAudioPCMBuffer)throws->Void
    let finish:@Sendable()throws->Void
}

private final class InputRingHandle:@unchecked Sendable {
    let pointer:OpaquePointer
    init(rate:Double,limit:Double)throws {
        var info=mach_timebase_info_data_t();mach_timebase_info(&info)
        let ticks=1_000_000_000*Double(info.denom)/Double(info.numer)
        guard let pointer=lg_input_create(rate,UInt32(ceil(rate*2)),UInt64.max,ticks,UInt64(ceil(rate*limit)))else{throw LiveInputError.unsupportedFormat}
        self.pointer=pointer
    }
    deinit{lg_input_destroy(pointer)}
}

private enum InputTapCallbacks {
    // Construct outside MainActor. The tap performs only bounded downmix/copy and
    // lock-free C atomics, never Swift tasks, allocations, recognition or file I/O.
    nonisolated static func install(input:AVAudioInputNode,format:AVAudioFormat,ring:InputRingHandle){
        let channels=format.channelCount,interleaved:Int32=format.isInterleaved ? 1:0,rate=format.sampleRate
        input.installTap(onBus:0,bufferSize:1024,format:format){ @Sendable [ring] buffer,time in
            let host=time.isHostTimeValid ? time.hostTime:mach_absolute_time()
            guard buffer.format.sampleRate==rate,buffer.format.channelCount==channels,buffer.format.isInterleaved==(interleaved != 0),let samples=buffer.floatChannelData else{_ = lg_input_push(ring.pointer,nil,0,0,0,host);return}
            _ = lg_input_push(ring.pointer,UnsafeRawPointer(samples),channels,buffer.frameLength,interleaved,host)
        }
    }
}

private enum InputNotifications {
    nonisolated static func forward(_ update:@escaping @MainActor @Sendable(String)->Void)->@Sendable(String)->Void {
        {message in Task{@MainActor in update(message)}}
    }
}

/// The only consumer of the SPSC ring. Conversion, speech append and file writes
/// run on this serial worker; a slow consumer produces an explicit bounded error.
private final class InputDrain:@unchecked Sendable {
    let ring:InputRingHandle
    private let queue=DispatchQueue(label:"com.alexgazin.LaGrilla.microphone",qos:.userInitiated)
    private let format:AVAudioFormat
    private let receiver:LiveInputReceiver
    private let onFailure:@Sendable(String)->Void
    private let scratch=UnsafeMutablePointer<Float>.allocate(capacity:4096)
    private var timer:DispatchSourceTimer?
    private var stopped=false
    private var failed:Error?
    init(ring:InputRingHandle,format:AVAudioFormat,receiver:LiveInputReceiver,onFailure:@escaping @Sendable(String)->Void){self.ring=ring;self.format=format;self.receiver=receiver;self.onFailure=onFailure}
    deinit{scratch.deallocate()}
    func start(){
        let timer=DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now(),repeating:.milliseconds(10),leeway:.milliseconds(2))
        timer.setEventHandler{[weak self] in self?.drainAndReport()}
        queue.sync{self.timer=timer;timer.resume()}
    }
    private func drain()throws {
        let state=lg_input_state(ring.pointer)
        if state.overflow != 0{throw LiveInputError.overflow}
        if state.invalidInput != 0{throw LiveInputError.invalidSamples}
        while true {
            let count=lg_input_pop(ring.pointer,scratch,4096)
            if count==0{break}
            guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:count),let destination=buffer.floatChannelData?[0]else{throw LiveInputError.unsupportedFormat}
            buffer.frameLength=count;destination.update(from:scratch,count:Int(count))
            try receiver.receive(buffer)
        }
    }
    private func drainAndReport(){
        guard !stopped,failed==nil else{return}
        do{try drain()}catch{failed=error;lg_input_close(ring.pointer);timer?.cancel();onFailure(error.localizedDescription)}
    }
    func finish()throws {
        try queue.sync {
            timer?.cancel();timer=nil
            guard !stopped else{if let failed{throw failed};return}
            stopped=true
            defer{lg_input_close(ring.pointer)}
            if let failed{throw failed}
            do{try drain();try receiver.finish()}catch{failed=error;throw error}
        }
    }
}

/// Resource lifetime outlives any in-flight tap callback. Explicit stop removes
/// the tap before joining the consumer; deinit schedules the same cleanup on main.
private final class InputResources:@unchecked Sendable {
    let engine:AVAudioEngine
    let ring:InputRingHandle
    let worker:InputDrain
    let previousCategory:AVAudioSession.Category
    let previousMode:AVAudioSession.Mode
    let previousOptions:AVAudioSession.CategoryOptions
    var installed=false
    var stopped=false
    init(engine:AVAudioEngine,ring:InputRingHandle,worker:InputDrain,category:AVAudioSession.Category,mode:AVAudioSession.Mode,options:AVAudioSession.CategoryOptions){self.engine=engine;self.ring=ring;self.worker=worker;previousCategory=category;previousMode=mode;previousOptions=options}
    @MainActor func stop()throws {
        guard !stopped else{return};stopped=true
        if installed{engine.inputNode.removeTap(onBus:0);installed=false}
        lg_input_close(ring.pointer)
        var failure:Error?
        do{try worker.finish()}catch{failure=error}
        do {
            // Keep the existing output graph/kernel and active audio session.
            // Category restoration releases microphone access, never deactivates
            // the session or issues Stop/Seek to the backing transport.
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(previousCategory,mode:previousMode,options:previousOptions)
            if !engine.isRunning{try engine.start()}
        }catch{failure=failure ?? error}
        if let failure{throw failure}
    }
}

@MainActor final class LiveMicrophone {
    private let resources:InputResources
    let sampleRate:Double
    let startHostTime:UInt64
    let duration:Double
    let routeDiagnostics:[LiveInputRouteSnapshot]
    private let ticksPerSecond:Double
    var elapsed:Double{Double(lg_input_state(resources.ring.pointer).frames)/sampleRate}
    var level:Double{Double(lg_input_state(resources.ring.pointer).peak)}
    var complete:Bool{lg_input_state(resources.ring.pointer).finished != 0}
    var secondsUntilStart:Double{max(0,(Double(startHostTime)-Double(mach_absolute_time()))/ticksPerSecond)}
    var secondsSinceStart:Double{max(0,(Double(mach_absolute_time())-Double(startHostTime))/ticksPerSecond)}
    var recordedAt:Date? {
        let host=lg_input_state(resources.ring.pointer).firstHostTime
        return host==0 ? nil:Date(timeIntervalSinceNow:(Double(host)-Double(mach_absolute_time()))/ticksPerSecond)
    }
    init(audio:AudioController,delay:Double,duration:Double,schedule:(@MainActor(Double)->Double?)?=nil,scheduleDuration:(@MainActor()->Double?)?=nil,receiver:(AVAudioFormat)throws->LiveInputReceiver,onFailure:@escaping @MainActor @Sendable(String)->Void)throws {
        guard delay.isFinite,(0...30).contains(delay),duration.isFinite,duration>0 else{throw LiveInputError.invalidSamples}
        guard let engine=audio.captureEngine,engine.isRunning else{throw LiveInputError.outputUnavailable}
        let session=AVAudioSession.sharedInstance(),category=session.category,mode=session.mode,options=session.categoryOptions
        var pending:InputResources?
        var info=mach_timebase_info_data_t();mach_timebase_info(&info)
        ticksPerSecond=1_000_000_000*Double(info.denom)/Double(info.numer)
        do {
            try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothA2DP])
            try session.setActive(true)
            // Observe the existing output I/O unit before lazily creating input.
            // This query must not itself access inputNode or enable hardware.
            let beforeInputNode=LiveInputRouteSnapshot.IOUnit(engine.outputNode)
            let input=engine.inputNode
            var format=input.outputFormat(forBus:0)
            var routes=[LiveInputRouteSnapshot.capture(engine,stage:"activated-playAndRecord",outputUnitBeforeInputNode:beforeInputNode)]
            func usable(_ format:AVAudioFormat)->Bool{format.sampleRate.isFinite && (8000...192000).contains(format.sampleRate) && format.channelCount>0 && format.channelCount<=32}
            if routes.last?.hardwareAbsent==true{throw LiveInputSetupFailure(LiveInputError.unavailable,routes:routes)}
            if !usable(format),routes.last?.hardwareAbsent==false {
                // Input may be created after the playback-only I/O was prepared.
                // pause() keeps those resources; stop() releases them so the
                // same attached graph can prepare its actual duplex hardware.
                // The external source/kernel/music state is retained. Hardware
                // rendering stops during reprepare: its gap must be measured.
                // Never reset/replace the engine, seek or manufacture a format.
                engine.stop()
                routes.append(.capture(engine,stage:"same-graph-stopped"))
                do{engine.prepare();try engine.start()}
                catch{routes.append(.capture(engine,stage:"same-graph-reprepare-failed"));throw LiveInputSetupFailure(error,routes:routes)}
                format=input.outputFormat(forBus:0)
                routes.append(.capture(engine,stage:"same-graph-reprepared"))
            }
            guard usable(format)else{throw LiveInputSetupFailure(LiveInputError.unavailable,routes:routes)}
            guard format.commonFormat == .pcmFormatFloat32,let mono=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:format.sampleRate,channels:1,interleaved:false)else{throw LiveInputSetupFailure(LiveInputError.unsupportedFormat,routes:routes)}
            routeDiagnostics=routes
            let ring=try InputRingHandle(rate:format.sampleRate,limit:min(30,max(0.2,duration)))
            let worker=InputDrain(ring:ring,format:mono,receiver:try receiver(mono),onFailure:InputNotifications.forward(onFailure))
            let resources=InputResources(engine:engine,ring:ring,worker:worker,category:category,mode:mode,options:options)
            pending=resources
            self.resources=resources;sampleRate=format.sampleRate
            InputTapCallbacks.install(input:input,format:format,ring:ring);resources.installed=true
            if !engine.isRunning{try engine.start()}
            guard engine.isRunning else{throw LiveInputError.outputUnavailable}
            let chosenDelay:Double
            if let schedule{guard let value=schedule(delay)else{throw LiveInputError.invalidSamples};chosenDelay=value}else{chosenDelay=delay}
            guard chosenDelay.isFinite,chosenDelay>=delay,chosenDelay<=600 else{throw LiveInputError.invalidSamples}
            let chosenDuration:Double
            if let scheduleDuration{guard let value=scheduleDuration()else{throw LiveInputError.invalidSamples};chosenDuration=value}else{chosenDuration=min(30,duration)}
            guard chosenDuration.isFinite,chosenDuration>0,chosenDuration<=min(30,duration)else{throw LiveInputError.invalidSamples}
            self.duration=chosenDuration
            startHostTime=mach_absolute_time()+UInt64(max(0.05,chosenDelay)*ticksPerSecond)
            guard lg_input_arm_limit(ring.pointer,startHostTime,UInt64(ceil(sampleRate*chosenDuration))) != 0 else{throw LiveInputError.invalidSamples}
            worker.start()
        }catch{
            // The root lease handles presentation/retry; never silently replace
            // the continuing beat with a separate recording-only audio engine.
            if let pending{try? pending.stop()}
            else{try? session.setCategory(category,mode:mode,options:options);if !engine.isRunning{try? engine.start()}}
            throw error
        }
    }
    deinit{let resources=resources;Task{@MainActor in try? resources.stop()}}
    func stop()throws{try resources.stop()}
}
