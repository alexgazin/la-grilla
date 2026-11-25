import Foundation

/// 55 · How a recorded take sits in time over the drum sequencer: exactly as played (micro-timing
/// and groove kept), or pulled toward a grid with a strength. Chosen before recording and changeable
/// on every take afterwards, without losing what was played.
public struct TakeTiming: Codable, Equatable, Hashable, Sendable {
    /// Grid in ticks (a `Quantize` value); 0 = as played.
    public var grid: Int
    /// 0…1: how far each hit moves toward the grid.
    public var strength: Double
    /// 0.5 = straight; up to 0.75 swings every second step (ignored on triplet grids).
    public var swing: Double

    public static let natural = TakeTiming(grid: 0, strength: 1, swing: 0.5)
    public static let strengths: [Double] = [0.5, 0.75, 1]

    public init(grid: Int, strength: Double = 1, swing: Double = 0.5) {
        self.grid = grid; self.strength = strength; self.swing = swing
    }
    public init(_ quantize: Quantize, strength: Double = 1, swing: Double = 0.5) {
        self.init(grid: quantize.rawValue, strength: strength, swing: swing)
    }

    public var quantize: Quantize { Quantize(rawValue: grid) ?? .off }
    public var isNatural: Bool { grid == 0 || strength <= 0 }
    public var quantizer: GrooveQuantizer {
        GrooveQuantizer(grid: grid, strength: strength, swing: quantize.isTriplet ? 0.5 : swing)
    }

    public func validate() throws {
        guard Quantize(rawValue: grid) != nil, strength.isFinite, (0...1).contains(strength), swing.isFinite, (0.5...0.75).contains(swing) else { throw MusicError.invalidProject }
    }

    /// "As played", or "1/16 · 75%".
    public var summary: String {
        isNatural ? NSLocalizedString("As played", comment: "Take timing") : quantize.label + (strength < 1 ? " · \(Int((strength * 100).rounded()))%" : "")
    }

    /// Where a hit played at `played` lands with this timing in a pattern of `length` ticks.
    public func tick(_ played: Int, length: Int) -> Int {
        guard length > 0 else { return 0 }
        let wrapped = ((played % length) + length) % length
        return isNatural ? wrapped : quantizer.tick(wrapped, length: length)
    }
}

public enum DrumTakeTiming {
    /// True when the take has hits that remember where they were played.
    public static func canRetime(_ take: UUID, in pattern: Pattern) -> Bool {
        pattern.drums.contains { $0.take == take && $0.played != nil }
            || (pattern.drumTakes?.first { $0.id == take }?.held ?? []).contains { $0.played != nil }
    }

    /// Moves every hit of the take that remembers where it was played to `timing`. A hit that lands
    /// on a step where the same pad already sounds is held aside (the louder hit plays), so the
    /// take can go back to how it was played at any time. One edit for the caller.
    @discardableResult
    public static func apply(_ timing: TakeTiming, take id: UUID, in pattern: inout Pattern) throws -> Int {
        try timing.validate()
        guard let index = pattern.drumTakes?.firstIndex(where: { $0.id == id }) else { throw MusicError.invalidProject }
        let length = pattern.length
        let others = pattern.drums.filter { $0.take != id }
        let mine = pattern.drums.filter { $0.take == id } + (pattern.drumTakes![index].held ?? [])
        var occupied = Set(others.map { $0.tick * 16 + $0.pad })
        var placed: [DrumEvent] = [], held: [DrumEvent] = [], moved = 0
        // Louder hits first so the strongest one keeps a shared step; ties keep the played order.
        for var hit in mine.sorted(by: { ($1.velocity, $0.played ?? $0.tick) < ($0.velocity, $1.played ?? $1.tick) }) {
            if let played = hit.played {
                let tick = timing.tick(played, length: length)
                if tick != hit.tick { moved += 1 }
                hit.tick = tick
            } else {
                hit.tick = min(length - 1, max(0, hit.tick))
            }
            let key = hit.tick * 16 + hit.pad
            if occupied.contains(key) { held.append(hit) } else {
                occupied.insert(key)
                hit.id = pattern.drums.contains { $0.id == hit.id } ? hit.id : UUID()
                placed.append(hit)
            }
        }
        guard others.count + placed.count <= 4096, held.count <= 4096 else { throw MusicError.tooDense }
        pattern.drums = others + placed.sorted { ($0.tick, $0.pad) < ($1.tick, $1.pad) }
        pattern.drumTakes![index].timing = timing
        pattern.drumTakes![index].held = held.isEmpty ? nil : held
        return moved
    }
}

/// 55 · The same choice for a phrase played on the keyboard: notes keep where they were played and
/// can be pulled to a grid (start only; lengths follow so a note never crosses the next one).
public enum NoteTiming {
    public static func applied(_ notes: [NoteEvent], timing: TakeTiming, length: Int) -> [NoteEvent] {
        guard !timing.isNatural, length > 0 else { return notes }
        return notes.map { note in
            var moved = note
            moved.tick = timing.quantizer.tick(note.tick, length: length)
            moved.duration = max(1, min(note.duration, length - moved.tick))
            return moved
        }
    }
}
