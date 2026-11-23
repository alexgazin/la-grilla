import Foundation

/// I49 · A lead sheet in MusicXML 4.0 (partwise): the melody with chord symbols above
/// and lyrics below, one part, 4/4, the song's key and tempo. Without a melody the
/// chords are written as slash rests so the sheet still carries the harmony.
public enum MusicXMLExporter {
    private static let divisions = ppq   // one quarter = ppq ticks
    private static let steps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    private static let alters = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
    private static let kinds: [Quality: String] = [.major: "major", .minor: "minor", .seventh: "dominant", .maj7: "major-seventh", .m7: "minor-seventh",
                                                   .dim: "diminished", .aug: "augmented", .sus2: "suspended-second", .sus4: "suspended-fourth", .m7b5: "half-diminished",
                                                   .sixth: "major-sixth", .m6: "minor-sixth", .ninth: "dominant-ninth", .maj9: "major-ninth", .m9: "minor-ninth"]
    private static let majorFifths = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]
    private static let minorFifths = [-3, 4, -1, -6, 1, -4, 3, -2, 5, 0, -5, 2]

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func noteType(_ duration: Int) -> String {
        switch duration {
        case (barTicks)...: "whole"
        case (barTicks / 2)...: "half"
        case (ppq)...: "quarter"
        case (ppq / 2)...: "eighth"
        case (ppq / 4)...: "16th"
        default: "32nd"
        }
    }

    private static func pitch(_ midi: Int) -> String {
        let pc = midi % 12
        let alter = alters[pc] != 0 ? "<alter>1</alter>" : ""
        return "<pitch><step>\(steps[pc])</step>\(alter)<octave>\(midi / 12 - 1)</octave></pitch>"
    }

    private static func chordSymbol(_ chord: Chord) -> String {
        let pc = chord.root % 12
        let alter = alters[pc] != 0 ? "<root-alter>1</root-alter>" : ""
        let kind = kinds[chord.quality] ?? "major"
        let bass = chord.slashBass.map { b in "<bass><bass-step>\(steps[b % 12])</bass-step>\(alters[b % 12] != 0 ? "<bass-alter>1</bass-alter>" : "")</bass>" } ?? ""
        return "<harmony><root><root-step>\(steps[pc])</root-step>\(alter)</root><kind text=\"\(escape(chord.quality.rawValue))\">\(kind)</kind>\(bass)</harmony>"
    }

    public static func data(_ project: Project) -> Data {
        let length = max(barTicks, project.length)
        let spans = Arrangement.harmony(project, section: Section(name: "Song", start: 0, length: length))
        let melodyTrack = project.tracks.first { $0.role == .melody }
        var notes: [NoteEvent] = []
        for clip in melodyTrack?.clips ?? [] {
            guard let pattern = project.patterns.first(where: { $0.id == clip.patternID }), pattern.length > 0 else { continue }
            for cycle in stride(from: -clip.offset, to: clip.length, by: pattern.length) {
                for note in pattern.notes ?? [] where cycle + note.tick >= 0 && cycle + note.tick < clip.length {
                    var placed = note; placed.tick = clip.start + cycle + note.tick
                    placed.duration = min(note.duration, clip.start + clip.length - placed.tick)
                    notes.append(placed)
                }
            }
        }
        // Monophonic line: the highest note wins where notes overlap.
        notes.sort { $0.tick == $1.tick ? $0.pitch > $1.pitch : $0.tick < $1.tick }
        var line: [NoteEvent] = []
        for note in notes {
            if let last = line.last, note.tick < last.tick + last.duration { if note.tick == last.tick { continue }; line[line.count - 1].duration = note.tick - last.tick }
            line.append(note)
        }
        let fifths = (project.minor ? minorFifths : majorFifths)[project.keyRoot % 12]
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0"><work><work-title>\(escape(project.name))</work-title></work>
        <identification><encoding><software>La Grilla</software></encoding></identification>
        <part-list><score-part id="P1"><part-name>\(escape(melodyTrack?.displayName ?? "Lead sheet"))</part-name></score-part></part-list><part id="P1">
        """
        let bars = length / barTicks
        for bar in 0..<bars {
            let start = bar * barTicks, end = start + barTicks
            xml += "<measure number=\"\(bar + 1)\">"
            if bar == 0 {
                xml += "<attributes><divisions>\(divisions)</divisions><key><fifths>\(fifths)</fifths><mode>\(project.minor ? "minor" : "major")</mode></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>"
                xml += "<direction placement=\"above\"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(Int(project.bpm.rounded()))</per-minute></metronome></direction-type><sound tempo=\"\(Int(project.bpm.rounded()))\"/></direction>"
            }
            if let section = project.sections.first(where: { $0.start == start }) {
                xml += "<direction placement=\"above\"><direction-type><rehearsal>\(escape(section.name))</rehearsal></direction-type></direction>"
            }
            // Events in this bar: chord changes and notes, written in time order with rests between.
            let chordStarts = spans.filter { $0.tick >= start && $0.tick < end }
            var cursor = start
            var chordIndex = 0
            func writeChords(upTo tick: Int) {
                while chordIndex < chordStarts.count && chordStarts[chordIndex].tick <= tick {
                    let event = chordStarts[chordIndex]
                    if event.tick > cursor { xml += rest(event.tick - cursor); cursor = event.tick }
                    xml += chordSymbol(event.chord); chordIndex += 1
                }
            }
            for note in line where note.tick >= start && note.tick < end {
                writeChords(upTo: note.tick)
                if note.tick > cursor { xml += rest(note.tick - cursor) }
                let duration = max(1, min(note.duration, end - note.tick))
                let lyric = note.syllable.map { syllable -> String in
                    let hyphen = syllable.hasSuffix("-")
                    return "<lyric><syllabic>\(hyphen ? "begin" : "single")</syllabic><text>\(escape(hyphen ? String(syllable.dropLast()) : syllable))</text></lyric>"
                } ?? ""
                xml += "<note>\(pitch(note.pitch))<duration>\(duration)</duration><type>\(noteType(duration))</type>\(lyric)</note>"
                cursor = note.tick + duration
            }
            writeChords(upTo: end)
            if cursor < end { xml += rest(end - cursor) }
            xml += "</measure>"
        }
        xml += "</part></score-partwise>\n"
        return Data(xml.utf8)
    }

    private static func rest(_ duration: Int) -> String { "<note><rest/><duration>\(duration)</duration><type>\(noteType(duration))</type></note>" }
}

/// I57 · A gentle check of the song: places worth a second look, never errors.
public enum ArrangementDoctor {
    public struct Finding: Equatable, Sendable {
        public enum Kind: String, Sendable { case clashWithChord, longWithoutChange, emptySection, tooDense, melodyOutOfRange }
        public let kind: Kind
        /// One-based song bar where it is.
        public let bar: Int
        /// English text, also the localization key (with %lld for the bar).
        public let message: String
    }

    public static func check(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        let notes = Compiler.notes(project)
        let harmonyIndex = project.tracks.firstIndex { $0.role == .harmony }
        let melodic = notes.filter { $0.pad < 0 && $0.track != harmonyIndex && project.tracks.indices.contains($0.track) && project.tracks[$0.track].role == .melody }
        let chordSpans = Arrangement.harmony(project, section: Section(name: "Song", start: 0, length: max(barTicks, project.length)))
        // Long melody notes a semitone away from a chord tone on a strong beat.
        var flagged = Set<Int>()
        for note in melodic where note.duration >= ppq && note.tick % (barTicks / 2) == 0 {
            guard let chord = chordSpans.last(where: { $0.tick <= note.tick && note.tick < $0.tick + $0.duration })?.chord else { continue }
            let tones = Set(chord.notes.map { $0 % 12 }), pc = note.pitch % 12
            if !tones.contains(pc) && (tones.contains((pc + 1) % 12) || tones.contains((pc + 11) % 12)) {
                let bar = note.tick / barTicks + 1
                if flagged.insert(bar).inserted {
                    findings.append(Finding(kind: .clashWithChord, bar: bar, message: "Bar %lld: a long melody note rubs a semitone against the chord."))
                }
            }
        }
        for section in project.sections {
            let bar = section.start / barTicks + 1
            let inside = notes.filter { $0.tick >= section.start && $0.tick < section.start + section.length }
            if inside.isEmpty { findings.append(Finding(kind: .emptySection, bar: bar, message: "Bar %lld: this section is silent.")) }
            let bars = max(1, section.length / barTicks)
            if inside.count / bars > 64 { findings.append(Finding(kind: .tooDense, bar: bar, message: "Bar %lld: very busy — try removing a layer so the main part breathes.")) }
            if section.length >= 16 * barTicks {
                let chordsHere = Set(chordSpans.filter { $0.tick >= section.start && $0.tick < section.start + section.length }.map(\.chord.symbol))
                if chordsHere.count <= 1 { findings.append(Finding(kind: .longWithoutChange, bar: bar, message: "Bar %lld: 16 bars or more on one chord — a change would keep it moving.")) }
            }
        }
        if let low = melodic.map(\.pitch).min(), let high = melodic.map(\.pitch).max(), high - low > 19 {
            let bar = (melodic.first { $0.pitch == high }?.tick ?? 0) / barTicks + 1
            findings.append(Finding(kind: .melodyOutOfRange, bar: bar, message: "Bar %lld: the melody spans more than an octave and a half — hard to sing."))
        }
        return findings.sorted { $0.bar < $1.bar }
    }
}

/// I69 · An idea for today, the same for everyone on the same day, without the network.
public enum DailyPrompt {
    public struct Idea: Equatable, Sendable {
        public let bpm: Int
        public let keyRoot: Int
        public let minor: Bool
        /// English, also the localization key.
        public let task: String
    }
    private static let tasks = [
        "A beat using only toms and the clap.", "Four chords, then change only the last one in the chorus.",
        "A melody that uses just three notes.", "A groove where the kick never lands on beat one.",
        "A short loop that sounds like rain.", "Start from the bass line, add chords last.",
        "A song in two sections that share no chords.", "Hum a melody first, then find the chords under it.",
        "A beat with ghost notes on every offbeat.", "Write the chorus before anything else.",
        "Use a borrowed chord from the parallel minor.", "A sixteen-bar idea with a key change in the middle.",
    ]
    public static func idea(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Idea {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        var random = SeededRandom(seed: UInt64(day) &* 2_654_435_761)
        let tempos = [70, 76, 82, 88, 92, 96, 100, 108, 116, 124, 132, 140]
        return Idea(bpm: tempos[Int(random.next() % UInt64(tempos.count))], keyRoot: Int(random.next() % 12), minor: random.next() % 2 == 0,
                    task: tasks[day % tasks.count])
    }
}

/// I66 · What you made, counted on this device.
public enum CreativeStats {
    public struct Summary: Equatable, Sendable {
        public let projects: Int
        public let minutesOfMusic: Double
        public let favouriteKey: String?
        public let averageTempo: Int?
        public let editedThisWeek: Int
    }
    public static func summarize(_ projects: [ProjectSummary], now: Date = Date()) -> Summary {
        let minutes = projects.reduce(0.0) { $0 + Double($1.bars) * 4 * 60 / max(1, $1.bpm) / 60 }
        let keys = Dictionary(grouping: projects, by: \.keyName).mapValues(\.count)
        let favourite = keys.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        let week = projects.filter { now.timeIntervalSince($0.modified) < 7 * 86_400 }.count
        let tempo = projects.isEmpty ? nil : Int((projects.reduce(0) { $0 + $1.bpm } / Double(projects.count)).rounded())
        return Summary(projects: projects.count, minutesOfMusic: (minutes * 10).rounded() / 10, favouriteKey: favourite, averageTempo: tempo, editedThisWeek: week)
    }
}

/// I59 · Song names from the mood of the key and tempo (offline word pairs).
public enum SongNames {
    private static let enAdjectives = ["Midnight", "Velvet", "Paper", "Neon", "Quiet", "Golden", "Broken", "Slow", "Electric", "Silver", "Hidden", "Last"]
    private static let enNouns = ["Rooms", "Tide", "Signal", "Bloom", "Static", "Window", "Summer", "Engine", "Letters", "Harbor", "Light", "Echo"]
    private static let ruAdjectives = ["Тихий", "Ночной", "Бумажный", "Неоновый", "Золотой", "Медленный", "Последний", "Летний", "Серебряный", "Далёкий", "Тёплый", "Пустой"]
    private static let ruNouns = ["город", "сигнал", "прибой", "дом", "свет", "вокзал", "двор", "сон", "ветер", "берег", "огонь", "экран"]

    public static func suggestions(keyRoot: Int, minor: Bool, bpm: Double, seed: UInt64, russian: Bool, count: Int = 5) -> [String] {
        var random = SeededRandom(seed: seed &+ UInt64(keyRoot * 31) &+ UInt64(bpm) &+ (minor ? 7 : 0))
        let adjectives = russian ? ruAdjectives : enAdjectives, nouns = russian ? ruNouns : enNouns
        var result: [String] = []
        var attempts = 0
        while result.count < count && attempts < 100 {
            attempts += 1
            let name = adjectives[Int(random.next() % UInt64(adjectives.count))] + " " + nouns[Int(random.next() % UInt64(nouns.count))]
            if !result.contains(name) { result.append(name) }
        }
        return result
    }
}

/// I41 · Ear training on your own song: which chord is this?
public enum EarTraining {
    public struct Question: Equatable, Sendable {
        public let chord: Chord
        public let tick: Int
        public let choices: [Chord]
    }
    /// Questions from the song's chords; each offers the right chord and three others from the same key.
    public static func questions(_ project: Project, count: Int = 8, seed: UInt64 = 1) -> [Question] {
        let spans = Arrangement.harmony(project, section: Section(name: "Song", start: 0, length: max(barTicks, project.length)))
        guard !spans.isEmpty else { return [] }
        var random = SeededRandom(seed: seed)
        let diatonic = (project.minor ? [(0, Quality.minor), (3, .major), (5, .minor), (7, .minor), (8, .major), (10, .major)]
                                      : [(0, Quality.major), (2, .minor), (4, .minor), (5, .major), (7, .major), (9, .minor)])
            .map { Chord(root: ($0.0 + project.keyRoot) % 12, quality: $0.1) }
        return (0..<min(count, max(1, spans.count * 2))).map { _ in
            let span = spans[Int(random.next() % UInt64(spans.count))]
            var choices = [span.chord]
            for candidate in diatonic.shuffled(using: &random) where choices.count < 4 && !choices.contains(where: { $0.symbol == candidate.symbol }) { choices.append(candidate) }
            return Question(chord: span.chord, tick: span.tick, choices: choices.shuffled(using: &random))
        }
    }
}

/// I58 · Balance by role: a starting mix where the beat leads, the bass sits under it and
/// harmony stays behind the melody. A starting point, not a master.
public enum RoleBalance {
    public static let gains: [TrackRole: Double] = [.drums: -6, .bass: -8, .melody: -7, .harmony: -11]
    public static func apply(to project: inout Project) {
        for index in project.tracks.indices { project.tracks[index].gain = gains[project.tracks[index].role] ?? project.tracks[index].gain }
        project.master = -3
    }
}

/// I60 · What the song sounds like, from tempo, swing and the drum pattern — with the
/// starter groove closest to it.
public enum StyleGuess {
    public struct Guess: Equatable, Sendable { public let grooveID: String; public let reason: String }
    public static func guess(_ project: Project) -> Guess {
        let drums = project.patterns.flatMap(\.drums)
        let bars = max(1, project.length / barTicks)
        let hatsPerBar = Double(drums.filter { $0.pad == 2 }.count) / Double(bars)
        let kicksOnBeats = drums.filter { $0.pad == 0 && $0.tick % ppq == 0 }.count, kicks = max(1, drums.filter { $0.pad == 0 }.count)
        let swung = drums.contains { $0.tick % (barTicks / 16) != 0 }
        let bpm = project.bpm
        if bpm >= 130 && hatsPerBar >= 12 { return Guess(grooveID: "trap", reason: "Fast tempo with rolling hi-hats.") }
        let kicksPerBar = Double(drums.filter { $0.pad == 0 }.count) / Double(bars)
        if (118...130).contains(bpm) && kicksPerBar >= 3.5 && Double(kicksOnBeats) / Double(kicks) > 0.8 { return Guess(grooveID: "house", reason: "Four on the floor around 124 BPM.") }
        if bpm < 88 && swung { return Guess(grooveID: "lofi", reason: "Slow and swung.") }
        if (84...98).contains(bpm) { return Guess(grooveID: "boombap", reason: "Around 90 BPM with a backbeat.") }
        if (100...112).contains(bpm) && hatsPerBar >= 12 { return Guess(grooveID: "funk", reason: "Busy sixteenth hats around 104 BPM.") }
        return Guess(grooveID: "rock", reason: "Straight eighths and a backbeat.")
    }
}
