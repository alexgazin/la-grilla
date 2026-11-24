import AudioDSP
import Foundation

/// I32 · Voice treatment presets for recorded sounds (audio tracks need I1 first).
public enum VoicePreset: Int, Codable, CaseIterable, Sendable {
    case podcast = 1, vocal, warm

    public var title: String {
        switch self {
        case .podcast: "Podcast"
        case .vocal: "Vocal"
        case .warm: "Warm"
        }
    }

    /// How far a sung note is pulled toward the nearest semitone (0 = not at all).
    public var pitchCorrection: Double { self == .vocal ? 0.7 : 0 }
}

public enum VoiceTreatment {
    /// EQ → compressor → de-esser in the kernel's offline chain, then soft pitch correction:
    /// the whole sound moves part of the way to the nearest note (only when a clear note is found).
    public static func apply(_ samples: [Float], rate: Int, preset: VoicePreset) -> [Float] {
        guard !samples.isEmpty, (8_000...192_000).contains(rate) else { return samples }
        var treated = samples
        let ok = treated.withUnsafeMutableBufferPointer { lg_voice_treat($0.baseAddress, Int32($0.count), Int32(rate), Int32(preset.rawValue)) } != 0
        guard ok else { return samples }
        guard preset.pitchCorrection > 0, let found = MelodicSampler.detectRoot(treated, rate: Double(rate)), abs(found.cents) > 3 else { return treated }
        let ratio = pow(2, -preset.pitchCorrection * found.cents / 1200)
        // Reading faster raises the pitch: resample to length / ratio.
        return MelodicSampler.resample(treated, from: Double(rate) * ratio, to: Double(rate))
    }
}
