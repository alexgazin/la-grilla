import Foundation

/// I64 · Mix presets: a single, undoable change of the master EQ and the
/// lead/bass balance for a listening situation. Notes and sounds never change.
public enum MixPreset: String, CaseIterable, Sendable {
    case phoneSpeaker, club, background
    public var title: String {
        switch self { case .phoneSpeaker: "Phone speaker"; case .club: "Club"; case .background: "Background" }
    }
    public var detail: String {
        switch self {
        case .phoneSpeaker: "Cuts sub-bass the speaker cannot play and brings the melody forward."
        case .club: "Fuller low end and a softer top for large speakers."
        case .background: "Quieter lead and a smoother top for listening under speech."
        }
    }
    public func applied(to project: Project) throws -> Project {
        var result = project
        var eq = StudioEQ()
        switch self {
        case .phoneSpeaker: eq.bands = [EQBand(.highPass, 90, 0, 0.707), EQBand(.bell, 300, -1.5, 1), EQBand(.bell, 2800, 2.5, 1), EQBand(.highShelf, 9000, 1)]
        case .club: eq.bands = [EQBand(.lowShelf, 70, 3), EQBand(.bell, 350, -1.5, 1), EQBand(.bell, 2500, 0, 1), EQBand(.highShelf, 9000, -1.5)]
        case .background: eq.bands = [EQBand(.lowShelf, 100, -1), EQBand(.bell, 420, 0, 1), EQBand(.bell, 3000, -2.5, 1), EQBand(.highShelf, 8000, -3)]
        }
        result.masterEQ = eq
        for i in result.tracks.indices where PaletteEngine.slot(of: result.tracks[i]) == .lead {
            let delta: Double = self == .phoneSpeaker ? 1.5 : self == .background ? -4 : 0
            result.tracks[i].gain = min(6, max(-60, result.tracks[i].gain + delta))
        }
        try result.validate()
        return result
    }
}

/// I31 · Song form templates over the open song: sections reuse the current
/// sections' rhythm and melody sources and their chords (applied through the
/// existing whole-song arrangement review, one Undo).
public enum SongFormTemplate: String, CaseIterable, Sendable {
    case pop, hipHop, house, ambient
    public var title: String {
        switch self { case .pop: "Pop: verse–chorus"; case .hipHop: "Hip-hop: intro–verse–hook"; case .house: "House: build and drop"; case .ambient: "Ambient: slow arc" }
    }
    /// (name, bars, index of the source section by role: 0 = first, 1 = second, …)
    public var layout: [(name: String, bars: Int, source: Int)] {
        switch self {
        case .pop: [("Intro", 4, 0), ("Verse", 8, 0), ("Chorus", 8, 1), ("Verse", 8, 0), ("Chorus", 8, 1), ("Bridge", 4, 0), ("Chorus", 8, 1)]
        case .hipHop: [("Intro", 4, 0), ("Verse", 16, 0), ("Hook", 8, 1), ("Verse", 16, 0), ("Hook", 8, 1), ("Outro", 4, 0)]
        case .house: [("Intro", 8, 0), ("Build", 8, 0), ("Drop", 16, 1), ("Break", 8, 0), ("Drop", 16, 1), ("Outro", 8, 0)]
        case .ambient: [("Intro", 8, 0), ("Theme", 16, 1), ("Drift", 16, 0), ("Theme", 8, 1), ("Fade", 8, 0)]
        }
    }

    /// Whole-song sections within the 64-bar / 8-section limits, as an Assistant proposal.
    public func proposal(for project: Project) throws -> AssistantProposal {
        try project.validate()
        var parts: [AssistantSongSection] = []
        var total = 0
        for item in layout {
            guard parts.count < maximumSections, total + item.bars <= maximumSongBars else { break }
            let source = project.sections[min(item.source, project.sections.count - 1)]
            let harmony = Arrangement.harmony(project, section: source)
            var chords: [Chord] = [], durations: [Int] = []
            if harmony.isEmpty {
                chords = [Chord(root: project.keyRoot, quality: project.minor ? .minor : .major)]; durations = [item.bars]
            } else {
                // Repeat the source's chord cycle bar by bar to fill the new length.
                let cycle = harmony.map { ($0.chord, max(1, $0.duration / barTicks)) }
                var bars = 0, i = 0
                while bars < item.bars {
                    let length = min(cycle[i % cycle.count].1, item.bars - bars)
                    chords.append(cycle[i % cycle.count].0); durations.append(length); bars += length; i += 1
                }
            }
            parts.append(AssistantSongSection(name: NSLocalizedString(item.name, comment: "Song form template section"), bars: item.bars, chords: chords, durations: durations, sourceSectionID: source.id))
            total += item.bars
        }
        let scope = project.sections[0].id
        return AssistantProposal(project: project, scope: scope, operations: [AssistantOperation(.arrangeSong, sections: parts)])
    }
}
