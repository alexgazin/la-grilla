import Foundation
public struct CompiledNote: Equatable, Sendable {
    public var tick: Int; public var duration: Int; public var pitch: Int; public var velocity: Int; public var track: Int; public var pad: Int = -1;public var instrument:Int=0
}
public enum Compiler {
    public static let drumMap = [36,38,42,46,39,37,45,47,50,49,51,54,56,75,70,82]
    public static let padNames = ["Kick","Snare","Closed hat","Open hat","Clap","Rim","Low tom","Mid tom","High tom","Crash","Ride","Tambourine","Cowbell","Clave","Shaker","Perc"]
    public static func notes(_ project: Project, range: Range<Int>? = nil) -> [CompiledNote] {
        let range = range ?? 0..<project.length
        var result: [CompiledNote] = []
        for (index, track) in project.tracks.enumerated() where track.role != .bass {
            for clip in track.clips {
                guard let pattern = project.patterns.first(where: {$0.id == clip.patternID}), pattern.length > 0 else { continue }
                for cycle in stride(from: -clip.offset, to: clip.length, by: pattern.length) {
                    if track.role == .harmony {
                        for chord in pattern.chords {
                            let local = cycle + chord.tick; let start = max(0, local); let end = min(clip.length, local + chord.duration)
                            guard end > start else { continue }
                            for pitch in chord.chord.notes { result.append(CompiledNote(tick: clip.start + start, duration: end - start, pitch: pitch, velocity: 88, track: index)) }
                            if let bass = project.tracks.firstIndex(where: {$0.role == .bass}) {
                                result.append(CompiledNote(tick: clip.start + start, duration: max(1, Int(Double(end-start) * project.bassGate)), pitch: ((chord.chord.slashBass ?? chord.chord.root) == 0 ? 36 : 24 + (chord.chord.slashBass ?? chord.chord.root)) + project.bassOctave * 12, velocity: 94, track: bass,instrument:2))
                            }
                        }
                    } else if track.role == .melody {
                        for note in pattern.notes ?? [] {
                            let local=cycle+note.tick;let start=max(0,local);let end=min(clip.length,local+note.duration)
                            if end>start{result.append(CompiledNote(tick:clip.start+start,duration:end-start,pitch:note.pitch,velocity:note.velocity,track:index,instrument:3))}
                        }
                    } else {
                        for drum in pattern.drums where cycle + drum.tick >= 0 && cycle + drum.tick < clip.length && (0..<16).contains(drum.pad) {
                            result.append(CompiledNote(tick: clip.start + cycle + drum.tick, duration: 120, pitch: drumMap[drum.pad], velocity: drum.velocity, track: index, pad: drum.pad,instrument:1))
                        }
                    }
                }
            }
        }
        return result.compactMap { note in
            let start = max(note.tick, range.lowerBound); let end = min(note.tick + note.duration, range.upperBound)
            guard end > start else { return nil }; var n = note; n.tick = start - range.lowerBound; n.duration = end-start; return n
        }.sorted { $0.tick == $1.tick ? $0.pitch < $1.pitch : $0.tick < $1.tick }
    }
}
public enum MIDIExporter {
    private struct Event { var tick: Int; var priority: Int; var bytes: [UInt8] }
    public static func data(_ project: Project, range: Range<Int>? = nil) throws -> Data {
        try project.validate(); let range = range ?? 0..<project.length
        guard range.lowerBound >= 0, range.upperBound <= project.length, !range.isEmpty else { throw MusicError.invalidProject }
        let notes = Compiler.notes(project, range: range); let tempo = Int((60_000_000 / project.bpm).rounded())
        func meta(_ type: UInt8, _ bytes: [UInt8]) -> [UInt8] { [0xff,type] + vlq(bytes.count) + bytes }
        // Circle-of-fifths signature counts: C, Db, D, Eb, E, F, F#, G, Ab, A, Bb, B.
        let majorFifths = [0,7,2,-3,4,-1,6,1,-4,3,-2,5]
        let minorFifths = [-3,4,-1,-6,1,-4,3,-2,-7,0,-5,2]
        let fifths = project.minor ? minorFifths[project.keyRoot] : majorFifths[project.keyRoot]
        var conductor = [Event(tick: 0, priority: 0, bytes: meta(3, Array(project.name.utf8))), Event(tick: 0, priority: 1, bytes: meta(0x51, [UInt8((tempo>>16)&255),UInt8((tempo>>8)&255),UInt8(tempo&255)])), Event(tick: 0, priority: 2, bytes: meta(0x58,[4,2,24,8])), Event(tick: 0, priority: 3, bytes: meta(0x59,[UInt8(bitPattern: Int8(fifths)),project.minor ? 1 : 0]))]
        for section in project.sections where section.start < range.upperBound && section.start + section.length > range.lowerBound {
            conductor.append(Event(tick: max(0,section.start-range.lowerBound), priority: 4, bytes: meta(6,Array(section.name.utf8))))
        }
        var result = Data(Array("MThd".utf8) + be(6,4) + be(1,2) + be(project.tracks.count+1,2) + be(ppq,2))
        func chunk(_ events: [Event]) -> Data {
            var bytes: [UInt8] = []; var previous = 0
            for e in events.sorted(by: { $0.tick == $1.tick ? $0.priority < $1.priority : $0.tick < $1.tick }) { bytes += vlq(e.tick - previous) + e.bytes; previous = e.tick }
            bytes += vlq(range.count - previous) + [0xff,0x2f,0]
            return Data(Array("MTrk".utf8) + be(bytes.count,4) + bytes)
        }
        result.append(chunk(conductor))
        var melodyChannel=2
        for (i,t) in project.tracks.enumerated() {
            let channel = t.role == .drums ? 9 : t.role == .bass ? 1 : t.role == .melody ? melodyChannel:0
            if t.role == .melody {melodyChannel+=1}
            var events = [Event(tick: 0, priority: -1, bytes: meta(3,Array(t.displayName.utf8)))]
            for n in notes where n.track == i {
                events.append(Event(tick: n.tick, priority: 1, bytes: [UInt8(0x90|channel),UInt8(n.pitch),UInt8(n.velocity)]))
                events.append(Event(tick: n.tick+n.duration, priority: 0, bytes: [UInt8(0x80|channel),UInt8(n.pitch),0]))
            }
            result.append(chunk(events))
        }
        return result
    }
    private static func be(_ n: Int, _ size: Int) -> [UInt8] { (0..<size).reversed().map {UInt8((n >> ($0*8)) & 255)} }
    private static func vlq(_ n: Int) -> [UInt8] { var value = n; var bytes = [UInt8(value & 127)]; value >>= 7; while value > 0 { bytes.insert(UInt8(value & 127)|128,at:0); value >>= 7 }; return bytes }
}
