import Foundation
import Testing
@testable import MusicDomain

struct OneShotEditingTests {
    private func source(_ samples: [Int16], rate: Int = 16000) throws -> (OneShotSource, Data) {
        let pcm = SamplePCM(rate: rate, zones: [.init(pitch: 42, samples: samples)])
        let bytes = try pcm.encode(kind: .oneShot)
        let asset = try SampleAsset(kind: .oneShot, name: "Rim", bytes: bytes)
        return (try OneShotSource(asset: asset, data: bytes), bytes)
    }

    @Test func waveformIncludesTheLastFrameAndBothPolarities() throws {
        var frames = [Int16](repeating: 0, count: 1003)
        frames[0] = .min; frames[1002] = .max
        let (input, bytes) = try source(frames)
        #expect(input.waveform.count == 256 && input.frameCount == frames.count && input.sampleRate == 16000)
        #expect(input.waveform.first?.min == -1 && input.waveform.last?.max == Float(Int16.max)/32768)
        #expect(try input.render(input.initialEdit).encode(kind: .oneShot) == bytes)
        #expect(try input.render(input.initialEdit).zones[0].pitch == 42)
        let (minimum, _) = try source(Array(frames.prefix(32)))
        #expect(minimum.waveform.count == 32)
    }

    @Test func trimUsesHalfOpenFramesAndFadesAndGainArePrintedOnce() throws {
        var frames = [Int16](repeating: 4000, count: 128)
        frames[8] = 123; frames[73] = 321
        let (input, originalBytes) = try source(frames)
        let edit = OneShotEdit(startFrame: 9, endFrame: 73, gainDB: 20*log10(2.0), fadeInFrames: 3, fadeOutFrames: 5)
        let output = try input.render(edit)
        #expect(output.zones.count == 1 && output.rate == 16000)
        let rendered = output.zones[0].samples
        #expect(rendered.count == 64)
        #expect(Array(rendered.prefix(4)) == [0,4000,8000,8000])
        #expect(Array(rendered.suffix(5)) == [8000,6000,4000,2000,0])
        let wav = try input.previewWAV(edit)
        let pcm = try output.encode(kind: .oneShot)
        #expect(wav.count == 44 + 128 && wav.prefix(4) == Data("RIFF".utf8))
        #expect(Data(wav.dropFirst(44)) == Data(pcm.dropFirst(24)))
        #expect(try input.render(input.initialEdit).encode(kind: .oneShot) == originalBytes)

        var extremes = [Int16](repeating: .max, count: 32)
        extremes[3] = .min
        let (loud, _) = try source(extremes)
        var clipping = loud.initialEdit; clipping.gainDB = 12
        #expect(try loud.render(clipping).zones[0].samples == extremes)
        var edge = loud.initialEdit; edge.fadeInFrames = 1; edge.fadeOutFrames = 1
        let result = try loud.render(edge).zones[0].samples
        #expect(result.first == 0 && result.last == 0 && result[1] == .max && result[3] == .min)
    }

    @Test func clipCountAndHeadroomUseTheSameTrimGainAndFadesAsPreview() throws {
        var frames = [Int16](repeating: 0, count: 320)
        frames[1] = .max  // trimmed out
        frames[32] = .min // faded to zero
        frames[42] = 30000
        frames[43] = -24000
        frames[44] = 11000
        frames[94] = .max // faded below clipping
        let (input, _) = try source(frames)
        var edit = OneShotEdit(startFrame: 32, endFrame: 96, gainDB: 6, fadeInFrames: 3, fadeOutFrames: 5)
        let levels = try input.levels(for: edit)
        #expect(levels.clippedFrames == 2)
        let peak = try #require(levels.peakDBFS)
        #expect(abs(peak - (6+20*log10(30000.0/32768))) < 0.00001)
        let rendered = try input.render(edit).zones[0].samples
        #expect(rendered.filter { $0 == .min || $0 == .max }.count == levels.clippedFrames)
        edit.gainDB = try #require(levels.headroomGainDB)
        #expect(edit.gainDB == -0.3)
        let safe = try input.levels(for: edit)
        let safePeak = try #require(safe.peakDBFS)
        #expect(safe.clippedFrames == 0 && safe.headroomGainDB == nil && (-1.1 ... -1.0).contains(safePeak))
        let silence = try input.levels(for: .init(startFrame: 100, endFrame: 200))
        #expect(silence.peakDBFS == nil && silence.clippedFrames == 0 && silence.headroomGainDB == nil)
    }

    @Test func invalidInputsAndOversizedFadesCannotReachRenderer() throws {
        let (input, bytes) = try source(Array(repeating: 123, count: 5000))
        for invalid in [
            OneShotEdit(startFrame: -1, endFrame: 40), OneShotEdit(startFrame: Int.max, endFrame: Int.min),
            OneShotEdit(startFrame: 4950, endFrame: 5001), OneShotEdit(startFrame: 0, endFrame: 31),
            OneShotEdit(startFrame: 0, endFrame: 100, gainDB: .infinity), OneShotEdit(startFrame: 0, endFrame: 100, gainDB: .nan),
            OneShotEdit(startFrame: 0, endFrame: 100, gainDB: 13), OneShotEdit(startFrame: 0, endFrame: 100, gainDB: -25),
            OneShotEdit(startFrame: 0, endFrame: 100, fadeInFrames: -1), OneShotEdit(startFrame: 0, endFrame: 100, fadeOutFrames: 101),
            OneShotEdit(startFrame: 0, endFrame: 5000, fadeInFrames: 4001)
        ] { #expect(throws: SampleError.self) { try input.render(invalid) } }
        #expect(input.maximumFadeFrames(for: input.initialEdit) == 4000)
        #expect(input.maximumFadeFrames(for: .init(startFrame: Int.max, endFrame: Int.min)) == 0)
        let instrument = try SampleAsset(kind: .instrument, name: "Instrument", bytes: bytes)
        #expect(throws: SampleError.self) { try OneShotSource(asset: instrument, data: bytes) }
        var corrupt = bytes; corrupt[30] ^= 1
        #expect(throws: SampleError.self) { try OneShotSource(asset: input.asset, data: corrupt) }
    }

    @Test func editsKeepTheirFullSourceInUndoDuplicationAndPortableArchives() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(root: folder)
        let frames = (0..<2048).map { Int16(($0%31-15)*1400) }
        let (input, bytes) = try source(frames)
        var song = Project.demo()
        try song.tracks[1].setPadSample(input.asset, pad: 0)
        try song.tracks[1].setPadSample(input.asset, pad: 3)
        let edit = OneShotEdit(startFrame: 80, endFrame: 830, gainDB: -12, fadeInFrames: 8, fadeOutFrames: 18)
        let printed = try input.render(edit).encode(kind: .oneShot)
        let hit = try SampleAsset(kind: .oneShot, name: "Edited rim", bytes: printed)
        let record = PadSampleEditRecord(source: input, edit: edit, renderedID: hit.id)
        var history = History()
        try history.apply(&song) { try $0.tracks[1].setPadSample(hit, pad: 0, edit: record) }
        #expect(song.tracks[1].padSamples?[3] == input.asset && song.tracks[1].padEdits?[3] == nil)
        history.undo(&song)
        #expect(song.tracks[1].padSamples?[0] == input.asset && song.tracks[1].padEdits == nil)
        history.redo(&song)
        try song.tracks[1].setPadSample(nil, pad: 3)
        #expect(song.tracks[1].padSamples == [0:hit] && song.referencedSamples == [hit,input.asset])
        let data = try PortableProject.data(song, assets: [hit.relativePath: printed, input.asset.relativePath: bytes])
        let imported = try await store.install(PortableProject.decodeBundle(data))
        let copy = try await store.duplicate(imported)
        let reopened = try await store.load(copy.id)
        let recipe = try #require(reopened.tracks[1].padEdits?[0])
        #expect(recipe == record && reopened.referencedSamples == song.referencedSamples)
        let read = try OneShotSource(asset: recipe.source, data: try await store.sampleData(recipe.source, projectID: reopened.id))
        #expect(read.frameCount == frames.count && read.sampleRate == recipe.sourceRate)
        #expect(try read.render(recipe.edit).encode(kind: .oneShot) == printed)
        var restored = reopened
        try history.apply(&restored) { _ = try $0.tracks[1].restoreOriginal(pad: 0) }
        #expect(restored.tracks[1].padEdits == nil && restored.tracks[1].padSamples?[0] == input.asset)
        history.undo(&restored)
        #expect(restored.tracks[1].padEdits?[0] == record)
        restored.tracks[1].clearPadSamples()
        #expect(restored.referencedSamples.isEmpty)
        #expect(throws: ExportError.self) { try PortableProject.data(song, assets: [hit.relativePath: printed]) }
    }

    @Test func mismatchedRecipeRateOrRenderedAssetIsRejected() throws {
        let (input, original) = try source(Array(repeating: 1200, count: 160))
        let edit = OneShotEdit(startFrame: 25, endFrame: 110)
        let bytes = try input.render(edit).encode(kind: .oneShot)
        let hit = try SampleAsset(kind: .oneShot, name: "Edited rim", bytes: bytes)
        let valid = PadSampleEditRecord(source: input, edit: edit, renderedID: hit.id)
        var track = Track(role: .drums)
        let badID = PadSampleEditRecord(source: input, edit: edit, renderedID: UUID())
        #expect(throws: SampleError.self) { try track.setPadSample(hit, pad: 0, edit: badID) }
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String:Any])
        json["sourceRate"] = 32000
        let badRate = try JSONDecoder().decode(PadSampleEditRecord.self, from: JSONSerialization.data(withJSONObject: json))
        var song = Project.demo()
        try song.tracks[1].setPadSample(hit, pad: 2, edit: badRate)
        #expect(throws: SampleError.self) { try PortableProject.data(song, assets: [input.asset.relativePath: original, hit.relativePath: bytes]) }
        song.schemaVersion = 14
        #expect(throws: MusicError.self) { try ProjectDocument.decode(JSONEncoder().encode(song)) }
        song.tracks[1].clearPadSamples()
        try song.tracks[1].setPadSample(input.asset, pad: 1)
        let migrated = try ProjectDocument.decode(JSONEncoder().encode(song))
        #expect(migrated.schemaVersion == Project.currentSchemaVersion)
        #expect(migrated.tracks[1].padSamples == [1:input.asset] && migrated.tracks[1].padEdits == nil)
    }
}
