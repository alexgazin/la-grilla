import Foundation

/// I39 · A note pinned to a place in the song ("add vocals here", "louder from here").
public struct Marker: Codable, Equatable, Identifiable, Sendable {
    public static let limit = 128
    public var id: UUID
    public var tick: Int
    public var text: String
    public init(id: UUID = UUID(), tick: Int, text: String) { self.id = id; self.tick = tick; self.text = text }
}

public enum MarkerEditing {
    /// Adds a marker at the beat nearest `tick` (one Undo when used inside `Session.edit`).
    @discardableResult
    public static func add(_ text: String, at tick: Int, in project: inout Project) throws -> Marker {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !trimmed.isEmpty, project.length > 0 else { throw MusicError.invalidProject }
        guard (project.markers ?? []).count < Marker.limit else { throw MusicError.limit }
        let beat = min(project.length - 1, max(0, (tick + ppq / 2) / ppq * ppq))
        let marker = Marker(tick: beat, text: trimmed)
        var markers = project.markers ?? []
        markers.append(marker)
        project.markers = markers.sorted { $0.tick < $1.tick }
        try project.validate()
        return marker
    }

    public static func remove(_ id: UUID, in project: inout Project) {
        project.markers?.removeAll { $0.id == id }
        if project.markers?.isEmpty == true { project.markers = nil }
    }

    public static func rename(_ id: UUID, to text: String, in project: inout Project) throws {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !trimmed.isEmpty, let index = project.markers?.firstIndex(where: { $0.id == id }) else { throw MusicError.invalidProject }
        project.markers?[index].text = trimmed
    }

    /// Keeps each marker at the same place inside its section after sections were moved,
    /// resized, duplicated or deleted; markers of a deleted section or past a shortened
    /// end go away.
    public static func remap(from old: Project, to new: inout Project) {
        guard let markers = old.markers, !markers.isEmpty, old.sections != new.sections else { trim(&new); return }
        let ids = Set(markers.map(\.id))
        var kept = (new.markers ?? []).filter { !ids.contains($0.id) }
        for marker in markers where new.markers?.contains(where: { $0.id == marker.id }) ?? false {
            guard let section = old.sections.first(where: { $0.start <= marker.tick && marker.tick < $0.start + $0.length }),
                  let moved = new.sections.first(where: { $0.id == section.id }) else { continue }
            let offset = marker.tick - section.start
            guard offset < moved.length else { continue }
            var copy = new.markers?.first { $0.id == marker.id } ?? marker
            copy.tick = moved.start + offset
            kept.append(copy)
        }
        new.markers = kept.isEmpty ? nil : kept.sorted { $0.tick < $1.tick }
        trim(&new)
    }

    /// Markers that no longer fit after the song got shorter are dropped.
    public static func trim(_ project: inout Project) {
        let length = project.length
        project.markers?.removeAll { $0.tick >= length }
        if project.markers?.isEmpty == true { project.markers = nil }
    }

    /// Bar and beat label, 1-based ("5.3").
    public static func position(_ tick: Int) -> String { "\(tick / barTicks + 1).\(tick % barTicks / ppq + 1)" }
}

/// I43 · A teacher's assignment kept in the project: one bar of beat to play back.
public struct Assignment: Codable, Equatable, Sendable {
    public struct Lane: Codable, Equatable, Sendable { public var pad: Int; public var steps: [Int] }
    public var title: String
    public var lanes: [Lane]

    /// The first bar of `hits`, each hit moved to the nearest sixteenth.
    public static func from(_ hits: [DrumEvent], title: String) -> Assignment? {
        var lanes: [Int: Set<Int>] = [:]
        for hit in hits where hit.tick < barTicks && (0..<16).contains(hit.pad) {
            let step = min(15, (hit.tick + 120) / 240)
            lanes[hit.pad, default: []].insert(step)
        }
        guard !lanes.isEmpty else { return nil }
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return Assignment(title: trimmed.isEmpty ? "Assignment" : trimmed, lanes: lanes.keys.sorted().map { Lane(pad: $0, steps: lanes[$0]!.sorted()) })
    }

    public func validate() throws {
        guard !title.isEmpty, title.count <= 80, lanes.count <= 16, Set(lanes.map(\.pad)).count == lanes.count,
              lanes.allSatisfy({ (0..<16).contains($0.pad) && !$0.steps.isEmpty && $0.steps.allSatisfy { (0..<16).contains($0) } }) else { throw MusicError.invalidProject }
    }
}
