import Foundation

/// I31 · An instrument made from one recorded or imported sound: its pitch is detected, the
/// kernel plays it on every key by resampling (as for the built-in sampled instruments).
public enum MelodicSampler {
    /// One kernel zone holds at most 8 seconds.
    public static let maxSeconds = 8.0
    public static let rate = 32_000

    public struct Shape: Equatable, Sendable {
        /// Seconds of fade-in baked into the start (0…1).
        public var attack: Double
        /// True: each note plays the sound to its end (plucked, bells). False: the sound loops
        /// while the key is held and stops with it.
        public var ringsOut: Bool
        public init(attack: Double = 0.005, ringsOut: Bool = true) { self.attack = attack; self.ringsOut = ringsOut }
    }

    /// Mono at the sampler rate, silence trimmed (−45 dBFS), at most 8 s, peak −1 dBFS.
    public static func prepare(_ samples: [Float], rate source: Double) -> [Float] {
        guard !samples.isEmpty, source > 0 else { return [] }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return [] }
        let threshold = peak * 0.0056
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
              let last = samples.lastIndex(where: { abs($0) >= threshold }) else { return [] }
        var trimmed = Array(samples[first...last])
        if Int(source) != rate { trimmed = resample(trimmed, from: source, to: Double(rate)) }
        let limit = Int(maxSeconds * Double(rate))
        if trimmed.count > limit { trimmed = Array(trimmed.prefix(limit)) }
        let gain = 0.891 / max(1e-6, trimmed.reduce(0) { max($0, abs($1)) })
        return trimmed.map { $0 * gain }
    }

    /// The sound's pitch: the median of several readings in its first two seconds.
    public static func detectRoot(_ samples: [Float], rate: Double) -> (pitch: Int, cents: Double)? {
        let window = 4096, hop = 2048
        var frequencies: [Double] = []
        var start = min(samples.count / 8, Int(rate * 0.03))
        while start + window <= min(samples.count, Int(rate * 2)) {
            if let reading = Tuner.detect(Array(samples[start..<(start + window)]), sampleRate: rate) { frequencies.append(reading.frequency) }
            start += hop
        }
        if frequencies.isEmpty, samples.count >= 2048, let reading = Tuner.detect(Array(samples.prefix(window)), sampleRate: rate) { frequencies = [reading.frequency] }
        guard !frequencies.isEmpty else { return nil }
        let frequency = frequencies.sorted()[frequencies.count / 2]
        let exact = 69 + 12 * log2(frequency / 440)
        let pitch = Int(exact.rounded())
        guard (0...127).contains(pitch) else { return nil }
        return (pitch, (exact - Double(pitch)) * 100)
    }

    /// One zone at `root`: fade-in baked, a click-free sustain loop when the sound is held.
    public static func instrument(_ samples: [Float], root: Int, shape: Shape) throws -> SamplePCM {
        guard (0...127).contains(root), samples.count >= 2048 else { throw SampleError.invalid }
        var values = samples
        let fade = max(1, Int(min(1, max(0, shape.attack)) * Double(rate)))
        for index in 0..<min(fade, values.count) { values[index] *= Float(index) / Float(fade) }
        // The very end always fades out so a ringing sound never clicks off.
        let tail = min(values.count / 4, 256)
        for index in 0..<tail { values[values.count - 1 - index] *= Float(index) / Float(tail) }
        var loopStart = 0
        if !shape.ringsOut, values.count >= rate / 2 {
            // Loop the later part; cross-fade its end into the material before the loop point.
            let cross = min(2048, values.count / 8)
            var candidate = min(values.count - 1024 - cross, max(fade + cross, Int(Double(values.count) * 0.45)))
            while candidate < values.count - 1024 - cross, !(values[candidate - 1] < 0 && values[candidate] >= 0) { candidate += 1 }
            loopStart = candidate
            let end = values.count
            for index in 0..<cross {
                let weight = Float(index) / Float(cross)
                let into = loopStart - cross + index, out = end - cross + index
                values[out] = values[out] * (1 - weight) + values[into] * weight
            }
        }
        let pcm = values.map { Int16(max(-32767, min(32767, ($0 * 32767).rounded()))) }
        return SamplePCM(rate: rate, zones: [SamplePCM.Zone(pitch: root, samples: pcm, loopStart: loopStart)])
    }

    /// The prepared sound as a 16-bit mono WAV, to hear it before it becomes an instrument.
    public static func previewWAV(_ samples: [Float]) -> Data {
        var body = Data(capacity: samples.count * 2)
        for value in samples { body.little(Int16(max(-32767, min(32767, (value * 32767).rounded())))) }
        return pcmWAVHeader(rate: rate, channels: 1, bits: 16, byteCount: body.count) + body
    }

    /// "My sound · A3".
    public static func name(root: Int, label: String? = nil) -> String {
        let note = MusicalNotation.pitchClassName(root % 12, keyRoot: 0, minor: false) + "\(root / 12 - 1)"
        let base = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NSLocalizedString("My sound", comment: "Sampler instrument")
        return String((base + " · " + note).prefix(120))
    }

    static func resample(_ samples: [Float], from source: Double, to target: Double) -> [Float] {
        guard samples.count > 1, source != target else { return samples }
        let count = max(1, Int((Double(samples.count) * target / source).rounded()))
        let step = Double(samples.count - 1) / Double(max(1, count - 1))
        return (0..<count).map { index in
            let position = Double(index) * step
            let lower = Int(position), upper = min(samples.count - 1, lower + 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
