import Foundation

/// I38 · "Song dynamics": the same parts, thinned and filled so the song breathes — a
/// sparse intro, a lighter verse, a full chorus with a crash, a contrasting bridge and a
/// thinner outro. Only drums and melodic tracks change; chords stay; locked tracks stay.
public enum ArrangementDynamics {
    public enum Role: String, CaseIterable, Codable, Sendable {
        case intro, verse, preChorus, chorus, bridge, outro, keep
        public var title: String {
            switch self {
            case .intro: "Intro"
            case .verse: "Verse"
            case .preChorus: "Pre-chorus"
            case .chorus: "Chorus"
            case .bridge: "Bridge"
            case .outro: "Outro"
            case .keep: "Leave as is"
            }
        }
        /// Relative energy, used to explain the plan.
        public var energy: Int {
            switch self { case .intro, .outro: 1; case .bridge: 2; case .verse: 2; case .preChorus: 3; case .chorus: 4; case .keep: 3 }
        }
    }

    /// A role from the section's name, or from its place when the name says nothing.
    public static func role(of section: Section, index: Int, count: Int) -> Role {
        let name = section.name.lowercased()
        let words: [(Role, [String])] = [
            (.preChorus, ["pre-chorus", "prechorus", "pre chorus", "предприпев", "пред-припев"]),
            (.intro, ["intro", "интро", "вступ"]),
            (.chorus, ["chorus", "hook", "припев", "хук", "drop", "дроп"]),
            (.bridge, ["bridge", "бридж", "переход", "breakdown", "проигрыш"]),
            (.outro, ["outro", "аутро", "кода", "концовк", "ending", "end"]),
            (.verse, ["verse", "куплет"]),
        ]
        if let match = words.first(where: { $0.1.contains(where: name.contains) }) { return match.0 }
        if count >= 3 && index == 0 { return .intro }
        if count >= 4 && index == count - 1 { return .outro }
        return index % 2 == 0 ? .verse : .chorus
    }

    public static func plan(_ project: Project) -> [UUID: Role] {
        Dictionary(uniqueKeysWithValues: project.sections.enumerated().map { ($0.element.id, role(of: $0.element, index: $0.offset, count: project.sections.count)) })
    }

    /// The song with dynamics applied by role (`roles` overrides the automatic plan).
    public static func apply(_ project: Project, roles: [UUID: Role]? = nil) throws -> Project {
        try project.validate()
        let plan = roles ?? self.plan(project)
        var result = project
        for section in project.sections {
            let role = plan[section.id] ?? .keep
            guard role != .keep else { continue }
            for (index, track) in project.tracks.enumerated() where track.locked != true {
                switch track.role {
                case .drums:
                    var pattern = Arrangement.materialize(result, track: result.tracks[index], section: section)
                    guard !pattern.drums.isEmpty else { continue }
                    pattern.drums = shape(pattern.drums, role: role, length: section.length)
                    pattern.drumTakes = pattern.drumTakes?.filter { take in pattern.drums.contains { $0.take == take.id } }
                    if pattern.drumTakes?.isEmpty == true { pattern.drumTakes = nil }
                    BeatMachine.place(pattern, on: index, section: section, in: &result)
                case .melody where role == .intro:
                    // The intro leaves the melody out; it enters with the first verse.
                    clear(track: index, section: section, in: &result)
                case .melody where role == .bridge || role == .outro:
                    var pattern = Arrangement.materialize(result, track: result.tracks[index], section: section)
                    guard !(pattern.notes ?? []).isEmpty else { continue }
                    pattern.notes = pattern.notes?.map { var note = $0; note.velocity = max(1, note.velocity * 3 / 4); return note }
                    BeatMachine.place(pattern, on: index, section: section, in: &result)
                default:
                    continue
                }
            }
        }
        result.removeUnusedPatterns()
        try result.validate()
        return result
    }

    /// Pads: 0 kick, 1 snare, 2/3 hats, 4 clap, 5 rim, 9 crash, 10 ride, 11–15 percussion.
    static func shape(_ hits: [DrumEvent], role: Role, length: Int) -> [DrumEvent] {
        func scaled(_ hit: DrumEvent, _ factor: Double) -> DrumEvent {
            var copy = hit; copy.velocity = max(1, min(127, Int((Double(hit.velocity) * factor).rounded()))); return copy
        }
        switch role {
        case .intro, .outro:
            // Only the top: hats, rim and shakers, a little softer; the kick on each bar's one.
            return hits.compactMap { hit in
                if [2, 5, 11, 13, 14].contains(hit.pad) { return scaled(hit, 0.8) }
                if hit.pad == 0 && hit.tick % barTicks == 0 { return scaled(hit, 0.85) }
                return nil
            }
        case .verse:
            return hits.compactMap { hit in [3, 9].contains(hit.pad) ? nil : scaled(hit, 0.92) }
        case .bridge:
            // Half-time contrast: kick on the one, snare on three, hats on quarters.
            return hits.compactMap { hit in
                let inBar = hit.tick % barTicks
                switch hit.pad {
                case 0: return inBar == 0 ? hit : nil
                case 1, 4: return inBar == 2 * ppq ? hit : nil
                case 2, 10: return inBar % ppq == 0 ? scaled(hit, 0.85) : nil
                case 9: return nil
                default: return scaled(hit, 0.8)
                }
            }
        case .preChorus:
            return hits.filter { $0.pad != 9 }
        case .chorus:
            var full = hits
            if !hits.contains(where: { $0.pad == 9 && $0.tick == 0 }) {
                full.append(DrumEvent(tick: 0, pad: 9, velocity: 110))
            }
            return full.sorted { ($0.tick, $0.pad) < ($1.tick, $1.pad) }
        case .keep:
            return hits
        }
    }

    /// Removes what a track plays inside a section, splitting clips that cross it.
    static func clear(track: Int, section: Section, in project: inout Project) {
        let start = section.start, end = section.start + section.length
        var clips: [Clip] = []
        for clip in project.tracks[track].clips {
            let clipEnd = clip.start + clip.length
            guard clip.start < end && clipEnd > start else { clips.append(clip); continue }
            if clip.start < start { var before = clip; before.length = start - clip.start; clips.append(before) }
            if clipEnd > end, let source = project.patterns.first(where: { $0.id == clip.patternID }) {
                var after = clip
                after.id = UUID(); after.start = end; after.length = clipEnd - end
                after.offset = (clip.offset + (end - clip.start)) % max(1, source.length)
                clips.append(after)
            }
        }
        project.tracks[track].clips = clips
    }

    /// Drum hits per bar in each section, to show (and test) the shape of the song.
    public static func density(_ project: Project) -> [UUID: Double] {
        let notes = Compiler.notes(project)
        return Dictionary(uniqueKeysWithValues: project.sections.map { section in
            let hits = notes.filter { $0.pad >= 0 && $0.tick >= section.start && $0.tick < section.start + section.length }.count
            return (section.id, Double(hits) / Double(max(1, section.length / barTicks)))
        })
    }
}
