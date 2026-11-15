import Foundation

public let ppq = 960
public let barTicks = 3840
public let masterBus = 8
public enum TrackRole: String, Codable, CaseIterable, Sendable { case harmony, drums, bass, melody
    public var instrument:Int {switch self{case .harmony:0;case .drums:1;case .bass:2;case .melody:3}}
}
public enum Quality: String, Codable, CaseIterable, Sendable {
    case major = "", minor = "m", dim, aug, sus2, sus4, seventh = "7", maj7, m7, m7b5
    case sixth="6",m6,add9,ninth="9",maj9,m9,eleventh="11",m11,thirteenth="13",flat9="7b9",sharp9="7#9",sharp11="7#11",flat13="7b13"
    public var intervals: [Int] {
        switch self {
        case .major: [0,4,7]; case .minor: [0,3,7]; case .dim: [0,3,6]; case .aug: [0,4,8]
        case .sus2: [0,2,7]; case .sus4: [0,5,7]; case .seventh: [0,4,7,10]
        case .maj7: [0,4,7,11]; case .m7: [0,3,7,10]; case .m7b5: [0,3,6,10]
        case .sixth:[0,4,7,9];case .m6:[0,3,7,9];case .add9:[0,4,7,14]
        case .ninth:[0,4,7,10,14];case .maj9:[0,4,7,11,14];case .m9:[0,3,7,10,14]
        case .eleventh:[0,4,7,10,14,17];case .m11:[0,3,7,10,14,17];case .thirteenth:[0,4,7,10,14,17,21]
        case .flat9:[0,4,7,10,13];case .sharp9:[0,4,7,10,15];case .sharp11:[0,4,7,10,18];case .flat13:[0,4,7,10,20]
        }
    }
    public var label: String { self == .major ? "Major" : self == .minor ? "Minor" : rawValue }
}
public struct Chord: Codable, Equatable, Sendable {
    public var root: Int; public var quality: Quality; public var inversion: Int
    public var slashBass:Int?;public var voicedNotes:[Int]?
    public init(root: Int = 0, quality: Quality = .major, inversion: Int = 0,slashBass:Int?=nil,voicedNotes:[Int]?=nil) { self.root = root; self.quality = quality; self.inversion = inversion;self.slashBass=slashBass;self.voicedNotes=voicedNotes }
    public static let roots = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    public var symbol: String { Self.roots[(root % 12 + 12) % 12] + quality.rawValue + (slashBass.map{"/"+Self.roots[($0%12+12)%12]} ?? "") }
    public var notes: [Int] {
        if let voicedNotes{return voicedNotes.sorted()}
        let base = root == 0 ? 60 : 48 + root
        var result = quality.intervals.map { base + $0 }
        for i in 0..<max(0, min(inversion, result.count - 1)) { result[i] += 12 }
        if let slashBass{var bass=48+slashBass;while bass>=(result.min() ?? 60){bass-=12};result.append(bass)}
        return result.sorted()
    }
    public static func parse(_ text: String) throws -> Chord {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"♯",with:"#").replacingOccurrences(of:"♭",with:"b")
        let parts=value.split(separator:"/",omittingEmptySubsequences:false);guard (1...2).contains(parts.count)else{throw MusicError.invalidChord}
        func pitch(_ raw:String)throws->(Int,String){guard let first=raw.first,let base=["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][String(first).uppercased()]else{throw MusicError.invalidChord};var suffix=String(raw.dropFirst());var root=base;if suffix.hasPrefix("#"){root+=1;suffix.removeFirst()}else if suffix.hasPrefix("b"){root-=1;suffix.removeFirst()};return ((root+12)%12,suffix)}
        let (root,suffix)=try pitch(String(parts[0]));guard let quality=Quality(rawValue:suffix)else{throw MusicError.invalidChord}
        var bass:Int?
        if parts.count==2{let (note,tail)=try pitch(String(parts[1]));guard tail.isEmpty else{throw MusicError.invalidChord};bass=note}
        return Chord(root:root,quality:quality,slashBass:bass)
    }
}
public struct ChordEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var tick: Int; public var duration: Int; public var chord: Chord
    public init(tick: Int, duration: Int = barTicks, chord: Chord) { self.tick = tick; self.duration = duration; self.chord = chord }
}
public struct DrumEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var tick: Int; public var pad: Int; public var velocity: Int
    public init(tick: Int, pad: Int, velocity: Int = 100) { self.tick = tick; self.pad = pad; self.velocity = velocity }
}
public struct NoteEvent: Codable, Equatable, Identifiable, Sendable {
    public var id:UUID=UUID()
    public var tick:Int;public var duration:Int;public var pitch:Int;public var velocity:Int
    public var confidence:Double?
    public init(tick:Int,duration:Int=ppq,pitch:Int=60,velocity:Int=100,confidence:Double?=nil){self.tick=tick;self.duration=duration;self.pitch=pitch;self.velocity=velocity;self.confidence=confidence}
    public var name:String{Chord.roots[(pitch%12+12)%12]+String(pitch/12-1)}
}
public struct Pattern: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var length: Int; public var chords: [ChordEvent] = []; public var drums: [DrumEvent] = []; public var notes:[NoteEvent]?
    public init(length: Int, chords: [ChordEvent] = [], drums: [DrumEvent] = [], notes:[NoteEvent]=[]) { self.length = length; self.chords = chords; self.drums = drums; self.notes=notes }
}
public struct Clip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var patternID: UUID;public var sourceAssetID:UUID?; public var start: Int; public var length: Int; public var offset: Int = 0
    public init(patternID: UUID, start: Int, length: Int) { self.patternID = patternID; self.start = start; self.length = length }
}
public struct Track: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var role: TrackRole; public var name:String?; public var displayName:String{name ?? role.rawValue.capitalized}; public var gain: Double = -6; public var pan: Double = 0
    public var mute = false; public var solo = false; public var presetVersion = 1; public var clips: [Clip] = []
    public init(role: TrackRole) { self.role = role }
}
public struct Section: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public var name: String; public var start: Int; public var length: Int
    public init(name: String, start: Int = 0, length: Int) { self.name = name; self.start = start; self.length = length }
}
public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID(); public static let currentSchemaVersion=6
    public var schemaVersion = Project.currentSchemaVersion; public var revision = 0
    public var name: String; public var bpm: Double = 120; public var keyRoot = 0; public var minor = false
    public var modified = Date(); public var tracks: [Track]; public var patterns: [Pattern]; public var sections: [Section]
    public var masterFX:MasterFX?;public var performanceTakes:[PerformanceTake]?
    public var performanceTake:PerformanceTake?{get{performanceTakes?.first}set{performanceTakes=newValue.map{[$0]}}}
    public var audioAssets:[AudioAssetRecord]?
    public var midi:MIDISettings?
    public var bassOctave = 0; public var bassGate = 0.9; public var master: Double = -3
    public var length: Int { sections.reduce(0) { total, section in let (sum, overflow) = total.addingReportingOverflow(section.length); return overflow ? Int.max : sum } }
    public var keyName: String { Chord.roots[keyRoot] + (minor ? " minor" : " major") }
    public init(name: String = "Untitled", bars: Int = 4) {
        self.name = name; let length = bars * barTicks
        let harmony = Pattern(length: length); let drums = Pattern(length: length)
        patterns = [harmony, drums]; sections = [Section(name: "Verse", length: length)]
        var h = Track(role: .harmony); h.clips = [Clip(patternID: harmony.id, start: 0, length: length)]
        var d = Track(role: .drums); d.clips = [Clip(patternID: drums.id, start: 0, length: length)]
        tracks = [h,d]
    }
    public static func demo() -> Project {
        var p = Project(name: "First light")
        p.patterns[0].chords = [Chord(root: 0), Chord(root: 9, quality: .minor), Chord(root: 5), Chord(root: 7)].enumerated().map { ChordEvent(tick: $0.offset * barTicks, chord: $0.element) }
        for bar in 0..<4 {
            for tick in [0,1920] { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 0)) }
            for tick in [960,2880] { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 1)) }
            for tick in stride(from: 0, to: barTicks, by: 480) { p.patterns[1].drums.append(DrumEvent(tick: bar * barTicks + tick, pad: 2, velocity: 72)) }
        }
        p.tracks.append(Track(role: .bass)); return p
    }
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw MusicError.unsupportedSchema }
        guard bpm.isFinite, (40...240).contains(bpm), (0..<12).contains(keyRoot), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              (1...8).contains(sections.count), (barTicks...64*barTicks).contains(length), tracks.count >= 2, tracks.count <= 8,
              bassGate.isFinite, (0.1...1).contains(bassGate), (-1...1).contains(bassOctave), master.isFinite, (-61...6).contains(master),
              tracks[0].role == .harmony, tracks[1].role == .drums, tracks.dropFirst(2).allSatisfy({$0.role == .bass || $0.role == .melody}), tracks.filter({$0.role == .bass}).count <= 1,
              patterns.count <= 64, Set(patterns.map(\.id)).count == patterns.count, Set(sections.map(\.id)).count == sections.count,
              Set(tracks.map(\.id)).count == tracks.count else { throw MusicError.invalidProject }
        guard (performanceTakes ?? []).count<=1 else{throw MusicError.limit}
        try midi?.validate(self)
        try masterFX?.validate();try performanceTake?.validate()
        if let take=performanceTake{guard (take.source.audioAssets ?? []).allSatisfy({asset in (audioAssets ?? []).contains(asset)})else{throw MusicError.invalidProject}}
        guard (audioAssets ?? []).count<=8 else{throw MusicError.tooDense}
        for asset in audioAssets ?? []{try asset.validate()}
        var ids=[id];if let take=performanceTake{ids.append(take.id)};ids += (audioAssets ?? []).map(\.id)
        ids += tracks.map(\.id);ids += patterns.map(\.id);ids += sections.map(\.id)
        ids += tracks.flatMap{$0.clips.map(\.id)}
        for p in patterns {ids += p.chords.map(\.id);ids += p.drums.map(\.id);ids += (p.notes ?? []).map(\.id)}
        guard Set(ids).count == ids.count else { throw MusicError.invalidProject }
        var end = 0
        for s in sections { guard s.start == end, s.length > 0, s.length <= 64*barTicks, s.length % barTicks == 0, !s.name.isEmpty, s.name.count <= 120 else { throw MusicError.invalidProject }; end += s.length }
        for p in patterns {
            guard p.length >= barTicks, p.length % barTicks == 0, p.length <= length, p.chords.count <= 256, p.drums.count <= 4096, (p.notes ?? []).count <= 4096 else { throw MusicError.invalidProject }
            var end = 0
            for e in p.chords.sorted(by: {$0.tick < $1.tick}) {
                guard e.tick >= end, e.tick < p.length, e.duration > 0, e.duration <= p.length, e.tick + e.duration <= p.length, (0..<12).contains(e.chord.root), (0..<e.chord.quality.intervals.count).contains(e.chord.inversion) else { throw MusicError.invalidProject }
                guard e.chord.slashBass==nil || (0..<12).contains(e.chord.slashBass!)else{throw MusicError.invalidProject}
                if let voiced=e.chord.voicedNotes{let allowed=Set(e.chord.quality.intervals.map{($0+e.chord.root)%12}+[e.chord.slashBass ?? e.chord.root]);guard !voiced.isEmpty,voiced.count<=8,Set(voiced).count==voiced.count,Set(voiced.map{$0%12})==allowed,voiced.allSatisfy({(0...127).contains($0)&&allowed.contains($0%12)})else{throw MusicError.invalidProject}}
                end = e.tick + e.duration
            }
            for e in p.notes ?? [] {
                guard e.tick>=0,e.tick<p.length,e.duration>0,e.duration<=p.length,e.tick+e.duration<=p.length,(0...127).contains(e.pitch),(1...127).contains(e.velocity),e.confidence==nil || (e.confidence!.isFinite && (0...1).contains(e.confidence!))else{throw MusicError.invalidProject}
            }
            for e in p.drums { guard e.tick >= 0, e.tick < p.length, (0..<16).contains(e.pad), (1...127).contains(e.velocity) else { throw MusicError.invalidProject } }
        }
        for t in tracks {
            guard (t.name==nil || (!t.name!.isEmpty && t.name!.count<=40)), t.gain.isFinite, (-61...6).contains(t.gain), t.pan.isFinite, (-1...1).contains(t.pan), t.presetVersion == 1 else { throw MusicError.invalidProject }
            var end = 0
            for c in t.clips.sorted(by: {$0.start < $1.start}) {
                guard c.start >= end, c.start < length, c.length > 0, c.length <= length, c.start + c.length <= length, c.offset >= 0, let p = patterns.first(where: {$0.id == c.patternID}), c.offset < p.length else { throw MusicError.invalidProject }
                if let asset=c.sourceAssetID{guard (audioAssets ?? []).contains(where:{$0.id==asset})else{throw MusicError.invalidProject}}
                end = c.start + c.length
            }
        }
        var upperBound = 0
        for t in tracks { for clip in t.clips {
            if let p = patterns.first(where: {$0.id == clip.patternID}) {
                upperBound += ((clip.length + p.length - 1) / p.length + 1) * (p.chords.count * 8 + p.drums.count + (p.notes ?? []).count)
            }
        }}
        guard upperBound <= 65536 else { throw MusicError.tooDense }
        guard Compiler.notes(self).count <= 32768 else { throw MusicError.tooDense }
        guard try JSONEncoder().encode(self).count<=8_000_000 else{throw MusicError.tooDense}
    }
    public mutating func duplicateSection(_ id: UUID, name: String) throws {
        guard let index = sections.firstIndex(where: {$0.id == id}), sections.count < 8, length + sections[index].length <= 64 * barTicks else { throw MusicError.limit }
        let original = sections[index]; let insertion = original.start + original.length
        for i in tracks.indices {
            let clips = tracks[i].clips.filter { $0.start >= original.start && $0.start < insertion }
            for j in tracks[i].clips.indices where tracks[i].clips[j].start >= insertion { tracks[i].clips[j].start += original.length }
            for c in clips {
                guard var p = patterns.first(where: {$0.id == c.patternID}) else { throw MusicError.invalidProject }
                p.id = UUID(); p.chords = p.chords.map { var e = $0; e.id = UUID(); return e }; p.drums = p.drums.map { var e = $0; e.id = UUID(); return e }; p.notes=(p.notes ?? []).map{var e=$0;e.id=UUID();return e}
                patterns.append(p);var copy=c;copy.id=UUID();copy.patternID=p.id;copy.start += original.length;tracks[i].clips.append(copy)
            }
        }
        for i in sections.indices where sections[i].start >= insertion { sections[i].start += original.length }
        sections.insert(Section(name: name, start: insertion, length: original.length), at: index + 1)
    }
    public mutating func addMelody(name:String?=nil)throws {
        guard tracks.count<8 else{throw MusicError.trackLimit}
        var t=Track(role:.melody);t.name=name ?? "Melody \(tracks.filter{$0.role == .melody}.count+1)"
        for section in sections {let p=Pattern(length:section.length);patterns.append(p);t.clips.append(Clip(patternID:p.id,start:section.start,length:section.length))}
        tracks.append(t)
    }
    public mutating func deleteTrack(_ id:UUID)throws {
        guard let i=tracks.firstIndex(where:{$0.id==id}),i>=2 else{throw MusicError.invalidProject}
        tracks.remove(at:i);let referenced=Set(tracks.flatMap{$0.clips.map(\.patternID)});patterns.removeAll{!referenced.contains($0.id)}
        midi?.mappings.removeAll{$0.trackID==id};if midi?.trackID==id{midi?.trackID=nil}
    }
    public mutating func duplicateTrack(_ id:UUID)throws {
        guard tracks.count<8,let t=tracks.first(where:{$0.id==id}),t.role == .melody else{throw MusicError.trackLimit}
        var copy=t;copy.id=UUID();copy.name=String(t.displayName.prefix(34))+" copy";copy.clips=[]
        for clip in t.clips {guard var p=patterns.first(where:{$0.id==clip.patternID})else{throw MusicError.invalidProject};p.id=UUID();p.notes=(p.notes ?? []).map{var n=$0;n.id=UUID();return n};p.chords=p.chords.map{var n=$0;n.id=UUID();return n};p.drums=p.drums.map{var n=$0;n.id=UUID();return n};patterns.append(p);var c=clip;c.id=UUID();c.patternID=p.id;copy.clips.append(c)}
        tracks.append(copy)
    }
    public mutating func deleteSection(_ id: UUID) throws {
        guard sections.count > 1, let index = sections.firstIndex(where: {$0.id == id}) else { throw MusicError.invalidProject }
        let removed = sections.remove(at: index)
        let end = removed.start + removed.length
        for i in tracks.indices {
            tracks[i].clips.removeAll { $0.start >= removed.start && $0.start < end }
            for j in tracks[i].clips.indices where tracks[i].clips[j].start >= end { tracks[i].clips[j].start -= removed.length }
        }
        for i in sections.indices where sections[i].start >= end { sections[i].start -= removed.length }
        let referenced = Set(tracks.flatMap { $0.clips.map(\.patternID) })
        patterns.removeAll { !referenced.contains($0.id) }
    }
    public mutating func moveSection(_ id: UUID, by delta: Int) throws {
        guard let i = sections.firstIndex(where: {$0.id == id}), sections.indices.contains(i + delta) else { return }
        let starts = Dictionary(uniqueKeysWithValues: sections.map {($0.id, $0.start)})
        sections.swapAt(i, i + delta); var cursor = 0
        for j in sections.indices {
            let len = sections[j].length
            sections[j].start = cursor; cursor += len
        }
        for k in tracks.indices { for c in tracks[k].clips.indices {
            let old = tracks[k].clips[c].start
            if let s = sections.first(where: {old >= starts[$0.id]! && old < starts[$0.id]! + $0.length}) { tracks[k].clips[c].start = s.start + old - starts[s.id]! }
        }}
    }
}
public enum MusicError: Error, LocalizedError {
    case invalidChord, invalidProject, unsupportedSchema, limit, tooDense, trackLimit, assetLimit
    public var errorDescription: String? {
        let key = switch self {
        case .invalidChord: "Unrecognized chord. Choose a chord from the list."
        case .unsupportedSchema: "This project was made with a newer version. The original has been preserved."
        case .limit: "A song can contain up to 8 sections and 64 bars."
        case .assetLimit: "A project can keep up to eight source recordings."
        case .trackLimit: "A project can contain up to eight tracks."
        case .tooDense: "This project has too many events."
        case .invalidProject: "The project contains invalid musical data."
        }
        return NSLocalizedString(key, comment: "Project validation")
    }
}
public enum Quantize: Int, CaseIterable, Sendable { case off = 0, eighth = 480, sixteenth = 240
    public func tick(_ tick: Int, length: Int) -> Int { rawValue == 0 ? max(0, min(length - 1, tick)) : ((max(0, tick) + rawValue / 2) / rawValue * rawValue) % length }
}
public struct History: Sendable {
    private var past: [Project] = []; private var future: [Project] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }; public var canRedo: Bool { !future.isEmpty }
    public mutating func apply(_ project: inout Project, coalescing: Bool = false, _ change: (inout Project) throws -> Void) throws {
        var candidate = project; try change(&candidate); candidate.revision = project.revision + 1; candidate.modified = Date(); try candidate.validate()
        if !coalescing || past.isEmpty { past.append(project) }; if past.count > 80 { past.removeFirst() }; future.removeAll(); project = candidate
    }
    public mutating func undo(_ project: inout Project) { guard var p = past.popLast() else { return }; future.append(project); p.revision = project.revision + 1; p.modified = Date(); project = p }
    public mutating func redo(_ project: inout Project) { guard var p = future.popLast() else { return }; past.append(project); p.revision = project.revision + 1; p.modified = Date(); project = p }
}

public enum ProjectDocument {
    /// Read/migrate a value copy. The source bytes are preserved until an explicit save.
    public static func decode(_ data:Data)throws->Project {
        guard data.count<=8_000_000 else{throw MusicError.tooDense}
        return try migrated(JSONDecoder().decode(Project.self,from:data))
    }
    private static func migrated(_ value:Project)throws->Project {
        var p=value
        guard (1...Project.currentSchemaVersion).contains(p.schemaVersion)else{throw MusicError.unsupportedSchema}
        if p.schemaVersion==1 {p.schemaVersion=2;for i in p.patterns.indices{if p.patterns[i].notes==nil{p.patterns[i].notes=[]}}}
        if p.schemaVersion==2{p.schemaVersion=3}
        if p.schemaVersion==3{p.schemaVersion=4}
        if p.schemaVersion==4{p.schemaVersion=5}
        if p.schemaVersion==5{p.schemaVersion=6}
        if var take=p.performanceTake{take.source=try migrated(take.source);p.performanceTake=take}
        try p.validate();return p
    }
}
