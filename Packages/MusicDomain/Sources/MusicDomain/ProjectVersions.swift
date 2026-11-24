import Foundation

/// U7 · A named snapshot of a whole song kept inside its project package
/// (`Versions/<id>.json` plus `Versions/index.json`). Versions are outside Undo,
/// survive relaunch, and share the package's audio and sample files.
public struct ProjectVersion: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let created: Date
    public let revision: Int
    public let bars: Int
    public let bpm: Double
    public let bytes: Int
}

public enum ProjectVersionError: Error, LocalizedError, Equatable {
    case limit, invalidName, missing
    public var errorDescription: String? {
        let key = switch self {
        case .limit: "This song already keeps 50 versions or 64 MB of them. Delete an old version to save a new one."
        case .invalidName: "Use a version name with 1–60 characters."
        case .missing: "This version is no longer available."
        }
        return NSLocalizedString(key, comment: "Song versions")
    }
}

public extension ProjectStore {
    static let versionLimit = 50
    static let versionByteLimit = 64_000_000

    private func versionsFolder(_ projectID: UUID) -> URL { package(projectID).appendingPathComponent("Versions", isDirectory: true) }
    private func versionIndex(_ projectID: UUID) -> URL { versionsFolder(projectID).appendingPathComponent("index.json") }
    private func versionFile(_ id: UUID, of projectID: UUID) -> URL { versionsFolder(projectID).appendingPathComponent(id.uuidString).appendingPathExtension("json") }

    /// Saved versions, newest first. A missing or unreadable index means none.
    func versions(of projectID: UUID) -> [ProjectVersion] {
        guard let data = try? Data(contentsOf: versionIndex(projectID)),
              let list = try? JSONDecoder().decode([ProjectVersion].self, from: data) else { return [] }
        return list.sorted { $0.created > $1.created }
    }

    static func validVersionName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(trimmed.count), !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    @discardableResult func saveVersion(_ project: Project, name: String, now: Date = Date()) throws -> ProjectVersion {
        guard let clean = Self.validVersionName(name) else { throw ProjectVersionError.invalidName }
        try project.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(project)
        var list = versions(of: project.id)
        guard list.count < Self.versionLimit, list.reduce(0, { $0 + $1.bytes }) + data.count <= Self.versionByteLimit else { throw ProjectVersionError.limit }
        let version = ProjectVersion(id: UUID(), name: clean, created: now, revision: project.revision,
                                     bars: project.length / barTicks, bpm: project.bpm, bytes: data.count)
        try FileManager.default.createDirectory(at: versionsFolder(project.id), withIntermediateDirectories: true)
        try data.write(to: versionFile(version.id, of: project.id), options: .atomic)
        list.append(version)
        do { try writeIndex(list, projectID: project.id) }
        catch { try? FileManager.default.removeItem(at: versionFile(version.id, of: project.id)); throw error }
        return version
    }

    /// The version's song, validated and migrated like any project document.
    func loadVersion(_ id: UUID, of projectID: UUID) throws -> Project {
        guard versions(of: projectID).contains(where: { $0.id == id }),
              let data = try? Data(contentsOf: versionFile(id, of: projectID)) else { throw ProjectVersionError.missing }
        let project = try ProjectDocument.decode(data)
        guard project.id == projectID else { throw MusicError.invalidProject }
        return project
    }

    func renameVersion(_ id: UUID, of projectID: UUID, to name: String) throws {
        guard let clean = Self.validVersionName(name) else { throw ProjectVersionError.invalidName }
        var list = versions(of: projectID)
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw ProjectVersionError.missing }
        list[index].name = clean
        try writeIndex(list, projectID: projectID)
    }

    func deleteVersion(_ id: UUID, of projectID: UUID) throws {
        var list = versions(of: projectID)
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw ProjectVersionError.missing }
        list.remove(at: index)
        try writeIndex(list, projectID: projectID)
        try? FileManager.default.removeItem(at: versionFile(id, of: projectID))
    }

    private func writeIndex(_ list: [ProjectVersion], projectID: UUID) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(list.sorted { $0.created < $1.created }).write(to: versionIndex(projectID), options: .atomic)
    }
}
