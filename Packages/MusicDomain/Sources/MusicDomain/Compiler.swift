import Foundation
public struct CompiledNote: Equatable, Sendable {
    public var tick: Int; public var duration: Int; public var pitch: Int; public var velocity: Int; public var track: Int; public var pad: Int = -1;public var instrument:Int=0
}
public enum Compiler {
    public static let drumMap = [36,38,42,46,39,37,45,47,50,49,51,54,56,75,70,82]
    public static let padNames = ["Kick","Snare","Closed hat","Open hat","Clap","Rim","Low tom","Mid tom","High tom","Crash","Ride","Tambourine","Cowbell","Clave","Shaker","Perc"]
    public static func bassPitch(for chord:Chord,register:Int)->Int {
        if let exact=chord.rootBassPitch{return exact}
        let root=chord.slashBass ?? chord.root
        return (root==0 ? 36:24+root)+register*12
    }
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
                            for pitch in chord.chord.notes { result.append(CompiledNote(tick: clip.start + start, duration: end - start, pitch: pitch, velocity: chord.velocity ?? 88, track: index)) }
                            if let bass = project.tracks.firstIndex(where: {$0.role == .bass}) {
                                result.append(CompiledNote(tick: clip.start + start, duration: max(1, Int(Double(end-start) * project.bassGate)), pitch: bassPitch(for:chord.chord,register:project.bassOctave), velocity: 94, track: bass,instrument:2))
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
public struct MIDIControl:Sendable {
    public var tick:Int;public var track:Int;public var number:Int;public var value:Int
    public init(tick:Int,track:Int,number:Int,value:Int){self.tick=tick;self.track=track;self.number=number;self.value=value}
}
public struct MIDIMarker:Sendable {
    public var tick:Int;public var text:String
    public init(tick:Int,text:String){self.tick=tick;self.text=text}
}
public enum MIDIExporter {
    private struct Event { var tick: Int; var priority: Int; var bytes: [UInt8] }
    public static func data(_ project: Project, range: Range<Int>? = nil) throws -> Data {
        try project.validate(); let range = range ?? 0..<project.length
        guard range.lowerBound >= 0, range.upperBound <= project.length, !range.isEmpty else { throw MusicError.invalidProject }
        let markers=project.sections.filter{$0.start<range.upperBound && $0.start+$0.length>range.lowerBound}.map{MIDIMarker(tick:max(0,$0.start-range.lowerBound),text:$0.name)}
        return try sequence(project,notes:Compiler.notes(project,range:range),duration:range.count,markers:markers)
    }
    public static func sequence(_ project:Project,notes:[CompiledNote],duration:Int,markers:[MIDIMarker]=[],controls:[MIDIControl]=[])throws->Data {
        try project.validate()
        guard (1...songTickLimit).contains(duration),notes.count<=200_000,markers.count<=16384,controls.count<=150_000 else{throw MusicError.limit}
        guard notes.allSatisfy({$0.tick>=0 && $0.tick<duration && $0.duration>0 && $0.duration<=duration-$0.tick && (0...127).contains($0.pitch) && (1...127).contains($0.velocity) && project.tracks.indices.contains($0.track)}),markers.allSatisfy({(0...duration).contains($0.tick) && $0.text.utf8.count<=512}),controls.allSatisfy({(0...duration).contains($0.tick) && project.tracks.indices.contains($0.track) && (0...127).contains($0.number) && (0...127).contains($0.value)})else{throw MusicError.invalidProject}
        let tempo = Int((60_000_000 / project.bpm).rounded())
        func meta(_ type: UInt8, _ bytes: [UInt8]) -> [UInt8] { [0xff,type] + vlq(bytes.count) + bytes }
        // Circle-of-fifths signature counts: C, Db, D, Eb, E, F, F#, G, Ab, A, Bb, B.
        let majorFifths = [0,7,2,-3,4,-1,6,1,-4,3,-2,5]
        let minorFifths = [-3,4,-1,-6,1,-4,3,-2,-7,0,-5,2]
        let fifths = project.minor ? minorFifths[project.keyRoot] : majorFifths[project.keyRoot]
        var conductor = [Event(tick: 0, priority: 0, bytes: meta(3, Array(project.name.utf8))), Event(tick: 0, priority: 1, bytes: meta(0x51, [UInt8((tempo>>16)&255),UInt8((tempo>>8)&255),UInt8(tempo&255)])), Event(tick: 0, priority: 2, bytes: meta(0x58,[4,2,24,8])), Event(tick: 0, priority: 3, bytes: meta(0x59,[UInt8(bitPattern: Int8(fifths)),project.minor ? 1 : 0]))]
        for marker in markers {conductor.append(Event(tick:marker.tick,priority:4,bytes:meta(6,Array(marker.text.utf8))))}
        var result = Data(Array("MThd".utf8) + be(6,4) + be(1,2) + be(project.tracks.count+1,2) + be(ppq,2))
        func chunk(_ events: [Event]) -> Data {
            var bytes: [UInt8] = []; var previous = 0
            for e in events.sorted(by: { $0.tick == $1.tick ? $0.priority < $1.priority : $0.tick < $1.tick }) { bytes += vlq(e.tick - previous) + e.bytes; previous = e.tick }
            bytes += vlq(duration - previous) + [0xff,0x2f,0]
            return Data(Array("MTrk".utf8) + be(bytes.count,4) + bytes)
        }
        result.append(chunk(conductor))
        var melodyChannel=2
        for (i,t) in project.tracks.enumerated() {
            let channel = t.role == .drums ? 9 : t.role == .bass ? 1 : t.role == .melody ? melodyChannel:0
            if t.role == .melody {melodyChannel+=1}
            var events = [Event(tick: 0, priority: -1, bytes: meta(3,Array(t.displayName.utf8)))]
            for control in controls where control.track==i {events.append(Event(tick:control.tick,priority:1,bytes:[UInt8(0xb0|channel),UInt8(control.number),UInt8(control.value)]))}
            for n in notes where n.track == i {
                events.append(Event(tick: n.tick, priority: 2, bytes: [UInt8(0x90|channel),UInt8(n.pitch),UInt8(n.velocity)]))
                events.append(Event(tick: n.tick+n.duration, priority: 0, bytes: [UInt8(0x80|channel),UInt8(n.pitch),0]))
            }
            result.append(chunk(events))
        }
        return result
    }
    private static func be(_ n: Int, _ size: Int) -> [UInt8] { (0..<size).reversed().map {UInt8((n >> ($0*8)) & 255)} }
    private static func vlq(_ n: Int) -> [UInt8] { var value = n; var bytes = [UInt8(value & 127)]; value >>= 7; while value > 0 { bytes.insert(UInt8(value & 127)|128,at:0); value >>= 7 }; return bytes }
}
