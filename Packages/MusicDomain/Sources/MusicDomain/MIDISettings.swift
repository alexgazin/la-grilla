import Foundation

public struct MIDIMapping:Codable,Equatable,Identifiable,Sendable {
    public enum Target:String,Codable,CaseIterable,Sendable {
        case masterGain,trackGain,trackPan,filter,delay
        /// I52: a melodic track's synth and EQ, its reverb send and drive.
        case synthCutoff,synthResonance,synthAttack,synthRelease,eqLow,eqHigh,reverbSend,drive
        /// True for controls that belong to one track (the mapping names it).
        public var needsTrack:Bool{self != .masterGain && self != .filter && self != .delay}
        public var title:String{
            switch self{
            case .masterGain:"Master gain";case .trackGain:"Track gain";case .trackPan:"Track pan";case .filter:"Master filter";case .delay:"Delay wet"
            case .synthCutoff:"Synth brightness";case .synthResonance:"Synth resonance";case .synthAttack:"Synth attack";case .synthRelease:"Synth release"
            case .eqLow:"EQ low";case .eqHigh:"EQ high";case .reverbSend:"Reverb send";case .drive:"Drive"
            }
        }
    }
    public var id=UUID();public var sourceID:Int32;public var channel:Int;public var controller:Int;public var target:Target;public var trackID:UUID?
    public init(sourceID:Int32,channel:Int,controller:Int,target:Target,trackID:UUID?=nil){self.sourceID=sourceID;self.channel=channel;self.controller=controller;self.target=target;self.trackID=trackID}
    public func validate(_ project:Project)throws {
        guard (0..<16).contains(channel),(0...127).contains(controller),controller != 64,controller<120 else{throw MusicError.invalidProject}
        if target.needsTrack{guard let trackID,project.tracks.contains(where:{$0.id==trackID})else{throw MusicError.invalidProject}}else{guard trackID==nil else{throw MusicError.invalidProject}}
    }
    public func value(_ byte:Int)->Double {
        let unit=Double(min(127,max(0,byte)))/127
        switch target {
        case .masterGain,.trackGain:return byte==0 ? -61:unit*66-60
        case .trackPan:return unit*2-1
        case .filter:return byte==64 ? 0:(unit*2-1)
        case .delay,.reverbSend:return unit*0.5
        case .synthCutoff:return unit
        case .synthResonance:return unit*0.9
        case .synthAttack:return unit*unit*4
        case .synthRelease:return unit*unit*8
        case .eqLow,.eqHigh:return byte==64 ? 0:unit*36-18
        case .drive:return unit*0.7
        }
    }

    /// I52 · Applies a controller value (from `value(_:)`) to the song. False when the target is
    /// missing (no such track, a drum track has no synth).
    @discardableResult public func apply(_ value:Double,to project:inout Project)->Bool {
        func track()->Int?{project.tracks.firstIndex{$0.id==trackID}}
        switch target {
        case .masterGain:project.master=value
        case .trackGain:guard let i=track()else{return false};project.tracks[i].gain=value
        case .trackPan:guard let i=track()else{return false};project.tracks[i].pan=value
        case .filter:var fx=project.masterFX ?? MasterFX();fx.filter=value;project.masterFX=fx
        case .delay:var fx=project.masterFX ?? MasterFX();fx.delayWet=value;project.masterFX=fx
        case .synthCutoff,.synthResonance,.synthAttack,.synthRelease:
            guard let i=track(),project.tracks[i].role != .drums else{return false}
            var patch=project.tracks[i].synth ?? SynthPatch()
            switch target{case .synthCutoff:patch.cutoff=value;case .synthResonance:patch.resonance=value;case .synthAttack:patch.attack=value;default:patch.release=value}
            project.tracks[i].synth=patch
        case .eqLow,.eqHigh:
            guard let i=track()else{return false}
            var eq=project.tracks[i].equalizer ?? StudioEQ()
            eq.bands[target == .eqLow ? 0:3].gain=value
            project.tracks[i].equalizer=eq
        case .reverbSend,.drive:
            guard let i=track()else{return false}
            var dynamics=project.tracks[i].dynamics ?? TrackDynamics()
            if target == .reverbSend{dynamics.reverbSend=value}else{dynamics.drive=value}
            project.tracks[i].dynamics=dynamics
        }
        return true
    }
}
public struct MIDISettings:Codable,Equatable,Sendable {
    public var enabled=false;public var inputIDs:[Int32]=[];public var outputID:Int32?
    public var channel:Int?;public var trackID:UUID?;public var mappings:[MIDIMapping]=[]
    /// I82: send MIDI clock and transport to the output destination. Nil = off.
    public var clockOut:Bool?
    public init(){}
    public func validate(_ project:Project)throws {
        guard inputIDs.count<=16,Set(inputIDs).count==inputIDs.count,mappings.count<=16,Set(mappings.map(\.id)).count==mappings.count,channel==nil || (0..<16).contains(channel!),trackID==nil || project.tracks.contains(where:{$0.id==trackID})else{throw MusicError.invalidProject}
        var keys=Set<String>()
        for mapping in mappings{try mapping.validate(project);guard keys.insert("\(mapping.sourceID):\(mapping.channel):\(mapping.controller)").inserted else{throw MusicError.invalidProject}}
    }
    /// I19: with no chosen track, an external keyboard plays the part being
    /// edited when it is melodic, else the first melody, bass or harmony track.
    public static func automaticTrack(_ tracks:[Track],focused:UUID?)->UUID? {
        if let focused,let track=tracks.first(where:{$0.id==focused}),track.role != .drums{return track.id}
        for role in [TrackRole.melody,.bass,.harmony]{if let track=tracks.first(where:{$0.role==role}){return track.id}}
        return tracks.first?.id
    }
    public func mapping(sourceID:Int32,channel:Int,controller:Int)->MIDIMapping?{mappings.first{$0.sourceID==sourceID && $0.channel==channel && $0.controller==controller}}
}
