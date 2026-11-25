import Foundation

/// A recording owns one linear occurrence of a drum clip. Source patterns and
/// other clips remain untouched until this draft is merged in one history edit.
public struct DrumRecordingDraft:Sendable {
    public private(set) var project:Project
    public let projectID:UUID;public let trackID:UUID;public let clipID:UUID
    public let sourcePatternID:UUID;public let patternID:UUID
    public let start:Int;public let length:Int
    public private(set) var changed=false
    /// Every pass of this recording belongs to one take, kept separable in the pattern.
    public let takeID=UUID()
    /// I8: the pattern's drums before each committed pass that changed it (newest last, at most 16).
    private var passHistory:[(drums:[DrumEvent],takes:[DrumTake]?)]=[]
    public var canUndoPass:Bool{!passHistory.isEmpty}
    public init(project:Project,clipID:UUID)throws {
        try project.validate()
        guard let track=project.tracks.first(where:{$0.role == .drums}),let clip=track.clips.first(where:{$0.id==clipID}),let trackIndex=project.tracks.firstIndex(where:{$0.id==track.id}),let clipIndex=track.clips.firstIndex(where:{$0.id==clipID})else{throw ClipEditingError.missing}
        var source=track;source.clips=[clip]
        var material=Arrangement.materialize(project,track:source,section:Section(name:"Recording",start:clip.start,length:clip.length))
        material.length=max(barTicks,((clip.length+barTicks-1)/barTicks)*barTicks)
        var candidate=project;candidate.patterns.append(material)
        candidate.tracks[trackIndex].clips[clipIndex].patternID=material.id;candidate.tracks[trackIndex].clips[clipIndex].offset=0
        candidate.removeUnusedPatterns()
        try candidate.validate()
        self.project=candidate;projectID=project.id;trackID=track.id;self.clipID=clipID;sourcePatternID=clip.patternID;patternID=material.id;start=clip.start;length=clip.length
    }
    /// A touch outside the actual selected clip never wraps into its pattern.
    public func localTick(_ absolute:Int)->Int? {
        guard absolute>=start,absolute<start+length else{return nil};return absolute-start
    }
    /// `timing`: how the take was set to sit in time while recording (55); hits keep `played`.
    @discardableResult public mutating func commitPass(_ events:[DrumEvent],replacing absoluteRange:Range<Int>?=nil,timing:TakeTiming?=nil)throws->Bool {
        guard events.count<=4096,events.allSatisfy({$0.tick>=0 && $0.tick<length}),let index=project.patterns.firstIndex(where:{$0.id==patternID})else{throw MusicError.invalidProject}
        if let absoluteRange{guard absoluteRange.lowerBound>=0,absoluteRange.upperBound<=songTickLimit else{throw MusicError.invalidProject}}
        var candidate=project
        let before=candidate.patterns[index].drums,beforeTakes=candidate.patterns[index].drumTakes
        if let absoluteRange{candidate.patterns[index].drums.removeAll{absoluteRange.contains(start+$0.tick)}}
        let tagged=events.map{event->DrumEvent in var hit=event;hit.take=takeID;return hit}
        var dropped:[DrumEvent]=[]
        candidate.patterns[index].drums.append(contentsOf:Self.singleAttacks(tagged,over:candidate.patterns[index].drums,velocities:&candidate.patterns[index].drums,dropped:&dropped))
        Self.registerTake(takeID,in:&candidate.patterns[index],timing:timing,held:dropped.filter{$0.played != nil})
        try candidate.validate()
        let edited=before != candidate.patterns[index].drums
        if edited{passHistory.append((before,beforeTakes));if passHistory.count>16{passHistory.removeFirst()}}
        project=candidate;changed = changed || edited;return edited
    }
    /// I8: remove the most recent committed pass without stopping the loop.
    /// Returns false when there is nothing to undo.
    @discardableResult public mutating func undoLastPass()->Bool {
        guard let previous=passHistory.popLast(),let index=project.patterns.firstIndex(where:{$0.id==patternID})else{return false}
        project.patterns[index].drums=previous.drums
        project.patterns[index].drumTakes=previous.takes
        Self.registerTake(takeID,in:&project.patterns[index])
        return true
    }
    /// The take is listed while it owns hits, numbered after the takes already there.
    static func registerTake(_ id:UUID,in pattern:inout Pattern,timing:TakeTiming?=nil,held:[DrumEvent]=[]) {
        let owns=pattern.drums.contains{$0.take==id}
        var takes=pattern.drumTakes ?? []
        if owns,!takes.contains(where:{$0.id==id}){var take=DrumTake(id:id,number:(takes.map(\.number).max() ?? 0)+1);take.timing=timing;takes.append(take)}
        if !owns{takes.removeAll{$0.id==id}}
        if let index=takes.firstIndex(where:{$0.id==id}),!held.isEmpty{
            let kept=Array(((takes[index].held ?? [])+held).suffix(4096))
            takes[index].held=kept.isEmpty ? nil:kept
        }
        pattern.drumTakes=takes.isEmpty ? nil:takes
    }
    /// Build 44: one contact gives one audible attack. A recorded hit that lands
    /// on a pad/tick already sounding in the pattern (overdub over the same
    /// step) or on another hit of this pass (two fast touches quantized to one
    /// step) does not stack a second identical voice; the louder velocity wins.
    /// Pre-existing pattern events are never removed or re-identified.
    /// 55: hits that do not get their own attack are reported in `dropped`, so the take can bring
    /// them back when it moves to the natural feel.
    static func singleAttacks(_ events:[DrumEvent],over existing:[DrumEvent],velocities pattern:inout [DrumEvent])->[DrumEvent] {
        var dropped:[DrumEvent]=[]
        return singleAttacks(events,over:existing,velocities:&pattern,dropped:&dropped)
    }
    static func singleAttacks(_ events:[DrumEvent],over existing:[DrumEvent],velocities pattern:inout [DrumEvent],dropped:inout [DrumEvent])->[DrumEvent] {
        var positions:[Int:Int]=[:]
        for (offset,event) in existing.enumerated() where positions[event.tick*16+event.pad]==nil {positions[event.tick*16+event.pad]=offset}
        var added:[DrumEvent]=[],addedPositions:[Int:Int]=[:]
        for event in events {
            let key=event.tick*16+event.pad
            if let offset=positions[key]{pattern[offset].velocity=max(pattern[offset].velocity,event.velocity);dropped.append(event)}
            else if let offset=addedPositions[key]{added[offset].velocity=max(added[offset].velocity,event.velocity);dropped.append(event)}
            else{addedPositions[key]=added.count;added.append(event)}
        }
        return added
    }
    /// Merge musical data only. Mixer/MIDI changes made while playing survive;
    /// a deleted/replaced source clip makes this draft stale instead of guessing.
    public func candidate(for current:Project)throws->Project {
        guard current.id==projectID,let track=current.tracks.firstIndex(where:{$0.id==trackID}),let clip=current.tracks[track].clips.firstIndex(where:{$0.id==clipID}),current.tracks[track].clips[clip].patternID==sourcePatternID,let material=project.patterns.first(where:{$0.id==patternID}),let draftClip=project.tracks.first(where:{$0.id==trackID})?.clips.first(where:{$0.id==clipID})else{throw AssistantError.stale}
        var result=current;result.patterns.append(material);result.tracks[track].clips[clip]=draftClip
        result.removeUnusedPatterns()
        try result.validate();return result
    }
}
