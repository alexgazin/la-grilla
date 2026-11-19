import Testing
@testable import MusicDomain

struct ArrangementOverviewTests {
    @Test func repeatsUseSameScoreAndEmptyBarsRetainTheirPlace() throws {
        let text = "Workout in D minor. Four on the floor, offbeat hats. Part A 8 bars chords A, Bb, C, D. Part B 16 bars chords D, E, F, G quieter. Return to part A."
        let brief = try TrackBrief().suggesting(text)
        let summary = try ArrangementOverview.make(brief: brief)
        #expect(summary.sections.map(\.startBar) == [0,8,24])
        #expect(summary.bars == 32 && summary.sections[2].startBar + summary.sections[2].bars == summary.bars)
        #expect(summary.sections[0].lanes == summary.sections[2].lanes)
        #expect(summary.sections[0].lanes != summary.sections[1].lanes)
        let counts = summary.sections.flatMap(\.lanes).map(\.eventCount).reduce(0,+)
        #expect(counts == Compiler.notes(try brief.makeProject(name: "Check")).count)
        #expect(summary.sections.flatMap(\.lanes).allSatisfy { $0.bins.count <= 24 && $0.bins.map(\.onsets).reduce(0,+) == $0.eventCount })
    }

    @Test func fluteBeatGongAndAmbientSilenceFollowScore() throws {
        let chill = try ArrangementOverview.make(brief: TrackBrief().suggesting(ExpressiveArrangementTests().chillhop))
        let flute = try #require(chill.tracks.firstIndex { $0.index == 3 })
        let drums = try #require(chill.tracks.firstIndex { $0.role == .drums })
        let gong = try #require(chill.tracks.firstIndex { $0.index == 5 })
        #expect(chill.sections[0].lanes[drums].bins.allSatisfy { $0.level == 0 && $0.maximumPitch == nil })
        #expect(chill.sections[0].lanes[flute].eventCount == 5)
        #expect(chill.sections[1].lanes[drums].eventCount > 0)
        #expect(chill.sections[3].startBar == 25 && chill.bars == 26)
        let ring = chill.sections[3].lanes[gong]
        #expect(ring.eventCount == 1 && ring.bins.first?.onsets == 1)
        #expect(ring.bins.allSatisfy { $0.minimumPitch == 60 && $0.level > 0 })
        let ambient = try ArrangementOverview.make(brief: TrackBrief().suggesting(ExpressiveArrangementTests().meditation))
        #expect(!ambient.tracks.contains { $0.role == .drums })
        #expect(ambient.tracks.contains { $0.index == 4 })
    }

    @Test func crossingBoundaryShowsSustainWithoutASecondAttack() throws {
        var project = Project(name: "Tie", bars: 2)
        project.sections = [Section(name: "A", length: barTicks), Section(name: "B", start: barTicks, length: barTicks)]
        project.patterns[0].chords = [ChordEvent(tick: barTicks-240, duration: 480, chord: Chord(root: 0), velocity: 73)]
        let overview = try ArrangementOverview.summarize(project)
        #expect(overview.tracks.count == 1)
        let onset = overview.sections[0].lanes[0], release = overview.sections[1].lanes[0]
        #expect(onset.eventCount == 3 && onset.bins.last?.onsets == 3)
        #expect(release.eventCount == 0 && release.bins.first?.level == 73.0/127)
        #expect(release.bins[0].minimumPitch != nil && release.bins[1].minimumPitch == nil)
    }
}
