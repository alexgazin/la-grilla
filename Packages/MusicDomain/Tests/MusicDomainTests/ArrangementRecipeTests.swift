import Foundation
import Testing
@testable import MusicDomain

struct ArrangementRecipeTests {
    @Test func reusableDraftPreservesOriginAndLeavesManualEditsInOriginal() throws {
        let prompt = ExpressiveBriefTests.chillhop
        let brief = try TrackBrief().suggesting(prompt)
        var original = try brief.makeProject(name: "Original", sourcePrompt: prompt)
        original.bpm += 7
        original.patterns[0].notes = [NoteEvent(tick: 0, pitch: 91)]
        let reopened = try PortableProject.decode(PortableProject.data(original), asCopy: false)
        #expect(Compiler.notes(reopened) == Compiler.notes(original))
        let recipe = try #require(reopened.arrangementRecipe)
        #expect(recipe.prompt == prompt && recipe.brief == brief)
        var edited = recipe.brief
        edited.songForm?.parts[1].chordText = "F G C Am"
        let copy = try edited.makeProject(name: "Variation", sourcePrompt: recipe.prompt)
        #expect(copy.id != reopened.id && copy.bpm == 90 && reopened.bpm == 97)
        #expect(copy.arrangementRecipe?.brief.songForm?.resolvedChordText(for: 2) == "F G C Am")
        #expect(reopened.arrangementRecipe?.brief.songForm?.resolvedChordText(for: 2) == "C, D, B, E")
    }

    @Test func recipesAreBoundedAndCannotMasqueradeAsOlderDocuments() throws {
        let brief = try TrackBrief().suggesting(ExpressiveBriefTests.ambient)
        #expect(throws: (any Error).self) { try brief.makeProject(name: "Long", sourcePrompt: String(repeating:"x",count:2001)) }
        var project = try brief.makeProject(name: "Meditation")
        project.schemaVersion = 13
        project.hasComposedEnding = nil
        for index in project.patterns.indices {
            for chord in project.patterns[index].chords.indices { project.patterns[index].chords[chord].velocity = nil }
        }
        #expect(throws: MusicError.self) { try ProjectDocument.decode(JSONEncoder().encode(project)) }
        project.arrangementRecipe = nil
        let migrated = try ProjectDocument.decode(JSONEncoder().encode(project))
        #expect(migrated.arrangementRecipe == nil && migrated.schemaVersion == Project.currentSchemaVersion)
        #expect(try TrackBrief().makeProject(name:"Ordinary loop").arrangementRecipe == nil)
    }

    @Test func explicitNegativeInstructionsAreNeverRenderedAsPositive() throws {
        let en = "Chillhop in E minor at 90 BPM. No flute intro. No late piano. Part A 16 bars chords C D B E. Part B arpeggio of those chords. End without a gong."
        let ru = "Чиллхоп, 90 бпм. Без флейты. Не опаздывающее пианино. Первая часть 16 тактов аккорды C D B E. Вторая часть арпеджио этих аккордов. Конец без гонга."
        for text in [en,ru] {
            let brief = try TrackBrief().suggesting(text)
            #expect(brief.songForm?.parts.map(\.role) == [.developingBeat,.arpeggio])
            #expect(!brief.laidBackKeys)
        }
        for negative in [" Без затухания. Без длинного дилея.", " No fade. No long delay."] {
            let dry = try TrackBrief().suggesting(ExpressiveBriefTests.ambient + negative)
            #expect(dry.songForm?.fadeBars == 0 && dry.songForm?.longDelay == false)
        }
        #expect(throws: SongFormError.self) { try TrackBrief().suggesting(en + " Modulate to A minor.") }
    }
}
