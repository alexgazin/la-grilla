import Foundation

/// I21 · I22 · I27: operations on a set of notes as one transaction. The group
/// keeps its shape: a move that would push any note out of the pattern or the
/// MIDI range is clamped for the whole group, never per note.
public enum NoteSelection {
    /// Notes whose start falls in `ticks` and pitch in `pitches` (a lasso rectangle).
    public static func ids(in notes: [NoteEvent], ticks: Range<Int>, pitches: ClosedRange<Int>) -> Set<UUID> {
        Set(notes.filter { ticks.contains($0.tick) && pitches.contains($0.pitch) }.map(\.id))
    }

    /// Moves every selected note by the same amount. Returns the applied
    /// (possibly clamped) delta.
    @discardableResult
    public static func shift(_ pattern: inout Pattern, ids: Set<UUID>, ticks: Int, semitones: Int) -> (ticks: Int, semitones: Int) {
        guard var notes = pattern.notes else { return (0, 0) }
        let chosen = notes.filter { ids.contains($0.id) }
        guard let first = chosen.map(\.tick).min(), let end = chosen.map({ $0.tick + $0.duration }).max(),
              let low = chosen.map(\.pitch).min(), let high = chosen.map(\.pitch).max() else { return (0, 0) }
        let dt = min(max(ticks, -first), pattern.length - end)
        let dp = min(max(semitones, -low), 127 - high)
        for i in notes.indices where ids.contains(notes[i].id) {
            notes[i].tick += dt; notes[i].pitch += dp
        }
        pattern.notes = notes
        return (dt, dp)
    }

    /// Scales start offsets (from the earliest selected note) and durations.
    /// Factors are limited to 1/4…4 and the result stays inside the pattern.
    public static func stretch(_ pattern: inout Pattern, ids: Set<UUID>, factor: Double) {
        guard factor.isFinite, var notes = pattern.notes else { return }
        let f = min(4, max(0.25, factor))
        let chosen = notes.filter { ids.contains($0.id) }
        guard let anchor = chosen.map(\.tick).min() else { return }
        for i in notes.indices where ids.contains(notes[i].id) {
            let tick = anchor + Int((Double(notes[i].tick - anchor) * f).rounded())
            let duration = max(1, Int((Double(notes[i].duration) * f).rounded()))
            notes[i].tick = min(tick, pattern.length - 1)
            notes[i].duration = max(1, min(duration, pattern.length - notes[i].tick))
        }
        pattern.notes = notes
    }

    public static func delete(_ pattern: inout Pattern, ids: Set<UUID>) {
        pattern.notes?.removeAll { ids.contains($0.id) }
    }

    /// Sets an absolute velocity, clamped to 1…127.
    public static func setVelocity(_ pattern: inout Pattern, ids: Set<UUID>, to value: Int) {
        let v = min(127, max(1, value))
        for i in (pattern.notes ?? []).indices where ids.contains(pattern.notes![i].id) { pattern.notes![i].velocity = v }
    }

    /// Adds `delta` to every selected velocity, each clamped to 1…127.
    public static func offsetVelocity(_ pattern: inout Pattern, ids: Set<UUID>, by delta: Int) {
        for i in (pattern.notes ?? []).indices where ids.contains(pattern.notes![i].id) {
            pattern.notes![i].velocity = min(127, max(1, pattern.notes![i].velocity + delta))
        }
    }

    /// A linear crescendo or diminuendo across the selection in time order.
    public static func ramp(_ pattern: inout Pattern, ids: Set<UUID>, from start: Int, to end: Int) {
        guard let notes = pattern.notes else { return }
        let order = notes.indices.filter { ids.contains(notes[$0].id) }.sorted { notes[$0].tick < notes[$1].tick }
        guard let firstTick = order.first.map({ notes[$0].tick }), let lastTick = order.last.map({ notes[$0].tick }) else { return }
        let span = Double(max(1, lastTick - firstTick))
        for i in order {
            let t = Double(notes[i].tick - firstTick) / span
            pattern.notes![i].velocity = min(127, max(1, Int((Double(start) + (Double(end) - Double(start)) * t).rounded())))
        }
    }

    /// I27 · free placement while the magnet is off: only the pattern bounds apply.
    public static func freeTick(_ tick: Int, duration: Int, length: Int) -> Int {
        min(max(0, tick), max(0, length - max(1, duration)))
    }
}
