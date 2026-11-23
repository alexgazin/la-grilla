import Foundation

/// Deterministic random numbers (SplitMix64): the same seed always gives the same music,
/// so a variant heard in the audition is exactly the one applied.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func chance(_ probability: Double) -> Bool { Double(next() % 10_000) / 10_000 < probability }
}

/// I7 · "Four more versions of this part": deterministic variations of a pattern.
public enum PartVariator {
    public enum Character: String, CaseIterable, Sendable {
        case ghostNotes, fill, simpler, busier, swing
        public var title: String {
            switch self {
            case .ghostNotes: "Ghost notes"
            case .fill: "Fill at the end"
            case .simpler: "Simpler"
            case .busier: "Busier"
            case .swing: "Swing"
            }
        }
    }

    /// Characters that make sense for a role (drums use all; melodic parts skip fills and ghost notes).
    public static func characters(for role: TrackRole) -> [Character] {
        role == .drums ? Character.allCases : [.simpler, .busier, .swing]
    }

    /// A variation. `boldness` 0 returns the pattern unchanged; 1 is the strongest version.
    public static func variant(_ pattern: Pattern, role: TrackRole, character: Character, boldness: Double, seed: UInt64) -> Pattern {
        let amount = min(1, max(0, boldness))
        guard amount > 0 else { return pattern }
        var random = SeededRandom(seed: seed &+ UInt64(Character.allCases.firstIndex(of: character) ?? 0) &* 1_000_003)
        var result = pattern
        if role == .drums {
            result.drums = drums(pattern, character: character, amount: amount, random: &random)
        } else {
            result.notes = notes(pattern, character: character, amount: amount, random: &random)
        }
        return result
    }

    private static func free(_ drums: [DrumEvent], pad: Int, tick: Int) -> Bool { !drums.contains { $0.pad == pad && $0.tick == tick } }

    private static func drums(_ pattern: Pattern, character: Character, amount: Double, random: inout SeededRandom) -> [DrumEvent] {
        var hits = pattern.drums
        let sixteenth = barTicks / 16
        switch character {
        case .ghostNotes:
            for tick in stride(from: 0, to: pattern.length, by: sixteenth) where tick % (sixteenth * 2) != 0 && free(hits, pad: 1, tick: tick) {
                if random.chance(0.45 * amount) { hits.append(DrumEvent(tick: tick, pad: 1, velocity: 28 + Int(random.next() % 16))) }
            }
        case .fill:
            let beats = 1 + Int((amount * 2).rounded(.down))
            let start = pattern.length - beats * (barTicks / 4)
            hits.removeAll { $0.tick >= start && ($0.pad == 1 || (6...8).contains($0.pad)) }
            let pads = [1, 8, 7, 6]
            for (index, tick) in stride(from: start, to: pattern.length, by: sixteenth).enumerated() {
                let pad = pads[min(pads.count - 1, index * pads.count / max(1, (pattern.length - start) / sixteenth))]
                hits.append(DrumEvent(tick: tick, pad: pad, velocity: min(127, 70 + index * 50 / max(1, (pattern.length - start) / sixteenth))))
            }
        case .simpler:
            hits.removeAll { hit in
                let onBeat = hit.tick % (barTicks / 4) == 0
                let backbone = (hit.pad == 0 && hit.tick % barTicks == 0) || (hit.pad == 1 && onBeat)
                return !backbone && !onBeat && random.chance(amount)
            }
        case .busier:
            let hatTicks = Set(hits.filter { $0.pad == 2 }.map(\.tick))
            for tick in stride(from: 0, to: pattern.length, by: sixteenth) where !hatTicks.isEmpty && free(hits, pad: 2, tick: tick) {
                if random.chance(0.6 * amount) { hits.append(DrumEvent(tick: tick, pad: 2, velocity: 58 + Int(random.next() % 20))) }
            }
            for bar in 0..<(pattern.length / barTicks) {
                let tick = bar * barTicks + barTicks * 7 / 8
                if free(hits, pad: 0, tick: tick), random.chance(0.5 * amount) { hits.append(DrumEvent(tick: tick, pad: 0, velocity: 96)) }
            }
        case .swing:
            let shift = Int(Double(sixteenth) * 0.33 * amount)
            hits = hits.map { hit in
                guard hit.tick % (sixteenth * 2) == sixteenth else { return hit }
                var moved = hit; moved.tick = min(pattern.length - 1, hit.tick + shift); return moved
            }
        }
        return Array(hits.sorted { $0.tick == $1.tick ? $0.pad < $1.pad : $0.tick < $1.tick }.prefix(4096))
    }

    private static func notes(_ pattern: Pattern, character: Character, amount: Double, random: inout SeededRandom) -> [NoteEvent] {
        var notes = pattern.notes ?? []
        let sixteenth = barTicks / 16
        switch character {
        case .simpler:
            notes.removeAll { $0.duration < sixteenth * 2 && $0.tick % (barTicks / 4) != 0 && random.chance(amount) }
        case .busier:
            // Repeat long notes as two shorter ones on the same pitch.
            notes = notes.flatMap { note -> [NoteEvent] in
                guard note.duration >= sixteenth * 4, random.chance(0.6 * amount) else { return [note] }
                var first = note, second = note
                first.duration = note.duration / 2
                second.id = UUID(); second.tick = note.tick + note.duration / 2; second.duration = note.duration - first.duration
                second.velocity = max(1, note.velocity - 12)
                return [first, second]
            }
        case .swing:
            let shift = Int(Double(sixteenth) * 0.33 * amount)
            notes = notes.map { note in
                guard note.tick % (sixteenth * 2) == sixteenth else { return note }
                var moved = note; moved.tick = min(pattern.length - 1, note.tick + shift)
                moved.duration = max(1, min(moved.duration, pattern.length - moved.tick)); return moved
            }
        case .ghostNotes, .fill:
            break
        }
        return Array(notes.sorted { $0.tick < $1.tick }.prefix(4096))
    }
}

/// I8 · Automatic fills before a section change, kept as their own take so the
/// Layers panel can mute or delete them in one touch.
public enum FillGenerator {
    public enum Kind: String, CaseIterable, Sendable {
        case snare, toms, roll, riser
        public var title: String {
            switch self { case .snare: "Snare build"; case .toms: "Tom run"; case .roll: "Snare roll"; case .riser: "Hat riser" }
        }
    }

    /// Adds a fill to the last `beats` beats of the bar that ends at `end` (pattern ticks).
    /// Returns the new take's id, or nil when there is no room.
    @discardableResult
    public static func add(_ kind: Kind, beats: Int, endingAt end: Int, strength: Double = 0.8, to pattern: inout Pattern) -> UUID? {
        let span = max(1, min(4, beats)) * (barTicks / 4)
        let start = end - span
        guard start >= 0, end <= pattern.length, (pattern.drumTakes ?? []).count < 64 else { return nil }
        let take = DrumTake(number: ((pattern.drumTakes ?? []).map(\.number).max() ?? 0) + 1, label: "Fill")
        let step = kind == .roll ? barTicks / 32 : barTicks / 16
        let count = span / step
        var hits: [DrumEvent] = []
        for index in 0..<count {
            let tick = start + index * step
            let rise = Double(index) / Double(max(1, count - 1))
            let velocity = max(1, min(127, Int((50 + 70 * rise) * (0.6 + 0.4 * strength))))
            let pad: Int
            switch kind {
            case .snare, .roll: pad = 1
            case .toms: pad = [8, 7, 6][min(2, index * 3 / max(1, count))]
            case .riser:
                // 8ths, then 16ths, then every 32nd-ish position as it builds.
                let stride = index < count / 2 ? 2 : 1
                guard index % stride == 0 else { continue }
                pad = 2
            }
            var hit = DrumEvent(tick: tick, pad: pad, velocity: velocity)
            hit.take = take.id
            hits.append(hit)
        }
        guard pattern.drums.count + hits.count <= 4096 else { return nil }
        pattern.drums += hits
        pattern.drumTakes = (pattern.drumTakes ?? []) + [take]
        return take.id
    }
}

/// I3 · Comping: build one take from the best bars of several takes.
public extension DrumTakes {
    /// For every chosen bar, copies that take's hits into a new "Comp" take; the source
    /// takes are muted (not deleted) so nothing is lost. Returns the comp take's id.
    @discardableResult
    static func comp(_ pattern: inout Pattern, choices: [Int: UUID]) -> UUID? {
        guard !choices.isEmpty, (pattern.drumTakes ?? []).count < 64 else { return nil }
        let known = Set((pattern.drumTakes ?? []).map(\.id))
        guard choices.values.allSatisfy(known.contains) else { return nil }
        let comp = DrumTake(number: ((pattern.drumTakes ?? []).map(\.number).max() ?? 0) + 1, label: "Comp")
        var copies: [DrumEvent] = []
        for (bar, take) in choices.sorted(by: { $0.key < $1.key }) {
            for hit in pattern.drums where hit.take == take && hit.tick / barTicks == bar {
                var copy = hit; copy.id = UUID(); copy.take = comp.id; copies.append(copy)
            }
        }
        guard !copies.isEmpty, pattern.drums.count + copies.count <= 4096 else { return nil }
        pattern.drums += copies
        let sources = Set(choices.values)
        pattern.drumTakes = (pattern.drumTakes ?? []).map { take in
            var updated = take; if sources.contains(take.id) { updated.muted = true }; return updated
        } + [comp]
        return comp.id
    }
}
