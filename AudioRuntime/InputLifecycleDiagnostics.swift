import AVFoundation
import AudioDSP
import Darwin
import Foundation

/// An isolated construction-order experiment, never a production fallback.
/// It intentionally releases Session.audio, then creates and tears down four
/// independent local graphs. Even successful PCM is diagnostic evidence only.
@MainActor enum InputLifecycleDiagnostics {
    private struct Failure:LocalizedError {
        let message:String
        var errorDescription:String?{message}
    }
    private enum Order:Int,CaseIterable {
        case duplexInputFirst,playbackInputPrecreated,playbackOutputFirst,duplexOutputFirst
        var id:String{switch self {
        case .duplexInputFirst:"duplex-input-first"
        case .playbackInputPrecreated:"playback-disabled-input-precreated"
        case .playbackOutputFirst:"playback-output-first-late-input"
        case .duplexOutputFirst:"duplex-output-first-late-input"
        }}
        var explanation:String{switch self {
        case .duplexInputFirst:"playAndRecord before engine creation; input getter before output graph, prepare and start"
        case .playbackInputPrecreated:"playback before engine creation; disabled input precreated before output graph/prepare/start; playAndRecord; same local engine stop/reprepare"
        case .playbackOutputFirst:"playback before engine creation; output-only prepare/start; playAndRecord; late input getter; same local engine stop/reprepare"
        case .duplexOutputFirst:"playAndRecord before engine creation; output-only prepare/start; input getter after start; no reprepare"
        }}
        var beginsDuplex:Bool{self == .duplexInputFirst || self == .duplexOutputFirst}
        var inputFirst:Bool{self == .duplexInputFirst || self == .playbackInputPrecreated}
    }
    private struct Stage:Encodable {
        let name:String
        let category:String
        let mode:String
        let sessionSampleRate:Double
        let inputAvailable:Bool
        let inputs:[LiveInputRouteSnapshot.Port]
        let availableInputs:[LiveInputRouteSnapshot.Port]
        let outputs:[LiveInputRouteSnapshot.Port]
        let engineRunning:Bool
        let inputGetterAlreadyInvoked:Bool
        let inputHardwareFormat:LiveInputRouteSnapshot.Format?
        let inputEngineFormat:LiveInputRouteSnapshot.Format?
        let outputHardwareFormat:LiveInputRouteSnapshot.Format
        let outputEngineFormat:LiveInputRouteSnapshot.Format
        let inputIOUnit:LiveInputRouteSnapshot.IOUnit?
        let outputIOUnit:LiveInputRouteSnapshot.IOUnit
        private enum CodingKeys:String,CodingKey {case name,category,mode,sessionSampleRate,inputAvailable,inputs,availableInputs,outputs,engineRunning,inputGetterAlreadyInvoked,inputHardwareFormat,inputEngineFormat,outputHardwareFormat,outputEngineFormat,inputIOUnit,outputIOUnit}
        func encode(to encoder:Encoder)throws {
            var fields=encoder.container(keyedBy:CodingKeys.self)
            try fields.encode(name,forKey:.name);try fields.encode(category,forKey:.category);try fields.encode(mode,forKey:.mode)
            try fields.encode(sessionSampleRate,forKey:.sessionSampleRate);try fields.encode(inputAvailable,forKey:.inputAvailable)
            try fields.encode(inputs,forKey:.inputs);try fields.encode(availableInputs,forKey:.availableInputs);try fields.encode(outputs,forKey:.outputs)
            try fields.encode(engineRunning,forKey:.engineRunning);try fields.encode(inputGetterAlreadyInvoked,forKey:.inputGetterAlreadyInvoked)
            try fields.encode(inputHardwareFormat,forKey:.inputHardwareFormat);try fields.encode(inputEngineFormat,forKey:.inputEngineFormat)
            try fields.encode(outputHardwareFormat,forKey:.outputHardwareFormat);try fields.encode(outputEngineFormat,forKey:.outputEngineFormat)
            try fields.encode(inputIOUnit,forKey:.inputIOUnit);try fields.encode(outputIOUnit,forKey:.outputIOUnit)
        }
        @MainActor init(_ name:String,engine:AVAudioEngine,input:AVAudioInputNode?){
            let session=AVAudioSession.sharedInstance(),output=engine.outputNode
            self.name=name;category=session.category.rawValue;mode=session.mode.rawValue
            sessionSampleRate=session.sampleRate;inputAvailable=session.isInputAvailable
            inputs=session.currentRoute.inputs.map{.init($0)}
            availableInputs=(session.availableInputs ?? []).map{.init($0)}
            outputs=session.currentRoute.outputs.map{.init($0)}
            engineRunning=engine.isRunning;inputGetterAlreadyInvoked=input != nil
            // Never fetch engine.inputNode here: output-first controls must
            // preserve their ordering until the explicit getter in runCase.
            inputHardwareFormat=input.map{.init($0.inputFormat(forBus:0))}
            inputEngineFormat=input.map{.init($0.outputFormat(forBus:0))}
            outputHardwareFormat = .init(output.outputFormat(forBus:0))
            outputEngineFormat = .init(output.inputFormat(forBus:0))
            inputIOUnit=input.map{.init($0)};outputIOUnit = .init(output)
        }
    }
    private struct CaseReport:Encodable {
        let id:String
        let order:String
        var stages:[Stage]=[]
        var tapInstalled=false
        var tapStage:String?
        var actualFrames:UInt64=0
        var drainedFrames:UInt64=0
        var firstHostTime:UInt64=0
        var lastHostTime:UInt64=0
        var overflow=false
        var invalidPCM=false
        var finitePCM=false
        var frameLimitReached=false
        var complete=false
        var peak:Float=0
        var error:String?
        var elapsedSeconds=0.0
    }
    private struct Report:Encodable {
        let diagnosticOnly=true
        let productionAcceptance=false
        let humanVoiceAccuracyVerified=false
        let signal="Real input callbacks only; output is a silent AVAudioSourceNode. No manufactured input format, injected PCM or AudioUnit setters."
        let originalSessionEngineReleased:Bool
        let permission:String
        let permissionBefore:String
        let permissionAfter:String
        let permissionRequestGranted:Bool
        let cases:[CaseReport]
        let categoryRestoreError:String?
        let elapsedSeconds:Double
    }
    private final class Ring:@unchecked Sendable {
        let pointer:OpaquePointer
        let limit:UInt64
        init(rate:Double)throws {
            var timebase=mach_timebase_info_data_t();mach_timebase_info(&timebase)
            let ticks=1_000_000_000*Double(timebase.denom)/Double(timebase.numer)
            limit=UInt64(ceil(rate*0.25))
            guard let value=lg_input_create(rate,UInt32(ceil(rate)),0,ticks,limit)else{throw Failure(message:"Cannot allocate bounded diagnostic input transport")}
            pointer=value
        }
        deinit{lg_input_destroy(pointer)}
    }
    private enum Callbacks {
        nonisolated static func silentSource(format:AVAudioFormat)->AVAudioSourceNode {
            AVAudioSourceNode(format:format){ @Sendable _,_,_,buffers in
                let list=UnsafeMutableAudioBufferListPointer(buffers)
                for buffer in list{if let memory=buffer.mData{memset(memory,0,Int(buffer.mDataByteSize))}}
                return noErr
            }
        }
        nonisolated static func install(input:AVAudioInputNode,format:AVAudioFormat,ring:Ring){
            let rate=format.sampleRate,channels=format.channelCount,interleaved:Int32=format.isInterleaved ? 1:0
            input.installTap(onBus:0,bufferSize:1024,format:format){ @Sendable [ring] buffer,time in
                let host=time.isHostTimeValid ? time.hostTime:mach_absolute_time()
                guard buffer.format.sampleRate==rate,buffer.format.channelCount==channels,buffer.format.commonFormat == .pcmFormatFloat32,buffer.format.isInterleaved==(interleaved != 0),let samples=buffer.floatChannelData else{_ = lg_input_push(ring.pointer,nil,0,0,0,host);return}
                _ = lg_input_push(ring.pointer,UnsafeRawPointer(samples),channels,buffer.frameLength,interleaved,host)
            }
        }
    }
    @MainActor private final class Graph {
        let engine=AVAudioEngine()
        var input:AVAudioInputNode?
        var source:AVAudioSourceNode?
        var ring:Ring?
        var tapStage:String?
        private var scratch=[Float](repeating:0,count:4096)
        var drained:UInt64=0
        var finite=true
        var peak:Float=0
        func attachSilentOutput()throws {
            let format=engine.outputNode.outputFormat(forBus:0)
            guard InputLifecycleDiagnostics.usable(format),format.commonFormat == .pcmFormatFloat32 else{throw Failure(message:"Actual output hardware format is not usable Float32; no manufactured output format")}
            let source=Callbacks.silentSource(format:format)
            self.source=source;engine.attach(source)
            engine.connect(source,to:engine.mainMixerNode,format:format)
        }
        func installIfUsable(stage:String)throws {
            guard ring==nil,let input else{return}
            let hardware=input.inputFormat(forBus:0),output=input.outputFormat(forBus:0)
            guard InputLifecycleDiagnostics.usable(hardware),InputLifecycleDiagnostics.usable(output)else{return}
            guard output.commonFormat == .pcmFormatFloat32 else{throw Failure(message:"Actual input-node output is not Float32; tap not installed")}
            // A real I/O node can convert hardware packing before its output.
            // Use that observed output format, exactly as production capture;
            // never manufacture a hardware-matching replacement format.
            let ring=try Ring(rate:output.sampleRate)
            self.ring=ring;tapStage=stage
            Callbacks.install(input:input,format:output,ring:ring)
        }
        func drain(){
            guard let ring else{return}
            while true {
                let count=scratch.withUnsafeMutableBufferPointer{lg_input_pop(ring.pointer,$0.baseAddress,4096)}
                if count==0{return}
                drained+=UInt64(count)
                for index in 0..<Int(count){let value=scratch[index];if !value.isFinite{finite=false}else{peak=max(peak,abs(value))}}
            }
        }
        func stop(){
            if ring != nil{input?.removeTap(onBus:0)}
            engine.stop();drain()
            if let ring{lg_input_close(ring.pointer)}
            if let source{engine.disconnectNodeOutput(source);engine.detach(source);self.source=nil}
        }
    }
    private static func usable(_ format:AVAudioFormat)->Bool {
        format.sampleRate.isFinite && (8000...192000).contains(format.sampleRate) && format.channelCount>0 && format.channelCount<=32
    }
    private static func activate(duplex:Bool)throws {
        let session=AVAudioSession.sharedInstance()
        if duplex{try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothA2DP])}
        else{try session.setCategory(.playback,mode:.default,options:[])}
        try session.setActive(true)
    }
    private static func checkBudget(_ deadline:Date)throws {
        try Task.checkCancellation()
        guard Date()<deadline else{throw Failure(message:"Diagnostic time budget exhausted")}
    }
    static func run(_ session:Session)async throws->String {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--uitesting"),args.contains("--audio-input-lifecycle-controls")else{throw Failure(message:"Input lifecycle controls require the explicit diagnostic-only launch mode")}
        let began=Date(),deadline=began.addingTimeInterval(19)
        let before=AVAudioApplication.shared.recordPermission
        let permissionBefore=before == .granted ? "granted":before == .denied ? "denied":"undetermined"
        // run() is dispatched only by the explicit READY/Start button. A fresh
        // diagnostic launch must request permission here, independently of test
        // order, before enabling any local recording graph.
        let granted=await AVAudioApplication.requestRecordPermission()
        let after=AVAudioApplication.shared.recordPermission
        let permissionAfter=after == .granted ? "granted":after == .denied ? "denied":"undetermined"
        guard granted,after == .granted else {
            let blocked=Order.allCases.map{order in
                var value=CaseReport(id:order.id,order:order.explanation)
                value.error="No engine/input was created: microphone permission was not granted"
                return value
            }
            let report=Report(originalSessionEngineReleased:false,permission:permissionAfter,permissionBefore:permissionBefore,permissionAfter:permissionAfter,permissionRequestGranted:granted,cases:blocked,categoryRestoreError:nil,elapsedSeconds:Date().timeIntervalSince(began))
            return try encoded(report)
        }
        let audioSession=AVAudioSession.sharedInstance()
        let category=audioSession.category,mode=audioSession.mode,options=audioSession.categoryOptions
        // This reset is deliberately isolated from all production acceptance.
        // It prevents the original output unit from affecting fresh controls.
        session.audio.reset()
        let released=session.audio.captureEngine==nil
        var cases:[CaseReport]=[]
        for order in Order.allCases{cases.append(await runCase(order,deadline:deadline))}
        var restorationError:String?
        do{try audioSession.setCategory(category,mode:mode,options:options);try audioSession.setActive(true)}catch{restorationError=error.localizedDescription}
        let report=Report(originalSessionEngineReleased:released,permission:permissionAfter,permissionBefore:permissionBefore,permissionAfter:permissionAfter,permissionRequestGranted:granted,cases:cases,categoryRestoreError:restorationError,elapsedSeconds:Date().timeIntervalSince(began))
        return try encoded(report)
    }
    private static func encoded(_ report:Report)throws->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        return String(decoding:try encoder.encode(report),as:UTF8.self)
    }
    private static func runCase(_ order:Order,deadline:Date)async->CaseReport {
        let began=Date(),caseDeadline=min(deadline,began.addingTimeInterval(4.5))
        var report=CaseReport(id:order.id,order:order.explanation)
        do {
            try checkBudget(caseDeadline)
            try activate(duplex:order.beginsDuplex)
        }catch {
            report.error="Category activation before engine creation: "+error.localizedDescription
            report.elapsedSeconds=Date().timeIntervalSince(began)
            return report
        }
        let graph=Graph()
        defer{graph.stop()}
        do {
            try checkBudget(caseDeadline)
            if order.inputFirst{graph.input=graph.engine.inputNode}
            report.stages.append(Stage("before-output-graph",engine:graph.engine,input:graph.input))
            try graph.attachSilentOutput()
            if order == .duplexInputFirst{try graph.installIfUsable(stage:"before-initial-prepare")}
            report.stages.append(Stage("before-initial-prepare",engine:graph.engine,input:graph.input))
            graph.engine.prepare();try graph.engine.start()
            report.stages.append(Stage("after-initial-start",engine:graph.engine,input:graph.input))
            try checkBudget(caseDeadline)
            if !order.beginsDuplex {
                // Let output hardware actually run before changing its category.
                try await Task.sleep(for:.milliseconds(100))
                try activate(duplex:true)
                if graph.input==nil{graph.input=graph.engine.inputNode}
                report.stages.append(Stage("duplex-category-before-reprepare",engine:graph.engine,input:graph.input))
                graph.engine.stop()
                report.stages.append(Stage("same-local-graph-stopped",engine:graph.engine,input:graph.input))
                try graph.installIfUsable(stage:"before-duplex-reprepare")
                graph.engine.prepare();try graph.engine.start()
                report.stages.append(Stage("same-local-graph-reprepared",engine:graph.engine,input:graph.input))
            }else if !order.inputFirst {
                graph.input=graph.engine.inputNode
                report.stages.append(Stage("input-getter-after-duplex-start",engine:graph.engine,input:graph.input))
            }
            // Give the system one bounded scheduling turn; record both the
            // immediate start state above and its settled real hardware state.
            try await Task.sleep(for:.milliseconds(100));try checkBudget(caseDeadline)
            try graph.installIfUsable(stage:"after-final-start-settle")
            report.stages.append(Stage("before-actual-input-observation",engine:graph.engine,input:graph.input))
            if graph.ring != nil {
                try await observe(graph,deadline:min(caseDeadline,Date().addingTimeInterval(1)))
            }else{report.error="Actual input hardware format remains zero/invalid; no tap was installed"}
            graph.drain()
            report.stages.append(Stage("after-actual-input-observation",engine:graph.engine,input:graph.input))
        }catch {
            report.error=error.localizedDescription
            report.stages.append(Stage("error-before-cleanup",engine:graph.engine,input:graph.input))
        }
        graph.drain()
        if let ring=graph.ring {
            let state=lg_input_state(ring.pointer)
            report.tapInstalled=true;report.tapStage=graph.tapStage
            report.actualFrames=state.frames;report.drainedFrames=graph.drained
            report.firstHostTime=state.firstHostTime;report.lastHostTime=state.lastHostTime
            report.overflow=state.overflow != 0;report.invalidPCM=state.invalidInput != 0
            report.finitePCM=state.frames>0 && graph.finite && state.invalidInput==0
            report.frameLimitReached=state.frames==ring.limit && state.finished != 0
            report.complete=report.frameLimitReached && report.finitePCM && !report.overflow && graph.drained==state.frames
            report.peak=graph.peak
            if !report.complete && report.error==nil{report.error="Real input did not complete the finite bounded capture"}
        }
        report.elapsedSeconds=Date().timeIntervalSince(began)
        return report
    }
    private static func observe(_ graph:Graph,deadline:Date)async throws {
        while Date()<deadline {
            try Task.checkCancellation();graph.drain()
            if let ring=graph.ring,lg_input_state(ring.pointer).finished != 0{return}
            try await Task.sleep(for:.milliseconds(20))
        }
        graph.drain()
    }
}
