import Foundation
import Testing
@testable import MusicDomain

struct GrooveArrangementTests {
    @Test func assistantRoutesTheReportedBilingualStyleRequest() throws {
        let text = "Create jazz hip hop old school"
        let brief = try #require(try TrackBrief.offlineCreationRequest(text))
        #expect(brief.style == .hipHop && brief.hipHopFeel == .boomBap)
        #expect(brief.chordText.contains("7"))
        let project = try brief.makeProject(name: text)
        #expect(Set(Compiler.notes(project).map(\.track)) == [0,1,2,3])
        let explicit = try #require(try TrackBrief.offlineCreationRequest("Создай джазовый хип-хоп, 90 BPM, аккорды: Am F C G"))
        #expect(explicit.tempo == 90 && explicit.chordText == "Am F C G")
        #expect(try TrackBrief.offlineCreationRequest("Create a song form: 8 bars of jazz") == nil)
        #expect(try TrackBrief.offlineCreationRequest("Change the verse to jazz") == nil)
        #expect(throws: TrackBriefError.self) { try TrackBrief.offlineCreationRequest("Make a hip hop beat at 999 BPM") }
    }

    @Test func russianAndEnglishPromptsCreateTheSameEditableForm() throws {
        let ru = try TrackBrief().suggesting("Бум-бэп, 8 тактов, 88 BPM, ре минор. Первые четыре — только бас и барабаны. Перед повтором полтакта тишины.")
        let en = try TrackBrief().suggesting("8 bars of boom bap at 88 BPM in D minor. First 4 bars only bass and drums. Half-bar break before the loop.")
        #expect(ru == en)
        #expect(ru.introBars == 4 && ru.bars == 8 && ru.tempo == 88 && ru.endBreak)
        let song = try ru.makeProject(name: "Offline")
        let notes = Compiler.notes(song)
        #expect(song.sections.map(\.length) == [4*barTicks, 4*barTicks])
        #expect(Set(notes.filter { $0.tick < 4*barTicks }.map(\.track)) == [1,2])
        #expect(Set(notes.filter { $0.tick >= 4*barTicks }.map(\.track)) == [0,1,2,3])
        #expect(notes.allSatisfy { $0.tick+$0.duration <= song.length-barTicks/2 })
        let reopened = try PortableProject.decode(PortableProject.data(song), asCopy:false)
        #expect(Compiler.notes(reopened) == notes)
    }

    @Test func independentVariationsPreserveEveryOtherPart() throws {
        let initial = try TrackBrief().suggesting("West Coast, 8 bars, 96 BPM in E minor")
        let original = Compiler.notes(try initial.makeProject(name:"Initial"))
        for (prompt, changed) in [("Сохрани бас, замени только ударные",1),("Change only the bass",2)] {
            let edited = try initial.suggesting(prompt)
            let new = Compiler.notes(try edited.makeProject(name:"Variation"))
            #expect(original.filter{$0.track != changed} == new.filter{$0.track != changed})
            #expect(original.filter{$0.track == changed} != new.filter{$0.track == changed})
        }
        let pocket = try initial.suggesting("Boom bap, 8 bars at 96 BPM in E minor")
        let boom = Compiler.notes(try pocket.makeProject(name:"Pocket"))
        #expect(original.contains{$0.track == 1 && $0.pad == 4})
        #expect(!boom.contains{$0.track == 1 && $0.pad == 4})
        #expect(original.filter{$0.track==2} != boom.filter{$0.track==2})
    }

    @Test func everyPresetBuildsAndImpossibleIntrosAreRejected() throws {
        for preset in GroovePreset.library {
            let song = try preset.recipe.makeProject(name:preset.name)
            try song.validate()
            #expect(song.length == preset.recipe.bars*barTicks)
            #expect(Set(Compiler.notes(song).map(\.track)) == [0,1,2,3])
        }
        #expect(throws: TrackBriefError.self) { try TrackBrief().suggesting("4 bars of house, first 4 bars bass and drums") }
        let brief = try TrackBrief().suggesting("First 2 bars bass and drums")
        #expect(brief.bars == 8 && brief.introBars == 2)
    }
}
