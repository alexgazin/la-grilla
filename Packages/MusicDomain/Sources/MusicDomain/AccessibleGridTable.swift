import Foundation

/// U15 · The arrangement as a table for VoiceOver: one row per bar (with its section), one cell
/// per track — the chords that start in the bar, how many drum hits and melody notes it has.
public enum AccessibleGridTable {
    public struct Cell: Equatable, Sendable { public var track: String; public var text: String }
    public struct Row: Equatable, Identifiable, Sendable {
        public var bar: Int
        public var section: String
        public var cells: [Cell]
        public var id: Int { bar }
        /// "Bar 3, Verse. Harmony: Am. Drums: 8 hits."
        public var label: String {
            let head = String(format: NSLocalizedString("Bar %lld, %@", comment: "Grid table"), Int64(bar), section)
            return ([head] + cells.map { "\($0.track): \($0.text)" }).joined(separator: ". ") + "."
        }
    }

    public static func rows(_ project: Project, spelling: (Chord) -> String = { $0.symbol }) -> [Row] {
        let bars = max(1, project.length / barTicks)
        var rows: [Row] = []
        for bar in 0..<bars {
            let start = bar * barTicks
            let section = project.sections.first { $0.start <= start && start < $0.start + $0.length }?.name ?? ""
            var cells: [Cell] = []
            for track in project.tracks {
                let pattern = Arrangement.materialize(project, track: track, section: Section(name: "", start: start, length: barTicks))
                switch track.role {
                case .harmony:
                    let chords = pattern.chords.sorted { $0.tick < $1.tick }
                    let text = chords.isEmpty ? NSLocalizedString("no chord", comment: "Grid table")
                        : chords.map { spelling($0.chord) }.joined(separator: ", ")
                    cells.append(Cell(track: track.displayName, text: text))
                case .drums:
                    cells.append(Cell(track: track.displayName, text: String(format: NSLocalizedString("%lld hits", comment: "Grid table"), Int64(pattern.drums.count))))
                case .melody:
                    let count = (pattern.notes ?? []).count
                    cells.append(Cell(track: track.displayName, text: String(format: NSLocalizedString("%lld notes", comment: "Grid table"), Int64(count))))
                case .bass:
                    cells.append(Cell(track: track.displayName, text: NSLocalizedString("follows the chords", comment: "Grid table")))
                }
            }
            rows.append(Row(bar: bar + 1, section: section, cells: cells))
        }
        return rows
    }
}
