import Foundation
import Testing
@testable import MusicDomain

struct MusicalPositionTests {
    @Test func quarterBeatsAndFractionalBeatsHaveDistinctExactPositions() {
        // A sixteenth advances the tick component, not the quarter-note beat.
        let fixtures: [(Int, String)] = [
            (0, "1:1"), (1, "1:1:1"), (240, "1:1:240"),
            (959, "1:1:959"), (960, "1:2"), (1200, "1:2:240"),
            (2880, "1:4"), (3600, "1:4:720"), (3839, "1:4:959"),
            (3840, "2:1"), (3841, "2:1:1"), (7747, "3:1:67")
        ]
        for (tick, expected) in fixtures {
            #expect(MusicalPosition(tick: tick).description == expected)
        }
    }

    @Test func arbitraryLegacyClipPositionsRemainExactAfterReopening() throws {
        var project = Project(name: "Unsnapped clip", bars: 4)
        project.tracks[0].clips[0].start = 961
        project.tracks[0].clips[0].length = 2640
        project.tracks[0].clips[0].offset = 1279
        try project.validate()
        let reopened = try ProjectDocument.decode(JSONEncoder().encode(project))
        let clip = try #require(reopened.tracks[0].clips.first)
        #expect(MusicalPosition(tick: clip.start).description == "1:2:1")
        #expect(MusicalPosition(tick: clip.start + clip.length).description == "1:4:721")
        #expect(MusicalPosition(tick: clip.offset).description == "1:2:319")
        #expect(clip.start == 961 && clip.length == 2640 && clip.offset == 1279)
    }

    @Test func decompositionIsLosslessAcrossTheSupportedTimeline() {
        // Covers every possible remainder, all bar boundaries, and the end
        // marker of the maximum song; no quantization is allowed by display.
        for tick in 0...64 * barTicks {
            let position = MusicalPosition(tick: tick)
            let recovered = (position.bar - 1) * barTicks + (position.beat - 1) * ppq + position.tickWithinBeat
            #expect(recovered == tick)
            #expect((1...4).contains(position.beat))
            #expect((0..<960).contains(position.tickWithinBeat))
        }
        #expect(MusicalPosition(tick: -1).description == "1:1")
        // Formatting itself also accepts a large external display input.
        #expect(MusicalPosition(tick: Int.max).tickWithinBeat == Int.max % ppq)
    }
}
