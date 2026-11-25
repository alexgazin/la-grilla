import Foundation

extension Arpeggiator.Pattern: Codable, Identifiable {
    public var id: String { rawValue }
    /// English name; the app localizes it.
    public var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .upDown: "Up and down"
        case .asPlayed: "As played"
        case .random: "Random"
        }
    }
    /// The live keyboard's order code in the audio kernel.
    public var kernelMode: Int {
        switch self {
        case .up: 0
        case .down: 1
        case .upDown: 2
        case .asPlayed: 3
        case .random: 5
        }
    }
}

/// 55 · One arpeggiator for the live keyboard and for "Arpeggiate to MIDI": the order of the
/// held notes, the note rate on the song's grid (with triplets), 1–3 octaves and how long each
/// note sounds within its step.
public struct ArpeggioSettings: Codable, Equatable, Hashable, Sendable {
    public enum Rate: Int, CaseIterable, Codable, Sendable, Identifiable {
        case quarter = 960, eighth = 480, eighthTriplet = 320, sixteenth = 240, sixteenthTriplet = 160, thirtySecond = 120
        public var id: Int { rawValue }
        public var label: String {
            switch self {
            case .quarter: "1/4"
            case .eighth: "1/8"
            case .eighthTriplet: "1/8T"
            case .sixteenth: "1/16"
            case .sixteenthTriplet: "1/16T"
            case .thirtySecond: "1/32"
            }
        }
        public var isTriplet: Bool { self == .eighthTriplet || self == .sixteenthTriplet }
    }

    public var direction: Arpeggiator.Pattern
    public var rate: Rate
    /// 1…3 octaves above the held notes.
    public var octaves: Int
    /// 0.1…1: the share of the step each note sounds (1 = legato).
    public var gate: Double

    public static let gates: [Double] = [0.25, 0.5, 0.8, 1.0]

    public init(direction: Arpeggiator.Pattern = .up, rate: Rate = .sixteenth, octaves: Int = 1, gate: Double = 0.8) {
        self.direction = direction; self.rate = rate; self.octaves = octaves; self.gate = gate
    }

    public func validate() throws {
        guard (1...3).contains(octaves), gate.isFinite, (0.1...1).contains(gate) else { throw MusicError.invalidProject }
    }

    /// "Up · 1/16 · 2 oct · 80%".
    public var summary: String {
        "\(direction.title) · \(rate.label) · \(octaves) oct · \(Int((gate * 100).rounded()))%"
    }
}

public enum ArpeggioRender {
    /// Notes that sound together, held until the next group starts or the longest one ends.
    public struct Block: Equatable, Sendable {
        public var start: Int
        public var end: Int
        /// In the order they were written (by start, then pitch).
        public var pitches: [Int]
        public init(start: Int, end: Int, pitches: [Int]) { self.start = start; self.end = end; self.pitches = pitches }
    }

    /// Groups notes whose starts are within `window` ticks of the group's first note (a chord
    /// played by hand is never perfectly together).
    public static func blocks(_ notes: [(tick: Int, duration: Int, pitch: Int)], window: Int = ppq / 16) -> [Block] {
        let sorted = notes.filter { $0.duration > 0 && (0...127).contains($0.pitch) }.sorted { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
        var groups: [[(tick: Int, duration: Int, pitch: Int)]] = []
        for note in sorted {
            if let first = groups.last?.first, note.tick - first.tick <= window { groups[groups.count - 1].append(note) }
            else { groups.append([note]) }
        }
        var result: [Block] = []
        for (index, group) in groups.enumerated() {
            let start = group[0].tick
            var end = group.map { $0.tick + $0.duration }.max() ?? start
            if index + 1 < groups.count { end = min(end, groups[index + 1][0].tick) }
            var pitches: [Int] = []
            for note in group where !pitches.contains(note.pitch) { pitches.append(note.pitch) }
            if end > start, !pitches.isEmpty { result.append(Block(start: start, end: end, pitches: Array(pitches.prefix(16)))) }
        }
        return result
    }

    /// The arpeggio over every block, restarting the order on each new group of held notes.
    public static func notes(_ blocks: [Block], settings: ArpeggioSettings, velocity: Int = 90, seed: UInt64 = 1) -> [NoteEvent] {
        var result: [NoteEvent] = []
        for (index, block) in blocks.enumerated() {
            result += Arpeggiator.notes(block.pitches, pattern: settings.direction, rate: settings.rate.rawValue, octaves: settings.octaves,
                                        start: block.start, duration: block.end - block.start, velocity: velocity,
                                        seed: seed &+ UInt64(index) &* 0x9E37_79B9, gate: settings.gate)
        }
        return result
    }
}

public enum ArpeggioToolError: Error, LocalizedError, Equatable {
    case nothingToArpeggiate, trackLimit, cannotReplaceChords
    public var errorDescription: String? {
        let key = switch self {
        case .nothingToArpeggiate: "There are no chords or notes to arpeggiate here."
        case .trackLimit: "The song already has eight tracks. Replace the notes on this track instead, or delete a track."
        case .cannotReplaceChords: "Chords stay chords: the arpeggio goes to a new track."
        }
        return NSLocalizedString(key, comment: "Arpeggiator")
    }
}

/// 55 · "Arpeggiate to MIDI": the chords or notes of one track, played through the arpeggiator
/// and written as ordinary notes the piano roll edits.
public enum ArpeggioTool {
    public enum Destination: String, Codable, Sendable, CaseIterable { case newTrack, replace }

    public struct Request: Equatable, Sendable {
        public var trackID: UUID
        /// Absolute ticks; nil = the whole song.
        public var range: Range<Int>?
        public var settings: ArpeggioSettings
        public var destination: Destination
        /// Harmony source only: silence its chords where the arpeggio now plays.
        public var removeChords: Bool
        public init(trackID: UUID, range: Range<Int>? = nil, settings: ArpeggioSettings, destination: Destination = .newTrack, removeChords: Bool = false) {
            self.trackID = trackID; self.range = range; self.settings = settings; self.destination = destination; self.removeChords = removeChords
        }
    }

    /// The bar-aligned span the request covers.
    public static func span(_ project: Project, _ request: Request) -> Range<Int> {
        let full = 0..<project.length
        guard let range = request.range else { return full }
        let lower = max(0, range.lowerBound / barTicks * barTicks)
        let upper = min(project.length, (range.upperBound + barTicks - 1) / barTicks * barTicks)
        return lower < upper ? lower..<upper : full
    }

    /// Held-note groups of the track over `span` (absolute ticks).
    public static func sourceBlocks(_ project: Project, track trackID: UUID, span: Range<Int>) -> [ArpeggioRender.Block] {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }), project.tracks[index].role != .drums else { return [] }
        let notes = Compiler.notes(project, range: span).filter { $0.track == index && $0.pad < 0 }
            .map { (tick: $0.tick, duration: min($0.duration, span.upperBound - $0.tick), pitch: $0.pitch) }
        return ArpeggioRender.blocks(notes)
    }

    /// The arpeggio notes (absolute ticks) the request writes.
    public static func render(_ project: Project, _ request: Request) -> [NoteEvent] {
        let span = span(project, request)
        let blocks = sourceBlocks(project, track: request.trackID, span: span)
        return ArpeggioRender.notes(blocks, settings: request.settings, seed: UInt64(truncatingIfNeeded: project.revision) &+ 0x55)
    }

    /// Writes the arpeggio; returns the track that holds it. One history edit for the caller.
    @discardableResult
    public static func apply(_ request: Request, to project: inout Project) throws -> UUID {
        try request.settings.validate()
        guard let sourceIndex = project.tracks.firstIndex(where: { $0.id == request.trackID }), project.tracks[sourceIndex].role != .drums else { throw MusicError.invalidProject }
        let span = span(project, request)
        let notes = render(project, request)
        guard !notes.isEmpty else { throw ArpeggioToolError.nothingToArpeggiate }
        let source = project.tracks[sourceIndex]
        switch request.destination {
        case .replace:
            guard source.role == .melody else { throw ArpeggioToolError.cannotReplaceChords }
            let range = SongEditor.isolationRange(project, track: sourceIndex, requested: span)
            let patternIndex = try SongEditor.isolate(&project, track: sourceIndex, range: range)
            var pattern = project.patterns[patternIndex]
            let base = range.lowerBound
            pattern.notes = (pattern.notes ?? []).filter { !span.contains($0.tick + base) }
            pattern.notes! += notes.map { note in var local = note; local.id = UUID(); local.tick -= base; local.duration = min(local.duration, pattern.length - local.tick); return local }
            guard pattern.notes!.count <= 4096 else { throw MusicError.tooDense }
            pattern.notes!.sort { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
            project.patterns[patternIndex] = pattern
            try project.validate()
            return source.id
        case .newTrack:
            guard project.tracks.count < 8 else { throw ArpeggioToolError.trackLimit }
            let name = String(format: NSLocalizedString("Arpeggio · %@", comment: "Arpeggio track"), source.displayName)
            try project.addMelody(name: String(name.prefix(60)))
            var track = project.tracks[project.tracks.count - 1]
            track.synth = SynthPatch.presets.first { $0.name == "Pluck" }?.patch
            track.gain = source.gain
            for clip in track.clips {
                guard let patternIndex = project.patterns.firstIndex(where: { $0.id == clip.patternID }) else { continue }
                let local = notes.filter { $0.tick >= clip.start && $0.tick < clip.start + clip.length }.map { note -> NoteEvent in
                    var moved = note; moved.id = UUID(); moved.tick -= clip.start; moved.duration = min(moved.duration, clip.length - moved.tick); return moved
                }
                guard local.count <= 4096 else { throw MusicError.tooDense }
                project.patterns[patternIndex].notes = local
            }
            project.tracks[project.tracks.count - 1] = track
            if request.removeChords, source.role == .harmony {
                let bars = (span.lowerBound / barTicks)..<(span.upperBound / barTicks)
                let removal = SongEditOperation(kind: .remove, target: SongEditTarget(trackID: source.id), bars: bars)
                try SongEditor.apply(removal, to: &project)
            }
            try project.validate()
            return track.id
        }
    }
}
