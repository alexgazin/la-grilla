import Foundation

/// I75 · Import a Standard MIDI File (format 0 or 1) as a new editable project.
/// Channel 10 becomes the drum pattern (GM drum notes mapped to the 16 pads);
/// every other channel with notes becomes a melody track named after its MIDI
/// track. Tempo, key signature and section markers are read when present.
/// Bounded: up to 64 bars, 6 melodic tracks and 4096 events per part; data
/// beyond the limits is reported, never silently reinterpreted.
public enum MIDIFileImport {
    public enum Failure: Error, LocalizedError, Equatable {
        case notMIDI, unsupportedFormat, noNotes, damaged
        public var errorDescription: String? {
            let key = switch self {
            case .notMIDI: "This file is not a Standard MIDI File."
            case .unsupportedFormat: "Only MIDI format 0 and 1 files with musical time can be imported."
            case .noNotes: "This MIDI file contains no notes."
            case .damaged: "This MIDI file is damaged."
            }
            return NSLocalizedString(key, comment: "MIDI import")
        }
    }

    public struct Result: Sendable {
        public var project: Project
        /// Notes dropped because they were beyond 64 bars or the per-part limit.
        public var droppedNotes: Int
        /// Melodic channels beyond the track limit that were not imported.
        public var droppedChannels: Int
        /// The imported project as an installable bundle (no audio assets).
        public var bundle: PortableProjectBundle { PortableProjectBundle(project: project, assets: [:]) }
    }

    struct RawNote { var tick: Int; var duration: Int; var pitch: Int; var velocity: Int; var channel: Int; var track: Int }

    public static func read(_ data: Data, name: String = "Imported MIDI") throws -> Result {
        guard data.count <= 4_000_000 else { throw Failure.damaged }
        let bytes = [UInt8](data)
        var cursor = 0
        func u32() throws -> Int { guard cursor + 4 <= bytes.count else { throw Failure.damaged }; defer { cursor += 4 }; return Int(bytes[cursor]) << 24 | Int(bytes[cursor + 1]) << 16 | Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3]) }
        func u16() throws -> Int { guard cursor + 2 <= bytes.count else { throw Failure.damaged }; defer { cursor += 2 }; return Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1]) }
        guard bytes.count >= 14, String(decoding: bytes[0..<4], as: UTF8.self) == "MThd" else { throw Failure.notMIDI }
        cursor = 4
        let headerLength = try u32()
        let format = try u16(), trackCount = try u16(), division = try u16()
        guard headerLength >= 6, [0, 1].contains(format), division & 0x8000 == 0, division > 0, (1...64).contains(trackCount) else { throw Failure.unsupportedFormat }
        cursor = 8 + headerLength
        let scale = Double(ppq) / Double(division)
        var notes: [RawNote] = [], trackNames: [Int: String] = [:]
        var tempo: Double?, key: (root: Int, minor: Bool)?, markers: [(Int, String)] = []
        for track in 0..<trackCount {
            guard cursor + 8 <= bytes.count, String(decoding: bytes[cursor..<cursor + 4], as: UTF8.self) == "MTrk" else { throw Failure.damaged }
            cursor += 4
            let length = try u32(), end = cursor + length
            guard end <= bytes.count else { throw Failure.damaged }
            var tick = 0, status: UInt8 = 0
            var open: [Int: [(tick: Int, velocity: Int)]] = [:]
            func vlq() throws -> Int {
                var value = 0
                for _ in 0..<4 {
                    guard cursor < end else { throw Failure.damaged }
                    let byte = bytes[cursor]; cursor += 1
                    value = value << 7 | Int(byte & 0x7f)
                    if byte & 0x80 == 0 { return value }
                }
                throw Failure.damaged
            }
            while cursor < end {
                tick += try vlq()
                guard cursor < end else { throw Failure.damaged }
                var byte = bytes[cursor]
                if byte & 0x80 != 0 { status = byte; cursor += 1 } else if status == 0 { throw Failure.damaged }
                if status == 0xff {
                    guard cursor < end else { throw Failure.damaged }
                    let type = bytes[cursor]; cursor += 1
                    let size = try vlq()
                    guard cursor + size <= end else { throw Failure.damaged }
                    let body = Array(bytes[cursor..<cursor + size]); cursor += size
                    switch type {
                    case 0x03: trackNames[track] = String(decoding: body.prefix(40), as: UTF8.self)
                    case 0x51 where size == 3 && tempo == nil:
                        let micro = Double(Int(body[0]) << 16 | Int(body[1]) << 8 | Int(body[2]))
                        if micro > 0 { tempo = 60_000_000 / micro }
                    case 0x59 where size == 2 && key == nil:
                        let fifths = Int(Int8(bitPattern: body[0])), minor = body[1] == 1
                        let major = ((fifths * 7) % 12 + 12) % 12
                        key = (minor ? (major + 9) % 12 : major, minor)
                    case 0x06: markers.append((Int((Double(tick) * scale).rounded()), String(decoding: body.prefix(60), as: UTF8.self)))
                    case 0x2f: cursor = end
                    default: break
                    }
                    status = 0
                    continue
                }
                if status == 0xf0 || status == 0xf7 {
                    let size = try vlq(); guard cursor + size <= end else { throw Failure.damaged }
                    cursor += size; status = 0; continue
                }
                let kind = status & 0xf0, channel = Int(status & 0x0f)
                let dataCount = (kind == 0xc0 || kind == 0xd0) ? 1 : 2
                guard cursor + dataCount <= end else { throw Failure.damaged }
                byte = bytes[cursor]
                let a = Int(byte & 0x7f), b = dataCount == 2 ? Int(bytes[cursor + 1] & 0x7f) : 0
                cursor += dataCount
                let key = channel << 8 | a
                if kind == 0x90 && b > 0 {
                    open[key, default: []].append((tick, b))
                } else if kind == 0x80 || (kind == 0x90 && b == 0) {
                    if var stack = open[key], !stack.isEmpty {
                        let start = stack.removeFirst(); open[key] = stack
                        let s = Int((Double(start.tick) * scale).rounded()), e = Int((Double(tick) * scale).rounded())
                        notes.append(RawNote(tick: s, duration: max(1, e - s), pitch: a, velocity: start.velocity, channel: channel, track: track))
                    }
                }
            }
            // Notes still held at the end of the track end there.
            for (key, stack) in open {
                for start in stack {
                    let s = Int((Double(start.tick) * scale).rounded()), e = Int((Double(tick) * scale).rounded())
                    notes.append(RawNote(tick: s, duration: max(ppq / 8, e - s), pitch: key & 0xff, velocity: start.velocity, channel: key >> 8, track: track))
                }
            }
            cursor = end
        }
        guard !notes.isEmpty else { throw Failure.noNotes }
        let lastTick = notes.map { $0.tick + $0.duration }.max() ?? barTicks
        let bars = min(64, max(1, (lastTick + barTicks - 1) / barTicks))
        let length = bars * barTicks
        var dropped = notes.filter { $0.tick >= length }.count
        notes = notes.filter { $0.tick < length }
        var project = Project(name: String(name.prefix(110)), bars: bars)
        project.bpm = min(240, max(40, ((tempo ?? 120) * 10).rounded() / 10))
        if let key { project.keyRoot = key.root; project.minor = key.minor }
        // Sections from markers, else one section.
        let marks = markers.filter { $0.0 < length }.map { (($0.0 / barTicks) * barTicks, $0.1) }
        var starts = [0] + marks.map(\.0).filter { $0 > 0 }
        starts = Array(Set(starts)).sorted().prefix(8).map { $0 }
        project.sections = starts.enumerated().map { index, start in
            let next = index + 1 < starts.count ? starts[index + 1] : length
            let label = marks.first { $0.0 == start }?.1.trimmingCharacters(in: .whitespacesAndNewlines)
            return Section(name: (label?.isEmpty == false ? label! : NSLocalizedString("Imported", comment: "MIDI import section")), start: start, length: next - start)
        }
        // Drums (channel 10).
        let drumIndex = project.tracks.firstIndex { $0.role == .drums }!
        let drumPattern = project.patterns.firstIndex { $0.id == project.tracks[drumIndex].clips[0].patternID }!
        project.patterns[drumPattern].length = length
        project.tracks[drumIndex].clips = [Clip(patternID: project.patterns[drumPattern].id, start: 0, length: length)]
        var drumEvents: [DrumEvent] = []
        for note in notes where note.channel == 9 {
            guard let pad = Compiler.drumMap.firstIndex(of: note.pitch) ?? nearestPad(note.pitch) else { dropped += 1; continue }
            if drumEvents.count < 4096 { drumEvents.append(DrumEvent(tick: note.tick, pad: pad, velocity: max(1, note.velocity))) } else { dropped += 1 }
        }
        project.patterns[drumPattern].drums = drumEvents
        let harmonyIndex = project.tracks.firstIndex { $0.role == .harmony }!
        let harmonyPattern = project.patterns.firstIndex { $0.id == project.tracks[harmonyIndex].clips[0].patternID }!
        project.patterns[harmonyPattern].length = length
        project.tracks[harmonyIndex].clips = [Clip(patternID: project.patterns[harmonyPattern].id, start: 0, length: length)]
        // Melodic channels, ordered by first note.
        let channels = Dictionary(grouping: notes.filter { $0.channel != 9 }, by: { $0.channel << 8 | $0.track })
        // Deterministic order: first note, then MIDI track, then channel.
        let ordered = channels.sorted { a, b in
            let x = (a.value.map(\.tick).min() ?? 0, a.key & 0xff, a.key >> 8), y = (b.value.map(\.tick).min() ?? 0, b.key & 0xff, b.key >> 8)
            return x < y
        }
        var droppedChannels = 0
        for (key, group) in ordered {
            guard project.tracks.count < 8 else { droppedChannels += 1; dropped += group.count; continue }
            var track = Track(role: .melody)
            let label = trackNames[key & 0xff].map { String($0.prefix(40)) }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            track.name = label ?? String(format: NSLocalizedString("MIDI channel %d", comment: "MIDI import track"), (key >> 8) + 1)
            var pattern = Pattern(length: length)
            for note in group.sorted(by: { $0.tick < $1.tick }) {
                guard (pattern.notes ?? []).count < 4096 else { dropped += 1; continue }
                pattern.notes?.append(NoteEvent(tick: note.tick, duration: max(1, min(note.duration, length - note.tick)), pitch: note.pitch, velocity: min(127, max(1, note.velocity))))
            }
            project.patterns.append(pattern)
            track.clips = [Clip(patternID: pattern.id, start: 0, length: length)]
            project.tracks.append(track)
        }
        try project.validate()
        return Result(project: project, droppedNotes: dropped, droppedChannels: droppedChannels)
    }

    static func nearestPad(_ pitch: Int) -> Int? {
        switch pitch {
        case 35, 36: return 0
        case 38, 40: return 1
        case 42, 44: return 2
        case 46: return 3
        case 39: return 4
        case 37: return 5
        case 41, 43, 45: return 6
        case 47, 48: return 7
        case 50: return 8
        case 49, 52, 55, 57: return 9
        case 51, 53, 59: return 10
        default: return (27...87).contains(pitch) ? 15 : nil
        }
    }
}
