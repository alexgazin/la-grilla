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
