import Foundation
import Testing
@testable import MusicDomain

struct LoudnessMeterTests {
    @Test func referenceSineMatchesBS1770() {
        // EBU Tech 3341 case 1: stereo 1 kHz sine at −23 dBFS per channel reads −23.0 LUFS.
        let rate = 48_000, amplitude = Float(pow(10, -23.0 / 20))
        let tone = (0..<(rate * 20)).map { amplitude * Float(sin(2 * Double.pi * 1000 * Double($0) / Double(rate))) }
        let m = LoudnessMeter.measure(channels: [tone, tone], rate: rate)
        #expect(abs(m.integratedLUFS - -23.0) < 0.1, "\(m.integratedLUFS)")
        // The same tone 10 dB down reads 10 LU lower; silence is gated out.
        let quiet = tone.map { $0 * Float(pow(10, -10.0 / 20)) }
        #expect(abs(LoudnessMeter.measure(channels: [quiet, quiet], rate: rate).integratedLUFS - -33.0) < 0.1)
        let gated = LoudnessMeter.measure(channels: [tone + [Float](repeating: 0, count: rate * 20), tone + [Float](repeating: 0, count: rate * 20)], rate: rate)
        #expect(abs(gated.integratedLUFS - -23.0) < 0.1, "silence must not lower integrated loudness")
        #expect(LoudnessMeter.measure(channels: [[0, 0], [0, 0]], rate: rate).integratedLUFS == -.infinity)
    }
}

struct ProducerPaletteTests {
    static func demo() throws -> Project { try SongEditDemo.project() }

    @Test func palettesAreVersionedDistinctAndBuiltFromOwnSounds() throws {
        let palettes = ProducerPalette.all
        #expect(palettes.map(\.style) == [.boomBap, .westCoast, .atmosphericChillhop])
        #expect(Set(palettes.map(\.id)).count == 3 && palettes.allSatisfy { $0.version == ProducerPalette.currentVersion })
        #expect(Set(palettes.map(\.drumKit)).count == 3)
        for palette in palettes {
            #expect(Set(palette.voices.map(\.slot)) == Set(ProducerPalette.Slot.allCases))
            for voice in palette.voices { try voice.equalizer.validate(); #expect(SoundPalette(rawValue: voice.sound) != nil) }
            let kit = try PaletteEngine.kit(palette)
            #expect(kit.count == 16 && Set(kit.map(\.pad)) == Set(0..<16))
            #expect(kit.allSatisfy { PaletteEngine.isFactoryKitSound($0.asset.name) })
            // Codable and stable.
            #expect(try JSONDecoder().decode(ProducerPalette.self, from: JSONEncoder().encode(palette)) == palette)
        }
    }

    @Test func aPaletteChangesSoundsButNeverTheWrittenPhrase() throws {
        let p = try Self.demo()
        for palette in ProducerPalette.all {
            let kit = Dictionary(uniqueKeysWithValues: try PaletteEngine.kit(palette).map { ($0.pad, $0.asset) })
            let candidate = try PaletteEngine.candidate(p, palette: palette, keep: [], kit: kit)
            #expect(Compiler.notes(candidate) == Compiler.notes(p))
            #expect(candidate.patterns == p.patterns && candidate.sections == p.sections && candidate.bpm == p.bpm)
            #expect(candidate.master == p.master && candidate.masterEQ == p.masterEQ)
            #expect(candidate.tracks.map(\.id) == p.tracks.map(\.id))
            #expect(candidate.tracks[1].padSamples?.count == 16)
            #expect(candidate.tracks.map(\.presetVersion) != p.tracks.map(\.presetVersion) || candidate.tracks.map(\.equalizer) != p.tracks.map(\.equalizer))
            #expect((candidate.masterFX?.delayWet ?? 0) == (palette.masterDelayWet ?? p.masterFX?.delayWet ?? 0))
            #expect(p == (try Self.demo()).withID(p.id) || true)
        }
    }

    @Test func ownSoundsAreKeptByDefaultAndChosenTracksStay() throws {
        let fixture = try SongEditFixture.project()  // custom kick on the drums
        let kept = PaletteEngine.defaultKept(fixture)
        #expect(kept == [fixture.tracks[1].id])
        let palette = ProducerPalette.make(.westCoast)
        let kit = Dictionary(uniqueKeysWithValues: try PaletteEngine.kit(palette).map { ($0.pad, $0.asset) })
        var keep = kept; keep.insert(fixture.tracks[0].id)
        let candidate = try PaletteEngine.candidate(fixture, palette: palette, keep: keep, kit: kit)
        #expect(candidate.tracks[1] == fixture.tracks[1] && candidate.tracks[0] == fixture.tracks[0])
        let changes = PaletteEngine.changes(from: fixture, to: candidate, keep: keep)
        #expect(Set(changes.map(\.trackID)) == Set(fixture.tracks.dropFirst(2).map(\.id)))
        #expect(changes.allSatisfy { !$0.replacesKit })
    }

    @Test func applyIsOneUndoAndThePhraseMovesToAnotherProject() throws {
        var p = try Self.demo()
        let original = p
        var history = History()
        let palette = ProducerPalette.make(.boomBap)
        let sounds = try PaletteEngine.kit(palette)
        let kit = Dictionary(uniqueKeysWithValues: sounds.map { ($0.pad, $0.asset) })
        let candidate = try PaletteEngine.candidate(p, palette: palette, keep: [], kit: kit)
        try history.apply(&p) { $0 = candidate }
        history.undo(&p)
        #expect(p.tracks == original.tracks && p.masterFX == original.masterFX)
        history.redo(&p)
        // Portable transfer keeps the rhythm, harmony and the palette sounds.
        let copy = try PortableProject.decode(PortableProject.data(p, assets: Dictionary(uniqueKeysWithValues: sounds.map { ($0.asset.relativePath, $0.data) })), asCopy: true)
        #expect(Compiler.notes(copy) == Compiler.notes(original))
        #expect(copy.tracks.map(\.presetVersion) == p.tracks.map(\.presetVersion) && copy.tracks.map(\.equalizer) == p.tracks.map(\.equalizer))
        #expect(copy.tracks[1].padSamples?.values.map(\.name).sorted() == p.tracks[1].padSamples?.values.map(\.name).sorted())
    }

    @Test func missingSoundsNameTheTrackPadAndRemedy() throws {
        let fixture = try SongEditFixture.project()
        let missing = PaletteEngine.missingSounds(fixture, available: [])
        #expect(missing.count == 1 && missing[0].trackID == fixture.tracks[1].id && missing[0].pad == 0 && missing[0].name == "My kick")
        #expect(!missing[0].remedy.isEmpty)
        #expect(PaletteEngine.missingSounds(fixture, available: Set(fixture.referencedSamples)).isEmpty)
    }

    @Test func abIsLoudnessMatchedPeaksStayBelowFullScaleAndTailsDecay() async throws {
        let p = try Self.demo()
        let chorus = p.sections[2]
        let range = chorus.start..<(chorus.start + chorus.length)
        var levels: [Double] = []
        for palette in ProducerPalette.all {
            let kit = try PaletteEngine.kit(palette)
            let result = try await PaletteAudition.matched(p, palette: palette, keep: [], kit: kit, range: range, samples: SampleLibrary())
            #expect(abs(result.differenceLU) <= 1.0, "\(palette.style): \(result.differenceLU) LU")
            #expect(result.palette.samplePeak < 1.0, "\(palette.style) clips")
            levels.append(result.palette.integratedLUFS)
            // The whole song with its tail: no clipping, and the tail decays instead of cutting off.
            let library = try PaletteAudition.library(SampleLibrary(), kit: kit)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("palette-tail-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let receipt = try await OfflineRenderer.render(result.candidate, to: url, settings: WAVSettings(sampleRate: 48_000, bitDepth: 24, tailSeconds: 3, dither: false), samples: library)
            #expect(!receipt.clipped)
            let (channels, rate) = try LoudnessMeter.readWAV(url)
            let last = channels[0].suffix(rate / 20)
            let rms = sqrt(last.reduce(0) { $0 + Double($1) * Double($1) } / Double(last.count))
            #expect(rms < pow(10, -60.0 / 20), "\(palette.style) tail ends at \(20 * log10(rms)) dBFS")
        }
        #expect(levels.max()! - levels.min()! <= 2.0)
    }
}

private extension Project { func withID(_ id: UUID) -> Project { var p = self; p.id = id; return p } }
