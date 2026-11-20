import Foundation
import Testing
@testable import MusicDomain

/// A small producer project: Intro 2, Verse 4, Chorus 4, Verse 4, Chorus 4 bars.
/// Both choruses share one drum pattern and one chord pattern, the verses share
/// another; a melody track has a hand-played note; the drums use a custom kick
/// sample; a named "Bass" melody track carries an editable bass line.
enum SongEditFixture {
    static func kickData() throws -> Data {
        var frames: [Int16] = []
        for index in 0..<3200 {
            let level: Int = index % 40 < 20 ? 12_000 : -9_000
            frames.append(Int16(level * (3200 - index) / 3200))
        }
        return try SamplePCM(rate: 32_000, zones: [.init(pitch: 60, samples: frames)]).encode(kind: .oneShot)
    }
    static func project(derivedBass: Bool = false) throws -> Project {
        var p = Project(name: "Edit fixture", bars: 4)
        p.bpm = 92; p.keyRoot = 9; p.minor = true
        let names = ["Intro", "Verse", "Chorus", "Verse", "Chorus"], lengths = [2, 4, 4, 4, 4]
        var start = 0
        p.sections = zip(names, lengths).map { name, bars in defer { start += bars * barTicks }; return Section(name: name, start: start, length: bars * barTicks) }
        func beat(bars: Int, busy: Bool) -> Pattern {
            var pattern = Pattern(length: bars * barTicks)
            for bar in 0..<bars {
                let at = bar * barTicks
                pattern.drums += [DrumEvent(tick: at, pad: 0, velocity: 110), DrumEvent(tick: at + 1920, pad: 0, velocity: 100)]
                pattern.drums += [DrumEvent(tick: at + 960, pad: 1), DrumEvent(tick: at + 2880, pad: 1)]
                for step in stride(from: 0, to: barTicks, by: busy ? 240 : 480) { pattern.drums.append(DrumEvent(tick: at + step, pad: 2, velocity: 70)) }
            }
            return pattern
        }
        func chords(_ symbols: [String]) throws -> Pattern {
            Pattern(length: symbols.count * barTicks, chords: try symbols.enumerated().map { ChordEvent(tick: $0.offset * barTicks, chord: try Chord.parse($0.element)) })
        }
        var introBeat = Pattern(length: 2 * barTicks)
        introBeat.drums = (0..<2).flatMap { bar in [DrumEvent(tick: bar * barTicks, pad: 0), DrumEvent(tick: bar * barTicks + 960, pad: 2), DrumEvent(tick: bar * barTicks + 1920, pad: 0)] }
        let verseBeat = beat(bars: 4, busy: false), chorusBeat = beat(bars: 4, busy: true)
        let introChords = try chords(["Am", "Am"]), verseChords = try chords(["Am", "F", "C", "G"]), chorusChords = try chords(["F", "G", "Am", "Am"])
        var bassLine = Pattern(length: 18 * barTicks)
        for bar in 0..<18 { bassLine.notes?.append(NoteEvent(tick: bar * barTicks, duration: 1800, pitch: 45, velocity: 96)); bassLine.notes?.append(NoteEvent(tick: bar * barTicks + 1920, duration: 900, pitch: 52, velocity: 90)) }
        var lead = Pattern(length: 18 * barTicks)
        lead.notes = [NoteEvent(tick: 0, duration: 480, pitch: 76, velocity: 101, confidence: nil)] // hand-played pickup in the intro
        lead.notes?.append(NoteEvent(tick: 6 * barTicks + 960, duration: 960, pitch: 72, velocity: 99))
        // A flute phrase over the last chorus.
        for bar in 14..<18 { for beat in 0..<4 { lead.notes?.append(NoteEvent(tick: bar * barTicks + beat * ppq, duration: 720, pitch: [76, 74, 72, 69][beat], velocity: 96)) } }
        p.patterns = [introChords, verseChords, chorusChords, introBeat, verseBeat, chorusBeat, bassLine, lead]
        p.tracks[0].clips = [Clip(patternID: introChords.id, start: 0, length: 2 * barTicks), Clip(patternID: verseChords.id, start: 2 * barTicks, length: 4 * barTicks),
                             Clip(patternID: chorusChords.id, start: 6 * barTicks, length: 4 * barTicks), Clip(patternID: verseChords.id, start: 10 * barTicks, length: 4 * barTicks),
                             Clip(patternID: chorusChords.id, start: 14 * barTicks, length: 4 * barTicks)]
        p.tracks[1].clips = [Clip(patternID: introBeat.id, start: 0, length: 2 * barTicks), Clip(patternID: verseBeat.id, start: 2 * barTicks, length: 4 * barTicks),
                             Clip(patternID: chorusBeat.id, start: 6 * barTicks, length: 4 * barTicks), Clip(patternID: verseBeat.id, start: 10 * barTicks, length: 4 * barTicks),
                             Clip(patternID: chorusBeat.id, start: 14 * barTicks, length: 4 * barTicks)]
        p.tracks[0].gain = -9; p.tracks[1].gain = -4; p.master = -2
        // Custom kick sample.
        let data = try kickData()
        p.tracks[1].padSamples = [0: try SampleAsset(kind: .oneShot, name: "My kick", bytes: data)]
        if derivedBass {
            p.tracks.append(Track(role: .bass))
            p.patterns.removeAll { $0.id == bassLine.id }
        } else {
            var bass = Track(role: .melody); bass.name = "Bass"; bass.gain = -5
            bass.clips = [Clip(patternID: bassLine.id, start: 0, length: 18 * barTicks)]
            p.tracks.append(bass)
        }
        var melody = Track(role: .melody); melody.name = "Flute"
        melody.clips = [Clip(patternID: lead.id, start: 0, length: 18 * barTicks)]
        p.tracks.append(melody)
        try p.validate()
        return p
    }
}

struct SongEditControlCommandTests {
    let command = "Бас и аккорды оставь. Убери бочку в первых двух тактах и добавь короткую сбивку перед первым припевом."

    @Test func controlCommandIsAnEditAndParsesIntoCheckableOperations() throws {
        let p = try SongEditFixture.project()
        #expect(SongEditParser.intent(command, project: p) == .edit)
        let plan = SongEditParser.plan(command, project: p)
        #expect(plan.problems.isEmpty, "\(plan.problems)")
        #expect(plan.choices.isEmpty)
        let bass = p.tracks.first { $0.name == "Bass" }!.id
        #expect(Set(plan.protectedTracks) == [p.tracks[0].id, bass])
        #expect(plan.operations.count == 2)
        let removal = try #require(plan.operations.first { $0.kind == .remove })
        #expect(removal.target == SongEditTarget(trackID: p.tracks[1].id, pads: [0]))
        #expect(removal.bars == 0..<2)
        let fill = try #require(plan.operations.first { $0.kind == .fill })
        let firstChorus = p.sections[2]
        #expect(fill.sectionID == firstChorus.id)
        #expect(fill.bars == (firstChorus.start / barTicks - 1)..<(firstChorus.start / barTicks))
        #expect(fill.amount == 2 * ppq)
        #expect(plan.isApplicable)
        let cells = plan.affectedCells(in: p)
        #expect(cells.contains(SongEditCell(trackID: p.tracks[1].id, sectionID: p.sections[0].id)))
        #expect(cells.contains(SongEditCell(trackID: p.tracks[1].id, sectionID: p.sections[1].id)))
        #expect(!cells.contains { $0.sectionID == p.sections[2].id || $0.sectionID == p.sections[4].id })
    }

    @Test func onlyTheKickDisappearsAndTheFillSoundsOnceBeforeTheChosenChorus() throws {
        // The intro has an empty beat; put kicks there so removal is audible.
        var p = try SongEditFixture.project()
        let intro = p.tracks[1].clips[0].patternID
        let i = p.patterns.firstIndex { $0.id == intro }!
        p.patterns[i].drums = (0..<2).flatMap { bar in [DrumEvent(tick: bar * barTicks, pad: 0), DrumEvent(tick: bar * barTicks + 960, pad: 2), DrumEvent(tick: bar * barTicks + 1920, pad: 0)] }
        try p.validate()
        let plan = SongEditParser.plan(command, project: p)
        let edited = try SongEditor.apply(plan, to: p)
        let diff = SongEditDiff(before: p, after: edited)
        let drums = p.tracks[1].id
        // First two bars: exactly the kicks are gone; the hats stay.
        let early = diff.removed.filter { $0.tick < 2 * barTicks }
        #expect(!early.isEmpty && early.allSatisfy { $0.trackID == drums && $0.pad == 0 })
        #expect(diff.added.filter { $0.tick < 2 * barTicks }.isEmpty)
        #expect(Compiler.notes(edited, range: 0..<2 * barTicks).filter { $0.pad == 2 }.count == 2)
        // The fill: only in the last two beats of the bar before the first chorus.
        let chorus = p.sections[2].start, window = (chorus - 2 * ppq)..<chorus
        #expect(diff.added.allSatisfy { window.contains($0.tick) && $0.trackID == drums })
        #expect(diff.added.contains { $0.pad == 1 } && diff.added.contains { [6, 7, 8].contains($0.pad) })
        #expect(diff.removed.filter { $0.tick >= 2 * barTicks }.allSatisfy { window.contains($0.tick) })
        // The second chorus (same source pattern) and the bar before it are unchanged.
        let second = p.sections[4]
        #expect(Compiler.notes(edited, range: (second.start - barTicks)..<(second.start + second.length)) == Compiler.notes(p, range: (second.start - barTicks)..<(second.start + second.length)))
        // Bass, chords, the hand-played melody, samples and mix match the source.
        for track in p.tracks where track.id != drums {
            #expect(diff.events(on: track.id).added.isEmpty && diff.events(on: track.id).removed.isEmpty)
        }
        #expect(edited.tracks[1].padSamples == p.tracks[1].padSamples)
        #expect(edited.tracks.map(\.gain) == p.tracks.map(\.gain) && edited.master == p.master)
        #expect(edited.tracks.map(\.id) == p.tracks.map(\.id) && edited.tracks.map(\.presetVersion) == p.tracks.map(\.presetVersion))
    }

    @Test func applyIsOneUndoAndSurvivesRedoSaveAndColdLoad() async throws {
        var p = try SongEditFixture.project()
        let original = p
        var history = History()
        let plan = SongEditParser.plan(command, project: p)
        try history.apply(&p) { $0 = try SongEditor.apply(plan, to: $0) }
        let edited = p
        history.undo(&p)
        #expect(p.patterns == original.patterns && p.tracks == original.tracks)
        history.redo(&p)
        #expect(p.patterns == edited.patterns && p.tracks == edited.tracks)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(root: folder)
        _ = try await store.stageSample(try SongEditFixture.kickData(), asset: p.tracks[1].padSamples![0]!, projectID: p.id)
        try await store.save(p)
        let reopened = try await ProjectStore(root: folder).load(p.id)
        #expect(Compiler.notes(reopened) == Compiler.notes(edited))
        #expect(reopened.tracks[1].padSamples == original.tracks[1].padSamples)
    }

    @Test func staleOrUnresolvedPlansCannotApply() throws {
        var p = try SongEditFixture.project()
        let plan = SongEditParser.plan(command, project: p)
        p.revision += 1
        #expect(throws: SongEditError.stale) { try SongEditor.apply(plan, to: p) }
    }

    @Test func twoChorusesWithoutAnOrdinalOfferTwoTargets() throws {
        let p = try SongEditFixture.project()
        let plan = SongEditParser.plan("Добавь сбивку перед припевом", project: p)
        #expect(plan.needsClarification)
        #expect(plan.choices.map(\.sectionID) == [p.sections[2].id, p.sections[4].id])
        let resolved = plan.choosing(1)
        #expect(resolved.isApplicable)
        #expect(resolved.operations.first?.bars == 13..<14)
        let edited = try SongEditor.apply(resolved, to: p)
        // The first chorus transition is untouched.
        #expect(Compiler.notes(edited, range: 0..<10 * barTicks) == Compiler.notes(p, range: 0..<10 * barTicks))
    }

    @Test func englishControlCommandMatches() throws {
        let p = try SongEditFixture.project()
        let ru = SongEditParser.plan(command, project: p)
        let en = SongEditParser.plan("Keep the bass and chords. Remove the kick in the first two bars and add a short fill before the first chorus.", project: p)
        #expect(en.problems.isEmpty, "\(en.problems)")
        #expect(en.operations == ru.operations)
        #expect(Set(en.protectedTracks) == Set(ru.protectedTracks))
    }
}

/// The on-screen walkthrough project behaves exactly as the UI test expects.
struct SongEditDemoTests {
    @Test func walkthroughProjectGivesTheReviewedPlanChoicesAndProblem() throws {
        let p = try SongEditDemo.project()
        for text in ["Бас и аккорды оставь. Убери бочку в первых двух тактах и добавь короткую сбивку перед первым припевом.",
                     "Keep the bass and chords. Remove the kick in the first two bars and add a short fill before the first chorus."] {
            let plan = SongEditParser.plan(text, project: p)
            #expect(plan.isApplicable && plan.operations.count == 2, "\(plan.problems)")
            #expect(Set(plan.affectedCells(in: p).map(\.trackID)) == [p.tracks[1].id])
            let edited = try SongEditor.apply(plan, to: p)
            #expect(!SongEditDiff(before: p, after: edited).isEmpty)
        }
        let choice = SongEditParser.plan("Add a fill before the chorus", project: p)
        #expect(choice.choices.count == 2 && !choice.isApplicable && choice.choosing(1).isApplicable)
        let unsupported = SongEditParser.plan("Add vocals to the second chorus", project: p)
        #expect(!unsupported.isApplicable && unsupported.problems.first?.fragment.lowercased().contains("vocals") == true)
    }
}

struct StopBreakTests {
    @Test func stopBreakSilencesTheLastBeatBeforeTheChosenChorusOnly() throws {
        let p = try SongEditDemo.project()
        for text in ["Сделай стоп-брейк перед вторым припевом, бас оставь", "Add a stop break before the second chorus and keep the bass"] {
            let plan = SongEditParser.plan(text, project: p)
            #expect(plan.isApplicable, "\(text): \(plan.problems)")
            #expect(plan.operations.allSatisfy { $0.kind == .stopBreak && $0.bars == 13..<14 && $0.amount == ppq })
            let bass = p.tracks.first { $0.name == "Bass" }!.id
            #expect(!plan.operations.contains { $0.target.trackID == bass })
            let edited = try SongEditor.apply(plan, to: p)
            let window = (14 * barTicks - ppq)..<(14 * barTicks)
            let bassIndex = p.tracks.firstIndex { $0.id == bass }!
            let inside = Compiler.notes(edited).filter { $0.tick < window.upperBound && $0.tick + $0.duration > window.lowerBound }
            #expect(inside.allSatisfy { $0.track == bassIndex }, "\(inside.map(\.track))")
            // The first chorus transition is untouched; the chorus itself starts as before.
            #expect(Compiler.notes(edited, range: 0..<(13 * barTicks)) == Compiler.notes(p, range: 0..<(13 * barTicks)))
            #expect(Compiler.notes(edited, range: (14 * barTicks)..<p.length) == Compiler.notes(p, range: (14 * barTicks)..<p.length))
        }
    }
}

struct PlayingToolsByPhraseTests {
    @Test func humanizeSwingScaleShiftAndBassFromKickByPhrase() throws {
        let p = try SongEditDemo.project()
        let cases: [(String, SongEditOperation.Kind)] = [
            ("Очеловечь флейту в последнем припеве", .humanize), ("Humanize the hats in the first verse", .humanize),
            ("Свинг 62% на хэтах во втором куплете", .swing), ("Add swing to the hats in the last chorus", .swing),
            ("Подними флейту на две ступени в последнем припеве", .scaleShift), ("Move the flute down an octave in the last chorus", .scaleShift),
            ("Сделай бас по бочке во втором куплете", .bassFromKick), ("Make the bass follow the kick in the first chorus", .bassFromKick),
        ]
        for (text, kind) in cases {
            let plan = SongEditParser.plan(text, project: p)
            #expect(plan.isApplicable, "\(text): \(plan.problems)")
            #expect(plan.operations.first?.kind == kind, "\(text)")
            let edited = try SongEditor.apply(plan, to: p)
            let diff = SongEditDiff(before: p, after: edited)
            #expect(!diff.isEmpty, "\(text) changed nothing")
            let ticks = (diff.added + diff.removed).map(\.tick)
            let bars = plan.operations.flatMap(\.editedBars)
            #expect(ticks.allSatisfy { bars.contains($0 / barTicks) }, "\(text) changed outside its bars")
        }
        let swing = SongEditParser.plan("Свинг 62% на хэтах во втором куплете", project: p)
        #expect(swing.operations.first?.amount == 62)
        let octave = SongEditParser.plan("Move the flute down an octave in the last chorus", project: p)
        #expect(octave.operations.first?.amount == -7)
        let shifted = try SongEditor.apply(octave, to: p)
        let flute = p.tracks.firstIndex { $0.name == "Flute" }!
        let before = Compiler.notes(p).filter { $0.track == flute && $0.tick >= 14 * barTicks }.map(\.pitch)
        let after = Compiler.notes(shifted).filter { $0.track == flute && $0.tick >= 14 * barTicks }.map(\.pitch)
        #expect(zip(before, after).allSatisfy { $0.0 - $0.1 == 12 })
    }
}

struct ReharmonizeByPhraseTests {
    @Test func restyleOneVerseOccurrenceAndKeepTheOther() throws {
        let p = try SongEditDemo.project()
        for text in ["Сделай аккорды джазовее во втором куплете", "Make the chords jazzier in the second verse"] {
            let plan = SongEditParser.plan(text, project: p)
            #expect(plan.isApplicable, "\(text): \(plan.problems)")
            #expect(plan.operations.first?.kind == .reharmonize && plan.operations.first?.bars == 10..<14)
            let edited = try SongEditor.apply(plan, to: p)
            let second = p.sections[3], first = p.sections[1]
            #expect(Arrangement.harmony(edited, section: second).map(\.chord) != Arrangement.harmony(p, section: second).map(\.chord))
            #expect(Arrangement.harmony(edited, section: first).map(\.chord) == Arrangement.harmony(p, section: first).map(\.chord))
            #expect(Compiler.notes(edited).filter { $0.pad >= 0 } == Compiler.notes(p).filter { $0.pad >= 0 })
        }
    }
}

struct SongEditIdeasTests {
    @Test func hereMeansTheSelectedSection() throws {
        let p = try SongEditDemo.project()
        let plan = SongEditParser.plan("Убери бочку здесь", project: p, selectedSectionID: p.sections[3].id)
        #expect(plan.isApplicable && plan.operations.first?.bars == 10..<14 && plan.operations.first?.sectionID == p.sections[3].id)
        let english = SongEditParser.plan("Remove the kick in this section", project: p, selectedSectionID: p.sections[1].id)
        #expect(english.operations.first?.bars == 2..<6)
    }

    @Test func threeHookTakesAreChoicesWithDifferentNotes() throws {
        let p = try SongEditDemo.project()
        let plan = SongEditParser.plan("Добавь мелодию во второй припев, дай три варианта", project: p)
        #expect(plan.choices.count == 3 && plan.choices.map(\.label).allSatisfy { $0.contains("Hook take") })
        let takes = try (0..<3).map { try SongEditor.apply(plan.choosing($0), to: p) }
        let melodies = takes.map { t in Compiler.notes(t).filter { $0.track == t.tracks.count - 1 }.map(\.pitch) }
        #expect(Set(melodies.map { $0.description }).count >= 2)
    }

    @Test func lockedPartsAreKeptAndEditsAreLogged() throws {
        var p = try SongEditDemo.project()
        p.tracks[1].locked = true
        let plan = SongEditParser.plan("Убери бочку в первых двух тактах", project: p)
        #expect(plan.protectedTracks.contains(p.tracks[1].id) && plan.problems.contains { $0.reason == .contradiction })
        p.tracks[1].locked = nil
        let ok = SongEditParser.plan("Убери бочку в первых двух тактах", project: p)
        let edited = try SongEditor.applyLogged(ok, to: p)
        #expect(edited.editLog == ["Убери бочку в первых двух тактах"])
        // Old files without the fields decode; new fields round-trip.
        var locked = edited; locked.tracks[2].locked = true
        let decoded = try ProjectDocument.decode(JSONEncoder().encode(locked))
        #expect(decoded.tracks[2].locked == true && decoded.editLog == edited.editLog)
        #expect(PaletteEngine.defaultKept(locked).contains(locked.tracks[2].id))
    }

    @Test func aVariantOfTheChorusIsInsertedAfterItAndCanBeResized() throws {
        let p = try SongEditDemo.project()
        let plan = SongEditParser.plan("Сделай ещё один вариант первого припева на 2 такта", project: p)
        #expect(plan.isApplicable, "\(plan.problems) \(plan.choices.map(\.label))")
        let edited = try SongEditor.apply(plan, to: p)
        #expect(edited.sections.count == p.sections.count + 1)
        #expect(edited.sections[3].length == 2 * barTicks && edited.sections[3].name.hasPrefix(p.sections[2].name))
        let firstEnd = p.sections[2].start + p.sections[2].length
        #expect(Compiler.notes(edited, range: 0..<firstEnd) == Compiler.notes(p, range: 0..<firstEnd))
        let two = SongEditParser.plan("Duplicate the chorus", project: p)
        #expect(two.choices.count == 2)
    }
}
