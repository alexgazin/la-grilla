import Foundation
import Testing
@testable import MusicDomain

@Suite struct DrumLayersTests {
    private func beat() -> Pattern {
        var p = Pattern(length: barTicks * 2)
        p.drums = [DrumEvent(tick: 0, pad: 0), DrumEvent(tick: 960, pad: 1), DrumEvent(tick: 480, pad: 2),
                   DrumEvent(tick: 1440, pad: 2), DrumEvent(tick: barTicks, pad: 0), DrumEvent(tick: barTicks + 480, pad: 2)]
        return p
    }

    @Test func layersListUsedPadsWithCountsAndKeepMutedOnes() {
        var track = Track(role: .drums)
        DrumLayers.setMuted(&track, pad: 9, muted: true)
        let layers = DrumLayers.layers(in: beat(), track: track)
        #expect(layers.map(\.pad) == [0, 1, 2, 9])
        #expect(layers.map(\.hits) == [2, 1, 3, 0])
        #expect(layers.last?.muted == true)
        #expect(DrumLayers.layers(in: beat(), track: nil, bar: 1).map(\.hits) == [1, 1])
    }

    @Test func clearingOneLayerOrOneBarLeavesTheRest() {
        var p = beat()
        #expect(DrumLayers.clear(&p, pad: 2, bar: 0) == 2)
        #expect(p.drums.filter { $0.pad == 2 }.count == 1)
        #expect(DrumLayers.clear(&p, pad: 0) == 2)
        #expect(Set(p.drums.map(\.pad)) == [1, 2])
        #expect(DrumLayers.clearAll(&p, bar: 1) == 1)
        #expect(DrumLayers.clearAll(&p) == 1)
        #expect(p.drums.isEmpty)
    }

    @Test func mutedPadsSkipPlaybackButStayInThePattern() throws {
        var project = Project.demo()
        guard let d = project.tracks.firstIndex(where: { $0.role == .drums }) else { return }
        let before = Compiler.notes(project).filter { $0.track == d && $0.pad == 0 }.count
        #expect(before > 0)
        DrumLayers.setMuted(&project.tracks[d], pad: 0, muted: true)
        try project.validate()
        #expect(Compiler.notes(project).filter { $0.track == d && $0.pad == 0 }.isEmpty)
        #expect(project.patterns.contains { $0.drums.contains { $0.pad == 0 } })
        DrumLayers.setMuted(&project.tracks[d], pad: 0, muted: false)
        #expect(project.tracks[d].mutedPads == nil)
        #expect(Compiler.notes(project).filter { $0.track == d && $0.pad == 0 }.count == before)
    }

    @Test func soloMutesTheOthersAndTogglesBack() {
        var track = Track(role: .drums)
        DrumLayers.solo(&track, pad: 1, among: [0, 1, 2])
        #expect(track.mutedPads == [0, 2])
        DrumLayers.solo(&track, pad: 1, among: [0, 1, 2])
        #expect(track.mutedPads == nil)
    }

    @Test func invalidMutedPadsAreRejectedAndOldFilesDecode() throws {
        var project = Project.demo()
        let h = try #require(project.tracks.firstIndex { $0.role == .harmony })
        project.tracks[h].mutedPads = [0]
        #expect(throws: (any Error).self) { try project.validate() }
        let legacy = try JSONEncoder().encode(Track(role: .drums))
        #expect(!String(decoding: legacy, as: UTF8.self).contains("mutedPads"))
        #expect(try JSONDecoder().decode(Track.self, from: legacy).mutedPads == nil)
    }
}
