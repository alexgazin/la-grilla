import AVFoundation
import AudioDSP
import MusicDomain
import Observation
import Darwin

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
}
final class KernelHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(rate: Double) { pointer = lg_create(rate)! }
    deinit { lg_destroy(pointer) }
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
            guard output.count==2,let left=output[0].mData,let right=output[1].mData else {return noErr}
            let host=stamp.pointee.mHostTime==0 ? mach_absolute_time():stamp.pointee.mHostTime
            lg_render_midi(kernel.pointer,hub.pointer,host,ticks,left.assumingMemoryBound(to:Float.self),right.assumingMemoryBound(to:Float.self),Int32(count))
            return noErr
        }
    }
}
@MainActor @Observable final class AudioController {
    let midiHub=MIDIHubHandle()
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var handle: KernelHandle?
    var tick: Double = 0; var playing = false; var appliedRevision = -1
    var meters: [Float] = Array(repeating:0,count:masterBus+1); var sampleRate: Double = 48000
    var countRemaining = 0; var error: String?
    var overflows = 0
    @ObservationIgnored var onPoll:(()->Void)?
    private var timer: Timer?
    @ObservationIgnored private var configurationObserver:NSObjectProtocol?
    private var generation = 0
    private var submittedNotes:[CompiledNote]?;private var submittedBPM=0.0;private var submittedRange:Range<Int>?;private var submittedLoop=false;private var submittedProject:UUID?
    private var performanceEpoch=0
    private var performanceBuffer=[LGPerformanceEvent](repeating:LGPerformanceEvent(),count:512)
    private var sentRevisions: [Int:Int] = [:]
    private var submittedLayout:[AudioTrackLayout]=[]
    private var routing:[Int:AudioMIDIRouting]=[:]
    private var pendingPreviews:[(UUID,Int)]=[]
    var isPrepared: Bool { engine?.isRunning == true }
    var captureEngine:AVAudioEngine? {engine}
    var pendingSnapshot:Bool {guard let k=handle?.pointer else{return false};return generation != Int(lg_revision(k))}
    var activeMIDIRouting:AudioMIDIRouting? {guard let k=handle?.pointer else{return nil};return routing[Int(lg_revision(k))]}
    /// Bounded metadata retained alongside the kernel's three musical slots.
    var retainedRoutingCount:Int {routing.count}
    var clock: UInt64 = 0
    func prepare() throws {
        if engine?.isRunning == true { return }
        // A microphone category/configuration change may stop AVAudioEngine.
        // Restart the same graph: replacing the kernel would lose its clock,
        // pending musical transaction, held MIDI and ongoing performance.
        if let engine,handle != nil {
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare();try engine.start();error=nil;return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(48000); try session.setPreferredIOBufferDuration(0.0053)
        try session.setActive(true); sampleRate = session.sampleRate
        guard sampleRate.isFinite, (8000...192000).contains(sampleRate) else {
            throw NSError(domain:"LaGrilla.Audio",code:1,userInfo:[NSLocalizedDescriptionKey:"No audio output is available. Connect an audio device and retry."])
        }
        let h = KernelHandle(rate: sampleRate); let e = AVAudioEngine()
        // Preserve musical position when rebuilding after an interruption or route change.
        lg_seek(h.pointer,Int32(max(0,tick).rounded(.down)))
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AudioRender.makeSource(format:format, kernel:h,hub:midiHub)
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: format); e.prepare(); try e.start()
        handle = h; source = node; engine = e;submittedNotes=nil
        configurationObserver=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:e,queue:.main){[weak self] _ in
            Task{@MainActor in self?.resumeConfiguredGraph()}
        }
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        error = nil
    }
    private func resumeConfiguredGraph(){
        guard let engine,handle != nil,!engine.isRunning else{return}
        do{engine.prepare();try engine.start();error=nil}
        catch{self.error=error.localizedDescription}
    }
    func poll() {
        guard let k = handle?.pointer else { return }
        clock = lg_clock(k); tick = lg_tick(k); playing = lg_playing(k) != 0; appliedRevision = sentRevisions[Int(lg_revision(k))] ?? -1; countRemaining = Int(lg_countremaining(k)); overflows = Int(lg_overflows(k))
        meters = (0...masterBus).map {lg_meter(k,Int32($0))}
        flushPreviews();onPoll?()
    }
    /// Read the audio clock at the touch, rather than using the last 30 Hz UI poll.
    func refreshClock(){guard let k=handle?.pointer else{return};clock=lg_clock(k);tick=lg_tick(k);playing=lg_playing(k) != 0;countRemaining=Int(lg_countremaining(k))}
    func submit(_ p: Project, loop: Bool, range: Range<Int>) {
        guard let k = handle?.pointer else { return }
        let compiled=Compiler.notes(p),layout=trackLayout(p)
        if compiled==submittedNotes,p.bpm==submittedBPM,range==submittedRange,loop==submittedLoop,p.id==submittedProject,layout==submittedLayout {
            sentRevisions[generation]=p.revision;routing[generation]=midiRouting(p)
            if Int(lg_revision(k))==generation{appliedRevision=p.revision};_ = mix(p);return
        }
        let next=generation+1
        let notes = compiled.map { LGNote(tick: Int32($0.tick), duration: Int32($0.duration), pitch: Int32($0.pitch), velocity: Int32($0.velocity), track: Int32($0.track), pad: Int32($0.pad),instrument:Int32($0.instrument)) }
        let mixes=trackMix(p)
        let tracks=layout.enumerated().map{i,t in LGProjectTrack(mix:mixes[i],presetVersion:t.preset,instrument:t.instrument,midiChannel:t.channel,identity:t.identity)}
        let fx=p.masterFX ?? MasterFX()
        let ok=notes.withUnsafeBufferPointer{n in tracks.withUnsafeBufferPointer{t in
            lg_submit_project(k,n.baseAddress,Int32(n.count),p.bpm,Int32(range.lowerBound),Int32(range.upperBound),loop ? 1:0,Int32(next),layoutToken(layout),t.baseAddress,Int32(t.count),Float(p.master),Float(fx.filter),Float(fx.delayWet))
        }}
        guard ok != 0 else{error="Audio update could not be queued. Stop and retry.";return}
        generation=next;sentRevisions[next]=p.revision;routing[next]=midiRouting(p)
        pruneRouting(k)
        submittedNotes=compiled;submittedBPM=p.bpm;submittedRange=range;submittedLoop=loop;submittedProject=p.id;submittedLayout=layout
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
            return AudioTrackLayout(identity:MIDIController.trackIdentity(track.id),instrument:Int32(track.role.instrument),preset:Int32(track.presetVersion),channel:channel)
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
        let accepted=tracks.withUnsafeBufferPointer{lg_mix_snapshot_for_revision(k,$0.baseAddress,Int32($0.count),Float(p.master),Float(fx.filter),Float(fx.delayWet),Int32(generation))} != 0
        if !accepted{error="Audio update could not be queued. Stop and retry."};return accepted
    }
    func play(countInBPM: Double? = nil) {
        guard let k = handle?.pointer else { return }
        if let bpm = countInBPM {lg_countin(k,Int32((sampleRate*240/bpm).rounded()))}
        lg_play(k,1); playing = true
    }
    func audition(_ p:Project,range:Range<Int>,tick:Int?=nil,loop:Bool=true){
        refreshClock();let continuing=playing
        submit(p,loop:loop,range:range)
        if !continuing{seek(tick ?? range.lowerBound);if let k=handle?.pointer{lg_restart(k)};playing=true}
    }
    func stop() {if let k = handle?.pointer {lg_play(k,0)}; playing = false}
    func seek(_ tick: Int) {if let k = handle?.pointer {lg_seek(k,Int32(tick))}; self.tick = Double(tick)}
    func pad(_ pad: Int, velocity: Int = 100) {if let k = handle?.pointer { _ = lg_pad(k,Int32(pad),Int32(velocity)) }}
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
        let limit=UInt64((Double(64*barTicks)/Double(ppq)*60/p.bpm*sampleRate).rounded())
        lg_perform_begin(k,Int32(token),Int32(performanceEpoch),recording ? 1:0,recording ? limit:0);playing=true;return performanceEpoch
    }
    func drainPerformance()->[LGPerformanceEvent]{guard let k=handle?.pointer else{return []};var result:[LGPerformanceEvent]=[];while true{let count=performanceBuffer.withUnsafeMutableBufferPointer{lg_perform_pop(k,$0.baseAddress,Int32($0.count))};if count==0{break};result.append(contentsOf:performanceBuffer.prefix(Int(count)))};return result}
    func effects(_ fx:MasterFX){if let k=handle?.pointer{lg_effects(k,Float(fx.filter),Float(fx.delayWet))}}
    func panic(){if let k=handle?.pointer{lg_panic(k)};playing=false}
    func metronome(_ on: Bool) {if let k = handle?.pointer {lg_metronome(k,on ? 1 : 0)}}
    func invalidateMusicSnapshot(){submittedNotes=nil}
    func reset() {
        submittedNotes=nil;submittedLayout=[];routing=[:];sentRevisions=[:];pendingPreviews=[];generation=0
        stop();timer?.invalidate()
        if let configurationObserver{NotificationCenter.default.removeObserver(configurationObserver)};configurationObserver=nil
        engine?.stop();engine=nil;source=nil;handle=nil
    }
}
