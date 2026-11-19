import Foundation

/// I67 · the picture of a song for a vertical social video (1080×1920): a map
/// of every part's notes, the sections above it and a playhead that follows
/// the audio. Pure layout; the app draws and encodes it.
public struct VideoStoryboard: Sendable {
    public static let width = 1080.0, height = 1920.0
    public static let map = (x: 60.0, y: 560.0, width: 960.0, height: 900.0)

    public struct Block: Equatable, Sendable { public let x, y, width, height: Double; public let role: TrackRole }
    public struct Band: Equatable, Sendable { public let x, width: Double; public let name: String; public let colour: Int }

    public let fps: Int
    public let frames: Int
    public let blocks: [Block]
    public let sections: [Band]
    public let title: String
    public let subtitle: String
    private let range: Range<Int>
    private let musicSeconds: Double

    /// `seconds` is the audio file's duration (music plus any tail).
    public init(project: Project, range: Range<Int>, seconds: Double, fps: Int = 30) {
        self.fps = max(1, min(60, fps))
        self.range = range
        frames = max(1, Int((max(0, seconds) * Double(self.fps)).rounded(.up)))
        musicSeconds = Double(range.count) / Double(ppq) * 60 / project.bpm
        title = String(project.name.prefix(60))
        subtitle = "\(Int(project.bpm.rounded())) BPM · \(project.keyName)"
        let m = Self.map
        let span = Double(max(1, range.count))
        func x(_ tick: Int) -> Double { m.x + Double(tick - range.lowerBound) / span * m.width }
        let lanes = max(1, project.tracks.count), lane = m.height / Double(lanes)
        var blocks: [Block] = []
        let notes = Compiler.notes(project, range: range)
        for (index, track) in project.tracks.enumerated() {
            let own = notes.filter { $0.track == index }
            guard !own.isEmpty else { continue }
            let low = own.map(\.pitch).min()!, high = max(low + 11, own.map(\.pitch).max()!)
            let top = m.y + Double(index) * lane + 6, usable = lane - 12
            for note in own.prefix(4000) {
                let row: Double
                if note.pad >= 0 { row = Double(note.pad % 8) / 8 } else { row = 1 - Double(note.pitch - low) / Double(high - low) }
                let h = max(3, usable / (note.pad >= 0 ? 8 : Double(high - low + 1)))
                let start = x(note.tick + range.lowerBound)
                let w = max(3, Double(note.duration) / span * m.width)
                blocks.append(Block(x: start, y: top + row * (usable - h), width: min(w, m.x + m.width - start), height: h, role: track.role))
            }
        }
        self.blocks = blocks
        sections = project.sections.compactMap { s in
            let lo = max(range.lowerBound, s.start), hi = min(range.upperBound, s.start + s.length)
            guard hi > lo else { return nil }
            return Band(x: x(lo), width: x(hi) - x(lo), name: String(s.name.prefix(24)), colour: s.color ?? (project.sections.firstIndex { $0.id == s.id } ?? 0) % 4)
        }
    }

    /// Musical position shown on `frame`; holds at the end during the tail.
    public func tick(frame: Int) -> Double {
        let seconds = Double(max(0, frame)) / Double(fps)
        let progress = musicSeconds > 0 ? min(1, seconds / musicSeconds) : 1
        return Double(range.lowerBound) + progress * Double(range.count)
    }
    public func playheadX(frame: Int) -> Double {
        Self.map.x + (tick(frame: frame) - Double(range.lowerBound)) / Double(max(1, range.count)) * Self.map.width
    }
    public func section(frame: Int) -> Int? {
        let x = playheadX(frame: frame)
        return sections.lastIndex { x >= $0.x && x <= $0.x + $0.width + 0.001 }
    }
}
