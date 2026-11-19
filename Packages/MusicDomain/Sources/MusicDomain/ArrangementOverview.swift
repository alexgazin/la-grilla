import Foundation

/// A bounded visualization of the same MIDI events used for playback, independent of PCM, samples and audio routes.
public struct ArrangementOverview: Equatable, Sendable {
    public struct TrackSummary: Equatable, Sendable {
        /// Index in the actual project, also when empty instruments are hidden from the overview.
        public let index: Int
        public let name: String
        public let role: TrackRole
    }

    public struct Bin: Equatable, Sendable {
        public fileprivate(set) var onsets = 0
        public fileprivate(set) var minimumPitch: Int?
        public fileprivate(set) var maximumPitch: Int?
        /// Peak score velocity in this interval, including continuing notes.
        public fileprivate(set) var level = 0.0
    }

    public struct Lane: Equatable, Sendable {
        /// Number of note-on events, including voices of a chord, starting in this section.
        public fileprivate(set) var eventCount = 0
        public fileprivate(set) var bins: [Bin]
    }

    public struct SectionSummary: Equatable, Sendable {
        public let index: Int
        public let name: String
        public let startBar: Int
        public let bars: Int
        /// In the same order as `tracks`.
        public let lanes: [Lane]
    }

    public let sections: [SectionSummary]
    public let tracks: [TrackSummary]
    public let bars: Int

    public static func make(brief: TrackBrief) throws -> Self {
        try Task.checkCancellation()
        let score = try brief.makeProject(name: "Preview")
        return try summarize(score)
    }

    /// The generator already validates its project. Compile once across the whole score to keep
    /// note-ons on the correct side of section boundaries even when a tail crosses the join.
    static func summarize(_ score: Project) throws -> Self {
        try Task.checkCancellation()
        let notes = Compiler.notes(score)
        let used = Set(notes.map(\.track))
        let tracks = score.tracks.enumerated().compactMap { index, track -> TrackSummary? in
            guard used.contains(index) else { return nil }
            return TrackSummary(index: index, name: track.displayName, role: track.role)
        }
        let laneForTrack = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($0.element.index, $0.offset) })
        var sections: [SectionSummary] = []
        for (index, section) in score.sections.enumerated() {
            try Task.checkCancellation()
            let bars = section.length/barTicks
            let count = min(24, bars*16)
            let empty = Lane(bins: Array(repeating: Bin(), count: count))
            var lanes = Array(repeating: empty, count: tracks.count)
            let end = section.start+section.length
            for note in notes {
                if note.tick >= end { break }
                let begin = max(section.start, note.tick)
                let stop = min(end, note.tick+note.duration)
                guard begin < stop, let lane = laneForTrack[note.track] else { continue }
                let first = (begin-section.start)*count/section.length
                let last = (stop-1-section.start)*count/section.length
                if note.tick >= section.start {
                    lanes[lane].eventCount += 1
                    lanes[lane].bins[first].onsets += 1
                }
                let strength = Double(note.velocity)/127.0
                for bin in first...last {
                    var value = lanes[lane].bins[bin]
                    value.level = max(value.level, strength)
                    value.minimumPitch = min(value.minimumPitch ?? note.pitch, note.pitch)
                    value.maximumPitch = max(value.maximumPitch ?? note.pitch, note.pitch)
                    lanes[lane].bins[bin] = value
                }
            }
            sections.append(SectionSummary(index: index, name: section.name, startBar: section.start/barTicks,
                                           bars: bars, lanes: lanes))
        }
        return Self(sections: sections, tracks: tracks, bars: score.length/barTicks)
    }
}
