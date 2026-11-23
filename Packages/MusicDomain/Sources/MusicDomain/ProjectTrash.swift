import Foundation

/// U8 · Something deleted from a song (a track, a drum take, a clip) kept inside the
/// project for 30 days, so it can come back after a relaunch, when Undo is gone.
public struct DeletedItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case track, take, clip }
    public var id: UUID = UUID()
    public var kind: Kind
    public var deletedAt: Date
    /// Display name at the time of deletion ("Melody 2", "Drums", take number).
    public var name: String
    /// .track: the whole track; .clip: nil (see `clip`).
    public var track: Track?
    /// Patterns the item plays, so it sounds the same when it comes back.
    public var patterns: [Pattern]?
    /// .track: original position; .take/.clip: the owning track.
    public var trackIndex: Int?
    public var trackID: UUID?
    /// .take: the pattern the take was recorded over, the take and its hits.
    public var patternID: UUID?
    public var take: DrumTake?
    public var hits: [DrumEvent]?
    /// .clip: the clip itself.
    public var clip: Clip?
}

public enum ProjectTrashError: Error, LocalizedError, Equatable {
    case missing, noRoom, trackLimit
    public var errorDescription: String? {
        let key = switch self {
        case .missing: "The place this came from no longer exists."
        case .noRoom: "Something else now plays in that spot. Clear it first, then restore."
        case .trackLimit: "This song already has 8 tracks. Delete one to restore this track."
        }
        return NSLocalizedString(key, comment: "Recently deleted")
    }
}

public enum ProjectTrash {
    public static let retentionDays = 30
    public static let itemLimit = 200
    public static let byteLimit = 2_000_000

    /// Items still in the trash (not expired), newest first.
    public static func items(in project: Project, now: Date = Date()) -> [DeletedItem] {
        (project.recentlyDeleted ?? []).filter { now.timeIntervalSince($0.deletedAt) < Double(retentionDays) * 86_400 }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    public static func daysLeft(_ item: DeletedItem, now: Date = Date()) -> Int {
        max(0, retentionDays - Int(now.timeIntervalSince(item.deletedAt) / 86_400))
    }

    // MARK: Deleting into the trash (each is part of one edit)

    public static func deleteTrack(_ id: UUID, in project: inout Project, now: Date = Date()) throws {
        guard let index = project.tracks.firstIndex(where: { $0.id == id }) else { throw MusicError.invalidProject }
        let track = project.tracks[index]
        let used = Set(track.clips.flatMap { [$0.patternID] + ($0.variants ?? []) })
        let patterns = project.patterns.filter { used.contains($0.id) }
        try project.deleteTrack(id)
        push(DeletedItem(kind: .track, deletedAt: now, name: track.displayName, track: track, patterns: patterns, trackIndex: index, trackID: id), into: &project)
    }

    public static func deleteTake(_ take: UUID, pattern patternID: UUID, in project: inout Project, now: Date = Date()) throws {
        guard let index = project.patterns.firstIndex(where: { $0.id == patternID }),
              let record = project.patterns[index].drumTakes?.first(where: { $0.id == take }) else { throw MusicError.invalidProject }
        let hits = project.patterns[index].drums.filter { $0.take == take }
        let owner = project.tracks.first { $0.clips.contains { $0.patternID == patternID } }
        DrumTakes.delete(&project.patterns[index], take: take)
        push(DeletedItem(kind: .take, deletedAt: now, name: String(record.number), trackID: owner?.id, patternID: patternID, take: record, hits: hits), into: &project)
    }

    public static func deleteClip(_ clipID: UUID, track trackID: UUID, in project: inout Project, now: Date = Date()) throws {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              let clip = project.tracks[trackIndex].clips.first(where: { $0.id == clipID }) else { throw MusicError.invalidProject }
        let used = Set([clip.patternID] + (clip.variants ?? []))
        let patterns = project.patterns.filter { used.contains($0.id) }
        let payload = ArrangementDragPayload(project: project, trackID: trackID, clipID: clipID)
        try ClipEditing.delete(payload, in: &project)
        push(DeletedItem(kind: .clip, deletedAt: now, name: project.tracks[trackIndex].displayName, patterns: patterns, trackID: trackID, clip: clip), into: &project)
    }

    /// Adds an item, then drops the oldest ones beyond the item and size limits.
    static func push(_ item: DeletedItem, into project: inout Project) {
        // Expired items leave with the next deletion; nothing is purged silently on open.
        var list = (project.recentlyDeleted ?? []).filter { item.deletedAt.timeIntervalSince($0.deletedAt) < Double(retentionDays) * 86_400 } + [item]
        list.sort { $0.deletedAt < $1.deletedAt }
        while list.count > itemLimit { list.removeFirst() }
        let encoder = JSONEncoder()
        while list.count > 1, ((try? encoder.encode(list).count) ?? 0) > byteLimit { list.removeFirst() }
        project.recentlyDeleted = list.isEmpty ? nil : list
    }

    // MARK: Restoring

    public static func restore(_ id: UUID, in project: inout Project) throws {
        guard let item = project.recentlyDeleted?.first(where: { $0.id == id }) else { throw ProjectTrashError.missing }
        var candidate = project
        candidate.recentlyDeleted?.removeAll { $0.id == id }
        if candidate.recentlyDeleted?.isEmpty == true { candidate.recentlyDeleted = nil }
        switch item.kind {
        case .track: try restoreTrack(item, in: &candidate)
        case .take: try restoreTake(item, in: &candidate)
        case .clip: try restoreClip(item, in: &candidate)
        }
        try candidate.validate()
        project = candidate
    }

    private static func addMissingPatterns(_ patterns: [Pattern]?, to project: inout Project) {
        let present = Set(project.patterns.map(\.id))
        project.patterns += (patterns ?? []).filter { !present.contains($0.id) }
    }

    /// Keeps only the parts of clips that still fit inside the song.
    private static func fitting(_ clips: [Clip], length: Int) -> [Clip] {
        clips.compactMap { clip in
            guard clip.start < length else { return nil }
            var fitted = clip; fitted.length = min(clip.length, length - clip.start); return fitted
        }
    }

    private static func restoreTrack(_ item: DeletedItem, in project: inout Project) throws {
        guard var track = item.track else { throw ProjectTrashError.missing }
        guard project.tracks.count < 8 else { throw ProjectTrashError.trackLimit }
        guard !project.tracks.contains(where: { $0.id == track.id }) else { throw ProjectTrashError.noRoom }
        addMissingPatterns(item.patterns, to: &project)
        if track.role != .bass { track.clips = fitting(track.clips, length: project.length) }
        project.tracks.insert(track, at: min(max(2, item.trackIndex ?? project.tracks.count), project.tracks.count))
    }

    private static func restoreTake(_ item: DeletedItem, in project: inout Project) throws {
        guard let patternID = item.patternID, let take = item.take,
              let index = project.patterns.firstIndex(where: { $0.id == patternID }) else { throw ProjectTrashError.missing }
        var pattern = project.patterns[index]
        guard !(pattern.drumTakes ?? []).contains(where: { $0.id == take.id }) else { throw ProjectTrashError.noRoom }
        let present = Set(pattern.drums.map(\.id))
        pattern.drums += (item.hits ?? []).filter { $0.tick >= 0 && $0.tick < pattern.length && !present.contains($0.id) }
        var restored = take
        if (pattern.drumTakes ?? []).contains(where: { $0.number == take.number }) {
            restored.number = ((pattern.drumTakes ?? []).map(\.number).max() ?? 0) + 1
        }
        pattern.drumTakes = (pattern.drumTakes ?? []) + [restored]
        project.patterns[index] = pattern
    }

    private static func restoreClip(_ item: DeletedItem, in project: inout Project) throws {
        guard let clip = item.clip, let trackID = item.trackID,
              let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { throw ProjectTrashError.missing }
        guard let fitted = fitting([clip], length: project.length).first else { throw ProjectTrashError.missing }
        let range = fitted.start..<fitted.start + fitted.length
        guard !project.tracks[index].clips.contains(where: { ($0.start..<$0.start + $0.length).overlaps(range) || $0.id == clip.id }) else {
            throw ProjectTrashError.noRoom
        }
        addMissingPatterns(item.patterns, to: &project)
        project.tracks[index].clips.append(fitted)
        project.tracks[index].clips.sort { $0.start < $1.start }
    }

    /// Removes items older than the retention period; returns how many went.
    @discardableResult public static func purge(_ project: inout Project, now: Date = Date()) -> Int {
        guard let list = project.recentlyDeleted else { return 0 }
        let kept = list.filter { now.timeIntervalSince($0.deletedAt) < Double(retentionDays) * 86_400 }
        project.recentlyDeleted = kept.isEmpty ? nil : kept
        return list.count - kept.count
    }
}
