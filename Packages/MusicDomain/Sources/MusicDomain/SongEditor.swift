import Foundation

/// Applies a SongEditPlan to the project it was made for. Every operation
/// first isolates the edited bars of its track into an independent pattern, so
/// an edit of one section occurrence never changes another occurrence that
/// shares the same source pattern. Tracks that no operation targets, the mix,
/// sounds and sections stay identical; this is verified after the edit.
public enum SongEditor {
    public static func apply(_ plan: SongEditPlan, to project: Project) throws -> Project {
        guard project.id == plan.projectID, project.revision == plan.baseRevision else { throw SongEditError.stale }
        guard plan.isApplicable else { throw SongEditError.notApplicable }
        try project.validate()
        var result = project
        for operation in plan.operations { try apply(operation, to: &result) }
        let used = Set(result.tracks.flatMap { $0.clips.map(\.patternID) })
        result.patterns.removeAll { !used.contains($0.id) }
        try verifyUntouched(before: project, after: result, plan: plan)
        try result.validate()
        return result
    }

    // MARK: Isolation

    /// Bar-aligned range around `requested` that no sustained note or chord of
    /// this track crosses, so splitting clips never re-attacks a held sound.
    static func isolationRange(_ project: Project, track index: Int, requested: Range<Int>) -> Range<Int> {
        let compiled = Compiler.notes(project).filter { note in
            note.pad < 0 && (note.track == index || (project.tracks[index].role == .harmony && project.tracks.indices.contains(note.track) && project.tracks[note.track].role == .bass))
        }
        var lower = requested.lowerBound, upper = min(project.length, requested.upperBound)
        var changed = true
        while changed {
            changed = false
            if lower > 0, compiled.contains(where: { $0.tick < lower && $0.tick + $0.duration > lower }) { lower -= barTicks; changed = true }
            if upper < project.length, compiled.contains(where: { $0.tick < upper && $0.tick + $0.duration > upper }) { upper += barTicks; changed = true }
        }
        return max(0, lower)..<min(project.length, upper)
    }

    /// Replace the track's clips over `range` with one clip of a new pattern
    /// holding exactly the sound of that range. Returns the pattern index.
    static func isolate(_ project: inout Project, track index: Int, range: Range<Int>) throws -> Int {
        guard range.lowerBound >= 0, range.upperBound <= project.length, !range.isEmpty,
              range.lowerBound % barTicks == 0, range.count % barTicks == 0 else { throw MusicError.invalidProject }
        let track = project.tracks[index]
        let material = Arrangement.materialize(project, track: track, section: Section(name: "Edit", start: range.lowerBound, length: range.count))
        var clips: [Clip] = []
        var covering: [Clip] = []
        for clip in track.clips {
            let end = clip.start + clip.length
            if end <= range.lowerBound || clip.start >= range.upperBound { clips.append(clip); continue }
            covering.append(clip)
            if clip.start < range.lowerBound { var left = clip; left.length = range.lowerBound - clip.start; clips.append(left) }
            if end > range.upperBound, let pattern = project.patterns.first(where: { $0.id == clip.patternID }) {
                var right = clip; right.id = UUID(); right.start = range.upperBound; right.length = end - range.upperBound
                right.offset = (clip.offset + range.upperBound - clip.start) % pattern.length
                clips.append(right)
            }
        }
        guard project.patterns.count < 64 else { throw MusicError.tooDense }
        project.patterns.append(material)
        var middle = Clip(patternID: material.id, start: range.lowerBound, length: range.count)
        if covering.count == 1, covering[0].start <= range.lowerBound, covering[0].start + covering[0].length >= range.upperBound {
            middle.sourceAssetID = covering[0].sourceAssetID
        }
        clips.append(middle)
        project.tracks[index].clips = clips.sorted { $0.start < $1.start }
        return project.patterns.count - 1
    }

    // MARK: Operations

    static func apply(_ op: SongEditOperation, to project: inout Project) throws {
        guard let index = project.tracks.firstIndex(where: { $0.id == op.target.trackID }) else { throw MusicError.invalidProject }
        guard op.bars.lowerBound >= 0, op.bars.upperBound * barTicks <= project.length, !op.bars.isEmpty else { throw MusicError.invalidProject }
        let role = project.tracks[index].role
        guard role != .bass else { throw SongEditError.notApplicable }
        let requested = op.bars.lowerBound * barTicks..<op.bars.upperBound * barTicks
        let range = isolationRange(project, track: index, requested: requested)
        if op.kind == .arpeggiate || op.kind == .hook {
            try arpeggiate(op, into: index, requested: requested, project: &project)
            return
        }
        let patternIndex = try isolate(&project, track: index, range: range)
        let base = range.lowerBound
        // Local windows (relative to the isolated pattern) the operation edits.
        let windows: [Range<Int>] = op.editedBars.map { ($0 * barTicks - base)..<(($0 + 1) * barTicks - base) }
        var pattern = project.patterns[patternIndex]
        let pads = op.target.pads.map(Set.init)
        func selected(_ e: DrumEvent, _ window: Range<Int>) -> Bool { window.contains(e.tick) && (pads?.contains(e.pad) ?? true) }
        switch op.kind {
        case .remove:
            for window in windows {
                pattern.drums.removeAll { selected($0, window) }
                pattern.notes?.removeAll { window.contains($0.tick) }
                pattern.chords.removeAll { window.contains($0.tick) }
            }
            // A chord that began before the window and sounds into it is cut at the window.
            for window in windows {
                for i in pattern.chords.indices where pattern.chords[i].tick < window.lowerBound && pattern.chords[i].tick + pattern.chords[i].duration > window.lowerBound {
                    pattern.chords[i].duration = window.lowerBound - pattern.chords[i].tick
                }
                if var notes = pattern.notes {
                    for i in notes.indices where notes[i].tick < window.lowerBound && notes[i].tick + notes[i].duration > window.lowerBound {
                        notes[i].duration = window.lowerBound - notes[i].tick
                    }
                    pattern.notes = notes
                }
            }
        case .fill:
            let barEnd = op.bars.upperBound * barTicks - base
            let length = max(ppq, min(barTicks, op.amount))
            let window = (barEnd - length)..<barEnd
            pattern.drums.removeAll { window.contains($0.tick) && $0.tick != window.lowerBound }
            pattern.drums.removeAll { $0.tick == window.lowerBound && $0.pad != 0 }
            pattern.drums.append(contentsOf: fillHits(window))
        case .denser:
            for window in windows {
                if role == .drums { densify(&pattern.drums, window: window, pads: pads) }
                else if role == .melody { pattern.notes = densifyNotes(pattern.notes ?? [], window: window) }
                else { pattern.chords = densifyChords(pattern.chords, window: window) }
            }
        case .sparser:
            for window in windows {
                if role == .drums { thin(&pattern.drums, window: window, pads: pads) }
                else if role == .melody { pattern.notes = thinNotes(pattern.notes ?? [], window: window) }
                else { pattern.chords = thinChords(pattern.chords, window: window) }
            }
        case .delay:
            let shift = max(1, min(barTicks / 2, op.amount))
            for window in windows {
                for i in pattern.drums.indices where selected(pattern.drums[i], window) {
                    pattern.drums[i].tick = min(pattern.length - 1, pattern.drums[i].tick + shift)
                }
                if var notes = pattern.notes {
                    for i in notes.indices where window.contains(notes[i].tick) {
                        notes[i].tick = min(pattern.length - 1, notes[i].tick + shift)
                        notes[i].duration = max(1, min(notes[i].duration, pattern.length - notes[i].tick))
                    }
                    pattern.notes = notes
                }
                pattern.chords = delayedChords(pattern.chords, window: window, shift: shift, length: pattern.length)
            }
        case .fadeIn, .fadeOut:
            let span = Double(max(1, op.bars.count * barTicks)), start = op.bars.lowerBound * barTicks - base
            func factor(_ tick: Int) -> Double {
                let x = min(1, max(0, Double(tick - start) / span))
                return op.kind == .fadeIn ? 0.25 + 0.75 * x : 1 - 0.75 * x
            }
            let whole = start..<(start + Int(span))
            for i in pattern.drums.indices where whole.contains(pattern.drums[i].tick) && (pads?.contains(pattern.drums[i].pad) ?? true) {
                pattern.drums[i].velocity = scaled(pattern.drums[i].velocity, factor(pattern.drums[i].tick))
            }
            if var notes = pattern.notes {
                for i in notes.indices where whole.contains(notes[i].tick) { notes[i].velocity = scaled(notes[i].velocity, factor(notes[i].tick)) }
                pattern.notes = notes
            }
            for i in pattern.chords.indices where whole.contains(pattern.chords[i].tick) {
                pattern.chords[i].velocity = scaled(pattern.chords[i].velocity ?? 88, factor(pattern.chords[i].tick))
            }
        case .arpeggiate, .hook:
            break
        }
        pattern.drums.sort { ($0.tick, $0.pad) < ($1.tick, $1.pad) }
        pattern.notes?.sort { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
        pattern.chords.sort { $0.tick < $1.tick }
        project.patterns[patternIndex] = pattern
    }

    static func scaled(_ velocity: Int, _ factor: Double) -> Int { max(1, min(127, Int((Double(velocity) * factor).rounded()))) }

    /// A short snare-to-toms run that rises in level and ends on the barline.
    static func fillHits(_ window: Range<Int>) -> [DrumEvent] {
        let step = ppq / 4, count = window.count / step
        var hits: [DrumEvent] = []
        for i in 0..<count {
            let progress = Double(i) / Double(max(1, count - 1))
            let pad: Int
            switch progress {
            case ..<0.4: pad = 1           // snare
            case ..<0.6: pad = 8           // high tom
            case ..<0.8: pad = 7           // mid tom
            default: pad = 6               // low tom
            }
            hits.append(DrumEvent(tick: window.lowerBound + i * step, pad: pad, velocity: Int(72 + 46 * progress)))
        }
        return hits
    }

    static func densify(_ drums: inout [DrumEvent], window: Range<Int>, pads: Set<Int>?) {
        let used = Set(drums.filter { window.contains($0.tick) }.map(\.pad))
        for pad in used where pads?.contains(pad) ?? true {
            let before = drums.count
            defer {
                // Already on every sixteenth: a thirty-second roll into the next bar.
                if drums.count == before {
                    let lastBeat = (window.upperBound - ppq)..<window.upperBound
                    let ticks = drums.filter { $0.pad == pad && lastBeat.contains($0.tick) }.sorted { $0.tick < $1.tick }
                    for event in ticks where event.tick + ppq / 8 < window.upperBound && !drums.contains(where: { $0.pad == pad && $0.tick == event.tick + ppq / 8 }) {
                        drums.append(DrumEvent(tick: event.tick + ppq / 8, pad: pad, velocity: max(1, event.velocity * 2 / 3)))
                    }
                }
            }
            let ticks = drums.filter { $0.pad == pad && window.contains($0.tick) }.sorted { $0.tick < $1.tick }
            var next = ticks.map(\.tick).dropFirst() + [window.upperBound]
            for event in ticks {
                let following = next.removeFirst()
                let gap = following - event.tick
                guard gap >= 2 * (ppq / 4) else { continue }
                let middle = event.tick + (gap / 2) / (ppq / 4) * (ppq / 4)
                if middle > event.tick, middle < window.upperBound, !drums.contains(where: { $0.pad == pad && $0.tick == middle }) {
                    drums.append(DrumEvent(tick: middle, pad: pad, velocity: max(1, event.velocity * 3 / 4)))
                }
            }
        }
    }

    static func thin(_ drums: inout [DrumEvent], window: Range<Int>, pads: Set<Int>?) {
        let used = Set(drums.filter { window.contains($0.tick) }.map(\.pad))
        var remove = Set<UUID>()
        for pad in used where pads?.contains(pad) ?? true {
            let events = drums.filter { $0.pad == pad && window.contains($0.tick) }.sorted { $0.tick < $1.tick }
            for (i, event) in events.enumerated() where i % 2 == 1 && event.tick % barTicks != 0 { remove.insert(event.id) }
        }
        drums.removeAll { remove.contains($0.id) }
    }

    static func densifyNotes(_ notes: [NoteEvent], window: Range<Int>) -> [NoteEvent] {
        var result: [NoteEvent] = []
        for note in notes {
            guard window.contains(note.tick), note.duration >= ppq else { result.append(note); continue }
            var first = note; first.duration = note.duration / 2
            var second = NoteEvent(tick: note.tick + note.duration / 2, duration: note.duration - note.duration / 2, pitch: note.pitch, velocity: max(1, note.velocity * 4 / 5))
            second.confidence = note.confidence
            result.append(first); result.append(second)
        }
        return result
    }

    static func thinNotes(_ notes: [NoteEvent], window: Range<Int>) -> [NoteEvent] {
        let inside = notes.filter { window.contains($0.tick) }.sorted { $0.tick < $1.tick }
        let offbeat = Set(inside.filter { $0.tick % ppq != 0 }.map(\.id))
        let remove = offbeat.isEmpty ? Set(inside.enumerated().filter { $0.offset % 2 == 1 }.map(\.element.id)) : offbeat
        return notes.filter { !remove.contains($0.id) }
    }

    static func densifyChords(_ chords: [ChordEvent], window: Range<Int>) -> [ChordEvent] {
        var result: [ChordEvent] = []
        for chord in chords {
            guard window.contains(chord.tick), chord.duration >= 2 * ppq else { result.append(chord); continue }
            var tick = chord.tick
            while tick < chord.tick + chord.duration {
                let duration = min(ppq, chord.tick + chord.duration - tick)
                result.append(ChordEvent(tick: tick, duration: duration, chord: chord.chord, velocity: chord.velocity))
                tick += ppq
            }
        }
        return result
    }

    static func thinChords(_ chords: [ChordEvent], window: Range<Int>) -> [ChordEvent] {
        // Merge a repeated chord into the previous one and let it ring.
        var result: [ChordEvent] = []
        for chord in chords.sorted(by: { $0.tick < $1.tick }) {
            if window.contains(chord.tick), var last = result.last, last.chord == chord.chord, last.tick + last.duration <= chord.tick {
                last.duration = chord.tick + chord.duration - last.tick
                result[result.count - 1] = last
            } else { result.append(chord) }
        }
        return result
    }

    static func delayedChords(_ chords: [ChordEvent], window: Range<Int>, shift: Int, length: Int) -> [ChordEvent] {
        var sorted = chords.sorted { $0.tick < $1.tick }
        for i in sorted.indices where window.contains(sorted[i].tick) {
            sorted[i].tick = min(length - 1, sorted[i].tick + shift)
        }
        // Keep chords sequential and inside the pattern.
        for i in sorted.indices {
            let limit = i + 1 < sorted.count ? sorted[i + 1].tick : length
            sorted[i].duration = max(1, min(sorted[i].duration, limit - sorted[i].tick))
        }
        return sorted.filter { $0.duration > 0 && $0.tick < length }
    }

    /// Arpeggio over the chords that already sound in the range, on an existing
    /// arpeggio/melody target or a new "Arpeggio" track.
    static func arpeggiate(_ op: SongEditOperation, into index: Int, requested: Range<Int>, project: inout Project) throws {
        let source = Arrangement.harmony(project, section: Section(name: "Arp", start: requested.lowerBound, length: requested.count))
        guard !source.isEmpty else { throw SongEditError.notApplicable }
        let target: Int
        if project.tracks[index].role == .melody {
            target = index
        } else {
            guard project.tracks.count < 8 else { throw SongEditError.trackLimit }
            try project.addMelody(name: op.kind == .hook ? NSLocalizedString("Hook", comment: "Generated hook track") : NSLocalizedString("Arpeggio", comment: "Generated arpeggio track"))
            target = project.tracks.count - 1
        }
        let range = isolationRange(project, track: target, requested: requested)
        let patternIndex = try isolate(&project, track: target, range: range)
        var pattern = project.patterns[patternIndex]
        let base = range.lowerBound
        let windows = op.editedBars.map { ($0 * barTicks - base)..<(($0 + 1) * barTicks - base) }
        let step = ppq / 2
        if op.kind == .hook {
            let local = source.map { chord -> ChordEvent in var c = chord; c.tick += requested.lowerBound - base; return c }
            let hook = HookGenerator.hook(chords: local, start: requested.lowerBound - base, bars: op.bars.count, root: project.keyRoot, minor: project.minor, seed: UInt64(project.revision) &+ UInt64(op.bars.lowerBound))
            for window in windows {
                pattern.notes?.removeAll { window.contains($0.tick) }
                pattern.notes?.append(contentsOf: hook.filter { window.contains($0.tick) }.map { n in var x = n; x.duration = min(x.duration, window.upperBound - x.tick); return x })
            }
            pattern.notes?.sort { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
            project.patterns[patternIndex] = pattern
            return
        }
        for window in windows {
            pattern.notes?.removeAll { window.contains($0.tick) }
            for chord in source {
                let absolute = requested.lowerBound + chord.tick
                let tones = Array(Set(chord.chord.notes.map { pitch -> Int in
                    var p = pitch; while p < 60 { p += 12 }; while p > 84 { p -= 12 }; return p
                })).sorted()
                guard !tones.isEmpty else { continue }
                let sequence = tones + tones.dropFirst().dropLast().reversed()
                var tick = absolute, i = 0
                while tick < absolute + chord.duration {
                    let local = tick - base
                    if window.contains(local) {
                        let duration = min(step, absolute + chord.duration - tick, window.upperBound - local)
                        if duration > 0 { pattern.notes?.append(NoteEvent(tick: local, duration: duration, pitch: sequence[i % sequence.count], velocity: i % 4 == 0 ? 92 : 78)) }
                    }
                    tick += step; i += 1
                }
            }
        }
        pattern.notes?.sort { ($0.tick, $0.pitch) < ($1.tick, $1.pitch) }
        project.patterns[patternIndex] = pattern
        if op.replacesChords, let harmony = project.tracks.firstIndex(where: { $0.role == .harmony }) {
            let removal = SongEditOperation(kind: .remove, target: SongEditTarget(trackID: project.tracks[harmony].id),
                                            bars: op.bars, everyOther: op.everyOther)
            try apply(removal, to: &project)
        }
    }

    // MARK: Safety

    /// Every track that no operation targets must compile to the same notes.
    static func verifyUntouched(before: Project, after: Project, plan: SongEditPlan) throws {
        var targeted = Set(plan.operations.map(\.target.trackID))
        for op in plan.operations where (op.kind == .arpeggiate || op.kind == .hook) && op.replacesChords {
            if let harmony = before.tracks.first(where: { $0.role == .harmony }) { targeted.insert(harmony.id) }
        }
        let old = Compiler.notes(before), new = Compiler.notes(after)
        for (index, track) in before.tracks.enumerated() {
            guard let afterIndex = after.tracks.firstIndex(where: { $0.id == track.id }) else { throw SongEditError.protectedPartChanged }
            var a = after.tracks[afterIndex], b = track
            a.clips = []; b.clips = []
            guard a == b else { throw SongEditError.protectedPartChanged }
            if targeted.contains(track.id) && !plan.protectedTracks.contains(track.id) { continue }
            // Derived bass follows harmony; it is protected only when harmony is untouched.
            if track.role == .bass, let harmony = before.tracks.first(where: { $0.role == .harmony }), targeted.contains(harmony.id), !plan.protectedTracks.contains(track.id) { continue }
            let x = old.filter { $0.track == index }.map(NoteKey.init), y = new.filter { $0.track == afterIndex }.map(NoteKey.init)
            guard x == y else { throw SongEditError.protectedPartChanged }
        }
        for kept in plan.protectedPads {
            guard let index = before.tracks.firstIndex(where: { $0.id == kept.trackID }), let afterIndex = after.tracks.firstIndex(where: { $0.id == kept.trackID }) else { continue }
            let pads = Set(kept.pads ?? [])
            let x = old.filter { $0.track == index && pads.contains($0.pad) }.map(NoteKey.init)
            let y = new.filter { $0.track == afterIndex && pads.contains($0.pad) }.map(NoteKey.init)
            guard x == y else { throw SongEditError.protectedPartChanged }
        }
        guard before.sections == after.sections, before.bpm == after.bpm, before.keyRoot == after.keyRoot, before.minor == after.minor,
              before.master == after.master, before.masterFX == after.masterFX, before.masterEQ == after.masterEQ else { throw SongEditError.protectedPartChanged }
    }

    struct NoteKey: Equatable, Hashable {
        let tick: Int, duration: Int, pitch: Int, velocity: Int, pad: Int
        init(_ n: CompiledNote) { tick = n.tick; duration = n.duration; pitch = n.pitch; velocity = n.velocity; pad = n.pad }
    }
}

/// MIDI-event difference between two versions of a project, per track.
public struct SongEditDiff: Equatable, Sendable {
    public struct Event: Equatable, Hashable, Sendable {
        public var trackID: UUID, tick: Int, duration: Int, pitch: Int, velocity: Int, pad: Int
    }
    public var added: [Event]
    public var removed: [Event]
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    public init(before: Project, after: Project, range: Range<Int>? = nil) {
        func events(_ p: Project) -> [Event] {
            Compiler.notes(p, range: range).compactMap { n in
                guard p.tracks.indices.contains(n.track) else { return nil }
                return Event(trackID: p.tracks[n.track].id, tick: n.tick + (range?.lowerBound ?? 0), duration: n.duration, pitch: n.pitch, velocity: n.velocity, pad: n.pad)
            }
        }
        var counts: [Event: Int] = [:]
        for e in events(before) { counts[e, default: 0] += 1 }
        var added: [Event] = []
        for e in events(after) {
            if let c = counts[e], c > 0 { counts[e] = c - 1 } else { added.append(e) }
        }
        var removed: [Event] = []
        for (e, c) in counts where c > 0 { removed.append(contentsOf: Array(repeating: e, count: c)) }
        func order(_ a: Event, _ b: Event) -> Bool { (a.tick, a.pitch, a.pad, a.velocity) < (b.tick, b.pitch, b.pad, b.velocity) }
        self.added = added.sorted(by: order); self.removed = removed.sorted(by: order)
    }

    public func events(on trackID: UUID) -> (added: [Event], removed: [Event]) {
        (added.filter { $0.trackID == trackID }, removed.filter { $0.trackID == trackID })
    }
}
