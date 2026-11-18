import Foundation

/// Files in this library are independent of the copies inside saved songs.
public actor PadSampleStore {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func list() throws -> [SampleAsset] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return folders.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try? entry(id)
        }.sorted {
            let ordered = $0.name.localizedStandardCompare($1.name)
            return ordered == .orderedSame ? $0.id.uuidString < $1.id.uuidString : ordered == .orderedAscending
        }
    }

    public func add(_ data: Data, asset: SampleAsset) throws -> SampleAsset {
        guard asset.kind == .oneShot else { throw SampleError.invalid }
        _ = try SamplePCM.decode(data, asset: asset)
        let assets = try list()
        if let existing = assets.first(where: { $0.sha256 == asset.sha256 && $0.name == asset.name }),
           (try? bytes(for: existing)) == data { return existing }
        guard assets.count < 256, assets.reduce(asset.byteCount, { $0 + $1.byteCount }) <= 96_000_000 else {
            throw SampleError.libraryLimit
        }
        let folder = root.appendingPathComponent(asset.id.uuidString, isDirectory: true)
        let staging = root.appendingPathComponent(".import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let header = try JSONEncoder().encode(asset)
        guard header.count <= 4096 else { throw SampleError.invalid }
        try header.write(to: staging.appendingPathComponent("sample.json"))
        try data.write(to: staging.appendingPathComponent("sound.lgpcm"))
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: folder)
        return asset
    }

    public func bytes(for asset: SampleAsset) throws -> Data {
        guard try entry(asset.id) == asset else { throw SampleError.unavailable }
        let url = root.appendingPathComponent(asset.id.uuidString).appendingPathComponent("sound.lgpcm")
        let data = try read(url, maximum: asset.byteCount)
        _ = try SamplePCM.decode(data, asset: asset)
        return data
    }

    public func previewWAV(for asset: SampleAsset) throws -> Data {
        let pcm = try SamplePCM.decode(bytes(for: asset), asset: asset)
        guard let zone = pcm.zones.first else { throw SampleError.invalid }
        var wave = pcmWAVHeader(rate: pcm.rate, channels: 1, bits: 16, byteCount: zone.samples.count * 2)
        for value in zone.samples { wave.little(value) }
        return wave
    }

    public func remove(_ asset: SampleAsset) throws {
        guard try entry(asset.id) == asset else { throw SampleError.unavailable }
        try FileManager.default.removeItem(at: root.appendingPathComponent(asset.id.uuidString, isDirectory: true))
    }

    private func entry(_ id: UUID) throws -> SampleAsset {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let header = try read(folder.appendingPathComponent("sample.json"), maximum: 4096)
        let asset = try JSONDecoder().decode(SampleAsset.self, from: header)
        try asset.validate()
        guard asset.id == id, asset.kind == .oneShot else { throw SampleError.invalid }
        return asset
    }

    private func read(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...maximum).contains(size) else { throw SampleError.invalid }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximum + 1) ?? Data()
        guard data.count == size else { throw SampleError.invalid }
        return data
    }
}
