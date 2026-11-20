import Foundation

/// I52 · trim leading and trailing silence of a recorded one-shot. The level
/// threshold is relative to the take's own peak (so quiet and loud takes trim
/// alike) but never lower than an absolute floor that ignores room noise.
extension OneShotSource {
    public func autoTrim(relativeDB: Double = -40, floorDBFS: Double = -60, preRollSeconds: Double = 0.002, fadeOutSeconds: Double = 0.01) -> OneShotEdit {
        autoTrimRange(relativeDB: relativeDB, floorDBFS: floorDBFS, preRollSeconds: preRollSeconds, fadeOutSeconds: fadeOutSeconds) ?? initialEdit
    }
}

public enum SilenceTrimmer {
    /// The audible range of `samples`, or nil for silence.
    public static func range(_ samples: [Int16], rate: Int, relativeDB: Double = -40, floorDBFS: Double = -60, preRollSeconds: Double = 0.002) -> Range<Int>? {
        guard let peak = samples.lazy.map({ abs(Int($0)) }).max(), peak > 0 else { return nil }
        let threshold = max(Double(peak) * pow(10, relativeDB / 20), 32768 * pow(10, floorDBFS / 20))
        guard let first = samples.firstIndex(where: { Double(abs(Int($0))) >= threshold }),
              let last = samples.lastIndex(where: { Double(abs(Int($0))) >= threshold }) else { return nil }
        let start = max(0, first - Int(preRollSeconds * Double(rate)))
        return start..<(last + 1)
    }
}

extension OneShotSource {
    func autoTrimRange(relativeDB: Double, floorDBFS: Double, preRollSeconds: Double, fadeOutSeconds: Double) -> OneShotEdit? {
        guard var range = SilenceTrimmer.range(zone.samples, rate: sampleRate, relativeDB: relativeDB, floorDBFS: floorDBFS, preRollSeconds: preRollSeconds) else { return nil }
        if range.count < OneShotEdit.minimumFrames {
            range = range.lowerBound..<min(frameCount, range.lowerBound + OneShotEdit.minimumFrames)
            guard range.count >= OneShotEdit.minimumFrames else { return nil }
        }
        var edit = OneShotEdit(startFrame: range.lowerBound, endFrame: range.upperBound, gainDB: 0)
        edit.fadeOutFrames = min(Int(fadeOutSeconds * Double(sampleRate)), maximumFadeFrames(for: edit))
        return edit
    }
}

/// I76 · the tempo of an audio loop from the autocorrelation of its onset
/// envelope. The coarse beat is refined on the four-beat lag, and when the
/// loop's duration fits a whole number of bars the tempo is snapped to it.
public enum AudioTempoEstimator {
    public struct Estimate: Equatable, Sendable {
        public let bpm: Double
        /// Bars in the loop when its length fits whole 4/4 bars at `bpm`.
        public let bars: Int?
    }

    public static func estimate(_ samples: [Float], rate: Int, range: ClosedRange<Double> = 70...180) -> Estimate? {
        let hop = max(64, rate / 200)   // 5 ms
        let envelope = onsetEnvelope(samples, hop: hop)
        guard envelope.count > 32 else { return nil }
        let frameRate = Double(rate) / Double(hop)
        let minLag = Int(frameRate * 60 / range.upperBound), maxLag = Int(frameRate * 60 / range.lowerBound) + 1
        guard maxLag < envelope.count / 2, minLag > 1 else { return nil }
        let r = autocorrelation(envelope, lags: 1...min(envelope.count - 1, maxLag * 4 + 4))
        // Prefer a beat whose double is also strong (avoids picking the off-beat).
        var best = minLag, bestScore = -Double.infinity
        for lag in minLag...maxLag {
            let score = r[lag] + 0.5 * (2 * lag < r.count ? r[2 * lag] : 0)
            if score > bestScore { best = lag; bestScore = score }
        }
        // Refine on the bar lag (4 beats): four times the resolution.
        var beatLag = interpolatedPeak(r, around: best)
        let bar = Int((beatLag * 4).rounded())
        if bar + 6 < r.count {
            var peak = bar
            for lag in max(1, bar - 6)...(bar + 6) where r[lag] > r[peak] { peak = lag }
            beatLag = interpolatedPeak(r, around: peak) / 4
        }
        var bpm = 60 * frameRate / beatLag
        let seconds = Double(samples.count) / Double(rate)
        var bars: Int?
        for candidate in [1, 2, 4, 8, 16] {
            let snapped = Double(candidate * 4) * 60 / seconds
            if abs(snapped - bpm) <= max(1.5, bpm * 0.015) { bpm = snapped; bars = candidate; break }
        }
        return Estimate(bpm: (bpm * 100).rounded() / 100, bars: bars)
    }

    static func onsetEnvelope(_ samples: [Float], hop: Int) -> [Double] {
        var energy: [Double] = []
        energy.reserveCapacity(samples.count / hop + 1)
        var i = 0
        while i + hop <= samples.count {
            var sum = 0.0
            for j in i..<(i + hop) { sum += Double(samples[j] * samples[j]) }
            energy.append(log(1e-9 + sum / Double(hop)))
            i += hop
        }
        guard energy.count > 1 else { return [] }
        var flux = [0.0]
        for k in 1..<energy.count { flux.append(max(0, energy[k] - energy[k - 1])) }
        let mean = flux.reduce(0, +) / Double(flux.count)
        return flux.map { $0 - mean }
    }

    static func autocorrelation(_ x: [Double], lags: ClosedRange<Int>) -> [Double] {
        var r = [Double](repeating: 0, count: lags.upperBound + 1)
        for lag in lags {
            var sum = 0.0
            for i in 0..<(x.count - lag) { sum += x[i] * x[i + lag] }
            r[lag] = sum / Double(x.count - lag)
        }
        return r
    }

    static func interpolatedPeak(_ r: [Double], around i: Int) -> Double {
        guard i > 0, i + 1 < r.count else { return Double(i) }
        let a = r[i - 1], b = r[i], c = r[i + 1], d = a - 2 * b + c
        guard d < 0 else { return Double(i) }
        return Double(i) + min(0.5, max(-0.5, 0.5 * (a - c) / d))
    }
}

/// I54 · offline time stretch without changing pitch (WSOLA). Runs at load
/// time only; the audio callback reads the finished buffer.
public enum TimeStretch {
    /// `ratio` is output length / input length, limited to 0.5…2.
    public static func wsola(_ input: [Float], rate: Int, ratio: Double) -> [Float] {
        let ratio = min(2, max(0.5, ratio.isFinite ? ratio : 1))
        guard input.count > 0 else { return [] }
        let outputCount = Int((Double(input.count) * ratio).rounded())
        if abs(ratio - 1) < 1e-9 { return input }
        let frame = max(256, (rate / 40) & ~1)          // ~25 ms
        let synthesisHop = frame / 2
        let analysisHop = Double(synthesisHop) / ratio
        let tolerance = frame / 4
        let padded = [Float](repeating: 0, count: frame + tolerance) + input + [Float](repeating: 0, count: 2 * frame + tolerance)
        let offset = frame + tolerance
        let window = (0..<frame).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frame))) }
        var output = [Float](repeating: 0, count: outputCount + 2 * frame)
        var norm = [Float](repeating: 0, count: output.count)
        var previous = offset           // input position copied last
        var k = 0
        while k * synthesisHop < outputCount + synthesisHop {
            let nominal = offset + Int((Double(k) * analysisHop).rounded())
            var position = nominal
            if k > 0 {
                let natural = previous + synthesisHop
                var best = -Float.infinity
                for delta in -tolerance...tolerance {
                    let candidate = nominal + delta
                    guard candidate >= 0, candidate + frame <= padded.count, natural + frame <= padded.count else { continue }
                    var sum: Float = 0
                    var j = 0
                    while j < frame { sum += padded[candidate + j] * padded[natural + j]; j += 4 }
                    if sum > best { best = sum; position = candidate }
                }
            }
            let out = k * synthesisHop
            guard position + frame <= padded.count, out + frame <= output.count else { break }
            for j in 0..<frame {
                output[out + j] += padded[position + j] * window[j]
                norm[out + j] += window[j]
            }
            previous = position
            k += 1
        }
        // The first half-frame was filled from the zero lead-in; shift it out.
        let lead = synthesisHop
        var result = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount where i + lead < output.count {
            let n = norm[i + lead]
            result[i] = n > 1e-3 ? output[i + lead] / n : 0
        }
        return result
    }
}

extension TimeStretch {
    /// I54 · fit a loop played at `from` BPM to `to` BPM without changing its pitch.
    public static func fit(_ samples: [Int16], rate: Int, from: Double, to: Double) -> [Int16] {
        guard from.isFinite, to.isFinite, from > 0, to > 0, abs(from - to) > 0.01 else { return samples }
        let stretched = wsola(samples.map { Float($0) / 32768 }, rate: rate, ratio: from / to)
        return stretched.map { Int16(clamping: Int(($0 * 32767).rounded())) }
    }
}

/// I94 · in-app latency measurement: the microphone records the output click;
/// cross-correlation of the reference click with the recording gives the
/// round-trip delay. Weak or ambiguous matches are rejected.
public enum LatencyAnalyzer {
    public struct Summary: Equatable, Sendable {
        public let medianMS: Double
        public let p95MS: Double
        public let count: Int
    }

    /// Delay of `reference` inside `recorded`, in milliseconds.
    public static func delay(reference: [Float], recorded: [Float], rate: Int, maximumSeconds: Double = 0.5, minimumCorrelation: Double = 0.5) -> Double? {
        guard !reference.isEmpty, recorded.count >= reference.count else { return nil }
        let refEnergy = reference.reduce(0.0) { $0 + Double($1 * $1) }
        guard refEnergy > 0 else { return nil }
        let maxLag = min(recorded.count - reference.count, Int(maximumSeconds * Double(rate)))
        var bestLag = -1, best = 0.0
        var window = recorded[0..<reference.count].reduce(0.0) { $0 + Double($1 * $1) }
        for lag in 0...maxLag {
            if lag > 0 {
                let out = Double(recorded[lag - 1]), inn = Double(recorded[lag + reference.count - 1])
                window = max(0, window - out * out + inn * inn)
            }
            guard window > 0 else { continue }
            var sum = 0.0
            for i in reference.indices { sum += Double(reference[i] * recorded[lag + i]) }
            let normalized = sum / sqrt(refEnergy * window)
            if normalized > best { best = normalized; bestLag = lag }
        }
        guard bestLag >= 0, best >= minimumCorrelation else { return nil }
        return Double(bestLag) * 1000 / Double(rate)
    }

    /// Median and 95th percentile after dropping outliers more than three
    /// median absolute deviations from the median.
    public static func summary(_ values: [Double]) -> Summary? {
        let finite = values.filter(\.isFinite).sorted()
        guard !finite.isEmpty else { return nil }
        let median = percentile(finite, 0.5)
        let mad = percentile(finite.map { abs($0 - median) }.sorted(), 0.5)
        let kept = mad > 0 ? finite.filter { abs($0 - median) <= 3 * mad * 1.4826 } : finite
        return Summary(medianMS: percentile(kept, 0.5), p95MS: percentile(kept, 0.95), count: kept.count)
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = p * Double(sorted.count - 1)
        let low = Int(position.rounded(.down)), high = min(sorted.count - 1, low + 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
    }

    /// A short windowed 2 kHz click that is easy to find in a noisy recording.
    public static func click(rate: Int, seconds: Double = 0.006) -> [Float] {
        let n = max(16, Int(Double(rate) * seconds))
        return (0..<n).map { i in
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))
            return Float(w * sin(2 * Double.pi * 2000 * Double(i) / Double(rate)) * 0.8)
        }
    }
}
