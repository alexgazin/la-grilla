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
    static func snapshots(_ session:Session)async throws->String {
        let audio=session.audio
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
        return "Actual engine: boundary mix/FX, deferred keyed preview, preset cache invalidation, reordered MIDI roles, 80 concurrent submissions, bounded routing cache, phase and kernel identity"
    }
    static func microphone(_ session:Session)async throws->String {
        let audio=session.audio
        _ = try await fixture(audio)
        defer{audio.stop()}
        guard await AVAudioApplication.requestRecordPermission()else{throw Failure(message:"Native microphone permission was denied")}
        let kernel=try pointer(audio)
        guard let engine=audio.captureEngine else{throw Failure(message:"No live engine")}
        let category=AVAudioSession.sharedInstance().category
        let lease=MicrophoneLease(),stats=InputStats()
        guard let owner=session.beginMicrophone(stop:{lease.stop()})else{throw Failure(message:"Microphone lease was rejected")}
        defer{lease.stop();session.endMicrophone(owner)}
        audio.refreshClock();let before=audio.clock
        lease.microphone=try LiveMicrophone(audio:audio,delay:0.1,duration:0.3,receiver:{_ in
            LiveInputReceiver(receive:{try stats.append($0)},finish:{stats.finish()})
        },onFailure:{lease.failure=$0})
        try require(session.ownsMicrophone(owner),"Session lost the microphone lease")
        // A category/configuration event may stop AVAudioEngine. prepare() must
        // restart this graph without restoring playback-only category mid-tap.
        engine.pause();try audio.prepare()
        try require(AVAudioSession.sharedInstance().category == .playAndRecord,"prepare() removed the microphone category")
        try await wait(audio){lease.microphone?.complete==true || lease.failure != nil}
        if let failure=lease.failure{throw Failure(message:failure)}
        try lease.microphone?.stop();lease.microphone=nil
        try require(stats.frames>0 && stats.finished,"No actual finite microphone PCM reached the consumer")
        session.endMicrophone(owner)
        try await wait(audio){audio.clock>before && audio.playing && audio.isPrepared}
        try require(AVAudioSession.sharedInstance().category==category,"Microphone category was not restored")
        try require(try pointer(audio)==kernel && audio.captureEngine===engine,"Microphone capture replaced the kernel or engine")
        let after=audio.clock
        try await wait(audio){audio.clock>after}
        return "Actual tap PCM frames: \(stats.frames); Session lease, permission, finite capture, paused-graph prepare, category restoration and continuing engine/kernel clock"
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
    var body:some View {
        VStack(spacing:12){
            Text(verbatim:result).font(.headline).accessibilityIdentifier("audio.runtime.result")
            Text(verbatim:details).font(.caption).accessibilityIdentifier("audio.runtime.details")
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.ink).foregroundStyle(Color.studioText)
            .task(id:session.ready){
                guard session.ready,!started else{return};started=true;result="RUNNING"
                do {
                    if ProcessInfo.processInfo.arguments.contains("--audio-runtime-microphone"){details=try await AudioRuntimeQA.microphone(session)}
                    else{details=try await AudioRuntimeQA.snapshots(session)}
                    result="PASS"
                }catch{details=error.localizedDescription;result="FAIL"}
            }
    }
}
