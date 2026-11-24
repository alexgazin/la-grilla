import Foundation

/// U35 · A useful default name: key, tempo and the day ("A minor · 92 · Tuesday").
public enum ProjectNaming {
    public static func suggest(keyRoot: Int, minor: Bool, bpm: Double, date: Date = Date(), locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let russian = locale.language.languageCode?.identifier == "ru"
        let russianRoots = ["До", "До♯", "Ре", "Ми♭", "Ми", "Фа", "Фа♯", "Соль", "Ля♭", "Ля", "Си♭", "Си"]
        let root = russian ? russianRoots[(keyRoot % 12 + 12) % 12] : Chord.roots[(keyRoot % 12 + 12) % 12]
        let mode = russian ? (minor ? "минор" : "мажор") : (minor ? "minor" : "major")
        return "\(root) \(mode) · \(Int(bpm.rounded())) · \(formatter.string(from: date))"
    }
}

/// U34 · Ordering and filtering the project list.
public enum ProjectOrdering: String, CaseIterable, Sendable {
    case modified, name, tempo, key
    public var title: String {
        switch self { case .modified: "Last edited"; case .name: "Name"; case .tempo: "Tempo"; case .key: "Key" }
    }

    /// Pinned projects first, then by the chosen order; ties fall back to the newest.
    public func sorted(_ summaries: [ProjectSummary], pinned: Set<UUID> = []) -> [ProjectSummary] {
        summaries.sorted { a, b in
            let pa = pinned.contains(a.id), pb = pinned.contains(b.id)
            if pa != pb { return pa }
            switch self {
            case .modified: return a.modified > b.modified
            case .name:
                let order = a.name.localizedStandardCompare(b.name)
                return order == .orderedSame ? a.modified > b.modified : order == .orderedAscending
            case .tempo: return a.bpm == b.bpm ? a.modified > b.modified : a.bpm < b.bpm
            case .key:
                let ka = a.keyRoot * 2 + (a.minor ? 1 : 0), kb = b.keyRoot * 2 + (b.minor ? 1 : 0)
                return ka == kb ? a.modified > b.modified : ka < kb
            }
        }
    }

    /// Text search over name, key and tempo ("92", "minor", "ля").
    public static func filter(_ summaries: [ProjectSummary], query: String) -> [ProjectSummary] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return summaries }
        return summaries.filter { summary in
            let haystack = "\(summary.name) \(summary.keyName) \(Int(summary.bpm))".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

/// U32 · Music copied between projects: chords, a beat or a melody, with where it came
/// from so pasting can follow the target's key.
public struct MusicClipboard: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case chords, beat, melody }
    public static let pasteboardType = "com.alexgazin.lagrilla.music"
    public var kind: Kind
    public var length: Int
    public var keyRoot: Int
    public var minor: Bool
    public var bpm: Double
    public var chords: [ChordEvent]
    public var drums: [DrumEvent]
    public var notes: [NoteEvent]

    /// Copies the music of one section (from the pattern under its first bar).
    public static func copy(_ kind: Kind, section: Section, from project: Project) -> MusicClipboard? {
        let role: TrackRole = kind == .chords ? .harmony : kind == .beat ? .drums : .melody
        guard let track = project.tracks.first(where: { $0.role == role && $0.clips.contains { $0.start <= section.start && section.start < $0.start + $0.length } }),
              let clip = track.clips.first(where: { $0.start <= section.start && section.start < $0.start + $0.length }),
              let pattern = project.patterns.first(where: { $0.id == clip.patternID }) else { return nil }
        let value = MusicClipboard(kind: kind, length: pattern.length, keyRoot: project.keyRoot, minor: project.minor, bpm: project.bpm,
                                   chords: kind == .chords ? pattern.chords : [], drums: kind == .beat ? pattern.drums.map { var d = $0; d.take = nil; return d } : [],
                                   notes: kind == .melody ? (pattern.notes ?? []) : [])
        return value.isEmpty ? nil : value
    }

    public var isEmpty: Bool { chords.isEmpty && drums.isEmpty && notes.isEmpty }

    /// Pastes into the selected section's pattern of the matching track, replacing that
    /// part; chords and notes move to the target key (by the shortest step) unless `keepKey`.
    public func paste(into section: Section, project: inout Project, keepKey: Bool = false) throws {
        let role: TrackRole = kind == .chords ? .harmony : kind == .beat ? .drums : .melody
        guard let track = project.tracks.first(where: { $0.role == role && $0.clips.contains { $0.start <= section.start && section.start < $0.start + $0.length } }),
              let clip = track.clips.first(where: { $0.start <= section.start && section.start < $0.start + $0.length }),
              let index = project.patterns.firstIndex(where: { $0.id == clip.patternID }) else { throw MusicError.invalidProject }
        var shift = keepKey ? 0 : ((project.keyRoot - keyRoot) % 12 + 12) % 12
        if shift > 6 { shift -= 12 }
        let length = project.patterns[index].length
        var candidate = project
        func repeated<T>(_ events: [T], tick: (T) -> Int, move: (T, Int) -> T) -> [T] {
            stride(from: 0, to: length, by: max(1, self.length)).flatMap { offset in
                events.filter { offset + tick($0) < length }.map { move($0, offset) }
            }
        }
        switch kind {
        case .chords:
            candidate.patterns[index].chords = repeated(chords, tick: \.tick) { event, offset in
                var e = event; e.id = UUID(); e.tick += offset; e.duration = min(e.duration, length - e.tick)
                if shift != 0 { e.chord = Chord(root: (e.chord.root + shift + 12) % 12, quality: e.chord.quality, inversion: e.chord.inversion, slashBass: e.chord.slashBass.map { ($0 + shift + 12) % 12 }) }
                return e
            }
        case .beat:
            candidate.patterns[index].drums = repeated(drums, tick: \.tick) { event, offset in var e = event; e.id = UUID(); e.tick += offset; return e }
            candidate.patterns[index].drumTakes = nil
        case .melody:
            candidate.patterns[index].notes = repeated(notes, tick: \.tick) { event, offset in
                var e = event; e.id = UUID(); e.tick += offset; e.duration = min(e.duration, length - e.tick)
                e.pitch = min(127, max(0, e.pitch + shift)); return e
            }
        }
        try candidate.validate()
        project = candidate
    }
}

/// U27 · Swap two pads: their hits, sounds, edits and mute state trade places.
public enum PadEditing {
    public static func swap(_ a: Int, _ b: Int, track trackID: UUID, in project: inout Project) throws {
        guard a != b, (0..<16).contains(a), (0..<16).contains(b),
              let index = project.tracks.firstIndex(where: { $0.id == trackID && $0.role == .drums }) else { throw MusicError.invalidProject }
        var candidate = project
        let patterns = Set(candidate.tracks[index].clips.flatMap { [$0.patternID] + ($0.variants ?? []) })
        for p in candidate.patterns.indices where patterns.contains(candidate.patterns[p].id) {
            candidate.patterns[p].drums = candidate.patterns[p].drums.map { hit in
                var moved = hit; moved.pad = hit.pad == a ? b : hit.pad == b ? a : hit.pad; return moved
            }
        }
        var track = candidate.tracks[index]
        if var samples = track.padSamples { let first = samples[a]; samples[a] = samples[b]; samples[b] = first; track.padSamples = samples.isEmpty ? nil : samples }
        if var edits = track.padEdits { let first = edits[a]; edits[a] = edits[b]; edits[b] = first; track.padEdits = edits.isEmpty ? nil : edits }
        if let muted = track.mutedPads { track.mutedPads = muted.map { $0 == a ? b : $0 == b ? a : $0 }.sorted() }
        candidate.tracks[index] = track
        try candidate.validate()
        project = candidate
    }
}

/// U62 · How much room the songs take on this device.
public enum StorageUsage {
    /// Bytes under a folder (files only), or 0 when it does not exist.
    public static func bytes(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

/// U70 · What's new in this build, shown once after an update.
public enum WhatsNew {
    public struct Item: Equatable, Sendable { public let symbol: String; public let title: String; public let detail: String; public let command: CommandID? }
    public static let items: [Item] = [
        .init(symbol: "hand.point.up.left", title: "A tour of the studio", detail: "Five steps on a demo song: pads, a chord, a hummed melody, the mixer and export. Settings → Show me around.", command: .settings),
        .init(symbol: "checkmark.circle", title: "Select several clips", detail: "In Grid, Select: duplicate, move, colour, mute or delete them with one Undo.", command: .grid),
        .init(symbol: "waveform.badge.mic", title: "An instrument from any sound", detail: "Record or import one note and play it on every key; voice treatment for recorded sounds.", command: nil),
        .init(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Automation and spaces", detail: "Write level and pan moves while playing; room, hall, plate and spring reverb.", command: .mixer),
        .init(symbol: "hand.tap", title: "Hold to hear", detail: "Hold a template, beat, groove or palette to hear four bars before choosing.", command: .newProject),
        .init(symbol: "slider.horizontal.below.square.filled.and.square", title: "Simple or full, compact or large", detail: "Show only the essentials, choose the density, or reach everything with one hand.", command: .settings),
    ]
    /// Shown when the build changed since it was last shown (never on a fresh install's first launch).
    public static func shouldShow(lastShownBuild: String?, currentBuild: String) -> Bool {
        guard let last = lastShownBuild else { return false }
        return last != currentBuild
    }
}

/// I47 · A note for a co-author, optionally pinned to a section; travels in the package
/// and merges by id with a co-author's copy.
public struct ProjectNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var author: String
    public var text: String
    public var sectionID: UUID?
    public var created: Date
    public var resolved: Bool?
    public init(author: String, text: String, sectionID: UUID? = nil, created: Date = Date()) {
        self.author = author; self.text = text; self.sectionID = sectionID; self.created = created
    }
}

/// I48 · Sharing licences offered when a song leaves the device.
public enum SongLicense: String, CaseIterable, Sendable {
    case allRights = "all-rights", attribution = "cc-by", nonCommercial = "cc-by-nc"
    public var title: String {
        switch self { case .allRights: "Listen only (all rights reserved)"; case .attribution: "Remix with credit (CC BY)"; case .nonCommercial: "Remix with credit, not for sale (CC BY-NC)" }
    }
}

/// I70 · Starter grooves by genre, written as step strings (16 steps, x = hit, o = soft),
/// ready to paste into any section with MusicClipboard. Our own patterns, free to use.
public enum StarterGrooves {
    public struct Groove: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let bpm: Int
        /// pad → 16-step string.
        public let steps: [Int: String]
        public var clipboard: MusicClipboard {
            var drums: [DrumEvent] = []
            for (pad, line) in steps {
                for (index, mark) in line.enumerated() where mark == "x" || mark == "o" {
                    drums.append(DrumEvent(tick: index * (barTicks / 16), pad: pad, velocity: mark == "x" ? 108 : 58))
                }
            }
            return MusicClipboard(kind: .beat, length: barTicks, keyRoot: 0, minor: false, bpm: Double(bpm), chords: [], drums: drums.sorted { $0.tick == $1.tick ? $0.pad < $1.pad : $0.tick < $1.tick }, notes: [])
        }
    }
    public static let all: [Groove] = [
        .init(id: "boombap", title: "Boom bap", bpm: 90, steps: [0: "x.....x...x.....", 1: "....x.......x...", 2: "x.x.x.x.x.x.x.x.", 3: "...............o"]),
        .init(id: "trap", title: "Trap", bpm: 140, steps: [0: "x......x..x.....", 1: "........x.......", 2: "xxxxxxxxxxxxxxxx", 4: "........x......."]),
        .init(id: "house", title: "House", bpm: 124, steps: [0: "x...x...x...x...", 4: "....x.......x...", 2: "..x...x...x...x.", 3: "..o...o...o...o."]),
        .init(id: "lofi", title: "Lo-fi", bpm: 80, steps: [0: "x......x.x......", 1: "....x.......x..o", 2: "x.o.x.o.x.o.x.o.", 5: "..............o."]),
        .init(id: "rock", title: "Rock", bpm: 116, steps: [0: "x.......x.x.....", 1: "....x.......x...", 2: "x.x.x.x.x.x.x.x.", 9: "x..............."]),
        .init(id: "reggaeton", title: "Reggaeton", bpm: 96, steps: [0: "x...x...x...x...", 1: "...x..x....x..x.", 2: "x.x.x.x.x.x.x.x."]),
        .init(id: "funk", title: "Funk", bpm: 104, steps: [0: "x.....x.x.....x.", 1: "....x..o.o..x...", 2: "xxxxxxxxxxxxxxxx", 3: "......x........."]),
        .init(id: "afrobeat", title: "Afrobeats", bpm: 108, steps: [0: "x......x..x.....", 5: "...x..x....x..x.", 2: "x.x.x.x.x.x.x.x.", 11: "..x...x...x...x."]),
    ]
}
