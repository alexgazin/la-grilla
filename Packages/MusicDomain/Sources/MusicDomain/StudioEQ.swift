import AudioDSP
import Foundation

public enum EQFilter:Int32,Codable,CaseIterable,Sendable {
    case bell=1, lowShelf, highShelf, highPass, lowPass
    public var title:String {
        switch self { case .bell:"Bell"; case .lowShelf:"Low shelf"; case .highShelf:"High shelf"; case .highPass:"High-pass"; case .lowPass:"Low-pass" }
    }
    public var hasGain:Bool { self != .highPass && self != .lowPass }
}

public struct EQBand: Codable,Equatable,Sendable {
    public var filter:EQFilter
    public var frequency:Double
    public var gain:Double
    public var q:Double
    public var enabled:Bool
    public init(_ filter:EQFilter,_ frequency:Double,_ gain:Double=0,_ q:Double=0.707,enabled:Bool=true) {
        self.filter=filter; self.frequency=frequency; self.gain=gain; self.q=q; self.enabled=enabled
    }
    fileprivate func kernel(enabled global:Bool)->LGEQBand {
        LGEQBand(kind:global && enabled ? filter.rawValue:0,frequency:Float(frequency),gainDB:Float(gain),q:Float(q))
    }
}
public struct StudioEQ:Codable,Equatable,Sendable {
    public var enabled=true
    public var bands=[EQBand(.lowShelf,100),EQBand(.bell,420),EQBand(.bell,2500),EQBand(.highShelf,9000)]
    public init() {}
    public func validate() throws {
        guard bands.count==4,bands.allSatisfy({(20...20000).contains($0.frequency) && (-18...18).contains($0.gain) && (0.25...8).contains($0.q)}) else { throw MusicError.invalidProject }
    }
    public func response(at frequencies:[Double],rate:Double)->[Double] {
        guard bands.count==4 else { return frequencies.map{_ in 0} }
        return bands.map{$0.kernel(enabled:enabled)}.withUnsafeBufferPointer { b in
            frequencies.map { lg_eq_response(b.baseAddress,rate,$0) }
        }
    }
}
public extension Project {
    func equalizerBands(includeMaster:Bool=true)->[LGEQBand] {
        var result=[LGEQBand](repeating:LGEQBand(),count:(masterBus+1)*4)
        func install(_ eq:StudioEQ?,_ bus:Int) {
            guard let eq,eq.enabled,eq.bands.count==4 else{return}
            for (i,band) in eq.bands.enumerated(){result[bus*4+i]=band.kernel(enabled:true)}
        }
        for (i,track) in tracks.prefix(masterBus).enumerated(){install(track.equalizer,i)}
        if includeMaster{install(masterEQ,masterBus)}
        return result
    }
}
public struct EQPreset:Identifiable,Sendable {
    public let name:String
    public let family:String
    public let settings:StudioEQ
    public var id:String {name}
    private init(_ group:String,_ name:String,_ edits:[EQBand]){
        self.family=group;self.name=name
        var eq=StudioEQ()
        for i in edits.indices {eq.bands[i]=edits[i]}
        settings=eq
    }
    public static let library:[EQPreset]=[
        .init("General","Flat",[]),
        .init("General","Low rumble cut",[.init(.highPass,45)]),
        .init("General","Subsonic cut",[.init(.highPass,26)]),
        .init("General","Warm tilt",[.init(.lowShelf,190,2),.init(.highShelf,3800,-2)]),
        .init("General","Bright tilt",[.init(.lowShelf,190,-2),.init(.highShelf,4200,2)]),
        .init("General","Pocket radio",[.init(.highPass,350),.init(.bell,1500,3,1.1),.init(.lowPass,3600)]),
        .init("Saxophone","Breathy alto",[.init(.highPass,105),.init(.bell,550,-1.5),.init(.highShelf,6800,3)]),
        .init("Saxophone","Warm tenor",[.init(.lowShelf,220,2.8),.init(.bell,2400,-2,1.3),.init(.highShelf,7200,-1.5)]),
        .init("Saxophone","Reed presence",[.init(.highPass,85),.init(.bell,1800,3.4,1.1)]),
        .init("Saxophone","Soft brass",[.init(.bell,3100,-3.2,1.6),.init(.highShelf,7000,-2)]),
        .init("Saxophone","Solo horn",[.init(.highPass,100),.init(.bell,360,-2),.init(.bell,1600,2.7),.init(.highShelf,8900,1.5)]),
        .init("Drums","Kick weight",[.init(.lowShelf,76,4),.init(.bell,280,-3,1.1)]),
        .init("Drums","Kick attack",[.init(.highPass,29),.init(.bell,340,-2.5),.init(.bell,3200,3.5)]),
        .init("Drums","Snare snap",[.init(.highPass,95),.init(.bell,200,2),.init(.bell,3300,3)]),
        .init("Drums","Silky hats",[.init(.highPass,420),.init(.bell,7400,-3.5,1.6),.init(.highShelf,11500,1.5)]),
        .init("Drums","Drum bus punch",[.init(.lowShelf,82,2),.init(.bell,460,-2),.init(.highShelf,7900,1.8)]),
        .init("Bass","Round sub",[.init(.highPass,28),.init(.lowShelf,90,2.5),.init(.lowPass,4100)]),
        .init("Bass","Small speaker bass",[.init(.highPass,40),.init(.bell,190,3),.init(.bell,850,2.2)]),
        .init("Bass","Clear bass line",[.init(.lowShelf,56,-1.5),.init(.bell,320,-3),.init(.bell,1300,2.5)]),
        .init("Keys and strings","Felt piano",[.init(.lowShelf,170,1.7),.init(.bell,2750,-2),.init(.highShelf,6500,-3)]),
        .init("Keys and strings","Concert piano",[.init(.highPass,45),.init(.bell,330,-2.4),.init(.highShelf,6200,2)]),
        .init("Keys and strings","Nylon clarity",[.init(.highPass,76),.init(.bell,220,-2.8),.init(.bell,2600,2)]),
        .init("Keys and strings","Velvet keys",[.init(.lowShelf,210,2),.init(.bell,1800,-2),.init(.lowPass,8400)]),
        .init("Master","Mix air",[.init(.highShelf,10800,1.7)]),
        .init("Master","Mix glue curve",[.init(.lowShelf,110,1.1),.init(.bell,480,-1),.init(.highShelf,7800,1)]),
        .init("Master","Tame harshness",[.init(.bell,3400,-2.2,1.7),.init(.highShelf,9200,-1)]),
        .init("Master","Deep club",[.init(.highPass,24),.init(.lowShelf,80,1.8),.init(.bell,310,-1.5),.init(.highShelf,10500,0.8)])
    ]
}
