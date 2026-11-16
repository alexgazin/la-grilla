import Foundation
import Testing
@testable import MusicDomain

struct VoiceNoteProjectionTests {
    private func phrase() -> VoiceAnalysis {
        VoiceAnalysis(segments: [
            VoiceSegment(start: 0, duration: 0.4, pitch: 60, confidence: 0.96, cents: 0, level: 0.4),
            VoiceSegment(start: 0.47, duration: 0.1, pitch: 64, confidence: 0.94, cents: 0, level: 0.3)
        ], duration: 0.6, waveform: [], detector: .yin)
    }

    @Test func partialGridTailKeepsTheLastOnsetOnItsMusicalGrid() {
        let analysis = phrase()
        let notes = VoiceAnalyzer.notes(analysis, bpm: 120, length: 1000, quantize: .eighth)
        #expect(notes.map(\.tick) == [0, 960])
        #expect(notes.map(\.duration) == [960, 40])
        #expect(notes.map(\.pitch) == [60, 64])
        #expect(notes.map(\.confidence) == [0.96, 0.94])
        #expect(analysis.segments[1].start == 0.47 && analysis.segments[1].duration == 0.1)
    }

    @Test(arguments: [1, 120, 239, 240, 241, 479, 480, 481, 1000])
    func shortAndPartialTakesAlwaysProduceBoundedQuantizedNotes(length: Int) {
        for quantize in [Quantize.sixteenth, .eighth] {
            let notes = VoiceAnalyzer.notes(phrase(), bpm: 120, length: length, quantize: quantize)
            #expect(!notes.isEmpty)
            var previousEnd = 0
            for note in notes {
                #expect(note.tick >= previousEnd && note.tick >= 0 && note.tick < length)
                #expect(note.tick % quantize.rawValue == 0)
                #expect(note.duration > 0 && note.tick + note.duration <= length)
                previousEnd = note.tick + note.duration
            }
        }
    }

    @Test func offsetLoopPlacementKeepsEveryTailNoteInsideItsActualCaptureRegion() throws {
        let project = Project.demo(), section = project.sections[0]
        let range = (barTicks + 120)..<(barTicks + 1120)
        let plan = try VoiceCapturePlan.make(project: project, selectedSectionID: section.id,
                                            tick: Double(range.lowerBound + 50), playing: true, loop: true,
                                            range: range, minimumLead: 0.05)
        #expect(plan.captureTicks == 1000 && plan.offsetTicks == range.lowerBound)
        let source = VoiceAnalyzer.notes(phrase(), bpm: project.bpm, length: plan.captureTicks, quantize: .eighth)
        let placed = try plan.place(source, sectionLength: section.length)
        #expect(placed.map(\.tick) == [range.lowerBound, range.lowerBound + 960])
        #expect(placed.last.map { $0.tick + $0.duration } == range.upperBound)
        #expect(placed.map(\.id) == source.map(\.id))
    }

    @Test func shortAnalyzedTakeAppliesAsOneUndoAndPreservesItsRealSyntheticCAF() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceProjection-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(root: folder)
        var project = Project.demo()
        project.bpm = 40
        let original = project, section = project.sections[0]
        let plan = try VoiceCapturePlan.make(project: project, selectedSectionID: section.id, tick: 0,
                                            playing: false, loop: true, range: 0..<project.length,
                                            minimumLead: 0, maximumDuration: 0.2)
        #expect(plan.captureTicks == 128)
        let (data, record) = AudioAssetTests.source()
        try AssetIntegrity.validate(data, record: record)
        // Exact samples used by this deterministic CAF fixture, not a captured
        // human phrase or manufactured live-input receipt.
        let samples = (0..<9600).map { Float(sin(Double($0) * 2 * Double.pi * 220 / 48000) * 0.5) }
        let analysis = try VoiceAnalyzer.analyze(samples, sampleRate: 48000)
        let notes = VoiceAnalyzer.notes(analysis, bpm: project.bpm, length: plan.captureTicks, quantize: .eighth)
        #expect(notes.count == 1 && notes[0].tick == 0 && notes[0].duration == 128 && notes[0].pitch == 57)
        let placed = try plan.place(notes, sectionLength: section.length)
        let placement = try Arrangement.voiceCandidate(project, sectionID: section.id, target: nil, notes: placed, source: record)
        var history = History()
        try history.apply(&project) { $0 = placement.project }
        #expect(Compiler.notes(project).contains { $0.instrument == 3 && $0.tick == 0 && $0.duration == 128 && $0.pitch == 57 })
        try await store.writeAsset(data, record: record, projectID: project.id)
        try await store.save(project)
        let saved = try await store.load(project.id)
        #expect(saved == project)
        #expect(try Data(contentsOf: await store.assetURL(record, projectID: project.id)) == data)
        history.undo(&project)
        #expect(project.patterns == original.patterns && project.tracks == original.tracks && project.audioAssets == original.audioAssets)
        history.redo(&project)
        #expect(project.audioAssets == [record] && project.tracks.last?.clips.first?.sourceAssetID == record.id)
        #expect(try Data(contentsOf: await store.assetURL(record, projectID: project.id)) == data)
    }
}
