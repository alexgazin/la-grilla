import Foundation
import MusicDomain

enum FactoryInstrument: String, CaseIterable, Identifiable, Sendable {
    case piano
    case nylonGuitar = "nylon-guitar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .piano: NSLocalizedString("Acoustic piano", comment: "Recorded factory instrument")
        case .nylonGuitar: NSLocalizedString("Nylon guitar", comment: "Recorded factory instrument")
        }
    }
}

extension SoundBankLibrary {
    private struct FactoryManifest: Decodable {
        struct Instrument: Decodable { let sha256: String }
        let piano: Instrument
        let guitar: Instrument
    }

    func prepareFactoryInstrument(_ instrument: FactoryInstrument, directory: URL? = nil) throws -> PreparedSound {
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
