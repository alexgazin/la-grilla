import Foundation
import Testing
@testable import MusicDomain

struct ProjectNamingAndOrderingTests {
    @Test func defaultNamesSayKeyTempoAndDay() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)   // a Tuesday in 2026 (UTC)
        let en = ProjectNaming.suggest(keyRoot: 9, minor: true, bpm: 92, date: date, locale: Locale(identifier: "en_US"))
        #expect(en.hasPrefix("A minor · 92 · "))
        let ru = ProjectNaming.suggest(keyRoot: 9, minor: true, bpm: 92, date: date, locale: Locale(identifier: "ru_RU"))
        #expect(ru.hasPrefix("Ля минор · 92 · "))
    }

    private func summary(_ name: String, bpm: Double, key: Int, minor: Bool, age: Double) -> ProjectSummary {
        ProjectSummary(id: UUID(), name: name, bpm: bpm, keyRoot: key, minor: minor, bars: 4, revision: 0,
                       modified: Date(timeIntervalSince1970: 1_000_000 - age), schemaVersion: 15, trackCount: 2)
    }

    @Test func orderingPinsFirstAndFiltersByWords() {
        let a = summary("Beta", bpm: 120, key: 0, minor: false, age: 10)
        let b = summary("alpha", bpm: 90, key: 9, minor: true, age: 20)
        let c = summary("Gamma", bpm: 100, key: 2, minor: false, age: 5)
        #expect(ProjectOrdering.modified.sorted([a, b, c]).map(\.name) == ["Gamma", "Beta", "alpha"])
        #expect(ProjectOrdering.name.sorted([a, b, c]).map(\.name) == ["alpha", "Beta", "Gamma"])
        #expect(ProjectOrdering.tempo.sorted([a, b, c]).map(\.name) == ["alpha", "Gamma", "Beta"])
        #expect(ProjectOrdering.name.sorted([a, b, c], pinned: [c.id]).map(\.name) == ["Gamma", "alpha", "Beta"])
        #expect(ProjectOrdering.filter([a, b, c], query: "90").map(\.name) == ["alpha"])
        #expect(ProjectOrdering.filter([a, b, c], query: "ga").map(\.name) == ["Gamma"])
    }
}

struct MusicClipboardTests {
    @Test func chordsCopiedFromCMajorPasteInAMinorByTheShortestStep() throws {
        let source = Project.demo()
        let copied = try #require(MusicClipboard.copy(.chords, section: source.sections[0], from: source))
        #expect(copied.chords.count == 4)
        var target = Project(name: "Target"); target.keyRoot = 2
        try copied.paste(into: target.sections[0], project: &target)
        #expect(target.patterns[0].chords.map(\.chord.root) == [2, 11, 7, 9])
        var kept = Project(name: "Kept"); kept.keyRoot = 2
        try copied.paste(into: kept.sections[0], project: &kept, keepKey: true)
        #expect(kept.patterns[0].chords.map(\.chord.root) == [0, 9, 5, 7])
    }

    @Test func aOneBarBeatRepeatsAcrossALongerSectionAndRoundTripsThroughJSON() throws {
        var source = Project(name: "One bar", bars: 1)
        source.patterns[1].drums = [DrumEvent(tick: 0, pad: 0), DrumEvent(tick: 960, pad: 1)]
        let copied = try #require(MusicClipboard.copy(.beat, section: source.sections[0], from: source))
        let decoded = try JSONDecoder().decode(MusicClipboard.self, from: JSONEncoder().encode(copied))
        #expect(decoded == copied)
        var target = Project(name: "Four bars", bars: 4)
        try decoded.paste(into: target.sections[0], project: &target)
        #expect(target.patterns[1].drums.count == 8)
        #expect(Set(target.patterns[1].drums.map(\.id)).count == 8)
        #expect(MusicClipboard.copy(.melody, section: source.sections[0], from: source) == nil)
    }
}

struct SolfegeTests {
    @Test func notesReadAsSolfegeWhileChordsKeepLetters() {
        #expect(MusicalNotation.pitchClassName(9, keyRoot: 0, minor: false, spelling: .solfege) == "La")
        #expect(MusicalNotation.pitchClassName(10, keyRoot: 5, minor: false, spelling: .solfege) == "Si♭")
        #expect(MusicalNotation.noteName(60, keyRoot: 0, minor: false, spelling: .solfege) == "Do4")
        #expect(MusicalNotation.noteName(71, keyRoot: 7, minor: false, spelling: .solfege) == "Si4")
        #expect(MusicalNotation.chordSymbol(Chord(root: 9, quality: .m7), keyRoot: 0, minor: false, spelling: .solfege) == "Am7")
    }
}

struct NextStepTests {
    @Test func suggestionsFollowWhatTheSongHas() throws {
        var project = Project(name: "Blank")
        #expect(NextStepAdvisor.suggest(project)?.command == .jam)
        project.patterns[1].drums = [DrumEvent(tick: 0, pad: 0)]
        #expect(NextStepAdvisor.suggest(project)?.command == .chordImport)
        project.patterns[0].chords = [ChordEvent(tick: 0, chord: Chord(root: 0))]
        #expect(NextStepAdvisor.suggest(project)?.command == .voice)
        try project.addMelody()
        let id = project.tracks[2].clips[0].patternID
        project.patterns[project.patterns.firstIndex { $0.id == id }!].notes = [NoteEvent(tick: 0, duration: 480, pitch: 64, velocity: 90)]
        #expect(NextStepAdvisor.suggest(project)?.command == .addSection)
        try project.duplicateSection(project.sections[0].id, name: "Chorus")
        #expect(NextStepAdvisor.suggest(project)?.command == .lyrics)
        project.sections[0].lyrics = "la la"
        #expect(NextStepAdvisor.suggest(project)?.command == .master)
    }

    @Test func practiceSlowsWithinTheTempoLimits() {
        var song = Project.demo(); song.bpm = 60
        #expect(Practice.slowed(song, rate: 0.75).bpm == 45)
        #expect(Practice.slowed(song, rate: 0.5).bpm == 40)
        #expect(Practice.slowed(song, rate: 0.5).patterns == song.patterns)
    }
}

struct PadSwapAndWhatsNewTests {
    @Test func swappingPadsMovesHitsAndMuteAndIsReversible() throws {
        var project = Project.demo()
        let drums = project.tracks[1].id
        project.tracks[1].mutedPads = [0]
        let kicks = project.patterns[1].drums.filter { $0.pad == 0 }.map(\.tick)
        try PadEditing.swap(0, 4, track: drums, in: &project)
        #expect(project.patterns[1].drums.filter { $0.pad == 4 }.map(\.tick) == kicks)
        #expect(project.patterns[1].drums.filter { $0.pad == 0 }.isEmpty)
        #expect(project.tracks[1].mutedPads == [4])
        try PadEditing.swap(4, 0, track: drums, in: &project)
        #expect(project.patterns[1].drums.filter { $0.pad == 0 }.map(\.tick) == kicks)
        #expect(throws: MusicError.self) { try PadEditing.swap(0, 0, track: drums, in: &project) }
    }

    @Test func whatsNewShowsOnlyAfterAnUpdate() {
        #expect(!WhatsNew.shouldShow(lastShownBuild: nil, currentBuild: "51"))
        #expect(WhatsNew.shouldShow(lastShownBuild: "50", currentBuild: "51"))
        #expect(!WhatsNew.shouldShow(lastShownBuild: "51", currentBuild: "51"))
        #expect(WhatsNew.items.count >= 4)
    }

    @Test func storageCountsFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data(count: 1000).write(to: folder.appendingPathComponent("a/x.bin"))
        try Data(count: 500).write(to: folder.appendingPathComponent("y.bin"))
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(StorageUsage.bytes(of: folder) == 1500)
        #expect(StorageUsage.bytes(of: folder.appendingPathComponent("missing")) == 0)
    }
}
