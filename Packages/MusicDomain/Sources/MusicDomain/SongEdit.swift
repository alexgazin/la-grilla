import Foundation

// Build 45: an edit of the open project described in plain RU/EN words is
// parsed into checkable musical operations (track or role, the exact section
// occurrence, a bar range and the result) before anything changes. The plan
// is applied as one transaction to the current project, including manual edits
// made after generation, and leaves every other part, the mix and sounds as they
// were.

public enum SongEditIntent: String, Equatable, Sendable {
    /// Describe a new song: handled by the offline arranger (TrackBrief).
    case create
    /// Change the open project: handled by SongEditParser/SongEditor.
    case edit
    case unknown
}

public struct SongEditTarget: Codable, Equatable, Hashable, Sendable {
    public var trackID: UUID
    /// Drum pads for a drum target; nil means the whole track.
    public var pads: [Int]?
    public init(trackID: UUID, pads: [Int]? = nil) { self.trackID = trackID; self.pads = pads }
}

public struct SongEditOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case remove, fill, denser, sparser, arpeggiate, delay, fadeIn, fadeOut
    }
    public var kind: Kind
    public var target: SongEditTarget
    /// Absolute bar indices, lower inclusive.
    public var bars: Range<Int>
    /// The section occurrence the instruction named, when it named one.
    public var sectionID: UUID?
    /// Apply to every second bar of `bars` (2nd, 4th, …): "через такт", "every other bar".
    public var everyOther: Bool
    /// Delay in ticks, fill length in ticks; unused otherwise.
    public var amount: Int
    /// Arpeggio source: also remove the chords it replaces ("instead of chords").
    public var replacesChords: Bool
    public init(kind: Kind, target: SongEditTarget, bars: Range<Int>, sectionID: UUID? = nil,
                everyOther: Bool = false, amount: Int = 0, replacesChords: Bool = false) {
        self.kind = kind; self.target = target; self.bars = bars; self.sectionID = sectionID
        self.everyOther = everyOther; self.amount = amount; self.replacesChords = replacesChords
    }
    /// Bars the operation actually changes.
    public var editedBars: [Int] { everyOther ? bars.filter { ($0 - bars.lowerBound) % 2 == 1 } : Array(bars) }
}

public struct SongEditProblem: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// No supported action or part was recognized in this fragment.
        case unsupported
        /// The same part is both kept and changed, or changed in opposite ways.
        case contradiction
        /// The named part, section or bar does not exist in this project.
        case missing
        /// A fill was requested before the first bar of the song.
        case noBarBefore
        /// The bass is derived from the chords; this change would alter or need it.
        case derivedBass
        /// Adding an arpeggio part would exceed eight tracks.
        case trackLimit
        /// The named part does not play in the chosen place, so nothing would change.
        case silent
    }
    public var fragment: String
    public var reason: Reason
    public init(fragment: String, reason: Reason) { self.fragment = fragment; self.reason = reason }
}

/// One meaningful target when the instruction fits several (for example two choruses).
public struct SongEditChoice: Equatable, Sendable {
    public var label: String
    public var sectionID: UUID
    public var operations: [SongEditOperation]
}

public struct SongEditPlan: Equatable, Sendable {
    public var projectID: UUID
    public var baseRevision: Int
    public var text: String
    /// Whole parts the user asked to keep.
    public var protectedTracks: [UUID]
    /// Drum pads the user asked to keep ("don't remove the hats").
    public var protectedPads: [SongEditTarget]
    public var operations: [SongEditOperation]
    public var problems: [SongEditProblem]
    /// Non-empty when the user must pick a target before the plan can apply.
    public var choices: [SongEditChoice]

    public var needsClarification: Bool { !choices.isEmpty }
    public var isApplicable: Bool { problems.isEmpty && choices.isEmpty && !operations.isEmpty }

    /// Resolve a clarification with one of the offered targets.
    public func choosing(_ index: Int) -> SongEditPlan {
        guard choices.indices.contains(index) else { return self }
        var plan = self
        plan.operations.append(contentsOf: choices[index].operations)
        plan.choices = []
        return plan
    }

    /// (track, section) cells touched by the plan, for highlighting the score.
    public func affectedCells(in project: Project) -> [SongEditCell] {
        var cells: [SongEditCell] = []
        for op in operations {
            let ticks = op.bars.lowerBound * barTicks..<op.bars.upperBound * barTicks
            let start = op.kind == .fill ? max(ticks.lowerBound, ticks.upperBound - op.amount) : ticks.lowerBound
            for section in project.sections where section.start < ticks.upperBound && section.start + section.length > start {
                let cell = SongEditCell(trackID: op.target.trackID, sectionID: section.id)
                if !cells.contains(cell) { cells.append(cell) }
            }
            if op.kind == .arpeggiate, op.replacesChords, let harmony = project.tracks.first(where: { $0.role == .harmony }) {
                for section in project.sections where section.start < ticks.upperBound && section.start + section.length > ticks.lowerBound {
                    let cell = SongEditCell(trackID: harmony.id, sectionID: section.id)
                    if !cells.contains(cell) { cells.append(cell) }
                }
            }
        }
        return cells
    }
}

public struct SongEditCell: Equatable, Hashable, Sendable {
    public var trackID: UUID
    public var sectionID: UUID
    public init(trackID: UUID, sectionID: UUID) { self.trackID = trackID; self.sectionID = sectionID }
}

public enum SongEditError: Error, LocalizedError, Equatable {
    case stale, notApplicable, protectedPartChanged, trackLimit
    public var errorDescription: String? {
        let key = switch self {
        case .stale: "The project changed. Generate a fresh proposal before applying."
        case .notApplicable: "Resolve the highlighted part of the request before applying."
        case .protectedPartChanged: "This change would alter a part you asked to keep."
        case .trackLimit: "A project can contain up to eight tracks."
        }
        return NSLocalizedString(key, comment: "Song edit")
    }
}

// MARK: - Description

extension SongEditOperation {
    /// Plain-language description shown before applying.
    public func summary(in project: Project) -> String {
        let track = project.tracks.first { $0.id == target.trackID }
        var part = track?.displayName ?? "?"
        if let pads = target.pads, !pads.isEmpty, pads.count < 16 {
            part = pads.map { NSLocalizedString(Compiler.padNames[$0], comment: "Drum pad") }.joined(separator: ", ")
        }
        let range = bars.count == 1
            ? String(format: NSLocalizedString("bar %d", comment: "Song edit range"), bars.lowerBound + 1)
            : String(format: NSLocalizedString("bars %d–%d", comment: "Song edit range"), bars.lowerBound + 1, bars.upperBound)
        let where_ = everyOther ? String(format: NSLocalizedString("every other bar of %@", comment: "Song edit range"), range) : range
        let key: String = switch kind {
        case .remove: "Remove %@ in %@"
        case .fill: "Add a %@ fill at the end of %@"
        case .denser: "Make %@ busier in %@"
        case .sparser: "Make %@ sparser in %@"
        case .arpeggiate: "Arpeggiate the chords on %@ in %@"
        case .delay: "Play %@ later in %@"
        case .fadeIn: "Fade %@ in over %@"
        case .fadeOut: "Fade %@ out over %@"
        }
        if kind == .fill {
            let beats = Double(amount) / Double(ppq)
            let length = String(format: NSLocalizedString("%g-beat", comment: "Fill length"), beats)
            return String(format: NSLocalizedString(key, comment: "Song edit operation"), length, where_)
        }
        return String(format: NSLocalizedString(key, comment: "Song edit operation"), part, where_)
    }
}
