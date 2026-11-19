import Foundation
import Testing
@testable import MusicDomain

/// Build 46 listening material made entirely in La Grilla: one short finished
/// instrumental per palette, a common A/B on the identical phrase, and the
/// mix-versus-stems comparison. Files are written only when
/// GRILLA_PALETTE_MEDIA names a folder; the checks always run.
struct PaletteMediaTests {
    static let briefs: [(ProducerPalette.Style, String)] = [
        (.boomBap, "Make a boom bap beat, 90 bpm, D minor, 8 bars, chords: Dm7 Gm7 Bbmaj7 A7"),
        (.westCoast, "Make a West Coast beat, 94 bpm, G minor, 8 bars, chords: Gm Eb Cm D7"),
        (.atmosphericChillhop, "Make a chillhop beat at 84 bpm, E minor, 8 bars, laid back keys, chords: Em9 Cmaj7 Am7 B7"),
    ]

    static func render(_ project: Project, _ url: URL, samples: SampleLibrary, range: Range<Int>? = nil, isolated: UUID? = nil, tail: Double = 3) async throws -> [[Float]] {
        _ = try await OfflineRenderer.render(project, to: url, settings: WAVSettings(sampleRate: 48_000, bitDepth: 24, tailSeconds: tail, dither: false), range: range, isolatedTrack: isolated, samples: samples)
        return try LoudnessMeter.readWAV(url).channels
    }

    @Test func instrumentalsABAndStemsForEveryPalette() async throws {
        let output = ProcessInfo.processInfo.environment["GRILLA_PALETTE_MEDIA"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("palette-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var report: [[String: Any]] = []
        // Common A/B: the identical four-bar chorus phrase of the walkthrough project.
        let phrase = try SongEditDemo.project(name: "Palette phrase")
        let chorus = phrase.sections[2]
        let phraseRange = chorus.start..<(chorus.start + chorus.length)
        if let output { _ = try await Self.render(phrase, output.appendingPathComponent("ab-source.wav"), samples: SampleLibrary(), range: phraseRange, tail: 1.5) }
        for (style, prompt) in Self.briefs {
            let palette = ProducerPalette.make(style)
            let kit = try PaletteEngine.kit(palette)
            let library = try PaletteAudition.library(SampleLibrary(), kit: kit)
            // 1. Same phrase in this palette, loudness-matched to the source.
            let ab = try await PaletteAudition.matched(phrase, palette: palette, keep: [], kit: kit, range: phraseRange, samples: SampleLibrary())
            #expect(abs(ab.differenceLU) <= 1)
            #expect(Compiler.notes(ab.candidate) == Compiler.notes(phrase))
            if let output { _ = try await Self.render(ab.candidate, output.appendingPathComponent("ab-\(style.rawValue).wav"), samples: library, range: phraseRange, tail: 1.5) }
            // 2. A finished instrumental created in La Grilla, then given the palette.
            let brief = try #require(try TrackBrief.offlineCreationRequest(prompt))
            let song = try brief.makeProject(name: "Palette \(style.title)", sourcePrompt: prompt)
            let whole = 0..<song.length
            let matched = try await PaletteAudition.matched(song, palette: palette, keep: PaletteEngine.defaultKept(song), kit: kit, range: whole, samples: SampleLibrary())
            let result = matched.candidate
            #expect(Compiler.notes(result) == Compiler.notes(song))
            let mixURL = scratch.appendingPathComponent("\(style.rawValue).wav")
            let mix = try await Self.render(result, mixURL, samples: library)
            let level = LoudnessMeter.measure(channels: mix, rate: 48_000)
            #expect(level.samplePeak < 1, "\(style) clips")
            // 3. Stems: the isolated tracks sum to the mix before master gain and master effects.
            var sum = [Float](repeating: 0, count: mix[0].count)
            for track in result.tracks {
                let stem = try await Self.render(result, scratch.appendingPathComponent("\(style.rawValue)-\(track.id).wav"), samples: library, isolated: track.id)
                for i in sum.indices where i < stem[0].count { sum[i] += stem[0][i] }
            }
            let master = Float(pow(10, result.master / 20))
            var residual = 0.0, energy = 0.0
            for i in sum.indices { let d = Double(mix[0][i] - sum[i] * master); residual += d * d; energy += Double(mix[0][i]) * Double(mix[0][i]) }
            let residualDB = residual > 0 && energy > 0 ? 10 * log10(residual / energy) : -200
            if palette.masterDelayWet == nil { #expect(residualDB < -40, "\(style): stems differ from the mix by \(residualDB) dB") }
            if let output {
                try FileManager.default.copyItem(at: mixURL, to: output.appendingPathComponent("\(style.rawValue)-instrumental.wav"))
                let assets = Dictionary(uniqueKeysWithValues: kit.map { ($0.asset.relativePath, $0.data) })
                let used = Set(result.referencedSamples.map(\.relativePath))
                try PortableProject.data(result, assets: assets.filter { used.contains($0.key) }).write(to: output.appendingPathComponent("\(style.rawValue).grillapack"))
                try MIDIExporter.data(result).write(to: output.appendingPathComponent("\(style.rawValue).mid"))
            }
            let notes = Compiler.notes(result)
            report.append([
                "palette": style.title, "paletteID": palette.id, "drumKit": palette.drumKit.rawValue,
                "prompt": prompt, "bpm": result.bpm, "key": result.keyName, "bars": result.length / barTicks,
                "abSourceLUFS": ab.source.integratedLUFS, "abPaletteLUFS": ab.palette.integratedLUFS, "abDifferenceLU": ab.differenceLU,
                "abPeakDBFS": ab.palette.samplePeakDBFS, "abGainOffsetDB": ab.gainOffsetDB,
                "instrumentalSourceLUFS": matched.source.integratedLUFS, "instrumentalLUFS": level.integratedLUFS,
                "instrumentalPeakDBFS": level.samplePeakDBFS, "instrumentalGainOffsetDB": matched.gainOffsetDB,
                "stemsVersusMixResidualDB": residualDB, "masterDelayWet": result.masterFX?.delayWet ?? 0,
                "midiNotes": notes.count,
                "dawInstruments": result.tracks.map { track in "\(track.displayName): \(PaletteEngine.slot(of: track).rawValue) — \(track.role == .drums ? "GM drum map (channel 10)" : "assign a \(PaletteEngine.slot(of: track) == .bass ? "bass" : PaletteEngine.slot(of: track) == .chords ? "keys/pad" : "lead") instrument")" },
            ])
        }
        if let output {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("palettes.json"))
        }
    }
}
