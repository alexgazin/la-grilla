import Foundation

/// I20 · Song structure from a template or from timings of a reference song.
public struct FormTemplate: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let sections: [(name: String, bars: Int)]
    public static func == (a: FormTemplate, b: FormTemplate) -> Bool { a.id == b.id }

    public static let all: [FormTemplate] = [
        .init(id: "pop", title: "Pop song", sections: [("Intro", 4), ("Verse", 8), ("Pre-chorus", 4), ("Chorus", 8), ("Verse", 8), ("Pre-chorus", 4), ("Chorus", 8), ("Bridge", 8), ("Chorus", 8), ("Outro", 4)]),
        .init(id: "hiphop", title: "Hip-hop", sections: [("Intro", 4), ("Verse", 16), ("Chorus", 8), ("Verse", 16), ("Chorus", 8), ("Outro", 4)]),
        .init(id: "lofi", title: "Lo-fi loop", sections: [("Intro", 4), ("Verse", 8), ("Verse", 8), ("Break", 4), ("Verse", 8), ("Outro", 4)]),
        .init(id: "edm", title: "EDM build and drop", sections: [("Intro", 8), ("Break", 4), ("Pre-chorus", 4), ("Drop", 16), ("Break", 8), ("Pre-chorus", 4), ("Drop", 16), ("Outro", 4)]),
        .init(id: "short", title: "Short idea", sections: [("Verse", 4), ("Chorus", 4), ("Verse", 4), ("Chorus", 4)]),
    ]
}

public enum FormFromTimings {
    /// Section lengths from the start times (seconds) of a reference song's parts.
    /// Each length is rounded to 2, 4 or a multiple of 4 bars; at most 16 sections.
    public static func bars(starts: [Double], end: Double, bpm: Double, beatsPerBar: Double = 4) -> [Int] {
        let times = (starts + [end]).sorted()
        guard bpm > 0, times.count >= 2 else { return [] }
        let barSeconds = 60 / bpm * beatsPerBar
        var result: [Int] = []
        for (a, b) in zip(times, times.dropFirst()) where b > a {
            let raw = (b - a) / barSeconds
            let rounded = raw < 3 ? 2 : Int((raw / 4).rounded()) * 4
            result.append(max(2, rounded))
        }
        return Array(result.prefix(maximumSections))
    }
}

public enum FormEditing {
    /// Lays the template over a song. An empty song is rebuilt with exactly these
    /// sections; a song with music keeps every existing section (renamed in order)
    /// and gets the remaining sections appended, within the song limits.
    public static func apply(_ sections: [(name: String, bars: Int)], to project: inout Project) throws {
        guard !sections.isEmpty else { return }
        let hasMusic = project.patterns.contains { !$0.chords.isEmpty || !$0.drums.isEmpty || !($0.notes ?? []).isEmpty }
        var candidate = project
        if !hasMusic {
            var fresh = Project(name: project.name, bars: max(1, sections[0].bars))
            fresh.id = project.id; fresh.revision = project.revision; fresh.bpm = project.bpm; fresh.keyRoot = project.keyRoot; fresh.minor = project.minor
            fresh.tracks = fresh.tracks.enumerated().map { index, track in
                guard index < project.tracks.count else { return track }
                var kept = project.tracks[index]; kept.clips = track.clips; return kept
            }
            // Keep extra tracks (bass, melody) with clips for the first section.
            for track in project.tracks.dropFirst(2) {
                var kept = track
                if track.role != .bass {
                    let pattern = Pattern(length: fresh.sections[0].length)
                    fresh.patterns.append(pattern)
                    kept.clips = [Clip(patternID: pattern.id, start: 0, length: pattern.length)]
                } else { kept.clips = [] }
                fresh.tracks.append(kept)
            }
            fresh.sections[0].name = NSLocalizedString(sections[0].name, comment: "Section name")
            for section in sections.dropFirst() {
                try SectionEditing.append(name: NSLocalizedString(section.name, comment: "Section name"), bars: section.bars, to: &fresh)
            }
            candidate = fresh
        } else {
            for (index, section) in sections.enumerated() {
                if index < candidate.sections.count { candidate.sections[index].name = NSLocalizedString(section.name, comment: "Section name") }
                else { try SectionEditing.append(name: NSLocalizedString(section.name, comment: "Section name"), bars: section.bars, to: &candidate) }
            }
        }
        try candidate.validate()
        project = candidate
    }
}
