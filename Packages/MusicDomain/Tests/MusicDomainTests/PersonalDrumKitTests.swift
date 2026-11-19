import Foundation
import Testing
@testable import MusicDomain

struct PersonalDrumKitTests {
    private let fm = FileManager.default
    private func temporaryDirectory() -> URL { fm.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func completeKitSurvivesSourceDeletionAndUndoAcrossProjects() async throws {
        let root = temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let store = ProjectStore(root: root.appendingPathComponent("Projects"))
        let libraryRoot = root.appendingPathComponent("Kits")
        let library = PersonalKitStore(root: libraryRoot)
        var origin = Project.demo()
        let original = try SamplePCM(rate: 16000, zones: [.init(pitch: 51, samples: (0..<1024).map { Int16($0*12-5000) })]).encode(kind: .oneShot)
        let originalAsset = try SampleAsset(kind: .oneShot, name: "Rim", bytes: original)
        let source = try OneShotSource(asset: originalAsset, data: original)
        let edit = OneShotEdit(startFrame: 50, endFrame: 610, gainDB: -3, fadeInFrames: 30, fadeOutFrames: 77)
        let printed = try source.render(edit).encode(kind: .oneShot)
        let hit = try SampleAsset(kind: .oneShot, name: "Rim cut", bytes: printed)
        let record = PadSampleEditRecord(source: source, edit: edit, renderedID: hit.id)
        origin.tracks[1].presetVersion = SoundPalette.bright.rawValue
        try origin.tracks[1].setPadSample(hit, pad: 0, edit: record)
        try origin.tracks[1].setPadSample(hit, pad: 15, edit: record)
        try origin.tracks[1].setPadSample(originalAsset, pad: 7)
        _ = try await store.stageSample(original, asset: originalAsset, projectID: origin.id)
        _ = try await store.stageSample(printed, asset: hit, projectID: origin.id)
        try await store.save(origin)

        let kit = try await store.capturePersonalKit(name: "  Session drums  ", track: origin.tracks[1], projectID: origin.id)
        let entries = try ProjectArchive.decode(kit.archive())
        #expect(entries.count == 3 && entries.filter { $0.name.hasPrefix("Samples/") }.count == 2)
        let saved = try await library.save(kit)
        #expect(saved.name == "Session drums" && saved.assignedCount == 3)
        try await store.delete(origin.id)
        let reopened = PersonalKitStore(root: libraryRoot)
        #expect(try await reopened.list() == [saved])
        let archived = try await reopened.load(saved.id)

        var song = Project.demo()
        song.tracks[1].gain = -17
        song.tracks[1].pan = 0.4
        song.tracks[1].mute = true
        let previous = song.tracks[1], patterns = song.patterns
        let prepared = try await store.preparePersonalKit(archived, projectID: song.id, retaining: song.referencedSamples)
        #expect(prepared.staged.count == 2 && prepared.banks.count == 2)
        var history = History()
        try history.apply(&song) { try prepared.apply(to: &$0.tracks[1]) }
        let track = song.tracks[1]
        #expect(track.id == previous.id && track.clips == previous.clips && track.gain == previous.gain && track.pan == previous.pan)
        #expect(track.mute == previous.mute && song.patterns == patterns && track.presetVersion == SoundPalette.bright.rawValue)
        #expect(track.padSamples?.count == 3 && track.padSamples?[0] == track.padSamples?[15] && track.padSamples?[1] == nil)
        let local = try #require(track.padEdits?[0])
        #expect(local.edit == edit && local.source == track.padSamples?[7] && local.source.id != originalAsset.id)
        #expect(local.renderedID == track.padSamples?[0]?.id && local.renderedID != hit.id)
        #expect(try await store.sampleData(local.source, projectID: song.id) == original)
        let printedAsset = try #require(track.padSamples?[0])
        #expect(try await store.sampleData(printedAsset, projectID: song.id) == printed)
        let repeated = try await store.preparePersonalKit(archived, projectID: song.id, retaining: song.referencedSamples)
        #expect(repeated.staged.isEmpty)
        try repeated.apply(to: &song.tracks[1])
        #expect(song.tracks[1] == track)
        try await store.save(song)
        #expect(try await store.load(song.id).tracks[1] == track)
        let recaptured = try await store.capturePersonalKit(name: "Session drums", track: track, projectID: song.id)
        #expect(try await reopened.save(recaptured) == saved)
        history.undo(&song)
        #expect(song.tracks[1] == previous)
        history.redo(&song)
        #expect(song.tracks[1] == track)
        try await reopened.delete(saved.id)
        #expect(try await reopened.list().isEmpty)
        #expect(try await store.sampleData(local.source, projectID: song.id) == original)
    }

    @Test func builtInKitResetsAllSlotsAndNameConflictKeepsLastGoodArchive() async throws {
        let root = temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let store = ProjectStore(root: root), library = PersonalKitStore(root: root.appendingPathComponent("Kits"))
        var track = Track(role: .drums)
        let kit = try await store.capturePersonalKit(name: "Default", track: track, projectID: UUID())
        #expect(kit.summary.assignedCount == 0)
        let saved = try await library.save(kit)
        track.presetVersion = SoundPalette.warm.rawValue
        let changed = try await store.capturePersonalKit(name: "dEFault", track: track, projectID: UUID())
        await #expect(throws: PersonalKitError.self) { try await library.save(changed) }
        #expect(try await library.load(saved.id).summary == saved)
        #expect(try await library.list() == [saved])
        let bytes = try SamplePCM(rate: 16000, zones: [.init(pitch: 36, samples: Array(repeating: 1, count: 90))]).encode(kind: .oneShot)
        let extra = try SampleAsset(kind: .oneShot, name: "Click", bytes: bytes)
        try track.setPadSample(extra, pad: 6)
        let prepared = try await store.preparePersonalKit(kit, projectID: UUID(), retaining: [])
        try prepared.apply(to: &track)
        #expect(track.padSamples == nil && track.padEdits == nil && track.presetVersion == 2)
        var melodic = Track(role: .bass)
        #expect(throws: SampleError.self) { try prepared.apply(to: &melodic) }
        await #expect(throws: PersonalKitError.self) { try await store.capturePersonalKit(name: "\n ", track: track, projectID: UUID()) }
        #expect(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Kits").path) == [saved.id.uuidString])
    }

    @Test func failedRecallRollsBackOnlyTheNewFiles() async throws {
        let root = temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let origin = UUID(), target = UUID()
        var track = Track(role: .drums)
        func hit(_ value: Int16, _ name: String, id: UUID = UUID()) throws -> (SampleAsset, Data) {
            let bytes = try SamplePCM(rate: 16000, zones: [.init(pitch: 48, samples: Array(repeating: value, count: 800))]).encode(kind: .oneShot)
            return (try SampleAsset(kind: .oneShot, name: name, bytes: bytes, id: id), bytes)
        }
        // The new voice is staged first, then the previously retained but missing voice fails verification.
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let lastID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        let (fresh, freshBytes) = try hit(123, "First", id: firstID)
        let (missing, missingBytes) = try hit(678, "Last", id: lastID)
        let (untouched, retainedBytes) = try hit(345, "Other")
        _ = try await store.stageSample(freshBytes, asset: fresh, projectID: origin)
        _ = try await store.stageSample(missingBytes, asset: missing, projectID: origin)
        _ = try await store.stageSample(retainedBytes, asset: untouched, projectID: target)
        try track.setPadSample(fresh, pad: 1)
        try track.setPadSample(missing, pad: 2)
        let kit = try await store.capturePersonalKit(name: "Kit", track: track, projectID: origin)
        await #expect(throws: SampleError.self) { try await store.preparePersonalKit(kit, projectID: target, retaining: [untouched, missing]) }
        let samples = root.appendingPathComponent(target.uuidString + ".grilla/Samples")
        #expect(try fm.contentsOfDirectory(atPath: samples.path) == [untouched.id.uuidString + ".lgpcm"])
        #expect(try await store.sampleData(untouched, projectID: target) == retainedBytes)
    }

    @Test func identicalCopiesSharePCMUnlessARecipeNeedsDistinctSourceAndPrint() async throws {
        let root = temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let store = ProjectStore(root: root), origin = UUID(), destination = UUID()
        let pcm = try SamplePCM(rate: 16000, zones: [.init(pitch: 48, samples: Array(repeating: Int16(0), count: 128))]).encode(kind: .oneShot)
        var track = Track(role: .drums)
        var aliases: [SampleAsset] = []
        for pad in 0..<4 {
            let hit = try SampleAsset(kind: .oneShot, name: "Rest", bytes: pcm)
            _ = try await store.stageSample(pcm, asset: hit, projectID: origin)
            try track.setPadSample(hit, pad: pad)
            aliases.append(hit)
        }
        let source = try OneShotSource(asset: aliases[0], data: pcm)
        var edit = source.initialEdit
        edit.gainDB = -6
        try track.setPadSample(aliases[1], pad: 1, edit: .init(source: source, edit: edit, renderedID: aliases[1].id))
        let kit = try await store.capturePersonalKit(name: "Rest kit", track: track, projectID: origin)
        #expect(try ProjectArchive.decode(kit.archive()).count == 2)
        let prepared = try await store.preparePersonalKit(kit, projectID: destination, retaining: [])
        #expect(prepared.staged.count == 2)
        try prepared.apply(to: &track)
        let record = try #require(track.padEdits?[1])
        #expect(record.source != track.padSamples?[1] && record.source == track.padSamples?[0])
        try record.validate(rendered: track.padSamples?[1])
        let retained = Set((track.padSamples ?? [:]).values).union([record.source])
        let again = try await store.preparePersonalKit(kit, projectID: destination, retaining: retained)
        #expect(again.staged.isEmpty)
        let previous = track
        try again.apply(to: &track)
        #expect(track == previous)
    }

    @Test func rejectsCorruptKitsAndIgnoresIncompleteStaging() async throws {
        let root = temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let library = PersonalKitStore(root: root)
        try fm.createDirectory(at: root.appendingPathComponent(".save-incomplete"), withIntermediateDirectories: true)
        #expect(try await library.list().isEmpty)
        let store = ProjectStore(root: root)
        let kit = try await store.capturePersonalKit(name: "Legacy", track: Track(role: .drums), projectID: UUID())
        let entries = try ProjectArchive.decode(kit.archive())
        let invalid = try ProjectArchive.encode(entries + [.init("unused", Data([0]))])
        #expect(throws: SampleError.self) { try PersonalDrumKit(archive: invalid) }
        var json = try #require(JSONSerialization.jsonObject(with: entries[0].data) as? [String: Any])
        json["version"] = 40
        let future = try ProjectArchive.encode([.init("kit.json", JSONSerialization.data(withJSONObject: json))])
        #expect(throws: SampleError.self) { try PersonalDrumKit(archive: future) }
        let saved = try await library.save(kit)
        let file = root.appendingPathComponent(saved.id.uuidString).appendingPathComponent("kit.grillakit")
        var damaged = try Data(contentsOf: file)
        damaged[50] ^= 4
        try damaged.write(to: file, options: .atomic)
        await #expect(throws: (any Error).self) { try await library.load(saved.id) }
        await #expect(throws: (any Error).self) { try await library.save(kit) }
        try await library.delete(saved.id)
        #expect(try await library.list().isEmpty)
    }
}
