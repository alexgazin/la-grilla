import Foundation

public extension Project {
    /// Pattern IDs used by a clip, including clip variants (I34).
    var referencedPatternIDs: Set<UUID> {
        Set(tracks.flatMap { $0.clips.flatMap { [$0.patternID] + ($0.variants ?? []) } })
    }
    /// Drops patterns that no clip plays or keeps as a variant.
    mutating func removeUnusedPatterns() {
        let used = referencedPatternIDs
        patterns.removeAll { !used.contains($0.id) }
    }
}

/// I34 · A/B/C variants of one clip. A new variant starts as an exact copy of
/// the current part; switching only changes which pattern the clip plays.
/// Every operation is one undoable project edit.
public enum ClipVariants {
    public static let maximum = 4

    /// The clip's patterns (current and alternatives) in a stable order: the
    /// order in which they were created in the project.
    public static func options(_ clip: Clip, in project: Project) -> [UUID] {
        let ids = Set([clip.patternID] + (clip.variants ?? []))
        return project.patterns.map(\.id).filter(ids.contains)
    }

    public static func label(_ index: Int) -> String { String(UnicodeScalar(UInt8(65 + max(0, min(25, index))))) }

    private static func locate(_ project: Project, track: UUID, clip: UUID) throws -> (Int, Int) {
        guard let t = project.tracks.firstIndex(where: { $0.id == track }), let c = project.tracks[t].clips.firstIndex(where: { $0.id == clip }) else { throw ClipEditingError.missing }
        return (t, c)
    }

    /// Adds a copy of the current part and switches the clip to it.
    @discardableResult
    public static func add(track: UUID, clip: UUID, in project: inout Project) throws -> UUID {
        let (t, c) = try locate(project, track: track, clip: clip)
        let current = project.tracks[t].clips[c]
        guard (current.variants?.count ?? 0) + 1 < maximum, project.tracks[t].clips[c].sourceAssetID == nil,
              var copy = project.patterns.first(where: { $0.id == current.patternID }) else { throw MusicError.limit }
        copy.id = UUID()
        copy.chords = copy.chords.map { var e = $0; e.id = UUID(); return e }
        copy.drums = copy.drums.map { var e = $0; e.id = UUID(); return e }
        copy.notes = copy.notes.map { $0.map { var e = $0; e.id = UUID(); return e } }
        project.patterns.append(copy)
        project.tracks[t].clips[c].variants = (current.variants ?? []) + [current.patternID]
        project.tracks[t].clips[c].patternID = copy.id
        try project.validate()
        return copy.id
    }

    /// Switches the clip to one of its variants.
    public static func select(_ pattern: UUID, track: UUID, clip: UUID, in project: inout Project) throws {
        let (t, c) = try locate(project, track: track, clip: clip)
        var value = project.tracks[t].clips[c]
        guard pattern != value.patternID else { return }
        guard var alternates = value.variants, let index = alternates.firstIndex(of: pattern),
              let target = project.patterns.first(where: { $0.id == pattern }) else { throw ClipEditingError.missing }
        alternates[index] = value.patternID
        value.patternID = pattern
        value.variants = alternates
        if value.offset >= target.length { value.offset = 0 }
        project.tracks[t].clips[c] = value
        try project.validate()
    }

    /// Removes the variant the clip plays now and switches to the earliest remaining one.
    public static func removeCurrent(track: UUID, clip: UUID, in project: inout Project) throws {
        let (t, c) = try locate(project, track: track, clip: clip)
        var value = project.tracks[t].clips[c]
        guard let alternates = value.variants, !alternates.isEmpty else { throw ClipEditingError.missing }
        let next = options(value, in: project).first { $0 != value.patternID } ?? alternates[0]
        value.patternID = next
        let rest = alternates.filter { $0 != next }
        value.variants = rest.isEmpty ? nil : rest
        if let target = project.patterns.first(where: { $0.id == next }), value.offset >= target.length { value.offset = 0 }
        project.tracks[t].clips[c] = value
        project.removeUnusedPatterns()
        try project.validate()
    }
}
