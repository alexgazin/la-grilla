import Foundation
import Testing
@testable import MusicDomain

struct SongFormBriefTests {
    let workout = """
    Динамичная композиция для тренировки. Прямая бочка. Хайхэт в слабую долю. Тональность Ре минор.
    Первая часть 8 тактов аккорды по повышающей A, Bb, C, D
    Вторая часть 16 тактов аккорды D, E, F, G чуть спокойнее для передышки. И опять возвращаемся в первую часть.
    """

    @Test func musicianBriefSurvivesPlaybackAndSave() throws {
        let brief = try #require(try TrackBrief.offlineCreationRequest(workout))
        let form = try #require(brief.songForm)
        #expect(brief.tempo == 128 && brief.root == 2 && brief.minor && form.proposedTempo)
        #expect(form.order == [0,1,0] && form.totalBars == 32 && form.parts[1].relaxed)
        let song = try brief.makeProject(name: "Workout")
        #expect(song.sections.map(\.start) == [0,8*barTicks,24*barTicks])
        for track in song.tracks { #expect(track.clips[0].patternID == track.clips[2].patternID) }
        #expect(song.patterns[0].chords.map(\.chord.symbol) == ["A","A","B♭","B♭","C","C","D","D"])
        #expect(song.patterns[4].chords.map(\.chord.symbol) == ["D","E","F","G"].flatMap { Array(repeating: $0, count: 4) })
        for index in [1,5] {
            let hits = song.patterns[index].drums
            #expect(hits.filter { $0.pad == 0 }.map(\.tick) == Array(stride(from: 0, to: song.patterns[index].length, by: ppq)))
            #expect(hits.filter { $0.pad == 2 }.map(\.tick) == Array(stride(from: ppq/2, to: song.patterns[index].length, by: ppq)))
        }
        #expect((song.patterns[6].notes ?? []).count == 16)
        #expect((song.patterns[2].notes ?? []).count > 16)
        let reopened = try PortableProject.decode(PortableProject.data(song), asCopy: false)
        #expect(Compiler.notes(reopened) == Compiler.notes(song))
        #expect(Compiler.notes(reopened).contains { $0.tick >= 24*barTicks })
    }

    @Test func editingSourceUpdatesRepeatAndExplicitTempoWins() throws {
        let text = "Workout in D minor at 109 BPM. Part A 4 bars chords F, G. Part B 7 bars chords D, Am quieter. Return to part A."
        var brief = try TrackBrief().suggesting(text)
        #expect(brief.tempo == 109 && brief.songForm?.proposedTempo == false)
        brief.songForm?.parts[0].bars = 2
        brief.songForm?.parts[1].chordText = "Bb Gm"
        let song = try brief.makeProject(name: "Edited")
        #expect(song.sections.map(\.length) == [2*barTicks,7*barTicks,2*barTicks])
        #expect(song.patterns[4].chords.last?.chord.symbol == "Gm")
        #expect(throws: SongFormError.self) { try TrackBrief().suggesting(text.replacingOccurrences(of: "4 bars", with: "32 bars")) }
        #expect(throws: TrackBriefError.self) { try TrackBrief().suggesting(text.replacingOccurrences(of: "D, Am", with: "D, nonsense")) }
    }

    @Test func unsupportedInstrumentalFormsAreReported() {
        for text in [
            "Песня в стиле chillhop. Около 90 бпм. Тональность ми натуральный минор. Вступление один такт флейта и сразу начинается бит, атмосферное слегка опаздывающее пианино. Первая часть аккорды: C, D, B, E 16 тактов с развитием. Далее вторая часть арпеджио этих аккордов и завершаем ударом гонга",
            "Песня для медитации. В стиле эмбиент. Длинные дилеи или подобные эффекты. Основные 4 аккорда песни C, Bb, G, Ab. Первая часть 8 тактов как вступление, далее вторая часть добавляем соло на флейте Бансури. 8 тактов. Третья часть добавляем немного клавиш и далее потихоньку рассеиваем звук что бы закончить трек"
        ] { #expect(throws: SongFormError.self) { try TrackBrief.offlineCreationRequest(text) } }
    }
}
