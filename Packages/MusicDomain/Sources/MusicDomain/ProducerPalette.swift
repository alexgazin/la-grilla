import Foundation

/// Build 46: a palette is a versioned description of a producer's sound —
/// role assignments, timbre parameters, relative balance and effects — that is
/// applied to the parts already written. Notes, velocities, tempo and the
/// master level never change; only sounds, EQ, track balance and (for the
/// atmospheric palette) the master delay amount.
///
/// Every drum sound comes from the app's own on-device FactoryDrumKit
/// generator, and every melodic timbre is a built-in synthesized palette.
/// No downloaded sample is used, so there is no third-party rights question
/// and portable projects carry the kit as ordinary one-shot assets.
public struct ProducerPalette: Codable, Equatable, Sendable, Identifiable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case boomBap, westCoast, atmosphericChillhop
        public var title: String {
            switch self { case .boomBap: "Boom bap"; case .westCoast: "West Coast"; case .atmosphericChillhop: "Atmospheric chillhop" }
        }
        public var brief: String {
            switch self {
            case .boomBap: "Short kick, dry snare, soft hats, dense bass and keys with a clear attack."
            case .westCoast: "Deep kick, clear clap, brighter top, springy bass and room for the melody."
            case .atmosphericChillhop: "Soft keys, short drums, round bass and an airy lead with a gentle delay."
            }
        }
    }
    /// Which part of the arrangement a track plays.
    public enum Slot: String, Codable, CaseIterable, Sendable { case drums, chords, bass, lead }

    public struct Voice: Codable, Equatable, Sendable {
        public var slot: Slot
        public var sound: Int          // SoundPalette raw value
        public var equalizer: StudioEQ
        /// Level relative to the drums, in dB.
        public var balanceDB: Double
    }

    public static let currentVersion = 1
    public var style: Style
    public var version: Int
    public var drumKit: FactoryDrumKit
    public var voices: [Voice]
    /// Master delay amount for this palette, or nil to leave the musician's setting.
    public var masterDelayWet: Double?
    public var id: String { "\(style.rawValue)-v\(version)" }

    public func voice(_ slot: Slot) -> Voice? { voices.first { $0.slot == slot } }

    static func eq(_ a: EQBand, _ b: EQBand, _ c: EQBand, _ d: EQBand) -> StudioEQ {
        var e = StudioEQ(); e.bands = [a, b, c, d]; return e
    }

    public static func make(_ style: Style) -> ProducerPalette {
        switch style {
        case .boomBap:
            return ProducerPalette(style: style, version: currentVersion, drumKit: .dusty, voices: [
                Voice(slot: .drums, sound: SoundPalette.classic.rawValue, equalizer: eq(EQBand(.lowShelf, 80, 2), EQBand(.bell, 420, -1.5, 1), EQBand(.bell, 2500, 1.5, 1.2), EQBand(.highShelf, 9000, -2.5)), balanceDB: 0),
                Voice(slot: .chords, sound: SoundPalette.bright.rawValue, equalizer: eq(EQBand(.lowShelf, 140, -3), EQBand(.bell, 420, -1, 1), EQBand(.bell, 2500, 1.5, 1), EQBand(.highShelf, 9000, 0)), balanceDB: -2),
                Voice(slot: .bass, sound: SoundPalette.warm.rawValue, equalizer: eq(EQBand(.lowShelf, 90, 2.5), EQBand(.bell, 420, -1, 1), EQBand(.bell, 2500, 0, 1), EQBand(.highShelf, 9000, -3)), balanceDB: 0.5),
                Voice(slot: .lead, sound: SoundPalette.classic.rawValue, equalizer: eq(EQBand(.lowShelf, 160, -4), EQBand(.bell, 420, 0, 1), EQBand(.bell, 2500, 1, 1), EQBand(.highShelf, 9000, 0)), balanceDB: -3),
            ], masterDelayWet: nil)
        case .westCoast:
            return ProducerPalette(style: style, version: currentVersion, drumKit: .coast, voices: [
                Voice(slot: .drums, sound: SoundPalette.classic.rawValue, equalizer: eq(EQBand(.lowShelf, 60, 3), EQBand(.bell, 420, -1, 1), EQBand(.bell, 2500, 1.5, 1), EQBand(.highShelf, 9000, 2.5)), balanceDB: 0),
                Voice(slot: .chords, sound: SoundPalette.warm.rawValue, equalizer: eq(EQBand(.highPass, 180, 0, 0.707), EQBand(.bell, 420, -1.5, 1), EQBand(.bell, 2500, 0, 1), EQBand(.highShelf, 9000, 1)), balanceDB: -4),
                Voice(slot: .bass, sound: SoundPalette.classic.rawValue, equalizer: eq(EQBand(.lowShelf, 100, 1.5), EQBand(.bell, 420, -2, 1), EQBand(.bell, 2500, 2, 1.4), EQBand(.highShelf, 9000, 0)), balanceDB: 0),
                Voice(slot: .lead, sound: SoundPalette.bright.rawValue, equalizer: eq(EQBand(.lowShelf, 200, -4), EQBand(.bell, 420, 0, 1), EQBand(.bell, 2500, 3, 1), EQBand(.highShelf, 9000, 2)), balanceDB: -1),
            ], masterDelayWet: nil)
        case .atmosphericChillhop:
            return ProducerPalette(style: style, version: currentVersion, drumKit: .pocket, voices: [
                Voice(slot: .drums, sound: SoundPalette.warm.rawValue, equalizer: eq(EQBand(.lowShelf, 100, 0), EQBand(.bell, 420, -2, 1), EQBand(.bell, 2500, -1.5, 1), EQBand(.highShelf, 9000, -4)), balanceDB: 0),
                Voice(slot: .chords, sound: SoundPalette.warm.rawValue, equalizer: eq(EQBand(.lowShelf, 120, -2), EQBand(.bell, 420, 0, 1), EQBand(.bell, 2500, -2, 1), EQBand(.lowPass, 6000, 0, 0.707)), balanceDB: -1.5),
                Voice(slot: .bass, sound: SoundPalette.warm.rawValue, equalizer: eq(EQBand(.lowShelf, 80, 1.5), EQBand(.bell, 420, -1, 1), EQBand(.bell, 2500, -3, 1), EQBand(.lowPass, 2500, 0, 0.707)), balanceDB: 0.5),
                Voice(slot: .lead, sound: SoundPalette.bright.rawValue, equalizer: eq(EQBand(.lowShelf, 250, -5), EQBand(.bell, 420, 0, 1), EQBand(.bell, 2500, 0, 1), EQBand(.highShelf, 10000, 3)), balanceDB: -3),
            ], masterDelayWet: 0.18)
        }
    }

    public static var all: [ProducerPalette] { Style.allCases.map(make) }
}

/// What applying a palette would change, shown before applying.
public struct PaletteChange: Equatable, Sendable {
    public var trackID: UUID
    public var slot: ProducerPalette.Slot
    public var soundBefore: Int, soundAfter: Int
    public var gainBefore: Double, gainAfter: Double
    public var replacesKit: Bool
}

public enum PaletteEngine {
    public static func slot(of track: Track) -> ProducerPalette.Slot {
        switch track.role {
        case .drums: return .drums
        case .harmony: return .chords
        case .bass: return .bass
        case .melody: return SongEditParser.isBassName(track.name) ? .bass : .lead
        }
    }

    /// Names given by the factory kit loader ("Dusty · Kick").
    static func isFactoryKitSound(_ name: String) -> Bool {
        let prefixes = ["Pocket · ", "Dusty · ", "Coast · ", NSLocalizedString("Pocket · %@", comment: "Pocket Kit sample").replacingOccurrences(of: "%@", with: "")]
        return prefixes.contains { !$0.isEmpty && name.hasPrefix($0) }
    }

    /// Tracks kept by default: the musician's own sounds (SoundFont or imported
    /// instrument, imported or edited pad samples) are not replaced unless chosen.
    public static func defaultKept(_ project: Project) -> Set<UUID> {
        Set(project.tracks.filter { track in
            track.instrumentSample != nil || !(track.padEdits ?? [:]).isEmpty
                || (track.padSamples ?? [:]).values.contains { !isFactoryKitSound($0.name) }
        }.map(\.id))
    }

    /// The palette's drum kit as one-shot assets with their bytes, in pad order.
    public static func kit(_ palette: ProducerPalette) throws -> [(pad: Int, asset: SampleAsset, data: Data)] {
        let prefix: String = switch palette.drumKit { case .pocket: "Pocket · "; case .dusty: "Dusty · "; case .coast: "Coast · " }
        return try Compiler.padNames.indices.map { pad in
            let pcm = SamplePCM(rate: FactoryDrumKit.sampleRate, zones: [.init(pitch: 60, samples: try palette.drumKit.sample(pad: pad))])
            let data = try pcm.encode(kind: .oneShot)
            let name = prefix + NSLocalizedString(Compiler.padNames[pad], comment: "Pad name")
            return (pad, try SampleAsset(kind: .oneShot, name: name, bytes: data), data)
        }
    }

    /// A candidate project with the palette applied; the source stays untouched.
    /// `gainOffsetDB` is the common loudness-matching offset for changed tracks.
    public static func candidate(_ project: Project, palette: ProducerPalette, keep: Set<UUID>,
                                 kit: [Int: SampleAsset], gainOffsetDB: Double = 0) throws -> Project {
        try project.validate()
        var result = project
        let reference = project.tracks.first { $0.role == .drums }?.gain ?? -6
        let drumsBalance = palette.voice(.drums)?.balanceDB ?? 0
        for index in result.tracks.indices where !keep.contains(result.tracks[index].id) {
            let slot = slot(of: result.tracks[index])
            guard let voice = palette.voice(slot) else { continue }
            result.tracks[index].presetVersion = voice.sound
            result.tracks[index].equalizer = voice.equalizer
            let target = reference + voice.balanceDB - drumsBalance + gainOffsetDB
            result.tracks[index].gain = min(6, max(-60, (target * 10).rounded() / 10))
            if slot == .drums && result.tracks[index].role == .drums {
                guard kit.count == 16 else { throw SampleError.invalid }
                result.tracks[index].padSamples = kit
                result.tracks[index].padEdits = nil
            }
        }
        if let delay = palette.masterDelayWet {
            var fx = result.masterFX ?? MasterFX()
            fx.delayWet = delay
            result.masterFX = fx
        }
        try result.validate()
        return result
    }

    public static func changes(from source: Project, to candidate: Project, keep: Set<UUID>) -> [PaletteChange] {
        source.tracks.compactMap { track in
            guard !keep.contains(track.id), let after = candidate.tracks.first(where: { $0.id == track.id }) else { return nil }
            return PaletteChange(trackID: track.id, slot: slot(of: track), soundBefore: track.presetVersion, soundAfter: after.presetVersion,
                                 gainBefore: track.gain, gainAfter: after.gain, replacesKit: track.padSamples != after.padSamples)
        }
    }

    /// Sounds a project refers to but the app cannot currently play, with the
    /// track (and pad) and how to get the sound back.
    public struct MissingSound: Equatable, Sendable {
        public var trackID: UUID
        public var pad: Int?
        public var name: String
        public var remedy: String
    }

    public static func missingSounds(_ project: Project, available: Set<SampleAsset>) -> [MissingSound] {
        var result: [MissingSound] = []
        for track in project.tracks {
            if let sample = track.instrumentSample, !available.contains(sample) {
                result.append(MissingSound(trackID: track.id, pad: nil, name: sample.name,
                                           remedy: NSLocalizedString("Import the instrument again in Sounds, or choose a built-in sound for this track.", comment: "Missing sound")))
            }
            for (pad, sample) in (track.padSamples ?? [:]).sorted(by: { $0.key < $1.key }) where !available.contains(sample) {
                let remedy = isFactoryKitSound(sample.name)
                    ? NSLocalizedString("Load the factory kit again in Sounds.", comment: "Missing sound")
                    : NSLocalizedString("Import the sample again on this pad, or load one of your saved kits.", comment: "Missing sound")
                result.append(MissingSound(trackID: track.id, pad: pad, name: sample.name, remedy: remedy))
            }
        }
        return result
    }
}

/// Loudness-matched palette candidates. The source and each palette are
/// rendered offline over the same passage with the same notes, velocities and
/// start; changed tracks receive one common gain offset so the candidate lands
/// within `tolerance` LU of the source. The master level is never touched.
public enum PaletteAudition {
    public struct Result: Sendable {
        public var candidate: Project
        public var source: LoudnessMeter.Measurement
        public var palette: LoudnessMeter.Measurement
        public var gainOffsetDB: Double
        public var differenceLU: Double { palette.integratedLUFS - source.integratedLUFS }
    }

    public static func library(_ base: SampleLibrary, kit: [(pad: Int, asset: SampleAsset, data: Data)]) throws -> SampleLibrary {
        var library = base
        for sound in kit { library.insert(try PreparedSampleBank(asset: sound.asset, data: sound.data)) }
        return library
    }

    public static func loudness(_ project: Project, range: Range<Int>, samples: SampleLibrary, tailSeconds: Double = 0) async throws -> LoudnessMeter.Measurement {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("palette-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await OfflineRenderer.render(project, to: url, settings: WAVSettings(sampleRate: 48_000, bitDepth: 24, tailSeconds: tailSeconds, dither: false), range: range, samples: samples)
        let (channels, rate) = try LoudnessMeter.readWAV(url)
        return LoudnessMeter.measure(channels: channels, rate: rate)
    }

    public static func matched(_ project: Project, palette: ProducerPalette, keep: Set<UUID>,
                               kit: [(pad: Int, asset: SampleAsset, data: Data)], range: Range<Int>,
                               samples: SampleLibrary, tolerance: Double = 0.5) async throws -> Result {
        let assets = Dictionary(uniqueKeysWithValues: kit.map { ($0.pad, $0.asset) })
        let library = try library(samples, kit: kit)
        let source = try await loudness(project, range: range, samples: samples)
        var offset = 0.0
        var candidate = try PaletteEngine.candidate(project, palette: palette, keep: keep, kit: assets, gainOffsetDB: offset)
        var measured = try await loudness(candidate, range: range, samples: library)
        for _ in 0..<4 where source.integratedLUFS.isFinite && measured.integratedLUFS.isFinite && abs(measured.integratedLUFS - source.integratedLUFS) > tolerance {
            offset += source.integratedLUFS - measured.integratedLUFS
            offset = min(24, max(-24, offset))
            candidate = try PaletteEngine.candidate(project, palette: palette, keep: keep, kit: assets, gainOffsetDB: offset)
            measured = try await loudness(candidate, range: range, samples: library)
        }
        return Result(candidate: candidate, source: source, palette: measured, gainOffsetDB: offset)
    }
}

extension FactoryDrumKit: Codable {}
