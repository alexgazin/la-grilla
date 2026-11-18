import Foundation
import MusicDomain

extension DrumSamplePreparation {
    /// Original one-shots baked only when the user loads the Pocket Kit.
    func pocketKit() throws -> [(pad: Int?, sound: PreparedSound)] {
        try Compiler.padNames.indices.map { pad in
            try Task.checkCancellation()
            let label = NSLocalizedString(Compiler.padNames[pad], comment: "Pad name")
            let name = String(format: NSLocalizedString("Pocket · %@", comment: "Pocket Kit sample"), label)
            let zone = SamplePCM.Zone(pitch: 60, samples: Self.pocketSample(pad))
            return (pad, try PreparedSound(name: name, kind: .oneShot, pcm: SamplePCM(rate: 32_000, zones: [zone])))
        }
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
