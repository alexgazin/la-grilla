import Foundation
import Testing
@testable import MusicDomain

struct PlayingToolsTests {
    @Test func strengthAndSwingQuantize() {
        let full = GrooveQuantizer(.sixteenth)
        #expect(full.tick(250, length: barTicks) == Quantize.sixteenth.tick(250, length: barTicks))
        #expect(full.tick(barTicks - 20, length: barTicks) == 0)
        let half = GrooveQuantizer(.sixteenth, strength: 0.5)
        #expect(half.tick(200, length: barTicks) == 220)       // halfway from 200 to 240
        #expect(GrooveQuantizer(.sixteenth, strength: 0).tick(203, length: barTicks) == 203)
        let swing = GrooveQuantizer(.sixteenth, swing: 2.0 / 3.0)
        #expect(swing.gridTick(step: 1) == 320 && swing.gridTick(step: 2) == 480 && swing.gridTick(step: 3) == 800)
        #expect(swing.tick(300, length: barTicks) == 320)
        #expect(swing.tick(470, length: barTicks) == 480)
        let off = GrooveQuantizer(grid: 0)
        #expect(off.tick(5000, length: barTicks) == barTicks - 1)
    }

    @Test func grooveTemplateMovesOnlyOffSteps() {
        var pattern = Pattern(length: barTicks)
        pattern.drums = stride(from: 0, to: barTicks, by: 240).map { DrumEvent(tick: $0, pad: 2) }
        let swung = GrooveTemplate.medium.applied(to: pattern)
        #expect(swung.drums[0].tick == 0 && swung.drums[2].tick == 480)
        #expect(swung.drums[1].tick == Int((480 * 0.58).rounded()))
        #expect(GrooveTemplate.straight.applied(to: pattern) == pattern)
    }

    @Test func tapTempoAndOnsetTempo() {
        let taps = (0..<8).map { Double($0) * 0.5 + ($0 % 2 == 0 ? 0.01 : -0.012) }
        #expect(abs((TempoEstimator.fromTaps(taps) ?? 0) - 120) <= 1)
        #expect(TempoEstimator.fromTaps([0, 0.5]) == nil)
        // A 92 BPM beat with kicks, snares and hats.
        let beat = 60.0 / 92
        var onsets: [Double] = []
        for bar in 0..<4 { for step in 0..<8 { onsets.append(Double(bar * 4) * beat + Double(step) * beat / 2) } }
        #expect(abs((TempoEstimator.fromOnsets(onsets) ?? 0) - 92) <= 1.5)
    }

    @Test func latencyCalibrationRejectsOutliersAndCompensates() {
        let taps: [Double] = [118, 122, 121, 119, 120, 124, 117, 300, 121, 120, -40, 119]
        let c = RouteLatencyCalibration.estimate(taps)!
        #expect(abs(c.medianMilliseconds - 120) <= 1 && c.rejected == 2 && c.accepted == 10)
        #expect(RouteLatencyCalibration.estimate([1, 2, 3]) == nil)
        // 120 ms at 120 BPM = 230 ticks earlier; wraps inside the loop.
        #expect(c.compensated(tick: 1000, bpm: 120, length: barTicks) == 1000 - 230)
        #expect(c.compensated(tick: 100, bpm: 120, length: barTicks) == barTicks - 130)
    }

    @Test func noteRepeatLocksToTheGridWithoutEdgeDuplicates() {
        let hits = NoteRepeat.hits(from: 0, to: barTicks, rate: .sixteenth)
        #expect(hits.count == 16 && Set(hits).count == 16 && hits.last == barTicks - 240)
        #expect(NoteRepeat.hits(from: 100, to: 1000, rate: .eighth) == [480, 960])
        #expect(NoteRepeat.hits(from: 0, to: barTicks, rate: .eighthTriplet).count == 12)
        #expect(NoteRepeat.hits(from: 500, to: 500, rate: .sixteenth).isEmpty)
    }

    @Test func retroBufferKeepsTheLastBars() {
        var buffer = PadRetroBuffer(capacity: 4)
        for (i, tick) in [100, 4000, 5000, 7000, 7600].enumerated() { buffer.append(.init(tick: tick, pad: i % 2, velocity: 90)) }
        #expect(buffer.hits.map(\.tick) == [4000, 5000, 7000, 7600])
        let last = buffer.lastBars(1, endingAt: 7680)
        #expect(last.map(\.tick) == [4000 - 3840, 5000 - 3840, 7000 - 3840, 7600 - 3840])
    }

    @Test func humanizeLegatoStaccatoAreBoundedAndDeterministic() {
        let notes = [NoteEvent(tick: 0, duration: 240, pitch: 60), NoteEvent(tick: 960, duration: 240, pitch: 64), NoteEvent(tick: 1920, duration: 240, pitch: 67)]
        let ids = Set(notes.map(\.id))
        let a = NoteTools.humanize(notes, ids: ids, timing: 20, velocity: 10, seed: 7, length: barTicks)
        #expect(a == NoteTools.humanize(notes, ids: ids, timing: 20, velocity: 10, seed: 7, length: barTicks))
        #expect(zip(a, notes).allSatisfy { abs($0.tick - $1.tick) <= 20 && abs($0.velocity - $1.velocity) <= 10 && $0.tick >= 0 })
        let legato = NoteTools.legato(notes, ids: ids, length: barTicks)
        #expect(legato.map(\.duration) == [960, 960, barTicks - 1920])
        let staccato = NoteTools.staccato(legato, ids: [legato[0].id])
        #expect(staccato[0].duration == 480 && staccato[1].duration == 960)
    }

    @Test func scaleTransposeKeepsTheKey() {
        // C major: C→E (2 steps), B→D (2 steps up crosses the octave), A minor keeps A minor tones.
        let notes = [NoteEvent(tick: 0, pitch: 60), NoteEvent(tick: 0, pitch: 71)]
        let up = NoteTools.scaleTranspose(notes, ids: Set(notes.map(\.id)), steps: 2, root: 0, minor: false)
        #expect(up.map(\.pitch) == [64, 74])
        let down = NoteTools.scaleTranspose(notes, ids: Set(notes.map(\.id)), steps: -7, root: 0, minor: false)
        #expect(down.map(\.pitch) == [48, 59])
        let minor = NoteTools.scaleTranspose([NoteEvent(tick: 0, pitch: 69)], ids: [], steps: 1, root: 9, minor: true)
        #expect(minor[0].pitch == 69)
        let am = NoteTools.scaleTranspose([NoteEvent(tick: 0, pitch: 69)].map { $0 }, ids: Set([NoteEvent(tick: 0, pitch: 69)].map(\.id)), steps: 1, root: 9, minor: true)
        _ = am
        let a = NoteEvent(tick: 0, pitch: 69)
        #expect(NoteTools.scaleTranspose([a], ids: [a.id], steps: 2, root: 9, minor: true)[0].pitch == 72)
    }

    @Test func chordAwarePasteMapsChordTones() throws {
        // C E G over C → over Am becomes A C E (each tone to its chord-tone index).
        let phrase = [60, 64, 67].map { NoteEvent(tick: 0, pitch: $0) }
        let moved = NoteTools.chordAwarePaste(phrase, from: try Chord.parse("C"), to: try Chord.parse("Am"))
        #expect(moved.map(\.pitch) == [57, 60, 64])
        #expect(Set(moved.map(\.id)).isDisjoint(with: phrase.map(\.id)))
    }

    @Test func scaleKeyboardAndVoiceLedChords() {
        let pitches = ScaleKeyboard.pitches(root: 2, minor: true, low: 60, high: 72)
        #expect(pitches == [60, 62, 64, 65, 67, 69, 70, 72])
        let one = ScaleKeyboard.chord(degree: 0, root: 0, minor: false)
        #expect(one == [60, 64, 67])
        let four = ScaleKeyboard.chord(degree: 3, root: 0, minor: false, previous: one)
        #expect(Set(four.map { $0 % 12 }) == [5, 9, 0])
        #expect(zip(four, one).allSatisfy { abs($0 - $1) <= 5 })
        let seventh = ScaleKeyboard.chord(degree: 4, root: 0, minor: false, seventh: true)
        #expect(Set(seventh.map { $0 % 12 }) == [7, 11, 2, 5])
    }

    @Test func arpeggiatorPatterns() {
        let up = Arpeggiator.notes([60, 64, 67], pattern: .up, rate: 240, start: 0, duration: 960)
        #expect(up.map(\.pitch) == [60, 64, 67, 60] && up.map(\.tick) == [0, 240, 480, 720])
        let upDown = Arpeggiator.notes([60, 64, 67], pattern: .upDown, rate: 240, start: 0, duration: 960)
        #expect(upDown.map(\.pitch) == [60, 64, 67, 64])
        let down = Arpeggiator.notes([60, 64, 67], pattern: .down, rate: 240, octaves: 2, start: 100, duration: 480)
        #expect(down.map(\.pitch) == [79, 76] && down.first?.tick == 100)
        let random = Arpeggiator.notes([60, 64, 67], pattern: .random, start: 0, duration: barTicks, seed: 3)
        #expect(random.map(\.pitch) == Arpeggiator.notes([60, 64, 67], pattern: .random, start: 0, duration: barTicks, seed: 3).map(\.pitch))
        #expect(random.allSatisfy { [60, 64, 67].contains($0.pitch) })
    }

    @Test func bassFollowsKickAndChords() throws {
        let chords = [ChordEvent(tick: 0, duration: 1920, chord: try Chord.parse("Am")), ChordEvent(tick: 1920, duration: 1920, chord: try Chord.parse("F"))]
        let line = BassFromGroove.line(kicks: [0, 1440, 1920, 3360], chords: chords, length: barTicks)
        #expect(line.map(\.tick) == [0, 1440, 1920, 3360])
        #expect(line[0].pitch == 36 + 9)
        // Off-beat kick 1440 leads into F (41) by a semitone from above or below.
        #expect([40, 42].contains(line[1].pitch))
        #expect(line[2].pitch == 36 + 5)
        #expect(line.allSatisfy { $0.tick + $0.duration <= barTicks })
    }
}

struct HookGeneratorTests {
    @Test func hookStaysInKeyLandsOnChordTonesAndIsDeterministic() throws {
        let chords = try ["Am", "F", "C", "G"].enumerated().map { ChordEvent(tick: $0.offset * barTicks, chord: try Chord.parse($0.element)) }
        let hook = HookGenerator.hook(chords: chords, start: 0, bars: 4, root: 9, minor: true, seed: 5)
        let scale = Set(NoteTools.scale(root: 9, minor: true))
        #expect(!hook.isEmpty && hook.allSatisfy { scale.contains($0.pitch % 12) && (64...84).contains($0.pitch) })
        for note in hook where note.tick % (2 * ppq) == 0 {
            let chord = chords.last { $0.tick <= note.tick }!.chord
            #expect(Set(chord.effectiveIntervals.map { ($0 + chord.root) % 12 }).contains(note.pitch % 12))
        }
        #expect(hook.map(\.pitch) == HookGenerator.hook(chords: chords, start: 0, bars: 4, root: 9, minor: true, seed: 5).map(\.pitch))
        #expect(hook.allSatisfy { $0.tick + $0.duration <= 4 * barTicks })
    }

    @Test func addAMelodyByPhraseCreatesAHookTrackOnlyInThatChorus() throws {
        let p = try SongEditDemo.project()
        let plan = SongEditParser.plan("Добавь мелодию во второй припев", project: p)
        #expect(plan.isApplicable, "\(plan.problems)")
        #expect(plan.operations.first?.kind == .hook && plan.operations.first?.bars == 14..<18)
        let edited = try SongEditor.apply(plan, to: p)
        #expect(edited.tracks.count == p.tracks.count + 1)
        let hook = edited.tracks.last!
        let index = edited.tracks.count - 1
        let notes = Compiler.notes(edited).filter { $0.track == index }
        #expect(!notes.isEmpty && notes.allSatisfy { (14 * barTicks..<18 * barTicks).contains($0.tick) })
        #expect(hook.role == .melody)
        // The original parts are untouched.
        #expect(Compiler.notes(edited).filter { $0.track < p.tracks.count } == Compiler.notes(p))
    }
}

struct RetroAndVelocityTests {
    @Test func recentHitsLandInTheClipQuantizedWithOneAttackPerStep() {
        var buffer = PadRetroBuffer(capacity: 16)
        buffer.append(.init(tick: 3830, pad: 0, velocity: 90, clock: 100))      // old: before the window
        buffer.append(.init(tick: 3850, pad: 0, velocity: 80, clock: 2_000))    // clip starts at 3840
        buffer.append(.init(tick: 3860, pad: 0, velocity: 110, clock: 2_010))   // same step, louder
        buffer.append(.init(tick: 4090, pad: 2, velocity: 70, clock: 2_100))
        buffer.append(.init(tick: 9000, pad: 1, velocity: 99, clock: 2_200))    // outside the clip
        let events = buffer.events(since: 1_000, clipStart: barTicks, clipLength: barTicks, quantizer: GrooveQuantizer(.sixteenth))
        #expect(events.map(\.tick) == [0, 240] && events.map(\.pad) == [0, 2] && events[0].velocity == 110)
    }

    @Test func touchVelocityFromForceOrRadiusAndCurves() {
        #expect(PadVelocity.fromTouch(force: 0, maximumForce: 0, radius: 8) == 30)
        #expect(PadVelocity.fromTouch(force: 0, maximumForce: 0, radius: 40) == 127)
        #expect(PadVelocity.fromTouch(force: 4, maximumForce: 6.67, radius: 10) == 127)
        let mid = PadVelocity.fromTouch(force: 0, maximumForce: 0, radius: 21)
        #expect(PadVelocity.fromTouch(force: 0, maximumForce: 0, radius: 21, curve: .soft) > mid)
        #expect(PadVelocity.fromTouch(force: 0, maximumForce: 0, radius: 21, curve: .hard) < mid)
    }
}
