import Foundation
import Testing
@testable import MusicDomain

/// Build 55: arpeggiator to MIDI, FM and analog sounds, classic drum machine kits, natural or
/// on-the-grid timing for takes and phrases.
struct ArpeggioSettingsTests {
    @Test func ratesFollowTheGridWithTripletsAndKernelModesMatch() throws {
        #expect(ArpeggioSettings.Rate.allCases.map(\.rawValue) == [960, 480, 320, 240, 160, 120])
        #expect(ArpeggioSettings.Rate.allCases.map(\.label) == ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32"])
        #expect(ArpeggioSettings.Rate.allCases.filter(\.isTriplet) == [.eighthTriplet, .sixteenthTriplet])
        #expect(Arpeggiator.Pattern.allCases.map(\.kernelMode) == [0, 1, 2, 3, 5])
        #expect(ArpPattern.kernelMode == 4, "My pattern keeps its own kernel mode")
        try ArpeggioSettings(octaves: 3, gate: 1).validate()
        #expect(throws: MusicError.self) { try ArpeggioSettings(octaves: 4).validate() }
        #expect(throws: MusicError.self) { try ArpeggioSettings(gate: 0.05).validate() }
        let data = try JSONEncoder().encode(ArpeggioSettings(direction: .random, rate: .sixteenthTriplet, octaves: 2, gate: 0.5))
        #expect(try JSONDecoder().decode(ArpeggioSettings.self, from: data) == ArpeggioSettings(direction: .random, rate: .sixteenthTriplet, octaves: 2, gate: 0.5))
    }

    @Test func heldNotesGroupIntoBlocksThatEndAtTheNextChord() {
        let notes = [(tick: 0, duration: 3840, pitch: 64), (tick: 10, duration: 3840, pitch: 60), (tick: 30, duration: 3840, pitch: 67),
                     (tick: 3840, duration: 1920, pitch: 62), (tick: 3840, duration: 1920, pitch: 65)]
        let blocks = ArpeggioRender.blocks(notes)
        #expect(blocks.count == 2)
        #expect(blocks[0] == ArpeggioRender.Block(start: 0, end: 3840, pitches: [64, 60, 67]), "As written, chord held until the next one")
        #expect(blocks[1] == ArpeggioRender.Block(start: 3840, end: 5760, pitches: [62, 65]))
    }

    @Test func upOverTwoOctavesAtSixteenthsWithGate() {
        let block = ArpeggioRender.Block(start: 0, end: 3840, pitches: [60, 64, 67])
        let notes = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .up, rate: .sixteenth, octaves: 2, gate: 0.5))
        #expect(notes.count == 16)
        #expect(notes.prefix(7).map(\.pitch) == [60, 64, 67, 72, 76, 79, 60])
        #expect(notes.allSatisfy { $0.tick % 240 == 0 && $0.duration == 120 })
        let down = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .down, rate: .eighth, octaves: 1, gate: 1))
        #expect(down.map(\.pitch) == [67, 64, 60, 67, 64, 60, 67, 64] && down.allSatisfy { $0.duration == 480 })
        let upDown = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .upDown, rate: .quarter))
        #expect(upDown.map(\.pitch) == [60, 64, 67, 64])
    }

    @Test func tripletsRandomAndAsPlayed() {
        let block = ArpeggioRender.Block(start: 0, end: 3840, pitches: [64, 60, 67])
        let triplets = ArpeggioRender.notes([block], settings: ArpeggioSettings(rate: .eighthTriplet))
        #expect(triplets.count == 12 && triplets.allSatisfy { $0.tick % 320 == 0 })
        let played = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .asPlayed, rate: .quarter))
        #expect(played.map(\.pitch) == [64, 60, 67, 64])
        let random = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .random, rate: .sixteenth, octaves: 2), seed: 7)
        let again = ArpeggioRender.notes([block], settings: ArpeggioSettings(direction: .random, rate: .sixteenth, octaves: 2), seed: 7)
        #expect(random.map(\.pitch) == again.map(\.pitch), "The same seed gives the same order")
        #expect(Set(random.map(\.pitch)).isSubset(of: [60, 64, 67, 72, 76, 79]))
        #expect(random.map(\.pitch) != random.map(\.pitch).sorted(), "Random is not simply ascending")
    }
}

struct ArpeggioToolTests {
    @Test func chordsBecomeANewTrackOfEditableNotesInOneEdit() throws {
        var project = Project.demo()
        let harmony = project.tracks[0].id
        let before = Compiler.notes(project).filter { $0.track == 0 }
        let request = ArpeggioTool.Request(trackID: harmony, settings: ArpeggioSettings(direction: .up, rate: .sixteenth, octaves: 1, gate: 0.8))
        let expected = ArpeggioTool.render(project, request)
        #expect(expected.count == 64, "Four bars of sixteenths")
        let id = try ArpeggioTool.apply(request, to: &project)
        let track = try #require(project.tracks.first { $0.id == id })
        #expect(track.role == .melody && track.displayName.contains("Arpeggio"))
        #expect(track.synth != nil, "A plucky built-in sound until another is chosen")
        let index = try #require(project.tracks.firstIndex { $0.id == id })
        let written = Compiler.notes(project).filter { $0.track == index }
        #expect(written.map(\.tick) == expected.map(\.tick) && written.map(\.pitch) == expected.map(\.pitch))
        #expect(Compiler.notes(project).filter { $0.track == 0 } == before, "The chords keep playing")
        try project.validate()
    }

    @Test func aSectionOnlyAndSilencingTheChords() throws {
        var project = Project.demo()
        let harmony = project.tracks[0].id
        let section = project.sections[0]
        let request = ArpeggioTool.Request(trackID: harmony, range: section.start..<(section.start + barTicks),
                                           settings: ArpeggioSettings(rate: .eighth), removeChords: true)
        let id = try ArpeggioTool.apply(request, to: &project)
        let index = try #require(project.tracks.firstIndex { $0.id == id })
        let written = Compiler.notes(project).filter { $0.track == index }
        #expect(written.count == 8 && written.allSatisfy { $0.tick < barTicks })
        #expect(!Compiler.notes(project).contains { $0.track == 0 && $0.tick < barTicks }, "The chords are silent where the arpeggio plays")
        #expect(Compiler.notes(project).contains { $0.track == 0 && $0.tick >= barTicks }, "and play elsewhere")
    }

    @Test func aMelodyTrackCanBeReplacedAndLimitsAreClear() throws {
        var project = Project.demo()
        try project.addMelody(name: "Keys")
        let keys = project.tracks.count - 1
        let pattern = try #require(project.patterns.firstIndex { $0.id == project.tracks[keys].clips[0].patternID })
        project.patterns[pattern].notes = [NoteEvent(tick: 0, duration: barTicks, pitch: 60, velocity: 90), NoteEvent(tick: 0, duration: barTicks, pitch: 63, velocity: 90)]
        let replace = ArpeggioTool.Request(trackID: project.tracks[keys].id, settings: ArpeggioSettings(rate: .quarter, octaves: 1), destination: .replace)
        let tracks = project.tracks.count
        _ = try ArpeggioTool.apply(replace, to: &project)
        #expect(project.tracks.count == tracks)
        let notes = Compiler.notes(project).filter { $0.track == keys }
        #expect(notes.map(\.pitch) == [60, 63, 60, 63] && notes.map(\.tick) == [0, 960, 1920, 2880])
        // Chords cannot be replaced in place; an empty track has nothing to play; eight tracks is the limit.
        #expect(throws: ArpeggioToolError.cannotReplaceChords) {
            var copy = project; try ArpeggioTool.apply(ArpeggioTool.Request(trackID: copy.tracks[0].id, settings: ArpeggioSettings(), destination: .replace), to: &copy)
        }
        try project.addMelody(name: "Empty")
        #expect(throws: ArpeggioToolError.nothingToArpeggiate) {
            var copy = project; try ArpeggioTool.apply(ArpeggioTool.Request(trackID: copy.tracks.last!.id, settings: ArpeggioSettings()), to: &copy)
        }
        while project.tracks.count < 8 { try project.addMelody() }
        #expect(throws: ArpeggioToolError.trackLimit) {
            var copy = project; try ArpeggioTool.apply(ArpeggioTool.Request(trackID: copy.tracks[0].id, settings: ArpeggioSettings()), to: &copy)
        }
    }
}

struct Build55SoundTests {
    @Test func fmAndAnalogSoundsAreGroupedAndNamedWithoutBrands() {
        let fm = FactorySynth.allCases.filter { $0.collection == .fm }
        let analog = FactorySynth.allCases.filter { $0.collection == .analog }
        #expect(fm.count == 7 && analog.count == 4)
        #expect(fm.contains(.fmEPiano) && fm.contains(.fmSlapBass) && fm.contains(.fmTubularBells) && fm.contains(.fmBrass))
        #expect(analog.contains(.chorusPad) && analog.contains(.analogBass))
        let names = (fm + analog).map { $0.title + " " + $0.brief }.joined(separator: " ")
        for brand in ["Yamaha", "Roland", "DX7", "Juno", "SH-101", "TR-"] { #expect(!names.contains(brand), "\(brand)") }
        #expect([FactorySynth.fmSlapBass, .fmSolidBass, .analogBass, .pulseBass].allSatisfy { $0.family == .bass })
    }

    @Test func classicMachineKitsHaveTheirBeats() throws {
        let kits: [FactoryDrumKit] = [.classic808, .punch909, .digital707, .mini606]
        #expect(kits.map(\.title) == ["808 Classic", "909 Punch", "707 Digital", "606 Mini"])
        for kit in kits {
            #expect(BeatPreset.library.filter { $0.kit == kit }.count == 2, "\(kit) has two factory beats")
            let kick = try kit.sample(pad: 0), hat = try kit.sample(pad: 2)
            #expect(kick.contains { abs(Int($0)) > 8_000 } && hat.contains { abs(Int($0)) > 2_000 })
        }
        // The 808 kick rings far longer than the 606 one.
        #expect(try FactoryDrumKit.classic808.sample(pad: 0).count > 3 * FactoryDrumKit.mini606.sample(pad: 0).count)
        for brand in ["Roland", "TR-"] { #expect(!FactoryDrumKit.allCases.map { $0.title + $0.brief }.joined().contains(brand)) }
    }
}

struct TakeTimingTests {
    @Test func timingValuesAndQuantizeMenu() throws {
        #expect(Quantize.menu.map(\.rawValue) == [0, 480, 320, 240, 160, 120])
        #expect(Quantize.menu.map(\.label) == ["As played", "1/8", "1/8T", "1/16", "1/16T", "1/32"])
        #expect(TakeTiming.natural.isNatural && TakeTiming.natural.tick(250, length: 3840) == 250)
        #expect(TakeTiming(.sixteenth).tick(250, length: 3840) == 240 && TakeTiming(.sixteenth, strength: 0.5).tick(260, length: 3840) == 250)
        #expect(TakeTiming(.eighthTriplet, swing: 0.62).tick(330, length: 3840) == 320, "Triplets ignore swing")
        #expect(TakeTiming.natural.tick(3850, length: 3840) == 10)
        try TakeTiming(.thirtySecond, strength: 0.75, swing: 0.58).validate()
        #expect(throws: MusicError.self) { try TakeTiming(grid: 200).validate() }
        #expect(throws: MusicError.self) { try TakeTiming(grid: 240, strength: 1.5).validate() }
    }

    private func takePattern() -> (Pattern, UUID) {
        let take = UUID()
        var pattern = Pattern(length: barTicks)
        let played = [(5, 0, 100), (250, 2, 70), (488, 2, 75), (962, 1, 110), (1500, 0, 90)]
        pattern.drums = played.map { tick, pad, velocity in
            var hit = DrumEvent(tick: tick, pad: pad, velocity: velocity); hit.played = tick; hit.take = take; return hit
        }
        pattern.drums.append(DrumEvent(tick: 1440, pad: 0, velocity: 80))       // programmed
        var record = DrumTake(id: take, number: 1); record.timing = .natural
        pattern.drumTakes = [record]
        return (pattern, take)
    }

    @Test func aTakeMovesToTheGridAndBackWithoutLosingAHit() throws {
        var (pattern, take) = takePattern()
        let original = pattern.drums.filter { $0.take == take }.map(\.tick).sorted()
        let moved = try DrumTakeTiming.apply(TakeTiming(.eighth), take: take, in: &pattern)
        #expect(moved == 5)
        let mine = pattern.drums.filter { $0.take == take }
        #expect(mine.allSatisfy { $0.tick % 480 == 0 })
        // 1500 → 1440 lands on the programmed kick, and the softer hat at 250 lands on the louder one
        // at 480: both are held aside, not doubled.
        #expect(Set(pattern.drumTakes?[0].held?.compactMap(\.played) ?? []) == [250, 1500])
        #expect(pattern.drums.filter { $0.tick == 1440 && $0.pad == 0 }.count == 1)
        #expect(pattern.drumTakes?[0].timing == TakeTiming(.eighth))
        try DrumTakeTiming.apply(.natural, take: take, in: &pattern)
        #expect(pattern.drums.filter { $0.take == take }.map(\.tick).sorted() == original, "Every hit is back where it was played")
        #expect(pattern.drumTakes?[0].held == nil && pattern.drums.count == 6)
        // Half strength moves each hit half way.
        try DrumTakeTiming.apply(TakeTiming(.sixteenth, strength: 0.5), take: take, in: &pattern)
        #expect(pattern.drums.first { $0.take == take && $0.pad == 1 }?.tick == 961)
        #expect(DrumTakeTiming.canRetime(take, in: pattern))
    }

    @Test func recordingKeepsWhatWasPlayedAndUndoBringsTheTakeBack() throws {
        let project = Project.demo()
        let clip = project.tracks[1].clips[0]
        var draft = try DrumRecordingDraft(project: project, clipID: clip.id)
        var a = DrumEvent(tick: 240, pad: 5, velocity: 90); a.played = 250
        var b = DrumEvent(tick: 240, pad: 5, velocity: 60); b.played = 230
        try draft.commitPass([a, b], timing: TakeTiming(.sixteenth))
        let pattern = try #require(draft.project.patterns.first { $0.id == draft.patternID })
        let takeRecord = try #require(pattern.drumTakes?.first { $0.id == draft.takeID })
        #expect(takeRecord.timing == TakeTiming(.sixteenth))
        #expect(pattern.drums.filter { $0.pad == 5 }.count == 1, "One attack on the shared step")
        #expect(takeRecord.held?.count == 1 && takeRecord.held?.first?.played == 230, "The other hit is kept for the natural feel")
        var natural = pattern
        try DrumTakeTiming.apply(.natural, take: draft.takeID, in: &natural)
        #expect(natural.drums.filter { $0.pad == 5 }.map(\.tick).sorted() == [230, 250])
        let undid = draft.undoLastPass()
        #expect(undid)
        let undone = try #require(draft.project.patterns.first { $0.id == draft.patternID })
        #expect(undone.drumTakes?.first { $0.id == draft.takeID } == nil)
        try draft.project.validate()
    }

    @Test func phrasesKeepTheirFeelOrSnapToAGrid() {
        let notes = [NoteEvent(tick: 250, duration: 200, pitch: 60, velocity: 90), NoteEvent(tick: 3830, duration: 200, pitch: 62, velocity: 90)]
        #expect(NoteTiming.applied(notes, timing: .natural, length: 3840) == notes)
        let snapped = NoteTiming.applied(notes, timing: TakeTiming(.sixteenth), length: 3840)
        #expect(snapped.map(\.tick) == [240, 0] && snapped[1].duration == 200)
    }

    @Test func oldTakesWithoutTimingStillDecodeAndValidate() throws {
        var project = Project.demo()
        var take = DrumTake(id: UUID(), number: 1)
        take.timing = TakeTiming(grid: 240, strength: 1.5)
        project.patterns[1].drumTakes = [take]
        project.patterns[1].drums[0].take = take.id
        #expect(throws: MusicError.self) { try project.validate() }
        project.patterns[1].drumTakes?[0].timing = nil
        try project.validate()
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)
    }
}
