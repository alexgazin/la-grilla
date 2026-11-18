import Foundation
import Testing
@testable import MusicDomain

struct SampleAssetTests {
    private func fixture(_ kind: SampleAsset.Kind) throws -> (SampleAsset, Data) {
        let frames = (0..<3200).map { index in
            Int16((index.isMultiple(of: 40) ? 14_000 : -4_000) * (3200 - index) / 3200)
        }
        let pcm = SamplePCM(rate: 32_000, zones: [.init(pitch: 60, samples: frames)])
        let data = try pcm.encode(kind: kind)
        return (try SampleAsset(kind: kind, name: "Test sample", bytes: data), data)
    }

    @Test func assignmentsSurviveHistoryStoreCopyAndPortableProject() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (instrument, data) = try fixture(.instrument)
        let (pad, padData) = try fixture(.oneShot)
        var project = Project.demo(), history = History()
        _ = try await store.stageSample(data, asset: instrument, projectID: project.id)
        _ = try await store.stageSample(padData, asset: pad, projectID: project.id)
        try history.apply(&project) { p in
            p.tracks[0].instrumentSample = instrument
            p.tracks[1].padSamples = [0: pad]
        }
        history.undo(&project)
        #expect(project.referencedSamples.isEmpty && history.retainedSamples == [instrument, pad])
        history.redo(&project)
        #expect(project.referencedSamples == [instrument, pad])
        // A performed song retains the original timbre after the live song changes.
        project.performanceTake = PerformanceTake(source: project, sampleRate: 48_000, durationFrames: 24_000,
            events: [PerformanceEvent(frame: 0, kind: .section, sectionID: project.sections[0].id)])
        project.tracks[0].instrumentSample = nil
        _ = try await store.save(project)
        let reopened = try await store.load(project.id)
        let loaded = try await store.loadSamples(for: reopened)
        #expect(reopened == project && loaded.assets == [instrument, pad])

        let archive = folder.appendingPathComponent("sample.grillapack")
        try await store.portable(reopened, to: archive)
        let bundle = try PortableProject.decodeBundle(Data(contentsOf: archive))
        #expect(bundle.assets[instrument.relativePath] == data && bundle.assets[pad.relativePath] == padData)
        let installed = try await store.install(bundle)
        let copy = try await store.duplicate(project)
        for candidate in [installed, copy] {
            let library = try await store.loadSamples(for: candidate)
            #expect(candidate.id != project.id && library.assets == loaded.assets)
            #expect(candidate.performanceTake?.source.tracks[0].instrumentSample == instrument)
        }
        let take = try #require(installed.performanceTake)
        let wav = folder.appendingPathComponent("performance.wav")
        let receipt = try await OfflineRenderer.renderPerformance(take, to: wav, samples: loaded)
        #expect(receipt.frames == 24_000 && receipt.peak > 0.001 && !receipt.clipped)
    }

    @Test func stemsUseTheAssignedWaveformAndRejectMissingAudio() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (asset, data) = try fixture(.instrument)
        var project = Project.demo(), library = SampleLibrary()
        library.insert(try PreparedSampleBank(asset: asset, data: data))
        project.tracks[0].instrumentSample = asset
        let track = project.tracks[0].id
        let wav = folder.appendingPathComponent("track.wav"), zip = folder.appendingPathComponent("stems.zip")
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 16, tailSeconds: 0, dither: false)
        await #expect(throws: SampleError.unavailable) { try await OfflineRenderer.render(project, to: wav, settings: settings) }
        #expect(!FileManager.default.fileExists(atPath: wav.path))
        let receipt = try await OfflineRenderer.render(project, to: wav, settings: settings, isolatedTrack: track, samples: library)
        #expect(receipt.peak > 0.001 && !receipt.clipped)
        _ = try await StemExporter.render(project, to: zip, settings: settings, selected: [track], samples: library)
        let stem = try #require(ProjectArchive.decode(Data(contentsOf: zip)).first { $0.name == "01-harmony.wav" })
        #expect(try Data(contentsOf: wav) == stem.data)
        project.tracks[0].instrumentSample = nil
        _ = try await OfflineRenderer.render(project, to: wav, settings: settings, isolatedTrack: track)
        #expect(try Data(contentsOf: wav) != stem.data)
    }

    @Test func formatChecksumAndRoutesAreValidatedBeforePlayback() throws {
        let (asset, data) = try fixture(.oneShot)
        var buffer = Data([0, 0, 0]); buffer.append(data)
        #expect(try SamplePCM.decode(buffer.dropFirst(3), asset: asset).zones.count == 1)
        buffer[buffer.count - 1] ^= 1
        #expect(throws: SampleError.invalid) { try SamplePCM.decode(buffer.dropFirst(3), asset: asset) }
        var project = Project.demo()
        project.tracks[1].padSamples = [16: asset]
        #expect(throws: MusicError.invalidProject) { try project.validate() }
        project.tracks[1].padSamples = [0: asset]
        project.schemaVersion = 11
        #expect(throws: MusicError.invalidProject) { try ProjectDocument.decode(JSONEncoder().encode(project)) }
    }
}
