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
