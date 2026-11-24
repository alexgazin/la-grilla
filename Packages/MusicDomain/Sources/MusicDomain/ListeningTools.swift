import Foundation

/// I10 · A singable melody over chords: chord tones on strong beats, scale steps
/// between them, a phrase every two bars with a longer last note, and the top note
/// around two thirds of the way through. Deterministic for a seed.
public enum MelodySketcher {
    public static func melody(chords: [ChordEvent], length: Int, keyRoot: Int, minor: Bool,
                              low: Int = 60, high: Int = 76, density: Double = 0.5, seed: UInt64 = 1) -> [NoteEvent] {
        guard length > 0, low < high else { return [] }
        var random = SeededRandom(seed: seed)
        let scale = Set((minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]).map { ($0 + keyRoot) % 12 })
        func chordTones(at tick: Int) -> Set<Int> {
            let chord = chords.last { $0.tick <= tick && tick < $0.tick + $0.duration } ?? chords.first
            return Set((chord?.chord.notes ?? [keyRoot + 60]).map { (($0 % 12) + 12) % 12 })
        }
        let step = density > 0.66 ? barTicks / 8 : density > 0.33 ? barTicks / 4 : barTicks / 2
        let climax = length * 2 / 3
        var notes: [NoteEvent] = []
        var pitch = (low + high) / 2
        var tick = 0
        while tick < length {
            let phraseEnd = (tick / (barTicks * 2) + 1) * barTicks * 2
            let lastOfPhrase = tick + step >= min(length, phraseEnd)
            let strong = tick % (barTicks / 2) == 0
            // Leave a breath on some weak beats so it can be sung.
            if !strong && !lastOfPhrase && random.chance(0.2) { tick += step; continue }
            let tones = chordTones(at: tick)
            // Lean upward before the climax and downward after it.
            let lean = tick < climax ? 1 : -1
            let candidates = (low...high).filter { candidate in
                let pc = candidate % 12
                let allowed = strong || lastOfPhrase ? tones.contains(pc) : scale.contains(pc) || tones.contains(pc)
                return allowed && abs(candidate - pitch) <= (strong ? 7 : 4)
            }
            let ranked = candidates.sorted { a, b in
                let da = abs(a - pitch) - (a - pitch) * lean / 2, db = abs(b - pitch) - (b - pitch) * lean / 2
                return da == db ? a < b : da < db
            }
            if let choice = ranked.prefix(3).randomElement(using: &random) ?? (low...high).filter({ tones.contains($0 % 12) }).min(by: { abs($0 - pitch) < abs($1 - pitch) }) {
                pitch = choice
                let duration = lastOfPhrase ? min(length, phraseEnd) - tick : step
                notes.append(NoteEvent(tick: tick, duration: max(1, duration), pitch: pitch, velocity: strong ? 96 : 84))
                tick += duration
            } else { tick += step }
        }
        return Array(notes.prefix(4096))
    }
}

/// I4 · Tempo and chords from audio (mono samples), entirely on the device.
public enum AudioListening {
    /// Onset strength per frame: half-wave rectified rise of log energy.
    public static func onsetEnvelope(_ samples: [Float], sampleRate: Double, hop: Int = 512) -> [Float] {
        let frame = hop * 2
        guard samples.count > frame else { return [] }
        var energies: [Float] = []
        var start = 0
        while start + frame <= samples.count {
            var sum: Float = 0
            for index in start..<(start + frame) { sum += samples[index] * samples[index] }
            energies.append(log(1e-9 + sum / Float(frame)))
            start += hop
        }
        var envelope = [Float](repeating: 0, count: energies.count)
        for index in 1..<energies.count { envelope[index] = max(0, energies[index] - energies[index - 1]) }
        return envelope
    }

    /// Tempo in BPM (60–200), by autocorrelation of the onset envelope with a gentle
    /// preference for 80–140 BPM, rounded to 0.5.
    public static func tempo(_ samples: [Float], sampleRate: Double) -> Double? {
        let hop = 256
        let envelope = onsetEnvelope(samples, sampleRate: sampleRate, hop: hop)
        guard envelope.count > 32 else { return nil }
        let framesPerSecond = sampleRate / Double(hop)
        let minLag = Int(framesPerSecond * 60 / 200), maxLag = min(envelope.count - 1, Int(framesPerSecond * 60 / 60))
        guard minLag < maxLag else { return nil }
        let mean = envelope.reduce(0, +) / Float(envelope.count)
        let centred = envelope.map { $0 - mean }
        var best: (lag: Int, score: Double) = (0, -.infinity)
        for lag in minLag...maxLag {
            var sum: Double = 0
            for index in lag..<centred.count { sum += Double(centred[index] * centred[index - lag]) }
            let bpm = 60 * framesPerSecond / Double(lag)
            let weight = exp(-pow(log2(bpm / 110), 2) / 0.5)
            let score = sum / Double(centred.count - lag) * (0.6 + 0.4 * weight)
            if score > best.score { best = (lag, score) }
        }
        guard best.lag > 0 else { return nil }
        // Refine between neighbouring lags with a parabola.
        func value(_ lag: Int) -> Double {
            var sum: Double = 0
            for index in lag..<centred.count { sum += Double(centred[index] * centred[index - lag]) }
            return sum
        }
        var lag = Double(best.lag)
        if best.lag > minLag, best.lag < maxLag {
            let a = value(best.lag - 1), b = value(best.lag), c = value(best.lag + 1)
            let denominator = a - 2 * b + c
            if denominator != 0 { lag += 0.5 * (a - c) / denominator }
        }
        return (60 * framesPerSecond / lag * 2).rounded() / 2
    }

    /// Energy of each pitch class in a stretch of audio (Goertzel over MIDI 36…95).
    public static func chroma(_ samples: ArraySlice<Float>, sampleRate: Double) -> [Double] {
        var bins = [Double](repeating: 0, count: 12)
        let values = Array(samples)
        guard values.count > 64 else { return bins }
        for note in 36...95 {
            let frequency = 440 * pow(2, Double(note - 69) / 12)
            let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
            var s1 = 0.0, s2 = 0.0
            for sample in values { let s0 = Double(sample) + coefficient * s1 - s2; s2 = s1; s1 = s0 }
            let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
            bins[note % 12] += power
        }
        let peak = bins.max() ?? 0
        return peak > 0 ? bins.map { $0 / peak } : bins
    }

    public struct RecognisedChord: Equatable, Sendable {
        public let start: Double
        public let duration: Double
        public let chord: Chord
        public let confidence: Double
    }

    /// The best major or minor triad (or dominant/minor seventh) for each segment.
    public static func chords(_ samples: [Float], sampleRate: Double, segmentSeconds: Double) -> [RecognisedChord] {
        let size = max(256, Int(sampleRate * segmentSeconds))
        var result: [RecognisedChord] = []
        var start = 0
        let templates: [(Quality, [Int])] = [(.major, [0, 4, 7]), (.minor, [0, 3, 7]), (.seventh, [0, 4, 7, 10]), (.m7, [0, 3, 7, 10])]
        while start + size / 2 <= samples.count {
            let end = min(samples.count, start + size)
            let profile = chroma(samples[start..<end], sampleRate: sampleRate)
            var best: (Chord, Double) = (Chord(root: 0), -1)
            for root in 0..<12 {
                for (quality, intervals) in templates {
                    let member = Set(intervals.map { ($0 + root) % 12 })
                    let inside = member.reduce(0.0) { $0 + profile[$1] } / Double(member.count)
                    let outside = (0..<12).filter { !member.contains($0) }.reduce(0.0) { $0 + profile[$1] } / Double(12 - member.count)
                    // Sevenths must earn their extra note.
                    let score = inside - outside - (intervals.count == 4 ? 0.08 : 0)
                    if score > best.1 { best = (Chord(root: root, quality: quality), score) }
                }
            }
            result.append(RecognisedChord(start: Double(start) / sampleRate, duration: Double(end - start) / sampleRate, chord: best.0, confidence: max(0, min(1, best.1))))
            start += size
        }
        return result
    }
}
