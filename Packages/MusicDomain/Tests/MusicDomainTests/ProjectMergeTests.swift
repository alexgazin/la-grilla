import Foundation
import Testing
@testable import MusicDomain

struct ProjectMergeTests {
    private func base() throws -> Project {
        var p = Project(name: "Shared", bars: 2)
        p.patterns[0].chords = [ChordEvent(tick: 0, chord: Chord(root: 0)), ChordEvent(tick: barTicks, chord: Chord(root: 7))]
        p.patterns[1].drums = [DrumEvent(tick: 0, pad: 0), DrumEvent(tick: 960, pad: 1), DrumEvent(tick: 1920, pad: 0)]
        try p.validate()
        return p
    }

    @Test func eachSideKeepsItsOwnEditsAndDeletionsApply() throws {
        let original = try base()
        var mine = original, theirs = original
        mine.bpm = 96
        mine.patterns[1].drums.append(DrumEvent(tick: 2880, pad: 2))
        theirs.patterns[0].chords[1].chord = Chord(root: 9, quality: .minor)
        theirs.patterns[1].drums.remove(at: 1)
        theirs.sections[0].name = "Intro"
        theirs.tracks[1].gain = -3
        let (merged, report) = try ProjectMerge.merge(base: original, mine: mine, theirs: theirs)
        #expect(merged.bpm == 96)
        #expect(merged.patterns[0].chords[1].chord == Chord(root: 9, quality: .minor))
        #expect(merged.patterns[1].drums.map(\.tick) == [0, 1920, 2880])
        #expect(merged.sections[0].name == "Intro" && merged.tracks[1].gain == -3)
        #expect(report.conflicts == 0 && report.removed == 1 && report.takenFromTheirs >= 3 && report.hasChanges)
        #expect(merged.id == mine.id)
    }

    @Test func conflictsKeepMineAndDeleteVersusChangeKeepsTheChange() throws {
        let original = try base()
        var mine = original, theirs = original
        mine.patterns[1].drums[0].velocity = 120
        theirs.patterns[1].drums[0].velocity = 40
        mine.patterns[1].drums[1].velocity = 70          // I changed it…
        theirs.patterns[1].drums.remove(at: 1)          // …they deleted it.
        theirs.patterns[1].drums[1].velocity = 90        // (index shifted: the 1920 kick)
        let (merged, report) = try ProjectMerge.merge(base: original, mine: mine, theirs: theirs)
        let drums = merged.patterns[1].drums
        #expect(drums.first { $0.tick == 0 }?.velocity == 120)
        #expect(drums.first { $0.tick == 960 }?.velocity == 70)
        #expect(drums.first { $0.tick == 1920 }?.velocity == 90)
        #expect(report.conflicts == 2)
    }

    @Test func withoutBaseNothingIsDeletedAndNewWorkIsAdded() throws {
        let original = try base()
        var mine = original, theirs = original
        theirs.patterns[1].drums.removeAll { $0.pad == 1 }
        theirs.patterns[1].drums.append(DrumEvent(tick: 480, pad: 2))
        theirs.bpm = 140
        let (merged, report) = try ProjectMerge.merge(base: nil, mine: mine, theirs: theirs)
        #expect(merged.patterns[1].drums.map(\.tick).sorted() == [0, 480, 960, 1920])
        #expect(merged.bpm == mine.bpm && report.conflicts == 1 && report.added == 1 && report.removed == 0)
        mine.name = "Mine"
        #expect(try ProjectMerge.merge(base: nil, mine: mine, theirs: mine).report.hasChanges == false)
    }

    @Test func aTrackAddedByTheCoAuthorArrivesWithBuiltInSounds() throws {
        let original = try base()
        var theirs = original
        var melody = Pattern(length: 2 * barTicks); melody.notes = [NoteEvent(tick: 0, duration: 480, pitch: 72, velocity: 90)]
        var track = Track(role: .melody); track.clips = [Clip(patternID: melody.id, start: 0, length: 2 * barTicks)]
        let bytes = try SamplePCM(rate: 16000, zones: [.init(pitch: 60, samples: [Int16](repeating: 1000, count: 400))]).encode(kind: .oneShot)
        track.padSamples = [0: try SampleAsset(kind: .oneShot, name: "Their kick", bytes: bytes)]
        theirs.patterns.append(melody); theirs.tracks.append(track)
        let (merged, report) = try ProjectMerge.merge(base: original, mine: original, theirs: theirs)
        #expect(merged.tracks.count == 3 && merged.tracks[2].padSamples == nil)
        #expect(merged.patterns.contains { $0.id == melody.id })
        #expect(report.keptSounds == 1 && report.added >= 2)
        #expect(Compiler.notes(merged).contains { $0.pitch == 72 })
    }
}

struct BatchArchiveNamesTests {
    @Test func namesAreSafeAndUnique() {
        let names = ProjectArchive.fileNames(["Song", "song", "a/b\\c:d", "  ", ".hidden.", "Song"], extension: "grillapack")
        #expect(names == ["Song.grillapack", "song (2).grillapack", "a-b-c-d.grillapack", "La Grilla.grillapack", "hidden.grillapack", "Song (3).grillapack"])
    }
}

struct SharedBaseStoreTests {
    @Test func exportRemembersTheSharedBaseAndBatchZipsEveryProject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        var a = Project(name: "Song", bars: 2); a.patterns[1].drums = [DrumEvent(tick: 0, pad: 0)]
        let b = Project(name: "Song", bars: 1)
        try await store.save(a); try await store.save(b)
        #expect(await store.sharedBase(a.id) == nil)
        let single = root.appendingPathComponent("a.grillapack")
        try await store.portable(try await store.load(a.id), to: single)
        let base = await store.sharedBase(a.id)
        #expect(base?.patterns[1].drums.count == 1)
        // The co-author's copy (imported as a new project) merges against that base.
        var theirs = try PortableProject.decode(Data(contentsOf: single))
        theirs.patterns[1].drums.append(DrumEvent(tick: 960, pad: 1))
        a = try await store.load(a.id)
        let merged = try ProjectMerge.merge(base: base, mine: a, theirs: theirs)
        #expect(merged.project.id == a.id && merged.project.patterns[1].drums.count == 2)
        let zip = root.appendingPathComponent("all.zip")
        #expect(try await store.portableBatch([a.id, b.id], to: zip) == 2)
        let entries = try ProjectArchive.decode(Data(contentsOf: zip), maxBytes: 50_000_000)
        #expect(entries.map(\.name).sorted() == ["Song (2).grillapack", "Song.grillapack"])
        #expect(try entries.allSatisfy { try PortableProject.decode($0.data).name.hasPrefix("Song") })
    }
}
