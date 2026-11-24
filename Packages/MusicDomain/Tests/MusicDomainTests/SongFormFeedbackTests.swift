import Foundation
import Testing
@testable import MusicDomain

/// Musician feedback on build 47: the Assistant asked for chords when they were written,
/// then for bar counts when chords were labelled, and refused instruments it lacks.
struct SongFormFeedbackTests {
    private func form(_ text: String) throws -> SongFormBrief {
        #expect(SongFormBrief.recognizes(text), "\(text)")
        return try #require(try TrackBrief().suggesting(text).songForm)
    }

    @Test func chordsWithoutTheWordChordsAreRead() throws {
        let text = "Часть A — 8 тактов: Db Eb Cm Fm. Часть B — 8 тактов: Bbm, Eb, Ab, Fm. Вернуться к части A."
        let result = try form(text)
        #expect(result.parts.map(\.chordText) == ["Db, Eb, Cm, Fm", "Bbm, Eb, Ab, Fm"])
        #expect(result.parts.map(\.bars) == [8, 8] && result.order == [0, 1, 0])
        #expect(result.parts.allSatisfy { !$0.proposedBars && $0.proposedChords == nil })
        let song = try TrackBrief().suggesting(text).makeProject(name: "Feedback")
        #expect(song.patterns[0].chords.map(\.chord.symbol).prefix(2) == ["D♭", "D♭"])
    }

    @Test func barsPerChordAndATotalNoLongerConflict() throws {
        let perChord = try form("Первая часть: аккорды Db, Eb, Cm, Fm по 2 такта. Вторая часть: аккорды Ab, Eb по 4 такта.")
        #expect(perChord.parts.map(\.bars) == [8, 8])
        #expect(perChord.parts[0].chordText == "Db, Eb, Cm, Fm")
        let both = try form("Part A 8 bars, chords Db Eb Cm Fm, 2 bars each. Part B chords Fm Db, 4 bars each.")
        #expect(both.parts.map(\.bars) == [8, 8], "A written total wins over the per-chord length")
        let english = try form("Part A: Db - Eb - Cm - Fm, 8 bars. Part B: Ab–Bb, 4 bars.")
        #expect(english.parts.map(\.chordText) == ["Db, Eb, Cm, Fm", "Ab, Bb"])
    }

    @Test func missingLengthsAndChordsBecomeSuggestionsNotQuestions() throws {
        let result = try form("Первая часть: Db Eb Cm Fm. Вторая часть: 4 такта, тише.")
        #expect(result.parts[0].bars == 8 && result.parts[0].proposedBars)
        #expect(result.parts[1].bars == 4 && !result.parts[1].proposedBars && result.parts[1].relaxed)
        #expect(result.parts[1].chordText == "Db, Eb, Cm, Fm" && result.parts[1].proposedChords == true)
        let keyOnly = try form("Ре минор, 100 BPM. Часть 1: 8 тактов. Часть 2: 8 тактов.")
        #expect(keyOnly.parts.allSatisfy { $0.proposedChords == true && !$0.chordText.isEmpty })
    }

    @Test func cyrillicLettersAndSectionNamesWork() throws {
        let cyrillic = try form("Часть А: 8 тактов Db Eb Cm Fm. Часть В: 4 такта Ab Bb. Снова часть А.")
        #expect(cyrillic.order == [0, 1, 0] && cyrillic.parts.count == 2)
        let alphabet = try form("Часть А: Db Eb. Часть Б: Cm Fm. Часть В: Ab Bb.")
        #expect(alphabet.parts.count == 3, "В after Б is the third part")
        let named = try form("Куплет: 8 тактов, Db Eb Cm Fm.\nПрипев: 8 тактов, Ab Eb Fm Db.\nКуплет 2:\nПрипев:\nБридж: 4 такта Bbm Cm.")
        #expect(named.parts.compactMap(\.name) == ["Куплет", "Припев", "Бридж"])
        #expect(named.order == [0, 1, 0, 1, 2] && named.totalBars == 36)
        let song = try TrackBrief().suggesting("Verse: 8 bars Am F C G. Chorus: 8 bars F G Am Am. Verse. Chorus.").makeProject(name: "Named")
        #expect(song.sections.map(\.name) == ["Verse", "Chorus", "Verse", "Chorus"])
    }

    @Test func instrumentsAndUnplayableWishesAreListed() throws {
        let result = try form("С саксофоном и скрипкой, без флейты. Часть A: 8 тактов Db Eb Cm Fm. Часть B: 8 тактов Fm Db, модуляция в конце.")
        #expect(Set(result.skipped ?? []) == ["Saxophone", "Strings", "Modulation"])
        #expect(!(result.skipped ?? []).contains("Flute"), "“Without flute” is not a wish")
        // Text before the parts may hold a length or chords without breaking the settings.
        let global = try TrackBrief().suggesting("Песня на 32 такта в до миноре, 90 BPM, аккорды Cm Ab. Часть A: 8 тактов. Часть B: 8 тактов Fm Cm.")
        #expect(global.tempo == 90 && global.root == 0 && global.minor)
        #expect(global.songForm?.parts[0].chordText == "Fm, Cm", "A part without chords repeats the nearest written part")
    }

    @Test func genuineMistakesStillExplainThemselves() {
        #expect(throws: TrackBriefError.self) { try TrackBrief().suggesting("Part A 4 bars chords F, Xq7. Part B 4 bars chords G, C.") }
        #expect(throws: SongFormError.self) { try TrackBrief().suggesting("Part A 40 bars Db Eb. Part B 40 bars Cm Fm.") }
    }

    @Test func tableEditingKeepsTheFormValid() throws {
        var table = SongFormBrief.starter(keyRoot: 1, minor: false)
        try table.validate()
        #expect(table.parts.map(\.chordText) == ["D♭, A♭, B♭m, G♭", "G♭, D♭, A♭, B♭m"])
        table.addPart(); table.addPart(); table.addPart()
        #expect(table.parts.count == SongFormBrief.maximumParts)
        try table.validate()
        table.setOrder([0, 1, 2]) // misses part D: refused
        #expect(table.order.contains(3))
        var brief = TrackBrief(); brief.songForm = table
        let song = try brief.makeProject(name: "Four parts")
        #expect(song.sections.map(\.name) == table.order.map { table.title($0) })
        table.removePart(1)
        #expect(table.parts.count == 3 && table.order.allSatisfy { $0 < 3 })
        for choice in SongFormBrief.orderChoices(parts: 3) {
            table.setOrder(choice)
            #expect(table.order == choice)
        }
        #expect(SongFormBrief.diatonic(keyRoot: 9, minor: true).map(\.symbol) == ["Am", "Bdim", "C", "Dm", "Em", "F", "G"])
    }

    @Test func theAssistantsSongCommandStaysWithTheAssistant() {
        #expect(!SongFormBrief.recognizes("Song: Tempo 108; Key D minor; Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars"))
        #expect(!SongFormBrief.recognizes("Песня: интро 4 такта: Dm Gm A Dm; припев 8 тактов: Dm Gm C F"))
        #expect(SongFormBrief.recognizes("Intro 4 bars: Dm Gm A Dm. Chorus 8 bars: Dm Gm C F."))
        #expect(SongFormBrief.recognizes("Структура: Часть A — 8 тактов: Db Eb Cm Fm. Часть B — 8 тактов: Bbm Eb Ab Fm."))
    }
}
