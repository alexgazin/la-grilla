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
        DrumTakes.pruneEmpty(&pattern)
        return before - pattern.drums.count
    }

    /// Removes every hit (in `bar`, or the whole beat). Returns how many were removed.
    @discardableResult
    public static func clearAll(_ pattern: inout Pattern, bar: Int? = nil) -> Int {
        let before = pattern.drums.count
        pattern.drums.removeAll { bar == nil || $0.tick / barTicks == bar! }
        DrumTakes.pruneEmpty(&pattern)
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

/// Recorded takes over a drum pattern: list, mute, keep (merge into the programmed beat)
/// or delete one take without touching what was programmed or recorded before.
public enum DrumTakes {
    public struct Summary: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let number: Int
        public let hits: Int
        public let muted: Bool
        /// "Fill" or "Comp" for generated takes, nil for recorded ones.
        public var label: String? = nil
        /// 55: how the take sits in time, and whether it remembers where it was played.
        public var timing: TakeTiming? = nil
        public var canRetime = false
    }

    /// Hits that belong to no listed take: steps, pads played outside recording, generators.
    public static func programmedHits(in pattern: Pattern?) -> Int {
        let known = Set((pattern?.drumTakes ?? []).map(\.id))
        return (pattern?.drums ?? []).filter { $0.take.map { !known.contains($0) } ?? true }.count
    }

    /// Takes oldest first, each with its hit count.
    public static func takes(in pattern: Pattern?) -> [Summary] {
        let drums = pattern?.drums ?? []
        return (pattern?.drumTakes ?? []).map { take in
            Summary(id: take.id, number: take.number, hits: drums.filter { $0.take == take.id }.count, muted: take.muted == true, label: take.label,
                    timing: take.timing, canRetime: pattern.map { DrumTakeTiming.canRetime(take.id, in: $0) } ?? false)
        }.filter { $0.hits > 0 }
    }

    /// A take whose hits were all cleared (by layer, bar or step) is no longer listed.
    public static func pruneEmpty(_ pattern: inout Pattern) {
        guard pattern.drumTakes != nil else { return }
        let owners = Set(pattern.drums.compactMap(\.take))
        pattern.drumTakes?.removeAll { !owners.contains($0.id) }
        if pattern.drumTakes?.isEmpty == true { pattern.drumTakes = nil }
    }

    public static func latest(in pattern: Pattern?) -> Summary? { takes(in: pattern).max { $0.number < $1.number } }

    /// Removes the take and its hits. Returns how many hits were removed.
    @discardableResult
    public static func delete(_ pattern: inout Pattern, take id: UUID) -> Int {
        let before = pattern.drums.count
        pattern.drums.removeAll { $0.take == id }
        pattern.drumTakes?.removeAll { $0.id == id }
        if pattern.drumTakes?.isEmpty == true { pattern.drumTakes = nil }
        return before - pattern.drums.count
    }

    public static func setMuted(_ pattern: inout Pattern, take id: UUID, muted: Bool) {
        guard let i = pattern.drumTakes?.firstIndex(where: { $0.id == id }) else { return }
        pattern.drumTakes?[i].muted = muted ? true : nil
    }

    /// Keeps the take: its hits become part of the programmed beat and the take entry goes.
    public static func keep(_ pattern: inout Pattern, take id: UUID) {
        for i in pattern.drums.indices where pattern.drums[i].take == id { pattern.drums[i].take = nil }
        pattern.drumTakes?.removeAll { $0.id == id }
        if pattern.drumTakes?.isEmpty == true { pattern.drumTakes = nil }
    }
}
