import Foundation

/// A kit directory is published by a single same-volume rename after both
/// its catalog entry and self-contained audio archive have been written.
public actor PersonalKitStore {
    private struct Entry: Codable {
        let summary: PersonalKitSummary
        let signature: String
        let byteCount: Int
    }
    private let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func size(of url: URL, limit: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              (1...limit).contains(size) else { throw SampleError.invalid }
        return size
    }

    private func entry(_ id: UUID) throws -> Entry {
        let dir = folder(id)
        let values = try dir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw SampleError.invalid }
        let info = dir.appendingPathComponent("info.json")
        _ = try size(of: info, limit: 4_096)
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: info))
        guard entry.summary.id == id, (0...16).contains(entry.summary.assignedCount),
              try PersonalDrumKit.validName(entry.summary.name) == entry.summary.name,
              entry.signature.utf8.count == 64,
              try size(of: dir.appendingPathComponent("kit.grillakit"), limit: PersonalDrumKit.byteLimit) == entry.byteCount
        else { throw SampleError.invalid }
        return entry
    }

    private func entries() throws -> [Entry] {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return try folders.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try entry(id)
        }
    }

    public func list() throws -> [PersonalKitSummary] {
        try entries().map(\.summary).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func load(_ id: UUID) throws -> PersonalDrumKit {
        let entry = try entry(id)
        let kit = try PersonalDrumKit(archive: Data(contentsOf: folder(id).appendingPathComponent("kit.grillakit")))
        guard kit.summary == entry.summary, try kit.signature() == entry.signature else { throw SampleError.invalid }
        return kit
    }

    public func save(_ kit: PersonalDrumKit) throws -> PersonalKitSummary {
        let entries = try entries(), signature = try kit.signature()
        if let existing = entries.first(where: { $0.summary.name.caseInsensitiveCompare(kit.summary.name) == .orderedSame }) {
            guard existing.signature == signature else { throw PersonalKitError.conflict }
            return try load(existing.summary.id).summary
        }
        guard entries.count < 64 else { throw PersonalKitError.full }
        let archive = try kit.archive()
        guard archive.count <= PersonalDrumKit.byteLimit,
              entries.reduce(archive.count, { $0 + $1.byteCount }) <= 128_000_000 else { throw PersonalKitError.full }
        let staging = root.appendingPathComponent(".save-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try Task.checkCancellation()
        try archive.write(to: staging.appendingPathComponent("kit.grillakit"))
        let info = Entry(summary: kit.summary, signature: signature, byteCount: archive.count)
        try JSONEncoder().encode(info).write(to: staging.appendingPathComponent("info.json"))
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: folder(kit.summary.id))
        return kit.summary
    }

    public func delete(_ id: UUID) throws {
        let target = folder(id)
        let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw SampleError.invalid }
        try fm.removeItem(at: target)
    }
}
