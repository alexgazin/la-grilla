import Foundation

/// 54 · Track in a minute: one tap on a genre makes a song you can play and post at once — the
/// genre's ready beat with its 808, chords, bass and a melody, as a verse and a chorus. Everything
/// is composed on the device and stays editable; nothing is downloaded.
public enum QuickTrack {
    /// Bars in each of the two sections.
    public static let sectionBars = 4

    /// The local composer's style closest to a genre (chords, bass and melody follow it; the beat
    /// always comes from the genre itself).
    public static func style(for genre: BeatPreset.Genre) -> SketchStyle {
        switch genre {
        case .trap, .drill, .boomBap, .westCoast, .lofi, .phonk, .rnb, .reggaeton: .hipHop
        case .jazz, .funk, .world: .jazz
        case .pop, .house, .techno, .garage, .dnb, .bass, .afro, .jersey, .rock, .synthwave, .electro, .chiptune: .house
        }
    }

    /// One of the genre's ready beats, chosen by `seed` so "Another one" gives a different beat.
    public static func preset(for genre: BeatPreset.Genre, seed: UInt32) -> BeatPreset? {
        let presets = BeatPreset.presets(genre)
        guard !presets.isEmpty else { return nil }
        return presets[Int(seed % UInt32(presets.count))]
    }

    /// The tempo the new project is created at.
    public static func tempo(for genre: BeatPreset.Genre, seed: UInt32) -> Double {
        Double(preset(for: genre, seed: seed)?.bpm ?? 120)
    }

    public struct Result: Sendable {
        public let project: Project
        /// Pads 0–15 of the kit, plus the 808 as pad -1 when the beat has one.
        public let sounds: [(pad: Int, asset: SampleAsset, data: Data)]
    }

    /// `base` is the empty project just created at `tempo(for:seed:)`, `sectionBars` long; the
    /// result keeps its id, so applying it is one undoable edit.
    public static func make(from base: Project, genre: BeatPreset.Genre, seed: UInt32) throws -> Result {
        guard let preset = preset(for: genre, seed: seed) else { throw MusicError.invalidProject }
        // The new project is made `sectionBars` long (one verse) at the genre's tempo.
        var empty = base
        empty.bpm = Double(preset.bpm)
        guard empty.length == sectionBars * barTicks, empty.sections.count == 1 else { throw MusicError.invalidProject }
        try empty.validate()
        guard let verse = empty.sections.first else { throw MusicError.invalidProject }
        let plan = SketchPlan(style: style(for: genre), bpm: Double(preset.bpm), root: empty.keyRoot, minor: empty.minor,
                              bars: sectionBars, seed: seed &+ 1)
        var song = try SketchComposer.compose(empty, plan: plan, scope: verse.id)
        try song.duplicateSection(verse.id, name: "Chorus")
        let draft = BeatDraft(preset)
        let kit = try PaletteEngine.kit(draft.kit)
        var sounds = kit
        var bass: SampleAsset?
        if let synth = draft.bass, !draft.bassNotes.isEmpty {
            let made = try synth.asset()
            bass = made.asset
            sounds.append((pad: -1, asset: made.asset, data: made.data))
        }
        let assets = Dictionary(uniqueKeysWithValues: kit.map { ($0.pad, $0.asset) })
        song = try BeatMachine.candidate(song, draft: draft, scope: .song, kit: assets, bass: bass,
                                         options: .init(useTempo: true, muteChordBass: bass != nil))
        try song.validate()
        return Result(project: song, sounds: sounds)
    }
}

/// 54 · The part of a song a social clip uses: whole bars from the chorus (or the first section),
/// about 15, 30 or 60 seconds, never past the end of the song.
public enum ShareClip {
    public enum Length: Int, CaseIterable, Sendable, Identifiable {
        case whole = 0, short = 15, medium = 30, long = 60
        public var id: Int { rawValue }
        public var title: String {
            switch self { case .whole: "Whole song"; case .short: "15 s"; case .medium: "30 s"; case .long: "60 s" }
        }
    }

    public static func range(_ project: Project, length: Length) -> Range<Int> {
        guard length != .whole, project.length > 0 else { return 0..<project.length }
        let start = ProjectPreview.section(of: project)?.start ?? 0
        let ticksPerSecond = project.bpm / 60 * Double(ppq)
        let wantedBars = max(1, Int((ticksPerSecond * Double(length.rawValue) / Double(barTicks)).rounded()))
        let wanted = wantedBars * barTicks
        // Not enough song after the chorus: move the start back so the clip is as long as it can be.
        let lower = max(0, min(start, project.length - wanted))
        return lower..<min(project.length, lower + wanted)
    }

    /// The clip's length in seconds at the song's tempo.
    public static func seconds(_ project: Project, range: Range<Int>) -> Double {
        Double(range.count) / Double(ppq) * 60 / max(1, project.bpm)
    }
}

/// 54 · How a social video draws the music.
public enum VideoStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Every part's notes on a map with a playhead (I67).
    case map
    /// A 4×4 pad grid that lights with the drums, chords glowing behind it.
    case pads
    /// One bar per track that rises with what that track plays.
    case levels
    public var id: String { rawValue }
    public var title: String {
        switch self { case .map: "Note map"; case .pads: "Pads"; case .levels: "Levels" }
    }
}

extension VideoStoryboard {
    /// How loud each track is on `frame` (0…1): sounding notes by velocity, with a short release.
    public func levels(frame: Int) -> [Double] {
        let now = tick(frame: frame)
        let release = Double(ppq) / 4
        var levels = Array(repeating: 0.0, count: trackCount)
        for event in events where Double(event.tick) <= now && now < Double(event.tick + event.duration) + release {
            let end = Double(event.tick + event.duration)
            let fade = now <= end ? 1 : max(0, 1 - (now - end) / release)
            levels[event.track] = max(levels[event.track], Double(event.velocity) / 127 * fade)
        }
        return levels
    }

    /// Drum pads struck within the last sixteenth on `frame`, with how bright each still is (0…1).
    public func pads(frame: Int) -> [Int: Double] {
        let now = tick(frame: frame)
        let glow = Double(ppq) / 4
        var lit: [Int: Double] = [:]
        for event in events where event.pad >= 0 && Double(event.tick) <= now && now < Double(event.tick) + glow {
            let brightness = (1 - (now - Double(event.tick)) / glow) * Double(event.velocity) / 127
            lit[event.pad % 16] = max(lit[event.pad % 16] ?? 0, brightness)
        }
        return lit
    }
}
