import Foundation

public enum HarmonyStyle:String,CaseIterable,Sendable {
    case voiceLeading,gentle,expressive,reharmonize
    public var title:String{switch self{case .voiceLeading:"Voice leading";case .gentle:"Gentle";case .expressive:"Expressive";case .reharmonize:"Reharmonize"}}
}
public enum HarmonyVoicing:String,CaseIterable,Sendable {
    case complete="Complete voicing",compact="Compact jazz voicing"
}
public struct HarmonyOptions:Sendable {
    public var style:HarmonyStyle;public var low:Int;public var high:Int
    public var voicing:HarmonyVoicing
    public init(style:HarmonyStyle = .gentle,low:Int=48,high:Int=84,voicing:HarmonyVoicing = .complete){self.style=style;self.low=low;self.high=high;self.voicing=voicing}
}
public enum HarmonyError:Error,LocalizedError {
    case empty,range,stale
    public var errorDescription:String?{let key=switch self{case .empty:"Add chords to this section first.";case .range:"Widen the register to fit all chord tones.";case .stale:"The project changed. Generate a fresh proposal before applying."};return NSLocalizedString(key,comment:"Harmony lab")}
}
public struct HarmonyChange:Identifiable,Sendable {
    public let id:UUID;public let tick:Int;public let before:Chord;public let after:Chord;public let chromatic:Bool
}
public struct HarmonyProposal:Identifiable,Sendable {
    public let id:UUID;public let projectID:UUID;public let revision:Int;public let sectionID:UUID
    public let candidate:Project;public let changes:[HarmonyChange];public let style:HarmonyStyle
    public func apply(to project:inout Project)throws {
        guard project.id==projectID,project.revision==revision else{throw HarmonyError.stale}
        project=candidate
    }
}

public enum Arrangement {
    /// Materialize a section, including repeats, offsets and chased chord boundaries.
    public static func harmony(_ p:Project,section:Section)->[ChordEvent] {
        guard let track=p.tracks.first(where:{$0.role == .harmony})else{return []}
        var events:[ChordEvent]=[]
        for c in track.clips {
            guard let pattern=p.patterns.first(where:{$0.id==c.patternID})else{continue}
            for cycle in stride(from:-c.offset,to:c.length,by:pattern.length){for e in pattern.chords{
                let start=max(c.start,c.start+cycle+e.tick,section.start)
                let end=min(c.start+c.length,c.start+cycle+e.tick+e.duration,section.start+section.length)
                if end>start{events.append(ChordEvent(tick:start-section.start,duration:end-start,chord:e.chord,velocity:e.velocity))}
            }}
        }
        return events.sorted{$0.tick<$1.tick}
    }
    /// Split crossing clip instances and create an independent section pattern.
    public static func replaceHarmony(_ events:[ChordEvent],in section:Section,project:inout Project)throws {
        guard let index=project.tracks.firstIndex(where:{$0.role == .harmony}),project.sections.contains(where:{$0.id==section.id})else{throw MusicError.invalidProject}
        let end=section.start+section.length
        var clips:[Clip]=[]
        for c in project.tracks[index].clips {
            let clipEnd=c.start+c.length
            if clipEnd<=section.start || c.start>=end{clips.append(c);continue}
            if c.start<section.start {var left=c;left.id=UUID();left.length=section.start-c.start;clips.append(left)}
            if clipEnd>end,let pattern=project.patterns.first(where:{$0.id==c.patternID}){var right=c;right.id=UUID();right.start=end;right.length=clipEnd-end;right.offset=(c.offset+end-c.start)%pattern.length;clips.append(right)}
        }
        let pattern=Pattern(length:section.length,chords:events)
        project.patterns.append(pattern);clips.append(Clip(patternID:pattern.id,start:section.start,length:section.length));project.tracks[index].clips=clips.sorted{$0.start<$1.start}
        project.removeUnusedPatterns()
    }
}

public enum HarmonyLab {
    public static func propose(_ project:Project,sectionID:UUID,options:HarmonyOptions=HarmonyOptions())throws->HarmonyProposal {
        try project.validate()
        guard (24...96).contains(options.low),(36...108).contains(options.high),options.high-options.low>=12,options.high-options.low<=60 else{throw HarmonyError.range}
        guard let section=project.sections.first(where:{$0.id==sectionID})else{throw MusicError.invalidProject}
        let original=Arrangement.harmony(project,section:section);guard !original.isEmpty else{throw HarmonyError.empty}
        let scale=Set((project.minor ? [0,2,3,5,7,8,10]:[0,2,4,5,7,9,11]).map{($0+project.keyRoot)%12})
        var output:[ChordEvent]=[];var changes:[HarmonyChange]=[];var previous:[Int]=[]
        for (index,e) in original.enumerated(){
            var chord=e.chord;chord.voicedNotes=nil;chord.inversion=0
            // A written custom formula is explicit musical content. Styles may
            // revoice it, but never silently replace its intervals or quality.
            if chord.customIntervals==nil{switch options.style {
            case .voiceLeading:break
            case .gentle:
                if chord.quality == .major{chord.quality=(chord.root-project.keyRoot+12)%12==7 ? .seventh:.maj7}
                else if chord.quality == .minor{chord.quality = .m7}
            case .expressive:
                switch chord.quality{case .major,.maj7:chord.quality=(chord.root-project.keyRoot+12)%12==7 ? .thirteenth:.maj9;case .minor,.m7:chord.quality = .m9;case .seventh:chord.quality = .ninth;case .dim:chord.quality = .m7b5;default:break}
            case .reharmonize:
                let next=index+1<original.count ? original[index+1].chord:nil
                if index>0,let next,(chord.root-next.root+12)%12==7,[Quality.seventh,.ninth,.thirteenth].contains(chord.quality){chord.root=(chord.root+6)%12;chord.quality = .flat9;chord.slashBass=nil}
                else if index>0,index<original.count-1,!project.minor,(chord.root-project.keyRoot+12)%12==5,chord.quality == .major{chord.quality = .m7}
            }}
            chord.voicedNotes=try voicing(chord,previous:previous,low:options.low,high:options.high,layout:options.voicing)
            previous=chord.notes
            var event=e;event.id=UUID();event.chord=chord;output.append(event)
            changes.append(HarmonyChange(id:event.id,tick:event.tick,before:e.chord,after:chord,chromatic:chord.notes.contains{!scale.contains($0%12)}))
        }
        var candidate=project;try Arrangement.replaceHarmony(output,in:section,project:&candidate);try candidate.validate()
        return HarmonyProposal(id:UUID(),projectID:project.id,revision:project.revision,sectionID:sectionID,candidate:candidate,changes:changes,style:options.style)
    }
    public static func voicing(_ chord:Chord,previous:[Int],low:Int,high:Int,layout:HarmonyVoicing = .complete)throws->[Int] {
        guard low>=0,high<=127,low<=high,(0..<12).contains(chord.root),Chord.validIntervals(chord.effectiveIntervals),previous.allSatisfy({(0...127).contains($0)}),chord.slashBass==nil || (0..<12).contains(chord.slashBass!)else{throw HarmonyError.range}
        let intervals=layout == .compact ? chord.requiredVoicingIntervals:chord.effectiveIntervals
        var best:[Int]?;var bestScore=Double.infinity
        for inversion in 0..<intervals.count {
            for octave in 1...7 {
                let base=octave*12+chord.root
                var notes=intervals.enumerated().map{base+$0.element+($0.offset<inversion ? 12:0)}.sorted()
                if let slash=chord.slashBass{var bass=notes[0]/12*12+slash;while bass>=notes[0]{bass-=12};notes.append(bass);notes.sort()}
                guard notes.allSatisfy({(low...high).contains($0)}),chord.isValidVoicing(notes) else{continue}
                let center=Double(low+high)/2
                var score=notes.reduce(0.0){$0+abs(Double($1)-center)*0.08}
                if previous.isEmpty{score+=abs(Double(notes.reduce(0,+))/Double(notes.count)-center)}
                else{for n in notes{score+=Double(previous.map{abs($0-n)}.min() ?? 0)};for n in previous{score+=Double(notes.map{abs($0-n)}.min() ?? 0)*0.5}}
                if score<bestScore{best=notes;bestScore=score}
            }
        }
        guard let best else{throw HarmonyError.range};return best
    }
}
