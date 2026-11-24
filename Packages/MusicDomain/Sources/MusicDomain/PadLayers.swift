import Foundation

/// I34 · How a layered pad picks its sound.
public enum PadLayerMode: String, Codable, CaseIterable, Hashable, Sendable {
    /// Soft hits play the first layer, hard hits the last (an equal split of 1…127).
    case velocity
    /// Each hit plays the next layer in turn, so repeated hits do not sound identical.
    case roundRobin

    public var title: String {
        switch self {
        case .velocity: "By hit strength"
        case .roundRobin: "In turn"
        }
    }
}

/// I34 · Two to four one-shots on one pad, stored as one layered sample.
public enum PadLayers {
    public static let counts = 2...4

    /// The layer a velocity plays; mirrors the kernel's equal split.
    public static func layer(velocity: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        return min(count - 1, min(127, max(1, velocity)) * count / 128)
    }

    /// Joins one-shots into layers 0…n−1 at the first sound's rate (others are resampled).
    public static func combine(_ sounds: [SamplePCM]) throws -> SamplePCM {
        guard counts.contains(sounds.count), sounds.allSatisfy({ $0.zones.count == 1 }) else { throw SampleError.invalid }
        let rate = sounds[0].rate
        var zones: [SamplePCM.Zone] = []
        var total = 0
        for (index, sound) in sounds.enumerated() {
            var samples = resample(sound.zones[0].samples, from: sound.rate, to: rate)
            if samples.count > rate * 8 { samples = Array(samples.prefix(rate * 8)) }
            guard samples.count >= 32 else { throw SampleError.invalid }
            total += samples.count
            zones.append(SamplePCM.Zone(pitch: index, samples: samples))
        }
        guard total <= 3_999_000 else { throw SampleError.limit }
        return SamplePCM(rate: rate, zones: zones)
    }

    /// A short name like "Layers · Kick + Snare".
    public static func name(_ names: [String]) -> String {
        let joined = names.map { $0.components(separatedBy: " · ").last ?? $0 }.joined(separator: " + ")
        return String((NSLocalizedString("Layers", comment: "Layered pad") + " · " + joined).prefix(120))
    }

    static func resample(_ samples: [Int16], from source: Int, to target: Int) -> [Int16] {
        guard source != target, source > 0, target > 0, samples.count > 1 else { return samples }
        let count = max(1, Int((Double(samples.count) * Double(target) / Double(source)).rounded()))
        let step = Double(samples.count - 1) / Double(max(1, count - 1))
        return (0..<count).map { index in
            let position = Double(index) * step
            let lower = Int(position), upper = min(samples.count - 1, lower + 1)
            let fraction = position - Double(lower)
            return Int16((Double(samples[lower]) * (1 - fraction) + Double(samples[upper]) * fraction).rounded())
        }
    }
}
