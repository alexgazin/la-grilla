import Foundation

/// U45 · One gentle suggestion for what to do next, from what the song already has.
public enum NextStepAdvisor {
    public struct Suggestion: Equatable, Sendable {
        public let command: CommandID
        /// English text, also the localization key.
        public let message: String
    }

    public static func suggest(_ project: Project) -> Suggestion? {
        let hasDrums = project.patterns.contains { !$0.drums.isEmpty }
        let hasChords = project.patterns.contains { !$0.chords.isEmpty }
        let hasMelody = project.patterns.contains { !($0.notes ?? []).isEmpty }
        let hasLyrics = project.sections.contains { !($0.lyrics ?? "").isEmpty }
        if !hasDrums && !hasChords { return Suggestion(command: .jam, message: "Start with a beat: play it on the pads.") }
        if !hasDrums { return Suggestion(command: .jam, message: "The chords are here. Add a beat under them?") }
        if !hasChords { return Suggestion(command: .chordImport, message: "The beat is ready. Add chords, or take them from a song or photo?") }
        if !hasMelody { return Suggestion(command: .voice, message: "Chords and beat are ready. Hum a melody over them?") }
        if project.sections.count < 2 { return Suggestion(command: .addSection, message: "One section so far. Add a chorus?") }
        if !hasLyrics { return Suggestion(command: .lyrics, message: "The melody is ready. Write the words under it?") }
        return Suggestion(command: .master, message: "The song is taking shape. Prepare it for release?")
    }
}

/// U44 · Practice: the same section, slower, looping, without changing the song.
public enum Practice {
    public static let rates: [Double] = [0.5, 0.75, 0.9]

    /// A copy of the song for the audition at `rate` of its tempo (kept within 40–240 BPM).
    public static func slowed(_ project: Project, rate: Double) -> Project {
        var copy = project
        copy.bpm = min(240, max(40, (project.bpm * rate).rounded()))
        return copy
    }
}
