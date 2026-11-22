import Foundation
import Testing
@testable import MusicDomain

@Suite struct DrumTakesTests {
    /// Demo beat (programmed), then a recorded take on top, merged like the app does on Stop.
    private func recorded(_ project: Project, hits: [DrumEvent]) throws -> (Project, UUID) {
        let track = try #require(project.tracks.first { $0.role == .drums })
        let clip = try #require(track.clips.first)
        var draft = try DrumRecordingDraft(project: project, clipID: clip.id)
        try draft.commitPass(hits)
        return (try draft.candidate(for: project), draft.takeID)
    }
    private func drumPattern(_ p: Project) throws -> Pattern {
        let clip = try #require(p.tracks.first { $0.role == .drums }?.clips.first)
        return try #require(p.patterns.first { $0.id == clip.patternID })
    }

    @Test func aRecordedTakeStaysSeparateFromTheProgrammedBeat() throws {
        let original = Project.demo()
        let programmed = try drumPattern(original).drums.count
        let (project, takeID) = try recorded(original, hits: [DrumEvent(tick: 240, pad: 4), DrumEvent(tick: 1200, pad: 4)])
        let pattern = try drumPattern(project)
        #expect(DrumTakes.programmedHits(in: pattern) == programmed)
        let takes = DrumTakes.takes(in: pattern)
        #expect(takes.map(\.number) == [1])
        #expect(takes.first?.id == takeID)
        #expect(takes.first?.hits == 2)
        try project.validate()
    }

    @Test func deletingOrMutingTheTakeLeavesWhatWasThere() throws {
        let original = Project.demo()
        let before = try drumPattern(original).drums.map { [$0.tick, $0.pad, $0.velocity] }
        var (project, takeID) = try recorded(original, hits: [DrumEvent(tick: 240, pad: 4)])
        let d = try #require(project.tracks.firstIndex { $0.role == .drums })
        let clipPattern = try drumPattern(project).id
        let p = try #require(project.patterns.firstIndex { $0.id == clipPattern })
        DrumTakes.setMuted(&project.patterns[p], take: takeID, muted: true)
        #expect(Compiler.notes(project).filter { $0.track == d && $0.pad == 4 }.isEmpty)
        #expect(Compiler.notes(project).filter { $0.track == d && $0.pad == 0 }.count > 0)
        let removed = DrumTakes.delete(&project.patterns[p], take: takeID)
        #expect(removed == 1)
        #expect(project.patterns[p].drumTakes == nil)
        #expect(project.patterns[p].drums.map { [$0.tick, $0.pad, $0.velocity] } == before)
        try project.validate()
    }

    @Test func keepMergesTheTakeAndTakesSurviveTheNextRecording() throws {
        let (first, firstTake) = try recorded(Project.demo(), hits: [DrumEvent(tick: 240, pad: 4)])
        // A second recording rebuilds the clip pattern; the first take must stay separable.
        let (second, secondTake) = try recorded(first, hits: [DrumEvent(tick: 720, pad: 5)])
        var pattern = try drumPattern(second)
        #expect(DrumTakes.takes(in: pattern).map(\.number) == [1, 2])
        #expect(DrumTakes.latest(in: pattern)?.id == secondTake)
        DrumTakes.keep(&pattern, take: firstTake)
        #expect(DrumTakes.takes(in: pattern).map(\.id) == [secondTake])
        #expect(pattern.drums.contains { $0.pad == 4 && $0.take == nil })
    }

    @Test func undoingEveryPassUnlistsTheTake() throws {
        let project = Project.demo()
        let clip = try #require(project.tracks.first { $0.role == .drums }?.clips.first)
        var draft = try DrumRecordingDraft(project: project, clipID: clip.id)
        try draft.commitPass([DrumEvent(tick: 240, pad: 4)])
        let undone = draft.undoLastPass()
        #expect(undone)
        let pattern = try #require(draft.project.patterns.first { $0.id == draft.patternID })
        #expect(pattern.drumTakes == nil)
        #expect(!pattern.drums.contains { $0.take == draft.takeID })
    }

    @Test func olderFilesDecodeWithoutTakes() throws {
        let legacy = try JSONEncoder().encode(Pattern(length: barTicks, drums: [DrumEvent(tick: 0, pad: 0)]))
        let text = String(decoding: legacy, as: UTF8.self)
        #expect(!text.contains("drumTakes") && !text.contains("\"take\""))
        let decoded = try JSONDecoder().decode(Pattern.self, from: legacy)
        #expect(decoded.drumTakes == nil && decoded.drums.first?.take == nil)
    }
}

@Suite struct DrumTakesPruneTests {
    @Test func clearingALayerDropsATakeThatLostAllItsHits() {
        var p = Pattern(length: barTicks)
        let take = DrumTake(number: 1)
        var hit = DrumEvent(tick: 240, pad: 4); hit.take = take.id
        p.drums = [DrumEvent(tick: 0, pad: 0), hit]; p.drumTakes = [take]
        DrumLayers.clear(&p, pad: 4)
        #expect(p.drumTakes == nil)
        #expect(p.drums.count == 1)
    }
}
