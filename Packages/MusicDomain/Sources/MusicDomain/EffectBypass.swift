import Foundation

/// U55 · "Before / after" for an effect at matched loudness: the version without the effect is
/// turned up or down until it is as loud as the processed one, so the comparison is about tone,
/// not level. The processed sound is never changed.
public enum EffectBypass {
    public enum Target: Equatable, Sendable {
        case trackEQ(UUID)
        case masterEQ
        case trackDrive(UUID)
    }

    public struct Comparison: Sendable {
        /// The song without the effect, level-compensated.
        public var bypassed: Project
        public var offsetDB: Double
        public var processed: LoudnessMeter.Measurement
        public var plain: LoudnessMeter.Measurement
        public var differenceLU: Double { plain.integratedLUFS - processed.integratedLUFS }
    }

    /// The song without the effect, `offsetDB` louder (on that track, or on the master for the master EQ).
    public static func bypassed(_ project: Project, target: Target, offsetDB: Double = 0) throws -> Project {
        var result = project
        switch target {
        case let .trackEQ(id):
            guard let index = result.tracks.firstIndex(where: { $0.id == id }) else { throw MusicError.invalidProject }
            result.tracks[index].equalizer?.enabled = false
            result.tracks[index].gain = min(6, max(-61, result.tracks[index].gain + offsetDB))
        case let .trackDrive(id):
            guard let index = result.tracks.firstIndex(where: { $0.id == id }) else { throw MusicError.invalidProject }
            if var dynamics = result.tracks[index].dynamics { dynamics.drive = 0; result.tracks[index].dynamics = dynamics }
            result.tracks[index].gain = min(6, max(-61, result.tracks[index].gain + offsetDB))
        case .masterEQ:
            result.masterEQ?.enabled = false
            result.master = min(6, max(-61, result.master + offsetDB))
        }
        try result.validate()
        return result
    }

    /// Measures both versions on `range` and compensates the plain one to within `tolerance` LU.
    public static func matched(_ project: Project, target: Target, range: Range<Int>, samples: SampleLibrary,
                               tolerance: Double = 0.5) async throws -> Comparison {
        let processed = try await PaletteAudition.loudness(project, range: range, samples: samples)
        var offset = 0.0
        var candidate = try bypassed(project, target: target)
        var plain = try await PaletteAudition.loudness(candidate, range: range, samples: samples)
        for _ in 0..<4 where processed.integratedLUFS.isFinite && plain.integratedLUFS.isFinite && abs(plain.integratedLUFS - processed.integratedLUFS) > tolerance {
            offset = min(24, max(-24, offset + processed.integratedLUFS - plain.integratedLUFS))
            candidate = try bypassed(project, target: target, offsetDB: offset)
            plain = try await PaletteAudition.loudness(candidate, range: range, samples: samples)
        }
        return Comparison(bypassed: candidate, offsetDB: offset, processed: processed, plain: plain)
    }
}
