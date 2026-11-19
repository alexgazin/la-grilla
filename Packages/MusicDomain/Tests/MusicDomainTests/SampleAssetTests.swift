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

    @Test func gongReleaseSurvivesPortableInstallAndExtendsPastTheFinalBar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try ArrangerTimbre.gong.sampleData(factoryDirectory: nil)
        let asset = try SampleAsset(kind: .instrument, name: "Gong", bytes: bytes, ringsOut: true)
        var song = Project(name: "Gong ending", bars: 1)
        song.bpm = 240
        song.hasComposedEnding = true
        let pattern = Pattern(length: barTicks, notes: [NoteEvent(tick: 0, duration: barTicks, pitch: 60, velocity: 100)])
        var track = Track(role: .melody)
        track.instrumentSample = asset
        track.clips = [Clip(patternID: pattern.id, start: 0, length: barTicks)]
        song.patterns.append(pattern)
        song.tracks.append(track)
        let imported = try PortableProject.decodeBundle(PortableProject.data(song, assets: [asset.relativePath: bytes]))
        let store = ProjectStore(root: root.appendingPathComponent("Projects"))
        let installed = try await store.install(imported)
        let library = try await store.loadSamples(for: installed)
        #expect(installed.hasComposedEnding == true && installed.tracks.last?.instrumentSample?.ringsOut == true)
        let wav = root.appendingPathComponent("tail.wav")
        let settings = WAVSettings(sampleRate: 44100, bitDepth: 16, tailSeconds: 0.5, dither: false)
        let receipt = try await OfflineRenderer.render(installed, to: wav, settings: settings, samples: library)
        #expect(receipt.frames == 66150 && !receipt.clipped)
        let data = try Data(contentsOf: wav)
        let peak = data.withUnsafeBytes { raw -> Int in
            // Stereo PCM16, half a second after the only scored bar ends.
            let start = 44 + 44100 * 4
            var value = 0
            for offset in stride(from: start, through: data.count-2, by: 2) {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                value = max(value, abs(Int(sample)))
            }
            return value
        }
        #expect(peak > 100)
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

    @Test func reusableSampleIsDeduplicatedAndProjectCopiesOutliveDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("PadSamples")
        let library = PadSampleStore(root: root)
        let (original, data) = try fixture(.oneShot)
        let added = try await library.add(data, asset: original)
        let repeated = try SampleAsset(kind: .oneShot, name: original.name, bytes: data)
        let deduplicated = try await library.add(data, asset: repeated)
        #expect(deduplicated == added)
        let reopened = PadSampleStore(root: root)
        #expect(try await reopened.list() == [added])
        #expect(try await reopened.bytes(for: added) == data)
        let wav = try await reopened.previewWAV(for: added)
        #expect(wav.prefix(4) == Data("RIFF".utf8) && wav.count == 44 + 3200 * 2)
        #expect(wav[22] == 1 && wav[34] == 16)
        let projects = ProjectStore(root: folder.appendingPathComponent("Projects"))
        var first = Project.demo(), second = Project.demo()
        for projectID in [first.id, second.id] {
            _ = try await projects.stageSample(data, asset: repeated, projectID: projectID)
        }
        first.tracks[1].padSamples = [0: repeated]
        second.tracks[1].padSamples = [2: repeated]
        _ = try await projects.save(first)
        _ = try await projects.save(second)
        try await reopened.remove(added)
        #expect(try await library.list().isEmpty)
        #expect(try await projects.loadSamples(for: first).assets == [repeated])
        #expect(try await projects.loadSamples(for: second).assets == [repeated])
    }
}
