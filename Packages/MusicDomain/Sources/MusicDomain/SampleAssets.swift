import AudioDSP
import Foundation

public struct SampleAsset: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case instrument, oneShot }

    public let id: UUID
    public let kind: Kind
    public let ringsOut: Bool?
    public let name: String
    public let byteCount: Int
    public let sha256: String
    /// I34: a one-shot holding 2…4 layers of one pad, chosen by velocity or in turn.
    public let layers: PadLayerMode?
    public var relativePath: String { "Samples/" + id.uuidString + ".lgpcm" }

    public init(kind: Kind, name: String, bytes: Data, id: UUID = UUID(), ringsOut: Bool = false, layers: PadLayerMode? = nil) throws {
        self.id = id
        self.kind = kind
        self.layers = layers
        self.ringsOut = ringsOut ? true : nil
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        byteCount = bytes.count
        sha256 = try AssetIntegrity.sha256(bytes)
        try validate()
    }

    public func validate() throws {
        guard (ringsOut != true || kind == .instrument), (layers == nil || kind == .oneShot), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (20...8_000_000).contains(byteCount), sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MusicError.invalidProject
        }
    }
}

public extension Project {
    var referencedSamples: Set<SampleAsset> {
        // Deleted tracks keep their samples so they can come back (U8).
        let allTracks = tracks + (performanceTake?.source.tracks ?? []) + (recentlyDeleted ?? []).compactMap(\.track)
        var result: Set<SampleAsset> = []
        for track in allTracks {
            if let sample = track.instrumentSample { result.insert(sample) }
            if let pads = track.padSamples { result.formUnion(pads.values) }
            if let edits = track.padEdits { result.formUnion(edits.values.map(\.source)) }
        }
        return result
    }
}

public enum SampleError: Error, LocalizedError, Sendable {
    case invalid, unavailable, limit, libraryLimit, stale

    public var errorDescription: String? {
        let key: String = switch self {
        case .invalid: "This sound sample is unsupported or damaged. Try another file."
        case .unavailable: "A sound sample is missing. Restore it from a portable project."
        case .limit: "This project has reached its sound sample limit. Empty Recently deleted or remove a sound."
        case .libraryLimit: "The pad sample library is full. Remove a sample to make room."
        case .stale: "The project changed while preparing this sound. Try again."
        }
        return NSLocalizedString(key, comment: "Imported sound")
    }
}

/// A versioned little-endian PCM container. Each zone stores an attack and an
/// optional sustain loop. Unlooped sounds continue to decay naturally.
public struct SamplePCM: Sendable {
    public struct Zone: Sendable {
        public let pitch: Int
        public let samples: [Int16]
        public let loopStart: Int

        public init(pitch: Int, samples: [Int16], loopStart: Int = 0) {
            self.pitch = pitch
            self.samples = samples
            self.loopStart = loopStart
        }
    }

    public let rate: Int
    public let zones: [Zone]

    public init(rate: Int, zones: [Zone]) { self.rate = rate; self.zones = zones }

    public func encode(kind: SampleAsset.Kind, layered: Bool = false) throws -> Data {
        try validate(kind: kind, layered: layered)
        var data = Data("LGS1".utf8)
        data.little(UInt32(rate))
        data.little(UInt32(zones.count))
        for zone in zones {
            data.little(UInt32(zone.pitch))
            data.little(UInt32(zone.samples.count))
            data.little(UInt32(zone.loopStart))
            // All supported Swift targets are little-endian. Keep the byte
            // order explicit so files are portable to other tools too.
            zone.samples.map(\.littleEndian).withUnsafeBytes { data.append(contentsOf: $0) }
        }
        guard data.count <= 8_000_000 else { throw SampleError.limit }
        return data
    }

    public static func decode(_ data: Data, asset: SampleAsset) throws -> Self {
        try asset.validate()
        guard data.count == asset.byteCount, data.count >= 24,
              data.prefix(4).elementsEqual("LGS1".utf8), try AssetIntegrity.sha256(data) == asset.sha256 else {
            throw SampleError.invalid
        }
        func word(_ at: Int) -> Int {
            Int(UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) }))
        }
        let rate = word(4), count = word(8)
        guard (8_000...48_000).contains(rate), (1...128).contains(count) else { throw SampleError.invalid }
        var index = 12
        var zones: [Zone] = []
        for _ in 0..<count {
            guard index + 12 <= data.count else { throw SampleError.invalid }
            let pitch = word(index), frames = word(index + 4), loop = word(index + 8)
            index += 12
            guard (32...rate * 8).contains(frames), frames <= (data.count - index) / 2 else { throw SampleError.invalid }
            var samples = [Int16](repeating: 0, count: frames)
            samples.withUnsafeMutableBytes { target in
                data.withUnsafeBytes { source in
                    target.copyBytes(from: UnsafeRawBufferPointer(rebasing: source[index..<(index + frames * 2)]))
                }
            }
            #if _endian(big)
            samples = samples.map(Int16.init(littleEndian:))
            #endif
            index += frames * 2
            zones.append(Zone(pitch: pitch, samples: samples, loopStart: loop))
        }
        guard index == data.count else { throw SampleError.invalid }
        let pcm = Self(rate: rate, zones: zones)
        try pcm.validate(kind: asset.kind, layered: asset.layers != nil)
        if asset.ringsOut == true && pcm.zones.contains(where: { $0.loopStart != 0 }) { throw SampleError.invalid }
        return pcm
    }

    private func validate(kind: SampleAsset.Kind, layered: Bool = false) throws {
        guard (8_000...48_000).contains(rate), (1...128).contains(zones.count),
              (kind != .oneShot || zones.count == 1 || layered), zones.reduce(0, { $0 + $1.samples.count }) <= 3_999_000 else {
            throw SampleError.invalid
        }
        if layered {
            guard kind == .oneShot, PadLayers.counts.contains(zones.count),
                  zones.enumerated().allSatisfy({ $0.offset == $0.element.pitch && $0.element.loopStart == 0 }) else { throw SampleError.invalid }
        }
        var previous = -1
        for zone in zones {
            guard (0...127).contains(zone.pitch), zone.pitch > previous,
                  (32...rate * 8).contains(zone.samples.count),
                  zone.loopStart == 0 || (kind == .instrument && zone.loopStart > 0 && zone.loopStart <= zone.samples.count - 1024) else {
                throw SampleError.invalid
            }
            previous = zone.pitch
        }
    }
}

/// PCM is immutable after construction. The DSP takes its own reference for
/// each submitted snapshot; Swift owners can be released during playback.
public final class PreparedSampleBank: @unchecked Sendable {
    public let asset: SampleAsset
    let sampleRate: Int
    let pointer: OpaquePointer

    public init(asset: SampleAsset, data: Data) throws {
        let pcm = try SamplePCM.decode(data, asset: asset)
        var frames: [Int16] = []
        frames.reserveCapacity(pcm.zones.reduce(0) { $0 + $1.samples.count })
        var zones: [LGSampleZone] = []
        for zone in pcm.zones {
            zones.append(LGSampleZone(pitch: Int32(zone.pitch), offset: Int32(frames.count),
                                      frames: Int32(zone.samples.count), loopStart: Int32(zone.loopStart)))
            frames.append(contentsOf: zone.samples)
        }
        let handle = zones.withUnsafeBufferPointer { table in
            frames.withUnsafeBufferPointer { samples in
                if let layers = asset.layers {
                    lg_sample_create_layers(Int32(pcm.rate), table.baseAddress, Int32(table.count),
                                            samples.baseAddress, Int32(samples.count), layers == .roundRobin ? 1 : 0)
                } else {
                    lg_sample_create_with_release(Int32(pcm.rate), table.baseAddress, Int32(table.count),
                                                  samples.baseAddress, Int32(samples.count), asset.ringsOut == true ? 1 : 0)
                }
            }
        }
        guard let handle else { throw SampleError.invalid }
        self.asset = asset
        sampleRate = pcm.rate
        pointer = handle
    }

    deinit { lg_sample_release(pointer) }
}

public struct SampleLibrary: Sendable {
    private var banks: [SampleAsset: PreparedSampleBank] = [:]

    public init() {}
    public var assets: Set<SampleAsset> { Set(banks.keys) }
    public mutating func insert(_ bank: PreparedSampleBank) { banks[bank.asset] = bank }
    public mutating func retainOnly(_ assets: Set<SampleAsset>) { banks = banks.filter { assets.contains($0.key) } }

    public func withRoutes<T>(for project: Project, _ body: (UnsafePointer<OpaquePointer?>?, UnsafePointer<OpaquePointer?>?) throws -> T) throws -> T {
        func lookup(_ asset: SampleAsset?) throws -> OpaquePointer? {
            guard let asset else { return nil }
            guard let bank = banks[asset] else { throw SampleError.unavailable }
            return bank.pointer
        }
        let tracks = try (0..<8).map { index in
            try lookup(project.tracks.indices.contains(index) ? project.tracks[index].instrumentSample : nil)
        }
        let drum = project.tracks.first(where: { $0.role == .drums })
        let pads = try (0..<16).map { try lookup(drum?.padSamples?[$0]) }
        return try withExtendedLifetime(self) {
            try tracks.withUnsafeBufferPointer { t in
                try pads.withUnsafeBufferPointer { p in try body(t.baseAddress, p.baseAddress) }
            }
        }
    }
}
