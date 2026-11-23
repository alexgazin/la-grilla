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
        guard let sectionCount = sections.count, (1...maximumSections).contains(sectionCount) else { throw MusicError.invalidProject }
        var end = 0
        while !sections.isAtEnd {
            let section = try sections.nestedContainer(keyedBy: SectionKeys.self)
            let start = try section.decode(Int.self, forKey: .start)
            let length = try section.decode(Int.self, forKey: .length)
            guard start == end, length > 0, length <= songTickLimit,
                  length % barTicks == 0, length <= songTickLimit - end else { throw MusicError.invalidProject }
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
    /// Immutable, so it is read without awaiting the actor (Swift 6.1 and later).
    public nonisolated let root: URL
    public init(root: URL) { self.root = root }
    func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("grilla") }
    @discardableResult public func save(_ project: Project) throws -> Int {
        try project.validate()
        for asset in project.referencedSamples { _ = try sampleURL(asset, projectID: project.id) }
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

    // MARK: I73 · Recently deleted (30 days)

    public struct TrashedProject: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let deletedAt: Date
    }
    /// A sibling folder, so the project list (which reads only `root`) never sees it.
    private var trashRoot: URL { root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-RecentlyDeleted", isDirectory: true) }
    private func trashed(_ id: UUID) -> URL { trashRoot.appendingPathComponent(id.uuidString).appendingPathExtension("grilla") }

    /// Move a project with its samples and recordings out of the list; it can be restored for 30 days.
    public func moveToTrash(_ id: UUID, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let destination = trashed(id)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: package(id), to: destination)
        try Data(ISO8601DateFormatter().string(from: now).utf8).write(to: destination.appendingPathComponent("deleted-at.txt"), options: .atomic)
    }

    public func recentlyDeleted() -> [TrashedProject] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "grilla" }.compactMap { url -> TrashedProject? in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let stamp = try? String(contentsOf: url.appendingPathComponent("deleted-at.txt"), encoding: .utf8),
                  let date = ISO8601DateFormatter().date(from: stamp.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let name = (try? Data(contentsOf: url.appendingPathComponent("manifest.json"))).flatMap { try? ProjectDocument.decode($0).name } ?? NSLocalizedString("Untitled", comment: "Project name")
            return TrashedProject(id: id, name: name, deletedAt: date)
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Put a trashed project back into the list; refuses to overwrite a live project.
    public func restoreFromTrash(_ id: UUID) throws {
        guard !FileManager.default.fileExists(atPath: package(id).path) else { throw MusicError.invalidProject }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: trashed(id), to: package(id))
        try? FileManager.default.removeItem(at: package(id).appendingPathComponent("deleted-at.txt"))
    }

    /// Permanently remove projects deleted more than `days` ago. Returns how many.
    @discardableResult public func purgeTrash(olderThan days: Int = 30, now: Date = Date()) -> Int {
        var removed = 0
        for item in recentlyDeleted() where now.timeIntervalSince(item.deletedAt) > Double(days) * 86_400 {
            if (try? FileManager.default.removeItem(at: trashed(item.id))) != nil { removed += 1 }
        }
        return removed
    }
}

public extension ProjectStore {
    /// Each staged asset uses a fresh UUID so a cancelled edit can remove
    /// its file without affecting a saved or undoable assignment.
    func stageSample(_ data: Data, asset: SampleAsset, projectID: UUID) throws -> PreparedSampleBank {
        let prepared = try PreparedSampleBank(asset: asset, data: data)
        guard !FileManager.default.fileExists(atPath: package(projectID).appendingPathComponent(asset.relativePath).path) else {
            throw SampleError.invalid
        }
        try putSample(data, asset: asset, projectID: projectID)
        return prepared
    }

    func removeStagedSample(_ asset: SampleAsset, projectID: UUID) {
        try? FileManager.default.removeItem(at: package(projectID).appendingPathComponent(asset.relativePath))
    }

    private func putSample(_ data: Data, asset: SampleAsset, projectID: UUID) throws {
        let url = package(projectID).appendingPathComponent(asset.relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let current = try readSample(asset, projectID: projectID)
            guard current == data else { throw SampleError.invalid }
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private func sampleURL(_ asset: SampleAsset, projectID: UUID) throws -> URL {
        try asset.validate()
        let url = package(projectID).appendingPathComponent(asset.relativePath)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              values?.fileSize == asset.byteCount else { throw SampleError.unavailable }
        return url
    }

    private func readSample(_ asset: SampleAsset, projectID: UUID) throws -> Data {
        let url = try sampleURL(asset, projectID: projectID)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: asset.byteCount + 1) ?? Data()
        guard data.count == asset.byteCount else { throw SampleError.invalid }
        return data
    }

    func sampleData(_ asset: SampleAsset, projectID: UUID) throws -> Data {
        let bytes = try readSample(asset, projectID: projectID)
        _ = try SamplePCM.decode(bytes, asset: asset)
        return bytes
    }

    func storedSampleBank(_ asset: SampleAsset, projectID: UUID) throws -> PreparedSampleBank {
        try PreparedSampleBank(asset: asset, data: readSample(asset, projectID: projectID))
    }

    func loadSamples(for project: Project) throws -> SampleLibrary {
        var library = SampleLibrary()
        for asset in project.referencedSamples {
            try Task.checkCancellation()
            let bank = try storedSampleBank(asset, projectID: project.id)
            try project.validatePadEditRate(for: asset, rate: bank.sampleRate)
            library.insert(bank)
        }
        return library
    }

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
    /// I70: several projects (at most 64) as one zip of portable projects.
    @discardableResult func portableBatch(_ ids:[UUID],to url:URL)throws->Int {
        guard (1...64).contains(ids.count) else{throw ExportError.invalidSettings}
        let folder=url.deletingLastPathComponent().appendingPathComponent("batch-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let projects=try ids.map{try load($0)}
        let names=ProjectArchive.fileNames(projects.map(\.name),extension:"grillapack")
        var files:[(name:String,url:URL)]=[]
        for (project,name) in zip(projects,names) {
            try Task.checkCancellation()
            let file=folder.appendingPathComponent(name)
            try portable(project,to:file);files.append((name,file))
        }
        try ProjectArchive.writeFiles(files,to:url)
        return files.count
    }
    func portable(_ project:Project,to url:URL)throws {
        let entries=try PortableProject.documentEntries(project)
        var files:[(name:String,url:URL)]=[]
        for record in project.audioAssets ?? []{try Task.checkCancellation();files.append((record.relativePath,try assetURL(record,projectID:project.id)))}
        for asset in project.referencedSamples.sorted(by: { $0.relativePath < $1.relativePath }) {
            try Task.checkCancellation()
            let pcm = try SamplePCM.decode(readSample(asset, projectID: project.id), asset: asset)
            try project.validatePadEditRate(for: asset, rate: pcm.rate)
            files.append((asset.relativePath, try sampleURL(asset, projectID: project.id)))
        }
        try ProjectArchive.writeFiles(files,extras:entries,to:url)
        // I78: remember what was shared, as the base for merging a co-author's copy.
        if let data=try? JSONEncoder().encode(project){try? data.write(to:package(project.id).appendingPathComponent("shared-base.json"),options:.atomic)}
    }
    /// I78: the version last exported as a portable project, if any.
    func sharedBase(_ id:UUID)->Project? {
        guard let data=try? Data(contentsOf:package(id).appendingPathComponent("shared-base.json")),data.count<=8_000_000,
              let project=try? JSONDecoder().decode(Project.self,from:data),(try? project.validate()) != nil else{return nil}
        return project
    }
    func install(_ bundle:PortableProjectBundle)throws->Project {
        try bundle.project.validate();let folder=package(bundle.project.id)
        guard !FileManager.default.fileExists(atPath:folder.path)else{throw ExportError.invalidArchive}
        do {
            for record in bundle.project.audioAssets ?? []{guard let data=bundle.assets[record.relativePath]else{throw ExportError.invalidArchive};try writeAsset(data,record:record,projectID:bundle.project.id)}
            for asset in bundle.project.referencedSamples {
                try Task.checkCancellation()
                guard let data = bundle.assets[asset.relativePath] else { throw SampleError.unavailable }
                let pcm = try SamplePCM.decode(data, asset: asset)
                try bundle.project.validatePadEditRate(for: asset, rate: pcm.rate)
                try putSample(data, asset: asset, projectID: bundle.project.id)
            }
            try save(bundle.project)
            return bundle.project
        }
        catch{try? FileManager.default.removeItem(at:folder);throw error}
    }
    func duplicate(_ source:Project,suffix:String=" copy")throws->Project {
        try source.validate();var copy=source;copy.id=UUID();copy.name=String(copy.name.prefix(110))+suffix;copy.modified=Date();copy.revision=0
        let folder=package(copy.id)
        do {
            for record in source.audioAssets ?? []{try Task.checkCancellation();let url=try assetURL(record,projectID:source.id);try writeAsset(Data(contentsOf:url),record:record,projectID:copy.id)}
            for asset in source.referencedSamples {
                try Task.checkCancellation()
                let data = try readSample(asset, projectID: source.id)
                let pcm = try SamplePCM.decode(data, asset: asset)
                try source.validatePadEditRate(for: asset, rate: pcm.rate)
                try putSample(data, asset: asset, projectID: copy.id)
            }
            try save(copy)
            return copy
        }
        catch{try? FileManager.default.removeItem(at:folder);throw error}
    }

    func createFromPerformance(_ take: PerformanceTake, projectID: UUID) throws -> Project {
        var draft = try PerformanceTimeline.arrangement(take)
        // Copies of a project may still contain a take whose frozen source has
        // the original ID. The active package owns all of that take's assets.
        draft.id = projectID
        return try duplicate(draft, suffix: "")
    }
}

/// I50 · the musician's habits from their own saved projects, computed on the
/// device only: median tempo, most used key and mode, usual length. Needs at
/// least three projects; nothing leaves the iPhone.
public struct StyleProfile: Equatable, Sendable {
    public let bpm: Double
    public let keyRoot: Int
    public let minor: Bool
    public let bars: Int
    public let projects: Int

    public static func from(_ summaries: [ProjectSummary], minimum: Int = 3) -> StyleProfile? {
        let valid = summaries.filter { $0.bpm.isFinite && (40...240).contains($0.bpm) && (0..<12).contains($0.keyRoot) && $0.bars > 0 }
        guard valid.count >= max(1, minimum) else { return nil }
        let tempos = valid.map(\.bpm).sorted()
        let middle = tempos.count / 2
        let median = tempos.count.isMultiple(of: 2) ? (tempos[middle - 1] + tempos[middle]) / 2 : tempos[middle]
        // Most frequent key; ties go to the most recently modified project.
        let recent = valid.sorted { $0.modified > $1.modified }
        var counts: [Int: Int] = [:]
        for s in valid { counts[s.keyRoot * 2 + (s.minor ? 1 : 0), default: 0] += 1 }
        let top = counts.values.max() ?? 0
        let key = recent.first { counts[$0.keyRoot * 2 + ($0.minor ? 1 : 0)] == top }!
        var bars: [Int: Int] = [:]
        for s in valid { bars[s.bars, default: 0] += 1 }
        let usualBars = bars.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }!.key
        return StyleProfile(bpm: median.rounded(), keyRoot: key.keyRoot, minor: key.minor, bars: min(64, usualBars), projects: valid.count)
    }
}

/// I77 · automatic backup to a folder the musician chose in Files: at most
/// once a day, only projects changed since the previous backup.
public enum BackupPlanner {
    public static let interval: TimeInterval = 20 * 3600
    public static func due(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || now < last
    }
    public static func changed(_ summaries: [ProjectSummary], since last: Date?) -> [UUID] {
        summaries.filter { last == nil || $0.modified > last! }.sorted { $0.modified > $1.modified }.prefix(64).map(\.id)
    }
    public static func fileName(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "La Grilla backup %04d-%02d-%02d.zip", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
