import Foundation

/// U11 · "Show me how it all works": five steps on a demo song, each finished by doing the real
/// action (not by reading). A step can be passed over; the whole tour can be skipped and started
/// again from Settings.
public enum TourStep: Int, CaseIterable, Codable, Sendable {
    case pads, chords, hum, layers, export

    public var title: String {
        switch self {
        case .pads: "Play the pads"
        case .chords: "Change a chord"
        case .hum: "Hum a melody"
        case .layers: "Balance the layers"
        case .export: "Take it with you"
        }
    }

    public var detail: String {
        switch self {
        case .pads: "Open Jam and tap any pad. Each one is a drum of the demo song."
        case .chords: "In Grid, tap a chord and pick another one. The bass and keys follow it."
        case .hum: "Open Voice: hum or sing a line and La Grilla writes the notes."
        case .layers: "Open Mixer: every part is a layer with its own level, pan and effects."
        case .export: "Open Export: share audio, MIDI or stems with another app."
        }
    }

    /// The action that finishes this step.
    public var event: TourEvent {
        switch self {
        case .pads: .padHit
        case .chords: .chordChanged
        case .hum: .voiceOpened
        case .layers: .mixerOpened
        case .export: .exportOpened
        }
    }
}

/// What the studio reports to the tour.
public enum TourEvent: Equatable, Sendable {
    case padHit, chordChanged, voiceOpened, mixerOpened, exportOpened
}

public struct DemoTour: Equatable, Codable, Sendable {
    /// The step being shown; nil once every step is done or passed over.
    public private(set) var step: TourStep?
    /// Steps finished by doing the action.
    public private(set) var done: Set<TourStep> = []
    /// Steps passed over with "Next".
    public private(set) var passed: Set<TourStep> = []

    public init() { step = TourStep.allCases.first }

    public var finished: Bool { step == nil }
    /// 1-based number of the current step (the total when finished).
    public var number: Int { step.map { $0.rawValue + 1 } ?? TourStep.allCases.count }
    public static var count: Int { TourStep.allCases.count }

    /// Records an action. Doing the current step's action finishes it and moves on; doing a later
    /// step's action early counts too, so it is not asked for again. Returns true when the current
    /// step was finished.
    @discardableResult
    public mutating func observe(_ event: TourEvent) -> Bool {
        guard let current = step else { return false }
        guard let matched = TourStep.allCases.first(where: { $0.event == event }) else { return false }
        if matched != current {
            if matched.rawValue > current.rawValue { done.insert(matched) }
            return false
        }
        done.insert(current)
        advance()
        return true
    }

    /// "Next": passes over the current step without doing it.
    public mutating func next() {
        guard let current = step else { return }
        passed.insert(current)
        advance()
    }

    /// Skips the rest of the tour.
    public mutating func skip() {
        guard let current = step else { return }
        for item in TourStep.allCases where item.rawValue >= current.rawValue && !done.contains(item) { passed.insert(item) }
        step = nil
    }

    private mutating func advance() {
        guard let current = step else { return }
        step = TourStep.allCases.first { $0.rawValue > current.rawValue && !done.contains($0) }
    }
}
