import Foundation
import Testing
@testable import MusicDomain

struct MusicXMLTests {
    @Test func aLeadSheetCarriesKeyTempoChordsNotesAndLyrics() throws {
        var project = Project.demo()
        try project.addMelody(name: "Voice")
        let id = project.tracks[3].clips[0].patternID
        let index = project.patterns.firstIndex { $0.id == id }!
        var a = NoteEvent(tick: 0, duration: 960, pitch: 64, velocity: 90); a.syllable = "лю-"
        var b = NoteEvent(tick: 960, duration: 960, pitch: 67, velocity: 90); b.syllable = "бовь"
        project.patterns[index].notes = [a, b]
        let xml = String(decoding: MusicXMLExporter.data(project), as: UTF8.self)
        #expect(xml.contains("<score-partwise version=\"4.0\">"))
        #expect(xml.contains("<fifths>0</fifths>") && xml.contains("<per-minute>120</per-minute>"))
        #expect(xml.contains("<root-step>A</root-step>") && xml.contains("<kind text=\"m\">minor</kind>"))
        #expect(xml.contains("<step>E</step>") && xml.contains("<syllabic>begin</syllabic><text>лю</text>"))
        #expect(xml.components(separatedBy: "<measure ").count - 1 == 4)
        #expect(xml.contains("<rehearsal>Verse</rehearsal>"))
        // Every measure adds up to a whole bar.
        for measure in xml.components(separatedBy: "<measure ").dropFirst() {
            let durations = measure.components(separatedBy: "<duration>").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
            #expect(durations.reduce(0, +) == barTicks)
        }
        #expect(MusicXMLExporter.escape("R&B <live>") == "R&amp;B &lt;live&gt;")
    }
}

struct ArrangementDoctorTests {
    @Test func aRubbingNoteAndASilentSectionAreFound() throws {
        var project = Project.demo()
        try project.addMelody(name: "Voice")
        let id = project.tracks[3].clips[0].patternID
        let index = project.patterns.firstIndex { $0.id == id }!
        // C major chord in bar 1; a long C♯ on beat one rubs against it.
        project.patterns[index].notes = [NoteEvent(tick: 0, duration: 960, pitch: 61, velocity: 90)]
        try SectionEditing.append(name: "Break", bars: 4, to: &project)
        let findings = ArrangementDoctor.check(project)
        #expect(findings.contains { $0.kind == .clashWithChord && $0.bar == 1 })
        #expect(findings.contains { $0.kind == .emptySection && $0.bar == 5 })
        #expect(ArrangementDoctor.check(Project.demo()).allSatisfy { $0.kind != .clashWithChord })
    }
}

struct DailyAndStatsTests {
    @Test func theDailyIdeaIsStableForADayAndChangesAcrossDays() {
        let day = Date(timeIntervalSince1970: 1_795_000_000)
        #expect(DailyPrompt.idea(for: day) == DailyPrompt.idea(for: day.addingTimeInterval(60)))
        let week = (0..<7).map { DailyPrompt.idea(for: day.addingTimeInterval(Double($0) * 86_400)) }
        #expect(Set(week.map(\.task)).count == 7)
        #expect(week.allSatisfy { (40...240).contains($0.bpm) && (0..<12).contains($0.keyRoot) })
    }

    @Test func statsCountMinutesKeysAndThisWeek() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func summary(_ bars: Int, _ bpm: Double, _ key: Int, _ age: Double) -> ProjectSummary {
            ProjectSummary(id: UUID(), name: "x", bpm: bpm, keyRoot: key, minor: false, bars: bars, revision: 0, modified: now.addingTimeInterval(-age), schemaVersion: 15, trackCount: 2)
        }
        let stats = CreativeStats.summarize([summary(30, 120, 0, 100), summary(60, 120, 0, 10 * 86_400), summary(8, 90, 9, 200)], now: now)
        #expect(stats.projects == 3 && stats.editedThisWeek == 2)
        #expect(stats.minutesOfMusic == 3.4)   // 1 + 2 + 0.36 minutes
        #expect(stats.favouriteKey == Project.demo().keyName && stats.averageTempo == 110)
    }

    @Test func songNamesAreDistinctAndInTheRightLanguage() {
        let en = SongNames.suggestions(keyRoot: 9, minor: true, bpm: 92, seed: 1, russian: false)
        let ru = SongNames.suggestions(keyRoot: 9, minor: true, bpm: 92, seed: 1, russian: true)
        #expect(en.count == 5 && Set(en).count == 5 && ru.count == 5)
        #expect(ru.allSatisfy { $0.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } })
    }

    @Test func earTrainingAsksAboutChordsOfTheSong() {
        let questions = EarTraining.questions(Project.demo(), count: 6, seed: 3)
        #expect(questions.count == 6)
        for question in questions {
            #expect(question.choices.count == 4 && question.choices.contains { $0.symbol == question.chord.symbol })
            #expect(Set(question.choices.map(\.symbol)).count == 4)
        }
        #expect(EarTraining.questions(Project(name: "Empty")).isEmpty)
    }
}
