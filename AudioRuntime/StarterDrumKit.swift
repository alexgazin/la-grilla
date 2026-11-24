import Foundation
import MusicDomain

extension DrumSamplePreparation {
    func pocketKit() throws -> [(pad: Int?, sound: PreparedSound)] {
        try kit(.pocket)
    }

    func kit(_ kit: FactoryDrumKit) throws -> [(pad: Int?, sound: PreparedSound)] {
        try Compiler.padNames.indices.map { pad in (pad, try factorySound(kit, pad: pad)) }
    }

    /// One factory one-shot, ready for a pad.
    func factorySound(_ kit: FactoryDrumKit, pad: Int) throws -> PreparedSound {
        let zone = SamplePCM.Zone(pitch: 60, samples: try kit.sample(pad: pad))
        let pcm = SamplePCM(rate: FactoryDrumKit.sampleRate, zones: [zone])
        return try PreparedSound(name: Self.factoryName(kit, pad: pad), kind: .oneShot, pcm: pcm)
    }

    func factoryPreview(_ kit: FactoryDrumKit, pad: Int) throws -> Data { try kit.oneShotWAV(pad: pad) }

    nonisolated static func factoryName(_ kit: FactoryDrumKit, pad: Int) -> String {
        let prefix = kit == .pocket ? NSLocalizedString("Pocket · %@", comment: "Pocket Kit sample") : kit.samplePrefix + "%@"
        return String(format: prefix, NSLocalizedString(Compiler.padNames[pad], comment: "Pad name"))
    }
}
