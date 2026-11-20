import Foundation

/// Original mono one-shots. The pocket voices use the same generator and frame rate
/// as profiles saved before selectable kits were introduced.
public enum FactoryDrumKit: String, CaseIterable, Sendable {
    case pocket, dusty, coast
    /// I51: further original on-device kits (build 47 wave 6).
    case trap808, house, brushes, world
    /// Kits with their own generator; the three original kits keep theirs bit-exact.
    public static let original: [FactoryDrumKit] = [.pocket, .dusty, .coast]

    public static let sampleRate = 32_000

    public func sample(pad: Int) throws -> [Int16] {
        guard Compiler.padNames.indices.contains(pad) else { throw SampleError.invalid }
        try Task.checkCancellation()
        if self == .pocket { return Self.pocketSample(pad) }
        if self == .dusty || self == .coast { return try render(Self.kitVoices[pad], pad: pad) }
        return try renderStyled(pad: pad)
    }

    private struct Voice {
        let length: Double
        let pitch: Double
        let sweep: Double
        let tone: Double
        let noise: Double
        let decay: Double
        let highPass: Double
    }

    private static let voices: [Voice] = [
        .init(length: 0.53, pitch: 48, sweep: 122, tone: 1, noise: 0.18, decay: 11, highPass: 0.06),
        .init(length: 0.37, pitch: 178, sweep: 70, tone: 0.4, noise: 0.91, decay: 23, highPass: 0.39),
        .init(length: 0.12, pitch: 4210, sweep: 0, tone: 0.16, noise: 0.5, decay: 66, highPass: 0.9),
        .init(length: 0.58, pitch: 3640, sweep: 0, tone: 0.16, noise: 0.5, decay: 12, highPass: 0.9),
        .init(length: 0.3, pitch: 980, sweep: 0, tone: 0.04, noise: 0.88, decay: 25, highPass: 0.54),
        .init(length: 0.14, pitch: 820, sweep: 35, tone: 0.55, noise: 0.21, decay: 58, highPass: 0.35),
        .init(length: 0.46, pitch: 82, sweep: 34, tone: 0.78, noise: 0.22, decay: 13, highPass: 0.14),
        .init(length: 0.41, pitch: 126, sweep: 48, tone: 0.76, noise: 0.22, decay: 16, highPass: 0.18),
        .init(length: 0.34, pitch: 183, sweep: 52, tone: 0.72, noise: 0.26, decay: 19, highPass: 0.22),
        .init(length: 1.6, pitch: 2738, sweep: 0, tone: 0.21, noise: 0.65, decay: 4.6, highPass: 0.78),
        .init(length: 1.12, pitch: 4610, sweep: 0, tone: 0.38, noise: 0.22, decay: 7, highPass: 0.81),
        .init(length: 0.34, pitch: 5430, sweep: 0, tone: 0.25, noise: 0.51, decay: 21, highPass: 0.84),
        .init(length: 0.28, pitch: 575, sweep: 0, tone: 0.78, noise: 0.08, decay: 27, highPass: 0.4),
        .init(length: 0.14, pitch: 1860, sweep: 0, tone: 0.77, noise: 0.22, decay: 53, highPass: 0.45),
        .init(length: 0.24, pitch: 3920, sweep: 0, tone: 0.08, noise: 0.64, decay: 34, highPass: 0.72),
        .init(length: 0.37, pitch: 273, sweep: 168, tone: 0.62, noise: 0.35, decay: 20, highPass: 0.27)
    ]

    private static func pocketSample(_ pad: Int) -> [Int16] {
        let voice = voices[pad]
        let rate = 32_000.0
        let count = Int(rate * voice.length)
        var seed = UInt32(pad + 1) &* 2_654_435_761
        var low = 0.0
        return (0..<count).map { frame in
            let time = Double(frame) / rate
            let phase = 2 * Double.pi * (voice.pitch * time + voice.sweep * (1 - exp(-time * 61)) / 61)
            let partials = sin(phase) * 0.72 + sin(phase * 1.492) * 0.19 + sin(phase * 2.41) * 0.09
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed >> 8) / 8_388_608 - 1
            low += (noise - low) * (1 - voice.highPass)
            let burst = pad == 4 && time < 0.032 ? 0.35 + 0.65 * pow(abs(cos(time * 274)), 5) : 1
            let envelope = min(1, Double(frame) / 16) * min(1, Double(count - 1 - frame) / 192)
            let tone = partials * voice.tone * exp(-time * voice.decay)
            let rattle = (noise - low * voice.highPass) * voice.noise * exp(-time * voice.decay * (pad == 0 ? 8 : 1))
            return Int16((tanh(tone + rattle * burst) * envelope * 29000).rounded())
        }
    }
}

extension FactoryDrumKit {
    private enum Excitation { case kick, snare, metal, clap, wood, tom, bell, shaker }

    private struct KitVoice {
        let type: Excitation
        let dustyPitch, coastPitch, dustyLength, coastLength, gain: Double
        init(_ type: Excitation, _ dustyPitch: Double, _ coastPitch: Double,
             _ dustyLength: Double, _ coastLength: Double, _ gain: Double) {
            self.type = type
            self.dustyPitch = dustyPitch
            self.coastPitch = coastPitch
            self.dustyLength = dustyLength
            self.coastLength = coastLength
            self.gain = gain
        }
    }

    // Order is the persisted MIDI-pad mapping used by Compiler.padNames.
    private static let kitVoices: [KitVoice] = [
        .init(.kick,   58,  47, 0.34, 0.61, 1.00),
        .init(.snare, 187, 212, 0.27, 0.34, 0.88),
        .init(.metal,  2540, 3570, 0.095, 0.073, 0.40),
        .init(.metal,  2360, 3310, 0.41, 0.49, 0.46),
        .init(.clap,   940, 1230, 0.23, 0.32, 0.74),
        .init(.wood,   630,  905, 0.13, 0.12, 0.64),
        .init(.tom,     83,   71, 0.40, 0.55, 0.80),
        .init(.tom,    114,  101, 0.34, 0.46, 0.75),
        .init(.tom,    157,  148, 0.29, 0.39, 0.70),
        .init(.metal, 1820, 2340, 1.36, 1.62, 0.62),
        .init(.metal, 2210, 2800, 0.91, 1.17, 0.53),
        .init(.metal, 2940, 3190, 0.22, 0.28, 0.43),
        .init(.bell,   512,  568, 0.23, 0.32, 0.60),
        .init(.wood,  1440, 1980, 0.11, 0.15, 0.62),
        .init(.shaker, 1500, 2420, 0.17, 0.23, 0.47),
        .init(.tom,    218,  294, 0.17, 0.28, 0.66)
    ]

    private func render(_ voice: KitVoice, pad: Int) throws -> [Int16] {
        let dusty = self == .dusty
        let length = dusty ? voice.dustyLength : voice.coastLength
        let pitch = dusty ? voice.dustyPitch : voice.coastPitch
        let rate = Double(Self.sampleRate)
        let count = Int(length * rate)
        let turn = 2 * Double.pi
        // Factory gain calibration uses the shared two-bar audition. Set it on
        // the voices so installed pads retain the same balance as their preview.
        let output = voice.gain * (dusty ? 18_550.0 : 14_000.0)
        let decay = (dusty ? 5.8 : 5.0) / length
        var seed = UInt32(pad + (dusty ? 31 : 71)) &* 2_654_435_761
        var low = 0.0, broad = 0.0, tape = 0.0
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for frame in 0..<count {
            if frame.isMultiple(of: 4096) { try Task.checkCancellation() }
            let t = Double(frame) / rate
            let phase = turn * pitch * t
            let envelope = exp(-t * decay)
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / 8_388_608 - 1
            low += (white - low) * (dusty ? 0.048 : 0.14)
            broad += (white - broad) * (dusty ? 0.58 : 0.81)
            let shellNoise = broad - low
            let hiss = white - broad
            let signal: Double
            switch voice.type {
            case .kick, .tom:
                let kick = voice.type == .kick
                let bend = kick ? (dusty ? 111.0 : 159.0) : pitch * (dusty ? 0.31 : 0.65)
                let bendDecay = dusty ? 54.0 : 34.0
                let skin = phase + turn * bend * (1 - exp(-bendDecay * t)) / bendDecay
                let body = sin(skin) + (dusty ? 0.38 : 0.21) * sin(skin * (dusty ? 1.58 : 2))
                let attack = shellNoise * (dusty ? 0.87 : 0.55) + sin(phase * 9) * 0.20
                signal = body * envelope + attack * exp(-t * (kick ? 138 : 109))
            case .snare:
                let shell = sin(phase + 1.9 * (1 - exp(-68 * t))) + 0.43 * sin(phase * 1.56)
                let wires = dusty ? shellNoise * 2.35 : shellNoise * 1.55 + hiss * 3.2
                signal = shell * 0.69 * exp(-t * (dusty ? 38 : 24)) + wires * envelope
            case .clap:
                let gap = dusty ? 0.011 : 0.015
                let distance = t - floor(min(3, t / gap)) * gap
                let hands = shellNoise * 1.78 + sin(phase) * 0.13
                signal = hands * exp(-distance * 215) + shellNoise * 0.96 * envelope
            case .metal:
                let ring = sin(phase) + 0.72 * sin(phase * 1.39 + 1.5 * sin(phase * 0.61))
                        + 0.46 * sin(phase * 2.17)
                let strike = pad == 10 ? 0.13 * sin(phase * 0.42) : 0
                let metal = dusty ? ring * 0.13 + shellNoise * 1.35 : ring * 0.25 + hiss * 2.2
                signal = (metal + strike) * envelope
            case .wood, .bell:
                let bell = voice.type == .bell
                let second = bell ? (dusty ? 1.48 : 1.52) : 2.63
                let mode = sin(phase) + 0.65 * sin(phase * second)
                let mallet = shellNoise * (dusty ? 0.65 : 0.35) * exp(-170 * t)
                signal = (mode * 0.66 + sin(phase * 3.69) * 0.14) * envelope + mallet
            case .shaker:
                let attack = min(1, t / (dusty ? 0.016 : 0.009))
                signal = attack * envelope * (shellNoise * 0.78 + hiss * (dusty ? 1.25 : 3.1))
            }
            // The dusty kit shares a slightly driven, rolled-off signal path. The
            // coast kit preserves fast transients and the electronic drum tails.
            tape += (signal - tape) * 0.52
            let shaped = dusty ? tanh(tape * 1.75) : tanh(signal * 1.25)
            let edge = min(1, Double(frame) / 9, Double(count - 1 - frame) / 120)
            samples.append(Int16((shaped * edge * output).rounded()))
        }
        return samples
    }

    /// Two bars of the same 92 BPM break for every kit. Uses original PCM,
    /// sampler-style polyphony and one fixed mix gain so auditions are comparable.
    /// One pad's one-shot as a mono WAV, for auditioning in the sample library.
    public func oneShotWAV(pad: Int) throws -> Data {
        SamplePCM(rate: Self.sampleRate, zones: [.init(pitch: 60, samples: try sample(pad: pad))]).monoWAV()
    }

    public func previewWAV() throws -> Data {
        let rate = Self.sampleRate
        let step = Double(rate) * 60 / (92 * 4)
        var mix = [Float](repeating: 0, count: Int(step * 32) + rate / 4)
        var cache: [Int: [Int16]] = [:]
        func hit(_ pad: Int, _ index: Int, _ velocity: Float, late: Double = 0) throws {
            if cache[pad] == nil { cache[pad] = try sample(pad: pad) }
            guard let pcm = cache[pad] else { return }
            let onset = Int(step * (Double(index) + late))
            let count = min(pcm.count, mix.count - onset)
            for frame in 0..<count {
                mix[onset + frame] += Float(pcm[frame]) * velocity * 0.72
            }
        }
        for index in stride(from: 0, to: 32, by: 2) {
            try hit(index == 14 || index == 30 ? 3 : 2, index, index.isMultiple(of: 4) ? 0.77 : 0.58)
        }
        for index in [0, 7, 10, 16, 22, 26] { try hit(0, index, index % 16 == 0 ? 1 : 0.83) }
        for index in [4, 12, 20, 28] {
            try hit(1, index, 0.90, late: 0.035)
            if index == 12 || index == 28 { try hit(4, index, 0.53, late: 0.07) }
        }
        try hit(1, 25, 0.26, late: 0.09)
        try hit(5, 31, 0.48)
        var result = pcmWAVHeader(rate: rate, channels: 1, bits: 16, byteCount: mix.count * 2)
        let pcm = mix.map { Int16(clamping: Int($0.rounded())).littleEndian }
        pcm.withUnsafeBytes { result.append(contentsOf: $0) }
        return result
    }
}

// MARK: - I51 styled kits

extension FactoryDrumKit {
    private enum Hit { case boom, punch, felt, frame, snap, clap, brush, tek, hat, openHat, cymbal, ride, conga, shaker, bell, rim }
    private struct StyledVoice { let hit: Hit; let pitch: Double; let length: Double; let gain: Double }
    private struct Style { let drive: Double; let warmth: Double; let air: Double; let level: Double }

    private var style: Style {
        switch self {
        case .trap808: Style(drive: 1.6, warmth: 0.55, air: 1.0, level: 15_500)
        case .house: Style(drive: 1.4, warmth: 0.75, air: 1.0, level: 15_000)
        case .brushes: Style(drive: 1.0, warmth: 0.35, air: 0.6, level: 16_500)
        default: Style(drive: 1.15, warmth: 0.5, air: 0.8, level: 15_500)
        }
    }

    // Pad order is the persisted MIDI-pad mapping (Kick, Snare, Closed hat, Open hat,
    // Clap, Rim, Low/Mid/High tom, Crash, Ride, Tambourine, Cowbell, Clave, Shaker, Perc).
    private var styledVoices: [StyledVoice] {
        switch self {
        case .trap808: [
            .init(hit: .boom, pitch: 46, length: 1.3, gain: 1), .init(hit: .snap, pitch: 205, length: 0.26, gain: 0.85),
            .init(hit: .hat, pitch: 8200, length: 0.06, gain: 0.42), .init(hit: .openHat, pitch: 7600, length: 0.42, gain: 0.4),
            .init(hit: .clap, pitch: 1150, length: 0.3, gain: 0.8), .init(hit: .rim, pitch: 1700, length: 0.07, gain: 0.6),
            .init(hit: .boom, pitch: 70, length: 0.7, gain: 0.8), .init(hit: .boom, pitch: 98, length: 0.6, gain: 0.75),
            .init(hit: .boom, pitch: 131, length: 0.5, gain: 0.7), .init(hit: .cymbal, pitch: 5200, length: 1.5, gain: 0.5),
            .init(hit: .ride, pitch: 6100, length: 1.0, gain: 0.42), .init(hit: .shaker, pitch: 9000, length: 0.18, gain: 0.4),
            .init(hit: .bell, pitch: 540, length: 0.3, gain: 0.55), .init(hit: .tek, pitch: 2500, length: 0.06, gain: 0.55),
            .init(hit: .shaker, pitch: 7000, length: 0.14, gain: 0.4), .init(hit: .snap, pitch: 330, length: 0.18, gain: 0.6)]
        case .house: [
            .init(hit: .punch, pitch: 52, length: 0.42, gain: 1), .init(hit: .snap, pitch: 190, length: 0.24, gain: 0.8),
            .init(hit: .hat, pitch: 9400, length: 0.07, gain: 0.45), .init(hit: .openHat, pitch: 8800, length: 0.34, gain: 0.45),
            .init(hit: .clap, pitch: 1050, length: 0.38, gain: 0.9), .init(hit: .rim, pitch: 1500, length: 0.06, gain: 0.6),
            .init(hit: .punch, pitch: 90, length: 0.4, gain: 0.75), .init(hit: .punch, pitch: 120, length: 0.35, gain: 0.72),
            .init(hit: .punch, pitch: 160, length: 0.3, gain: 0.7), .init(hit: .cymbal, pitch: 6000, length: 1.4, gain: 0.5),
            .init(hit: .ride, pitch: 6800, length: 0.9, gain: 0.45), .init(hit: .shaker, pitch: 8000, length: 0.2, gain: 0.45),
            .init(hit: .bell, pitch: 590, length: 0.25, gain: 0.55), .init(hit: .tek, pitch: 2300, length: 0.07, gain: 0.55),
            .init(hit: .shaker, pitch: 6400, length: 0.16, gain: 0.45), .init(hit: .conga, pitch: 280, length: 0.25, gain: 0.6)]
        case .brushes: [
            .init(hit: .felt, pitch: 60, length: 0.4, gain: 0.95), .init(hit: .brush, pitch: 220, length: 0.42, gain: 0.85),
            .init(hit: .brush, pitch: 5200, length: 0.12, gain: 0.45), .init(hit: .brush, pitch: 4800, length: 0.5, gain: 0.45),
            .init(hit: .brush, pitch: 1400, length: 0.3, gain: 0.6), .init(hit: .rim, pitch: 1250, length: 0.08, gain: 0.55),
            .init(hit: .felt, pitch: 95, length: 0.45, gain: 0.75), .init(hit: .felt, pitch: 125, length: 0.4, gain: 0.72),
            .init(hit: .felt, pitch: 165, length: 0.35, gain: 0.7), .init(hit: .cymbal, pitch: 3800, length: 1.8, gain: 0.45),
            .init(hit: .ride, pitch: 4300, length: 1.4, gain: 0.5), .init(hit: .shaker, pitch: 5200, length: 0.22, gain: 0.4),
            .init(hit: .bell, pitch: 470, length: 0.3, gain: 0.5), .init(hit: .tek, pitch: 1900, length: 0.08, gain: 0.5),
            .init(hit: .shaker, pitch: 4200, length: 0.2, gain: 0.4), .init(hit: .brush, pitch: 800, length: 0.25, gain: 0.5)]
        default: [
            .init(hit: .frame, pitch: 64, length: 0.55, gain: 1), .init(hit: .tek, pitch: 900, length: 0.16, gain: 0.85),
            .init(hit: .shaker, pitch: 7200, length: 0.1, gain: 0.45), .init(hit: .shaker, pitch: 6400, length: 0.32, gain: 0.45),
            .init(hit: .clap, pitch: 980, length: 0.32, gain: 0.75), .init(hit: .tek, pitch: 1600, length: 0.09, gain: 0.6),
            .init(hit: .conga, pitch: 180, length: 0.4, gain: 0.8), .init(hit: .conga, pitch: 240, length: 0.35, gain: 0.78),
            .init(hit: .conga, pitch: 320, length: 0.3, gain: 0.76), .init(hit: .bell, pitch: 1320, length: 1.4, gain: 0.45),
            .init(hit: .bell, pitch: 880, length: 1.0, gain: 0.45), .init(hit: .shaker, pitch: 8600, length: 0.26, gain: 0.42),
            .init(hit: .bell, pitch: 640, length: 0.35, gain: 0.55), .init(hit: .tek, pitch: 2700, length: 0.07, gain: 0.55),
            .init(hit: .shaker, pitch: 5600, length: 0.2, gain: 0.45), .init(hit: .frame, pitch: 110, length: 0.3, gain: 0.7)]
        }
    }

    private func renderStyled(pad: Int) throws -> [Int16] {
        let voice = styledVoices[pad], style = self.style
        let rate = Double(Self.sampleRate), count = Int(max(0.075, voice.length) * rate), turn = 2 * Double.pi
        var seed = UInt32(pad + 101 + (Self.allCases.firstIndex(of: self) ?? 0) * 17) &* 2_654_435_761
        var low = 0.0, band = 0.0, phase = 0.0, out = [Int16](), tone = 0.0
        out.reserveCapacity(count)
        for frame in 0..<count {
            if frame.isMultiple(of: 4096) { try Task.checkCancellation() }
            let t = Double(frame) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / 8_388_608 - 1
            low += (white - low) * 0.06
            band += (white - band) * (0.3 + 0.6 * style.air)
            let hiss = white - band, body = band - low
            let decay = exp(-t * 5.2 / voice.length)
            var signal: Double
            switch voice.hit {
            case .boom:
                // 808: sine with a fast downward glide and a long tail.
                let f = voice.pitch * (1 + 1.6 * exp(-t * 34))
                phase += turn * f / rate
                signal = sin(phase) * exp(-t * 2.6 / voice.length) + body * 0.4 * exp(-t * 160)
            case .punch:
                let f = voice.pitch * (1 + 2.2 * exp(-t * 48))
                phase += turn * f / rate
                signal = sin(phase) * decay + (body * 0.8 + sin(turn * 3200 * t) * 0.25) * exp(-t * 220)
            case .felt:
                let f = voice.pitch * (1 + 0.5 * exp(-t * 30))
                phase += turn * f / rate
                signal = sin(phase) * decay * 0.9 + low * 2.2 * exp(-t * 60)
            case .frame:
                let f = voice.pitch * (1 + 0.8 * exp(-t * 40))
                phase += turn * f / rate
                signal = (sin(phase) + 0.3 * sin(phase * 2.3)) * decay + body * 0.6 * exp(-t * 90)
            case .snap:
                signal = sin(turn * voice.pitch * t) * 0.6 * exp(-t * 32) + (body * 1.6 + hiss * 1.4) * decay
            case .clap:
                let gap = 0.012, distance = t - floor(min(3, t / gap)) * gap
                signal = body * 1.9 * exp(-distance * 230) + body * 0.9 * decay
            case .brush:
                // A swish: band noise with a slow attack.
                let attack = min(1, t / 0.025)
                signal = attack * decay * (body * 1.4 + hiss * 0.5 * style.air)
            case .tek, .rim:
                signal = (sin(turn * voice.pitch * t) + 0.5 * sin(turn * voice.pitch * 2.7 * t)) * exp(-t * 60) + body * 0.5 * exp(-t * 120)
            case .hat, .openHat, .shaker:
                let attack = voice.hit == .shaker ? min(1, t / 0.012) : 1
                signal = attack * decay * (hiss * 7 + body * 0.6 + sin(turn * voice.pitch * t) * 0.08)
            case .cymbal, .ride:
                let ring = sin(turn * voice.pitch * t) + 0.7 * sin(turn * voice.pitch * 1.41 * t) + 0.4 * sin(turn * voice.pitch * 2.23 * t)
                signal = (ring * (voice.hit == .ride ? 0.32 : 0.18) + hiss * 4.5) * decay
            case .conga:
                let f = voice.pitch * (1 + 0.25 * exp(-t * 50))
                phase += turn * f / rate
                signal = sin(phase) * decay + body * 0.5 * exp(-t * 140)
            case .bell:
                signal = (sin(turn * voice.pitch * t) + 0.6 * sin(turn * voice.pitch * 2.76 * t) + 0.3 * sin(turn * voice.pitch * 5.4 * t)) * decay * 0.7
            }
            // Metals keep their air; drums and tones get the kit's warmth.
            let metallic = [.hat, .openHat, .shaker, .cymbal, .ride].contains(voice.hit)
            tone += (signal - tone) * (1 - (metallic ? 0 : style.warmth) * 0.6)
            let shaped = tanh(tone * style.drive)
            let edge = min(1, Double(frame) / 9, Double(count - 1 - frame) / 120)
            out.append(Int16((shaped * edge * voice.gain * style.level).rounded()))
        }
        return out
    }
}
