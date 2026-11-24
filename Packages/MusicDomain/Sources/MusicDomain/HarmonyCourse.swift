import Foundation

/// 54 · A chord by its place in the key: semitones above the key's root and what kind of chord.
public struct Degree: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case major, minor, diminished, dominant, major7, minor7, any }
    public var offset: Int
    public var kind: Kind
    public init(_ offset: Int, _ kind: Kind) { self.offset = ((offset % 12) + 12) % 12; self.kind = kind }

    public func matches(_ chord: Chord, keyRoot: Int) -> Bool {
        guard ((chord.root - keyRoot) % 12 + 12) % 12 == offset else { return false }
        let intervals = Set(chord.effectiveIntervals.map { (($0 % 12) + 12) % 12 })
        let majorThird = intervals.contains(4), minorThird = intervals.contains(3) && !intervals.contains(4)
        let perfectFifth = intervals.contains(7), flatFifth = intervals.contains(6) && !intervals.contains(7)
        switch kind {
        case .any: return true
        case .major: return majorThird && !flatFifth && !intervals.contains(8)
        case .minor: return minorThird && perfectFifth
        case .diminished: return minorThird && flatFifth
        case .dominant: return majorThird && intervals.contains(10)
        case .major7: return majorThird && intervals.contains(11)
        case .minor7: return minorThird && perfectFifth && intervals.contains(10)
        }
    }

    /// The plain chord for this degree in a key (for examples and hints).
    public func chord(keyRoot: Int) -> Chord {
        let quality: Quality = switch kind {
        case .major, .any: .major
        case .minor: .minor
        case .diminished: .dim
        case .dominant: .seventh
        case .major7: .maj7
        case .minor7: .m7
        }
        return Chord(root: (keyRoot + offset) % 12, quality: quality)
    }

    /// Roman numeral against the major scale (♭ for lowered degrees): I, ii, V7, ♭VI, vii°.
    public var roman: String {
        let names = ["I", "♭II", "II", "♭III", "III", "IV", "♯IV", "V", "♭VI", "VI", "♭VII", "VII"]
        var name = names[offset]
        if kind == .minor || kind == .diminished || kind == .minor7 { name = name.lowercased() }
        switch kind {
        case .diminished: name += "°"
        case .dominant: name += "7"
        case .major7: name += "maj7"
        case .minor7: name += "7"
        default: break
        }
        return name
    }
}

/// 54 · Tonic, subdominant and dominant: what a chord does in its key.
public enum ChordFunction: String, Codable, CaseIterable, Sendable {
    case tonic, subdominant, dominant
    public var title: String { switch self { case .tonic: "Tonic"; case .subdominant: "Subdominant"; case .dominant: "Dominant" } }
    public var letter: String { switch self { case .tonic: "T"; case .subdominant: "S"; case .dominant: "D" } }

    public static func of(_ chord: Chord, keyRoot: Int, minor: Bool) -> ChordFunction? {
        let offset = ((chord.root - keyRoot) % 12 + 12) % 12
        if minor {
            switch offset { case 0, 3, 8: return .tonic; case 2, 5: return .subdominant; case 7, 10, 11: return .dominant; default: return nil }
        }
        switch offset { case 0, 4, 9: return .tonic; case 2, 5: return .subdominant; case 7, 11: return .dominant; default: return nil }
    }
}

/// 54 · What an exercise asks of the song's chords (in the song's key, in playing order).
public enum ExerciseRule: Codable, Equatable, Sendable {
    /// These chords one after another somewhere in the song.
    case progression([Degree])
    /// The song ends on these chords.
    case ends([Degree])
    /// These functions one after another somewhere.
    case functions([ChordFunction])
    /// At least one of these chords somewhere.
    case contains([Degree])
    /// A chord with its third or fifth in the bass (an inversion or slash chord).
    case inversion
    /// At least this many chords.
    case chords(Int)

    /// English text; the app localizes it.
    public var title: String {
        switch self {
        case .progression(let degrees): String(format: NSLocalizedString("Play %@", comment: "Exercise rule"), degrees.map(\.roman).joined(separator: " – "))
        case .ends(let degrees): String(format: NSLocalizedString("End on %@", comment: "Exercise rule"), degrees.map(\.roman).joined(separator: " – "))
        case .functions(let functions): String(format: NSLocalizedString("Functions %@", comment: "Exercise rule"), functions.map(\.letter).joined(separator: " – "))
        case .contains(let degrees): String(format: NSLocalizedString("Use %@", comment: "Exercise rule"), degrees.map(\.roman).joined(separator: NSLocalizedString(" or ", comment: "Exercise rule")))
        case .inversion: NSLocalizedString("A chord with another note in the bass", comment: "Exercise rule")
        case .chords(let count): String(format: NSLocalizedString("At least %d chords", comment: "Exercise rule"), count)
        }
    }

    public func isMet(by project: Project) -> Bool {
        let chords = HarmonyCourse.chords(project)
        let key = project.keyRoot
        func run(_ degrees: [Degree], in list: [Chord]) -> Bool {
            guard !degrees.isEmpty, list.count >= degrees.count else { return false }
            return (0...(list.count - degrees.count)).contains { start in
                degrees.enumerated().allSatisfy { $0.element.matches(list[start + $0.offset], keyRoot: key) }
            }
        }
        switch self {
        case .progression(let degrees): return run(degrees, in: chords)
        case .ends(let degrees):
            guard chords.count >= degrees.count else { return false }
            return run(degrees, in: Array(chords.suffix(degrees.count)))
        case .functions(let wanted):
            let functions = chords.map { ChordFunction.of($0, keyRoot: key, minor: project.minor) }
            guard functions.count >= wanted.count else { return false }
            return (0...(functions.count - wanted.count)).contains { start in wanted.enumerated().allSatisfy { functions[start + $0.offset] == $0.element } }
        case .contains(let degrees): return chords.contains { chord in degrees.contains { $0.matches(chord, keyRoot: key) } }
        case .inversion: return chords.contains { $0.inversion > 0 || ($0.slashBass != nil && $0.slashBass != $0.root) }
        case .chords(let count): return chords.count >= count
        }
    }
}

/// 54 · One lesson: a short explanation, an example to hear and an exercise checked on the song.
public struct Lesson: Equatable, Sendable, Identifiable {
    public let id: String
    /// English; the app localizes each.
    public let title: String
    public let text: [String]
    public let minor: Bool
    public let example: [Degree]
    public let rules: [ExerciseRule]
    public let hint: String
}

public enum HarmonyCourse {
    /// The song's chords in playing order (muted clips are skipped).
    public static func chords(_ project: Project) -> [Chord] {
        Arrangement.harmony(project, section: Section(name: "Song", start: 0, length: max(barTicks, project.length)))
            .sorted { $0.tick < $1.tick }.map(\.chord)
    }

    /// A song in `root` playing the lesson's example, a bar a chord.
    public static func example(_ lesson: Lesson, root: Int) throws -> Project {
        var project = try ProjectTemplates.make(name: lesson.title, bpm: 90, root: root, minor: lesson.minor, bars: max(1, lesson.example.count), template: .empty)
        guard let harmony = project.tracks.firstIndex(where: { $0.role == .harmony }),
              let pattern = project.patterns.firstIndex(where: { $0.id == project.tracks[harmony].clips.first?.patternID }) else { throw MusicError.invalidProject }
        project.patterns[pattern].chords = lesson.example.enumerated().map { ChordEvent(tick: $0.offset * barTicks, chord: $0.element.chord(keyRoot: root)) }
        try project.validate()
        return project
    }

    /// An empty song in `root` with the lesson's exercise attached, for the student to fill.
    public static func workspace(_ lesson: Lesson, root: Int, name: String) throws -> Project {
        var project = try ProjectTemplates.make(name: name, bpm: 90, root: root, minor: lesson.minor, bars: max(4, lesson.example.count), template: .empty)
        project.harmonyAssignment = HarmonyAssignment(lesson: lesson, keyRoot: root, teacher: nil)
        try project.validate()
        return project
    }

    public static func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }

    public static let lessons: [Lesson] = [
        Lesson(id: "degrees", title: "Chords of a key", text: [
            "Every key has seven chords, one on each note of its scale. Roman numerals name them by place: I is the home chord, IV and V are its closest neighbours.",
            "Capitals are major chords, small letters are minor: in C major, I is C, ii is Dm, IV is F and V is G.",
        ], minor: false, example: [Degree(0, .major), Degree(5, .major), Degree(7, .major), Degree(0, .major)],
               rules: [.progression([Degree(0, .major), Degree(5, .major), Degree(7, .major), Degree(0, .major)])],
               hint: "Write I, IV, V and I again, a bar each."),
        Lesson(id: "functions", title: "Home, away, tension", text: [
            "Chords have jobs. The tonic (T) feels like home, the subdominant (S) moves away, the dominant (D) builds tension that wants to go home.",
            "Most music walks T – S – D – T. I, iii and vi act as tonic; ii and IV as subdominant; V and vii° as dominant.",
        ], minor: false, example: [Degree(9, .minor), Degree(2, .minor), Degree(7, .major), Degree(0, .major)],
               rules: [.functions([.tonic, .subdominant, .dominant, .tonic])],
               hint: "Any tonic, then any subdominant, then any dominant, then a tonic."),
        Lesson(id: "pop-four", title: "The four-chord song", text: [
            "I – V – vi – IV carries thousands of songs. Start it from vi and the same chords sound sad: vi – IV – I – V.",
            "Play it, then write a melody on top: the chords do half the work.",
        ], minor: false, example: [Degree(0, .major), Degree(7, .major), Degree(9, .minor), Degree(5, .major)],
               rules: [.progression([Degree(0, .major), Degree(7, .major), Degree(9, .minor), Degree(5, .major)])],
               hint: "I – V – vi – IV, a bar each."),
        Lesson(id: "minor-key", title: "The minor key", text: [
            "In a minor key the home chord is minor: i. Its natural v is minor too, and sounds soft.",
            "Make v major (V) and it pulls home much harder. That borrowed leading note is why minor songs so often use a major V.",
        ], minor: true, example: [Degree(0, .minor), Degree(5, .minor), Degree(7, .major), Degree(0, .minor)],
               rules: [.progression([Degree(5, .minor), Degree(7, .major), Degree(0, .minor)])],
               hint: "End with iv – V – i: the V must be major."),
        Lesson(id: "cadences", title: "Endings: cadences", text: [
            "How a phrase ends is a cadence. V – I closes like a full stop. IV – I is the softer “amen”. Ending on V leaves a question.",
            "The deceptive cadence goes V – vi: the ear expects home and lands somewhere else.",
        ], minor: false, example: [Degree(0, .major), Degree(5, .major), Degree(7, .major), Degree(9, .minor)],
               rules: [.ends([Degree(7, .major), Degree(9, .minor)])],
               hint: "Make the song end V – vi."),
        Lesson(id: "two-five-one", title: "ii – V – I with sevenths", text: [
            "Jazz runs on ii7 – V7 – Imaj7. Each chord's root falls a fifth to the next, and the sevenths slide down by step.",
            "Try it in a few keys: it is the most useful three chords in jazz.",
        ], minor: false, example: [Degree(2, .minor7), Degree(7, .dominant), Degree(0, .major7), Degree(0, .major7)],
               rules: [.progression([Degree(2, .minor7), Degree(7, .dominant), Degree(0, .major7)])],
               hint: "Dm7 – G7 – Cmaj7 in C, or the same places in your key."),
        Lesson(id: "secondary-dominant", title: "Borrowing a dominant", text: [
            "Any chord can have its own dominant. II as a major chord is “the V of V”: it points to V the way V points to I.",
            "Play II – V – I and listen to the extra push before V.",
        ], minor: false, example: [Degree(0, .major), Degree(2, .major), Degree(7, .major), Degree(0, .major)],
               rules: [.progression([Degree(2, .major), Degree(7, .major), Degree(0, .major)])],
               hint: "Make ii major (II), then V, then I."),
        Lesson(id: "borrowed", title: "Colours from the minor", text: [
            "A major-key song can borrow chords from its parallel minor: iv, ♭VI and ♭VII bring a bittersweet colour.",
            "I – ♭VI – ♭VII – I is the sound of film trailers and rock anthems.",
        ], minor: false, example: [Degree(0, .major), Degree(8, .major), Degree(10, .major), Degree(0, .major)],
               rules: [.contains([Degree(8, .major), Degree(10, .major), Degree(5, .minor)])],
               hint: "Use ♭VI, ♭VII or a minor iv somewhere."),
        Lesson(id: "inversions", title: "Smooth bass lines", text: [
            "An inversion puts another chord note in the bass: C/E is C with E at the bottom. The chord stays, the bass line moves by step.",
            "I – V⁶ – vi walks the bass down: C – G/B – Am.",
        ], minor: false, example: [Degree(0, .major), Degree(7, .major), Degree(9, .minor), Degree(5, .major)],
               rules: [.inversion, .chords(3)],
               hint: "Give one chord an inversion or a slash bass in the chord editor."),
        Lesson(id: "circle", title: "Round the circle of fifths", text: [
            "Roots falling by fifths sound inevitable: vi – ii – V – I goes A – D – G – C in C major.",
            "Keep falling and you pass through every chord of the key.",
        ], minor: false, example: [Degree(9, .minor), Degree(2, .minor), Degree(7, .major), Degree(0, .major)],
               rules: [.progression([Degree(9, .minor), Degree(2, .minor), Degree(7, .major), Degree(0, .major)])],
               hint: "vi – ii – V – I, a bar each."),
    ]
}

/// 54 · An exercise sent by a teacher (or opened from a lesson), checked on the device; a student
/// sends the song back with their name and the teacher sees the result.
public struct HarmonyAssignment: Codable, Equatable, Sendable {
    public var title: String
    public var lessonID: String?
    public var rules: [ExerciseRule]
    public var hint: String?
    public var keyRoot: Int
    public var minor: Bool
    public var teacher: String?
    public var student: String?
    public var submittedAt: Date?

    public init(title: String, rules: [ExerciseRule], keyRoot: Int, minor: Bool, lessonID: String? = nil, hint: String? = nil, teacher: String? = nil) {
        self.title = String(title.prefix(80)); self.rules = rules; self.keyRoot = keyRoot; self.minor = minor
        self.lessonID = lessonID; self.hint = hint; self.teacher = teacher.map { String($0.prefix(60)) }
    }

    public init(lesson: Lesson, keyRoot: Int, teacher: String?) {
        self.init(title: lesson.title, rules: lesson.rules, keyRoot: keyRoot, minor: lesson.minor, lessonID: lesson.id, hint: lesson.hint, teacher: teacher)
    }

    /// "Play my progression": the teacher's own chords (up to 8) become the exercise, in degrees.
    public static func progression(of project: Project, title: String, teacher: String?) -> HarmonyAssignment? {
        let chords = HarmonyCourse.chords(project).prefix(8)
        guard chords.count >= 2 else { return nil }
        let degrees = chords.map { chord -> Degree in
            let offset = chord.root - project.keyRoot
            let kinds: [Degree.Kind] = [.dominant, .major7, .minor7, .diminished, .minor, .major]
            let kind = kinds.first { Degree(offset, $0).matches(chord, keyRoot: project.keyRoot) } ?? .any
            return Degree(offset, kind)
        }
        return HarmonyAssignment(title: title, rules: [.progression(Array(degrees))], keyRoot: project.keyRoot, minor: project.minor, teacher: teacher)
    }

    public func check(_ project: Project) -> [(rule: ExerciseRule, met: Bool)] { rules.map { ($0, $0.isMet(by: project)) } }
    public func score(_ project: Project) -> (met: Int, total: Int) {
        let checks = check(project)
        return (checks.filter(\.met).count, checks.count)
    }

    /// The empty song the teacher shares: the key, enough bars and this assignment.
    public func project(name: String, bars: Int = 4) throws -> Project {
        var project = try ProjectTemplates.make(name: name, bpm: 90, root: keyRoot, minor: minor, bars: max(1, min(64, bars)), template: .empty)
        project.harmonyAssignment = self
        try project.validate()
        return project
    }

    public func validate() throws {
        guard !title.isEmpty, title.count <= 80, !rules.isEmpty, rules.count <= 8, (0..<12).contains(keyRoot) else { throw MusicError.invalidProject }
    }
}

/// 54 · A student's song the teacher opened: who, which assignment and how it went.
public struct AssignmentResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var student: String
    public var title: String
    public var met: Int
    public var total: Int
    public var submittedAt: Date
    public init?(_ project: Project) {
        guard let assignment = project.harmonyAssignment, let student = assignment.student, let date = assignment.submittedAt else { return nil }
        let score = assignment.score(project)
        id = project.id; self.student = student; title = assignment.title; met = score.met; total = score.total; submittedAt = date
    }
}
