import AVFoundation
import MusicDomain
import Observation

final class KernelHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(rate: Double) { pointer = lg_create(rate)! }
    deinit { lg_destroy(pointer) }
}
/// The render block must be constructed outside MainActor. AVFAudio's legacy block
/// type does not express Sendable; creating it in prepare() inherits MainActor
/// and Swift 6 traps when the engine calls it on the real-time audio thread.
private enum AudioRender {
    nonisolated static func makeSource(format: AVAudioFormat, kernel: KernelHandle) -> AVAudioSourceNode {
        AVAudioSourceNode(format:format) { @Sendable [kernel] _, _, count, buffers in
            let output=UnsafeMutableAudioBufferListPointer(buffers)
            guard output.count==2,let left=output[0].mData,let right=output[1].mData else {return noErr}
            lg_render(kernel.pointer,left.assumingMemoryBound(to:Float.self),right.assumingMemoryBound(to:Float.self),Int32(count))
            return noErr
        }
    }
}
@MainActor @Observable final class AudioController {
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var handle: KernelHandle?
    var tick: Double = 0; var playing = false; var appliedRevision = -1
    var meters: [Float] = [0,0,0,0]; var sampleRate: Double = 48000
    var countRemaining = 0; var error: String?
    var overflows = 0
    private var timer: Timer?
    private var generation = 0
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
        let node = AudioRender.makeSource(format:format, kernel:h)
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: format); e.prepare(); try e.start()
        handle = h; source = node; engine = e
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        error = nil
    }
    func poll() {
        guard let k = handle?.pointer else { return }
        clock = lg_clock(k); tick = lg_tick(k); playing = lg_playing(k) != 0; appliedRevision = sentRevisions[Int(lg_revision(k))] ?? -1; countRemaining = Int(lg_countremaining(k)); overflows = Int(lg_overflows(k))
        meters = (0..<4).map {lg_meter(k,Int32($0))}
    }
    func submit(_ p: Project, loop: Bool, range: Range<Int>) {
        guard let k = handle?.pointer else { return }
        generation += 1; sentRevisions[generation] = p.revision
        if sentRevisions.count > 100 { sentRevisions = sentRevisions.filter { $0.key >= generation - 50 } }
        let notes = Compiler.notes(p).map { LGNote(tick: Int32($0.tick), duration: Int32($0.duration), pitch: Int32($0.pitch), velocity: Int32($0.velocity), track: Int32($0.track), pad: Int32($0.pad)) }
        let ok = notes.withUnsafeBufferPointer {lg_submit(k,$0.baseAddress,Int32($0.count),p.bpm,Int32(range.lowerBound),Int32(range.upperBound),loop ? 1 : 0,Int32(generation))}
        if ok == 0 { error = "Audio update could not be queued. Stop and retry." }
        mix(p)
    }
    func mix(_ p: Project) {
        guard let k = handle?.pointer else { return }; let solo = p.tracks.contains(where: \.solo)
        for (i,t) in p.tracks.enumerated() {lg_mix(k,Int32(i),Float(t.gain),Float(t.pan),!t.mute && (!solo || t.solo) ? 1 : 0)}
        lg_master(k,Float(p.master))
    }
    func play(countInBPM: Double? = nil) {
        guard let k = handle?.pointer else { return }
        if let bpm = countInBPM {lg_countin(k,Int32((sampleRate*240/bpm).rounded()))}
        lg_play(k,1); playing = true
    }
    func stop() {if let k = handle?.pointer {lg_play(k,0)}; playing = false}
    func seek(_ tick: Int) {if let k = handle?.pointer {lg_seek(k,Int32(tick))}; self.tick = Double(tick)}
    func pad(_ pad: Int, velocity: Int = 100) {if let k = handle?.pointer { _ = lg_pad(k,Int32(pad),Int32(velocity)) }}
    func preview(_ chord: Chord) {if let k = handle?.pointer {for n in chord.notes {lg_preview(k,Int32(n))}}}
    func metronome(_ on: Bool) {if let k = handle?.pointer {lg_metronome(k,on ? 1 : 0)}}
    func reset() { stop(); timer?.invalidate(); engine?.stop(); engine = nil; source = nil; handle = nil }
}
