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
