import Foundation

/// The exact project and instruments used by preview, save, and offline export.
public struct PreparedTrackDraft: Sendable {
    public let project: Project
    public let assets: [String: Data]
    public let samples: SampleLibrary
    public let loops: Bool

    public var bundle: PortableProjectBundle { PortableProjectBundle(project: project, assets: assets) }

    public static func make(brief: TrackBrief, name: String, factoryDirectory: URL?, sourcePrompt: String = "") throws -> Self {
        try Task.checkCancellation()
        var project = try brief.makeProject(name: name, sourcePrompt: sourcePrompt)
        let assignments = brief.songForm.map { ExpressiveArrangement.instruments(form: $0, project: project) } ?? [:]
        let composedEnding = (brief.songForm?.arrangement ?? .groove) != .groove
        if composedEnding {
            guard !assignments.isEmpty else { throw SampleError.unavailable }
            project.hasComposedEnding = true
        }
        var library = SampleLibrary()
        var files: [String: Data] = [:]
        var loaded: [ArrangerTimbre: SampleAsset] = [:]
        for index in project.tracks.indices {
            guard let instrument = assignments[project.tracks[index].id] else { continue }
            try Task.checkCancellation()
            if loaded[instrument] == nil {
                let bytes = try instrument.sampleData(factoryDirectory: factoryDirectory)
                let asset = try SampleAsset(kind: .instrument, name: instrument.sampleName, bytes: bytes, ringsOut: instrument == .gong)
                library.insert(try PreparedSampleBank(asset: asset, data: bytes))
                files[asset.relativePath] = bytes
                loaded[instrument] = asset
            }
            project.tracks[index].instrumentSample = loaded[instrument]
        }
        try Task.checkCancellation()
        try project.validate()
        return Self(project: project, assets: files, samples: library, loops: !composedEnding)
    }
}

public extension ArrangerTimbre {
    var sampleName: String {
        switch self {
        case .piano: NSLocalizedString("Acoustic piano", comment: "Recorded instrument")
        case .flute: NSLocalizedString("Synth flute", comment: "Synthesized concert flute")
        case .bansuri: NSLocalizedString("Bansuri", comment: "Synthesized bamboo flute")
        case .gong: NSLocalizedString("Gong", comment: "Synthesized suspended gong")
        case .ambientPad: NSLocalizedString("Ambient pad", comment: "Sustained harmonic bed")
        }
    }

    func sampleData(factoryDirectory: URL?) throws -> Data {
        if self == .piano {
            guard let directory = factoryDirectory else { throw SampleError.unavailable }
            struct Manifest: Decodable { struct Record: Decodable { let sha256: String }; let piano: Record }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            let bytes = try Data(contentsOf: directory.appendingPathComponent("piano.lgpcm"), options: .mappedIfSafe)
            guard try AssetIntegrity.sha256(bytes) == manifest.piano.sha256 else { throw SampleError.invalid }
            return bytes
        }
        let rate = 32000
        let zones: [SamplePCM.Zone]
        switch self {
        case .flute, .bansuri:
            let pitches = self == .bansuri ? [52, 60, 67, 74, 81] : [60, 67, 74, 81, 88]
            zones = try pitches.map { try windZone(pitch: $0, rate: rate) }
        case .ambientPad: zones = try [45, 57, 69, 81].map { try padZone(pitch: $0, rate: rate) }
        case .gong: zones = [try gongZone(rate: rate)]
        case .piano: throw SampleError.invalid
        }
        return try SamplePCM(rate: rate, zones: zones).encode(kind: .instrument)
    }

    private func windZone(pitch: Int, rate: Int) throws -> SamplePCM.Zone {
        let bamboo = self == .bansuri
        let frequency = 440 * pow(2, Double(pitch - 69)/12)
        let cycles = frequency.rounded()
        let period = Int((cycles / frequency * Double(rate)).rounded())
        let length = period * 2
        var frames = [Int16]()
        frames.reserveCapacity(length)
        var noise = UInt32(pitch * 7)
        var air = 0.0
        // Store a repeatable, low-passed breath texture. Its attack is louder
        // and the brightness and vibrato settle before the sustain loop.
        var breath = [Double](repeating: 0, count: period)
        for frame in breath.indices {
            noise = noise &* 1664525 &+ 1013904223
            air = 0.72 * air + 0.28 * (2 * Double(noise) / Double(UInt32.max) - 1)
            breath[frame] = air
        }
        for frame in 0..<length {
            if frame.isMultiple(of: 4096) { try Task.checkCancellation() }
            let t = Double(frame)/Double(rate)
            let cycle = 2 * Double.pi * Double(frame) / Double(period)
            let breathDepth = bamboo ? 0.22 : 0.105
            let vibrato = sin(cycle * (bamboo ? 4 : 5)) * (bamboo ? 0.22 : 0.09)
            // Approach the center of the note with a brief bamboo pitch scoop.
            let scoop = bamboo ? 0.65 * exp(-16 * t) : 0
            let phase = cycle * cycles + vibrato * min(1, t*3) + scoop
            let second = (bamboo ? 0.13 : 0.22) * sin(2*phase)
            let third = (bamboo ? 0.22 : 0.07) * sin(3*phase)
            let tone = 0.79*sin(phase) + second + third
            let attack = 1 - exp(-t / (bamboo ? 0.064 : 0.035))
            let value = attack * (tone + breath[frame % period] * (breathDepth + 0.23 * exp(-21*t)))
            frames.append(Int16(clamping: Int((value * 14000).rounded())))
        }
        return .init(pitch: pitch, samples: frames, loopStart: period)
    }

    private func padZone(pitch: Int, rate: Int) throws -> SamplePCM.Zone {
        let frequency = 440 * pow(2, Double(pitch - 69)/12)
        let cycles = (2*frequency).rounded()
        let period = Int((cycles / frequency * Double(rate)).rounded())
        let length = 2 * period
        var frames = [Int16]()
        frames.reserveCapacity(length)
        for frame in 0..<length {
            if frame.isMultiple(of: 4096) { try Task.checkCancellation() }
            let phase = 2 * Double.pi * Double(frame) / Double(period)
            let carrier = cycles * phase
            let bloom = 0.67 + 0.33 * sin(phase)
            let fundamental = 0.53*sin(carrier + 0.22*sin(phase))
            let pair = 0.19*sin(carrier-phase+0.5) + 0.16*sin(carrier+phase-0.7)
            let sheen = bloom * (0.09*sin(2*carrier + phase) + 0.035*sin(3*carrier-phase))
            let attack = min(1, Double(frame) / (0.32*Double(rate)))
            let envelope = attack*attack*(3-2*attack)
            frames.append(Int16(clamping: Int(((fundamental+pair+sheen)*envelope*9200).rounded())))
        }
        return .init(pitch: pitch, samples: frames, loopStart: period)
    }

    private func gongZone(rate: Int) throws -> SamplePCM.Zone {
        // Inharmonic plate modes bloom at different rates, then decay at
        // different rates. The short bright strike disappears before the body.
        let modes: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (118, 0.36, 1.03), (169.9, 0.24, 1.25), (239, 0.18, 1.52),
            (320.4, 0.16, 1.82), (478.2, 0.14, 2.06), (652.3, 0.08, 2.54),
            (884, 0.06, 3.4), (1281, 0.04, 4.7)
        ]
        let length = rate * 5
        var frames = [Int16]()
        frames.reserveCapacity(length)
        for frame in 0..<length {
            if frame.isMultiple(of: 4096) { try Task.checkCancellation() }
            let t = Double(frame) / Double(rate)
            let excursion = 0.64 * (1 - exp(-5*t))
            var metal = 0.0
            for mode in modes {
                metal += mode.amplitude * exp(-mode.decay*t) * sin(2 * .pi * mode.frequency * t + excursion)
            }
            let envelope = (1-exp(-39*t)) * min(1, Double(length-1-frame)/1024)
            frames.append(Int16(clamping: Int((metal*envelope*21000).rounded())))
        }
        return .init(pitch: 60, samples: frames)
    }
}
