import Foundation

/// A drag contains identities, never musical data supplied by another app.
public struct ArrangementDragPayload: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case clip, section }
    public let version: Int
    public let kind: Kind
    public let projectID: UUID
    public let revision: Int
    public let sourceTrackID: UUID?
    public let objectID: UUID
    public let grabOffset: Int
    public init(project: Project, trackID: UUID, clipID: UUID, grabOffset: Int = 0) {
        version=1;kind = .clip;projectID=project.id;revision=project.revision
        sourceTrackID=trackID;objectID=clipID;self.grabOffset=grabOffset
    }
    public init(project: Project, sectionID: UUID) {
        version=1;kind = .section;projectID=project.id;revision=project.revision
        sourceTrackID=nil;objectID=sectionID;grabOffset=0
    }
    public func encoded() -> String {
        guard let data=try? JSONEncoder().encode(self) else { return "" }
        return "lagrilla.arrangement.v1:"+data.base64EncodedString()
    }
    public static func decode(_ text: String) throws -> Self {
        let prefix="lagrilla.arrangement.v1:"
        guard text.utf8.count<=2048,text.hasPrefix(prefix),
              let data=Data(base64Encoded:String(text.dropFirst(prefix.count))),
              let value=try? JSONDecoder().decode(Self.self,from:data),
              value.version==1,value.revision>=0,(0...64*barTicks).contains(value.grabOffset) else { throw ClipEditingError.invalidDrag }
        return value
    }
    public func validate(in project: Project, kind: Kind) throws {
        guard version==1,self.kind==kind else { throw ClipEditingError.invalidDrag }
        guard project.id==projectID,project.revision==revision else { throw ClipEditingError.stale }
    }
}

public enum ClipEditingError: Error, Equatable, LocalizedError {
    case invalidDrag, stale, missing, incompatible, overlap, bounds, derivedBass, grid
    public var errorDescription: String? {
        let key: String = switch self {
        case .invalidDrag: "The dragged item is not a La Grilla clip or section."
        case .stale: "This drag belongs to a different or changed project. Start the drag again."
        case .missing: "This clip or section no longer exists."
        case .incompatible: "Drop clips onto a track with the same instrument type."
        case .overlap: "Clips cannot overlap. Move or shorten the other clip first."
        case .bounds: "Keep clips inside the 64-bar song limit."
        case .derivedBass: "Root bass follows harmony and cannot hold independent clips."
        case .grid: "Choose a valid grid size."
        }
        return NSLocalizedString(key,comment:"Arrangement editing")
    }
}

/// A visible occurrence retains the original event for source-pattern editing.
public struct ArrangementChordSlice: Identifiable, Sendable {
    public let id: String
    public let event: ChordEvent?
    public let sourceTick: Int
    public let timelineTick: Int
    public let duration: Int
}

/// All public operations use a value candidate, so a rejected drop is atomic.
public enum ClipEditing {
    /// Expand loops and crop both ends. Empty source spans stay editable without
    /// drawing chord tiles beyond the clip or misidentifying a repeated event.
    public static func chordSlices(clip: Clip, pattern: Pattern) -> [ArrangementChordSlice] {
        guard (barTicks...64*barTicks).contains(pattern.length),pattern.chords.count<=256,
              clip.start>=0,clip.start<=64*barTicks,clip.length>0,clip.length<=64*barTicks-clip.start,
              clip.offset>=0,clip.offset<pattern.length,
              pattern.chords.allSatisfy({$0.tick>=0 && $0.tick<pattern.length && $0.duration>0 && $0.duration<=pattern.length-$0.tick}) else {return []}
        var source: [(ChordEvent?,Int,Int)]=[],cursor=0
        func appendSilence(until end: Int) {
            while cursor<end {
                let next=min(end,(cursor/barTicks+1)*barTicks)
                source.append((nil,cursor,next));cursor=next
            }
        }
        for event in pattern.chords.sorted(by:{$0.tick<$1.tick}) {
            guard event.tick>=cursor else {return []}
            appendSilence(until:event.tick)
            source.append((event,event.tick,event.tick+event.duration))
            cursor=event.tick+event.duration
        }
        appendSilence(until:pattern.length)
        var result: [ArrangementChordSlice]=[]
        for cycle in stride(from:-clip.offset,to:clip.length,by:pattern.length) {
            for (event,start,end) in source {
                let begin=max(0,cycle+start),finish=min(clip.length,cycle+end)
                guard finish>begin else {continue}
                let key=event?.id.uuidString ?? "empty-\(start)"
                result.append(ArrangementChordSlice(id:"\(clip.id).\(key).\(cycle)",event:event,
                    sourceTick:event?.tick ?? begin-cycle,timelineTick:clip.start+begin,duration:finish-begin))
            }
        }
        return result
    }
    public static func snapped(_ value: Int, step: Int = barTicks) throws -> Int {
        guard (1...barTicks).contains(step) else { throw ClipEditingError.grid }
        guard (0...64*barTicks).contains(value) else { throw ClipEditingError.bounds }
        return Int((Double(value)/Double(step)).rounded())*step
    }
    private static func source(_ payload: ArrangementDragPayload, in project: Project) throws -> (Int,Int) {
        try payload.validate(in:project,kind:.clip)
        guard let trackID=payload.sourceTrackID,
              let track=project.tracks.firstIndex(where:{$0.id==trackID}),
              let clip=project.tracks[track].clips.firstIndex(where:{$0.id==payload.objectID}) else { throw ClipEditingError.missing }
        guard project.tracks[track].role != .bass else { throw ClipEditingError.derivedBass }
        guard payload.grabOffset>=0,payload.grabOffset<project.tracks[track].clips[clip].length else { throw ClipEditingError.invalidDrag }
        return (track,clip)
    }
    private static func extend(_ end: Int, allowed: Bool, project: inout Project) throws {
        guard end>0,end<=64*barTicks else { throw ClipEditingError.bounds }
        if end<=project.length { return }
        guard allowed,!project.sections.isEmpty else { throw ClipEditingError.bounds }
        let newLength=((end+barTicks-1)/barTicks)*barTicks
        let delta=newLength-project.length,index=project.sections.count-1
        project.sections[index].length += delta
    }
    private static func available(_ range: Range<Int>, track: Int, project: inout Project) throws {
        var clips: [Clip]=[]
        for clip in project.tracks[track].clips {
            let end=clip.start+clip.length
            guard clip.start<range.upperBound,end>range.lowerBound else { clips.append(clip);continue }
            // Automatically replace only genuinely empty, unrecorded placeholders.
            // Muted notes and clips with an original recording are still content.
            guard clip.sourceAssetID==nil,let pattern=project.patterns.first(where:{$0.id==clip.patternID}),
                  pattern.chords.isEmpty,pattern.drums.isEmpty,(pattern.notes ?? []).isEmpty else { throw ClipEditingError.overlap }
            var retainedOriginal=false
            if clip.start<range.lowerBound {
                var left=clip;left.length=range.lowerBound-clip.start;clips.append(left);retainedOriginal=true
            }
            if end>range.upperBound {
                var right=clip;if retainedOriginal { right.id=UUID() }
                right.start=range.upperBound;right.length=end-right.start
                right.offset=(clip.offset+right.start-clip.start)%pattern.length;clips.append(right)
            }
        }
        project.tracks[track].clips=clips
    }
    fileprivate static func finish(_ candidate: inout Project) throws {
        for index in candidate.tracks.indices { candidate.tracks[index].clips.sort{$0.start<$1.start} }
        let referenced=Set(candidate.tracks.flatMap{$0.clips.map(\.patternID)})
        candidate.patterns.removeAll{!referenced.contains($0.id)}
        try candidate.validate()
    }
    fileprivate static func cloned(_ pattern: Pattern) -> Pattern {
        var copy=pattern;copy.id=UUID()
        copy.chords=pattern.chords.map{var event=$0;event.id=UUID();return event}
        copy.drums=pattern.drums.map{var event=$0;event.id=UUID();return event}
        copy.notes=pattern.notes?.map{var event=$0;event.id=UUID();return event}
        return copy
    }
    public static func move(_ payload: ArrangementDragPayload, to trackID: UUID, start: Int, snap: Int = barTicks, extendingSong: Bool = true, in project: inout Project) throws {
        try relocate(payload,to:trackID,start:start,snap:snap,copy:false,extendingSong:extendingSong,in:&project)
    }
    public static func copy(_ payload: ArrangementDragPayload, to trackID: UUID, start: Int, snap: Int = barTicks, extendingSong: Bool = true, in project: inout Project) throws {
        try relocate(payload,to:trackID,start:start,snap:snap,copy:true,extendingSong:extendingSong,in:&project)
    }
    private static func relocate(_ payload: ArrangementDragPayload, to trackID: UUID, start: Int, snap: Int, copy: Bool, extendingSong: Bool, in project: inout Project) throws {
        try project.validate();let (sourceTrack,sourceClip)=try source(payload,in:project)
        guard let target=project.tracks.firstIndex(where:{$0.id==trackID}) else { throw ClipEditingError.missing }
        guard project.tracks[target].role != .bass else { throw ClipEditingError.derivedBass }
        guard project.tracks[sourceTrack].role==project.tracks[target].role else { throw ClipEditingError.incompatible }
        var clip=project.tracks[sourceTrack].clips[sourceClip]
        let tick=try snapped(start,step:snap)
        guard clip.length<=64*barTicks-tick else { throw ClipEditingError.bounds }
        if !copy,sourceTrack==target,tick==clip.start { return }
        var candidate=project
        if copy {
            guard let original=project.patterns.first(where:{$0.id==clip.patternID}) else { throw ClipEditingError.missing }
            let pattern=cloned(original);candidate.patterns.append(pattern);clip.id=UUID();clip.patternID=pattern.id
        } else { candidate.tracks[sourceTrack].clips.remove(at:sourceClip) }
        try extend(tick+clip.length,allowed:extendingSong,project:&candidate)
        try available(tick..<tick+clip.length,track:target,project:&candidate)
        clip.start=tick;candidate.tracks[target].clips.append(clip)
        try finish(&candidate);project=candidate
    }
    public static func resize(_ payload: ArrangementDragPayload, length: Int, snap: Int = barTicks, extendingSong: Bool = true, in project: inout Project) throws {
        try project.validate();let (track,index)=try source(payload,in:project)
        let duration=max(snap,try snapped(length,step:snap))
        let old=project.tracks[track].clips[index]
        guard duration<=64*barTicks-old.start else { throw ClipEditingError.bounds }
        if duration==old.length { return }
        var candidate=project;candidate.tracks[track].clips.remove(at:index)
        try extend(old.start+duration,allowed:extendingSong,project:&candidate)
        try available(old.start..<old.start+duration,track:track,project:&candidate)
        var clip=old;clip.length=duration;candidate.tracks[track].clips.append(clip)
        try finish(&candidate);project=candidate
    }
    public static func setOffset(_ payload: ArrangementDragPayload, offset: Int, snap: Int = 240, in project: inout Project) throws {
        try project.validate();let (track,index)=try source(payload,in:project)
        guard let pattern=project.patterns.first(where:{$0.id==project.tracks[track].clips[index].patternID}) else { throw ClipEditingError.missing }
        let value=try snapped(offset,step:snap)%pattern.length
        var candidate=project;candidate.tracks[track].clips[index].offset=value
        try finish(&candidate);project=candidate
    }
    public static func delete(_ payload: ArrangementDragPayload, in project: inout Project) throws {
        try project.validate();let (track,index)=try source(payload,in:project)
        var candidate=project;candidate.tracks[track].clips.remove(at:index)
        try finish(&candidate);project=candidate
    }
    public static func create(on trackID: UUID, start: Int, length: Int = barTicks, snap: Int = barTicks, in project: inout Project) throws {
        try project.validate()
        guard let track=project.tracks.firstIndex(where:{$0.id==trackID}) else { throw ClipEditingError.missing }
        guard project.tracks[track].role != .bass else { throw ClipEditingError.derivedBass }
        let tick=try snapped(start,step:snap),duration=max(snap,try snapped(length,step:snap))
        guard duration<=64*barTicks-tick else { throw ClipEditingError.bounds }
        var candidate=project;try extend(tick+duration,allowed:true,project:&candidate)
        try available(tick..<tick+duration,track:track,project:&candidate)
        let pattern=Pattern(length:max(barTicks,((duration+barTicks-1)/barTicks)*barTicks))
        candidate.patterns.append(pattern);candidate.tracks[track].clips.append(Clip(patternID:pattern.id,start:tick,length:duration))
        try finish(&candidate);project=candidate
    }
    /// Move an entire section and split crossing clips without losing their loop
    /// phase or source-recording association. Dropping on a chip uses its index.
    public static func reorderSection(_ payload: ArrangementDragPayload, to targetID: UUID, in project: inout Project) throws {
        try project.validate();try payload.validate(in:project,kind:.section)
        guard let source=project.sections.firstIndex(where:{$0.id==payload.objectID}),
              let destination=project.sections.firstIndex(where:{$0.id==targetID}) else { throw ClipEditingError.missing }
        if source==destination { return }
        let original=project.sections;var candidate=project
        let section=candidate.sections.remove(at:source);candidate.sections.insert(section,at:destination)
        var cursor=0
        for index in candidate.sections.indices { candidate.sections[index].start=cursor;cursor += candidate.sections[index].length }
        let positions=Dictionary(uniqueKeysWithValues:candidate.sections.map{($0.id,$0.start)})
        for track in project.tracks.indices {
            var clips: [Clip]=[]
            for clip in project.tracks[track].clips {
                guard let pattern=project.patterns.first(where:{$0.id==clip.patternID}) else { throw ClipEditingError.missing }
                var first=true
                for section in original {
                    let begin=max(clip.start,section.start),end=min(clip.start+clip.length,section.start+section.length)
                    if end<=begin { continue }
                    var part=clip;if !first { part.id=UUID() };first=false
                    part.start=positions[section.id]!+begin-section.start;part.length=end-begin
                    part.offset=(clip.offset+begin-clip.start)%pattern.length;clips.append(part)
                }
            }
            candidate.tracks[track].clips=clips
        }
        try finish(&candidate);project=candidate
    }
}

/// Section edits also support clips which cross section boundaries.
public enum SectionEditing {
    public static func append(name: String, bars: Int, to project: inout Project) throws {
        try project.validate()
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw MusicError.invalidProject }
        guard (1...64).contains(bars), project.sections.count < 8,
              bars <= 64 - project.length / barTicks else { throw MusicError.limit }

        var candidate = project
        let section = Section(name: title, start: project.length, length: bars * barTicks)
        candidate.sections.append(section)
        // Give the editors a writable clip immediately, including Jam's drum take.
        for index in candidate.tracks.indices where candidate.tracks[index].role != .bass {
            let pattern = Pattern(length: section.length)
            candidate.patterns.append(pattern)
            candidate.tracks[index].clips.append(Clip(patternID: pattern.id, start: section.start, length: section.length))
        }
        try ClipEditing.finish(&candidate)
        project = candidate
    }

    public static func duplicate(_ sectionID: UUID, name: String, in project: inout Project) throws {
        try project.validate()
        guard let index=project.sections.firstIndex(where:{$0.id==sectionID}) else { throw ClipEditingError.missing }
        let section=project.sections[index],insertion=section.start+section.length
        guard project.sections.count<8,project.length<=64*barTicks-section.length else { throw MusicError.limit }
        var candidate=project
        for track in project.tracks.indices {
            var output: [Clip]=[]
            for clip in project.tracks[track].clips {
                guard let pattern=project.patterns.first(where:{$0.id==clip.patternID}) else { throw ClipEditingError.missing }
                let end=clip.start+clip.length
                if clip.start>=insertion {var next=clip;next.start+=section.length;output.append(next)}
                else if end>insertion {
                    var left=clip;left.length=insertion-clip.start;output.append(left)
                    var right=clip;right.id=UUID();right.start=insertion+section.length;right.length=end-insertion;right.offset=(clip.offset+insertion-clip.start)%pattern.length;output.append(right)
                } else {output.append(clip)}
                let begin=max(clip.start,section.start),finish=min(end,insertion)
                if finish>begin {
                    let copiedPattern=ClipEditing.cloned(pattern);candidate.patterns.append(copiedPattern)
                    var copy=clip;copy.id=UUID();copy.patternID=copiedPattern.id
                    copy.start=insertion+begin-section.start;copy.length=finish-begin
                    copy.offset=(clip.offset+begin-clip.start)%pattern.length;output.append(copy)
                }
            }
            candidate.tracks[track].clips=output
        }
        for i in candidate.sections.indices where candidate.sections[i].start>=insertion {candidate.sections[i].start+=section.length}
        candidate.sections.insert(Section(name:name,start:insertion,length:section.length),at:index+1)
        try ClipEditing.finish(&candidate);project=candidate
    }
    public static func delete(_ sectionID: UUID, in project: inout Project) throws {
        try project.validate()
        guard project.sections.count>1 else { throw MusicError.invalidProject }
        guard let index=project.sections.firstIndex(where:{$0.id==sectionID}) else { throw ClipEditingError.missing }
        let section=project.sections[index],end=section.start+section.length
        var candidate=project;candidate.sections.remove(at:index)
        for i in candidate.sections.indices where candidate.sections[i].start>=end {candidate.sections[i].start-=section.length}
        for track in project.tracks.indices {
            var output: [Clip]=[]
            for clip in project.tracks[track].clips {
                let clipEnd=clip.start+clip.length
                if clipEnd<=section.start {output.append(clip);continue}
                if clip.start>=end {var moved=clip;moved.start-=section.length;output.append(moved);continue}
                guard let pattern=project.patterns.first(where:{$0.id==clip.patternID}) else { throw ClipEditingError.missing }
                var retainedOriginal=false
                if clip.start<section.start {var left=clip;left.length=section.start-clip.start;output.append(left);retainedOriginal=true}
                if clipEnd>end {
                    var right=clip;if retainedOriginal {right.id=UUID()};right.start=section.start;right.length=clipEnd-end
                    right.offset=(clip.offset+end-clip.start)%pattern.length;output.append(right)
                }
            }
            candidate.tracks[track].clips=output
        }
        // A long source pattern can outlive a shortened song. Materialize only
        // those references so the heard notes survive without invalid lengths.
        for track in candidate.tracks.indices {
            for index in candidate.tracks[track].clips.indices {
                let clip=candidate.tracks[track].clips[index]
                guard let pattern=candidate.patterns.first(where:{$0.id==clip.patternID}),pattern.length>candidate.length else {continue}
                var fitted=Arrangement.materialize(candidate,track:candidate.tracks[track],section:Section(name:"Clip",start:clip.start,length:clip.length))
                fitted.length=max(barTicks,((clip.length+barTicks-1)/barTicks)*barTicks)
                candidate.patterns.append(fitted);candidate.tracks[track].clips[index].patternID=fitted.id;candidate.tracks[track].clips[index].offset=0
            }
        }
        try ClipEditing.finish(&candidate);project=candidate
    }
}
