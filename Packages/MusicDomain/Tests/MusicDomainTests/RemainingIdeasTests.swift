import Foundation
import Testing
@testable import MusicDomain

/// The last 19 ideas of the 2026 waves.
struct ArpPatternTests {
    @Test func textAndKernelCodesRoundTrip() throws {
        let pattern = try #require(ArpPattern(name: "Mine", encoded: "1 3 - 2^1 1^2 4 - 1"))
        #expect(pattern.steps.count == 8)
        #expect(pattern.codes == [0, 2, -1, 1 + 16, 0 + 32, 3, -1, 0])
        #expect(pattern.encoded == "1 3 - 2^1 1^2 4 - 1")
        #expect(ArpPattern(name: "Mine", encoded: pattern.encoded) == pattern)
        #expect(ArpPattern(name: "Bad", encoded: "1 0") == nil, "Notes count from 1")
        #expect(ArpPattern(name: "Bad", encoded: "1^3") == nil, "At most two octaves up")
        #expect(ArpPattern(name: "Bad", encoded: "17") == nil)
        #expect(ArpPattern(name: "Bad", encoded: String(repeating: "1 ", count: 17)) == nil)
        #expect(ArpPattern(name: "Bad", encoded: "x") == nil)
        for preset in ArpPattern.presets {
            try preset.validate()
            #expect(ArpPattern.lengths.contains(preset.steps.count) && preset.plays, "\(preset.name)")
        }
    }

    @Test func editingCyclesNotesOctavesAndLength() throws {
        var pattern = try #require(ArpPattern(name: "Edit", encoded: "1 - - - - - - -"))
        pattern.toggle(step: 1, note: 2)
        #expect(pattern.steps[1] == .note(index: 2, octave: 0))
        pattern.cycleOctave(step: 1); pattern.cycleOctave(step: 1)
        #expect(pattern.steps[1] == .note(index: 2, octave: 2))
        pattern.cycleOctave(step: 1)
        #expect(pattern.steps[1] == .note(index: 2, octave: 0))
        pattern.toggle(step: 1, note: 0)
        #expect(pattern.steps[1] == .note(index: 0, octave: 0), "Another note replaces the step")
        pattern.toggle(step: 1, note: 0)
        #expect(pattern.steps[1] == .rest, "The same note makes a rest")
        pattern.cycleOctave(step: 1)
        #expect(pattern.steps[1] == .rest, "A rest has no octave")
        pattern.setLength(16)
        #expect(pattern.steps.count == 16 && Array(pattern.steps[8...]) == Array(pattern.steps[..<8]))
        pattern.setLength(8)
        #expect(pattern.steps.count == 8)
        pattern.setLength(12)
        #expect(pattern.steps.count == 8, "Only 8 or 16 steps")
    }

    @Test func libraryKeepsThePlayersPatterns() throws {
        var library = ArpPatternLibrary(stored: "")
        #expect(library.patterns.isEmpty && library.all.count == ArpPattern.presets.count)
        let mine = try #require(ArpPattern(name: "Night", encoded: "1 2 - 3 1^1 - 2 3"))
        let saved = library.save(mine)
        #expect(saved)
        let factory = library.save(ArpPattern(name: "Alberti", steps: mine.steps))
        #expect(!factory, "Factory names stay free")
        var renamed = mine; renamed.steps[0] = .rest
        let replaced = library.save(renamed)
        #expect(replaced && library.patterns.count == 1 && library.patterns[0].steps[0] == .rest)
        let restored = ArpPatternLibrary(stored: library.stored)
        #expect(restored == library)
        library.remove("Night")
        #expect(library.patterns.isEmpty)
        #expect(ArpPatternLibrary(stored: "not json").patterns.isEmpty)
    }
}

struct PadLayersTests {
    private func shot(_ value: Int16, frames: Int = 800, rate: Int = 32_000) -> SamplePCM {
        SamplePCM(rate: rate, zones: [SamplePCM.Zone(pitch: 60, samples: Array(repeating: value, count: frames))])
    }

    @Test func velocitySplitMirrorsTheKernel() {
        #expect(PadLayers.layer(velocity: 20, count: 3) == 0 && PadLayers.layer(velocity: 42, count: 3) == 0)
        #expect(PadLayers.layer(velocity: 43, count: 3) == 1 && PadLayers.layer(velocity: 84, count: 3) == 1)
        #expect(PadLayers.layer(velocity: 86, count: 3) == 2 && PadLayers.layer(velocity: 127, count: 3) == 2)
        #expect(PadLayers.layer(velocity: 127, count: 1) == 0 && PadLayers.layer(velocity: 0, count: 4) == 0)
    }

    @Test func layersAreStoredAsOneLayeredOneShot() throws {
        let combined = try PadLayers.combine([shot(1000), shot(2000, rate: 16_000), shot(3000)])
        #expect(combined.rate == 32_000 && combined.zones.map(\.pitch) == [0, 1, 2])
        #expect(combined.zones[1].samples.count == 1600, "Resampled to the first layer's rate")
        let data = try combined.encode(kind: .oneShot, layered: true)
        let asset = try SampleAsset(kind: .oneShot, name: PadLayers.name(["Dusty · Kick", "Coast · Kick", "Rock · Kick"]), bytes: data, layers: .roundRobin)
        let decoded = try SamplePCM.decode(data, asset: asset)
        #expect(decoded.zones.count == 3 && decoded.zones[2].samples.first == 3000)
        #expect(asset.name.hasSuffix("Kick + Kick + Kick"))
        // The same bytes are not a plain one-shot, and plain one-shots stay single.
        let plain = try SampleAsset(kind: .oneShot, name: "Plain", bytes: data)
        #expect(throws: SampleError.self) { try SamplePCM.decode(data, asset: plain) }
        #expect(throws: SampleError.self) { try combined.encode(kind: .oneShot) }
        #expect(throws: SampleError.self) { try PadLayers.combine([shot(1)]) }
        #expect(throws: SampleError.self) { try PadLayers.combine(Array(repeating: shot(1), count: 5)) }
        #expect(throws: MusicError.self) { try SampleAsset(kind: .instrument, name: "Bad", bytes: data, layers: .velocity) }
        // Older assets without the field decode unchanged.
        let json = try JSONEncoder().encode(plain)
        #expect(try JSONDecoder().decode(SampleAsset.self, from: json).layers == nil)
    }

    @Test func aLayeredPadValidatesInAProject() throws {
        var project = Project.demo()
        let data = try PadLayers.combine([shot(500), shot(900)]).encode(kind: .oneShot, layered: true)
        let asset = try SampleAsset(kind: .oneShot, name: "Layers · Kick + Kick", bytes: data, layers: .velocity)
        let drums = try #require(project.tracks.firstIndex { $0.role == .drums })
        try project.tracks[drums].setPadSample(asset, pad: 0, edit: nil)
        try project.validate()
        #expect(project.referencedSamples.contains(asset))
    }
}
