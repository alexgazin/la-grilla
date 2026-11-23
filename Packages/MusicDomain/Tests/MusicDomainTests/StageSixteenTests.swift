import Foundation
import Testing
@testable import MusicDomain

struct MoodProgressionTests {
    @Test func everyMoodHasFourOptionsWithReasonsInTheKey() throws {
        for mood in Mood.allCases {
            let options = MoodProgressions.options(mood, keyRoot: 2)
            #expect(options.count == 4)
            for option in options {
                #expect(option.chords.count == 4 && !option.reason.isEmpty && !option.numerals.isEmpty)
                for chord in option.chords { try chord.validate() }
            }
        }
        let pop = MoodProgressions.options(.bright, keyRoot: 0)[0]
        #expect(pop.chords.map(\.symbol) == ["C", "G", "Am", "F"])
        #expect(MoodProgressions.events(pop, bars: 6).map(\.chord.symbol) == ["C", "G", "Am", "F", "C", "G"])
    }
}

struct EuclidTests {
    private func string(_ pattern: [Bool]) -> String { String(pattern.map { $0 ? "x" : "." }) }
    @Test func classicRhythms() {
        #expect(string(Euclid.pattern(hits: 3, steps: 8)) == "x..x..x.")
        // E(5,8) is the cinquillo up to rotation.
        let five = string(Euclid.pattern(hits: 5, steps: 8))
        #expect((0..<8).contains { shift in String((five + five).dropFirst(shift).prefix(8)) == "x.xx.xx." })
        #expect(Euclid.pattern(hits: 7, steps: 16).filter { $0 }.count == 7)
        #expect(string(Euclid.pattern(hits: 3, steps: 8, rotate: 1)) == ".x..x..x")
        #expect(Euclid.pattern(hits: 0, steps: 4) == [false, false, false, false])
        #expect(Euclid.pattern(hits: 9, steps: 4) == [true, true, true, true])
    }

    @Test func applyingReplacesOnlyThatPadInThatBar() {
        var pattern = Project.demo().patterns[1]
        let others = pattern.drums.filter { $0.pad != 0 || $0.tick >= barTicks }
        Euclid.apply(hits: 5, pad: 0, bar: 0, to: &pattern)
        #expect(pattern.drums.filter { $0.pad == 0 && $0.tick < barTicks }.count == 5)
        #expect(Set(pattern.drums.filter { $0.pad != 0 || $0.tick >= barTicks }.map(\.id)) == Set(others.map(\.id)))
    }
}

struct HarmonizerTests {
    @Test func thirdsAboveStayInTheKey() {
        let notes = [60, 62, 64, 65, 67].map { NoteEvent(tick: 0, duration: 240, pitch: $0, velocity: 90) }
        let voice = Harmonizer.secondVoice(notes, keyRoot: 0, minor: false, interval: .thirdAbove)
        #expect(voice.map(\.pitch) == [64, 65, 67, 69, 71])
        let below = Harmonizer.secondVoice(notes, keyRoot: 9, minor: true, interval: .sixthBelow)
        let scale: Set<Int> = [9, 11, 0, 2, 4, 5, 7]
        #expect(below.allSatisfy { scale.contains($0.pitch % 12) && $0.pitch < 60 })
        #expect(Set(voice.map(\.id)).isDisjoint(with: Set(notes.map(\.id))))
    }
}

struct ChordShapeTests {
    @Test func openShapesAreFoundAndSoundTheChord() throws {
        let c = try #require(ChordShapes.shape(for: Chord(root: 0), on: .guitar))
        #expect(c.frets == [-1, 3, 2, 0, 1, 0])
        let am = try #require(ChordShapes.shape(for: Chord(root: 9, quality: .minor), on: .guitar))
        #expect(am.frets == [-1, 0, 2, 2, 1, 0])
        let ukuleleC = try #require(ChordShapes.shape(for: Chord(root: 0), on: .ukulele))
        #expect(ukuleleC.frets == [0, 0, 0, 3])
        for root in 0..<12 {
            for quality in [Quality.major, .minor, .seventh] {
                let chord = Chord(root: root, quality: quality)
                if let shape = ChordShapes.shape(for: chord, on: .guitar) {
                    let tuning = ChordShapes.Instrument.guitar.tuning
                    let sounding = Set(shape.frets.enumerated().filter { $0.element >= 0 }.map { (tuning[$0.offset] + $0.element) % 12 })
                    #expect(sounding == Set(chord.notes.map { $0 % 12 }), "\(chord.symbol)")
                }
            }
        }
    }
}

struct RatchetTests {
    @Test func aRatchetRepeatsInsideItsStepAndFades() {
        let hit = DrumEvent(tick: 480, pad: 1, velocity: 100)
        let three = Ratchet.expand(hit, times: 3)
        #expect(three.map(\.tick) == [480, 560, 640])
        #expect(three.map(\.velocity) == [100, 86, 72])
        #expect(three[0].id == hit.id && Set(three.map(\.id)).count == 3)
        #expect(Ratchet.expand(hit, times: 1) == [hit])
    }
}

struct SectionTransposeTests {
    @Test func aChorusUpATwoMovesChordsAndBassButNotDrums() throws {
        var project = Project.demo()
        try project.duplicateSection(project.sections[0].id, name: "Chorus")
        let before = Compiler.notes(project)
        project.sections[1].transpose = 2
        try project.validate()
        let after = Compiler.notes(project)
        let chorusStart = project.sections[1].start
        #expect(before.count == after.count)
        for (a, b) in zip(before, after) {
            if b.tick >= chorusStart && b.pad < 0 { #expect(b.pitch == a.pitch + 2) } else { #expect(b.pitch == a.pitch) }
        }
        project.sections[1].transpose = 9
        #expect(throws: MusicError.self) { try project.validate() }
    }
}
