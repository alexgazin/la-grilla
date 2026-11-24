import Foundation

/// 54 · A challenge for the week: a few musical rules a song is checked against on the device.
/// The same week gives everyone the same challenge, with no server; finished songs are shared as a
/// clip with the challenge's tag.
public struct WeeklyChallenge: Equatable, Sendable, Identifiable {
    public enum Rule: Equatable, Sendable {
        case tempo(ClosedRange<Int>)
        case mode(minor: Bool)
        case atMostChords(Int)
        case atLeastChords(Int)
        case quality(Quality)
        case melody
        case atLeastBars(Int)
        case atLeastSections(Int)
        case drumHits(atLeast: Int)
        case borrowedChord

        /// English text; the app localizes it.
        public var title: String {
            switch self {
            case .tempo(let range): String(format: NSLocalizedString("Tempo %d–%d BPM", comment: "Challenge rule"), range.lowerBound, range.upperBound)
            case .mode(let minor): NSLocalizedString(minor ? "A minor key" : "A major key", comment: "Challenge rule")
            case .atMostChords(let count): String(format: NSLocalizedString("At most %d different chords", comment: "Challenge rule"), count)
            case .atLeastChords(let count): String(format: NSLocalizedString("At least %d different chords", comment: "Challenge rule"), count)
            case .quality(let quality): String(format: NSLocalizedString("A %@ chord somewhere", comment: "Challenge rule"), quality.rawValue.isEmpty ? "major" : quality.rawValue)
            case .melody: NSLocalizedString("A melody", comment: "Challenge rule")
            case .atLeastBars(let bars): String(format: NSLocalizedString("At least %d bars", comment: "Challenge rule"), bars)
            case .atLeastSections(let count): String(format: NSLocalizedString("At least %d sections", comment: "Challenge rule"), count)
            case .drumHits(let count): String(format: NSLocalizedString("A beat with at least %d hits", comment: "Challenge rule"), count)
            case .borrowedChord: NSLocalizedString("A chord borrowed from the other mode", comment: "Challenge rule")
            }
        }
    }

    public let id: String
    /// English title; the app localizes it.
    public let title: String
    public let idea: String
    public let rules: [Rule]
    public var tag: String { "#LaGrilla" + id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined() }

    /// The challenge of the week containing `date` (ISO weeks, the same everywhere).
    public static func current(_ date: Date = Date()) -> WeeklyChallenge {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let week = calendar.component(.weekOfYear, from: date), year = calendar.component(.yearForWeekOfYear, from: date)
        return all[(year * 53 + week) % all.count]
    }

    public struct Check: Equatable, Sendable { public let rule: Rule; public let met: Bool }

    public func check(_ project: Project) -> [Check] { rules.map { Check(rule: $0, met: Self.meets($0, project)) } }
    public func isComplete(_ project: Project) -> Bool { check(project).allSatisfy(\.met) }

    static func meets(_ rule: Rule, _ project: Project) -> Bool {
        let chords = Self.chords(project)
        switch rule {
        case .tempo(let range): return range.contains(Int(project.bpm.rounded()))
        case .mode(let minor): return project.minor == minor
        case .atMostChords(let count): return !chords.isEmpty && Set(chords.map(Self.name)).count <= count
        case .atLeastChords(let count): return Set(chords.map(Self.name)).count >= count
        case .quality(let quality): return chords.contains { $0.quality == quality }
        case .melody:
            return project.tracks.enumerated().contains { index, track in
                track.role == .melody && Compiler.notes(project).contains { $0.track == index }
            }
        case .atLeastBars(let bars): return project.length >= bars * barTicks
        case .atLeastSections(let count): return project.sections.count >= count
        case .drumHits(let count): return Compiler.notes(project).filter { $0.pad >= 0 }.count >= count
        case .borrowedChord:
            // A chord whose root is outside the key's own scale degrees, or the parallel mode's.
            let scale = project.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
            let other = project.minor ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
            return chords.contains { chord in
                let degree = ((chord.root - project.keyRoot) % 12 + 12) % 12
                return !scale.contains(degree) && other.contains(degree)
            }
        }
    }

    static func chords(_ project: Project) -> [Chord] {
        guard let harmony = project.tracks.first(where: { $0.role == .harmony }) else { return [] }
        let used = Set(harmony.clips.filter { $0.muted != true }.map(\.patternID))
        return project.patterns.filter { used.contains($0.id) }.flatMap { $0.chords.map(\.chord) }
    }
    static func name(_ chord: Chord) -> String { "\(chord.root)-\(chord.quality.rawValue)" }

    /// 26 challenges, one a week, then round again.
    public static let all: [WeeklyChallenge] = [
        .init(id: "four-chords", title: "Four chords, one hook", idea: "Most hits use four chords. Write yours and make the melody carry it.",
              rules: [.atMostChords(4), .melody, .atLeastBars(8)]),
        .init(id: "night-drive", title: "Night drive", idea: "Phonk or synthwave for an empty road.", rules: [.tempo(80...130), .mode(minor: true), .drumHits(atLeast: 24)]),
        .init(id: "sunrise", title: "Sunrise", idea: "A bright major tune that grows in the chorus.", rules: [.mode(minor: false), .atLeastSections(2), .melody]),
        .init(id: "jazz-seven", title: "Sevenths only", idea: "Give every chord a seventh and listen to the colour.", rules: [.quality(.maj7), .quality(.m7), .atLeastChords(3)]),
        .init(id: "slow-jam", title: "Slow jam", idea: "R&B under 80 BPM with room to breathe.", rules: [.tempo(60...80), .melody, .drumHits(atLeast: 12)]),
        .init(id: "club-ready", title: "Club ready", idea: "House or techno that keeps a dance floor moving.", rules: [.tempo(120...130), .drumHits(atLeast: 48), .atLeastBars(8)]),
        .init(id: "borrowed", title: "Borrowed colour", idea: "Take one chord from the other mode, like ♭VI in a major key.", rules: [.borrowedChord, .atLeastChords(3)]),
        .init(id: "two-chords", title: "Two chords", idea: "Only two chords — the beat and the melody do the rest.", rules: [.atMostChords(2), .melody, .drumHits(atLeast: 16)]),
        .init(id: "drill-time", title: "Drill time", idea: "Sliding 808s and a sharp minor melody.", rules: [.tempo(138...146), .mode(minor: true), .melody]),
        .init(id: "lofi-study", title: "Study beat", idea: "Lo-fi for homework: soft, warm, unhurried.", rules: [.tempo(70...90), .quality(.m7), .drumHits(atLeast: 12)]),
        .init(id: "verse-chorus", title: "Verse and chorus", idea: "Make the chorus feel different from the verse.", rules: [.atLeastSections(2), .atLeastBars(8), .melody]),
        .init(id: "minor-ballad", title: "Minor ballad", idea: "A sad song with a hopeful last chord.", rules: [.mode(minor: true), .tempo(60...90), .atLeastChords(4)]),
        .init(id: "fast-lane", title: "Fast lane", idea: "Drum & bass energy at 170 BPM.", rules: [.tempo(160...178), .drumHits(atLeast: 48)]),
        .init(id: "suspense", title: "Suspense", idea: "Hold the tension with suspended chords.", rules: [.quality(.sus4), .atLeastChords(3)]),
        .init(id: "afro-sun", title: "Afro sun", idea: "Afrobeats or amapiano with a bouncing bass.", rules: [.tempo(100...118), .drumHits(atLeast: 32), .melody]),
        .init(id: "eight-bars", title: "Eight bars of story", idea: "Tell a whole little story in eight bars.", rules: [.atLeastBars(8), .melody, .atLeastChords(3)]),
        .init(id: "funky", title: "Funky", idea: "Ninths and a busy beat.", rules: [.quality(.ninth), .drumHits(atLeast: 32)]),
        .init(id: "chiptune", title: "Level one", idea: "An 8-bit tune for a game that does not exist yet.", rules: [.tempo(120...160), .mode(minor: false), .melody]),
        .init(id: "three-parts", title: "Three parts", idea: "Intro, verse and chorus — a whole song shape.", rules: [.atLeastSections(3), .atLeastBars(12)]),
        .init(id: "dark-trap", title: "Dark trap", idea: "Half-time drums and a minor key.", rules: [.tempo(130...150), .mode(minor: true), .drumHits(atLeast: 24)]),
        .init(id: "major-seven", title: "Dreamy", idea: "Major sevenths for a soft, floating mood.", rules: [.quality(.maj7), .mode(minor: false), .melody]),
        .init(id: "no-drums-groove", title: "Groove without drums", idea: "Make it move with chords, bass and melody only.", rules: [.melody, .atLeastChords(3), .atLeastBars(8)]),
        .init(id: "reggaeton", title: "Dembow", idea: "The reggaeton rhythm and a catchy minor hook.", rules: [.tempo(88...100), .mode(minor: true), .drumHits(atLeast: 24)]),
        .init(id: "big-chorus", title: "Big chorus", idea: "Make the chorus the moment everyone waits for.", rules: [.atLeastSections(2), .atLeastChords(4), .melody]),
        .init(id: "diminished", title: "A little danger", idea: "Slip a diminished chord in on the way somewhere.", rules: [.quality(.dim), .atLeastChords(4)]),
        .init(id: "remix-it", title: "Remix it", idea: "Take a friend's song with Make your version and change its mood.", rules: [.atLeastBars(8), .melody, .drumHits(atLeast: 16)]),
    ]
}
