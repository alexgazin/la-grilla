import Foundation
import Testing
@testable import MusicDomain

private func emptyProject(bpm: Double = 120, bars: Int = 8, root: Int = 2, minor: Bool = true) throws -> Project {
    try ProjectTemplates.make(name: "New", bpm: bpm, root: root, minor: minor, bars: bars, template: .empty)
}

@Suite("54 · Track in a minute")
struct QuickTrackTests {
    @Test func everyGenreMakesAVerseAndChorusWithBeatChordsAndMelody() throws {
        for genre in BeatPreset.Genre.allCases {
            let base = try emptyProject(bpm: QuickTrack.tempo(for: genre, seed: 0), bars: QuickTrack.sectionBars)
            let result = try QuickTrack.make(from: base, genre: genre, seed: 0)
            let song = result.project
            #expect(song.id == base.id, "\(genre): one undoable edit of the new project")
            #expect(song.sections.map(\.name) == ["Verse", "Chorus"], "\(genre)")
            #expect(song.length == 2 * QuickTrack.sectionBars * barTicks, "\(genre)")
            let preset = try #require(QuickTrack.preset(for: genre, seed: 0))
            #expect(song.bpm == Double(preset.bpm), "\(genre): the genre's tempo")
            let notes = Compiler.notes(song)
            let roles = Set(notes.map { song.tracks[$0.track].role })
            #expect(roles.contains(.harmony), "\(genre): chords")
            #expect(notes.contains { $0.pad >= 0 }, "\(genre): drums")
            #expect(roles.contains(.melody), "\(genre): a melody")
            // Both sections sound.
            #expect(notes.contains { $0.tick < QuickTrack.sectionBars * barTicks } && notes.contains { $0.tick >= QuickTrack.sectionBars * barTicks }, "\(genre)")
            #expect(result.sounds.filter { $0.pad >= 0 }.count == 16, "\(genre): a full kit")
            if preset.bass != nil { #expect(result.sounds.contains { $0.pad == -1 }, "\(genre): the 808 sound") }
        }
    }

    @Test func theSameSeedRepeatsAndAnotherSeedChangesTheTrack() throws {
        let base = try emptyProject(bpm: QuickTrack.tempo(for: .trap, seed: 3), bars: QuickTrack.sectionBars)
        let first = try QuickTrack.make(from: base, genre: .trap, seed: 3).project
        let again = try QuickTrack.make(from: base, genre: .trap, seed: 3).project
        let other = try QuickTrack.make(from: try emptyProject(bpm: QuickTrack.tempo(for: .trap, seed: 4), bars: QuickTrack.sectionBars), genre: .trap, seed: 4).project
        #expect(Compiler.notes(first) == Compiler.notes(again))
        #expect(Compiler.notes(first) != Compiler.notes(other))
    }

    @Test func styleFollowsTheGenreFamily() {
        #expect(QuickTrack.style(for: .drill) == .hipHop)
        #expect(QuickTrack.style(for: .techno) == .house)
        #expect(QuickTrack.style(for: .jazz) == .jazz)
    }

    @Test func aNonEmptyProjectIsRefused() throws {
        let base = try ProjectTemplates.make(name: "Busy", bpm: 120, root: 0, minor: false, bars: QuickTrack.sectionBars, template: .starter)
        #expect(throws: (any Error).self) { try QuickTrack.make(from: base, genre: .house, seed: 0) }
    }
}

@Suite("54 · Social clip")
struct ShareClipTests {
    private func song(bars: Int, chorusAt: Int?) throws -> Project {
        var project = try emptyProject(bpm: 120, bars: bars)
        if let chorusAt {
            let length = bars * barTicks
            project.sections = [Section(name: "Verse", length: chorusAt * barTicks),
                                Section(name: "Chorus", start: chorusAt * barTicks, length: length - chorusAt * barTicks)]
        }
        return project
    }

    @Test func aClipStartsAtTheChorusInWholeBars() throws {
        let project = try song(bars: 32, chorusAt: 8)
        let range = ShareClip.range(project, length: .short)
        // 15 s at 120 BPM is 7.5 bars, so 8 whole bars from the chorus.
        #expect(range == 8 * barTicks..<16 * barTicks)
        #expect(abs(ShareClip.seconds(project, range: range) - 16) < 0.001)
    }

    @Test func aClipNeverRunsPastTheEndAndMovesBackInstead() throws {
        let project = try song(bars: 20, chorusAt: 16)
        let range = ShareClip.range(project, length: .medium)
        #expect(range.upperBound == project.length)
        #expect(range.count == 15 * barTicks)
    }

    @Test func aShortSongIsWholeAndWholeMeansEverything() throws {
        let project = try song(bars: 8, chorusAt: nil)
        #expect(ShareClip.range(project, length: .long) == 0..<project.length)
        #expect(ShareClip.range(project, length: .whole) == 0..<project.length)
    }
}

@Suite("54 · Video styles")
struct VideoActivityTests {
    @Test func padsLightOnTheirHitsAndFade() throws {
        var project = try emptyProject(bpm: 120, bars: 1)
        let drums = try #require(project.tracks.firstIndex { $0.role == .drums })
        let pattern = try #require(project.patterns.firstIndex { $0.id == project.tracks[drums].clips.first?.patternID })
        project.patterns[pattern].drums = [DrumEvent(tick: 0, pad: 0, velocity: 127), DrumEvent(tick: ppq, pad: 1, velocity: 64)]
        let board = VideoStoryboard(project: project, range: 0..<project.length, seconds: 2, fps: 30)
        #expect((board.pads(frame: 0)[0] ?? 0) > 0.9)
        #expect(board.pads(frame: 0)[1] == nil)
        // 120 BPM: a beat is 0.5 s = 15 frames; the snare lights there, the kick has faded.
        #expect(board.pads(frame: 15)[0] == nil)
        #expect((board.pads(frame: 15)[1] ?? 0) > 0.4)
    }

    @Test func levelsRiseWhileATrackPlays() throws {
        var project = try emptyProject(bpm: 120, bars: 1)
        let harmony = try #require(project.tracks.firstIndex { $0.role == .harmony })
        let pattern = try #require(project.patterns.firstIndex { $0.id == project.tracks[harmony].clips.first?.patternID })
        project.patterns[pattern].chords = [ChordEvent(tick: 0, duration: ppq, chord: Chord(root: 0))]
        let board = VideoStoryboard(project: project, range: 0..<project.length, seconds: 2, fps: 30)
        #expect(board.levels(frame: 1)[harmony] > 0.5)
        #expect(board.levels(frame: 40)[harmony] == 0)
        #expect(board.trackCount == project.tracks.count)
    }
}
