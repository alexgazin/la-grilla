import Foundation

/// A recording owns one linear occurrence of a drum clip. Source patterns and
/// other clips remain untouched until this draft is merged in one history edit.
public struct DrumRecordingDraft:Sendable {
    public private(set) var project:Project
    public let projectID:UUID;public let trackID:UUID;public let clipID:UUID
    public let sourcePatternID:UUID;public let patternID:UUID
    public let start:Int;public let length:Int
    public private(set) var changed=false
    public init(project:Project,clipID:UUID)throws {
        try project.validate()
        guard let track=project.tracks.first(where:{$0.role == .drums}),let clip=track.clips.first(where:{$0.id==clipID}),let trackIndex=project.tracks.firstIndex(where:{$0.id==track.id}),let clipIndex=track.clips.firstIndex(where:{$0.id==clipID})else{throw ClipEditingError.missing}
        var source=track;source.clips=[clip]
        var material=Arrangement.materialize(project,track:source,section:Section(name:"Recording",start:clip.start,length:clip.length))
        material.length=max(barTicks,((clip.length+barTicks-1)/barTicks)*barTicks)
        var candidate=project;candidate.patterns.append(material)
        candidate.tracks[trackIndex].clips[clipIndex].patternID=material.id;candidate.tracks[trackIndex].clips[clipIndex].offset=0
        let used=Set(candidate.tracks.flatMap{$0.clips.map(\.patternID)});candidate.patterns.removeAll{!used.contains($0.id)}
        try candidate.validate()
        self.project=candidate;projectID=project.id;trackID=track.id;self.clipID=clipID;sourcePatternID=clip.patternID;patternID=material.id;start=clip.start;length=clip.length
    }
    /// A touch outside the actual selected clip never wraps into its pattern.
    public func localTick(_ absolute:Int)->Int? {
        guard absolute>=start,absolute<start+length else{return nil};return absolute-start
    }
    @discardableResult public mutating func commitPass(_ events:[DrumEvent],replacing absoluteRange:Range<Int>?=nil)throws->Bool {
        guard events.count<=4096,events.allSatisfy({$0.tick>=0 && $0.tick<length}),let index=project.patterns.firstIndex(where:{$0.id==patternID})else{throw MusicError.invalidProject}
        if let absoluteRange{guard absoluteRange.lowerBound>=0,absoluteRange.upperBound<=64*barTicks else{throw MusicError.invalidProject}}
        var candidate=project
        let before=candidate.patterns[index].drums
        if let absoluteRange{candidate.patterns[index].drums.removeAll{absoluteRange.contains(start+$0.tick)}}
        candidate.patterns[index].drums.append(contentsOf:events);try candidate.validate()
        let edited=before != candidate.patterns[index].drums
        project=candidate;changed = changed || edited;return edited
    }
    /// Merge musical data only. Mixer/MIDI changes made while playing survive;
    /// a deleted/replaced source clip makes this draft stale instead of guessing.
    public func candidate(for current:Project)throws->Project {
        guard current.id==projectID,let track=current.tracks.firstIndex(where:{$0.id==trackID}),let clip=current.tracks[track].clips.firstIndex(where:{$0.id==clipID}),current.tracks[track].clips[clip].patternID==sourcePatternID,let material=project.patterns.first(where:{$0.id==patternID}),let draftClip=project.tracks.first(where:{$0.id==trackID})?.clips.first(where:{$0.id==clipID})else{throw AssistantError.stale}
        var result=current;result.patterns.append(material);result.tracks[track].clips[clip]=draftClip
        let used=Set(result.tracks.flatMap{$0.clips.map(\.patternID)});result.patterns.removeAll{!used.contains($0.id)}
        try result.validate();return result
    }
}
