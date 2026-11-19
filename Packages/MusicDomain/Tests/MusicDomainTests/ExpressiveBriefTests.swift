import Testing
@testable import MusicDomain

struct ExpressiveBriefTests {
    static let chillhop = """
        Песня в стиле chillhop. Около 90 бпм. Тональность ми натуральный минор.
        Вступление один такт флейта и сразу начинается бит, атмосферное слегка опаздывающее пианино.
        Первая часть аккорды: C, D, B, E
        16 тактов с развитием. Далее вторая часть арпеджио этих аккордов и завершаем ударом гонга
        """
    static let ambient = """
        Песня для медитации. В стиле эмбиент. Длинные дилеи или подобные эффекты.
        Основные 4 аккорда песни C, Bb, G, Ab .
        Первая часть 8 тактов как вступление, далее вторая часть добавляем соло на флейте Бансури. 8 тактов.
        Третья часть добавляем немного клавиш и далее потихоньку рассеиваем звук что бы закончить трек
        """

    @Test func chillhopAuthoringAndInheritedHarmony() throws {
        let brief = try #require(try TrackBrief.offlineCreationRequest(Self.chillhop))
        var form = try #require(brief.songForm)
        #expect(brief.style == .hipHop && brief.tempo == 90 && brief.root == 4 && brief.minor && brief.laidBackKeys)
        #expect(form.parts.map(\.role) == [.fluteIntro,.developingBeat,.arpeggio,.gong])
        #expect(form.parts.map(\.bars) == [1,16,8,1])
        #expect(form.parts.map(\.proposedBars) == [false,false,true,true])
        #expect(form.parts[2].chordSource == 1 && !form.proposedTempo && !form.proposedKey)
        #expect(try form.resolvedChords(for: 2).map(\.quality) == Array(repeating: .major, count: 4))
        form.parts[1].chordText = "Em7 A7 F G"
        #expect(form.resolvedChordText(for: 2) == "Em7 A7 F G")
        #expect(try form.resolvedChords(for: 2).map(\.root) == [4,9,5,7])
    }

    @Test func ambientParsesEarlierGlobalHarmonyAndMarksProposals() throws {
        let brief = try #require(try TrackBrief.offlineCreationRequest(Self.ambient))
        var form = try #require(brief.songForm)
        #expect(form.arrangement == .ambient && brief.tempo == 64 && form.proposedTempo && form.proposedKey && form.longDelay)
        #expect(form.parts.map(\.bars) == [8,8,8] && form.parts.map(\.proposedBars) == [false,false,true])
        #expect(form.parts.map(\.role) == [.ambientIntro,.bansuriSolo,.keysOutro] && form.parts.map(\.chordSource) == [nil,0,0])
        #expect(form.fadeBars == 4 && form.proposedFadeBars)
        form.parts[0].chordText = "F C Gm Am"
        #expect(form.resolvedChordText(for: 2) == form.parts[0].chordText)
    }

    @Test func englishVariantsRespectSpecifiedCountsTempoAndFade() throws {
        let chill = "Chillhop 103 BPM in G natural minor. Intro two bars flute, then beat and laid-back piano. Part A 12 bars chords Cm, Eb, G, D with development. Part B four bars arpeggio of these chords. End with a gong."
        let ambient = "Ambient in Bb minor at 68 BPM. Long delay. Main chords Dm, F, Ab, C. First part 4 bars intro. Second part bansuri solo for 12 bars. Third part 6 bars sparse keys fade over 3 bars."
        let one = try TrackBrief().suggesting(chill)
        let two = try TrackBrief().suggesting(ambient)
        #expect(one.songForm?.parts.map(\.bars) == [2,12,4,1])
        #expect(one.root == 7 && one.minor && one.tempo == 103)
        #expect(two.root == 10 && two.minor && two.tempo == 68)
        #expect(two.songForm?.fadeBars == 3 && two.songForm?.proposedFadeBars == false)
        #expect(two.songForm?.parts.map(\.bars) == [4,12,6])
    }

    @Test func invalidAndAmbiguousParametersFailBeforeGeneration() throws {
        for (from,to) in [("16 тактов","80 тактов"),("один такт","0 тактов"),("90 бпм","900 бпм"),("C, D, B, E","C, H, B, E")] {
            let text = Self.chillhop.replacingOccurrences(of: from, with: to)
            #expect(throws: (any Error).self) { try TrackBrief().suggesting(text) }
        }
        let form = SongFormBrief(parts: [.init(bars: 1, chordText: "C", chordSource: 0)], order: [0])
        #expect(throws: SongFormError.self) { try form.validate() }
    }
}
