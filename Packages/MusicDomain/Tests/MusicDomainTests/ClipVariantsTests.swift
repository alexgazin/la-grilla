import Foundation
import Testing
@testable import MusicDomain

struct ClipVariantsTests {
    private func project() throws -> Project {
        var p = Project(name: "Variants", bars: 2)
        p.patterns[1].drums = [DrumEvent(tick: 0, pad: 0), DrumEvent(tick: 960, pad: 1)]
        try p.validate()
        return p
    }

    @Test func addSwitchAndRemoveKeepEveryPartAndOneUndoEach() throws {
        var p = try project()
        let track = p.tracks[1].id, clip = p.tracks[1].clips[0].id, a = p.tracks[1].clips[0].patternID
        let before = Compiler.notes(p)
        let b = try ClipVariants.add(track: track, clip: clip, in: &p)
        #expect(Compiler.notes(p) == before)                                  // an exact copy sounds the same
        #expect(p.tracks[1].clips[0].patternID == b && p.tracks[1].clips[0].variants == [a])
        // Edit B only.
        let bi = p.patterns.firstIndex { $0.id == b }!
        p.patterns[bi].drums.append(DrumEvent(tick: 1920, pad: 2))
        #expect(p.patterns.first { $0.id == a }!.drums.count == 2)
        #expect(ClipVariants.options(p.tracks[1].clips[0], in: p) == [a, b])
        #expect(ClipVariants.label(0) == "A" && ClipVariants.label(2) == "C")
        try ClipVariants.select(a, track: track, clip: clip, in: &p)
        #expect(Compiler.notes(p) == before && p.tracks[1].clips[0].variants == [b])
        // Pruning anywhere keeps the inactive variant.
        p.removeUnusedPatterns()
        #expect(p.patterns.contains { $0.id == b })
        let c = try ClipVariants.add(track: track, clip: clip, in: &p)
        _ = try ClipVariants.add(track: track, clip: clip, in: &p)
        #expect(throws: MusicError.self) { try ClipVariants.add(track: track, clip: clip, in: &p) }
        try ClipVariants.select(c, track: track, clip: clip, in: &p)
        try ClipVariants.removeCurrent(track: track, clip: clip, in: &p)
        #expect(!p.patterns.contains { $0.id == c } && p.tracks[1].clips[0].patternID == a)
        try p.validate()
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(decoded.tracks[1].clips[0].variants == p.tracks[1].clips[0].variants)
    }

    @Test func invalidVariantListsAreRejectedAndEditsKeepThem() throws {
        var p = try project()
        let track = p.tracks[1].id, clip = p.tracks[1].clips[0].id
        try ClipVariants.add(track: track, clip: clip, in: &p)
        var broken = p
        broken.tracks[1].clips[0].variants = [UUID()]
        #expect(throws: MusicError.self) { try broken.validate() }
        broken = p
        broken.tracks[1].clips[0].variants = [broken.tracks[1].clips[0].patternID]
        #expect(throws: MusicError.self) { try broken.validate() }
        // Recording into the clip materializes a new pattern; the variant survives.
        var draft = try DrumRecordingDraft(project: p, clipID: clip)
        try draft.commitPass([DrumEvent(tick: 480, pad: 3)])
        let recorded = try draft.candidate(for: p)
        try recorded.validate()
        #expect(recorded.tracks[1].clips[0].variants?.count == 1)
        #expect(recorded.patterns.contains { $0.id == recorded.tracks[1].clips[0].variants![0] })
    }
}
