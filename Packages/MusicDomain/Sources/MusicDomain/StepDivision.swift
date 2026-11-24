import Foundation

/// I24 · How finely the step editor divides a bar: straight eighths to thirty-seconds,
/// and eighth or sixteenth triplets.
public enum StepDivision: String, CaseIterable, Codable, Sendable, Identifiable {
    case eighth, sixteenth, eighthTriplet, sixteenthTriplet, thirtySecond
    public var id: String { rawValue }

    /// Steps in one 4/4 bar.
    public var steps: Int {
        switch self {
        case .eighth: 8
        case .sixteenth: 16
        case .eighthTriplet: 12
        case .sixteenthTriplet: 24
        case .thirtySecond: 32
        }
    }

    /// Ticks between steps; every division fits a bar exactly.
    public var ticks: Int { barTicks / steps }
    /// Steps in one beat, for the visual grouping.
    public var perBeat: Int { steps / 4 }
    public var isTriplet: Bool { self == .eighthTriplet || self == .sixteenthTriplet }

    public var title: String {
        switch self {
        case .eighth: "1/8"
        case .sixteenth: "1/16"
        case .eighthTriplet: "1/8T"
        case .sixteenthTriplet: "1/16T"
        case .thirtySecond: "1/32"
        }
    }

    /// The tick of a step in a bar.
    public func tick(bar: Int, step: Int) -> Int { bar * barTicks + step * ticks }

    /// The step a tick falls on, or nil when it sits between this division's steps.
    public func step(of tick: Int) -> Int? { tick % ticks == 0 ? (tick % barTicks) / ticks : nil }

    /// How many hits of a bar sit between the steps of this division (shown as a hint).
    public func offGrid(_ hits: [DrumEvent], bar: Int) -> Int {
        hits.filter { $0.tick / barTicks == bar && $0.tick % ticks != 0 }.count
    }

    /// The coarsest division that shows every hit of a bar, so an opened beat looks complete.
    public static func fitting(_ hits: [DrumEvent], bar: Int) -> StepDivision {
        let inBar = hits.filter { $0.tick / barTicks == bar }
        return [StepDivision.eighth, .sixteenth, .eighthTriplet, .sixteenthTriplet, .thirtySecond]
            .first { division in inBar.allSatisfy { $0.tick % division.ticks == 0 } } ?? .sixteenth
    }
}
