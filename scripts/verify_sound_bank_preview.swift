import AVFoundation
import Foundation
import MusicDomain

/// Runs only on Apple hosts and auditions a real external SoundFont, never a bundled fixture.
@main struct VerifySoundBankPreview {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw SoundBankError.invalid }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SoundBankLibrary(directory: root)
        let added = try await library.importBank(from: source)
        let reloaded = try await SoundBankLibrary(directory: root).list()
        guard reloaded.count == 1, let bank = reloaded.first, bank.id == added.id,
              bank.url != source, bank.programs == added.programs,
              let piano = bank.programs.first(where: { $0.bank == 0 && $0.program == 0 }),
              let guitar = bank.programs.first(where: { $0.bank == 0 && $0.program == 24 }) else {
            throw SoundBankError.invalid
        }
        let first = try await PCM(program: piano, bank: bank, library: library)
        let second = try await PCM(program: guitar, bank: bank, library: library)
        guard first != second, first.count == 52_224, second.count == first.count else { throw SoundBankError.cannotRender }
        print("Real SoundFont import persisted \(bank.programs.count) programs. Sampler rendered distinct audible piano and guitar previews.")

        var project = Project.demo()
        let store = ProjectStore(root: root.appendingPathComponent("Projects"))
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 16, tailSeconds: 0, dither: false)
        var exported: [Data] = []
        for program in [piano, guitar] {
            let prepared = try await library.prepareInstrument(program, in: bank)
            let pcm = try SamplePCM.decode(prepared.data, asset: prepared.asset)
            guard pcm.zones.count == 37,
                  let middleC = pcm.zones.first(where: { $0.pitch == 60 }),
                  middleC.samples.prefix(3200).contains(where: { abs(Int($0)) > 128 }) else { throw SoundBankError.cannotRender }
            project.tracks[0].instrumentSample = prepared.asset
            _ = try await store.stageSample(prepared.data, asset: prepared.asset, projectID: project.id)
            project.revision += 1
            _ = try await store.save(project)
            let restored = try await store.load(project.id)
            let samples = try await store.loadSamples(for: restored)
            let url = root.appendingPathComponent("program-\(program.program).wav")
            let rendered = try await OfflineRenderer.render(restored, to: url, settings: settings,
                                                            isolatedTrack: project.tracks[0].id, samples: samples)
            guard rendered.peak > 0.001, !rendered.clipped else { throw SoundBankError.cannotRender }
            exported.append(try Data(contentsOf: url))
            let oneShot = try await DrumSamplePreparation.shared.importSample(url)
            guard oneShot.asset.kind == .oneShot else { throw SampleError.invalid }
            print("Program \(program.program) \(program.name): baked \(pcm.zones.count) zones, reopened, exported \(rendered.frames) frames, peak \(rendered.peak)")
        }
        guard exported[0] != exported[1] else { throw SoundBankError.cannotRender }
        let kit = try await DrumSamplePreparation.shared.pocketKit()
        guard kit.count == 16, Set(kit.map { $0.sound.asset.sha256 }).count == 16 else { throw SampleError.invalid }
        print("16 distinct original one-shots verified. Exported PCM WAV files can be imported as drum samples.")

        exported.removeAll()
        let resources = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        for instrument in FactoryInstrument.allCases {
            let sound = try await library.prepareFactoryInstrument(instrument, directory: resources)
            var samples = SampleLibrary()
            samples.insert(try PreparedSampleBank(asset: sound.asset, data: sound.data))
            project.tracks[0].instrumentSample = sound.asset
            let output = root.appendingPathComponent(instrument.rawValue).appendingPathExtension("wav")
            let result = try await OfflineRenderer.render(project, to: output, settings: settings,
                                                          isolatedTrack: project.tracks[0].id, samples: samples)
            guard result.peak > 0.001, !result.clipped else { throw SoundBankError.cannotRender }
            exported.append(try Data(contentsOf: output))
            print("Bundled \(instrument.displayName) generated \(result.frames) audible WAV frames, peak \(result.peak)")
        }
        guard exported[0] != exported[1] else { throw SoundBankError.cannotRender }
    }

    static func PCM(program: SoundBankProgram, bank: ImportedSoundBank, library: SoundBankLibrary) async throws -> [Float] {
        let url = try await library.audition(program, in: bank)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        guard file.length == 52_224,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundBankError.cannotRender
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw SoundBankError.cannotRender }
        let pcm = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard pcm.allSatisfy(\.isFinite), pcm.contains(where: { abs($0) > 0.001 }) else { throw SoundBankError.cannotRender }
        return pcm
    }
}
