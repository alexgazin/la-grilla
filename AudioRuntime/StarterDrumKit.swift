import Foundation
import MusicDomain

extension DrumSamplePreparation {
    func pocketKit() throws -> [(pad: Int?, sound: PreparedSound)] {
        try kit(.pocket)
    }

    func kit(_ kit: FactoryDrumKit) throws -> [(pad: Int?, sound: PreparedSound)] {
        let prefix: String = switch kit {
        case .pocket: NSLocalizedString("Pocket · %@", comment: "Pocket Kit sample")
        case .dusty: "Dusty · %@"
        case .coast: "Coast · %@"
        case .trap808: "808 Trap · %@"
        case .house: "House · %@"
        case .brushes: "Brushes · %@"
        case .world: "World · %@"
        }
        return try Compiler.padNames.indices.map { pad in
            let label = NSLocalizedString(Compiler.padNames[pad], comment: "Pad name")
            let name = String(format: prefix, label)
            let zone = SamplePCM.Zone(pitch: 60, samples: try kit.sample(pad: pad))
            let pcm = SamplePCM(rate: FactoryDrumKit.sampleRate, zones: [zone])
            return (pad, try PreparedSound(name: name, kind: .oneShot, pcm: pcm))
        }
    }
}
