/// A position in La Grilla's 4/4 timeline. Bars and quarter-note beats are
/// one-based; the optional final component is a zero-based tick within a beat.
/// This representation retains unsnapped positions from existing documents.
public struct MusicalPosition: Equatable, Sendable, CustomStringConvertible {
    public let bar: Int
    public let beat: Int
    public let tickWithinBeat: Int

    /// Project positions are nonnegative. Clamp an invalid negative display
    /// input to the beginning without rounding any valid tick to a grid.
    public init(tick: Int) {
        let tick = max(0, tick)
        bar = tick / barTicks + 1
        beat = tick % barTicks / ppq + 1
        tickWithinBeat = tick % ppq
    }

    /// `bar:beat`, or `bar:beat:tick` when a position lies between beats.
    public var description: String {
        let position = "\(bar):\(beat)"
        return tickWithinBeat == 0 ? position : "\(position):\(tickWithinBeat)"
    }
}
