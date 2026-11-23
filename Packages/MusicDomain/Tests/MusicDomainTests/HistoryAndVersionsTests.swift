import Foundation
import Testing
@testable import MusicDomain

struct HistoryTimelineTests {
    @Test func jumpBackSeveralStepsIsOneActionAndRedoBringsEveryStateBack() throws {
        var project = Project.demo(), history = History()
        let start = project
        try history.apply(&project) { $0.bpm = 100 }
        try history.apply(&project) { $0.bpm = 110 }
        try history.apply(&project) { $0.bpm = 120.5 }
        #expect(history.earlierStates.map(\.bpm) == [120, 100, 110])
        let jumped = history.undo(&project, steps: 3)
        #expect(jumped)
        #expect(project.bpm == start.bpm && project.patterns == start.patterns)
        #expect(history.laterStates.map(\.bpm) == [100, 110, 120.5])
        #expect(!history.canUndo)
        let forward = history.redo(&project, steps: 2)
        #expect(forward)
        #expect(project.bpm == 110)
        history.redo(&project)
        #expect(project.bpm == 120.5)
        #expect(!history.canRedo)
    }

    @Test func jumpsOutsideTheHistoryChangeNothing() throws {
        var project = Project.demo(), history = History()
        try history.apply(&project) { $0.bpm = 90 }
        let before = project
        let tooFar = history.undo(&project, steps: 2), zero = history.redo(&project, steps: 0)
        #expect(!tooFar && !zero)
        #expect(project == before)
    }
}

struct ProjectChangesTests {
    @Test func tempoKeyAndNameAreReportedWithBeforeAndAfter() {
        let before = Project.demo()
        var after = before
        after.bpm = 92; after.keyRoot = 9; after.minor = true; after.name = "Night"
        let changes = ProjectChanges.describe(from: before, to: after)
        #expect(changes.contains(.init(area: .project, kind: .changed, from: "First light", to: "Night")))
        #expect(changes.contains(.init(area: .tempo, kind: .changed, from: "120", to: "92")))
        #expect(changes.contains { $0.area == .key && $0.kind == .changed })
    }

    @Test func oneChordEditNamesItsSongBar() {
        let before = Project.demo()
        var after = before
        after.patterns[0].chords[2].chord = Chord(root: 2, quality: .minor)
        let changes = ProjectChanges.describe(from: before, to: after)
        #expect(changes == [.init(area: .harmony, kind: .changed, subject: after.tracks[0].displayName, bar: 3, count: 1)])
    }

    @Test func addedHitsOnOnePadNameThePad() {
        let before = Project.demo()
        var after = before
        after.patterns[1].drums.append(DrumEvent(tick: barTicks + 240, pad: 4))
        let change = ProjectChanges.describe(from: before, to: after).first
        #expect(change?.area == .drums && change?.kind == .added && change?.bar == 2 && change?.count == 1)
        #expect(change?.subject == "Clap")
    }

    @Test func aRecordedTakeExplainsItsHits() {
        let before = Project.demo()
        var after = before
        let take = DrumTake(number: 1)
        var hit = DrumEvent(tick: 480, pad: 4); hit.take = take.id
        after.patterns[1].drums.append(hit); after.patterns[1].drumTakes = [take]
        #expect(ProjectChanges.describe(from: before, to: after) == [.init(area: .takes, kind: .added, subject: "1")])
        var muted = after; muted.patterns[1].drumTakes![0].muted = true
        #expect(ProjectChanges.describe(from: after, to: muted) == [.init(area: .takes, kind: .changed, subject: "1", to: "muted")])
        var deleted = after; deleted.patterns[1].drums.removeLast(); deleted.patterns[1].drumTakes = nil
        #expect(ProjectChanges.describe(from: after, to: deleted) == [.init(area: .takes, kind: .removed, subject: "1")])
    }

    @Test func mixSoundLayersSectionsAndTracksHaveTheirOwnAreas() {
        let before = Project.demo()
        var after = before
        after.tracks[1].mute = true
        after.tracks[1].mutedPads = [0]
        after.sections[0].name = "Chorus"
        after.tracks.append(Track(role: .melody))
        after.master = -6
        let changes = ProjectChanges.describe(from: before, to: after)
        #expect(changes.contains(.init(area: .mix, kind: .changed, subject: after.tracks[1].displayName)))
        #expect(changes.contains(.init(area: .layers, kind: .changed, subject: "Kick", count: 1, to: "muted")))
        #expect(changes.contains(.init(area: .structure, kind: .changed, subject: "Chorus", from: "Verse", to: "Chorus")))
        #expect(changes.contains { $0.area == .melody && $0.kind == .added })
        #expect(changes.contains(.init(area: .mix, kind: .changed)))
    }

    @Test func noChangeMeansNoRowsAndTheListIsBounded() {
        let project = Project.demo()
        #expect(ProjectChanges.describe(from: project, to: project).isEmpty)
        var after = project
        for index in 0..<4 { after.tracks.append(Track(role: .melody)); after.tracks[index].gain = -20 }
        after.bpm = 99; after.name = "X"; after.master = -9; after.keyRoot = 3
        #expect(ProjectChanges.describe(from: project, to: after).count <= ProjectChanges.limit)
    }
}

struct ProjectVersionTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("Versions-" + UUID().uuidString) }

    @Test func savedVersionLoadsAsTheSameSongNewestFirst() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        try await store.save(project)
        let first = try await store.saveVersion(project, name: "  Syncopated verse ", now: Date(timeIntervalSince1970: 1000))
        project.bpm = 96
        let second = try await store.saveVersion(project, name: "Slower", now: Date(timeIntervalSince1970: 2000))
        #expect(first.name == "Syncopated verse" && first.bars == 4 && first.bpm == 120)
        #expect(await store.versions(of: project.id).map(\.id) == [second.id, first.id])
        let loaded = try await store.loadVersion(first.id, of: project.id)
        #expect(loaded.bpm == 120 && loaded.patterns == project.patterns && loaded.id == project.id)
        // Saving the project itself leaves its versions alone.
        try await store.save(project)
        #expect(await store.versions(of: project.id).count == 2)
    }

    @Test func renameDeleteAndNamesAreChecked() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project.demo()
        try await store.save(project)
        await #expect(throws: ProjectVersionError.invalidName) { try await store.saveVersion(project, name: "   ") }
        await #expect(throws: ProjectVersionError.invalidName) { try await store.saveVersion(project, name: String(repeating: "a", count: 61)) }
        let version = try await store.saveVersion(project, name: "A")
        try await store.renameVersion(version.id, of: project.id, to: "B")
        #expect(await store.versions(of: project.id).first?.name == "B")
        try await store.deleteVersion(version.id, of: project.id)
        #expect(await store.versions(of: project.id).isEmpty)
        await #expect(throws: ProjectVersionError.missing) { try await store.loadVersion(version.id, of: project.id) }
    }

    @Test func theFiftyVersionLimitRefusesInsteadOfDroppingOld() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project(name: "Small")
        try await store.save(project)
        for index in 0..<ProjectStore.versionLimit { try await store.saveVersion(project, name: "V\(index)") }
        await #expect(throws: ProjectVersionError.limit) { try await store.saveVersion(project, name: "One more") }
        #expect(await store.versions(of: project.id).count == ProjectStore.versionLimit)
    }
}
