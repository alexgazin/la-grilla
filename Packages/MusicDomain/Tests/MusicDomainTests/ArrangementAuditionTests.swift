import Testing
@testable import MusicDomain

struct ArrangementAuditionTests {
    @Test(arguments: [ExpressiveBriefTests.chillhop, SongFormBriefTests().workout, ExpressiveBriefTests.ambient])
    func comparePerformancesWithoutChangingTheAuthorsForm(_ text: String) throws {
        let original = try TrackBrief().suggesting(text)
        let alternate = ArrangementAudition.select(.b, in: original)
        #expect(ArrangementAudition.take(in: alternate) == .b)
        #expect(ArrangementAudition.select(.b, in: alternate) == alternate)
        #expect(alternate.songForm == original.songForm)
        let first = try original.makeProject(name: "A")
        let second = try alternate.makeProject(name: "B", sourcePrompt: text)
        #expect(first.bpm == second.bpm && first.keyRoot == second.keyRoot && first.minor == second.minor)
        #expect(first.sections.map(\.name) == second.sections.map(\.name))
        #expect(first.sections.map(\.length) == second.sections.map(\.length))
        #expect(first.patterns.flatMap(\.chords).map(\.chord.symbol) == second.patterns.flatMap(\.chords).map(\.chord.symbol))
        let notesA = Compiler.notes(first)
        let notesB = Compiler.notes(second)
        #expect(notesA != notesB)
        // The workout's final A still references the identical original performance on every track.
        if alternate.songForm?.arrangement == .groove {
            #expect(second.tracks.allSatisfy { $0.clips.first?.patternID == $0.clips.last?.patternID })
        }
        let reopened = try PortableProject.decode(PortableProject.data(second), asCopy: false)
        let committed = try #require(reopened.arrangementRecipe?.brief)
        #expect(ArrangementAudition.take(in: committed) == .b)
        #expect(try Compiler.notes(committed.makeProject(name: "Reopened B")) == notesB)
        let restored = ArrangementAudition.select(.a, in: committed)
        #expect(restored == original)
        #expect(try Compiler.notes(restored.makeProject(name: "Restored A")) == notesA)
    }

    @Test func anySeedCanReturnToAAndEditsSurviveTakeChanges() throws {
        var brief = try TrackBrief().suggesting(ExpressiveBriefTests.ambient)
        brief.seed = .max
        var selected = ArrangementAudition.select(.b, in: brief)
        selected.songForm?.parts[0].chordText = "F G Ab Dm"
        let restored = ArrangementAudition.select(.a, in: selected)
        #expect(restored.seed == UInt32.max)
        #expect(restored.songForm?.resolvedChordText(for: 2) == "F G Ab Dm")
        #expect(ArrangementAudition.select(.b, in: TrackBrief()) == TrackBrief())
    }
}
