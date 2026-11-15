import AVFoundation
import AudioDSP
import MusicDomain
import Observation
import Darwin

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
        return
        AVAudioSourceNode(format:format) { @Sendable [kernel,hub] _, stamp, count, buffers in
            let output=UnsafeMutableAudioBufferListPointer(buffers)
            guard output.count==2,let left=output[0].mData,let right=output[1].mData else {return noErr}
            lg_render_midi(kernel.pointer,hub.pointer,stamp.pointee.mHostTime,ticks,left.assumingMemoryBound(to:Float.self),right.assumingMemoryBound(to:Float.self),Int32(count))
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
    private var generation = 0
    private var submittedNotes:[CompiledNote]?;private var submittedBPM=0.0;private var submittedRange:Range<Int>?;private var submittedLoop=false;private var submittedProject:UUID?
    private var performanceEpoch=0
    private var performanceBuffer=[LGPerformanceEvent](repeating:LGPerformanceEvent(),count:512)
    private var sentRevisions: [Int:Int] = [:]
    var isPrepared: Bool { engine?.isRunning == true }
    var clock: UInt64 = 0
    func prepare() throws {
        if engine?.isRunning == true { return }
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
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        error = nil
    }
    func poll() {
        guard let k = handle?.pointer else { return }
        clock = lg_clock(k); tick = lg_tick(k); playing = lg_playing(k) != 0; appliedRevision = sentRevisions[Int(lg_revision(k))] ?? -1; countRemaining = Int(lg_countremaining(k)); overflows = Int(lg_overflows(k))
        meters = (0...masterBus).map {lg_meter(k,Int32($0))};onPoll?()
    }
    func submit(_ p: Project, loop: Bool, range: Range<Int>) {
        guard let k = handle?.pointer else { return }
        let compiled=Compiler.notes(p)
        if compiled==submittedNotes,p.bpm==submittedBPM,range==submittedRange,loop==submittedLoop,p.id==submittedProject {
            sentRevisions[generation]=p.revision;if Int(lg_revision(k))==generation{appliedRevision=p.revision};mix(p);return
        }
        generation += 1; sentRevisions[generation] = p.revision
        if sentRevisions.count > 100 { sentRevisions = sentRevisions.filter { $0.key >= generation - 50 } }
        let notes = compiled.map { LGNote(tick: Int32($0.tick), duration: Int32($0.duration), pitch: Int32($0.pitch), velocity: Int32($0.velocity), track: Int32($0.track), pad: Int32($0.pad),instrument:Int32($0.instrument)) }
        let ok = notes.withUnsafeBufferPointer {lg_submit(k,$0.baseAddress,Int32($0.count),p.bpm,Int32(range.lowerBound),Int32(range.upperBound),loop ? 1 : 0,Int32(generation))}
        if ok == 0 { error = "Audio update could not be queued. Stop and retry." }else{submittedNotes=compiled;submittedBPM=p.bpm;submittedRange=range;submittedLoop=loop;submittedProject=p.id}
        mix(p)
    }
    func mix(_ p: Project) {
        guard let k = handle?.pointer else { return }; let solo = p.tracks.contains(where: \.solo)
        for (i,t) in p.tracks.enumerated() {lg_mix(k,Int32(i),Float(t.gain),Float(t.pan),!t.mute && (!solo || t.solo) ? 1 : 0)}
        lg_master(k,Float(p.master));let fx=p.masterFX ?? MasterFX();lg_effects(k,Float(fx.filter),Float(fx.delayWet))
    }
    func play(countInBPM: Double? = nil) {
        guard let k = handle?.pointer else { return }
        if let bpm = countInBPM {lg_countin(k,Int32((sampleRate*240/bpm).rounded()))}
        lg_play(k,1); playing = true
    }
    func audition(_ p:Project,range:Range<Int>,tick:Int?=nil,loop:Bool=true){submit(p,loop:loop,range:range);seek(tick ?? range.lowerBound);if let k=handle?.pointer{lg_restart(k)};playing=true}
    func stop() {if let k = handle?.pointer {lg_play(k,0)}; playing = false}
    func seek(_ tick: Int) {if let k = handle?.pointer {lg_seek(k,Int32(tick))}; self.tick = Double(tick)}
    func pad(_ pad: Int, velocity: Int = 100) {if let k = handle?.pointer { _ = lg_pad(k,Int32(pad),Int32(velocity)) }}
    func preview(_ chord: Chord) {if let k = handle?.pointer {for n in chord.notes {lg_preview(k,Int32(n))}}}
    func previewNote(_ pitch:Int,track:Int){if let k=handle?.pointer{lg_note_preview(k,Int32(pitch),Int32(track),3)}}
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
    func reset() {submittedNotes=nil; stop(); timer?.invalidate(); engine?.stop(); engine = nil; source = nil; handle = nil }
}
