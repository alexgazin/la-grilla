import Foundation
import Testing
@testable import MusicDomain

struct PadEditExportTests {
    @Test func aTrimmedStudioKickReopensAndRendersInTimeInTheMixAndStem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let samples = try FactoryDrumKit.dusty.sample(pad: 0)
        let sourcePCM = SamplePCM(rate: 32_000, zones: [.init(pitch: 60, samples: samples)])
        let sourceBytes = try sourcePCM.encode(kind: .oneShot)
        let sourceAsset = try SampleAsset(kind: .oneShot, name: "Dusty kick", bytes: sourceBytes)
        let source = try OneShotSource(asset: sourceAsset, data: sourceBytes)

        var project = Project(name: "Kick print", bars: 1)
        project.bpm = 120
        project.master = 0
        project.patterns[1].drums = [DrumEvent(tick: ppq, pad: 0, velocity: 108)]
        try project.tracks[1].setPadSample(sourceAsset, pad: 0)
        let originalMIDI = try MIDIExporter.data(project)
        let settings = WAVSettings(sampleRate: 48_000, bitDepth: 16, tailSeconds: 0, dither: false)
        var library = SampleLibrary()
        library.insert(try PreparedSampleBank(asset: sourceAsset, data: sourceBytes))
        let original = try await OfflineRenderer.render(project, to: directory.appendingPathComponent("original.wav"),
                                                        settings: settings, samples: library)

        var edit = source.initialEdit
        edit.startFrame = 96
        edit.endFrame = 2_016
        edit.gainDB = -6
        edit.fadeInFrames = 48
        edit.fadeOutFrames = 240
        let printed = try source.render(edit).encode(kind: .oneShot)
        let replacement = try SampleAsset(kind: .oneShot, name: "Tight kick", bytes: printed)
        let recipe = PadSampleEditRecord(source: source, edit: edit, renderedID: replacement.id)
        try project.tracks[1].setPadSample(replacement, pad: 0, edit: recipe)
        let package = try PortableProject.data(project, assets: [sourceAsset.relativePath: sourceBytes,
                                                                 replacement.relativePath: printed])
        let store = ProjectStore(root: directory.appendingPathComponent("Projects"))
        let reopened = try await store.install(PortableProject.decodeBundle(package))
        #expect(try MIDIExporter.data(reopened) == originalMIDI)
        let reopenedLibrary = try await store.loadSamples(for: reopened)
        let mix = try await OfflineRenderer.render(reopened, to: directory.appendingPathComponent("mix.wav"),
                                                   settings: settings, samples: reopenedLibrary)
        let stemURL = try await StemExporter.render(reopened, to: directory.appendingPathComponent("stems.zip"),
                                                    settings: settings, selected: [reopened.tracks[1].id],
                                                    samples: reopenedLibrary)
        let stem = try #require(ProjectArchive.decode(Data(contentsOf: stemURL)).first { $0.name.hasSuffix(".wav") })
        let originalBytes = try Data(contentsOf: original.url)
        let mixBytes = try Data(contentsOf: mix.url)
        #expect(original.frames == mix.frames && original.peak > mix.peak && mix.peak > 0.001)
        #expect(!mix.clipped)
        let beat = 24_000
        for wave in [mixBytes, stem.data] {
            #expect(wave.count == 44 + mix.frames * 4)
            #expect(peak(wave, frames: 0..<beat) == 0)
            #expect(peak(wave, frames: beat..<(beat + 2_880)) > 20)
            #expect(peak(wave, frames: (beat + 6_000)..<(beat + 8_000)) <= 1)
        }
        #expect(peak(originalBytes, frames: (beat + 6_000)..<(beat + 8_000)) > 20)
    }

    private func peak(_ wave: Data, frames: Range<Int>) -> Int {
        var maximum = 0
        for offset in stride(from: 44 + frames.lowerBound * 4, to: 44 + frames.upperBound * 4, by: 2) {
            let word = UInt16(wave[offset]) | (UInt16(wave[offset + 1]) << 8)
            maximum = max(maximum, abs(Int(Int16(bitPattern: word))))
        }
        return maximum
    }
}
