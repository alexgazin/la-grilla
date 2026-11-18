import AVFoundation
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
        struct Instrument: Decodable {
            struct Zone: Decodable { let pitch: Int; let frames: Int }
            let rate: Int
            let zones: [Zone]
            let sha256: String
        }
        let piano: Instrument
        let guitar: Instrument
    }

    func prepareFactoryInstrument(_ instrument: FactoryInstrument, directory: URL? = nil) throws -> PreparedSound {
        guard let root = directory ?? Bundle.main.resourceURL?.appendingPathComponent("FactoryInstruments", isDirectory: true) else {
            throw SampleError.unavailable
        }
        let manifest = try JSONDecoder().decode(FactoryManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let record = instrument == .piano ? manifest.piano : manifest.guitar
        let url = root.appendingPathComponent(instrument.rawValue).appendingPathExtension("caf")
        guard (8_000...48_000).contains(record.rate), (1...128).contains(record.zones.count),
              record.zones.allSatisfy({ (32...record.rate * 8).contains($0.frames) }),
              try AssetIntegrity.sha256(Data(contentsOf: url)) == record.sha256 else { throw SampleError.invalid }
        let count = record.zones.reduce(0) { $0 + $1.frames }
        guard count <= 3_999_000 else { throw SampleError.invalid }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        guard file.processingFormat.channelCount == 1, file.processingFormat.sampleRate == Double(record.rate),
              file.length == AVAudioFramePosition(count),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else {
            throw SampleError.invalid
        }
        try file.read(into: buffer)
        guard buffer.frameLength == AVAudioFrameCount(count), let samples = buffer.int16ChannelData?[0] else { throw SampleError.invalid }
        var offset = 0
        let zones = record.zones.map { zone in
            let pcm = Array(UnsafeBufferPointer(start: samples.advanced(by: offset), count: zone.frames))
            offset += zone.frames
            return SamplePCM.Zone(pitch: zone.pitch, samples: pcm)
        }
        return try PreparedSound(name: instrument.displayName, kind: .instrument, pcm: SamplePCM(rate: record.rate, zones: zones))
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
