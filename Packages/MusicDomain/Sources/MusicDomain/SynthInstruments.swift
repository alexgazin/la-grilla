import Foundation

/// Beat machine · Original synthesized instruments for melodic tracks: 808s and other
/// basses for hip-hop and electronic music, plus leads, keys and pads. Everything is
/// rendered on the device from these formulas, so there is no third-party sample and
/// projects carry the sound as an ordinary instrument asset.
///
/// Sustained sounds loop over whole cycles of every partial (the same technique as the
/// built-in organ), so held notes never click; decaying sounds play out like one-shots.
public enum FactorySynth: String, CaseIterable, Codable, Sendable, Identifiable {
    case sub808 = "808-sub", punch808 = "808-punch", dirty808 = "808-dirty", logDrum = "log-drum"
    case reese = "reese-bass", acid = "acid-bass", fingerBass = "finger-bass", synthBass = "square-bass"
    case supersaw = "supersaw", pluck = "synth-pluck", bellKeys = "bell-keys", lofiKeys = "lofi-keys"
    case brass = "synth-brass", strings = "string-pad", choir = "choir-pad", chipLead = "chip-lead"

    public enum Family: String, Sendable { case bass, lead, keys, pad }

    public var id: String { rawValue }
    public static let rate = 32_000
    public static let basses: [FactorySynth] = allCases.filter { $0.family == .bass }
    public static let melodic: [FactorySynth] = allCases.filter { $0.family != .bass }

    public var family: Family {
        switch self {
        case .sub808, .punch808, .dirty808, .logDrum, .reese, .acid, .fingerBass, .synthBass: .bass
        case .supersaw, .chipLead: .lead
        case .pluck, .bellKeys, .lofiKeys: .keys
        case .brass, .strings, .choir: .pad
        }
    }

    /// English name; the app localizes it. Also the instrument asset's name.
    public var title: String {
        switch self {
        case .sub808: "808 Sub"
        case .punch808: "808 Punch"
        case .dirty808: "808 Distorted"
        case .logDrum: "Log drum bass"
        case .reese: "Reese bass"
        case .acid: "Acid bass"
        case .fingerBass: "Finger bass"
        case .synthBass: "Square bass"
        case .supersaw: "Supersaw lead"
        case .pluck: "Synth pluck"
        case .bellKeys: "Bell keys"
        case .lofiKeys: "Lo-fi keys"
        case .brass: "Synth brass"
        case .strings: "String pad"
        case .choir: "Choir pad"
        case .chipLead: "8-bit lead"
        }
    }

    public var brief: String {
        switch self {
        case .sub808: "Deep round 808 with a long tail. Trap, drill, R&B."
        case .punch808: "Short 808 with a hard click that cuts through on phone speakers."
        case .dirty808: "Saturated 808 that growls. Phonk, rage, hard trap."
        case .logDrum: "Woody pitched bass drum. Amapiano and afro house."
        case .reese: "Two detuned saws beating slowly. Drum & bass, dark garage."
        case .acid: "Resonant squelchy saw bass. Acid house and techno."
        case .fingerBass: "Plucked string bass. Funk, soul, boom bap."
        case .synthBass: "Square-wave bass with a short pluck. House, synthwave, pop."
        case .supersaw: "Wide detuned lead for drops and hooks."
        case .pluck: "Short bright pluck for arps and counter-melodies."
        case .bellKeys: "Glassy bell keys for trap melodies."
        case .lofiKeys: "Soft wobbly electric keys for lo-fi and neo soul."
        case .brass: "Warm swelling synth brass stabs."
        case .strings: "Slow string ensemble pad."
        case .choir: "Airy “ah” choir pad."
        case .chipLead: "Pulse-wave lead from old game consoles."
        }
    }

    /// Notes the sampler maps to each zone (zones every six semitones).
    public var zonePitches: [Int] {
        family == .bass ? Array(stride(from: 24, through: 60, by: 6)) : Array(stride(from: 36, through: 96, by: 6))
    }

    public var loops: Bool {
        switch self {
        case .reese, .synthBass, .supersaw, .brass, .strings, .choir, .chipLead: true
        default: false
        }
    }

    public func pcm() throws -> SamplePCM {
        let zones = try zonePitches.map { try zone($0) }
        return SamplePCM(rate: Self.rate, zones: zones)
    }

    /// The instrument as a project asset with its encoded bytes.
    public func asset() throws -> (asset: SampleAsset, data: Data) {
        let data = try pcm().encode(kind: .instrument)
        return (try SampleAsset(kind: .instrument, name: NSLocalizedString(title, comment: "Factory synth"), bytes: data), data)
    }

    /// Two seconds of a short phrase in this sound, for auditioning in a list.
    public func previewWAV(_ rendered: SamplePCM? = nil) throws -> Data {
        let pcm = try rendered ?? pcm()
        let rate = Self.rate
        let phrase: [(pitch: Int, start: Double, length: Double)] = family == .bass
            ? [(36, 0, 0.55), (36, 0.75, 0.2), (43, 1.0, 0.45), (39, 1.5, 0.5)]
            : [(60, 0, 0.4), (63, 0.5, 0.4), (67, 1.0, 0.4), (70, 1.5, 0.45)]
        var mix = [Float](repeating: 0, count: rate * 2 + rate / 2)
        for note in phrase {
            guard let zone = pcm.zones.min(by: { abs($0.pitch - note.pitch) < abs($1.pitch - note.pitch) }) else { continue }
            let ratio = pow(2, Double(note.pitch - zone.pitch) / 12)
            let onset = Int(note.start * Double(rate)), held = Int(note.length * Double(rate))
            var position = 0.0
            for frame in 0..<min(held + 2400, mix.count - onset) {
                var index = Int(position)
                if index >= zone.samples.count - 1 {
                    guard zone.loopStart > 0 else { break }
                    position -= Double(zone.samples.count - 1 - zone.loopStart); index = Int(position)
                }
                let fraction = Float(position - Double(index))
                let value = Float(zone.samples[index]) * (1 - fraction) + Float(zone.samples[index + 1]) * fraction
                let release: Float = frame < held ? 1 : max(0, 1 - Float(frame - held) / 2400)
                mix[onset + frame] += value * release * 0.8
                position += ratio
            }
        }
        var result = pcmWAVHeader(rate: rate, channels: 1, bits: 16, byteCount: mix.count * 2)
        let samples = mix.map { Int16(clamping: Int($0.rounded())).littleEndian }
        samples.withUnsafeBytes { result.append(contentsOf: $0) }
        return result
    }

    // MARK: Rendering

    private func zone(_ pitch: Int) throws -> SamplePCM.Zone {
        try Task.checkCancellation()
        let frequency = 440 * pow(2.0, Double(pitch - 69) / 12)
        let samples = loops ? try looped(frequency) : try decaying(frequency, pitch: pitch)
        let peak = samples.reduce(0.0) { max($0, abs($1)) }
        guard peak > 0 else { throw SampleError.invalid }
        let gain = 17_000 / peak
        let count = samples.count
        var pcm = [Int16]()
        pcm.reserveCapacity(count)
        for (frame, value) in samples.enumerated() {
            let edge = loops ? min(1, Double(frame) / 24) : min(1, Double(frame) / 24, Double(count - 1 - frame) / 600)
            pcm.append(Int16(clamping: Int((value * gain * edge).rounded())))
        }
        return SamplePCM.Zone(pitch: pitch, samples: pcm, loopStart: loops ? count / 2 : 0)
    }

    /// Sum of harmonics 1…count of `x` weighted by `weights` (Chebyshev recurrence).
    @inline(__always) private static func partials(_ x: Double, _ weights: [Double]) -> Double {
        let c = 2 * cos(x)
        var previous = 0.0, current = sin(x), sum = 0.0
        for weight in weights {
            sum += weight * current
            (previous, current) = (current, c * current - previous)
        }
        return sum
    }

    /// Resonant low-pass response at `frequency` for cutoff `cutoff` and resonance `q`.
    private static func lowPass(_ frequency: Double, cutoff: Double, q: Double) -> Double {
        let r = frequency / max(20, cutoff)
        return 1 / sqrt(pow(1 - r * r, 2) + pow(r / q, 2)) / (1 + pow(r, 4) * 0.25)
    }

    /// A seamless sustain: the second half is one loop in which every partial, detune
    /// and vibrato completes whole cycles; the first half holds the attack.
    private func looped(_ frequency: Double) throws -> [Double] {
        let rate = Double(Self.rate)
        let cycles = max(8, Int(frequency.rounded()))
        let period = Int((rate * Double(cycles) / frequency).rounded())
        let count = period * 2
        let turn = 2 * Double.pi
        let maximum = family == .bass ? 3_200.0 : 9_000.0
        let harmonicCount = max(1, min(family == .bass ? 48 : 32, Int(maximum / frequency)))
        func saw(_ cutoff: Double, q: Double = 0.75) -> [Double] {
            (1...harmonicCount).map { n in Self.lowPass(Double(n) * frequency, cutoff: cutoff, q: q) / Double(n) }
        }
        // Integer extra cycles per loop detune a voice while keeping the loop exact.
        let spread = max(1, Int((frequency * 0.006).rounded()))
        var out = [Double]()
        out.reserveCapacity(count)
        var weights: [Double] = [], bright: [Double] = []
        switch self {
        case .reese: weights = saw(520, q: 1.1)
        case .synthBass:
            func square(_ cutoff: Double) -> [Double] {
                (1...harmonicCount).map { (n: Int) -> Double in
                    let level: Double = n % 2 == 1 ? 1 : 0.35
                    return level / Double(n) * Self.lowPass(Double(n) * frequency, cutoff: cutoff, q: 1.4)
                }
            }
            weights = square(900)
            bright = square(3_000)
        case .supersaw: weights = saw(7_000)
        case .brass:
            weights = saw(2_600, q: 0.9)
            bright = saw(420, q: 0.9)
        case .strings: weights = saw(3_400)
        case .choir:
            weights = (1...harmonicCount).map { n in
                let f = Double(n) * frequency
                let formants = [(800.0, 1.0), (1_150, 0.6), (2_900, 0.25)].reduce(0) { $0 + $1.1 * exp(-pow(log2(f / $1.0) / 0.22, 2)) }
                return (0.08 + formants) / pow(Double(n), 0.6)
            }
        case .chipLead:
            weights = (1...harmonicCount).map { n in sin(Double.pi * Double(n) * 0.25) / Double(n) }
        default: throw SampleError.invalid
        }
        for frame in 0..<count {
            if frame.isMultiple(of: 8192) { try Task.checkCancellation() }
            let t = Double(frame) / rate
            let base = turn * Double(frame) / Double(period)
            let vibrato = 0.0035 * sin(base * 5) * min(1, t * 2)
            func phase(_ extra: Int) -> Double { base * Double(cycles + extra) * (1 + vibrato) }
            var value: Double
            switch self {
            case .reese:
                value = Self.partials(phase(-1), weights) + Self.partials(phase(1), weights) + 0.9 * sin(phase(0))
            case .synthBass:
                let pluck = exp(-t * 14)
                value = Self.partials(phase(0), weights) * (1 - pluck) + Self.partials(phase(0), bright) * pluck
                value *= 0.82 + 0.18 * exp(-t * 9)
            case .supersaw:
                value = Self.partials(phase(0), weights) + 0.8 * Self.partials(phase(-spread), weights) + 0.8 * Self.partials(phase(spread), weights)
                    + 0.5 * Self.partials(phase(-2 * spread), weights) + 0.5 * Self.partials(phase(2 * spread), weights)
            case .brass:
                let swell = exp(-t * 11)
                value = Self.partials(phase(0), weights) * (1 - swell) + Self.partials(phase(0), bright) * swell
                value = (value + 0.6 * Self.partials(phase(spread), weights) * (1 - swell)) * min(1, t * 22)
            case .strings:
                value = (Self.partials(phase(0), weights) + Self.partials(phase(-spread), weights) + Self.partials(phase(spread), weights)) * min(1, t * 3.5)
            case .choir:
                value = (Self.partials(phase(0), weights) + 0.8 * Self.partials(phase(spread), weights)) * min(1, t * 4)
            default:
                value = Self.partials(phase(0), weights)
            }
            out.append(value)
        }
        return out
    }

    /// Notes that ring out and fade on their own.
    private func decaying(_ frequency: Double, pitch: Int) throws -> [Double] {
        let rate = Double(Self.rate)
        let seconds: Double = switch self {
        case .sub808: 1.8
        case .punch808: 1.2
        case .dirty808: 1.6
        case .logDrum: 0.9
        case .acid: 1.4
        case .fingerBass: 1.5
        case .pluck: 1.1
        case .bellKeys: 2.2
        default: 2.0
        }
        let count = Int(seconds * rate)
        let turn = 2 * Double.pi
        var out = [Double]()
        out.reserveCapacity(count)
        var phase = 0.0, second = 0.0
        var seed = UInt32(truncatingIfNeeded: pitch &* 7919 &+ rawValue.count)
        // Karplus-Strong string for the finger bass.
        var string: [Double] = []
        if self == .fingerBass {
            let length = max(2, Int((rate / frequency).rounded()))
            var low = 0.0
            string = (0..<length).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                low += (Double(seed >> 8) / 8_388_608 - 1 - low) * 0.35
                return low
            }
        }
        var position = 0, last = 0.0
        var acidWeights: [Double] = []
        let acidHarmonics = max(1, min(40, Int(4_000 / frequency)))
        for frame in 0..<count {
            if frame.isMultiple(of: 8192) { try Task.checkCancellation() }
            let t = Double(frame) / rate
            var value: Double
            switch self {
            case .sub808, .punch808, .dirty808:
                let drop = self == .punch808 ? 1.4 * exp(-t * 45) : 0.7 * exp(-t * 30)
                phase += turn * frequency * (1 + drop) / rate
                let decay = exp(-t * (self == .punch808 ? 2.3 : self == .dirty808 ? 1.25 : 1.05))
                let tone = sin(phase) + 0.12 * sin(2 * phase)
                let click = self == .punch808 ? 0.5 * exp(-t * 180) * sin(turn * 1_800 * t) : 0.15 * exp(-t * 240) * sin(turn * 1_200 * t)
                switch self {
                case .dirty808:
                    let driven = tone * 3.4 + 0.35
                    value = (tanh(driven) - tanh(0.35)) * decay * 0.9 + click
                case .punch808: value = tanh(tone * 2.1) * decay + click
                default: value = tanh(tone * 1.35) * decay + click
                }
            case .logDrum:
                phase += turn * frequency * (1 + 0.55 * exp(-t * 26)) / rate
                second += turn * frequency * 2.02 * (1 + 0.55 * exp(-t * 26)) / rate
                value = tanh((sin(phase) + 0.35 * sin(second) * exp(-t * 9)) * 1.8) * exp(-t * 4.2)
            case .acid:
                if frame.isMultiple(of: 64) {
                    let cutoff = 380 + 2_600 * exp(-t * 5.5)
                    acidWeights = (1...acidHarmonics).map { n in Self.lowPass(Double(n) * frequency, cutoff: cutoff, q: 5) / Double(n) }
                }
                phase += turn * frequency / rate
                value = tanh(Self.partials(phase, acidWeights) * 0.9) * exp(-t * 0.9)
            case .fingerBass:
                let current = string[position]
                let next = string[(position + 1) % string.count]
                let averaged = (current + next) * 0.5 * 0.9975
                string[position] = averaged
                position = (position + 1) % string.count
                last += (current - last) * 0.45
                phase += turn * frequency / rate
                value = last * 1.4 + 0.25 * sin(phase) * exp(-t * 2.5)
            case .pluck:
                if frame.isMultiple(of: 64) {
                    let cutoff = 450 + 6_000 * exp(-t * 9)
                    let harmonics = max(1, min(32, Int(9_000 / frequency)))
                    acidWeights = (1...harmonics).map { n in Self.lowPass(Double(n) * frequency, cutoff: cutoff, q: 1.2) / Double(n) }
                }
                phase += turn * frequency / rate
                value = Self.partials(phase, acidWeights) * exp(-t * 3.4)
            case .bellKeys:
                phase += turn * frequency / rate
                let index = 2.2 * exp(-t * 3)
                value = sin(phase + index * sin(phase * 3.5)) * exp(-t * 1.5) + 0.25 * sin(phase * 2) * exp(-t * 4)
            case .lofiKeys:
                let wow = 1 + 0.0035 * sin(turn * 0.7 * t)
                phase += turn * frequency * wow / rate
                second += turn * frequency * 1.003 * wow / rate
                let tine = 1.5 * exp(-t * 4) * sin(phase * 2)
                value = tanh((sin(phase + tine) + 0.55 * sin(second + tine * 0.6)) * 0.9) * exp(-t * 1.25)
            default: throw SampleError.invalid
            }
            out.append(value)
        }
        return out
    }
}
