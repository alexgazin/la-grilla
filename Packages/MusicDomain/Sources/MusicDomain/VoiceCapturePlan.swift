import Foundation

/// A source take covers one uninterrupted region of the backing arrangement.
/// Ending at the section/loop edge keeps every captured note inside its target.
public struct VoiceCapturePlan:Equatable,Sendable {
    public let sectionID:UUID
    public let startTick:Int
    public let offsetTicks:Int
    public let captureTicks:Int
    public let delay:Double
    public let duration:Double
    public static func make(project:Project,selectedSectionID:UUID,tick:Double,playing:Bool,loop:Bool,range:Range<Int>,minimumLead:Double,maximumDuration:Double=30)throws->VoiceCapturePlan {
        try project.validate()
        guard tick.isFinite,minimumLead.isFinite,minimumLead>=0,minimumLead<=600,maximumDuration.isFinite,maximumDuration>0,maximumDuration<=30,range.lowerBound>=0,range.upperBound<=project.length,!range.isEmpty,
              let selected=project.sections.first(where:{$0.id==selectedSectionID})else{throw MusicError.invalidProject}
        let speed=project.bpm/60*Double(ppq)
        let start:Int,delay:Double
        if !playing {start=selected.start;delay=minimumLead}
        else if loop {
            let length=Double(range.count),raw=(tick-Double(range.lowerBound)).truncatingRemainder(dividingBy:length),position=raw<0 ? raw+length:raw
            let first=length-position
            let cycles=max(0,ceil((minimumLead*speed-first)/length))
            start=range.lowerBound;delay=(first+cycles*length)/speed
        }else {
            let future=tick+minimumLead*speed
            guard future<Double(range.upperBound)else{throw VoiceCapturePlanError.arrangementEnded}
            start=Int(ceil(future/Double(barTicks)))*barTicks
            guard range.contains(start)else{throw VoiceCapturePlanError.arrangementEnded}
            delay=(Double(start)-tick)/speed
        }
        guard let section=project.sections.first(where:{$0.start<=start && start<$0.start+$0.length})else{throw MusicError.invalidProject}
        let edge=playing && loop ? min(section.start+section.length,range.upperBound):section.start+section.length
        let length=min(edge-start,Int((maximumDuration*speed).rounded(.down)))
        guard length>0,delay>=minimumLead-0.000_001,delay<=600 else{throw MusicError.invalidProject}
        return VoiceCapturePlan(sectionID:section.id,startTick:start,offsetTicks:start-section.start,captureTicks:length,delay:max(minimumLead,delay),duration:Double(length)/speed)
    }
    public func place(_ source:[NoteEvent],sectionLength:Int)throws->[NoteEvent] {
        guard sectionLength>0,offsetTicks>=0,offsetTicks<=sectionLength,captureTicks>0,captureTicks<=sectionLength-offsetTicks else{throw MusicError.invalidProject}
        return try source.map{note in
            guard note.tick>=0,note.tick<captureTicks,note.duration>0,note.duration<=captureTicks-note.tick else{throw MusicError.invalidProject}
            var placed=note;placed.tick+=offsetTicks;return placed
        }
    }
}
public enum VoiceCapturePlanError:Error,LocalizedError {
    case arrangementEnded
    public var errorDescription:String?{NSLocalizedString("There is no next bar before the arrangement ends. Loop a section or rewind, then record again.",comment:"")}
}
