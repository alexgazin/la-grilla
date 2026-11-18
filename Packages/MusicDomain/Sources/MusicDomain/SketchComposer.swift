import Foundation

public enum SketchStyle:String,Codable,CaseIterable,Sendable {
    case house,hipHop,jazz
    public var title:String{switch self{case .house:"House";case .hipHop:"Hip-hop";case .jazz:"Jazz"}}
}
public enum SketchError:Error,LocalizedError {
    case invalidPlan,requiresEmpty
    public var errorDescription:String? {
        let key=switch self {
        case .invalidPlan:"Choose House, Hip-hop or Jazz, 4, 8 or 16 bars, and a tempo of 40–240 BPM."
        case .requiresEmpty:"Create an empty project before generating a new sketch. Your existing music is kept."
        }
        return NSLocalizedString(key,comment:"Editable musical sketch")
    }
}
/// Versioned parameters, never model-supplied note arrays or persistent IDs.
public struct SketchPlan:Codable,Equatable,Sendable {
    public var version=1
    public var style:SketchStyle
    public var bpm:Double
    public var root:Int
    public var minor:Bool
    public var bars:Int
    public var seed:UInt32
    public init(style:SketchStyle,bpm:Double,root:Int,minor:Bool,bars:Int,seed:UInt32=1){self.style=style;self.bpm=bpm;self.root=root;self.minor=minor;self.bars=bars;self.seed=seed}
    public func validate()throws {
        guard version==1,bpm.isFinite,(40...240).contains(bpm),(0..<12).contains(root),[4,8,16].contains(bars)else{throw SketchError.invalidPlan}
    }
}

/// A deterministic, local MIDI composer. It creates new music from bounded
/// parameters; it does not reuse drum/melody events or claim generated audio.
public enum SketchComposer {
    public static func accepts(_ project:Project)->Bool {
        project.patterns.allSatisfy{$0.chords.isEmpty && $0.drums.isEmpty && ($0.notes ?? []).isEmpty}
            && (project.audioAssets ?? []).isEmpty && (project.performanceTakes ?? []).isEmpty
    }
    public static func compose(_ project:Project,plan:SketchPlan,scope:UUID,chordCycle:[Chord] = [])throws->Project {
        try project.validate();try plan.validate()
        guard accepts(project)else{throw SketchError.requiresEmpty}
        guard let selected=project.sections.first(where:{$0.id==scope})else{throw AssistantError.unsafe}
        var random=Random(seed:plan.seed)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard chordCycle.count <= plan.bars else { throw TrackBriefError.tooManyChords }
        for chord in chordCycle { try chord.validate() }
        var namespace=project.id.uuidString+"/"+String(project.revision)+"/"+String(decoding:try encoder.encode(plan),as:UTF8.self)
        if !chordCycle.isEmpty { namespace += "/" + String(decoding:try encoder.encode(chordCycle),as:UTF8.self) }
        var identities=Identities(namespace:namespace)
        let progression=progression(plan,variation:random.pick(3))
        let length=plan.bars*barTicks
        var harmony=Pattern(length:length);harmony.id=try identities.next()
        var drums=Pattern(length:length);drums.id=try identities.next()
        var melody=Pattern(length:length);melody.id=try identities.next()
        for bar in 0..<plan.bars {
            let component=progression[bar%progression.count]
            let root=(plan.root+component.0)%12
            let base=60+root
            // Explicit pitches avoid the legacy C/C-sharp register jump.
            var chord=Chord(root:root,quality:component.1,voicedNotes:component.1.intervals.map{base+$0},rootBassPitch:36+root+project.bassOctave*12)
            if !chordCycle.isEmpty {
                chord = chordCycle[bar % chordCycle.count]
                chord.rootBassPitch = 36 + (chord.slashBass ?? chord.root) + project.bassOctave * 12
            }
            var event=ChordEvent(tick:bar*barTicks,chord:chord);event.id=try identities.next()
            harmony.chords.append(event)
            for hit in hits(plan.style,bar:bar,random:&random) {
                var event=DrumEvent(tick:bar*barTicks+hit.tick,pad:hit.pad,velocity:hit.velocity)
                event.id=try identities.next();drums.drums.append(event)
            }
            let tones=chord.notes.map{pitch in var value=pitch;while value>84{value-=12};while value<60{value+=12};return value}
            let phrase=motif(plan.style,bar:bar,random:&random)
            for (index,onset) in phrase.enumerated() {
                // Chord tones anchor the line; a seeded, short contour varies
                // actual pitches as well as velocities, with clear bar edges.
                let pitch=tones[(index+random.pick(tones.count))%tones.count]
                let next=index+1<phrase.count ? phrase[index+1]:barTicks
                let duration=max(120,min(next-onset-40,plan.style == .hipHop ? 600:400))
                var event=NoteEvent(tick:bar*barTicks+onset,duration:duration,pitch:pitch,velocity:76+random.pick(25))
                event.id=try identities.next();melody.notes?.append(event)
            }
        }
        var result=project
        result.bpm=plan.bpm;result.keyRoot=plan.root;result.minor=plan.minor
        result.sections=[Section(name:selected.name,length:length)];result.sections[0].id=scope
        result.patterns=[harmony,drums,melody]
        for i in result.tracks.indices{result.tracks[i].clips=[]}
        if !result.tracks.contains(where:{$0.role == .bass}) {
            guard result.tracks.count<8 else{throw MusicError.trackLimit}
            var bass=Track(role:.bass);bass.id=try identities.next();bass.gain = -9;result.tracks.append(bass)
        }
        if !result.tracks.contains(where:{$0.role == .melody}) {
            guard result.tracks.count<8 else{throw MusicError.trackLimit}
            var lead=Track(role:.melody);lead.id=try identities.next();lead.gain = -12;result.tracks.append(lead)
        }
        let melodyID=result.tracks.first{$0.role == .melody}!.id
        for i in result.tracks.indices {
            let pattern:Pattern?
            switch result.tracks[i].role {
            case .harmony:pattern=harmony
            case .drums:pattern=drums
            case .bass:pattern=nil
            case .melody:pattern=result.tracks[i].id==melodyID ? melody:nil
            }
            if let pattern{var clip=Clip(patternID:pattern.id,start:0,length:length);clip.id=try identities.next();result.tracks[i].clips=[clip]}
        }
        try result.validate()
        return result
    }
    private static func progression(_ plan:SketchPlan,variation:Int)->[(Int,Quality)] {
        if plan.style == .jazz {
            let values:[(Int,Quality)]=plan.minor ? [(2,.m7b5),(7,.seventh),(0,.m7),(8,.maj7)]:[(2,.m7),(7,.seventh),(0,.maj7),(9,.m7)]
            let shift=variation==0 ? 0:variation==1 ? 2:3
            return (0..<4).map{values[($0+shift)%4]}
        }
        let offsets=plan.minor ? [[0,8,5,10],[0,5,8,10],[8,10,0,5]]:[[0,9,5,7],[0,5,9,7],[9,5,0,7]]
        return offsets[variation].map{offset in
            let minor=plan.minor ? [0,5].contains(offset):offset==9
            return (offset,minor ? .minor:.major)
        }
    }
    private struct Hit {let tick:Int;let pad:Int;let velocity:Int}
    private static func hits(_ style:SketchStyle,bar:Int,random:inout Random)->[Hit] {
        var hits:[Hit]=[]
        func hit(_ tick:Int,_ pad:Int,_ velocity:Int){hits.append(Hit(tick:tick,pad:pad,velocity:velocity))}
        switch style {
        case .house:
            for tick in stride(from:0,to:barTicks,by:ppq){hit(tick,0,104)}
            for tick in [ppq,3*ppq]{hit(tick,4,88)}
            for tick in stride(from:ppq/2,to:barTicks,by:ppq){hit(tick,2,68+random.pick(14))}
            if bar%4==3{hit(3*ppq+ppq/2,3,70+random.pick(15))}
        case .hipHop:
            for tick in [0,ppq+ppq/2,2*ppq+ppq/4]{hit(tick,0,98+random.pick(12))}
            for tick in [ppq,3*ppq]{hit(tick,1,95)}
            for tick in stride(from:0,to:barTicks,by:ppq/2){hit(tick,2,58+random.pick(28))}
            if bar%2==1{hit(3*ppq+3*ppq/4,2,55+random.pick(20))}
        case .jazz:
            for beat in 0..<4{hit(beat*ppq,10,62+random.pick(18));hit(beat*ppq+2*ppq/3,10,48+random.pick(16))}
            for tick in [ppq,3*ppq]{hit(tick,1,52+random.pick(18))}
            hit(0,0,70);hit(2*ppq,0,64)
        }
        return hits.sorted{$0.tick==$1.tick ? $0.pad<$1.pad:$0.tick<$1.tick}
    }
    private static func motif(_ style:SketchStyle,bar:Int,random:inout Random)->[Int] {
        let positions:[Int]
        switch style {
        case .house:positions=bar%2==0 ? [0,480,960,1680,1920,2400,2880]:[0,720,1440,1920,2640,3360]
        case .hipHop:positions=bar%2==0 ? [0,720,1440,2400]:[240,960,1920,2640]
        case .jazz:positions=[0,640,960,1600,1920,2560,2880,3520]
        }
        let chosen=positions.filter{_ in random.pick(style == .hipHop ? 7:6) != 0}
        return chosen.isEmpty ? [0]:chosen
    }
    private struct Random {
        var state:UInt64
        init(seed:UInt32){state=UInt64(seed)}
        mutating func pick(_ count:Int)->Int {
            state &+= 0x9e3779b97f4a7c15
            var z=state;z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9;z=(z^(z>>27)) &* 0x94d049bb133111eb
            return Int((z^(z>>31))%UInt64(count))
        }
    }
    private struct Identities {
        let namespace:String
        var index=0
        mutating func next()throws->UUID {
            let hex=Array(try AssetIntegrity.sha256(Data((namespace+"/"+String(index)).utf8)).prefix(32));index+=1
            let value=[String(hex[0..<8]),String(hex[8..<12]),String(hex[12..<16]),String(hex[16..<20]),String(hex[20..<32])].joined(separator:"-")
            guard let id=UUID(uuidString:value)else{throw AssistantError.unsafe};return id
        }
    }
}

enum SketchCommandParser {
    static func recognizes(_ text:String)->Bool {
        let text=text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        return text.hasPrefix("create ") || text.hasPrefix("создай ")
    }
    private static func captures(_ pattern:String,_ text:String)->[String]? {
        guard let regex=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),
              let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),match.range.length==(text as NSString).length else{return nil}
        return (1..<match.numberOfRanges).map{index in Range(match.range(at:index),in:text).map{String(text[$0])} ?? ""}
    }
    static func propose(_ text:String,project:Project,scope:UUID)throws->AssistantProposal {
        let clauses=text.split(separator:";",omittingEmptySubsequences:false).map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}
        guard (1...6).contains(clauses.count),clauses.allSatisfy({!$0.isEmpty && $0.count<=200}),
              let command=captures("^(?:create\\s+(?:(?:a|an)\\s+)?|создай\\s+)(.+?)\\s+(?:groove|грув)$",clauses[0])else{throw AssistantError.unsupported}
        let styles:[String:SketchStyle]=["house":.house,"хаус":.house,"хаусовый":.house,"hip-hop":.hipHop,"hip hop":.hipHop,"хип-хоп":.hipHop,"хип хоп":.hipHop,"хипхоп":.hipHop,"jazz":.jazz,"джаз":.jazz,"джазовый":.jazz]
        guard let style=styles[command[0].lowercased()]else{throw SketchError.invalidPlan}
        var plan=SketchPlan(style:style,bpm:project.bpm,root:project.keyRoot,minor:project.minor,bars:4)
        var used=Set<String>()
        for clause in clauses.dropFirst() {
            if let bars=captures("^([0-9]{1,2})\\s*(?:bars?|тактов|такта|такт)$",clause),let value=Int(bars[0]) {
                guard used.insert("bars").inserted else{throw SketchError.invalidPlan};plan.bars=value;continue
            }
            if let seed=captures("^(?:seed|вариант)\\s+([0-9]{1,10})$",clause),let value=UInt32(seed[0]) {
                guard used.insert("seed").inserted else{throw SketchError.invalidPlan};plan.seed=value;continue
            }
            let proposal=try AssistantEngine.propose(clause,project:project,sectionID:scope)
            guard proposal.operations.count==1,let operation=proposal.operations.first else{throw AssistantError.unsupported}
            switch operation.type {
            case .setTempo:guard used.insert("tempo").inserted else{throw SketchError.invalidPlan};plan.bpm=operation.bpm!
            case .setKey:guard used.insert("key").inserted else{throw SketchError.invalidPlan};plan.root=operation.root!;plan.minor=operation.minor!
            default:throw AssistantError.unsupported
            }
        }
        try plan.validate()
        let proposal=AssistantProposal(project:project,scope:scope,operations:[.init(.generateSketch,sketch:plan)],assumptions:[NSLocalizedString("The notes are composed locally from the displayed style and seed. Existing mixer settings are kept.",comment:"Musical sketch")])
        _ = try proposal.candidate(for:project)
        return proposal
    }
}
