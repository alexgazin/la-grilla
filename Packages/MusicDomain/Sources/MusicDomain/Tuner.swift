import Foundation

/// I35 · A chromatic tuner. One analysis window (about 0.1 s) gives the nearest note and
/// how many cents the sound is away from it. Works from a low bass E (41 Hz) to 1.3 kHz.
public enum Tuner {
    public struct Reading: Equatable, Sendable {
        public var frequency: Double
        /// MIDI note of the nearest equal-tempered pitch.
        public var note: Int
        /// −50…+50: flat below zero, sharp above.
        public var cents: Double
        public var confidence: Double
        public var inTune: Bool { abs(cents) <= 5 }
        public var name: String { Chord.roots[((note % 12) + 12) % 12] + String(note / 12 - 1) }
    }

    /// The nearest note for a frequency against an A4 reference (default 440 Hz).
    public static func reading(frequency: Double, reference: Double = 440, confidence: Double = 1) -> Reading? {
        guard frequency.isFinite, frequency > 20, frequency < 5_000, reference > 400, reference < 480 else { return nil }
        let exact = 69 + 12 * log2(frequency / reference)
        let note = Int(exact.rounded())
        return Reading(frequency: frequency, note: note, cents: (exact - Double(note)) * 100, confidence: confidence)
    }

    /// YIN on the newest window of `samples` (mono), decimated to about 11 kHz.
    public static func detect(_ samples: [Float], sampleRate: Double, reference: Double = 440) -> Reading? {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), samples.count >= 256 else { return nil }
        let factor = max(1, Int(sampleRate / 11_025))
        let rate = sampleRate / Double(factor)
        let window = min(1_024, samples.count / factor)
        guard window >= 256 else { return nil }
        let start = samples.count - window * factor
        var frame = [Double](repeating: 0, count: window)
        for index in 0..<window {
            var sum = 0.0
            for offset in 0..<factor { sum += Double(samples[start + index * factor + offset]) }
            frame[index] = sum / Double(factor)
        }
        let mean = frame.reduce(0, +) / Double(window)
        for index in frame.indices { frame[index] -= mean }
        let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Double(window))
        guard rms >= 0.003 else { return nil }
        let minLag = max(2, Int(rate / 1_300)), maxLag = min(window / 2, Int(rate / 40))
        guard maxLag > minLag + 2 else { return nil }
        var difference = [Double](repeating: 1, count: maxLag + 2)
        var running = 0.0
        for lag in 1...(maxLag + 1) {
            var sum = 0.0
            for index in 0..<(window - lag) { let d = frame[index] - frame[index + lag]; sum += d * d }
            running += sum
            difference[lag] = running > 1e-12 ? sum * Double(lag) / running : 1
        }
        var chosen: Int?
        var lag = minLag
        while lag <= maxLag {
            if difference[lag] < 0.12 {
                while lag < maxLag, difference[lag + 1] < difference[lag] { lag += 1 }
                chosen = lag; break
            }
            lag += 1
        }
        guard let best = chosen ?? (minLag...maxLag).min(by: { difference[$0] < difference[$1] }), difference[best] < 0.3 else { return nil }
        var refined = Double(best)
        if best > 1, best + 1 < difference.count {
            let left = difference[best - 1], center = difference[best], right = difference[best + 1]
            let denominator = left - 2 * center + right
            if abs(denominator) > 1e-12 { refined += max(-0.5, min(0.5, 0.5 * (left - right) / denominator)) }
        }
        return reading(frequency: rate / refined, reference: reference, confidence: max(0, min(1, 1 - difference[best])))
    }

    /// Standard open strings for a quick check, low to high.
    public static let guitar = [40, 45, 50, 55, 59, 64]
    public static let bass = [28, 33, 38, 43]
    public static let ukulele = [67, 60, 64, 69]
}
