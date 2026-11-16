import Foundation

/// Catalogue metadata only. It retains no Project, patterns, events or frozen
/// performance source. A document must still pass ProjectStore.load before use.
public struct ProjectSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let bpm: Double
    public let keyRoot: Int
    public let minor: Bool
    public let bars: Int
    public let revision: Int
    public let modified: Date
    public let schemaVersion: Int
    public let trackCount: Int
    public var length: Int { bars * barTicks }
    public var keyName: String { Chord.roots[keyRoot] + " " + NSLocalizedString(minor ? "minor" : "major", comment: "Key mode") }
}

private struct ProjectSummaryDocument: Decodable {
    let summary: ProjectSummary
    private enum Keys: String, CodingKey {
        case id, name, bpm, keyRoot, minor, revision, modified, schemaVersion, sections, tracks, performanceTakes
    }
    private enum SectionKeys: String, CodingKey { case start, length }
    private enum TakeKeys: String, CodingKey { case source }

    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: Keys.self)
        let version = try value.decode(Int.self, forKey: .schemaVersion)
        guard (1...Project.currentSchemaVersion).contains(version) else { throw MusicError.unsupportedSchema }
        let id = try value.decode(UUID.self, forKey: .id)
        let name = try value.decode(String.self, forKey: .name)
        let bpm = try value.decode(Double.self, forKey: .bpm)
        let keyRoot = try value.decode(Int.self, forKey: .keyRoot)
        let minor = try value.decode(Bool.self, forKey: .minor)
        let revision = try value.decode(Int.self, forKey: .revision)
        let modified = try value.decode(Date.self, forKey: .modified)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              bpm.isFinite, (40...240).contains(bpm), (0..<12).contains(keyRoot),
              (0...Project.maximumRevision).contains(revision), modified.timeIntervalSinceReferenceDate.isFinite else { throw MusicError.invalidProject }

        let tracks = try value.nestedUnkeyedContainer(forKey: .tracks)
        guard let trackCount = tracks.count, (2...8).contains(trackCount) else { throw MusicError.invalidProject }
        var sections = try value.nestedUnkeyedContainer(forKey: .sections)
        guard let sectionCount = sections.count, (1...8).contains(sectionCount) else { throw MusicError.invalidProject }
        var end = 0
        while !sections.isAtEnd {
            let section = try sections.nestedContainer(keyedBy: SectionKeys.self)
            let start = try section.decode(Int.self, forKey: .start)
            let length = try section.decode(Int.self, forKey: .length)
            guard start == end, length > 0, length <= 64 * barTicks,
                  length % barTicks == 0, length <= 64 * barTicks - end else { throw MusicError.invalidProject }
            end += length
        }
        // A future frozen source must not appear compatible merely because the
        // outer document's version is supported. Do not decode its musical data.
        if value.contains(.performanceTakes), try !value.decodeNil(forKey: .performanceTakes) {
            var takes = try value.nestedUnkeyedContainer(forKey: .performanceTakes)
            guard let count = takes.count, count <= 1 else { throw MusicError.invalidProject }
            while !takes.isAtEnd {
                let take = try takes.nestedContainer(keyedBy: TakeKeys.self)
                let source = try take.nestedContainer(keyedBy: Keys.self, forKey: .source)
                let sourceVersion = try source.decode(Int.self, forKey: .schemaVersion)
                guard (1...Project.currentSchemaVersion).contains(sourceVersion) else { throw MusicError.unsupportedSchema }
                if source.contains(.performanceTakes), try !source.decodeNil(forKey: .performanceTakes) {
                    let nested = try source.nestedUnkeyedContainer(forKey: .performanceTakes)
                    guard nested.isAtEnd else { throw MusicError.invalidProject }
                }
            }
        }
        summary = ProjectSummary(id: id, name: name, bpm: bpm, keyRoot: keyRoot, minor: minor,
                                 bars: end / barTicks, revision: revision, modified: modified,
                                 schemaVersion: version, trackCount: trackCount)
    }
}

/// Serial actor: disk writes never run on the audio or main thread.
public actor ProjectStore {
    public enum RenameError: Error, LocalizedError {
        case staleRevision, invalidName
        public var errorDescription: String? {
            let key = switch self {
            case .staleRevision: "This project changed. Refresh the project list and try renaming it again."
            case .invalidName: "Use a project name with 1–120 characters and no control characters."
            }
            return NSLocalizedString(key, comment: "Project rename")
        }
    }
    public let root: URL
    public init(root: URL) { self.root = root }
    private func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("grilla") }
    @discardableResult public func save(_ project: Project) throws -> Int {
        try project.validate()
        let folder = package(project.id); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let data = try encoder.encode(project)
        _ = try JSONDecoder().decode(Project.self, from: data)
        let manifest = folder.appendingPathComponent("manifest.json")
        if let old = try? Data(contentsOf: manifest) {
            if old==data{return project.revision}
            // This decoder checks outer/frozen-source schema headers before
            // decoding, then migrates and fully validates exactly once.
            let valid: Project?
            do { valid = try ProjectDocument.decode(old) }
            catch MusicError.unsupportedSchema { throw MusicError.unsupportedSchema }
            catch { valid = nil }
            if let valid, valid.id == project.id {
                if valid.revision > project.revision {return valid.revision}
                try old.write(to:folder.appendingPathComponent("backup.json"),options:.atomic)
            }
        }
        try data.write(to: manifest, options: .atomic)
        return project.revision
    }
    public func load(_ id: UUID, backup: Bool = false) throws -> Project {
        let project = try ProjectDocument.decode(readManifest(id, backup: backup))
        guard project.id == id else { throw MusicError.invalidProject }
        return project
    }
    private func readManifest(_ id: UUID, backup: Bool = false) throws -> Data {
        let file = package(id).appendingPathComponent(backup ? "backup.json" : "manifest.json")
        let values = try file.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 8_000_000 else { throw MusicError.tooDense }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8_000_001) ?? Data()
        guard data.count <= 8_000_000 else { throw MusicError.tooDense }
        return data
    }
    /// Read/compare/write in one actor turn. A catalogue row is a revision token,
    /// not the document to save: the canonical project may have changed meanwhile.
    @discardableResult public func rename(_ id: UUID, expectedRevision: Int, to name: String) throws -> Project {
        var project = try load(id)
        guard project.id == id else { throw MusicError.invalidProject }
        guard project.revision == expectedRevision else { throw RenameError.staleRevision }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120,
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) else { throw RenameError.invalidName }
        guard project.revision < Project.maximumRevision else { throw MusicError.revisionLimit }
        let modified = max(Date().timeIntervalSinceReferenceDate, project.modified.timeIntervalSinceReferenceDate.nextUp)
        guard modified.isFinite else { throw MusicError.invalidProject }
        project.name = title
        project.revision += 1
        project.modified = Date(timeIntervalSinceReferenceDate: modified)
        try save(project)
        return project
    }
    public struct Entry: Sendable, Identifiable { public let id: UUID; public let project: Project?; public let error: String? }
    public struct SummaryEntry: Sendable, Identifiable {
        public let id: UUID
        public let summary: ProjectSummary?
        public let error: String?
        /// Presence of a regular backup file, not proof that it is valid.
        public let hasBackup: Bool
        public init(id: UUID, summary: ProjectSummary?, error: String?, hasBackup: Bool) {
            self.id = id; self.summary = summary; self.error = error; self.hasBackup = hasBackup
        }
    }
    /// Reads just one real manifest. Even valid metadata is not musical validation;
    /// callers retain a full-load error row until retry/recovery succeeds.
    public func summary(_ id: UUID) -> SummaryEntry {
        let backup = package(id).appendingPathComponent("backup.json")
        let hasBackup = (try? backup.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        do {
            let value = try JSONDecoder().decode(ProjectSummaryDocument.self, from: readManifest(id)).summary
            guard value.id == id else { throw MusicError.invalidProject }
            return SummaryEntry(id: id, summary: value, error: nil, hasBackup: hasBackup)
        } catch {
            let message = error is DecodingError ? MusicError.invalidProject.localizedDescription : error.localizedDescription
            return SummaryEntry(id: id, summary: nil, error: String(message.prefix(1024)), hasBackup: hasBackup)
        }
    }
    public func listSummaries() throws -> [SummaryEntry] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "grilla" }
            .compactMap { url -> SummaryEntry? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                return summary(id)
            }
            .sorted {
                let left = $0.summary?.modified ?? .distantPast, right = $1.summary?.modified ?? .distantPast
                return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
            }
    }
    public func list() throws -> [Entry] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter {$0.pathExtension == "grilla"}.compactMap { url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            do { return Entry(id: id, project: try load(id), error: nil) } catch { return Entry(id: id, project: nil, error: error.localizedDescription) }
        }.sorted { ($0.project?.modified ?? .distantPast) > ($1.project?.modified ?? .distantPast) }
    }
    public func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: package(id)) }
}

public extension ProjectStore {
    func writeAsset(_ data:Data,record:AudioAssetRecord,projectID:UUID)throws {
        try AssetIntegrity.validate(data,record:record)
        let url=package(projectID).appendingPathComponent(record.relativePath)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
    func assetURL(_ record:AudioAssetRecord,projectID:UUID)throws->URL {
        let url=package(projectID).appendingPathComponent(record.relativePath)
        let count=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize
        guard count==record.byteCount else{throw ExportError.invalidArchive}
        try AssetIntegrity.validate(Data(contentsOf:url),record:record);return url
    }
    func removeStagedAsset(_ record:AudioAssetRecord,projectID:UUID){try? FileManager.default.removeItem(at:package(projectID).appendingPathComponent(record.relativePath))}
    func portable(_ project:Project,to url:URL)throws {
        let entries=try PortableProject.documentEntries(project)
        var files:[(name:String,url:URL)]=[]
        for record in project.audioAssets ?? []{try Task.checkCancellation();files.append((record.relativePath,try assetURL(record,projectID:project.id)))}
        try ProjectArchive.writeFiles(files,extras:entries,to:url)
    }
    func install(_ bundle:PortableProjectBundle)throws->Project {
        try bundle.project.validate();let folder=package(bundle.project.id)
        guard !FileManager.default.fileExists(atPath:folder.path)else{throw ExportError.invalidArchive}
        do{for record in bundle.project.audioAssets ?? []{guard let data=bundle.assets[record.relativePath]else{throw ExportError.invalidArchive};try writeAsset(data,record:record,projectID:bundle.project.id)};try save(bundle.project);return bundle.project}
        catch{try? FileManager.default.removeItem(at:folder);throw error}
    }
    func duplicate(_ source:Project,suffix:String=" copy")throws->Project {
        try source.validate();var copy=source;copy.id=UUID();copy.name=String(copy.name.prefix(110))+suffix;copy.modified=Date();copy.revision=0
        let folder=package(copy.id)
        do{for record in source.audioAssets ?? []{try Task.checkCancellation();let url=try assetURL(record,projectID:source.id);try writeAsset(Data(contentsOf:url),record:record,projectID:copy.id)};try save(copy);return copy}
        catch{try? FileManager.default.removeItem(at:folder);throw error}
    }
}
