import Foundation
import Testing
@testable import MusicDomain

@Suite("U11 demo tour")
struct DemoTourTests {
    @Test func everyStepIsFinishedByItsAction() {
        var tour = DemoTour()
        #expect(tour.step == .pads && tour.number == 1)
        for step in TourStep.allCases {
            #expect(tour.step == step)
            let finished = tour.observe(step.event)
            #expect(finished)
        }
        #expect(tour.finished && tour.done.count == DemoTour.count && tour.passed.isEmpty)
        #expect(tour.observe(.padHit) == false)
    }

    @Test func otherActionsDoNotFinishTheCurrentStepButCountForLater() {
        var tour = DemoTour()
        #expect(tour.observe(.exportOpened) == false)
        #expect(tour.step == .pads && tour.done == [.export])
        tour.observe(.padHit); tour.observe(.chordChanged); tour.observe(.voiceOpened)
        #expect(tour.step == .layers)
        tour.observe(.mixerOpened)
        // Export was already done, so the tour ends here.
        #expect(tour.finished)
        // An earlier step's action never moves the tour back.
        var again = DemoTour(); again.observe(.padHit); again.observe(.padHit)
        #expect(again.step == .chords)
    }

    @Test func nextPassesOverAndSkipEndsTheTour() {
        var tour = DemoTour()
        tour.next()
        #expect(tour.step == .chords && tour.passed == [.pads])
        tour.observe(.chordChanged)
        tour.skip()
        #expect(tour.finished && tour.passed == [.pads, .hum, .layers, .export] && tour.done == [.chords])
        tour.next(); tour.skip()
        #expect(tour.finished)
    }

    @Test func stepsHaveWordsAndDistinctActions() {
        #expect(Set(TourStep.allCases.map(\.event)).count == TourStep.allCases.count)
        #expect(TourStep.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }
}

@Suite("U31 selected clips")
struct ClipBatchTests {
    /// A song with a drum track holding clips at bars 1, 2 and 4 (one bar each), 8 bars long.
    func fixture() throws -> (Project, Int, [UUID]) {
        var project = Project.demo()
        let drums = try #require(project.tracks.firstIndex { $0.role == .drums })
        let pattern = Pattern(length: barTicks, drums: [DrumEvent(tick: 0, pad: 0, velocity: 100)])
        project.patterns.removeAll { id in project.tracks[drums].clips.contains { $0.patternID == id.id } && !project.tracks.enumerated().contains { $0.offset != drums && $0.element.clips.contains { $0.patternID == id.id } } }
        project.tracks[drums].clips = []
        var ids: [UUID] = []
        for bar in [0, 1, 3] {
            var copy = pattern; copy.id = UUID(); copy.drums = copy.drums.map { var event = $0; event.id = UUID(); return event }
            project.patterns.append(copy)
            let clip = Clip(patternID: copy.id, start: bar * barTicks, length: barTicks)
            ids.append(clip.id)
            project.tracks[drums].clips.append(clip)
        }
        try project.validate()
        return (project, drums, ids)
    }

    @Test func deleteSendsEveryClipToTheTrashAtOnce() throws {
        var (project, drums, ids) = try fixture()
        try ClipEditing.batch(.delete, ids: Set(ids.prefix(2)), in: &project)
        #expect(project.tracks[drums].clips.map(\.id) == [ids[2]])
        #expect(ProjectTrash.items(in: project).filter { $0.kind == .clip }.count == 2)
        for item in ProjectTrash.items(in: project) where item.kind == .clip { try ProjectTrash.restore(item.id, in: &project) }
        #expect(Set(project.tracks[drums].clips.map(\.id)) == Set(ids))
    }

    @Test func everyClipOfTheSongCanGoAndComeBack() throws {
        var project = Project.demo()
        let all = Set(project.tracks.filter { $0.role != .bass }.flatMap(\.clips).map(\.id))
        try ClipEditing.batch(.delete, ids: all, in: &project)
        #expect(project.tracks.allSatisfy { $0.clips.isEmpty || $0.role == .bass })
        for item in ProjectTrash.items(in: project) { try ProjectTrash.restore(item.id, in: &project) }
        #expect(Set(project.tracks.flatMap(\.clips).map(\.id)) == all)
    }

    @Test func moveIsAllOrNothing() throws {
        var (project, drums, ids) = try fixture()
        // Bars 1–2 one bar later: bar 2 moves into the space bar 1 leaves; bar 3 is free.
        try ClipEditing.batch(.move(bars: 1), ids: [ids[0], ids[1]], in: &project)
        #expect(project.tracks[drums].clips.map(\.start) == [barTicks, 2 * barTicks, 3 * barTicks])
        // Two bars later would land the second clip on bar 4, which holds content: nothing changes.
        let before = project
        #expect(throws: ClipEditingError.overlap) { try ClipEditing.batch(.move(bars: 2), ids: [ids[0], ids[1]], in: &project) }
        #expect(project == before)
        // Before the song start: nothing changes either.
        #expect(throws: ClipEditingError.bounds) { try ClipEditing.batch(.move(bars: -2), ids: [ids[0]], in: &project) }
        #expect(project == before)
    }

    @Test func duplicateCopiesTheBlockAfterItself() throws {
        var (project, drums, ids) = try fixture()
        // Bars 1–2 copied after themselves would land on bars 3–4; bar 4 holds content: nothing changes.
        let before = project
        #expect(throws: ClipEditingError.overlap) { try ClipEditing.batch(.duplicate, ids: [ids[0], ids[1]], in: &project) }
        #expect(project == before)
        // Bar 2 alone goes to the free bar 3, on a new pattern with the same hits.
        try ClipEditing.batch(.duplicate, ids: [ids[1]], in: &project)
        #expect(project.tracks[drums].clips.map(\.start) == [0, barTicks, 2 * barTicks, 3 * barTicks])
        let copy = try #require(project.tracks[drums].clips.first { $0.start == 2 * barTicks })
        #expect(!ids.contains(copy.id) && copy.patternID != project.tracks[drums].clips[1].patternID)
        #expect(project.patterns.first { $0.id == copy.patternID }?.drums.map(\.pad) == [0])
    }

    @Test func colourAndMuteChangeOnlyTheSelection() throws {
        var (project, drums, ids) = try fixture()
        try ClipEditing.batch(.color(2), ids: [ids[0], ids[2]], in: &project)
        try ClipEditing.batch(.mute(true), ids: [ids[1]], in: &project)
        #expect(project.tracks[drums].clips.map(\.color) == [2, nil, 2])
        #expect(project.tracks[drums].clips.map(\.muted) == [nil, true, nil])
        // A muted clip is not played.
        let played = Compiler.notes(project).filter { $0.track == drums }.map(\.tick)
        #expect(!played.contains(barTicks) && played.contains(0))
        #expect(throws: ClipEditingError.invalidDrag) { try ClipEditing.batch(.color(9), ids: [ids[0]], in: &project) }
        #expect(throws: ClipEditingError.missing) { try ClipEditing.batch(.mute(true), ids: [UUID()], in: &project) }
    }
}

@Suite("U60 · U39 interface level and density")
struct InterfaceLevelTests {
    @Test func simpleHidesEveryAdvancedPanel() {
        #expect(AdvancedFeature.allCases.allSatisfy { !FeatureLevel.simple.shows($0) && FeatureLevel.full.shows($0) })
    }

    @Test func densityKeepsTouchTargetsAndAccessibilitySizes() {
        #expect(InterfaceDensity.allCases.allSatisfy { $0.controlHeight >= 44 })
        #expect(InterfaceDensity.compact.controlHeight < InterfaceDensity.normal.controlHeight && InterfaceDensity.normal.controlHeight < InterfaceDensity.large.controlHeight)
        #expect(InterfaceDensity.compact.typeIndex(system: 3) == 2 && InterfaceDensity.large.typeIndex(system: 3) == 4)
        #expect(InterfaceDensity.compact.typeIndex(system: 0) == 0 && InterfaceDensity.large.typeIndex(system: 6) == 6)
        // Accessibility sizes are never made smaller.
        #expect(InterfaceDensity.compact.typeIndex(system: 9) == 9 && InterfaceDensity.large.typeIndex(system: 9) == 10)
    }
}

@Suite("U67 hold to preview")
struct HoldPreviewTests {
    @Test func templatesStylesAndBeatsMakeFourBarsToHear() throws {
        let starter = try HoldPreview.template(.starter, bpm: 96, root: 2, minor: true)
        #expect(starter.length == 4 * barTicks && starter.keyRoot == 2 && starter.minor)
        #expect(starter.patterns.contains { !$0.chords.isEmpty })
        for style in SketchStyle.allCases {
            let sketch = try HoldPreview.style(style, root: 0, minor: false)
            #expect(sketch.bpm == HoldPreview.tempo(style) && sketch.length == 4 * barTicks)
            #expect(!Compiler.notes(sketch).isEmpty)
        }
        for genre in BeatPreset.Genre.allCases {
            let beat = try HoldPreview.beat(genre, root: 0, minor: false)
            #expect(beat.kit.count == 16 && beat.project.length == 4 * barTicks)
            #expect(beat.project.patterns.contains { !$0.drums.isEmpty })
        }
    }

    @Test func theRangeStaysInsideTheSong() throws {
        let starter = try HoldPreview.template(.starter, bpm: 96, root: 0, minor: false)
        #expect(HoldPreview.range(starter) == 0..<4 * barTicks)
        var long = Project.demo()
        long.sections[0].length = 2 * barTicks
        #expect(HoldPreview.range(long, from: long.length + 99).upperBound == long.length)
    }
}

@Suite("U33 held project card")
struct HeldProjectCardTests {
    @Test func theChorusPlaysForAboutTenSeconds() throws {
        var project = Project.demo()
        project.bpm = 120
        try SectionEditing.append(name: "Chorus", bars: 8, to: &project)
        let chorus = try #require(project.sections.first { $0.name == "Chorus" })
        let range = ProjectPreview.range(project)
        #expect(range.lowerBound == chorus.start)
        // 120 BPM: ten seconds are twenty beats.
        #expect(range.count == 20 * ppq)
        // A slow song plays fewer beats, never past its section.
        project.bpm = 60
        #expect(ProjectPreview.range(project).count == 10 * ppq)
        project.bpm = 240
        #expect(ProjectPreview.range(project).upperBound == chorus.start + chorus.length)
    }

    @Test func withoutAChorusTheFirstSectionPlays() {
        let project = Project.demo()
        #expect(ProjectPreview.section(of: project)?.id == project.sections[0].id)
        #expect(ProjectPreview.range(project).lowerBound == 0)
    }
}

@Suite("U63 eco mode")
struct EcoModeTests {
    @Test func lowPowerHalvesTheMeterRateAndStopsTheBackground() {
        #expect(EcoMode.meterRate(lowPower: false) == 30 && EcoMode.meterRate(lowPower: true) == 15)
        #expect(EcoMode.animatesBackground(lowPower: false, reduceMotion: false))
        #expect(!EcoMode.animatesBackground(lowPower: true, reduceMotion: false))
        #expect(!EcoMode.animatesBackground(lowPower: false, reduceMotion: true))
        // A pad stays lit for at least two meter reads.
        for lowPower in [false, true] { #expect(EcoMode.padGlow(lowPower: lowPower) * EcoMode.meterRate(lowPower: lowPower) >= 2.9) }
    }
}

@Suite("U55 level-matched bypass")
struct EffectBypassTests {
    /// The demo song with a strong boost on the chords so the EQ changes the level a lot.
    func boosted() throws -> (Project, UUID) {
        var project = Project.demo()
        let harmony = try #require(project.tracks.firstIndex { $0.role == .harmony })
        var eq = StudioEQ()
        eq.bands[1].gain = 12
        eq.bands[2].gain = 9
        project.tracks[harmony].equalizer = eq
        try project.validate()
        return (project, project.tracks[harmony].id)
    }

    @Test func bypassTurnsTheEffectOffAndMovesOnlyTheLevel() throws {
        let (project, id) = try boosted()
        let plain = try EffectBypass.bypassed(project, target: .trackEQ(id), offsetDB: 4)
        let index = try #require(plain.tracks.firstIndex { $0.id == id })
        #expect(plain.tracks[index].equalizer?.enabled == false)
        #expect(plain.tracks[index].gain == project.tracks[index].gain + 4)
        #expect(plain.tracks.enumerated().allSatisfy { $0.offset == index || $0.element == project.tracks[$0.offset] })
        var master = project; master.masterEQ = StudioEQ()
        let masterPlain = try EffectBypass.bypassed(master, target: .masterEQ, offsetDB: -2)
        #expect(masterPlain.masterEQ?.enabled == false && masterPlain.master == master.master - 2)
    }

    @Test func theComparisonIsWithinHalfALoudnessUnit() async throws {
        let (project, id) = try boosted()
        let comparison = try await EffectBypass.matched(project, target: .trackEQ(id), range: 0..<2 * barTicks, samples: SampleLibrary())
        #expect(abs(comparison.differenceLU) <= 0.5, "difference \(comparison.differenceLU) LU, offset \(comparison.offsetDB) dB")
        // The boost made the processed version louder, so the plain one is turned up.
        #expect(comparison.offsetDB > 0)
    }
}

@Suite("U69 field hints")
struct QuerySuggestionsTests {
    let examples = QuerySuggestions.assistantExamples(russian: false)

    @Test func topFiveByPrefixWithHistoryFirst() {
        let history = ["tempo 100", "add a verse", "tempo 80"]
        let hints = QuerySuggestions.top("te", history: history, examples: examples)
        #expect(hints == ["tempo 80", "tempo 100", "tempo 92"])
        // A word inside the phrase matches too.
        #expect(QuerySuggestions.top("chor", history: [], examples: examples).contains("add a chorus"))
        // Never more than five, never the text itself, no repeats.
        let many = QuerySuggestions.top("", history: (1...9).map { "tempo \($0)" } + ["tempo 9"], examples: examples)
        #expect(many.count == 5 && Set(many).count == 5 && many.first == "tempo 9")
        #expect(!QuerySuggestions.top("louder", history: [], examples: examples).contains("louder"))
    }

    @Test func russianExamplesAndNewNames() {
        #expect(QuerySuggestions.top("доб", history: [], examples: QuerySuggestions.assistantExamples(russian: true)) == ["добавь припев"])
        let all = QuerySuggestions.projectNames(existing: [], keyRoot: 9, minor: true, bpm: 90, seed: 3, russian: false, limit: 10)
        #expect(!all.isEmpty)
        let fresh = QuerySuggestions.projectNames(existing: [all[0].uppercased()], keyRoot: 9, minor: true, bpm: 90, seed: 3, russian: false, limit: 10)
        #expect(!fresh.contains(all[0]))
    }
}

@Suite("I6 slice markers")
struct SliceMarkerTests {
    /// Eight hits a quarter second apart at 48 kHz: loud on the beat, quiet in between.
    func loop() -> [Int16] {
        let rate = 48_000
        var samples = [Int16](repeating: 0, count: 2 * rate)
        for hit in 0..<8 {
            let start = hit * rate / 4, loud = hit % 2 == 0
            for i in 0..<2400 { samples[start + i] = Int16(Double(loud ? 20_000 : 3_000) * exp(-Double(i) / 400) * (i % 20 < 10 ? 1 : -1)) }
        }
        return samples
    }

    @Test func sensitivityAndIntervalChooseTheHits() {
        let samples = loop()
        let all = SliceMarkers.detect(samples, rate: 48_000, sensitivity: 1)
        #expect(all.frames.count == 8)
        let strong = SliceMarkers.detect(samples, rate: 48_000, sensitivity: 0)
        #expect(strong.frames.count == 4, "only the loud hits: \(strong.frames)")
        let spaced = SliceMarkers.detect(samples, rate: 48_000, sensitivity: 1, minimumGap: 0.4)
        #expect(spaced.frames.count == 4)
        #expect(all.ranges(rate: 48_000).count == 8 && all.ranges(rate: 48_000).last?.upperBound == samples.count)
    }

    @Test func markersAreAddedRemovedAndMovedSafely() {
        var markers = SliceMarkers(frames: [0, 12_000, 24_000], length: 48_000)
        let added = markers.add(30_000)
        #expect(added && markers.frames == [0, 12_000, 24_000, 30_000])
        let tooClose = markers.add(30_010)
        #expect(!tooClose, "too close to another marker")
        markers.move(1, to: 40_000)
        #expect(markers.frames[1] == 24_000 - SliceMarkers.spacing, "never past the next marker")
        let removed = markers.remove(at: 0)
        #expect(removed && markers.frames.count == 3)
        var one = SliceMarkers(frames: [100], length: 48_000)
        let removedLast = one.remove(at: 0)
        #expect(!removedLast && one.frames == [100])
        #expect(markers.slice(containing: 35_000) == 2)
        let wav = SliceMarkers.previewWAV(loop(), 0..<1000, rate: 48_000)
        #expect(wav.count == 44 + 2000 && String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
    }
}

@Suite("U27 pad drag")
struct PadDragTests {
    @Test func aDraggedPadIsReadBackAndNothingElseIs() {
        #expect(PadEditing.pad(fromDrag: PadEditing.dragPayload(4)) == 4)
        #expect(PadEditing.pad(fromDrag: "grilla-pad:16") == nil)
        #expect(PadEditing.pad(fromDrag: "grid.clip.123") == nil)
        #expect(PadEditing.pad(fromDrag: "grilla-pad:x") == nil)
    }

    @Test func droppingPadOneOnPadFiveSwapsTheirHits() throws {
        var project = Project.demo()
        let drums = try #require(project.tracks.first { $0.role == .drums })
        let before = project.patterns.flatMap(\.drums).filter { $0.pad == 0 }.count
        let from = try #require(PadEditing.pad(fromDrag: PadEditing.dragPayload(0)))
        try PadEditing.swap(from, 4, track: drums.id, in: &project)
        #expect(project.patterns.flatMap(\.drums).filter { $0.pad == 4 }.count == before)
        #expect(project.patterns.flatMap(\.drums).filter { $0.pad == 0 }.isEmpty)
    }
}
