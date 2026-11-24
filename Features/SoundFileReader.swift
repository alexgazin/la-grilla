import AVFoundation
import MusicDomain

/// Reads the start of an audio (or video) file as mono samples for the sound makers
/// ("Instrument from a sound", "My 808").
enum SoundFileReader {
    /// At most `seconds` of `url`, channels averaged to mono, at the file's own rate.
    static func mono(_ url: URL, seconds: Double) async throws -> (samples: [Float], rate: Double) {
        let wav = try await AudioExtraction.wavIfNeeded(url, limit: seconds)
        let granted = wav.startAccessingSecurityScopedResource()
        defer { if granted { wav.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * seconds))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
              (try? file.read(into: buffer, frameCount: AVAudioFrameCount(frames))) != nil, let channels = buffer.floatChannelData else { throw SampleError.invalid }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        let mono = (0..<count).map { index in (0..<channelCount).reduce(Float(0)) { $0 + channels[$1][index] } / Float(channelCount) }
        return (mono, file.processingFormat.sampleRate)
    }

    /// One note from a file as an instrument that rings out on every key (the "My 808" sound).
    static func instrument(_ url: URL, name: String) async throws -> PreparedSound {
        let raw = try await mono(url, seconds: MelodicSampler.maxSeconds + 2)
        let samples = MelodicSampler.prepare(raw.samples, rate: raw.rate)
        guard samples.count >= 2048 else { throw SampleError.invalid }
        let root = MelodicSampler.detectRoot(samples, rate: Double(MelodicSampler.rate)).map { min(96, max(24, $0.pitch)) } ?? 36
        let pcm = try MelodicSampler.instrument(samples, root: root, shape: .init(attack: 0.003, ringsOut: true))
        return try PreparedSound(name: MelodicSampler.name(root: root, label: name), instrumentData: try pcm.encode(kind: .instrument), ringsOut: true)
    }
}
