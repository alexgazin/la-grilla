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

struct MasterAssistantTests {
    @Test func aQuietMixIsRaisedToTheTargetWithTheLimiterOnlyWhenPeaksNeedIt() {
        let quiet = LoudnessMeter.Measurement(integratedLUFS: -20, samplePeak: pow(10, -10.0 / 20))
        let lift = MasterAssistant.suggest(measured: quiet, currentMaster: -3, target: .streaming)
        #expect(lift.master == 3 && lift.predictedLUFS == -14 && lift.advice == "louder")
        #expect(lift.limiter == false && lift.limiterReduction == 0)
        let peaky = LoudnessMeter.Measurement(integratedLUFS: -18, samplePeak: pow(10, -2.0 / 20))
        let limited = MasterAssistant.suggest(measured: peaky, currentMaster: -3, target: .streaming)
        #expect(limited.limiter && limited.limiterReduction == 3)
    }

    @Test func tooLoudStopsAtSixDecibelsOfLimitingAndQuietTargetsLowerTheMaster() {
        let dense = LoudnessMeter.Measurement(integratedLUFS: -20, samplePeak: 1)
        let club = MasterAssistant.suggest(measured: dense, currentMaster: -3, target: .club)
        #expect(club.advice == "tooLoud" && club.limiterReduction == 6 && club.predictedLUFS < MasterTarget.club.lufs)
        let loud = LoudnessMeter.Measurement(integratedLUFS: -10, samplePeak: pow(10, -1.5 / 20))
        let apple = MasterAssistant.suggest(measured: loud, currentMaster: 0, target: .appleMusic)
        #expect(apple.master == -6 && apple.advice == "quieter" && !apple.limiter)
        #expect(MasterAssistant.suggest(measured: .init(integratedLUFS: -200, samplePeak: 0), currentMaster: -3, target: .streaming).advice == "silent")
    }
}

struct HarmonyExplainerTests {
    @Test(arguments: [
        (0, Quality.major, false, "I", "tonic"), (9, .minor, false, "vi", "tonic"), (5, .major, false, "IV", "subdominant"),
        (7, .seventh, false, "V", "dominant"), (10, .major, false, "♭VII", "borrowed"), (2, .minor, false, "ii", "subdominant"),
        (9, .minor, true, "i", "tonic"), (2, .minor, true, "iv", "subdominant"), (4, .major, true, "V", "dominant"), (5, .major, true, "VI", "tonic"),
    ])
    func degreesAndFunctions(root: Int, quality: Quality, minor: Bool, degree: String, function: String) {
        let key = minor ? 9 : 0
        let result = HarmonyExplainer.explain(Chord(root: root, quality: quality), previous: nil, keyRoot: key, minor: minor)
        #expect(result.degree == degree, "\(root)\(quality.rawValue) → \(result.degree)")
        #expect(result.function == function)
        #expect(!result.text.isEmpty)
    }

    @Test func rootMotionIsNamed() {
        let toC = HarmonyExplainer.explain(Chord(root: 0), previous: Chord(root: 7, quality: .seventh), keyRoot: 0, minor: false)
        #expect(toC.text.contains("up a fourth"))
    }
}
