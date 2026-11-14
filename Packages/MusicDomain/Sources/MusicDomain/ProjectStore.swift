import Foundation
/// Serial actor: disk writes never run on the audio or main thread.
public actor ProjectStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    private func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("grilla") }
    public func save(_ project: Project) throws {
        try project.validate()
        let folder = package(project.id); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(project)
        _ = try JSONDecoder().decode(Project.self, from: data)
        let manifest = folder.appendingPathComponent("manifest.json")
        if let old = try? Data(contentsOf: manifest), let valid = try? JSONDecoder().decode(Project.self, from: old), (try? valid.validate()) != nil {
            try old.write(to: folder.appendingPathComponent("backup.json"), options: .atomic)
        }
        try data.write(to: manifest, options: .atomic)
    }
    public func load(_ id: UUID, backup: Bool = false) throws -> Project {
        let file = package(id).appendingPathComponent(backup ? "backup.json" : "manifest.json")
        let values = try file.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 8_000_000 else { throw MusicError.tooDense }
        let p = try JSONDecoder().decode(Project.self, from: Data(contentsOf: file)); try p.validate(); return p
    }
    public struct Entry: Sendable, Identifiable { public let id: UUID; public let project: Project?; public let error: String? }
    public func list() throws -> [Entry] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter {$0.pathExtension == "grilla"}.compactMap { url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            do { return Entry(id: id, project: try load(id), error: nil) } catch { return Entry(id: id, project: nil, error: error.localizedDescription) }
        }.sorted { ($0.project?.modified ?? .distantPast) > ($1.project?.modified ?? .distantPast) }
    }
    public func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: package(id)) }
}
