import Foundation
import Testing
@testable import MusicDomain

struct PartVariatorTests {
    private let beat = Project.demo().patterns[1]
    private func signature(_ p: Pattern) -> [String] { p.drums.map { "\($0.tick).\($0.pad).\($0.velocity)" } }

    @Test func boldnessZeroIsTheOriginalAndTheSameSeedGivesTheSameVariant() {
        for character in PartVariator.Character.allCases {
            #expect(PartVariator.variant(beat, role: .drums, character: character, boldness: 0, seed: 7) == beat)
            let a = PartVariator.variant(beat, role: .drums, character: character, boldness: 0.8, seed: 7)
            let b = PartVariator.variant(beat, role: .drums, character: character, boldness: 0.8, seed: 7)
            #expect(signature(a) == signature(b), "\(character)")
        }
    }

    @Test func eachCharacterChangesTheBeatTheWayItSays() throws {
        let ghost = PartVariator.variant(beat, role: .drums, character: .ghostNotes, boldness: 1, seed: 3)
        #expect(ghost.drums.count > beat.drums.count && ghost.drums.filter { $0.velocity < 50 && $0.pad == 1 }.count > 0)
        let simpler = PartVariator.variant(beat, role: .drums, character: .simpler, boldness: 1, seed: 3)
        #expect(simpler.drums.count < beat.drums.count)
        #expect(simpler.drums.contains { $0.pad == 0 && $0.tick == 0 } && simpler.drums.contains { $0.pad == 1 && $0.tick == 960 })
        let fill = PartVariator.variant(beat, role: .drums, character: .fill, boldness: 1, seed: 3)
        #expect(fill.drums.filter { $0.tick >= beat.length - barTicks * 3 / 4 && (6...8).contains($0.pad) }.count > 0)
        let busier = PartVariator.variant(beat, role: .drums, character: .busier, boldness: 1, seed: 3)
        #expect(busier.drums.count > beat.drums.count)
        let swing = PartVariator.variant(beat, role: .drums, character: .swing, boldness: 1, seed: 3)
        #expect(swing.drums.count == beat.drums.count)
        var project = Project.demo()
        for (name, variant) in [("ghost", ghost), ("simpler", simpler), ("fill", fill), ("busier", busier), ("swing", swing)] {
            var pattern = variant; pattern.id = project.patterns[1].id
            project.patterns[1] = pattern
            #expect(throws: Never.self, "\(name)") { try project.validate() }
        }
    }

    @Test func melodicPartsGetTheirOwnCharacters() throws {
        var pattern = Pattern(length: barTicks)
        pattern.notes = [NoteEvent(tick: 0, duration: 960, pitch: 60, velocity: 90), NoteEvent(tick: 1200, duration: 120, pitch: 62, velocity: 90)]
        #expect(PartVariator.characters(for: .melody) == [.simpler, .busier, .swing])
        let busier = PartVariator.variant(pattern, role: .melody, character: .busier, boldness: 1, seed: 1)
        #expect((busier.notes ?? []).count >= 2)
        let simpler = PartVariator.variant(pattern, role: .melody, character: .simpler, boldness: 1, seed: 1)
        #expect((simpler.notes ?? []).count == 1)
    }
}

struct FillAndCompTests {
    @Test func aFillIsItsOwnTakeInsideTheBarAndCanBeDeletedAlone() throws {
        var project = Project.demo()
        let before = project.patterns[1]
        let id = try #require(FillGenerator.add(.toms, beats: 2, endingAt: barTicks * 2, to: &project.patterns[1]))
        let added = project.patterns[1].drums.filter { $0.take == id }
        #expect(!added.isEmpty && added.allSatisfy { $0.tick >= barTicks * 2 - barTicks / 2 && $0.tick < barTicks * 2 })
        #expect(project.patterns[1].drumTakes?.last?.label == "Fill")
        try project.validate()
        DrumTakes.delete(&project.patterns[1], take: id)
        #expect(project.patterns[1] == before)
        #expect(FillGenerator.add(.snare, beats: 4, endingAt: barTicks * 10, to: &project.patterns[1]) == nil)
    }

    @Test func compTakesChosenBarsAndMutesTheSources() throws {
        var pattern = Pattern(length: barTicks * 2)
        let one = DrumTake(number: 1), two = DrumTake(number: 2)
        func hit(_ tick: Int, _ take: DrumTake) -> DrumEvent { var h = DrumEvent(tick: tick, pad: 4); h.take = take.id; return h }
        pattern.drums = [hit(0, one), hit(barTicks, one), hit(240, two), hit(barTicks + 240, two)]
        pattern.drumTakes = [one, two]
        let comp = try #require(DrumTakes.comp(&pattern, choices: [0: one.id, 1: two.id]))
        let compHits = pattern.drums.filter { $0.take == comp }.map(\.tick).sorted()
        #expect(compHits == [0, barTicks + 240])
        let muted: Set<UUID> = Set((pattern.drumTakes ?? []).filter { $0.muted == true }.map(\.id))
        #expect(muted == Set([one.id, two.id]))
        #expect(pattern.drumTakes?.last?.label == "Comp")
        let unknown: [Int: UUID] = [0: UUID()]
        #expect(DrumTakes.comp(&pattern, choices: unknown) == nil)
    }
}

struct FormTemplateTests {
    @Test func everyTemplateFitsAndRebuildsAnEmptySong() throws {
        for template in FormTemplate.all {
            var project = Project(name: "Blank")
            try FormEditing.apply(template.sections, to: &project)
            #expect(project.sections.map(\.length) == template.sections.map { $0.bars * barTicks }, "\(template.id)")
            try project.validate()
        }
    }

    @Test func aSongWithMusicKeepsItAndGetsTheRestAppended() throws {
        var project = Project.demo()
        let beat = project.patterns[1].drums
        try FormEditing.apply([("Verse", 4), ("Chorus", 8)], to: &project)
        #expect(project.sections.count == 2 && project.sections[1].length == 8 * barTicks)
        #expect(project.patterns[1].drums == beat)
    }

    @Test func timingsRoundToMusicalLengths() {
        // 120 BPM: one bar is 2 s. Parts at 0, 15.5, 32 and 33.5 s; the song ends at 48 s.
        #expect(FormFromTimings.bars(starts: [0, 15.5, 32, 33.5], end: 48, bpm: 120) == [8, 8, 2, 8])
        #expect(FormFromTimings.bars(starts: [], end: 10, bpm: 0).isEmpty)
    }

    @Test func catalogueAcceptsSongsWithMoreThanEightSections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Form-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project(name: "Long")
        try FormEditing.apply(FormTemplate.all.first { $0.id == "pop" }!.sections, to: &project)
        #expect(project.sections.count == 10)
        let store = ProjectStore(root: folder)
        try await store.save(project)
        #expect(await store.summary(project.id).summary?.bars == 64)
    }
}
