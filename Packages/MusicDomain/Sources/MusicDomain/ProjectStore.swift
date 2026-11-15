import Foundation
/// Serial actor: disk writes never run on the audio or main thread.
public actor ProjectStore {
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
            if let header = try? JSONSerialization.jsonObject(with:old) as? [String:Any], let version=header["schemaVersion"] as? Int, version>Project.currentSchemaVersion {
                throw MusicError.unsupportedSchema
            }
            if let valid = try? ProjectDocument.decode(old), (try? valid.validate()) != nil {
                if valid.revision > project.revision {return valid.revision}
                try old.write(to:folder.appendingPathComponent("backup.json"),options:.atomic)
            }
        }
        try data.write(to: manifest, options: .atomic)
        return project.revision
    }
    public func load(_ id: UUID, backup: Bool = false) throws -> Project {
        let file = package(id).appendingPathComponent(backup ? "backup.json" : "manifest.json")
        let values = try file.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 8_000_000 else { throw MusicError.tooDense }
        let p = try ProjectDocument.decode(Data(contentsOf:file)); try p.validate(); return p
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
