import Foundation

/// I68 · Recovery after a crash. Between saves the app keeps a small journal: the song as it is
/// now and the last edits' short names. If the app stops before the next save, the next launch
/// offers the newer state over the saved one ("Restore unsaved changes?") with what differs.
public struct EditJournal: Codable, Equatable, Sendable {
    public static let summaryLimit = 20
    public var projectID: UUID
    /// The revision that was on disk when the journal started.
    public var savedRevision: Int
    /// The song after the last journaled edit.
    public var latest: Project
    /// Short names of the edits since the save, oldest first.
    public var edits: [String]

    public init(saved project: Project, savedRevision: Int) {
        projectID = project.id; self.savedRevision = savedRevision; latest = project; edits = []
    }

    /// Records the song after an edit. A different song starts a new journal.
    public mutating func record(_ project: Project, edit name: String, savedRevision: Int) {
        if project.id != projectID { self = EditJournal(saved: project, savedRevision: savedRevision) }
        self.savedRevision = max(self.savedRevision, savedRevision)
        latest = project
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { edits = Array((edits + [String(label.prefix(80))]).suffix(Self.summaryLimit)) }
    }

    /// True when everything in the journal is already saved.
    public func isSaved(at revision: Int) -> Bool { latest.revision <= revision }

    /// The state to offer over `saved`: only for the same song, only when it is newer and valid.
    public func recovery(over saved: Project) -> Project? {
        guard latest.id == saved.id, latest.revision > saved.revision, (try? latest.validate()) != nil else { return nil }
        return latest
    }

    /// What the recovered state would change, in the history's words.
    public func changes(over saved: Project) -> [ProjectChange] {
        guard let recovered = recovery(over: saved) else { return [] }
        return ProjectChanges.describe(from: saved, to: recovered)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> EditJournal? { try? JSONDecoder().decode(EditJournal.self, from: data) }
}
