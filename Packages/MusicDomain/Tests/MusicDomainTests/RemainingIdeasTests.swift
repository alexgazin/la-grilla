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

struct TrackAutomationTests {
    @Test func valuesInterpolateLikeTheKernel() throws {
        let lane = AutomationLane(parameter: .level, points: [.init(tick: 0, value: 0), .init(tick: 1920, value: -20)])
        try lane.validate()
        #expect(lane.value(at: -5) == 0 && lane.value(at: 960) == -10 && lane.value(at: 5000) == -20)
        #expect(throws: MusicError.self) { try AutomationLane(parameter: .pan, points: [.init(tick: 0, value: 2)]).validate() }
        #expect(throws: MusicError.self) { try AutomationLane(parameter: .level, points: [.init(tick: 9, value: 0), .init(tick: 9, value: 1)]).validate() }
        #expect(throws: MusicError.self) { try AutomationLane(parameter: .level, points: []).validate() }
    }

    @Test func aRecordedPassIsThinnedAndReplacesOnlyItsRange() throws {
        // A fader pulled smoothly down over two bars, sampled every 20 ticks.
        let samples = stride(from: 0, through: 3840, by: 20).map { (tick: $0, value: -Double($0) / 192) }
        let lane = try #require(AutomationEditing.record(samples, parameter: .level, into: nil))
        try lane.validate()
        #expect(lane.points.count == 2, "A straight movement needs only its ends")
        #expect(lane.points.first?.value == 0 && lane.points.last?.value == -20)
        // A second pass over bar 2 keeps bar 1.
        let punch = stride(from: 1920, through: 3840, by: 40).map { (tick: $0, value: $0 < 2880 ? -3.0 : -9.0) }
        let merged = try #require(AutomationEditing.record(punch, parameter: .level, into: lane))
        try merged.validate()
        #expect(merged.points.first == .init(tick: 0, value: 0))
        #expect(merged.value(at: 2400) == -3 && merged.value(at: 3840) == -9)
        // A wild movement still fits in 64 points.
        let wild = (0..<2000).map { (tick: $0 * 3, value: $0 % 2 == 0 ? -40.0 : 0.0) }
        let busy = try #require(AutomationEditing.record(wild, parameter: .level, into: nil))
        #expect(busy.points.count <= AutomationLane.maxPoints)
        try busy.validate()
    }

    @Test func pointsEditAndFollowTheirSections() throws {
        var lane = AutomationLane(parameter: .pan, points: [.init(tick: 0, value: -1)])
        #expect(AutomationEditing.set(&lane, tick: 960, value: 3) && lane.points.last?.value == 1)
        AutomationEditing.move(&lane, index: 1, tick: -50, value: 0.5)
        #expect(lane.points[1].tick == 1, "A point cannot pass its neighbour")
        var project = Project.demo()
        project.sections = [Section(name: "A", start: 0, length: barTicks), Section(name: "B", start: barTicks, length: barTicks)]
        project.tracks[0].automation = [AutomationLane(parameter: .level, points: [.init(tick: 100, value: -3), .init(tick: barTicks + 100, value: -12)])]
        let before = project
        var after = project
        var first = project.sections[1], second = project.sections[0]
        first.start = 0; second.start = barTicks
        after.sections = [first, second]
        AutomationEditing.remap(from: before, to: &after)
        #expect(after.tracks[0].automation?.first?.points == [.init(tick: 100, value: -12), .init(tick: barTicks + 100, value: -3)])
    }

    @Test func aProjectWithLanesValidatesAndRoundTrips() throws {
        var project = Project.demo()
        project.tracks[0].automation = [AutomationLane(parameter: .level, points: [.init(tick: 0, value: -6)]),
                                        AutomationLane(parameter: .pan, points: [.init(tick: 0, value: 0.5)])]
        try project.validate()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.tracks[0].automation == project.tracks[0].automation)
        project.tracks[0].automation?.append(AutomationLane(parameter: .pan, points: [.init(tick: 0, value: 0)]))
        #expect(throws: MusicError.self) { try project.validate() }
    }
}

struct ReverbSpaceTests {
    @Test func theSpaceIsSavedWithTheMasterAndOlderFilesKeepTheClassicRoom() throws {
        var project = Project.demo()
        project.masterFX = MasterFX(space: .hall)
        try project.validate()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.masterFX?.space == .hall)
        let legacy = try JSONDecoder().decode(MasterFX.self, from: Data(#"{"filter":0,"delayWet":0}"#.utf8))
        #expect(legacy.space == nil)
        #expect(ReverbSpace.allCases.map(\.rawValue) == [1, 2, 3, 4], "Kernel space numbers")
    }
}

struct MelodicSamplerTests {
    private func sine(_ frequency: Double, seconds: Double, rate: Double = 48_000, lead: Int = 4800) -> [Float] {
        [Float](repeating: 0, count: lead) + (0..<Int(seconds * rate)).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    @Test func soundIsTrimmedResampledAndItsPitchFound() throws {
        let raw = sine(220 * pow(2, 7.0 / 1200), seconds: 1.5)      // A3, 7 cents sharp, after silence
        let prepared = MelodicSampler.prepare(raw, rate: 48_000)
        #expect(abs(prepared.count - Int(1.5 * 32_000)) < 64, "Silence trimmed, resampled to 32 kHz")
        #expect(abs((prepared.map { abs($0) }.max() ?? 0) - 0.891) < 0.01)
        let root = try #require(MelodicSampler.detectRoot(prepared, rate: Double(MelodicSampler.rate)))
        #expect(root.pitch == 57 && abs(root.cents - 7) < 3)
        let long = MelodicSampler.prepare(sine(440, seconds: 12), rate: 48_000)
        #expect(long.count == Int(MelodicSampler.maxSeconds) * MelodicSampler.rate)
        #expect(MelodicSampler.prepare([Float](repeating: 0, count: 1000), rate: 48_000).isEmpty)
    }

    @Test func theInstrumentIsOneZoneAtItsRoot() throws {
        let prepared = MelodicSampler.prepare(sine(440, seconds: 2), rate: 48_000)
        let ringing = try MelodicSampler.instrument(prepared, root: 69, shape: .init(attack: 0.05, ringsOut: true))
        #expect(ringing.zones.count == 1 && ringing.zones[0].pitch == 69 && ringing.zones[0].loopStart == 0)
        #expect(ringing.zones[0].samples.prefix(10).allSatisfy { abs($0) < 300 }, "The fade-in starts silent")
        let held = try MelodicSampler.instrument(prepared, root: 69, shape: .init(attack: 0.005, ringsOut: false))
        let loop = held.zones[0].loopStart
        #expect(loop > 0 && loop <= held.zones[0].samples.count - 1024)
        let data = try held.encode(kind: .instrument)
        let asset = try SampleAsset(kind: .instrument, name: MelodicSampler.name(root: 69), bytes: data)
        #expect(asset.name.hasSuffix("A4"))
        #expect(try SamplePCM.decode(data, asset: asset).zones[0].loopStart == loop)
        let rings = try ringing.encode(kind: .instrument)
        _ = try SampleAsset(kind: .instrument, name: "Bell", bytes: rings, ringsOut: true)
        #expect(throws: SampleError.self) { try MelodicSampler.instrument([0.1, 0.2], root: 60, shape: .init()) }
    }
}

struct VoiceTreatmentTests {
    private func sine(_ frequency: Double, seconds: Double, rate: Int) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { Float(0.4 * sin(2 * Double.pi * frequency * Double($0) / Double(rate))) }
    }

    @Test func vocalPullsASharpNoteTowardItsSemitoneAndPodcastKeepsThePitch() throws {
        let rate = 32_000
        let sharp = sine(220 * pow(2, 30.0 / 1200), seconds: 1.5, rate: rate)        // A3 + 30 cents
        let vocal = VoiceTreatment.apply(sharp, rate: rate, preset: .vocal)
        let after = try #require(MelodicSampler.detectRoot(vocal, rate: Double(rate)))
        #expect(after.pitch == 57 && abs(after.cents - 9) < 4, "70 % of the way: about +9 cents left")
        let podcast = VoiceTreatment.apply(sharp, rate: rate, preset: .podcast)
        #expect(podcast.count == sharp.count)
        #expect(abs(try #require(MelodicSampler.detectRoot(podcast, rate: Double(rate))).cents - 30) < 4)
        #expect(podcast.map { abs($0) }.max()! <= 0.8913)
    }

    @Test func aPadEditCarriesItsVoicePreset() throws {
        let rate = 32_000
        let samples = sine(330, seconds: 0.8, rate: rate).map { Int16($0 * 32767) }
        let data = try SamplePCM(rate: rate, zones: [.init(pitch: 60, samples: samples)]).encode(kind: .oneShot)
        let source = try OneShotSource(asset: try SampleAsset(kind: .oneShot, name: "Voice", bytes: data), data: data)
        let plain = try source.render(source.initialEdit)
        var edit = source.initialEdit
        edit.voice = .warm
        let warm = try source.render(edit)
        #expect(warm.zones[0].samples.count == plain.zones[0].samples.count && warm.zones[0].samples != plain.zones[0].samples)
        let json = try JSONEncoder().encode(edit)
        #expect(try JSONDecoder().decode(OneShotEdit.self, from: json).voice == .warm)
        let legacy = try JSONDecoder().decode(OneShotEdit.self, from: Data(#"{"startFrame":0,"endFrame":100,"gainDB":0,"fadeInFrames":0,"fadeOutFrames":0}"#.utf8))
        #expect(legacy.voice == nil)
    }
}
