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
