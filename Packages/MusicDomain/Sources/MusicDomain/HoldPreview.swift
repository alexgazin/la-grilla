import Foundation

/// U67 · Four bars to hear while a template, style or beat card is held. Each preview is a small
/// throwaway project; nothing is saved and the current song is never touched.
public enum HoldPreview {
    public static let bars = 4

    /// The tempo a style is heard at when the card does not set one.
    public static func tempo(_ style: SketchStyle) -> Double {
        switch style {
        case .house: 124
        case .hipHop: 90
        case .jazz: 110
        }
    }

    /// A new-project template in the chosen key and tempo.
    public static func template(_ template: ProjectTemplate, bpm: Double, root: Int, minor: Bool) throws -> Project {
        try ProjectTemplates.make(name: "Preview", bpm: bpm, root: root, minor: minor, bars: bars, template: template)
    }

    /// A sketch in `style`: drums, chords, bass and a melody, composed locally.
    public static func style(_ style: SketchStyle, bpm: Double? = nil, root: Int, minor: Bool, seed: UInt32 = 1) throws -> Project {
        let empty = try ProjectTemplates.make(name: "Preview", bpm: bpm ?? tempo(style), root: root, minor: minor, bars: bars, template: .empty)
        guard let section = empty.sections.first else { throw MusicError.invalidProject }
        let plan = SketchPlan(style: style, bpm: bpm ?? tempo(style), root: root, minor: minor, bars: bars, seed: seed)
        return try SketchComposer.compose(empty, plan: plan, scope: section.id)
    }

    /// The first beat of a genre on its own kit (drums only, so it starts at once).
    public static func beat(_ genre: BeatPreset.Genre, root: Int, minor: Bool) throws -> (project: Project, kit: [(pad: Int, asset: SampleAsset, data: Data)]) {
        guard let preset = BeatPreset.presets(genre).first else { throw MusicError.invalidProject }
        return try beat(preset: preset, root: root, minor: minor)
    }

    /// U29 · One ready beat on its own kit, four bars at its tempo (drums only).
    public static func beat(preset: BeatPreset, root: Int, minor: Bool) throws -> (project: Project, kit: [(pad: Int, asset: SampleAsset, data: Data)]) {
        let draft = BeatDraft(preset)
        let empty = try ProjectTemplates.make(name: "Preview", bpm: Double(preset.bpm), root: root, minor: minor, bars: bars, template: .empty)
        let kit = try PaletteEngine.kit(draft.kit)
        let assets = Dictionary(uniqueKeysWithValues: kit.map { ($0.pad, $0.asset) })
        let project = try BeatMachine.candidate(empty, draft: draft, scope: .song, kit: assets, bass: nil)
        return (project, kit)
    }

    /// The part to loop: four bars from `start`, inside the song.
    public static func range(_ project: Project, from start: Int = 0) -> Range<Int> {
        let lower = max(0, min(start, max(0, project.length - barTicks)))
        return lower..<min(project.length, lower + bars * barTicks)
    }
}

/// U33 · What a held project card plays: about ten seconds of the chorus (or of the first section
/// when no section is called a chorus).
public enum ProjectPreview {
    public static let seconds = 10.0
    static let chorusNames = ["chorus", "припев", "refrain", "hook", "drop"]

    /// The section heard first: the first one named like a chorus, else the first section.
    public static func section(of project: Project) -> Section? {
        project.sections.first { section in
            let name = section.name.lowercased()
            return chorusNames.contains { name.contains($0) }
        } ?? project.sections.first
    }

    /// From the start of that section, at most `seconds` long at the song's tempo, whole beats.
    public static func range(_ project: Project, seconds: Double = seconds) -> Range<Int> {
        guard let section = section(of: project) else { return 0..<0 }
        let ticksPerSecond = project.bpm / 60 * Double(ppq)
        let wanted = max(ppq, Int((ticksPerSecond * seconds / Double(ppq)).rounded()) * ppq)
        return section.start..<min(section.start + section.length, section.start + wanted, project.length)
    }
}
