import AVFoundation
import AudioDSP
import MusicDomain
import SwiftUI

/// Explicit native acceptance fixture. It uses the app's actual engine and C
/// renderer; no manual render call races the AVAudioSourceNode callback.
@MainActor enum AudioRuntimeQA {
    static var enabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        return args.contains("--uitesting") && args.contains("--audio-runtime-qa")
    }
    private struct Failure:LocalizedError {
        let message:String
        var errorDescription:String?{message}
    }
    private static func require(_ condition:Bool,_ message:String)throws {
        guard condition else{throw Failure(message:message)}
    }
    private static func wait(_ audio:AudioController,timeout:Double=5,_ condition:()->Bool)async throws {
        let deadline=Date().addingTimeInterval(timeout)
        while Date()<deadline {
            audio.poll()
            if condition(){return}
            try await Task.sleep(for:.milliseconds(20))
        }
        throw Failure(message:"Timed out waiting for an actual audio callback")
    }
    private static func fixture(_ audio:AudioController)async throws->Project {
        try audio.prepare()
        var project=Project.demo();project.bpm=240;project.revision=1000
        try project.addMelody();try project.validate()
        audio.submit(project,loop:true,range:0..<project.length);audio.seek(0);audio.play()
        try await wait(audio){audio.appliedRevision==project.revision && audio.playing && audio.clock>0}
        return project
    }
    private static func pointer(_ audio:AudioController)throws->OpaquePointer {
        guard let pointer=audio.withKernel({$0})else{throw Failure(message:"No live kernel")}
        return pointer
    }
    /// Observe ordinary output startup without fetching inputNode, installing
    /// an input tap or invoking any microphone permission request API.
    static func outputPrivacy(_ session:Session)async throws->String {
        let audio=session.audio
        let before=AVAudioApplication.shared.recordPermission
        _ = try await fixture(audio)
        defer{audio.stop()}
        let clockBefore=audio.clock
        var peak:Float=0
        try await wait(audio){
            peak=max(peak,audio.meters.max() ?? 0)
            return audio.playing && audio.clock>clockBefore && Double(audio.clock-clockBefore)>=audio.sampleRate*0.25 && peak>0.0001
        }
        let after=AVAudioApplication.shared.recordPermission
        func permissionName(_ value:AVAudioApplication.recordPermission)->String {
            value == .undetermined ? "undetermined":value == .granted ? "granted":"denied"
        }
        struct Report:Encodable {
            let outcome:String
            let diagnosticOnly=true
            let productionAcceptance=false
            let permissionBefore:String
            let permissionAfter:String
            let outputPlaying:Bool
            let outputEngineRunning:Bool
            let outputClockFramesAdvanced:UInt64
            let observedOutputPeak:Float
            let softwareOutputPrivacyVerified:Bool
            let physicalMicrophoneIndicatorVerified=false
            let observation="Permission state and output callbacks are software observations. System-alert absence is checked by XCTest; physical microphone-indicator behavior requires device verification."
        }
        let verified=before == .undetermined && after == .undetermined && audio.playing && audio.captureEngine?.isRunning==true
        let report=Report(outcome:verified ? "PASS":"FAIL",permissionBefore:permissionName(before),permissionAfter:permissionName(after),outputPlaying:audio.playing,outputEngineRunning:audio.captureEngine?.isRunning==true,outputClockFramesAdvanced:audio.clock-clockBefore,observedOutputPeak:peak,softwareOutputPrivacyVerified:verified)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        let details=String(decoding:try encoder.encode(report),as:UTF8.self)
        try require(verified,details)
        return details
    }
    static func snapshots(_ session:Session)async throws->String {
        let audio=session.audio
        let acceptanceDeadline=Date().addingTimeInterval(30)
        var project=try await fixture(audio)
        defer{audio.stop()}
        let kernel=try pointer(audio)
        guard let engine=audio.captureEngine else{throw Failure(message:"No live engine")}
        // Stage away from a boundary so the test can inspect the pending bus.
        audio.seek(240);try await Task.sleep(for:.milliseconds(60));audio.refreshClock()
        let startClock=audio.clock,startTick=audio.tick
        try project.addMelody();project.revision+=1
        let added=project.tracks.count-1
        project.tracks[added].presetVersion=1
        audio.submit(project,loop:true,range:0..<project.length)
        var controls=project;controls.tracks[added].gain = -9;controls.tracks[added].pan = -0.6
        controls.masterFX=MasterFX(filter:-0.2,delayWet:0.125)
        try require(audio.mix(controls),"Pending-generation mixer transaction was rejected")
        audio.previewNote(74,track:added)
        try require(audio.pendingSnapshot,"New track was not staged for a musical boundary")
        try require(audio.withKernel{lg_gain_target($0,Int32(added))==0}==true,"New track gain leaked into the old layout")
        try await wait(audio){audio.appliedRevision==project.revision && !audio.pendingSnapshot}
        try require(audio.withKernel{abs(lg_gain_target($0,Int32(added))-powf(10,-9/20))<0.0001 && abs(lg_pan_target($0,Int32(added))+0.6)<0.0001}==true,"Pending generation lost its latest gain/pan")
        try require(audio.withKernel{lg_filter_target($0) == -0.2 && lg_delay_target($0)==0.125}==true,"Pending generation lost its latest FX")
        try await wait(audio,timeout:1){audio.meters.indices.contains(added) && audio.meters[added]>0.001}
        audio.refreshClock()
        let expected=Double(audio.clock-startClock)*240*Double(ppq)/(60*audio.sampleRate)
        let actual=(audio.tick-startTick+Double(project.length)).truncatingRemainder(dividingBy:Double(project.length))
        try require(abs(actual-expected)<128,"Live structural editing changed musical phase")
        try require(try pointer(audio)==kernel && audio.captureEngine===engine && audio.playing,"Live editing replaced or stopped the engine")
        // Empty melody clips compile to the same note array. Preset changes and
        // channel/order changes still have to publish a new musical generation.
        var prior=audio.withKernel{lg_revision($0)} ?? -1
        project.tracks[added].presetVersion=2;project.revision+=1
        audio.submit(project,loop:true,range:0..<project.length)
        try await wait(audio){audio.appliedRevision==project.revision}
        try require((audio.withKernel{lg_revision($0)} ?? -1)>prior,"Preset-only change reused a stale snapshot")
        prior=audio.withKernel{lg_revision($0)} ?? -1
        project.tracks.swapAt(3,4);project.revision+=1
        audio.submit(project,loop:true,range:0..<project.length)
        try await wait(audio){audio.appliedRevision==project.revision}
        try require((audio.withKernel{lg_revision($0)} ?? -1)>prior && audio.activeMIDIRouting?.tracks.map(\.id)==project.tracks.map(\.id),"Reordered melody routing was not adopted")
        // More submissions than the old cache window, with the real callback
        // adopting concurrently. Every potentially active generation stays known.
        for index in 0..<80 {
            project.tracks[3].presetVersion=index%2+1;project.revision+=1
            audio.submit(project,loop:true,range:0..<project.length)
            try require(audio.retainedRoutingCount<=3 && audio.activeMIDIRouting != nil,"Routing metadata was lost or grew beyond the three kernel slots")
            if index%8==0{await Task.yield()}
        }
        try await wait(audio){audio.appliedRevision==project.revision}
        var foreign=project;foreign.id=UUID()
        try require(!audio.mix(foreign),"Mixer accepted a different project's identical track layout")
        try require(try pointer(audio)==kernel && audio.captureEngine===engine && audio.playing,"Snapshot burst replaced or stopped the engine")
        // Exercise the actual Session publication paths, including the path a
        // controller CC uses. The fixture above submitted directly to audio;
        // now make that same source the editable Session project.
        session.project=project;session.history=History();session.mixerGesture=false
        session.loop=true;session.loopBars=4;session.metronome=false;session.sync()
        @MainActor func previewWait(_ stage:String,_ condition:()->Bool)async throws {
            let remaining=acceptanceDeadline.timeIntervalSinceNow
            try require(remaining>0,"Preview acceptance deadline exceeded: "+stage)
            do{try await wait(audio,timeout:min(3,remaining),condition)}
            catch{throw Failure(message:"Preview acceptance ("+stage+"): "+error.localizedDescription)}
        }
        try await previewWait("Session source adoption"){audio.playing && !audio.pendingSnapshot}
        let baseline=session.project,section=baseline.sections[0]
        let running=try HarmonyLab.propose(baseline,sectionID:section.id,options:HarmonyOptions(style:.expressive,voicing:.compact))
        try require(Compiler.notes(running.candidate) != Compiler.notes(baseline),"Running preview fixture did not change audible harmony")
        session.previewAssistant(running.candidate,wholeSong:true,sectionID:section.id)
        try await previewWait("running audition"){session.harmonyPreview && audio.playing && !audio.pendingSnapshot}
        audio.refreshClock();let previewClock=audio.clock,previewTick=audio.tick
        let gain=MIDIMapping(sourceID:0,channel:0,controller:20,target:.trackGain,trackID:baseline.tracks[0].id)
        session.applyMIDI(gain,value:-12)
        try require(!session.harmonyPreview && audio.playing,"A controller mixer edit left the running audition marked active or stopped playback")
        try require(session.project.patterns==baseline.patterns,"A controller mixer edit committed audition harmony")
        try await previewWait("controller edit adoption"){
            audio.playing && !audio.pendingSnapshot && audio.appliedRevision==session.project.revision && audio.withKernel{abs(lg_gain_target($0,0)-powf(10,-12/20))<0.0001}==true
        }
        audio.refreshClock()
        try require(audio.clock>previewClock && audio.captureEngine===engine && (try pointer(audio))==kernel,"Controller preview invalidation replaced or reset the actual engine/kernel/clock")
        let previewLength=Double(baseline.length)
        let previewExpected=(Double(audio.clock-previewClock)*baseline.bpm*Double(ppq)/(60*audio.sampleRate)).truncatingRemainder(dividingBy:previewLength)
        let previewActual=(audio.tick-previewTick+previewLength).truncatingRemainder(dividingBy:previewLength)
        let previewDelta=abs(previewActual-previewExpected),previewPhase=min(previewDelta,previewLength-previewDelta)
        try require(previewPhase<128,"Ending a running preview after a controller edit changed musical phase")

        audio.stop();try await previewWait("idle setup stop"){!audio.playing}
        let idlePosition=960
        audio.seek(idlePosition)
        try await previewWait("idle setup position"){!audio.playing && abs(audio.tick-Double(idlePosition))<1}
        let idleSource=session.project
        let idle=try HarmonyLab.propose(idleSource,sectionID:section.id,options:HarmonyOptions(style:.gentle))
        try require(Compiler.notes(idle.candidate) != Compiler.notes(idleSource),"Idle preview fixture did not change audible harmony")
        session.previewHarmony(idle.candidate,section:section)
        try await previewWait("idle-started audition"){session.harmonyPreview && audio.playing && !audio.pendingSnapshot}
        session.edit{$0.bpm=999}
        let rejectedKeptPreview=session.project==idleSource && session.harmonyPreview && audio.playing && session.message != nil
        // Consume the expected validation failure in this fixture's MainActor
        // turn before SwiftUI can present an alert over its QA result.
        session.message=nil
        try require(rejectedKeptPreview,"A rejected edit invalidated a still-valid audition or changed its source")
        session.edit{$0.name="Native preview source"}
        try require(!session.harmonyPreview && !audio.playing,"An accepted edit left an idle-started audition playing")
        try await previewWait("stopped source restoration"){
            !audio.playing && !audio.pendingSnapshot && audio.appliedRevision==session.project.revision && abs(audio.tick-Double(idlePosition))<1
        }
        try require(session.project.patterns==idleSource.patterns && session.project.tracks==idleSource.tracks,"Ending the idle audition changed source music/mix")
        try require(audio.captureEngine===engine && (try pointer(audio))==kernel,"Idle preview invalidation replaced the engine or kernel")

        // Open's explicit seek(0) must win over the previous idle audition's
        // saved position. Clearing only inside the later sync would seek 960.
        let beforeOpen=session.project
        let opening=try HarmonyLab.propose(beforeOpen,sectionID:section.id,options:HarmonyOptions(style:.gentle))
        session.previewHarmony(opening.candidate,section:section)
        try await previewWait("audition before project open"){session.harmonyPreview && audio.playing && !audio.pendingSnapshot}
        var opened=Project.demo();opened.name="Native opened source";opened.bpm=240
        await session.open(opened,force:true)
        try require(session.project.id==opened.id && !session.harmonyPreview && !audio.playing,"Project open retained an old audition or did not switch the source")
        try await previewWait("opened source at zero"){!audio.playing && !audio.pendingSnapshot && abs(audio.tick)<1}
        try require(audio.captureEngine===engine && (try pointer(audio))==kernel && audio.clock>previewClock,"Project open unnecessarily replaced the engine/kernel or reset its clock")
        return "Actual engine: boundary mix/FX, deferred keyed preview, preset cache invalidation, reordered MIDI roles, 80 concurrent submissions, bounded routing cache; actual Session controller-edit preview invalidation (phase difference \(previewPhase) ticks), rejected edit preserves audition, accepted idle edit restores stopped position \(idlePosition), project open clears audition and restores zero; retained engine/kernel/clock"
    }
    struct InputUnavailable:Error {let details:String}
    struct OutputHostTimingReport:Encodable {
        let epoch:UInt64
        let callbacks:UInt64
        let comparedCallbacks:UInt64
        let maxExcessNanoseconds:UInt64
        let maxIntervalNanoseconds:UInt64
        let baselineBufferNanoseconds:UInt64
        let baselineFrames:UInt32
        let inheritedAnchor:Bool
        let nonIncreasingTimestamps:UInt64
        let clockRateChanges:UInt64
        init(_ value:LGOutputTiming){
            epoch=value.epoch;callbacks=value.callbacks;comparedCallbacks=value.comparedCallbacks
            maxExcessNanoseconds=value.maxExcessNanoseconds;maxIntervalNanoseconds=value.maxIntervalNanoseconds
            baselineBufferNanoseconds=value.baselineBufferNanoseconds;baselineFrames=value.baselineFrames;inheritedAnchor=value.inheritedAnchor != 0
            nonIncreasingTimestamps=value.nonIncreasingTimestamps;clockRateChanges=value.clockRateChanges
        }
    }
    private struct MicrophoneReport:Encodable {
        let outcome:String
        let detail:String
        let routes:[LiveInputRouteSnapshot]
        let frames:Int
        let outputEngineRetained:Bool
        let outputKernelRetained:Bool
        let outputClockAdvanced:Bool
        let outputPlaying:Bool
        let categoryRestored:Bool
        let phaseDifferenceTicks:Double
        let outputHostTimingBaseline:OutputHostTimingReport
        let outputHostTiming:OutputHostTimingReport
        // Host callback timestamps measure scheduling discontinuities, not the
        // physical speaker waveform. That separate C8 acceptance remains open.
        let physicalDropoutAbsenceVerified=false
        func json()throws->String{let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return String(decoding:try encoder.encode(self),as:UTF8.self)}
    }
    static func microphone(_ session:Session)async throws->String {
        let audio=session.audio
        let project=try await fixture(audio)
        defer{audio.stop()}
        guard await AVAudioApplication.requestRecordPermission()else{throw Failure(message:"Native microphone permission was denied")}
        let kernel=try pointer(audio)
        guard let engine=audio.captureEngine else{throw Failure(message:"No live engine")}
        let category=AVAudioSession.sharedInstance().category
        let timingEpoch=lg_output_timing_begin(kernel)
        try require(timingEpoch != 0,"Output timing measurement could not start")
        var timingBaseline=LGOutputTiming()
        // Arm and observe the measurement BEFORE category or hardware changes.
        // Its retained anchor then includes the first callback after a restart.
        try await wait(audio){
            var value=LGOutputTiming()
            guard lg_output_timing_read(kernel,&value) != 0,value.epoch==timingEpoch,value.comparedCallbacks>=8 else{return false}
            timingBaseline=value;return true
        }
        let lease=MicrophoneLease(),stats=InputStats()
        guard let owner=session.beginMicrophone(stop:{lease.stop()})else{throw Failure(message:"Microphone lease was rejected")}
        defer{lease.stop();session.endMicrophone(owner)}
        audio.refreshClock();let before=audio.clock,beforeTick=audio.tick
        @MainActor func outputReport(outcome:String,detail:String,routes:[LiveInputRouteSnapshot])async throws->String {
            session.endMicrophone(owner)
            try await wait(audio){audio.clock>before && audio.playing && audio.isPrepared}
            let categoryRestored=AVAudioSession.sharedInstance().category==category
            let kernelRetained=try pointer(audio)==kernel,engineRetained=audio.captureEngine===engine
            try require(categoryRestored,"Microphone category was not restored")
            try require(kernelRetained && engineRetained,"Microphone capture replaced the kernel or engine")
            let length=Double(project.length)
            let expected=(Double(audio.clock-before)*project.bpm*Double(ppq)/(60*audio.sampleRate)).truncatingRemainder(dividingBy:length)
            let actual=(audio.tick-beforeTick+length).truncatingRemainder(dividingBy:length)
            let difference=abs(actual-expected),phaseDifference=min(difference,length-difference)
            try require(phaseDifference<128,"Microphone category transition reset the musical position")
            let after=audio.clock
            var timing=LGOutputTiming()
            try await wait(audio){
                var value=LGOutputTiming()
                guard audio.clock>after,lg_output_timing_read(kernel,&value) != 0,value.epoch==timingEpoch,value.callbacks>timingBaseline.callbacks else{return false}
                timing=value;return true
            }
            return try MicrophoneReport(outcome:outcome,detail:detail,routes:routes,frames:stats.frames,outputEngineRetained:engineRetained,outputKernelRetained:kernelRetained,outputClockAdvanced:audio.clock>before,outputPlaying:audio.playing,categoryRestored:categoryRestored,phaseDifferenceTicks:phaseDifference,outputHostTimingBaseline:OutputHostTimingReport(timingBaseline),outputHostTiming:OutputHostTimingReport(timing)).json()
        }
        do {
            lease.microphone=try LiveMicrophone(audio:audio,delay:0.1,duration:0.3,receiver:{_ in
                LiveInputReceiver(receive:{try stats.append($0)},finish:{stats.finish()})
            },onFailure:{lease.failure=$0})
        }catch let failure as LiveInputSetupFailure {
            // A zero node format is not an infrastructure skip. Only the actual
            // activated session declaring no input plus empty current/available
            // input routes can be unavailable, after output continuity passed.
            let report=try await outputReport(outcome:failure.hardwareAbsent ? "UNAVAILABLE":"FAIL",detail:failure.message,routes:failure.routes)
            if failure.hardwareAbsent{throw InputUnavailable(details:report)}
            throw Failure(message:report)
        }
        try require(session.ownsMicrophone(owner),"Session lost the microphone lease")
        // A category/configuration event may stop AVAudioEngine. prepare() must
        // restart this graph without restoring playback-only category mid-tap.
        engine.pause();try audio.prepare()
        try require(AVAudioSession.sharedInstance().category == .playAndRecord,"prepare() removed the microphone category")
        try await wait(audio){lease.microphone?.complete==true || lease.failure != nil}
        if let failure=lease.failure{throw Failure(message:failure)}
        let routes=lease.microphone?.routeDiagnostics ?? []
        try lease.microphone?.stop();lease.microphone=nil
        try require(stats.frames>0 && stats.finished,"No actual finite microphone PCM reached the consumer")
        return try await outputReport(outcome:"PASS",detail:"Actual finite PCM, Session lease, permission, restored category and musical phase; host callback gaps measured separately from the retained kernel clock",routes:routes)
    }
    static func midiPolicy(_ session:Session)async throws->String {
        let audio=session.audio,midi=session.midi
        try audio.prepare()
        defer{midi.suspend();audio.stop()}
        guard let source=midi.createFixture(),let output=midi.fixtureOutputID else{throw Failure(message:"Virtual MIDI endpoints could not start")}
        session.edit{p in
            p.bpm=40
            var settings=MIDISettings();settings.enabled=true;settings.inputIDs=[source];settings.outputID=output;settings.trackID=p.tracks[0].id;p.midi=settings
        }
        audio.play()
        try await wait(audio){audio.playing && midi.isConnected(source) && lg_midi_output_active_epoch(audio.midiHub.pointer) != 0}
        midi.sendFixture()
        try await wait(audio){midi.fixtureReceivedNotes>0 && midi.lastMessage.contains("74")}
        let kernel=try pointer(audio)
        // This seek belongs only to fixture setup. The following two Session
        // edits run in one MainActor turn, safely away from the six-second bar.
        audio.seek(240);try await wait(audio){audio.tick>240 && audio.tick<960}
        let clock=audio.clock
        session.edit{try $0.addMelody()}
        try require(audio.pendingSnapshot,"Structural edit did not remain pending")
        session.edit{p in p.midi?.enabled=false;p.midi?.outputID=nil}
        try require(!midi.isConnected(source),"Input Off waited for the pending structural bar")
        try require(lg_midi_output_active_epoch(audio.midiHub.pointer)==0,"Output None waited for the pending structural bar")
        try require(audio.pendingSnapshot && audio.playing,"MIDI Off adopted or stopped the pending song")
        try await wait(audio,timeout:8){!audio.pendingSnapshot}
        try require(!midi.isConnected(source) && lg_midi_output_active_epoch(audio.midiHub.pointer)==0,"Old snapshot settings reconnected a disabled MIDI endpoint")
        let sameKernel=try pointer(audio)==kernel
        try require(audio.clock>clock && audio.playing && sameKernel,"MIDI policy update replaced or stopped the live engine")
        return "Actual Session + virtual CoreMIDI: 40 BPM pending layout, immediate input Off/output None, no reconnect after adoption, continuing kernel clock"
    }
    @MainActor private final class MicrophoneLease {
        var microphone:LiveMicrophone?
        var failure:String?
        func stop(){try? microphone?.stop();microphone=nil}
    }
    private final class InputStats:@unchecked Sendable {
        private let lock=NSLock()
        private var count=0,done=false
        var frames:Int{lock.withLock{count}}
        var finished:Bool{lock.withLock{done}}
        func append(_ buffer:AVAudioPCMBuffer)throws {
            guard let samples=buffer.floatChannelData?[0],buffer.format.channelCount==1,buffer.frameLength>0 else{throw Failure(message:"Invalid native input buffer")}
            for index in 0..<Int(buffer.frameLength){guard samples[index].isFinite else{throw Failure(message:"Non-finite native input PCM")}}
            lock.withLock{count+=Int(buffer.frameLength)}
        }
        func finish(){lock.withLock{done=true}}
    }
}

struct AudioRuntimeQAView:View {
    @Bindable var session:Session
    @State private var result="WAITING"
    @State private var details=""
    @State private var started=false
    private var inputDiagnosticCase:Bool{ProcessInfo.processInfo.arguments.contains("--audio-input-lifecycle-controls")}
    private var voiceCaptureCase:Bool{ProcessInfo.processInfo.arguments.contains("--audio-runtime-voice-capture")}
    private var microphoneCase:Bool {
        let args=ProcessInfo.processInfo.arguments
        return (args.contains("--audio-runtime-microphone") || voiceCaptureCase || inputDiagnosticCase) && !args.contains("--audio-runtime-midi-policy")
    }
    var body:some View {
        VStack(spacing:12){
            Text(verbatim:result).font(.headline).accessibilityIdentifier("audio.runtime.result")
            Text(verbatim:details).font(.caption).accessibilityIdentifier("audio.runtime.details")
            if microphoneCase,result=="READY" {
                Button{Task{await run()}}label:{Text(verbatim:inputDiagnosticCase ? "Start input diagnostics":"Start microphone check").frame(minHeight:44)}
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("audio.runtime.start")
            }
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.ink).foregroundStyle(Color.studioText)
            .task(id:session.ready){
                guard session.ready,!started else{return}
                // Requesting permission during app launch can prevent XCTest
                // from attaching its automation session. Wait for its explicit
                // button tap before starting the real microphone acceptance.
                if microphoneCase{result="READY"}else{await run()}
            }
    }
    @MainActor private func run()async {
        guard !started else{return};started=true;result="RUNNING"
        do {
            if inputDiagnosticCase {
                details=try await InputLifecycleDiagnostics.run(session)
                result="DIAGNOSTIC"
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--audio-runtime-output-privacy"){details=try await AudioRuntimeQA.outputPrivacy(session);result="PASS";return}
            if ProcessInfo.processInfo.arguments.contains("--audio-runtime-midi-policy"){details=try await AudioRuntimeQA.midiPolicy(session)}
            else if ProcessInfo.processInfo.arguments.contains("--audio-runtime-drum-clip"){details=try await DrumClipRuntimeQA.run(session)}
            else if voiceCaptureCase{details=try await VoiceCaptureRuntimeQA.run(session)}
            else if microphoneCase{details=try await AudioRuntimeQA.microphone(session)}
            else{details=try await AudioRuntimeQA.snapshots(session)}
            result="PASS"
        }catch let unavailable as AudioRuntimeQA.InputUnavailable{details=unavailable.details;result="UNAVAILABLE"}
        catch{details=error.localizedDescription;result="FAIL"}
    }
}
