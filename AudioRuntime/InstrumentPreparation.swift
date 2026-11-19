import AVFoundation
import Foundation
import MusicDomain

struct PreparedSound: Sendable {
    let asset: SampleAsset
    let data: Data

    init(name: String, kind: SampleAsset.Kind, pcm: SamplePCM) throws {
        data = try pcm.encode(kind: kind)
        asset = try SampleAsset(kind: kind, name: name, bytes: data)
    }

    init(copying asset: SampleAsset, data: Data) throws {
        self.data = data
        self.asset = try SampleAsset(kind: asset.kind, name: asset.name, bytes: data, ringsOut: asset.ringsOut == true)
    }

    init(name: String, instrumentData: Data, ringsOut: Bool = false) throws {
        data = instrumentData
        asset = try SampleAsset(kind: .instrument, name: name, bytes: instrumentData, ringsOut: ringsOut)
        _ = try SamplePCM.decode(instrumentData, asset: asset)
    }
}

extension SoundBankLibrary {
    /// Prepare portable zones before touching the live render graph. Let the
    /// sampler resolve SF2 layers, transposition and envelopes at each root.
    func prepareInstrument(_ program: SoundBankProgram, in bank: ImportedSoundBank) throws -> PreparedSound {
        let rate = 32_000
        let frames = 80_000
        guard program.bank != 128, bank.programs.contains(program),
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048) else { throw SoundBankError.cannotRender }
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try load(program, into: sampler, from: bank.url)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: buffer.frameCapacity)
        try engine.start()
        defer { engine.stop() }

        var recordings: [(pitch: Int, pcm: [Float])] = []
        var peak: Float = 0
        for pitch in stride(from: 24, through: 96, by: 2) {
            try Task.checkCancellation()
            sampler.sendController(120, withValue: 0, onChannel: 0)
            try render(frames: 2048, in: engine, buffer: buffer) { _ in }
            sampler.startNote(UInt8(pitch), withVelocity: 100, onChannel: 0)
            var pcm: [Float] = []
            pcm.reserveCapacity(frames)
            try render(frames: AVAudioFramePosition(frames), in: engine, buffer: buffer) { block in
                guard let channels = block.floatChannelData else { throw SoundBankError.cannotRender }
                for index in 0..<Int(block.frameLength) {
                    let value = (channels[0][index] + channels[1][index]) * 0.5
                    guard value.isFinite else { throw SoundBankError.cannotRender }
                    peak = max(peak, abs(value))
                    pcm.append(value)
                }
            }
            sampler.stopNote(UInt8(pitch), onChannel: 0)
            guard pcm.count == frames else { throw SoundBankError.cannotRender }
            recordings.append((pitch, pcm))
        }
        guard peak > 0.0001 else { throw SoundBankError.cannotRender }
        // Leave polyphonic headroom for chords and simultaneous drums.
        let gain = min(8, 0.32 / peak)
        let zones = recordings.map { pitch, pcm in
            let early = Self.energy(pcm, from: 800, to: 8_000)
            let tail = Self.energy(pcm, from: 72_000, to: frames)
            let sustains = tail > 0.000001 && tail > early * 0.28
            let loopStart = sustains ? 48_000 : 0
            let fadeStart = frames - 512
            let values = pcm.enumerated().map { index, value in
                let envelope: Float = sustains || index < fadeStart ? 1 : Float(frames - 1 - index) / 511
                return Int16((value * gain * envelope * 32767).rounded())
            }
            return SamplePCM.Zone(pitch: pitch, samples: values, loopStart: loopStart)
        }
        try Task.checkCancellation()
        return try PreparedSound(name: program.name, kind: .instrument, pcm: SamplePCM(rate: rate, zones: zones))
    }

    private static func energy(_ pcm: [Float], from start: Int, to end: Int) -> Float {
        pcm[start..<end].reduce(0) { $0 + $1 * $1 } / Float(end - start)
    }
}

actor DrumSamplePreparation {
    static let shared = DrumSamplePreparation()
    static let library: Result<PadSampleStore, Error> = Result {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return PadSampleStore(root: support.appendingPathComponent("PadSamples", isDirectory: true))
    }

    func importAndKeep(_ url: URL) async throws -> PreparedSound {
        let sound = try importSample(url)
        _ = try await Self.library.get().add(sound.data, asset: sound.asset)
        return sound
    }

    func importSample(_ url: URL) throws -> PreparedSound {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard ["wav", "wave", "aif", "aiff"].contains(url.pathExtension.lowercased()),
              properties.isRegularFile == true, let bytes = properties.fileSize, bytes <= 8_000_000 else {
            throw SampleError.invalid
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let rate = format.sampleRate
        let frames = file.length
        guard (8_000...48_000).contains(rate), (1...2).contains(format.channelCount),
              frames >= 32, Double(frames) <= rate * 8,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw SampleError.invalid
        }
        try file.read(into: buffer)
        guard AVAudioFramePosition(buffer.frameLength) == frames, let channels = buffer.floatChannelData else {
            throw SampleError.invalid
        }
        let count = Int(buffer.frameLength)
        var pcm: [Int16] = []
        pcm.reserveCapacity(count)
        for index in 0..<count {
            let value = format.channelCount == 1 ? channels[0][index] : (channels[0][index] + channels[1][index]) * 0.5
            guard value.isFinite else { throw SampleError.invalid }
            let fade = Float(min(95, count - 1 - index)) / 95
            pcm.append(Int16((max(-1, min(1, value)) * fade * 32767).rounded()))
        }
        guard pcm.contains(where: { $0 != 0 }) else { throw SampleError.invalid }
        try Task.checkCancellation()
        return try PreparedSound(name: url.deletingPathExtension().lastPathComponent, kind: .oneShot,
                                 pcm: SamplePCM(rate: Int(rate.rounded()), zones: [.init(pitch: 60, samples: pcm)]))
    }
}
