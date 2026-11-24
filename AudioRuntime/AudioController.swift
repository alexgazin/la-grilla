import AVFoundation
import AudioDSP
import MusicDomain
import Observation
import Darwin
import Foundation

/// Only routing metadata is retained for a rendered generation, never a second
/// mutable project. MIDI must follow the layout actually adopted by the callback.
struct AudioMIDIRouting {
    let midi:MIDISettings
    let tracks:[Track]
}
private struct AudioTrackLayout:Equatable {
    let identity:UInt64
    let instrument:Int32
    let preset:Int32
    let channel:Int32
    let sample: SampleAsset?
    let pads: [Int: SampleAsset]?
}
final class KernelHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(rate: Double) throws {
        guard let pointer=lg_create(rate) else {
            throw NSError(domain:"LaGrilla.Audio",code:2,userInfo:[NSLocalizedDescriptionKey:"Could not allocate the audio renderer."])
        }
        self.pointer=pointer
    }
    deinit { lg_destroy(pointer) }
}

/// Bounded, read-only startup/recovery evidence. It contains no audio, device
/// names, port identifiers or user project data, and never creates an input node.
struct AudioFailureDetails:Codable,Sendable {
    let stage:String
    let domain:String
    let code:Int
    let fourCC:String?
    let detail:String
    let category:String
    let mode:String
    let sessionSampleRate:Double?
    let outputPortTypes:[String]
    let observedOutputSampleRate:Double?
    let observedOutputChannels:Int?
    let inputPriming:String
    let inputPrimed:Bool
    let preferenceWarnings:[String]
    let qaInjected:Bool
    let inputRetirementCount:Int
    let inputRetirementMilliseconds:Double
    let inputRetirementPending:Bool
    let currentGraphHasInputNode:Bool
    let activeAudioGraphCount:Int
}

/// Input failure metadata is deliberately copied into a separate, sanitized
/// shape. The historical QA route snapshots contain port names; those snapshots
/// must never be serialized into a user's shareable support report.
struct AudioInputFailureDetails:Codable,Sendable {
    struct Port:Codable,Sendable {
        let type:String
        let channels:Int
        init(_ port:AVAudioSessionPortDescription){type=String(port.portType.rawValue.prefix(80));channels=port.channels?.count ?? 0}
    }
    struct Route:Codable,Sendable {
        let stage:String
        let hardwareInput:LiveInputRouteSnapshot.Format
        let engineInput:LiveInputRouteSnapshot.Format
        let inputUnit:LiveInputRouteSnapshot.IOUnit
        let outputUnit:LiveInputRouteSnapshot.IOUnit
        init(_ value:LiveInputRouteSnapshot){stage=value.stage;hardwareInput=value.inputFormat;engineInput=value.outputFormat;inputUnit=value.inputUnit;outputUnit=value.outputUnit}
    }
    let stage:String
    let domain:String
    let code:Int
    let permission:String
    let category:String
    let mode:String
    let sessionSampleRate:Double?
    let inputAvailable:Bool
    let inputs:[Port]
    let availableInputs:[Port]
    let outputs:[Port]
    let observations:[Route]
    let inputPriming:String
    let inputPrimedAtStartup:Bool
    let inputTransitionCount:Int
    let inputTransitionMilliseconds:Double
    var cleanupDomain:String?
    var cleanupCode:Int?
}

private struct AudioStartFailure:LocalizedError {
    let underlying:Error
    var errorDescription:String? {
        NSLocalizedString("Audio could not start. Check the audio route and retry.",comment:"Audio startup")
    }
}
/// The render block must be constructed outside MainActor. AVFAudio's legacy block
/// type does not express Sendable; creating it in prepare() inherits MainActor
/// and Swift 6 traps when the engine calls it on the real-time audio thread.
private enum AudioRender {
    nonisolated static func makeSource(format: AVAudioFormat, kernel: KernelHandle,hub:MIDIHubHandle) -> AVAudioSourceNode {
        var info=mach_timebase_info_data_t();mach_timebase_info(&info)
        let ticks=1_000_000_000*Double(info.denom)/Double(info.numer)
        return AVAudioSourceNode(format:format) { @Sendable [kernel,hub] _, stamp, count, buffers in
            let output=UnsafeMutableAudioBufferListPointer(buffers)
            guard output.count==2,let left=output[0].mData,let right=output[1].mData else {
                for buffer in output {if let data=buffer.mData{memset(data,0,Int(buffer.mDataByteSize))}}
                return noErr
            }
            let host=stamp.pointee.mHostTime==0 ? mach_absolute_time():stamp.pointee.mHostTime
            lg_render_midi(kernel.pointer,hub.pointer,host,ticks,left.assumingMemoryBound(to:Float.self),right.assumingMemoryBound(to:Float.self),Int32(count))
            return noErr
        }
    }
}
@MainActor @Observable final class AudioController {
    @ObservationIgnored var samples = SampleLibrary()
    enum InputPrimingPolicy:String {case platformDefault,outputOnly,sharedInputFirst}
    private let inputPriming:InputPrimingPolicy
    private(set) var inputPrimedAtStartup=false
    private(set) var failureDetails:AudioFailureDetails?
    private(set) var inputFailureDetails:AudioInputFailureDetails?
    // Historical result of the latest capture setup, not current mic usage.
    // After retirement currentGraphHasInputNode describes the new output graph.
    private(set) var inputConfigured=false
    private(set) var inputTransitionCount=0
    private(set) var inputTransitionMilliseconds=0.0
    private(set) var inputRetirementCount=0
    private(set) var inputRetirementMilliseconds=0.0
    @ObservationIgnored private weak var lastRetiredInputEngine:AVAudioEngine?
    @ObservationIgnored private var pendingInputRetirement:PendingInputRetirement?
    @ObservationIgnored private var inputNodeTouchedInCurrentGraph=false
    private struct PendingInputRetirement {
        let engine:AVAudioEngine
        let category:AVAudioSession.Category
        let mode:AVAudioSession.Mode
        let options:AVAudioSession.CategoryOptions
        let began:UInt64
    }
    var inputRetirementPending:Bool{pendingInputRetirement != nil}
    // Inspect attachment state without invoking the lazy inputNode getter.
    var currentGraphHasInputNode:Bool{engine?.attachedNodes.contains{$0 is AVAudioInputNode} ?? false}
    var retiredInputGraphStopped:Bool{
        if let lastRetiredInputEngine{return !lastRetiredInputEngine.isRunning}
        return inputRetirementCount>0
    }
    var activeAudioGraphCount:Int{
        var count=engine?.isRunning == true ? 1:0
        if let retired=lastRetiredInputEngine,retired !== engine,retired.isRunning{count+=1}
        return count
    }
    var inputPrimingName:String{inputPriming.rawValue}
    @ObservationIgnored private var preferenceWarnings:[String]=[]
    @ObservationIgnored private var observedOutputSampleRate:Double?
    @ObservationIgnored private var observedOutputChannels:Int?
    let midiHub=MIDIHubHandle()
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var handle: KernelHandle?
    var tick: Double = 0; var playing = false; var appliedRevision = -1
    var meters: [Float] = Array(repeating:0,count:masterBus+1); var sampleRate: Double = 48000
    /// Luz meters: the highest recent level per bus, held 1 s, then falling.
    var peakHolds: [Float] = Array(repeating:0,count:masterBus+1)
    @ObservationIgnored private var peakTimes = [TimeInterval](repeating:0,count:masterBus+1)
    var countRemaining = 0; var error: String?
    var overflows = 0
    @ObservationIgnored var onPoll:(()->Void)?
    @ObservationIgnored var onRuntimeTrace:((String)->Void)?
    @ObservationIgnored private var lastRuntimeTracePoll:String?
    private var timer: Timer?
    @ObservationIgnored private var configurationObserver:NSObjectProtocol?
    private var generation = 0
    @ObservationIgnored private var musicCompilationCache=MusicCompilationCache()
    private var submittedNotes:[CompiledNote]?;private var submittedBPM=0.0;private var submittedRange:Range<Int>?;private var submittedLoop=false;private var submittedProject:UUID?
    private var performanceEpoch=0
    private var performanceBuffer=[LGPerformanceEvent](repeating:LGPerformanceEvent(),count:512)
    private var sentRevisions: [Int:Int] = [:]
    private var submittedLayout:[AudioTrackLayout]=[]
    private var routing:[Int:AudioMIDIRouting]=[:]
    private var pendingPreviews:[(UUID,Int)]=[]
    init(inputPriming:InputPrimingPolicy = .platformDefault){
        if inputPriming != .platformDefault {self.inputPriming=inputPriming}
        else if ProcessInfo.processInfo.arguments.contains("--uitesting"),ProcessInfo.processInfo.arguments.contains("--device-output-startup") {self.inputPriming = .outputOnly}
        else {
            #if targetEnvironment(simulator)
            self.inputPriming = .sharedInputFirst
            #else
            self.inputPriming = .outputOnly
            #endif
        }
    }
    var isPrepared: Bool { engine?.isRunning == true }
    /// U16: output port types of the current route, first first.
    var outputPortTypes:[String]{AVAudioSession.sharedInstance().currentRoute.outputs.map{$0.portType.rawValue}}
    var wirelessOutput:Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains{[AVAudioSession.Port.bluetoothA2DP,.bluetoothHFP,.bluetoothLE,.airPlay].contains($0.portType)}
    }
    var captureEngine:AVAudioEngine? {engine}
    var pendingSnapshot:Bool {guard let k=handle?.pointer else{return false};return generation != Int(lg_revision(k))}
    var activeMIDIRouting:AudioMIDIRouting? {guard let k=handle?.pointer else{return nil};return routing[Int(lg_revision(k))]}
    /// Bounded metadata retained alongside the kernel's three musical slots.
    var retainedRoutingCount:Int {routing.count}
    /// Control-path diagnostic; no render callback consults the compiler cache.
    var musicCompilationCount:Int{musicCompilationCache.compileCount}
    /// U37: compiled notes of a project from the shared cache (the playing project is already compiled).
    func compiledNotes(_ p:Project)->[CompiledNote]{musicCompilationCache.notes(p)}
    var clock: UInt64 = 0
    var failureReport:String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        if let inputFailureDetails {
            struct Report:Encodable {let output:AudioFailureDetails?;let input:AudioInputFailureDetails}
            guard let data=try? encoder.encode(Report(output:failureDetails,input:inputFailureDetails))else{return ""}
            return String(decoding:data,as:UTF8.self)
        }
        guard let failureDetails,let data=try? encoder.encode(failureDetails)else{return ""}
        return String(decoding:data,as:UTF8.self)
    }
    /// Read-only native test diagnostics. Never called from the render thread.
    var runtimeTraceState:String {
        let prefix="engineRunning=\(engine?.isRunning == true) controllerPlaying=\(playing) controllerTick=\(tick) controllerClock=\(clock) appliedRevision=\(appliedRevision) submittedGeneration=\(generation) inputPriming=\(inputPriming.rawValue) inputPrimed=\(inputPrimedAtStartup) inputConfigured=\(inputConfigured) inputTransitionCount=\(inputTransitionCount) inputTransitionMilliseconds=\(inputTransitionMilliseconds) inputRetirementCount=\(inputRetirementCount) inputRetirementMilliseconds=\(inputRetirementMilliseconds) inputRetirementPending=\(inputRetirementPending) currentGraphHasInputNode=\(currentGraphHasInputNode) retiredInputGraphStopped=\(retiredInputGraphStopped) activeAudioGraphCount=\(activeAudioGraphCount) failureStage=\(failureDetails?.stage ?? "none") qaAudioUnavailable=\(failureDetails?.qaInjected ?? false)"
        guard let k=handle?.pointer else{return prefix+" kernel=none error=\(error ?? "none")"}
        let revision=Int(lg_revision(k))
        return prefix+" kernel=\(UInt(bitPattern:k)) actualClock=\(lg_clock(k)) actualTick=\(lg_tick(k)) actualPlaying=\(lg_playing(k)) actualGeneration=\(revision) actualRevision=\(sentRevisions[revision] ?? -1) pending=\(generation != revision) error=\(error ?? "none")"
    }
    func prepare() throws {
        // A failed privacy handoff must retry a fresh output-only graph, never
        // revive the input-enabled graph that was deliberately retired.
        if pendingInputRetirement != nil{try finishInputRetirement();return}
        if engine?.isRunning == true { return }
        // A microphone category/configuration change may stop AVAudioEngine.
        // Restart the same graph: replacing the kernel would lose its clock,
        // pending musical transaction, held MIDI and ongoing performance.
        var stage="activate-existing-output"
        var pendingEngine:AVAudioEngine?
        do {
            if let engine,handle != nil {
                try AVAudioSession.sharedInstance().setActive(true)
                try startOutputGraph(engine,stage:&stage);error=nil;return
            }
            let arguments=ProcessInfo.processInfo.arguments
            if arguments.contains("--uitesting"),arguments.contains("--audio-unavailable") {
                stage="qa-output-unavailable"
                throw unavailableOutput()
            }
            let session = AVAudioSession.sharedInstance()
            stage="set-playback-category"
            try session.setCategory(.playback, mode: .default, options: [])
            preferenceWarnings=[]
            // These are preferences, not requirements. Use the negotiated
            // hardware format even when a route rejects the requested hints.
            preference("sample-rate"){try session.setPreferredSampleRate(48000)}
            preference("io-buffer"){try session.setPreferredIOBufferDuration(0.0053)}
            stage="activate-playback"
            try session.setActive(true)
            let e=AVAudioEngine();pendingEngine=e
            inputPrimedAtStartup=false;inputNodeTouchedInCurrentGraph=false
            if inputPriming == .sharedInputFirst {
                // Simulator HAL requires this ordering for later shared input.
                // A physical playback-only graph must not initialize input
                // before the user explicitly grants capture permission.
                stage="prime-simulator-input"
                _ = e.inputNode;inputPrimedAtStartup=true;inputNodeTouchedInCurrentGraph=true
            }
            stage="read-initial-output-format"
            let output=try outputFormat(e)
            sampleRate=output.sampleRate
            let h=try KernelHandle(rate:sampleRate)
            // Preserve position only when creating a new kernel after an idle
            // reset. Recovery of an existing graph never resets/seeks it.
            lg_seek(h.pointer,Int32(max(0,tick).rounded(.down)))
            guard let format=AVAudioFormat(standardFormatWithSampleRate:sampleRate,channels:2)else{throw unavailableOutput()}
            let node=AudioRender.makeSource(format:format,kernel:h,hub:midiHub)
            stage="connect-source"
            e.attach(node);e.connect(node,to:e.mainMixerNode,format:format)
            try startOutputGraph(e,stage:&stage)
            metronomeSettings.apply(to: h.pointer)
            handle=h;source=node;engine=e;submittedNotes=nil;pendingEngine=nil
            observeConfiguration(of:e)
            timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:1/30,repeats:true){[weak self] _ in
                Task{@MainActor in self?.poll()}
            }
            error=nil
        }catch {
            pendingEngine?.stop()
            recordFailure(error,stage:stage,qaInjected:stage=="qa-output-unavailable")
            throw AudioStartFailure(underlying:error)
        }
    }
    /// An output-only I/O unit may already be initialized without input. Stop
    /// it BEFORE changing category or lazily creating the input node, rather
    /// than asking an initialized output unit for a zero-format input and then
    /// trying to repair it. The source/kernel and every musical queue survive.
    /// Simulator's input-first graph already owns input and needs no such stop.
    /// Reapply this for each output-only lease: restoring playback or changing
    /// hardware can invalidate the previous input configuration.
    func beginMicrophoneConfiguration()throws->UInt64? {
        guard let engine,handle != nil else{throw LiveInputError.outputUnavailable}
        inputConfigured=false
        guard !inputPrimedAtStartup else{return nil}
        let began=mach_absolute_time()
        engine.stop()
        inputTransitionCount+=1
        onRuntimeTrace?("audio.input.transition.begin")
        return began
    }
    func finishMicrophoneConfiguration(_ began:UInt64?,ready:Bool){
        inputConfigured=ready
        if let began {
            var info=mach_timebase_info_data_t();mach_timebase_info(&info)
            inputTransitionMilliseconds=Double(mach_absolute_time()-began)*Double(info.numer)/Double(info.denom)/1_000_000
        }
        onRuntimeTrace?(ready ? "audio.input.transition.ready":"audio.input.transition.failed")
    }
    func recordInputFailure(_ cause:Error,stage:String,routes:[LiveInputRouteSnapshot]){
        let failure=cause as NSError,session=AVAudioSession.sharedInstance()
        let permission=AVAudioApplication.shared.recordPermission
        inputFailureDetails=AudioInputFailureDetails(
            stage:String(stage.prefix(100)),domain:String(failure.domain.prefix(160)),code:failure.code,
            permission:permission == .granted ? "granted":permission == .denied ? "denied":"undetermined",
            category:session.category.rawValue,mode:session.mode.rawValue,
            sessionSampleRate:session.sampleRate.isFinite ? session.sampleRate:nil,
            inputAvailable:session.isInputAvailable,
            inputs:session.currentRoute.inputs.prefix(8).map{.init($0)},
            availableInputs:(session.availableInputs ?? []).prefix(8).map{.init($0)},
            outputs:session.currentRoute.outputs.prefix(8).map{.init($0)},
            observations:routes.prefix(4).map{.init($0)},inputPriming:inputPriming.rawValue,
            inputPrimedAtStartup:inputPrimedAtStartup,inputTransitionCount:inputTransitionCount,
            inputTransitionMilliseconds:inputTransitionMilliseconds
        )
        onRuntimeTrace?("audio.input.failure."+stage)
    }
    func recordInputCleanupFailure(_ cause:Error){
        let failure=cause as NSError
        inputFailureDetails?.cleanupDomain=String(failure.domain.prefix(160));inputFailureDetails?.cleanupCode=failure.code
    }
    func noteMicrophoneInputAccess(on expectedEngine:AVAudioEngine){
        if engine === expectedEngine{inputNodeTouchedInCurrentGraph=true}
    }
    /// AVAudioEngine's SDK contract warns that once input has been enabled,
    /// running that engine can keep the microphone-use indicator active. After
    /// an explicit capture stop, retire its I/O graph for the output-only policy.
    /// DSP state is owned by KernelHandle, not by either AVAudioEngine instance.
    func restoreAfterMicrophone(expectedEngine:AVAudioEngine,category:AVAudioSession.Category,mode:AVAudioSession.Mode,options:AVAudioSession.CategoryOptions)throws {
        // Explicit cleanup and a queued deinit may both arrive. An old lease
        // cannot change the category or restart a successor's current graph.
        guard engine === expectedEngine else{return}
        let hasInput=expectedEngine.attachedNodes.contains{$0 is AVAudioInputNode}
        if inputPriming == .outputOnly,(inputNodeTouchedInCurrentGraph || hasInput) {
            if pendingInputRetirement == nil {
                pendingInputRetirement=PendingInputRetirement(engine:expectedEngine,category:category,mode:mode,options:options,began:mach_absolute_time())
                lastRetiredInputEngine=expectedEngine
                if let configurationObserver{NotificationCenter.default.removeObserver(configurationObserver)}
                configurationObserver=nil
                // Stop before restoring the playback category. The old graph
                // stays stopped even if constructing its replacement fails.
                expectedEngine.stop()
                onRuntimeTrace?("audio.input.retirement.begin")
            }
            try finishInputRetirement()
        }else{
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(category,mode:mode,options:options)
            if !expectedEngine.isRunning{try resumeOutputAfterInputChange()}
        }
    }
    private func finishInputRetirement()throws {
        guard let pending=pendingInputRetirement else{return}
        guard engine === pending.engine,let handle else{throw LiveInputError.outputUnavailable}
        var stage="retire-input-stop"
        var replacement:AVAudioEngine?
        do {
            pending.engine.stop()
            guard !pending.engine.isRunning else{throw LiveInputError.outputUnavailable}
            let session=AVAudioSession.sharedInstance()
            stage="retire-input-category"
            try session.setCategory(pending.category,mode:pending.mode,options:pending.options)
            stage="retire-input-activate-output"
            try session.setActive(true)
            let next=AVAudioEngine();replacement=next
            // Do not touch next.inputNode, including from diagnostics. The new
            // source shares the existing kernel, MIDI hub and original DSP rate.
            guard let format=AVAudioFormat(standardFormatWithSampleRate:sampleRate,channels:2)else{throw unavailableOutput()}
            let node=AudioRender.makeSource(format:format,kernel:handle,hub:midiHub)
            stage="retire-input-connect-source"
            next.attach(node);next.connect(node,to:next.mainMixerNode,format:format)
            try startOutputGraph(next,stage:&stage)
            guard next.isRunning,!pending.engine.isRunning else{throw LiveInputError.outputUnavailable}
            // Publish only a running replacement. No kernel creation, stop,
            // seek, music resubmission, generation or routing changes occur.
            source=node;engine=next;replacement=nil;inputNodeTouchedInCurrentGraph=false
            observeConfiguration(of:next)
            inputRetirementCount+=1
            inputRetirementMilliseconds=milliseconds(since:pending.began)
            pendingInputRetirement=nil
            error=nil
            onRuntimeTrace?("audio.input.retirement.ready")
        }catch {
            replacement?.stop();pending.engine.stop()
            inputRetirementMilliseconds=milliseconds(since:pending.began)
            recordFailure(error,stage:stage)
            throw AudioStartFailure(underlying:error)
        }
    }
    private func milliseconds(since host:UInt64)->Double {
        var info=mach_timebase_info_data_t();mach_timebase_info(&info)
        return Double(mach_absolute_time()-host)*Double(info.numer)/Double(info.denom)/1_000_000
    }
    private func observeConfiguration(of observedEngine:AVAudioEngine){
        if let configurationObserver{NotificationCenter.default.removeObserver(configurationObserver)}
        let identity=ObjectIdentifier(observedEngine)
        configurationObserver=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:observedEngine,queue:.main){ @Sendable [weak self] _ in
            Task{@MainActor in
                guard let self,let current=self.engine,ObjectIdentifier(current)==identity else{return}
                self.resumeConfiguredGraph()
            }
        }
    }
    /// Called after category/tap changes only if the OS stopped this graph.
    /// The source, kernel, musical clock and submitted generations are retained.
    func resumeOutputAfterInputChange()throws {
        if pendingInputRetirement != nil{try finishInputRetirement();return}
        guard let engine,handle != nil else{throw LiveInputError.outputUnavailable}
        guard !engine.isRunning else{return}
        var stage="resume-input-output"
        do{try startOutputGraph(engine,stage:&stage);error=nil}
        catch{recordFailure(error,stage:stage);throw AudioStartFailure(underlying:error)}
    }
    private func outputFormat(_ engine:AVAudioEngine)throws->AVAudioFormat {
        let format=engine.outputNode.inputFormat(forBus:0)
        observedOutputSampleRate=format.sampleRate.isFinite ? format.sampleRate:nil
        observedOutputChannels=Int(format.channelCount)
        guard format.sampleRate.isFinite,(8000...192000).contains(format.sampleRate),format.channelCount>0,format.channelCount<=32 else{throw unavailableOutput()}
        return format
    }
    private func startOutputGraph(_ engine:AVAudioEngine,stage:inout String)throws {
        stage="read-output-format"
        let output=try outputFormat(engine)
        // A route can change the negotiated output rate or mono/stereo layout. The mixer
        // converts the existing stereo source; never change the DSP clock rate.
        let mixer=engine.mainMixerNode
        let connected=engine.outputConnectionPoints(for:mixer,outputBus:0).contains{$0.node === engine.outputNode && $0.bus==0}
        let current=mixer.outputFormat(forBus:0)
        if !connected || current.sampleRate != output.sampleRate || current.channelCount != output.channelCount {
            stage="connect-engine-output"
            engine.connect(mixer,to:engine.outputNode,format:output)
        }
        stage="prepare-output"
        engine.prepare()
        stage="start-output"
        try engine.start()
    }
    private func preference(_ name:String,_ action:()throws->Void){
        do{try action()}catch{
            let failure=error as NSError
            preferenceWarnings.append(String((name+": "+failure.domain+"/"+String(failure.code)).prefix(160)))
            if preferenceWarnings.count>4{preferenceWarnings.removeFirst()}
        }
    }
    private func unavailableOutput()->NSError {
        NSError(domain:"LaGrilla.Audio",code:1,userInfo:[NSLocalizedDescriptionKey:"No audio output is available. Connect an audio device and retry."])
    }
    private func recordFailure(_ cause:Error,stage:String,qaInjected:Bool=false){
        let failure=cause as NSError,session=AVAudioSession.sharedInstance()
        let bits=UInt32(truncatingIfNeeded:failure.code)
        let bytes=[UInt8((bits>>24)&255),UInt8((bits>>16)&255),UInt8((bits>>8)&255),UInt8(bits&255)]
        let fourCC=bytes.allSatisfy{(32...126).contains($0)} ? String(bytes:bytes,encoding:.ascii):nil
        let sessionRate:Double?=session.sampleRate.isFinite ? session.sampleRate:nil
        let ports:[String]=session.currentRoute.outputs.prefix(8).map{String($0.portType.rawValue.prefix(80))}
        failureDetails=AudioFailureDetails(
            stage:stage,
            domain:String(failure.domain.prefix(160)),
            code:failure.code,
            fourCC:fourCC,
            detail:String(failure.localizedDescription.prefix(400)),
            category:session.category.rawValue,
            mode:session.mode.rawValue,
            sessionSampleRate:sessionRate,
            outputPortTypes:ports,
            observedOutputSampleRate:observedOutputSampleRate,
            observedOutputChannels:observedOutputChannels,
            inputPriming:inputPriming.rawValue,
            inputPrimed:inputPrimedAtStartup,
            preferenceWarnings:preferenceWarnings,
            qaInjected:qaInjected,inputRetirementCount:inputRetirementCount,
            inputRetirementMilliseconds:inputRetirementMilliseconds,inputRetirementPending:inputRetirementPending,
            currentGraphHasInputNode:currentGraphHasInputNode,activeAudioGraphCount:activeAudioGraphCount
        )
        error=AudioStartFailure(underlying:cause).localizedDescription
        onRuntimeTrace?("audio.failure."+stage)
    }
    private func resumeConfiguredGraph(){
        onRuntimeTrace?("audio.configuration.before")
        defer{onRuntimeTrace?("audio.configuration.after")}
        guard let engine,handle != nil,!engine.isRunning else{return}
        do{try resumeOutputAfterInputChange()}
        catch{/* The resume operation retained its real failure diagnostics. */}
    }
    func poll() {
        guard let k = handle?.pointer else { return }
        clock = lg_clock(k); tick = lg_tick(k); playing = lg_playing(k) != 0; appliedRevision = sentRevisions[Int(lg_revision(k))] ?? -1; countRemaining = Int(lg_countremaining(k)); overflows = Int(lg_overflows(k))
        meters = (0...masterBus).map {lg_meter(k,Int32($0))}
        let now = ProcessInfo.processInfo.systemUptime
        var holds = peakHolds
        for bus in holds.indices {
            if meters[bus] >= holds[bus] { holds[bus] = meters[bus]; peakTimes[bus] = now }
            else if now - peakTimes[bus] > 1 { holds[bus] = max(meters[bus], holds[bus] * 0.92) }
        }
        if holds != peakHolds { peakHolds = holds }
        if let onRuntimeTrace {
            let state="\(engine?.isRunning == true)/\(playing)/\(lg_revision(k))/\(generation)"
            if state != lastRuntimeTracePoll{lastRuntimeTracePoll=state;onRuntimeTrace("audio.poll.transition")}
        }
        flushPreviews();onPoll?()
    }
    /// Read the audio clock at the touch, rather than using the last 30 Hz UI poll.
    func refreshClock(){guard let k=handle?.pointer else{return};clock=lg_clock(k);tick=lg_tick(k);playing=lg_playing(k) != 0;countRemaining=Int(lg_countremaining(k))}
    @discardableResult func submit(_ p: Project, loop: Bool, range: Range<Int>, auditionSamples: SampleLibrary? = nil) -> Bool {
        guard let k = handle?.pointer else { return false }
        let compiled=musicCompilationCache.notes(p),layout=trackLayout(p)
        if compiled==submittedNotes,p.bpm==submittedBPM,range==submittedRange,loop==submittedLoop,p.id==submittedProject,layout==submittedLayout {
            sentRevisions[generation]=p.revision;routing[generation]=midiRouting(p)
            if Int(lg_revision(k))==generation{appliedRevision=p.revision};return mix(p)
        }
        let next=generation+1
        let notes = compiled.map { LGNote(tick: Int32($0.tick), duration: Int32($0.duration), pitch: Int32($0.pitch), velocity: Int32($0.velocity), track: Int32($0.track), pad: Int32($0.pad),instrument:Int32($0.instrument)) }
        let mixes=trackMix(p)
        let tracks=layout.enumerated().map{i,t in LGProjectTrack(mix:mixes[i],presetVersion:t.preset,instrument:t.instrument,midiChannel:t.channel,identity:t.identity)}
        let fx=p.masterFX ?? MasterFX()
        let ok: Int32
        do {
            ok = try (auditionSamples ?? samples).withRoutes(for: p) { instruments, pads in
                notes.withUnsafeBufferPointer { n in tracks.withUnsafeBufferPointer { t in
                    lg_submit_project_eq(k,n.baseAddress,Int32(n.count),p.bpm,Int32(range.lowerBound),Int32(range.upperBound),loop ? 1:0,Int32(next),layoutToken(layout),t.baseAddress,Int32(t.count),Float(p.master),Float(fx.filter),Float(fx.delayWet),instruments,pads,p.equalizerBands())
                }}
            }
        } catch { self.error = error.localizedDescription; return false }
        guard ok != 0 else{error="Audio update could not be queued. Stop and retry.";return false}
        p.applyDynamics(to: k); p.applyAutomation(to: k); p.applySynths(to: k)
        lg_tail_on_end(k, !loop && p.hasComposedEnding == true ? 1 : 0)
        generation=next;sentRevisions[next]=p.revision;routing[next]=midiRouting(p)
        pruneRouting(k)
        submittedNotes=compiled;submittedBPM=p.bpm;submittedRange=range;submittedLoop=loop;submittedProject=p.id;submittedLayout=layout
        return true
    }
    private func pruneRouting(_ k:OpaquePointer){
        // Reading just the applied revision and keeping recent submissions can
        // lose a generation adopted between that read and pruning. The kernel
        // exposes all three slot IDs on this same serialized publication thread.
        var slots=[Int32](repeating:-1,count:3)
        let count=slots.withUnsafeMutableBufferPointer{lg_snapshot_generations(k,$0.baseAddress,Int32($0.count))}
        let retained=Set(slots.prefix(Int(count)).map(Int.init)).union([generation])
        sentRevisions=sentRevisions.filter{retained.contains($0.key)}
        routing=routing.filter{retained.contains($0.key)}
    }
    private func trackLayout(_ p:Project)->[AudioTrackLayout]{
        var melody:Int32=2
        return p.tracks.map{track in
            let channel:Int32
            switch track.role{case .harmony:channel=0;case .drums:channel=9;case .bass:channel=1;case .melody:channel=melody;melody+=1}
            return AudioTrackLayout(identity:MIDIController.trackIdentity(track.id),instrument:Int32(track.role.instrument),preset:Int32(track.presetVersion),channel:channel,sample:track.instrumentSample,pads:track.padSamples)
        }
    }
    private func layoutToken(_ layout:[AudioTrackLayout])->UInt64 {
        var value:UInt64=14_695_981_039_346_656_037
        for track in layout{value=(value ^ track.identity) &* 1_099_511_628_211;value=(value ^ UInt64(track.instrument)) &* 1_099_511_628_211}
        return value==0 ? 1:value
    }
    private func midiRouting(_ p:Project)->AudioMIDIRouting {
        AudioMIDIRouting(midi:p.midi ?? MIDISettings(),tracks:p.tracks.map{var track=$0;track.clips=[];return track})
    }
    private func trackMix(_ p:Project)->[LGTrackMix]{
        let solo=p.tracks.contains(where:\.solo)
        return p.tracks.map{LGTrackMix(gainDB:Float($0.gain),pan:Float($0.pan),audible:!$0.mute && (!solo || $0.solo) ? 1:0)}
    }
    @discardableResult func mix(_ p: Project)->Bool {
        guard let k=handle?.pointer,generation>0,p.id==submittedProject,trackLayout(p)==submittedLayout else{return false}
        let tracks=trackMix(p)
        let fx=p.masterFX ?? MasterFX()
        let accepted=tracks.withUnsafeBufferPointer{lg_mix_revision_eq(k,$0.baseAddress,Int32($0.count),Float(p.master),Float(fx.filter),Float(fx.delayWet),Int32(generation),p.equalizerBands())} != 0
        if accepted{p.applyDynamics(to: k); p.applyAutomation(to: k); p.applySynths(to: k)}
        if !accepted{error="Audio update could not be queued. Stop and retry."};return accepted
    }
    func play(countInBPM: Double? = nil) {
        guard let k = handle?.pointer else { return }
        if let bpm = countInBPM {lg_countin(k,Int32((sampleRate*240/bpm).rounded()))}
        lg_play(k,1); playing = true
    }
    @discardableResult func audition(_ p: Project, range: Range<Int>, tick: Int? = nil, loop: Bool = true,
                                     samples: SampleLibrary? = nil, restart: Bool = false) -> Bool {
        refreshClock()
        let continuing = playing
        guard submit(p, loop: loop, range: range, auditionSamples: samples) else { return false }
        if restart || !continuing { restartAt(tick ?? range.lowerBound) }
        return true
    }
    func restartAt(_ tick: Int) {
        seek(tick)
        if let k = handle?.pointer { lg_restart(k); playing = true }
    }
    func stop() {if let k = handle?.pointer {lg_play(k,0)}; playing = false}
    func seek(_ tick: Int) {if let k = handle?.pointer {lg_seek(k,Int32(tick))}; self.tick = Double(tick)}
    @discardableResult func pad(_ pad: Int, velocity: Int = 100)->Bool {
        guard (0..<16).contains(pad),let k=handle?.pointer else{return false}
        let accepted=lg_pad(k,Int32(pad),Int32(velocity)) != 0
        if !accepted{error=NSLocalizedString("A pad hit could not be queued. Try again.",comment:"Live drum input")}
        return accepted
    }
    func preview(_ chord: Chord) {if let k = handle?.pointer {for n in chord.notes {lg_preview(k,Int32(n))}}}
    func previewNote(_ pitch:Int,track:Int){
        guard (0...127).contains(pitch),let desired=routing[generation],desired.tracks.indices.contains(track)else{return}
        let id=desired.tracks[track].id
        if !previewNote(pitch,id:id){pendingPreviews.append((id,pitch));if pendingPreviews.count>32{pendingPreviews.removeFirst()}}
    }
    private func previewNote(_ pitch:Int,id:UUID)->Bool {
        guard let k=handle?.pointer,let active=activeMIDIRouting,active.tracks.contains(where:{$0.id==id})else{return false}
        // A layout can change after the main-thread lookup but before the
        // callback drains its input queue. Resolve the UUID key in that callback.
        return lg_note_preview_track(k,Int32(pitch),MIDIController.trackIdentity(id)) != 0
    }
    private func flushPreviews(){
        let waiting=pendingPreviews;pendingPreviews=[]
        for (id,pitch) in waiting where routing[generation]?.tracks.contains(where:{$0.id==id})==true {
            if !previewNote(pitch,id:id){pendingPreviews.append((id,pitch))}
        }
    }
    func stopRenderAndFinalizePerformance(){engine?.stop();if let k=handle?.pointer{lg_perform_finalize_paused(k)};playing=false}
    func withKernel<T>(_ action:(OpaquePointer)->T)->T?{guard let pointer=handle?.pointer else{return nil};return action(pointer)}
    func beginPerformance(_ p:Project,section:MusicDomain.Section,token:Int,recording:Bool,replay:[LGPerformanceEvent]?=nil,duration:UInt64=0)throws->Int {
        guard let k=handle?.pointer else{throw MusicError.invalidProject};performanceEpoch+=1
        submittedNotes=nil;submit(p,loop:true,range:section.start..<section.start+section.length);metronome(false);seek(section.start)
        if let replay{let ok=replay.withUnsafeBufferPointer{lg_perform_replay_submit(k,$0.baseAddress,Int32($0.count),duration,Int32(performanceEpoch))};guard ok != 0 else{throw MusicError.invalidProject}}
        let limit=UInt64((Double(songTickLimit)/Double(ppq)*60/p.bpm*sampleRate).rounded())
        lg_perform_begin(k,Int32(token),Int32(performanceEpoch),recording ? 1:0,recording ? limit:0);playing=true;return performanceEpoch
    }
    func drainPerformance()->[LGPerformanceEvent]{guard let k=handle?.pointer else{return []};var result:[LGPerformanceEvent]=[];while true{let count=performanceBuffer.withUnsafeMutableBufferPointer{lg_perform_pop(k,$0.baseAddress,Int32($0.count))};if count==0{break};result.append(contentsOf:performanceBuffer.prefix(Int(count)))};return result}
    func effects(_ fx:MasterFX){if let k=handle?.pointer{lg_effects(k,Float(fx.filter),Float(fx.delayWet))}}
    func panic(){if let k=handle?.pointer{lg_panic(k)};playing=false}
    /// I10: level, accent, sound and count-in-only, kept in UserDefaults.
    var metronomeSettings = AudioController.storedMetronome {
        didSet {
            if let data = try? JSONEncoder().encode(metronomeSettings) { UserDefaults.standard.set(data, forKey: "metronome.settings") }
            if let k = handle?.pointer { metronomeSettings.apply(to: k); lg_metronome(k, metronomeOn && !metronomeSettings.countInOnly ? 1 : 0) }
        }
    }
    private static var storedMetronome: MetronomeSettings {
        guard let data = UserDefaults.standard.data(forKey: "metronome.settings"), let value = try? JSONDecoder().decode(MetronomeSettings.self, from: data) else { return MetronomeSettings() }
        return MetronomeSettings(gainDB: value.gainDB, accent: value.accent, sound: value.sound, countInOnly: value.countInOnly)
    }
    private var metronomeOn = false
    /// I15: live arpeggio of the held pitches on the track with `identity`; empty stops.
    @discardableResult func arp(identity: UInt64, pitches: [Int], step: Int, mode: Int, octaves: Int, velocity: Int = 100) -> Bool {
        guard let k = handle?.pointer else { return false }
        let values = pitches.prefix(16).map { Int32($0) }
        return values.withUnsafeBufferPointer { lg_arp(k, identity, $0.baseAddress, Int32($0.count), Int32(step), Int32(mode), Int32(octaves), Int32(velocity)) } != 0
    }
    /// I29: the custom pattern played by arpeggio mode 4 (empty clears it).
    @discardableResult func arpPattern(_ codes: [Int]) -> Bool {
        guard let k = handle?.pointer else { return false }
        let values = codes.prefix(16).map { Int32($0) }
        return values.withUnsafeBufferPointer { lg_arp_pattern(k, $0.baseAddress, Int32($0.count)) } != 0
    }
    /// I16: pitch bend (semitones) and modulation (0...1) for the track with `identity`.
    func pitchBend(identity: UInt64, semitones: Float, modulation: Float) { if let k = handle?.pointer { lg_pitch_bend(k, identity, semitones, modulation) } }
    /// I37: a lane being re-recorded stops reading so the hand on the control is heard.
    func suspendAutomation(track index: Int, parameter: AutomationLane.Parameter) {
        guard let k = handle?.pointer, (0..<masterBus).contains(index) else { return }
        _ = lg_track_automation(k, Int32(index), parameter == .level ? 0 : 1, nil, 0)
    }
    /// I55: hear a synth patch while its knobs move, before the edit is committed.
    func previewSynth(track index: Int, _ patch: SynthPatch?) {
        guard let k = handle?.pointer, (0..<masterBus).contains(index) else { return }
        if let patch { var value = LGSynthPatch(wave: Int32(patch.wave.rawValue), cutoff: Float(patch.cutoff), resonance: Float(patch.resonance), attack: Float(patch.attack), decay: Float(patch.decay), sustain: Float(patch.sustain), release: Float(patch.release)); _ = lg_synth(k, Int32(index), &value) }
        else { _ = lg_synth(k, Int32(index), nil) }
    }
    /// I82: MIDI clock and transport messages on the selected output.
    func midiClock(_ on: Bool) { if let k = handle?.pointer { lg_midi_clock_out(k, on ? 1 : 0) } }
    /// I63: the latest mono master samples for the spectrum view.
    func scope(_ count: Int) -> [Float] {
        guard let k = handle?.pointer else { return [] }
        var samples = [Float](repeating: 0, count: max(0, min(4096, count)))
        let n = samples.withUnsafeMutableBufferPointer { lg_scope_read(k, $0.baseAddress, Int32($0.count)) }
        return Array(samples.prefix(Int(n)))
    }
    /// I3: start (pad) or stop (nil) the kernel's note repeat.
    @discardableResult func padRepeat(_ pad: Int?, step: Int = 240, velocity: Int = 100) -> Bool {
        guard let k = handle?.pointer else { return false }
        return lg_pad_repeat(k, Int32(pad ?? -1), Int32(step), Int32(velocity)) != 0
    }
    func metronome(_ on: Bool) {metronomeOn=on;if let k = handle?.pointer {metronomeSettings.apply(to: k);lg_metronome(k,on && !metronomeSettings.countInOnly ? 1 : 0)}}
    func invalidateMusicSnapshot(){submittedNotes=nil}
    func reset() {
        musicCompilationCache.reset()
        submittedNotes=nil;submittedLayout=[];routing=[:];sentRevisions=[:];pendingPreviews=[];generation=0
        stop();timer?.invalidate()
        if let configurationObserver{NotificationCenter.default.removeObserver(configurationObserver)};configurationObserver=nil
        engine?.stop();engine=nil;source=nil;handle=nil
        inputConfigured=false;inputTransitionCount=0;inputTransitionMilliseconds=0
        pendingInputRetirement=nil;lastRetiredInputEngine=nil;inputRetirementCount=0;inputRetirementMilliseconds=0;inputNodeTouchedInCurrentGraph=false
    }
}
