import Foundation
import Testing
@testable import MusicDomain

/// Tuner (I35), markers (I39), triplet steps (I24) and song dynamics (I38).
struct IdeasBatchTests {
    private func sine(_ frequency: Double, rate: Double = 48_000, seconds: Double = 0.12, harmonics: Bool = false) -> [Float] {
        (0..<Int(rate * seconds)).map { index in
            let t = Double(index) / rate
            let tone = sin(2 * .pi * frequency * t) + (harmonics ? 0.5 * sin(4 * .pi * frequency * t) + 0.25 * sin(6 * .pi * frequency * t) : 0)
            return Float(0.4 * tone)
        }
    }

    @Test func tunerNamesNotesAndCents() throws {
        let a4 = try #require(Tuner.detect(sine(440), sampleRate: 48_000))
        #expect(a4.name == "A4" && abs(a4.cents) <= 2 && a4.inTune)
        let lowE = try #require(Tuner.detect(sine(41.2, rate: 44_100, seconds: 0.2, harmonics: true), sampleRate: 44_100))
        #expect(lowE.note == 28 && abs(lowE.cents) <= 4, "Bass low E: \(lowE.frequency) \(lowE.confidence)")
        let sharp = try #require(Tuner.detect(sine(440 * pow(2, 20.0 / 1200)), sampleRate: 48_000))
        #expect(sharp.note == 69 && (16...24).contains(sharp.cents))
        let guitarG = try #require(Tuner.detect(sine(196, harmonics: true), sampleRate: 48_000))
        #expect(guitarG.name == "G3")
        #expect(Tuner.detect([Float](repeating: 0, count: 4_800), sampleRate: 48_000) == nil, "Silence has no note")
        #expect(Tuner.reading(frequency: 432, reference: 432)?.cents == 0)
    }

    @Test func markersStayWithTheirSectionAndTravelInMIDI() throws {
        var project = Project.demo()
        try project.duplicateSection(project.sections[0].id, name: "Chorus")
        let marker = try MarkerEditing.add("vocals here", at: 4 * barTicks + 2 * ppq + 30, in: &project)
        #expect(marker.tick == 4 * barTicks + 2 * ppq && MarkerEditing.position(marker.tick) == "5.3")
        let midi = try MIDIExporter.data(project)
        #expect(midi.range(of: Data("vocals here".utf8)) != nil)
        // Moving the chorus first carries its marker along.
        var moved = project
        let verse = moved.sections[0], chorus = moved.sections[1]
        moved.sections = [Section(name: chorus.name, start: 0, length: chorus.length), Section(name: verse.name, start: chorus.length, length: verse.length)]
        moved.sections[0].id = chorus.id; moved.sections[1].id = verse.id
        MarkerEditing.remap(from: project, to: &moved)
        #expect(moved.markers?.first?.tick == 2 * ppq)
        // Deleting the chorus removes its marker.
        var shorter = project
        shorter.sections.removeLast()
        MarkerEditing.remap(from: project, to: &shorter)
        #expect(shorter.markers == nil)
        #expect(throws: MusicError.self) { _ = try MarkerEditing.add("   ", at: 0, in: &project) }
    }

    @Test func tripletAndThirtySecondStepsFitTheBar() {
        #expect(StepDivision.allCases.map(\.steps) == [8, 16, 12, 24, 32])
        #expect(StepDivision.allCases.allSatisfy { $0.ticks * $0.steps == barTicks })
        #expect(StepDivision.eighthTriplet.tick(bar: 1, step: 3) == barTicks + ppq)
        #expect(StepDivision.sixteenthTriplet.step(of: 160) == 1 && StepDivision.sixteenth.step(of: 160) == nil)
        let triplets = [DrumEvent(tick: 0, pad: 2), DrumEvent(tick: 320, pad: 2), DrumEvent(tick: 640, pad: 2)]
        #expect(StepDivision.fitting(triplets, bar: 0) == .eighthTriplet)
        #expect(StepDivision.fitting([DrumEvent(tick: 240, pad: 0)], bar: 0) == .sixteenth)
        #expect(StepDivision.sixteenth.offGrid(triplets, bar: 0) == 2)
    }

    @Test func dynamicsBuildTowardsTheChorus() throws {
        var project = Project.demo()
        // A busier beat: hats on sixteenths, an open hat and a crash.
        for tick in stride(from: 0, to: project.patterns[1].length, by: 240) { project.patterns[1].drums.append(DrumEvent(tick: tick, pad: 14, velocity: 60)) }
        project.patterns[1].drums.append(DrumEvent(tick: 1_920, pad: 3, velocity: 80))
        try project.addMelody(name: "Lead")
        let lead = project.tracks.count - 1
        project.patterns.append(Pattern(length: 4 * barTicks, notes: [NoteEvent(tick: 0, duration: ppq, pitch: 72)]))
        project.tracks[lead].clips = [Clip(patternID: project.patterns.last!.id, start: 0, length: 4 * barTicks)]
        try SectionEditing.append(name: "Chorus", bars: 4, to: &project)
        project.patterns[1].length = 4 * barTicks
        project.tracks[1].clips = [Clip(patternID: project.patterns[1].id, start: 0, length: project.length)]
        project.tracks[lead].clips = [Clip(patternID: project.patterns.first { $0.notes?.isEmpty == false }!.id, start: 0, length: project.length)]
        try SectionEditing.append(name: "Bridge", bars: 4, to: &project)
        try project.validate()
        project.sections[0].name = "Intro"
        let shaped = try ArrangementDynamics.apply(project)
        let density = ArrangementDynamics.density(shaped)
        let (intro, chorus, bridge) = (project.sections[0].id, project.sections[1].id, project.sections[2].id)
        #expect(density[intro]! < density[chorus]!)
        #expect(density[bridge]! < density[chorus]!)
        #expect(Compiler.notes(shaped).contains { $0.pad == 9 && $0.tick == project.sections[1].start }, "The chorus opens with a crash")
        #expect(!Compiler.notes(shaped).contains { $0.track == lead && $0.tick < barTicks * 4 }, "The intro leaves the melody out")
        #expect(Compiler.notes(shaped).contains { $0.track == lead && $0.tick >= project.sections[1].start })
        // A locked drum track stays exactly as it was.
        var locked = project; locked.tracks[1].locked = true
        let kept = try ArrangementDynamics.apply(locked)
        #expect(Compiler.notes(kept).filter { $0.pad >= 0 } == Compiler.notes(project).filter { $0.pad >= 0 })
        #expect(ArrangementDynamics.role(of: Section(name: "Припев", length: barTicks), index: 0, count: 1) == .chorus)
        #expect(ArrangementDynamics.role(of: Section(name: "Part 1", length: barTicks), index: 0, count: 4) == .intro)
    }
}

struct SoundSearchTests {
    private func found(_ query: String) -> Set<String> {
        Set(SoundIndex.tags.keys.filter { SoundIndex.matches(name: $0, id: $0, query: query) })
    }

    @Test func wordsInEitherLanguageFindTheirSounds() {
        let cases: [(String, String)] = [
            ("808", "synth-808-sub"), ("бас пальцами", "synth-finger-bass"), ("finger bass", "synth-finger-bass"),
            ("лоу-фай клавиши", "synth-lofi-keys"), ("lofi keys", "synth-lofi-keys"), ("тёплый пэд", "ambient-pad"),
            ("саксофон джаз", "alto-sax"), ("гитара", "nylon-guitar"), ("фонк", "synth-808-dirty"), ("амапиано", "synth-log-drum"),
            ("хор", "synth-choir-pad"), ("струнные", "synth-string-pad"), ("8 бит", "synth-chip-lead"), ("acid 303", "synth-acid-bass"),
            ("вибрафон", "vibraphone"), ("ORGAN", "organ"), ("клавиши", "piano"), ("риз", "synth-reese-bass"),
        ]
        for (query, id) in cases { #expect(found(query).contains(id), "\(query) → \(id)") }
        #expect(found("бас пальцами").count == 1)
        #expect(found("qqq").isEmpty)
        #expect(SoundIndex.matches(name: "Warm keys", id: "x", query: ""))
        #expect(SoundIndex.score(name: "808 Sub", id: "synth-808-sub", query: "808 sub") == 100)
        #expect(SoundIndex.score(name: "808 Sub", id: "synth-808-sub", query: "808") > SoundIndex.score(name: "Square bass", id: "synth-square-bass", query: "бас"))
    }

    @Test func favoritesAndRecentsKeepTheirOrder() {
        var favorites = Favorites("")
        favorites.toggle("piano"); favorites.toggle("synth-808-sub"); favorites.toggle("piano")
        #expect(favorites.ids == ["synth-808-sub"] && Favorites(favorites.stored) == favorites)
        favorites.toggle("bad,id")
        #expect(favorites.ids.count == 1)
        var recent = RecentItems("")
        for id in ["a", "b", "c", "a", "d", "e", "f", "g", "h", "i"] { recent.use(id) }
        #expect(recent.ids.first == "i" && recent.ids.count == RecentItems.limit && !recent.ids.contains("b"))
        #expect(recent.ids.filter { $0 == "a" }.count <= 1)
    }
}
