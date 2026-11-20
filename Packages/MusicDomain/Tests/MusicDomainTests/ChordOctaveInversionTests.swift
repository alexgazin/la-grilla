import Testing
import Foundation
@testable import MusicDomain

@Suite struct ChordOctaveInversionTests {
    private func shift(_ chord: inout Chord, _ octaves: Int) -> Bool { chord.shiftOctave(by: octaves) }

    @Test func inversionMovesTheBassAndTheWrittenSymbol() throws {
        var chord = Chord(root: 0, quality: .major)
        #expect(chord.notes == [60, 64, 67])
        chord.inversion = 1
        try chord.validate()
        #expect(chord.notes == [64, 67, 72])
        #expect(chord.bassPitchClass == 4)
        #expect(Compiler.bassPitch(for: chord, register: 0) % 12 == 4)
        #expect(MusicalNotation.chordSymbol(chord, keyRoot: 0, minor: false) == "C/E")
        chord.inversion = 2
        #expect(chord.bassPitchClass == 7)
        #expect(MusicalNotation.chordSymbol(chord, keyRoot: 0, minor: false) == "C/G")
    }

    @Test func compiledBassFollowsTheInversion() throws {
        var project = Project.demo()
        guard let h = project.patterns.firstIndex(where: { !$0.chords.isEmpty }) else { return }
        project.patterns[h].chords[0].chord.inversion = 1
        project.patterns[h].chords[0].chord.voicedNotes = nil
        project.patterns[h].chords[0].chord.rootBassPitch = nil
        let chord = project.patterns[h].chords[0].chord
        #expect(Compiler.bassPitch(for: chord, register: project.bassOctave) % 12 == chord.bassPitchClass)
    }

    @Test func octaveShiftsTheWholeChordWithinRange() throws {
        var chord = Chord(root: 9, quality: .minor)
        let before = chord.notes
        #expect(shift(&chord, 1))
        #expect(chord.notes == before.map { $0 + 12 })
        try chord.validate()
        #expect(shift(&chord, -2))
        #expect(chord.notes == before.map { $0 - 12 })
        #expect(shift(&chord, -1))
        #expect(!shift(&chord, -1))   // −2 is the floor
        #expect(chord.octave == -2)
        #expect(shift(&chord, 2))
        #expect(chord.octave == nil)
    }

    @Test func octaveMovesAnExplicitVoicing() {
        var chord = Chord(root: 0, quality: .major, voicedNotes: [52, 60, 67])
        #expect(shift(&chord, 1))
        #expect(chord.voicedNotes == [64, 72, 79])
        var high = Chord(root: 0, quality: .major, voicedNotes: [120, 124, 127])
        #expect(!shift(&high, 1))
        #expect(high.voicedNotes == [120, 124, 127])
    }

    @Test func octaveSurvivesCoding() throws {
        var chord = Chord(root: 2, quality: .m7)
        chord.shiftOctave(by: -1)
        let data = try JSONEncoder().encode(chord)
        #expect(try JSONDecoder().decode(Chord.self, from: data) == chord)
        let legacy = try JSONEncoder().encode(Chord(root: 2, quality: .m7))
        #expect(!String(decoding: legacy, as: UTF8.self).contains("octave"))
    }
}
