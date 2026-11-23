import Foundation

/// I21 · Progressions by mood, each with a one-line reason.
public enum Mood: String, CaseIterable, Sendable {
    case sad, bright, tense, nostalgic, driving
    public var title: String {
        switch self { case .sad: "Sad"; case .bright: "Bright"; case .tense: "Tense"; case .nostalgic: "Nostalgic"; case .driving: "Driving" }
    }
}

public enum MoodProgressions {
    public struct Option: Equatable, Sendable {
        /// Scale degrees from the key root with qualities (one chord per bar).
        public let chords: [Chord]
        public let numerals: String
        /// English reason, also the localization key.
        public let reason: String
    }

    private typealias Step = (interval: Int, quality: Quality, numeral: String)
    private static let library: [Mood: [([Step], String)]] = [
        .sad: [([(9, .minor, "vi"), (5, .major, "IV"), (0, .major, "I"), (7, .major, "V")], "Starts on the minor sixth: a hopeful song that leans sad."),
               ([(0, .minor, "i"), (8, .major, "VI"), (3, .major, "III"), (10, .major, "VII")], "The natural-minor loop: wide, melancholic, cinematic."),
               ([(0, .minor, "i"), (5, .minor, "iv"), (0, .minor, "i"), (7, .major, "V")], "Minor with a major V: grief that resolves."),
               ([(5, .major, "IV"), (7, .major, "V"), (4, .minor, "iii"), (9, .minor, "vi")], "Rises, then falls onto the minor sixth: bright sadness.")],
        .bright: [([(0, .major, "I"), (7, .major, "V"), (9, .minor, "vi"), (5, .major, "IV")], "The pop loop everyone hums: open and warm."),
                  ([(0, .major, "I"), (5, .major, "IV"), (7, .major, "V"), (5, .major, "IV")], "Three major chords going home: sunny and simple."),
                  ([(0, .maj7, "Imaj7"), (2, .m7, "ii7"), (4, .m7, "iii7"), (5, .maj7, "IVmaj7")], "Stepwise sevenths: soft, airy, a little jazzy."),
                  ([(0, .major, "I"), (2, .major, "II"), (5, .major, "IV"), (0, .major, "I")], "A major II borrowed from the dominant: a lift.")],
        .tense: [([(0, .minor, "i"), (1, .major, "♭II"), (0, .minor, "i"), (7, .seventh, "V7")], "The flat second hangs over the tonic: menace."),
                 ([(0, .minor, "i"), (10, .major, "♭VII"), (8, .major, "♭VI"), (7, .seventh, "V7")], "A falling bass into a dominant seventh: the build before a drop."),
                 ([(0, .minor, "i"), (6, .dim, "♯iv°"), (7, .seventh, "V7"), (0, .minor, "i")], "The diminished chord sharpens the pull home."),
                 ([(0, .sus4, "Isus4"), (0, .major, "I"), (10, .major, "♭VII"), (5, .sus2, "IVsus2")], "Suspended chords that never quite settle.")],
        .nostalgic: [([(0, .maj7, "Imaj7"), (9, .m7, "vi7"), (2, .m7, "ii7"), (7, .seventh, "V7")], "The old turnaround: records, rooms, summers."),
                     ([(5, .maj7, "IVmaj7"), (4, .m7, "iii7"), (2, .m7, "ii7"), (0, .maj7, "Imaj7")], "Walks down to home: a fond look back."),
                     ([(0, .major, "I"), (4, .major, "III"), (9, .minor, "vi"), (5, .minor, "iv")], "A major III and a minor iv: memories with a sting."),
                     ([(0, .major, "I"), (5, .minor, "iv"), (0, .major, "I"), (5, .minor, "iv")], "The borrowed minor iv: bittersweet.")],
        .driving: [([(0, .minor, "i"), (10, .major, "♭VII"), (8, .major, "♭VI"), (10, .major, "♭VII")], "Rock's engine: three chords that keep moving."),
                   ([(0, .major, "I"), (10, .major, "♭VII"), (5, .major, "IV"), (0, .major, "I")], "Mixolydian swagger: forward without resolving."),
                   ([(0, .minor, "i"), (8, .major, "VI"), (10, .major, "VII"), (0, .minor, "i")], "Epic minor that comes straight back home."),
                   ([(0, .major, "I"), (7, .major, "V"), (5, .major, "IV"), (7, .major, "V")], "Bounces between IV and V: endless energy.")],
    ]

    public static func options(_ mood: Mood, keyRoot: Int) -> [Option] {
        (library[mood] ?? []).map { steps, reason in
            Option(chords: steps.map { Chord(root: (keyRoot + $0.interval) % 12, quality: $0.quality) },
                   numerals: steps.map(\.numeral).joined(separator: " – "), reason: reason)
        }
    }

    /// One chord per bar across `bars`, repeating the progression.
    public static func events(_ option: Option, bars: Int) -> [ChordEvent] {
        (0..<max(1, bars)).map { ChordEvent(tick: $0 * barTicks, chord: option.chords[$0 % option.chords.count]) }
    }
}

/// I26 · Euclidean rhythms: N hits spread as evenly as possible over M steps.
public enum Euclid {
    public static func pattern(hits: Int, steps: Int, rotate: Int = 0) -> [Bool] {
        guard steps > 0 else { return [] }
        let count = min(max(0, hits), steps)
        var result = (0..<steps).map { index in (index * count) % steps < count }
        // Bresenham places the first hit at step 0; rotate moves the start.
        let shift = ((rotate % steps) + steps) % steps
        if shift > 0 { result = Array(result[(steps - shift)...] + result[..<(steps - shift)]) }
        return result
    }

    /// Replaces a pad's hits in one bar of a pattern with the Euclidean rhythm (16 steps).
    public static func apply(hits: Int, steps: Int = 16, rotate: Int = 0, pad: Int, bar: Int, velocity: Int = 100, to pattern: inout Pattern) {
        let start = bar * barTicks, step = barTicks / steps
        pattern.drums.removeAll { $0.pad == pad && $0.tick >= start && $0.tick < start + barTicks }
        for (index, on) in self.pattern(hits: hits, steps: steps, rotate: rotate).enumerated() where on && start + index * step < pattern.length {
            pattern.drums.append(DrumEvent(tick: start + index * step, pad: pad, velocity: velocity))
        }
        pattern.drums.sort { $0.tick == $1.tick ? $0.pad < $1.pad : $0.tick < $1.tick }
    }
}

/// I28 · A second voice a third or a sixth away, kept inside the key.
public enum Harmonizer {
    public enum Interval: Int, CaseIterable, Sendable { case thirdAbove = 2, sixthAbove = 5, thirdBelow = -2, sixthBelow = -5
        public var title: String { switch self { case .thirdAbove: "A third above"; case .sixthAbove: "A sixth above"; case .thirdBelow: "A third below"; case .sixthBelow: "A sixth below" } }
    }

    /// Moves every note by `interval` scale steps in the key; notes outside the key move by
    /// the nearest scale note. Pitches stay within 0…127.
    public static func secondVoice(_ notes: [NoteEvent], keyRoot: Int, minor: Bool, interval: Interval) -> [NoteEvent] {
        let scale = (minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]).map { ($0 + keyRoot) % 12 }.sorted()
        func index(of pitch: Int) -> (octave: Int, degree: Int) {
            let pc = pitch % 12
            let degree = scale.enumerated().min { abs($0.element - pc) < abs($1.element - pc) }!.offset
            return (pitch / 12, degree)
        }
        return notes.map { note in
            let (octave, degree) = index(of: note.pitch)
            let total = degree + interval.rawValue
            let newOctave = octave + Int(floor(Double(total) / 7)), newDegree = ((total % 7) + 7) % 7
            var voiced = note
            voiced.id = UUID()
            voiced.syllable = nil
            voiced.pitch = min(127, max(0, newOctave * 12 + scale[newDegree]))
            voiced.velocity = max(1, note.velocity - 8)
            return voiced
        }
    }
}

/// I30 · Chord diagrams for guitar and ukulele (common open and barre shapes).
public enum ChordShapes {
    public enum Instrument: String, CaseIterable, Sendable { case guitar, ukulele
        public var tuning: [Int] { self == .guitar ? [40, 45, 50, 55, 59, 64] : [67, 60, 64, 69] }
    }
    /// Fret per string (low to high for guitar, G-C-E-A for ukulele); -1 = not played.
    public struct Shape: Equatable, Sendable { public let frets: [Int]; public var baseFret: Int { frets.filter { $0 > 0 }.min() ?? 0 } }

    /// The lowest playable shape whose sounding notes are exactly the chord's pitch classes
    /// (every chord tone at least once, nothing else), searched up to the 7th fret.
    public static func shape(for chord: Chord, on instrument: Instrument) -> Shape? {
        let tones = Set(chord.notes.map { $0 % 12 })
        let strings = instrument.tuning
        var best: (shape: [Int], score: Int)?
        func search(_ string: Int, _ current: [Int]) {
            if string == strings.count {
                let sounding = current.enumerated().filter { $0.element >= 0 }.map { (strings[$0.offset] + $0.element) % 12 }
                guard !sounding.isEmpty, Set(sounding) == tones else { return }
                let fretted = current.filter { $0 > 0 }
                guard let low = fretted.min(), let high = fretted.max() else {
                    best = (current, -1); return   // all open strings
                }
                guard high - low <= 3 else { return }
                // Prefer the root in the bass, low positions, more open strings, fewer muted.
                let bass = current.enumerated().first { $0.element >= 0 }.map { (strings[$0.offset] + $0.element) % 12 } ?? -1
                let score = low * 4 + current.filter { $0 < 0 }.count * 3 - current.filter { $0 == 0 }.count + (instrument == .ukulele || bass == chord.root % 12 ? 0 : 6)   // ukulele is re-entrant: no bass string
                if best == nil || score < best!.score { best = (current, score) }
                return
            }
            for fret in -1...7 {
                if fret >= 0, !tones.contains((strings[string] + fret) % 12) { continue }
                // Only the lowest strings may be muted on guitar.
                if fret < 0, instrument == .guitar, string > 1, current.contains(where: { $0 >= 0 }) { continue }
                if fret < 0, instrument == .ukulele { continue }
                search(string + 1, current + [fret])
            }
        }
        search(0, [])
        return best.map { Shape(frets: $0.shape) }
    }
}

/// I27 · Ratchets: a step that repeats 2–4 times within its sixteenth, fading.
public enum Ratchet {
    public static func expand(_ hit: DrumEvent, times: Int, step: Int = barTicks / 16) -> [DrumEvent] {
        let count = min(4, max(1, times))
        guard count > 1 else { return [hit] }
        return (0..<count).map { index in
            var copy = hit
            copy.id = index == 0 ? hit.id : UUID()
            copy.tick = hit.tick + index * step / count
            copy.velocity = max(1, hit.velocity - index * 14)
            return copy
        }
    }
}
