import Foundation

public struct PersonalKitSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let assignedCount: Int
}

public enum PersonalKitError: Error, LocalizedError {
    case name, conflict, full
    public var errorDescription: String? {
        let key = switch self {
        case .name: "Enter a kit name of 1–60 characters."
        case .conflict: "Choose another name for this kit."
        case .full: "The personal kit library is full."
        }
        return NSLocalizedString(key, comment: "Personal drum kit")
    }
}

public struct PersonalDrumKit: Sendable {
    struct Manifest: Codable, Sendable {
        let version: Int
        let summary: PersonalKitSummary
        let preset: Int
        let pads: [Int: SampleAsset]
        let edits: [Int: PadSampleEditRecord]
    }

    static let byteLimit = 26_000_000
    let manifest: Manifest
    let blobs: [String: Data]
    public var summary: PersonalKitSummary { manifest.summary }

    static func validName(_ name: String) throws -> String {
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(result.count), result.utf8.count <= 512,
              !result.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw PersonalKitError.name }
        return result
    }

    init(manifest: Manifest, blobs: [String: Data]) throws {
        let m = manifest
        guard m.version == 1, try Self.validName(m.summary.name) == m.summary.name,
              SoundPalette(rawValue: m.preset) != nil, m.summary.assignedCount == m.pads.count,
              m.pads.keys.allSatisfy((0..<16).contains), Set(m.edits.keys).isSubset(of: m.pads.keys) else { throw SampleError.invalid }
        let descriptors = Set(m.pads.values).union(m.edits.values.map(\.source))
        guard Set(descriptors.map(\.id)).count == descriptors.count,
              Set(descriptors.map(\.sha256)) == Set(blobs.keys) else { throw SampleError.invalid }
        var rates: [String: Int] = [:]
        for asset in descriptors {
            try Task.checkCancellation()
            try asset.validate()
            guard asset.kind == .oneShot, let data = blobs[asset.sha256], data.count == asset.byteCount else { throw SampleError.invalid }
            if rates[asset.sha256] == nil { rates[asset.sha256] = try SamplePCM.decode(data, asset: asset).rate }
        }
        for (pad, record) in m.edits {
            try record.validate(rendered: m.pads[pad])
            guard rates[record.source.sha256] == record.sourceRate,
                  let output = m.pads[pad], rates[output.sha256] == record.sourceRate else { throw SampleError.invalid }
        }
        self.manifest = m
        self.blobs = blobs
    }

    public func archive() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(manifest)
        guard json.count < 160_000 else { throw SampleError.limit }
        var entries = [ProjectArchive.Entry("kit.json", json)]
        for (sha, data) in blobs.sorted(by: { $0.key < $1.key }) {
            entries.append(.init("Samples/" + sha + ".lgpcm", data))
        }
        return try ProjectArchive.encode(entries)
    }

    public init(archive: Data) throws {
        let entries = try ProjectArchive.decode(archive, maxBytes: Self.byteLimit)
        guard let json = entries.first(where: { $0.name == "kit.json" })?.data, json.count < 160_000 else { throw SampleError.invalid }
        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        var blobs: [String: Data] = [:]
        for entry in entries where entry.name != "kit.json" {
            guard entry.name.hasPrefix("Samples/"), entry.name.hasSuffix(".lgpcm") else { throw SampleError.invalid }
            blobs[String(entry.name.dropFirst(8).dropLast(6))] = entry.data
        }
        try self.init(manifest: manifest, blobs: blobs)
    }

    /// Compare what is audible and editable across projects with different sample UUIDs.
    func signature() throws -> String {
        struct Slot: Encodable {
            var name: String?
            var hash: String?
            var sourceName: String?
            var sourceHash: String?
            var edit: OneShotEdit?
        }
        struct Layout: Encodable { let preset: Int; let slots: [Slot] }
        let slots = (0..<16).map { pad in
            let sample = manifest.pads[pad], record = manifest.edits[pad]
            return Slot(name: sample?.name, hash: sample?.sha256, sourceName: record?.source.name,
                        sourceHash: record?.source.sha256, edit: record?.edit)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try AssetIntegrity.sha256(encoder.encode(Layout(preset: manifest.preset, slots: slots)))
    }
}

public struct PreparedPersonalKit: Sendable {
    let preset: Int
    let pads: [Int: SampleAsset]
    let edits: [Int: PadSampleEditRecord]
    public let banks: [PreparedSampleBank]
    public let staged: [SampleAsset]

    public func apply(to track: inout Track) throws {
        guard track.role == .drums else { throw SampleError.invalid }
        track.presetVersion = preset
        track.padSamples = pads.isEmpty ? nil : pads
        track.padEdits = edits.isEmpty ? nil : edits
    }
}

public extension ProjectStore {
    func capturePersonalKit(name: String, track: Track, projectID: UUID) throws -> PersonalDrumKit {
        let name = try PersonalDrumKit.validName(name)
        guard track.role == .drums else { throw SampleError.invalid }
        let pads = track.padSamples ?? [:], edits = track.padEdits ?? [:]
        let summary = PersonalKitSummary(id: UUID(), name: name, assignedCount: pads.count)
        var blobs: [String: Data] = [:]
        for asset in Set(pads.values).union(edits.values.map(\.source)) {
            try Task.checkCancellation()
            blobs[asset.sha256] = try sampleData(asset, projectID: projectID)
        }
        return try PersonalDrumKit(manifest: .init(version: 1, summary: summary, preset: track.presetVersion, pads: pads, edits: edits), blobs: blobs)
    }

    func preparePersonalKit(_ kit: PersonalDrumKit, projectID: UUID, retaining: Set<SampleAsset>,
                            replacing track: Track? = nil) throws -> PreparedPersonalKit {
        let m = kit.manifest
        var banks: [PreparedSampleBank] = [], staged: [SampleAsset] = []
        var mapped: [UUID: SampleAsset] = [:]
        var distinct: [UUID: Set<UUID>] = [:]
        for record in m.edits.values {
            distinct[record.source.id, default: []].insert(record.renderedID)
            distinct[record.renderedID, default: []].insert(record.source.id)
        }
        var preferred: [UUID: SampleAsset] = [:]
        for pad in 0..<16 {
            if let original = m.pads[pad], let current = track?.padSamples?[pad], retaining.contains(current) {
                preferred[original.id] = current
            }
            if let original = m.edits[pad]?.source, let current = track?.padEdits?[pad]?.source, retaining.contains(current) {
                preferred[original.id] = current
            }
        }
        let candidates = retaining.sorted { $0.id.uuidString < $1.id.uuidString }
        do {
            for asset in Set(m.pads.values).union(m.edits.values.map(\.source)).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                try Task.checkCancellation()
                let bank: PreparedSampleBank
                let excluded = Set((distinct[asset.id] ?? []).compactMap { mapped[$0]?.id })
                func matches(_ other: SampleAsset) -> Bool {
                    !excluded.contains(other.id) && other.kind == .oneShot && other.name == asset.name && other.sha256 == asset.sha256
                }
                let current = preferred[asset.id].flatMap { matches($0) ? $0 : nil }
                let reused = current ?? candidates.first(where: { $0.id == asset.id && matches($0) })
                    ?? banks.first(where: { matches($0.asset) })?.asset ?? candidates.first(where: matches)
                if let reused {
                    if banks.contains(where: { $0.asset == reused }) {
                        mapped[asset.id] = reused
                        continue
                    }
                    bank = try storedSampleBank(reused, projectID: projectID)
                } else {
                    guard let data = kit.blobs[asset.sha256] else { throw SampleError.invalid }
                    let fresh = try SampleAsset(kind: .oneShot, name: asset.name, bytes: data)
                    bank = try stageSample(data, asset: fresh, projectID: projectID)
                    staged.append(fresh)
                }
                mapped[asset.id] = bank.asset
                banks.append(bank)
            }
            let pads = try m.pads.mapValues { asset in
                guard let local = mapped[asset.id] else { throw SampleError.invalid }
                return local
            }
            let edits = try m.edits.mapValues { record in
                guard let source = mapped[record.source.id], let output = mapped[record.renderedID] else { throw SampleError.invalid }
                return PadSampleEditRecord(remapping: record, source: source, renderedID: output.id)
            }
            try Task.checkCancellation()
            return PreparedPersonalKit(preset: m.preset, pads: pads, edits: edits, banks: banks, staged: staged)
        } catch {
            for asset in staged { removeStagedSample(asset, projectID: projectID) }
            throw error
        }
    }
}
