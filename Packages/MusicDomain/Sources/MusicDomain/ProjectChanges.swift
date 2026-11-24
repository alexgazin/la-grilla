import Foundation

/// U6 · One readable difference between two states of a project, for the visual
/// history. Values stay structured (area, kind, subject, bar, count); the UI turns
/// them into localized text.
public struct ProjectChange: Equatable, Sendable {
    public enum Area: String, Sendable, CaseIterable {
        case project, tempo, key, structure, harmony, drums, layers, bass, melody, mix, sound, takes, voice
    }
    public enum Kind: String, Sendable { case added, removed, changed }
    public var area: Area
    public var kind: Kind
    /// Track, section, pad or take name already in display form; nil = the whole area.
    public var subject: String?
    /// One-based song bar where the change starts, when it is a single place.
    public var bar: Int?
    /// How many events (chords, hits, notes) changed, when that is meaningful.
    public var count: Int?
    /// Before and after for single values (tempo, key, name).
    public var from: String?
    public var to: String?
    public init(area: Area, kind: Kind, subject: String? = nil, bar: Int? = nil, count: Int? = nil, from: String? = nil, to: String? = nil) {
        self.area = area; self.kind = kind; self.subject = subject; self.bar = bar; self.count = count; self.from = from; self.to = to
    }
}

public enum ProjectChanges {
    /// At most this many changes are reported; the history row shows the first and a count.
    public static let limit = 12

    public static func describe(from before: Project, to after: Project) -> [ProjectChange] {
        var result: [ProjectChange] = []
        if before.name != after.name { result.append(.init(area: .project, kind: .changed, from: before.name, to: after.name)) }
        if before.bpm != after.bpm { result.append(.init(area: .tempo, kind: .changed, from: bpm(before.bpm), to: bpm(after.bpm))) }
        if before.keyRoot != after.keyRoot || before.minor != after.minor {
            result.append(.init(area: .key, kind: .changed, from: before.keyName, to: after.keyName))
        }
        result += sections(before, after)
        result += tracks(before, after)
        result += patterns(before, after)
        if before.bassOctave != after.bassOctave || before.bassGate != after.bassGate { result.append(.init(area: .bass, kind: .changed)) }
        if before.master != after.master || before.masterEQ != after.masterEQ || before.masterFX != after.masterFX {
            result.append(.init(area: .mix, kind: .changed))
        }
        let oldAssets = Set((before.audioAssets ?? []).map(\.id)), newAssets = Set((after.audioAssets ?? []).map(\.id))
        if !newAssets.subtracting(oldAssets).isEmpty { result.append(.init(area: .voice, kind: .added, count: newAssets.subtracting(oldAssets).count)) }
        if !oldAssets.subtracting(newAssets).isEmpty { result.append(.init(area: .voice, kind: .removed, count: oldAssets.subtracting(newAssets).count)) }
        return Array(result.prefix(limit))
    }

    private static func bpm(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func area(for role: TrackRole) -> ProjectChange.Area {
        switch role { case .harmony: .harmony; case .drums: .drums; case .bass: .bass; case .melody: .melody }
    }

    private static func sections(_ before: Project, _ after: Project) -> [ProjectChange] {
        var result: [ProjectChange] = []
        let old = Dictionary(before.sections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.sections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for section in after.sections where old[section.id] == nil {
            result.append(.init(area: .structure, kind: .added, subject: section.name, bar: section.start / barTicks + 1))
        }
        for section in before.sections where new[section.id] == nil {
            result.append(.init(area: .structure, kind: .removed, subject: section.name))
        }
        for section in after.sections {
            guard let previous = old[section.id], previous != section else { continue }
            if previous.name != section.name {
                result.append(.init(area: .structure, kind: .changed, subject: section.name, from: previous.name, to: section.name))
            } else if previous.length != section.length {
                result.append(.init(area: .structure, kind: .changed, subject: section.name,
                                    from: String(previous.length / barTicks), to: String(section.length / barTicks)))
            } else if previous.color != section.color || previous.filterSweep != section.filterSweep {
                result.append(.init(area: .mix, kind: .changed, subject: section.name))
            }
        }
        if result.isEmpty, before.sections.map(\.id) != after.sections.map(\.id) {
            result.append(.init(area: .structure, kind: .changed))
        }
        return result
    }

    private static func tracks(_ before: Project, _ after: Project) -> [ProjectChange] {
        var result: [ProjectChange] = []
        let old = Dictionary(before.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Set(after.tracks.map(\.id))
        for track in after.tracks where old[track.id] == nil {
            result.append(.init(area: area(for: track.role), kind: .added, subject: track.displayName))
        }
        for track in before.tracks where !new.contains(track.id) {
            result.append(.init(area: area(for: track.role), kind: .removed, subject: track.displayName))
        }
        for track in after.tracks {
            guard let previous = old[track.id], previous != track else { continue }
            if previous.mute != track.mute || previous.solo != track.solo || previous.gain != track.gain
                || previous.pan != track.pan || previous.equalizer != track.equalizer || previous.dynamics != track.dynamics {
                result.append(.init(area: .mix, kind: .changed, subject: track.displayName))
            }
            if previous.instrumentSample != track.instrumentSample || previous.padSamples != track.padSamples
                || previous.padEdits != track.padEdits || previous.synth != track.synth || previous.presetVersion != track.presetVersion {
                result.append(.init(area: .sound, kind: .changed, subject: track.displayName))
            }
            if (previous.mutedPads ?? []) != (track.mutedPads ?? []) {
                let was = Set(previous.mutedPads ?? []), now = Set(track.mutedPads ?? [])
                let changed = was.symmetricDifference(now).sorted()
                let direction = now.isSuperset(of: was) ? "muted" : was.isSuperset(of: now) ? "unmuted" : nil
                result.append(.init(area: .layers, kind: .changed, subject: changed.count == 1 ? padName(changed[0]) : track.displayName,
                                    count: changed.count, to: direction))
            }
            if previous.clips != track.clips {
                result.append(.init(area: .structure, kind: .changed, subject: track.displayName))
            }
            if previous.name != track.name || previous.locked != track.locked {
                result.append(.init(area: area(for: track.role), kind: .changed, subject: track.displayName))
            }
        }
        return result
    }

    private static func padName(_ pad: Int) -> String {
        Compiler.padNames.indices.contains(pad) ? NSLocalizedString(Compiler.padNames[pad], comment: "Drum pad") : String(pad + 1)
    }

    /// The track that plays a pattern and, when it plays it exactly once, the clip.
    private static func owner(of pattern: UUID, in project: Project) -> (track: Track, clip: Clip?)? {
        var found: (Track, [Clip])?
        for track in project.tracks {
            let clips = track.clips.filter { $0.patternID == pattern || ($0.variants ?? []).contains(pattern) }
            guard !clips.isEmpty else { continue }
            if found == nil { found = (track, clips) } else { return (found!.0, nil) }
        }
        guard let found else { return nil }
        return (found.0, found.1.count == 1 ? found.1[0] : nil)
    }

    private static func bar(_ tick: Int?, clip: Clip?) -> Int? {
        guard let tick, let clip, tick >= clip.offset, tick - clip.offset < clip.length else { return nil }
        return (clip.start + tick - clip.offset) / barTicks + 1
    }

    /// Added, removed and edited event counts plus the earliest tick that differs.
    private static func diff<E: Identifiable & Equatable>(_ old: [E], _ new: [E], tick: (E) -> Int) -> (count: Int, first: Int?) where E.ID == UUID {
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let current = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var count = 0, first: Int?
        func mark(_ t: Int) { count += 1; first = min(first ?? t, t) }
        for event in new { if let was = previous[event.id] { if was != event { mark(min(tick(was), tick(event))) } } else { mark(tick(event)) } }
        for event in old where current[event.id] == nil { mark(tick(event)) }
        return (count, first)
    }

    private static func kind(added: Int, removed: Int) -> ProjectChange.Kind {
        added > 0 && removed == 0 ? .added : removed > 0 && added == 0 ? .removed : .changed
    }

    private static func patterns(_ before: Project, _ after: Project) -> [ProjectChange] {
        var result: [ProjectChange] = []
        let old = Dictionary(before.patterns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for pattern in after.patterns {
            guard let previous = old[pattern.id], previous != pattern else { continue }
            let owner = owner(of: pattern.id, in: after) ?? owner(of: pattern.id, in: before)
            let subject = owner?.track.displayName
            let chords = diff(previous.chords, pattern.chords, tick: \.tick)
            if chords.count > 0 {
                let added = pattern.chords.count - previous.chords.count
                result.append(.init(area: .harmony, kind: kind(added: max(0, added), removed: max(0, -added)), subject: subject,
                                    bar: bar(chords.first, clip: owner?.clip), count: chords.count))
            }
            let drums = diff(previous.drums, pattern.drums, tick: \.tick)
            let oldTakes = Dictionary((previous.drumTakes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let newTakes = pattern.drumTakes ?? []
            var takeChanges: [ProjectChange] = []
            for take in newTakes {
                if let was = oldTakes[take.id] {
                    if was.muted != take.muted {
                        takeChanges.append(.init(area: .takes, kind: .changed, subject: String(take.number), to: take.muted == true ? "muted" : "unmuted"))
                    }
                } else { takeChanges.append(.init(area: .takes, kind: .added, subject: String(take.number))) }
            }
            let kept = Set(newTakes.map(\.id))
            for take in previous.drumTakes ?? [] where !kept.contains(take.id) {
                takeChanges.append(.init(area: .takes, kind: .removed, subject: String(take.number)))
            }
            result += takeChanges
            // A recorded or deleted take already explains its hits.
            if drums.count > 0 && takeChanges.allSatisfy({ $0.kind == .changed }) {
                let pads = Set(pattern.drums.map(\.pad)).symmetricDifference(Set(previous.drums.map(\.pad)))
                let touched = Set(diffPads(previous.drums, pattern.drums)).union(pads)
                let added = pattern.drums.count - previous.drums.count
                result.append(.init(area: .drums, kind: kind(added: max(0, added), removed: max(0, -added)),
                                    subject: touched.count == 1 ? padName(touched.first!) : subject,
                                    bar: bar(drums.first, clip: owner?.clip), count: drums.count))
            }
            let notes = diff(previous.notes ?? [], pattern.notes ?? [], tick: \.tick)
            if notes.count > 0 {
                let added = (pattern.notes ?? []).count - (previous.notes ?? []).count
                result.append(.init(area: .melody, kind: kind(added: max(0, added), removed: max(0, -added)), subject: subject,
                                    bar: bar(notes.first, clip: owner?.clip), count: notes.count))
            }
            if previous.length != pattern.length && chords.count + drums.count + notes.count == 0 {
                result.append(.init(area: .structure, kind: .changed, subject: subject))
            }
        }
        return result
    }

    private static func diffPads(_ old: [DrumEvent], _ new: [DrumEvent]) -> [Int] {
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let current = Set(new.map(\.id))
        var pads: [Int] = []
        for event in new where previous[event.id] != event { pads.append(event.pad); if let was = previous[event.id] { pads.append(was.pad) } }
        for event in old where !current.contains(event.id) { pads.append(event.pad) }
        return pads
    }
}
