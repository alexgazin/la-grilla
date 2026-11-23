import Foundation
import Testing
@testable import MusicDomain

struct SyllableTests {
    @Test(arguments: [
        ("любовь", ["лю", "бовь"]), ("молоко", ["мо", "ло", "ко"]), ("музыка", ["му", "зы", "ка"]),
        ("сердце", ["сер", "дце"]), ("майка", ["май", "ка"]), ("дом", ["дом"]),
        ("music", ["mu", "sic"]), ("time", ["time"]), ("rain", ["rain"]), ("tonight", ["to", "night"]), ("hello", ["hel", "lo"]),
    ])
    func wordsSplitIntoSyllables(word: String, expected: [String]) {
        #expect(Syllables.split(word) == expected, "\(word) → \(Syllables.split(word))")
    }

    @Test func linesAreHyphenatedAndLaidOnNotesInOrder() {
        #expect(Syllables.line("Моя любовь, music!") == ["Мо-", "я", "лю-", "бовь", "mu-", "sic"])
        let notes = (0..<4).map { NoteEvent(tick: $0 * 480, duration: 480, pitch: 60, velocity: 90) }
        let (laid, balance) = Syllables.assign("мо-ло-ко\nдом да", to: notes)
        #expect(laid.map(\.syllable) == ["мо-", "ло-", "ко", "дом"])
        #expect(balance == 1)
        let (short, missing) = Syllables.assign("да", to: notes)
        #expect(short.compactMap(\.syllable) == ["да"] && missing == -3)
    }

    @Test func syllablesAreWrittenAsMIDILyrics() throws {
        var project = Project.demo()
        try project.addMelody(name: "Voice")
        let id = project.tracks[3].clips[0].patternID
        let index = project.patterns.firstIndex { $0.id == id }!
        var note = NoteEvent(tick: 0, duration: 480, pitch: 64, velocity: 90); note.syllable = "лю-"
        project.patterns[index].notes = [note]
        try project.validate()
        let data = try MIDIExporter.data(project)
        let bytes = [UInt8](data)
        let lyric = [UInt8(0xFF), 0x05, UInt8("лю-".utf8.count)] + Array("лю-".utf8)
        #expect(bytes.indices.contains { bytes[$0...].starts(with: lyric) })
    }

    @Test func olderFilesWithoutLyricsStillDecode() throws {
        let project = Project.demo()
        let decoded = try ProjectDocument.decode(JSONEncoder().encode(project))
        #expect(decoded.sections.allSatisfy { $0.lyrics == nil })
    }
}

struct DAWPackageTests {
    @Test func readmeNamesTempoKeySectionsAndTracks() throws {
        var project = Project.demo()
        try project.duplicateSection(project.sections[0].id, name: "Chorus")
        let text = DAWPackage.readme(project, settings: WAVSettings())
        #expect(text.contains("Tempo: 120 BPM"))
        #expect(text.contains("bar 1: Verse (4 bars)") && text.contains("bar 5: Chorus (4 bars)"))
        #expect(text.contains("01-harmony.wav") && text.contains("02-drums.wav"))
        let extras = try DAWPackage.extras(project, range: nil, settings: WAVSettings())
        #expect(extras.map(\.name) == ["song.mid", "README.txt"])
        #expect(extras[0].data.starts(with: Array("MThd".utf8)))
    }
}
