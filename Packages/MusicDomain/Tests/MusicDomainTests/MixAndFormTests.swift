import Foundation
import Testing
@testable import MusicDomain

struct MixAndFormTests {
    @Test func mixPresetsChangeOnlyMasterEQAndLeadBalance() throws {
        let p = try SongEditDemo.project()
        for preset in MixPreset.allCases {
            let mixed = try preset.applied(to: p)
            #expect(Compiler.notes(mixed) == Compiler.notes(p))
            #expect(mixed.masterEQ != nil && mixed.master == p.master)
            #expect(mixed.tracks.map(\.presetVersion) == p.tracks.map(\.presetVersion))
            let lead = p.tracks.firstIndex { $0.name == "Flute" }!
            if preset == .club { #expect(mixed.tracks[lead].gain == p.tracks[lead].gain) } else { #expect(mixed.tracks[lead].gain != p.tracks[lead].gain) }
        }
    }

    @Test func formTemplatesFitTheLimitsAndReuseTheSongsParts() throws {
        let p = try SongEditDemo.project()
        for template in SongFormTemplate.allCases {
            let proposal = try template.proposal(for: p)
            let candidate = try proposal.candidate(for: p)
            try candidate.validate()
            #expect(candidate.length <= 64 * barTicks && candidate.sections.count <= 8)
            #expect(candidate.sections.count >= 4)
            #expect(Set(candidate.tracks.map(\.id)) == Set(p.tracks.map(\.id)))
            #expect(!Compiler.notes(candidate).isEmpty)
        }
    }
}

struct StemNormalizeTests {
    @Test func normalizedStemsPeakAtTheTargetAndKeepTheirShape() async throws {
        let p = try SongEditDemo.project()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("norm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let range = 0..<(2 * barTicks)
        let plain = folder.appendingPathComponent("plain.wav"), loud = folder.appendingPathComponent("loud.wav")
        _ = try await OfflineRenderer.render(p, to: plain, settings: WAVSettings(tailSeconds: 0, dither: false), range: range, isolatedTrack: p.tracks[1].id)
        try FileManager.default.copyItem(at: plain, to: loud)
        let gain = try WAVNormalizer.normalize(loud, targetDBFS: -1)
        #expect(gain > 0)
        let a = try LoudnessMeter.readWAV(plain).channels[0], b = try LoudnessMeter.readWAV(loud).channels[0]
        let peak = b.map { abs($0) }.max()!
        #expect(abs(20 * log10(Double(peak)) - -1) < 0.05)
        let ratio = Float(pow(10, gain / 20))
        #expect(zip(a, b).allSatisfy { abs($0 * ratio - $1) < 0.0005 })
        #expect(throws: ExportError.self) { try WAVSettings(normalizeStemsDBFS: 3).validate() }
    }
}

struct RecentlyDeletedTests {
    @Test func deletedProjectsCanBeRestoredForThirtyDaysThenArePurged() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(root: folder.appendingPathComponent("Projects"))
        let a = try SongEditDemo.project(name: "Keep me"), b = try SongEditDemo.project(name: "Old")
        try await store.save(a); try await store.save(b)
        try await store.moveToTrash(a.id)
        try await store.moveToTrash(b.id, now: Date().addingTimeInterval(-31 * 86_400))
        #expect(try await store.listSummaries().isEmpty)
        #expect(await store.recentlyDeleted().map(\.name) == ["Keep me", "Old"])
        #expect(await store.purgeTrash() == 1)
        try await store.restoreFromTrash(a.id)
        let restored = try await store.load(a.id)
        #expect(Compiler.notes(restored) == Compiler.notes(a))
        #expect(try await store.listSummaries().map(\.id) == [a.id])
        #expect(await store.recentlyDeleted().isEmpty)
    }
}
