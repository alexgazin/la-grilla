import Foundation

public struct MasterFX:Codable,Equatable,Sendable {
    public var filter:Double;public var delayWet:Double
    public init(filter:Double=0,delayWet:Double=0){self.filter=filter;self.delayWet=delayWet}
    public func validate()throws{guard filter.isFinite,(-1...1).contains(filter),delayWet.isFinite,(0...0.5).contains(delayWet)else{throw MusicError.invalidProject}}
}
public struct PerformanceEvent:Codable,Equatable,Sendable {
    public enum Kind:Int,Codable,Sendable {case section=1,jump,repeatSize,filter,delay,gain,pan,pad,preview}
    public var frame:UInt64;public var kind:Kind;public var value:Double;public var track:Int?;public var sectionID:UUID?;public var pad:Int?;public var note:NoteEvent?;public var instrument:Int?
    public init(frame:UInt64,kind:Kind,value:Double=0,track:Int?=nil,sectionID:UUID?=nil,pad:Int?=nil,note:NoteEvent?=nil,instrument:Int?=nil){self.pad=pad;self.note=note;self.instrument=instrument;self.frame=frame;self.kind=kind;self.value=value;self.track=track;self.sectionID=sectionID}
    public func validate(source:Project,duration:UInt64)throws {
        guard frame<=duration,value.isFinite else{throw MusicError.invalidProject}
        if kind != .pad && kind != .preview{guard pad==nil,note==nil,instrument==nil else{throw MusicError.invalidProject}}
        switch kind {
        case .section:guard value==0,track==nil,let sectionID,source.sections.contains(where:{$0.id==sectionID})else{throw MusicError.invalidProject}
        case .jump:guard sectionID==nil,track==nil,[-4.0,-1,1,4].contains(value)else{throw MusicError.invalidProject}
        case .repeatSize:guard sectionID==nil,track==nil,[0.0,240,480,960,1920].contains(value)else{throw MusicError.invalidProject}
        case .filter:guard sectionID==nil,track==nil,(-1...1).contains(value)else{throw MusicError.invalidProject}
        case .delay:guard sectionID==nil,track==nil,(0...0.5).contains(value)else{throw MusicError.invalidProject}
        case .gain:guard sectionID==nil,let track,(0..<source.tracks.count).contains(track) || track==masterBus,(0...2).contains(value)else{throw MusicError.invalidProject}
        case .pan:guard sectionID==nil,let track,(0..<source.tracks.count).contains(track),(-1...1).contains(value)else{throw MusicError.invalidProject}
        case .pad:guard sectionID==nil,track==1,let pad,(0..<16).contains(pad),note==nil,instrument==nil,(1...127).contains(value),value.rounded()==value else{throw MusicError.invalidProject}
        case .preview:guard sectionID==nil,pad==nil,let note,note.tick==0,note.duration>0,note.duration<=barTicks,(0...127).contains(note.pitch),(1...127).contains(note.velocity),let instrument,(0...3).contains(instrument),let track,(0..<source.tracks.count).contains(track)else{throw MusicError.invalidProject}
        }
    }
}
public struct PerformanceTake:Codable,Equatable,Identifiable,Sendable {
    public var id:UUID=UUID();public var name:String;public var created=Date()
    public var source:Project;public var sourceRevision:Int;public var sampleRate:Double
    public var durationFrames:UInt64;public var events:[PerformanceEvent]
    public var seed:UInt32=0x4c47524c
    public var durationSeconds:Double{Double(durationFrames)/sampleRate}
    public init(name:String="Performance",source:Project,sampleRate:Double,durationFrames:UInt64,events:[PerformanceEvent]){self.name=name;var frozen=source;frozen.performanceTake=nil;self.source=frozen;sourceRevision=source.revision;self.sampleRate=sampleRate;self.durationFrames=durationFrames;self.events=events}
    public func validate()throws {
        guard source.performanceTake==nil,source.revision==sourceRevision,seed==0x4c47524c,!name.isEmpty,name.count<=80,created.timeIntervalSinceReferenceDate.isFinite,sampleRate.isFinite,(8000...192000).contains(sampleRate),durationFrames>0,(1...16384).contains(events.count)else{throw MusicError.invalidProject}
        try source.validate()
        guard Double(durationFrames)<=Double(64*barTicks)/Double(ppq)*60/source.bpm*sampleRate,events[0].frame==0,events[0].kind == .section,try JSONEncoder().encode(source).count<=2_000_000 else{throw MusicError.limit}
        var previous:UInt64=0;var sameFrame=0
        for event in events{guard event.frame>=previous else{throw MusicError.invalidProject};sameFrame=event.frame==previous ? sameFrame+1:1;guard sameFrame<=512 else{throw MusicError.tooDense};try event.validate(source:source,duration:durationFrames);previous=event.frame}
    }
}
