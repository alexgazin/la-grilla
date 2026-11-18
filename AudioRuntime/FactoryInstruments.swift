import Foundation
import MusicDomain

enum FactoryInstrument: String, CaseIterable, Identifiable, Sendable {
    case piano
    case nylonGuitar = "nylon-guitar"

    case electricPiano = "electric-piano"
    case marimba, vibraphone, organ

    var isRecorded: Bool { self == .piano || self == .nylonGuitar }

    var id: String { rawValue }

    private var nameKey: String {
        switch self {
        case .piano: "Acoustic piano"
        case .nylonGuitar: "Nylon guitar"
        case .electricPiano: "Electric piano"
        case .marimba: "Marimba"
        case .vibraphone: "Vibraphone"
        case .organ: "Drawbar organ"
        }
    }

    var displayName: String { NSLocalizedString(nameKey, comment: "Studio instrument") }

    private static let persistedNames: [Self: Set<String>] = {
        let catalogs = ["en", "ru"].compactMap { language in
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        return Dictionary(uniqueKeysWithValues: allCases.map { instrument in
            let names = catalogs.map { $0.localizedString(forKey: instrument.nameKey, value: nil, table: nil) }
            return (instrument, Set(names + [instrument.nameKey]))
        })
    }()

    func matches(name: String?) -> Bool {
        guard let name else { return false }
        return Self.persistedNames[self]?.contains(name) == true
    }

}

extension SoundBankLibrary {
    private struct FactoryManifest: Decodable {
        struct Instrument: Decodable { let sha256: String }
        let piano: Instrument
        let guitar: Instrument
    }

    func prepareFactoryInstrument(_ instrument: FactoryInstrument, directory: URL? = nil) throws -> PreparedSound {
        if !instrument.isRecorded {
            return try PreparedSound(name: instrument.displayName, kind: .instrument, pcm: instrument.synthesize())
        }
        guard let root = directory ?? Bundle.main.resourceURL?.appendingPathComponent("FactoryInstruments", isDirectory: true) else {
            throw SampleError.unavailable
        }
        let manifest = try JSONDecoder().decode(FactoryManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let record = instrument == .piano ? manifest.piano : manifest.guitar
        let url = root.appendingPathComponent(instrument.rawValue).appendingPathExtension("lgpcm")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let sound = try PreparedSound(name: instrument.displayName, instrumentData: data)
        guard sound.asset.sha256 == record.sha256 else { throw SampleError.invalid }
        return sound
    }

    func auditionFactoryInstrument(_ instrument: FactoryInstrument) async throws -> URL {
        let prepared = try prepareFactoryInstrument(instrument)
        var project = Project.demo(), library = SampleLibrary()
        let harmony = project.tracks[0].id
        project = try TrackSoundPreview.project(from: project, trackID: harmony, palette: .classic)
        project.tracks[0].instrumentSample = prepared.asset
        library.insert(try PreparedSampleBank(asset: prepared.asset, data: prepared.data))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 16, tailSeconds: 0, dither: false)
        _ = try await OfflineRenderer.render(project, to: path, settings: settings, isolatedTrack: harmony, samples: library)
        return path
    }
}

private extension FactoryInstrument {
    func synthesize() throws -> SamplePCM {
        let rate = 32_000
        let zones = try stride(from: 36, through: 96, by: 6).map { pitch in
            try Task.checkCancellation()
            let frequency = 440 * pow(2.0, Double(pitch - 69) / 12)
            // Whole cycles at both ends of the organ loop keep held chords seamless.
            let cycles = Int(frequency.rounded())
            let periodFrames = Int((Double(rate * cycles) / frequency).rounded())
            let length = periodFrames * 2
            var pcm = [Int16]()
            pcm.reserveCapacity(length)
            for frame in 0..<length {
                let t = Double(frame) / Double(rate)
                let phase = 2 * Double.pi * Double(frame * cycles) / Double(periodFrames)
                let sample: Double
                switch self {
                case .electricPiano:
                    let tine = 2.3 * exp(-4 * t) * sin(phase * 2)
                    sample = exp(-1.8 * t) * sin(phase + tine)
                case .marimba:
                    sample = 0.85 * exp(-3.8 * t) * sin(phase) + 0.36 * exp(-15 * t) * sin(phase * 4)
                case .vibraphone:
                    let metal = sin(phase) + 0.3 * exp(-6 * t) * sin(phase * 3.99)
                    sample = exp(-1.6 * t) * (0.83 + 0.17 * cos(2 * .pi * 5.4 * t)) * metal
                case .organ:
                    sample = 0.59 * sin(phase) + 0.27 * sin(2 * phase) + 0.14 * sin(3 * phase)
                case .piano, .nylonGuitar:
                    throw SampleError.invalid
                }
                let attack = min(1, t * 350)
                let tail = self == .organ ? 1 : min(1, Double(length - frame - 1) / 400)
                pcm.append(Int16(clamping: Int((sample * attack * tail * 9500).rounded())))
            }
            return SamplePCM.Zone(pitch: pitch, samples: pcm, loopStart: self == .organ ? periodFrames : 0)
        }
        return SamplePCM(rate: rate, zones: zones)
    }
}
