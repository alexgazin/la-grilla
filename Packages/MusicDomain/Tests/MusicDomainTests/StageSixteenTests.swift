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

struct EndingAndVariationTests {
    @Test func anEndingAddsOneBarOnTheHomeChordAndPlaysOnce() throws {
        var project = Project.demo(); project.keyRoot = 9; project.minor = true
        try EndingGenerator.append(to: &project)
        #expect(project.sections.last?.name == "Ending" && project.sections.last?.length == barTicks)
        #expect(project.hasComposedEnding == true)
        let last = project.sections.last!
        let chords = Arrangement.harmony(project, section: last)
        #expect(chords.map(\.chord.symbol) == ["Am"])
    }

    @Test func aVariedCopyGetsAFillAndTheSourceStaysTheSame() throws {
        var project = Project.demo()
        let source = project.sections[0].id
        let before = Compiler.notes(project, range: 0..<project.sections[0].length)
        try SectionEditing.duplicateWithVariation(source, name: "Verse 2", in: &project)
        #expect(project.sections.count == 2)
        #expect(Compiler.notes(project, range: 0..<project.sections[0].length) == before)
        let copyStart = project.sections[1].start
        let copyNotes = Compiler.notes(project, range: copyStart..<copyStart + project.sections[1].length)
        #expect(copyNotes.count > before.count)
    }
}

struct ChanceAndRatchetCompileTests {
    @Test func chanceStepsPlayAboutAsOftenAsSetAndTheSameEveryTime() throws {
        var project = Project(name: "Chance", bars: 1)
        project.tracks[1].clips[0].length = 64 * barTicks   // 64 passes of a one-bar beat
        project.sections[0].length = 64 * barTicks
        project.patterns[0].length = barTicks
        project.tracks[0].clips[0].length = 64 * barTicks
        var hit = DrumEvent(tick: 0, pad: 1); hit.probability = 50
        project.patterns[1].drums = [hit]
        try project.validate()
        let first = Compiler.notes(project).filter { $0.pad == 1 }.map(\.tick)
        #expect(first == Compiler.notes(project).filter { $0.pad == 1 }.map(\.tick))
        #expect((20...44).contains(first.count), "\(first.count) of 64")
    }

    @Test func ratchetsCompileToRepeatedFadingHits() throws {
        var project = Project(name: "Ratchet", bars: 1)
        var hit = DrumEvent(tick: 480, pad: 2, velocity: 100); hit.ratchet = 4
        project.patterns[1].drums = [hit]
        try project.validate()
        let notes = Compiler.notes(project).filter { $0.pad == 2 }
        #expect(notes.map(\.tick) == [480, 540, 600, 660])
        #expect(notes.map(\.velocity) == [100, 86, 72, 58])
        hit.ratchet = 7; project.patterns[1].drums = [hit]
        #expect(throws: MusicError.self) { try project.validate() }
    }
}

struct ContinueIdeaTests {
    @Test func theContinuationVariesTheLastChordAndKeepsTheSource() throws {
        var project = Project.demo()
        let before = project.patterns[0].chords.map(\.chord.symbol)
        try ContinueIdea.extend(project.sections[0].id, name: "Continuation", in: &project)
        #expect(project.sections.map(\.name) == ["Verse", "Continuation"])
        #expect(project.patterns[0].chords.map(\.chord.symbol) == before)
        let continued = Arrangement.harmony(project, section: project.sections[1]).map(\.chord.symbol)
        #expect(continued.prefix(3) == before.prefix(3) && continued.last == "Em")   // G (V) → Em (iii)
        #expect(ContinueIdea.relative(of: Chord(root: 9, quality: .minor), keyRoot: 0, minor: false).symbol == "C")
    }
}
