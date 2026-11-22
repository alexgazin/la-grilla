import Foundation

/// Pocket beat layers: each pad that has hits in a drum pattern is a layer that can be
/// silenced (kept in the pattern, skipped in playback and export) or cleared outright,
/// for one bar or the whole pattern, as a single edit.
public enum DrumLayers {
    public struct Layer: Equatable, Sendable, Identifiable {
        public let pad: Int
        public let hits: Int
        public let muted: Bool
        public var id: Int { pad }
    }

    /// Layers in pad order: every pad with hits, plus muted pads (so a silenced layer
    /// never disappears from view). `bar` limits the hit count to one bar.
    public static func layers(in pattern: Pattern?, track: Track?, bar: Int? = nil) -> [Layer] {
        let drums = (pattern?.drums ?? []).filter { (0..<16).contains($0.pad) && (bar == nil || $0.tick / barTicks == bar!) }
        var counts: [Int: Int] = [:]
        for drum in drums { counts[drum.pad, default: 0] += 1 }
        let pads = Set(counts.keys).union(track?.mutedPads ?? [])
        return pads.sorted().map { Layer(pad: $0, hits: counts[$0] ?? 0, muted: track?.isPadMuted($0) == true) }
    }

    /// Removes one pad's hits (in `bar`, or everywhere). Returns how many were removed.
    @discardableResult
    public static func clear(_ pattern: inout Pattern, pad: Int, bar: Int? = nil) -> Int {
        let before = pattern.drums.count
        pattern.drums.removeAll { $0.pad == pad && (bar == nil || $0.tick / barTicks == bar!) }
        return before - pattern.drums.count
    }

    /// Removes every hit (in `bar`, or the whole beat). Returns how many were removed.
    @discardableResult
    public static func clearAll(_ pattern: inout Pattern, bar: Int? = nil) -> Int {
        let before = pattern.drums.count
        pattern.drums.removeAll { bar == nil || $0.tick / barTicks == bar! }
        return before - pattern.drums.count
    }

    public static func setMuted(_ track: inout Track, pad: Int, muted: Bool) {
        guard (0..<16).contains(pad) else { return }
        var set = Set(track.mutedPads ?? [])
        if muted { set.insert(pad) } else { set.remove(pad) }
        track.mutedPads = set.isEmpty ? nil : set.sorted()
    }

    /// Solo: only `pad` plays among `pads`; soloing the only audible layer again unmutes all.
    public static func solo(_ track: inout Track, pad: Int, among pads: [Int]) {
        let others = pads.filter { $0 != pad }
        let alreadySolo = !track.isPadMuted(pad) && !others.isEmpty && others.allSatisfy { track.isPadMuted($0) }
        if alreadySolo { track.mutedPads = nil; return }
        var set = Set(track.mutedPads ?? []).union(others)
        set.remove(pad)
        track.mutedPads = set.isEmpty ? nil : set.sorted()
    }
}
