import Foundation
import AVFoundation
import Observation
import MusicDomain

/// 54 · A recorded take for an audio track: the CAF, its record and the samples to play.
struct AudioTakeResult: Sendable {
    let data: Data
    let record: AudioAssetRecord
    let samples: [Float]
}

/// 54 · Records one take from the microphone while the song plays, timed like voice-to-MIDI
/// (the capture starts at a planned song position) but kept as audio, up to two minutes.
@MainActor @Observable final class AudioTakeController {
    enum State: Equatable { case idle, waiting, recording, finishing }
    var state: State = .idle
    var error: String?
    var elapsed = 0.0
    var waitingSeconds = 0.0
    var plannedDuration = 0.0
    var level = 0.0
    var isCapturing: Bool { state == .waiting || state == .recording }
    private var microphone: LiveMicrophone?
    private var timer: Timer?
    private var generation = 0
    private var activeURL: URL?
    private var finish: ((AudioTakeResult) -> Void)?

    func start(audio: AudioController, maximum: Double,
               schedule: @escaping @MainActor (Double) -> Double?, scheduleDuration: @escaping @MainActor () -> Double?,
               finished: @escaping (AudioTakeResult) -> Void) async {
        guard state == .idle else { return }
        error = nil; elapsed = 0; level = 0; generation += 1
        let attempt = generation
        let permission = await AVAudioApplication.requestRecordPermission()
        guard attempt == generation else { return }
        guard permission else { error = NSLocalizedString("Microphone access was denied. Turn it on in Settings › Privacy › Microphone to record.", comment: "Audio take"); return }
        do {
            if !audio.isPrepared { try audio.prepare() }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AudioTake-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("take.caf"); activeURL = url
            let stream = try LiveMicrophone(audio: audio, delay: 0.3, duration: maximum, maximum: maximum, schedule: schedule, scheduleDuration: scheduleDuration,
                                            receiver: { format in try VoicePCMSink.receiver(url: url, input: format) },
                                            onFailure: { [weak self] message in
                                                guard let self, self.generation == attempt, self.isCapturing else { return }
                                                self.fail(message)
                                            })
            microphone = stream; finish = finished
            plannedDuration = stream.duration; waitingSeconds = stream.secondsUntilStart; state = .waiting
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        } catch { guard generation == attempt else { return }; fail(error.localizedDescription) }
    }

    private func poll() {
        guard let microphone else { return }
        waitingSeconds = microphone.secondsUntilStart
        if state == .waiting, waitingSeconds <= 0 { state = .recording }
        elapsed = microphone.elapsed; level = microphone.level
        if elapsed == 0, microphone.secondsSinceStart > 2 { fail(LiveInputError.unavailable.localizedDescription); return }
        if microphone.complete { complete() }
    }

    /// Stop early: what was recorded so far becomes the take; before the start nothing is kept.
    func stop() {
        if state == .waiting { cancel(); return }
        if state == .recording { complete() }
    }

    func cancel() {
        generation += 1
        try? microphone?.stop(); microphone = nil
        timer?.invalidate(); timer = nil
        clear(); state = .idle; finish = nil
    }

    private func complete() {
        guard let url = activeURL, state != .finishing else { return }
        do { try microphone?.stop() } catch { fail(error.localizedDescription); return }
        microphone = nil; timer?.invalidate(); timer = nil; state = .finishing
        let attempt = generation
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) { try AudioTakeIO.result(url) }.value
                guard generation == attempt else { return }
                let done = finish
                clear(); state = .idle; finish = nil
                done?(result)
            } catch {
                guard generation == attempt else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        error = message
        try? microphone?.stop(); microphone = nil
        timer?.invalidate(); timer = nil
        clear(); state = .idle; finish = nil
    }
    private func clear() { if let folder = activeURL?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: folder) }; activeURL = nil }
}

enum AudioTakeIO {
    nonisolated static func result(_ url: URL) throws -> AudioTakeResult {
        let data = try Data(contentsOf: url)
        guard (64...32_000_000).contains(data.count) else { throw ExportError.archiveTooLarge }
        let read = try AudioTakeReader.samples(data)
        guard read.samples.count >= Int(read.rate * 0.05) else { throw LiveInputError.invalidSamples }
        let record = AudioAssetRecord(sha256: try AssetIntegrity.sha256(data), byteCount: data.count, sampleRate: read.rate,
                                      duration: Double(read.samples.count) / read.rate, origin: .microphone, recordedAt: Date(),
                                      inputLatencySeconds: min(2, max(0, AVAudioSession.sharedInstance().inputLatency)))
        try AssetIntegrity.validate(data, record: record)
        return AudioTakeResult(data: data, record: record, samples: read.samples)
    }
}
