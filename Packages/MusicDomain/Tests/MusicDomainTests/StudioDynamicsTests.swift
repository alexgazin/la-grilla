import Foundation
import Testing
@testable import MusicDomain

struct StudioDynamicsTests {
    private func loudProject() -> Project {
        var project = Project(name: "Loud", bars: 1)
        project.patterns[1].drums = (0..<4).flatMap { q in [DrumEvent(tick: q * ppq, pad: 0, velocity: 127), DrumEvent(tick: q * ppq, pad: 1, velocity: 127), DrumEvent(tick: q * ppq, pad: 9, velocity: 127)] }
        project.patterns[0].chords = [ChordEvent(tick: 0, chord: Chord(root: 0), velocity: 127)]
        for i in project.tracks.indices { project.tracks[i].gain = 6 }
        project.master = 6
        return project
    }

    private func render(_ project: Project, range: Range<Int> = 0..<barTicks) async throws -> (Data, RenderReceipt) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let receipt = try await OfflineRenderer.render(project, to: url, settings: WAVSettings(bitDepth: 16, tailSeconds: 0, dither: false), range: range)
        return (try Data(contentsOf: url), receipt)
    }

    private func samples(_ wav: Data) -> [Int16] {
        let body = wav.dropFirst(44)
        return stride(from: body.startIndex, to: body.endIndex - 1, by: 2).map { Int16(bitPattern: UInt16(body[$0]) | UInt16(body[$0 + 1]) << 8) }
    }

    @Test func neutralDynamicsAreBitIdenticalAndLimiterHoldsTheCeiling() async throws {
        let plain = loudProject()
        var neutral = plain
        for i in neutral.tracks.indices { neutral.tracks[i].dynamics = TrackDynamics() }
        let (a, ra) = try await render(plain), (b, _) = try await render(neutral)
        #expect(a == b)
        #expect(ra.clipped)
        var limited = plain
        limited.masterFX = MasterFX(limiter: true)
        let (c, rc) = try await render(limited)
        #expect(!rc.clipped)
        let ceiling = Int(32767 * pow(10, Double(Project.limiterCeilingDB) / 20)) + 2
        let pcm = samples(c)
        #expect(pcm.allSatisfy { abs(Int($0)) <= ceiling })
        // Look-ahead is compensated: the first hit starts on the same frame.
        let onsetPlain = samples(a).firstIndex { abs(Int($0)) > 200 }, onsetLimited = pcm.firstIndex { abs(Int($0)) > 200 }
        #expect(onsetPlain != nil && onsetLimited != nil && abs(onsetPlain! - onsetLimited!) <= 2)
        #expect(c.count == a.count)
    }

    @Test func dynamicsValidateAndRoundTrip() throws {
        var project = loudProject()
        project.tracks[0].dynamics = TrackDynamics(chokeGroups: [[2, 3], [9, 10, 11]], sidechainDB: 6, drive: 0.4, crushBits: 12)
        project.masterFX = MasterFX(filter: 0, delayWet: 0.1, limiter: true)
        try project.validate()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.tracks[0].dynamics == project.tracks[0].dynamics && decoded.masterFX?.limiter == true)
        for bad in [TrackDynamics(chokeGroups: [[1]]), TrackDynamics(chokeGroups: [[1, 2], [2, 3]]), TrackDynamics(chokeGroups: [[0, 16]]),
                    TrackDynamics(sidechainDB: 13), TrackDynamics(drive: -0.1), TrackDynamics(crushBits: 3), TrackDynamics(sidechainDB: .nan)] {
            var broken = project; broken.tracks[0].dynamics = bad
            #expect(throws: MusicError.self) { try broken.validate() }
        }
        #expect(TrackDynamics().isNeutral && !TrackDynamics.hatChoke.isNeutral && !TrackDynamics(reverbSend: 0.3).isNeutral)
        // Dynamics saved before the reverb send existed still decode.
        let older = try JSONDecoder().decode(TrackDynamics.self, from: Data(#"{"chokeGroups":[[2,3]],"sidechainDB":6,"drive":0,"crushBits":0}"#.utf8))
        #expect(older.reverbSend == 0 && older.chokeGroups == [[2, 3]] && older.sidechainDB == 6)
        var wet = project; wet.tracks[0].dynamics = TrackDynamics(reverbSend: 1.2)
        #expect(throws: MusicError.self) { try wet.validate() }
        let kernel = TrackDynamics(chokeGroups: [[2, 3], [9, 10]]).kernel
        let slots = withUnsafeBytes(of: kernel.choke) { Array($0.bindMemory(to: Int32.self)) }
        #expect(slots[2] == 1 && slots[3] == 1 && slots[9] == 2 && slots[10] == 2 && slots[0] == 0)
        #expect(MetronomeSettings(gainDB: 40).gainDB == 6 && MetronomeSettings(gainDB: -.infinity).gainDB == 0)
    }

    @Test func sectionColourIsOptionalAndBounded() throws {
        var project = Project(name: "Colours", bars: 2)
        #expect(project.sections[0].color == nil)
        project.sections[0].color = 2
        try project.validate()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.sections[0].color == 2)
        project.sections[0].color = 4
        #expect(throws: MusicError.self) { try project.validate() }
    }

    @Test func sectionFilterSweepRendersAndRebasesToTheExportRange() async throws {
        var project = Project(name: "Sweep", bars: 2)
        project.sections = [Section(name: "A", start: 0, length: barTicks), Section(name: "B", start: barTicks, length: barTicks)]
        project.patterns[1].drums = (0..<32).map { DrumEvent(tick: $0 * 240, pad: 2, velocity: 110) }
        try project.validate()
        let plain = try await render(project, range: 0..<project.length).0
        var swept = project
        swept.sections[1].filterSweep = .openUp
        try swept.validate()
        let ramps = swept.filterRamps(rangeStart: barTicks)
        #expect(ramps.count == 1 && ramps[0].start == 0 && ramps[0].end == Int32(barTicks) && ramps[0].from == -0.8)
        #expect(swept.filterRamps().first?.start == Int32(barTicks))
        let (sweptAudio, _) = try await render(swept, range: 0..<swept.length)
        // Exporting only bar 2 applies the same sweep from its first frame (rebased ramp).
        let barTwo = samples(try await render(swept, range: barTicks..<swept.length).0)
        let barTwoOpen = samples(try await render(project, range: barTicks..<project.length).0)
        func level(_ x: [Int16], _ r: Range<Int>) -> Double { sqrt(x[r].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(r.count)) }
        let quarter = barTwo.count / 4
        let early = level(barTwo, 0..<quarter) / level(barTwoOpen, 0..<quarter)
        let late = level(barTwo, 3 * quarter..<barTwo.count) / level(barTwoOpen, 3 * quarter..<barTwo.count)
        #expect(early < 0.3 && late > early * 2)
        let differs = sweptAudio != plain
        #expect(differs)
        // Bar 1 (no sweep) is untouched.
        let firstBarSame = sweptAudio.prefix(44 + 48000 * 2 * 2) == plain.prefix(44 + 48000 * 2 * 2)
        #expect(firstBarSame)
        swept.sections[1].filterSweep = FilterSweep(from: 0.2, to: 0.2)
        #expect(throws: MusicError.self) { try swept.validate() }
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.sections[1].filterSweep == nil)
    }

    @Test func synthPatchRendersValidatesAndRoundTrips() async throws {
        var project = Project(name: "Synth", bars: 1)
        project.patterns[0].chords = [ChordEvent(tick: 0, chord: Chord(root: 0))]
        let plain = try await render(project).0
        var synth = project
        synth.tracks[0].synth = SynthPatch.presets[0].patch
        try synth.validate()
        let voiced = try await render(synth).0
        let differs = voiced != plain
        #expect(differs)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(synth))
        #expect(decoded.tracks[0].synth == synth.tracks[0].synth)
        var drums = project; drums.tracks[1].synth = SynthPatch()
        #expect(throws: MusicError.self) { try drums.validate() }
        var bad = project; bad.tracks[0].synth = SynthPatch(resonance: 0.95)
        #expect(throws: MusicError.self) { try bad.validate() }
        #expect(SynthPatch.presets.count == 4 && SynthPatch.presets.allSatisfy { (try? $0.patch.validate()) != nil })
    }
}
