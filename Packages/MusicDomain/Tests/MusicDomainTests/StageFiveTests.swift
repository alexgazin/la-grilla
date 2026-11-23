import Foundation
import Testing
@testable import MusicDomain

struct ChordTextParserTests {
    private func names(_ result: ChordTextParser.Result) -> [[String]] { result.bars.map { $0.map(\.symbol) } }

    @Test func chordLinesAboveLyricsGiveOneChordPerBar() {
        let text = """
        [Verse]
        Am        F         C        G
        Hello darkness my old friend
        Am   F   C   G
        I've come to talk with you again
        """
        let result = ChordTextParser.parse(text)
        #expect(names(result) == [["Am"], ["F"], ["C"], ["G"], ["Am"], ["F"], ["C"], ["G"]])
        #expect(result.chordLines == [1, 3])
    }

    @Test func barLinesSplitAndRepeatsExpand() {
        #expect(names(ChordTextParser.parse("| C G | Am F |")) == [["C", "G"], ["Am", "F"]])
        #expect(names(ChordTextParser.parse("|: Dm7 | G7 :| Cmaj7 |")) == [["Dm7"], ["G7"], ["Dm7"], ["G7"], ["Cmaj7"]])
        #expect(names(ChordTextParser.parse("|: E | A :| x3")) == [["E"], ["A"], ["E"], ["A"], ["E"], ["A"]])
        #expect(names(ChordTextParser.parse("| D | % | G |")) == [["D"], ["D"], ["G"]])
        #expect(names(ChordTextParser.parse("Em C G D x2")).count == 8)
    }

    @Test func russianSongbookNamingWithHIsDetected() {
        let result = ChordTextParser.parse("Am Dm E Hm\nB H7")
        #expect(names(result) == [["Am"], ["Dm"], ["E"], ["Bm"], ["B♭"], ["B7"]])
    }

    @Test func lyricsAndShortWordsAreNotChords() {
        #expect(ChordTextParser.parse("A day in the life of a fool").bars.isEmpty)
        #expect(ChordTextParser.parse("Припев:\nЛя минор это грустно").bars.isEmpty)
    }

    @Test func eventsFillEachBarEvenly() {
        let events = ChordTextParser.events([[Chord(root: 0), Chord(root: 7)], [Chord(root: 9, quality: .minor)]])
        #expect(events.map(\.tick) == [0, barTicks / 2, barTicks])
        #expect(events.map(\.duration) == [barTicks / 2, barTicks / 2, barTicks])
    }
}

struct MelodySketcherTests {
    private var chords: [ChordEvent] {
        [Chord(root: 0), Chord(root: 9, quality: .minor), Chord(root: 5), Chord(root: 7)].enumerated()
            .map { ChordEvent(tick: $0.offset * barTicks, chord: $0.element) }
    }

    @Test func strongBeatsLandOnChordTonesInsideTheRange() throws {
        let chords = self.chords
        for seed in UInt64(1)...5 {
            let melody = MelodySketcher.melody(chords: chords, length: 4 * barTicks, keyRoot: 0, minor: false, density: 0.6, seed: seed)
            #expect(!melody.isEmpty)
            #expect(melody.allSatisfy { (60...76).contains($0.pitch) && $0.tick + $0.duration <= 4 * barTicks })
            let strong = melody.filter { $0.tick % (barTicks / 2) == 0 }
            let onChord = strong.filter { note in
                let chord = chords.last { $0.tick <= note.tick }!.chord
                return chord.notes.map { $0 % 12 }.contains(note.pitch % 12)
            }
            #expect(Double(onChord.count) >= 0.8 * Double(strong.count), "seed \(seed)")
            let scale: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
            #expect(melody.allSatisfy { scale.contains($0.pitch % 12) })
            #expect(zip(melody, melody.dropFirst()).allSatisfy { abs($0.pitch - $1.pitch) <= 7 })
        }
        let a = MelodySketcher.melody(chords: chords, length: 4 * barTicks, keyRoot: 0, minor: false, seed: 9)
        let b = MelodySketcher.melody(chords: chords, length: 4 * barTicks, keyRoot: 0, minor: false, seed: 9)
        #expect(a.map(\.pitch) == b.map(\.pitch) && a.map(\.tick) == b.map(\.tick))
    }
}

struct AudioListeningTests {
    private let rate = 22_050.0

    private func clicks(bpm: Double, seconds: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        let interval = 60 / bpm
        var time = 0.0
        while time < seconds {
            let start = Int(time * rate)
            for index in 0..<min(400, samples.count - start) { samples[start + index] = Float(sin(Double(index) * 0.9)) * Float(exp(-Double(index) / 80)) }
            time += interval
        }
        return samples
    }

    private func triad(_ notes: [Int], seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { index in
            Float(notes.reduce(0.0) { $0 + sin(2 * .pi * 440 * pow(2, Double($1 - 69) / 12) * Double(index) / rate) } / Double(notes.count))
        }
    }

    @Test func clickTrackTempoIsFound() throws {
        for bpm in [90.0, 120.0, 140.0] {
            let found = try #require(AudioListening.tempo(clicks(bpm: bpm, seconds: 8), sampleRate: rate))
            #expect(abs(found - bpm) <= 1.5, "\(bpm) → \(found)")
        }
    }

    @Test func aTriadProgressionIsRecognised() {
        let audio = triad([60, 64, 67], seconds: 1) + triad([57, 60, 64], seconds: 1) + triad([53, 57, 60], seconds: 1) + triad([55, 59, 62], seconds: 1)
        let found = AudioListening.chords(audio, sampleRate: rate, segmentSeconds: 1).map(\.chord.symbol)
        #expect(found == ["C", "Am", "F", "G"])
    }
}
