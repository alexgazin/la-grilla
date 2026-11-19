import Foundation

/// I78 · merge a co-author's copy into the open project by stable IDs.
///
/// Three-way: `base` is the version that was shared (saved when the portable
/// project was exported). For every element the side that changed it wins;
/// when both changed it differently the musician's own version is kept and a
/// conflict is counted. Elements added on either side are kept; an element
/// deleted on one side is deleted unless the other side changed it.
///
/// Sounds (imported samples, pad edits) and voice recordings are not merged:
/// they stay as in `mine`, because their files belong to the other device.
/// Without a base, nothing is deleted and differing elements keep `mine`.
public enum ProjectMerge {
    public struct Report: Equatable, Sendable {
        public var conflicts = 0
        public var takenFromTheirs = 0
        public var added = 0
        public var removed = 0
        public var keptSounds = 0
        public var hasChanges: Bool { takenFromTheirs + added + removed > 0 }
    }

    public static func merge(base: Project?, mine: Project, theirs: Project) throws -> (project: Project, report: Report) {
        var report = Report()
        let b = base ?? mine
        let twoWay = base == nil
        var result = mine
        result.bpm = pick(b.bpm, mine.bpm, theirs.bpm, twoWay, &report)
        result.keyRoot = pick(b.keyRoot, mine.keyRoot, theirs.keyRoot, twoWay, &report)
        result.minor = pick(b.minor, mine.minor, theirs.minor, twoWay, &report)
        result.master = pick(b.master, mine.master, theirs.master, twoWay, &report)
        result.masterFX = pick(b.masterFX, mine.masterFX, theirs.masterFX, twoWay, &report)
        result.masterEQ = pick(b.masterEQ, mine.masterEQ, theirs.masterEQ, twoWay, &report)
        result.sections = list(base.map(\.sections), mine.sections, theirs.sections, &report, combine: nil)
        result.patterns = list(base.map(\.patterns), mine.patterns, theirs.patterns, &report) { o, m, t, r in
            var p = m
            p.length = pick(o?.length ?? m.length, m.length, t.length, o == nil, &r)
            p.chords = list(o?.chords, m.chords, t.chords, &r, combine: nil)
            p.drums = list(o?.drums, m.drums, t.drums, &r, combine: nil)
            let notes = list(o?.notes ?? [], m.notes ?? [], t.notes ?? [], &r, combine: nil)
            p.notes = notes.isEmpty && m.notes == nil ? nil : notes
            return p
        }
        let assets = Set((mine.audioAssets ?? []).map(\.id))
        result.tracks = list(base.map(\.tracks), mine.tracks, theirs.tracks, &report) { o, m, t, r in
            var track = m
            let original = o ?? m, two = o == nil
            track.gain = pick(original.gain, m.gain, t.gain, two, &r)
            track.pan = pick(original.pan, m.pan, t.pan, two, &r)
            track.mute = pick(original.mute, m.mute, t.mute, two, &r)
            track.solo = pick(original.solo, m.solo, t.solo, two, &r)
            track.name = pick(original.name, m.name, t.name, two, &r)
            track.presetVersion = pick(original.presetVersion, m.presetVersion, t.presetVersion, two, &r)
            track.locked = pick(original.locked, m.locked, t.locked, two, &r)
            track.dynamics = pick(original.dynamics, m.dynamics, t.dynamics, two, &r)
            track.equalizer = pick(original.equalizer, m.equalizer, t.equalizer, two, &r)
            if t.instrumentSample != original.instrumentSample || t.padSamples != original.padSamples || t.padEdits != original.padEdits { r.keptSounds += 1 }
            track.clips = list(o?.clips, m.clips, t.clips, &r, combine: nil).filter { $0.sourceAssetID.map(assets.contains) ?? true }
            return track
        }
        // A track added on the other device keeps its notes but uses built-in sounds.
        for i in result.tracks.indices where !mine.tracks.contains(where: { $0.id == result.tracks[i].id }) {
            if result.tracks[i].instrumentSample != nil || result.tracks[i].padSamples != nil { report.keptSounds += 1 }
            result.tracks[i].instrumentSample = nil; result.tracks[i].padSamples = nil; result.tracks[i].padEdits = nil
        }
        // Patterns no clip uses any more are dropped.
        // Variant lists may point at patterns the other side removed.
        let available = Set(result.patterns.map(\.id))
        for t in result.tracks.indices { for c in result.tracks[t].clips.indices {
            let kept = (result.tracks[t].clips[c].variants ?? []).filter { available.contains($0) && $0 != result.tracks[t].clips[c].patternID }
            result.tracks[t].clips[c].variants = kept.isEmpty ? nil : Array(kept.prefix(3))
        } }
        result.removeUnusedPatterns()
        result.performanceTakes = mine.performanceTakes
        try result.validate()
        return (result, report)
    }

    static func pick<T: Equatable>(_ base: T, _ mine: T, _ theirs: T, _ twoWay: Bool, _ report: inout Report) -> T {
        if mine == theirs { return mine }
        if twoWay { report.conflicts += 1; return mine }
        if mine == base { report.takenFromTheirs += 1; return theirs }
        if theirs == base { return mine }
        report.conflicts += 1
        return mine
    }

    /// Merges an ordered list of identified values. Order follows `mine`, with
    /// elements new in `theirs` inserted after their preceding neighbour.
    static func list<T: Identifiable & Equatable>(_ base: [T]?, _ mine: [T], _ theirs: [T], _ report: inout Report,
                                                   combine: ((T?, T, T, inout Report) -> T)?) -> [T] where T.ID == UUID {
        let baseByID = Dictionary((base ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let theirsByID = Dictionary(theirs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mineIDs = Set(mine.map(\.id))
        var output: [T] = []
        for m in mine {
            let o = baseByID[m.id]
            if let t = theirsByID[m.id] {
                if m == t { output.append(m) }
                else if let combine { output.append(combine(o, m, t, &report)) }
                else { output.append(pick(o ?? m, m, t, base == nil || o == nil, &report)) }
            } else if base != nil, let o {
                // Deleted on their side.
                if m == o { report.removed += 1 } else { report.conflicts += 1; output.append(m) }
            } else {
                output.append(m)            // added on my side (or no base)
            }
        }
        // Elements new on their side, placed after the closest earlier element they had.
        for (index, t) in theirs.enumerated() where !mineIDs.contains(t.id) {
            if base != nil, let o = baseByID[t.id] {
                // I deleted it; keep it only if they changed it.
                if t != o { report.conflicts += 1 } else { continue }
            } else { report.added += 1 }
            let anchor = theirs[..<index].last { item in output.contains { $0.id == item.id } }
            let position = anchor.flatMap { a in output.firstIndex { $0.id == a.id } }.map { $0 + 1 } ?? output.count
            output.insert(t, at: position)
        }
        return output
    }
}
