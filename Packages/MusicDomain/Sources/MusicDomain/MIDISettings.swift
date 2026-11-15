import Foundation

public struct MIDIMapping:Codable,Equatable,Identifiable,Sendable {
    public enum Target:String,Codable,CaseIterable,Sendable {case masterGain,trackGain,trackPan,filter,delay}
    public var id=UUID();public var sourceID:Int32;public var channel:Int;public var controller:Int;public var target:Target;public var trackID:UUID?
    public init(sourceID:Int32,channel:Int,controller:Int,target:Target,trackID:UUID?=nil){self.sourceID=sourceID;self.channel=channel;self.controller=controller;self.target=target;self.trackID=trackID}
    public func validate(_ project:Project)throws {
        guard (0..<16).contains(channel),(0...127).contains(controller),controller != 64,controller<120 else{throw MusicError.invalidProject}
        if target == .trackGain || target == .trackPan{guard let trackID,project.tracks.contains(where:{$0.id==trackID})else{throw MusicError.invalidProject}}else{guard trackID==nil else{throw MusicError.invalidProject}}
    }
    public func value(_ byte:Int)->Double {
        let unit=Double(min(127,max(0,byte)))/127
        switch target {case .masterGain,.trackGain:return byte==0 ? -61:unit*66-60;case .trackPan:return unit*2-1;case .filter:return byte==64 ? 0:(unit*2-1);case .delay:return unit*0.5}
    }
}
public struct MIDISettings:Codable,Equatable,Sendable {
    public var enabled=false;public var inputIDs:[Int32]=[];public var outputID:Int32?
    public var channel:Int?;public var trackID:UUID?;public var mappings:[MIDIMapping]=[]
    public init(){}
    public func validate(_ project:Project)throws {
        guard inputIDs.count<=16,Set(inputIDs).count==inputIDs.count,mappings.count<=16,Set(mappings.map(\.id)).count==mappings.count,channel==nil || (0..<16).contains(channel!),trackID==nil || project.tracks.contains(where:{$0.id==trackID})else{throw MusicError.invalidProject}
        var keys=Set<String>()
        for mapping in mappings{try mapping.validate(project);guard keys.insert("\(mapping.sourceID):\(mapping.channel):\(mapping.controller)").inserted else{throw MusicError.invalidProject}}
    }
    public func mapping(sourceID:Int32,channel:Int,controller:Int)->MIDIMapping?{mappings.first{$0.sourceID==sourceID && $0.channel==channel && $0.controller==controller}}
}
