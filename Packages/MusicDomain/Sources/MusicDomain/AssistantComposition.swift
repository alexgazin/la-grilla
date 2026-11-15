import Foundation

/// A bounded, reviewable section description. Source IDs refer only to the
/// request's existing project; the model never supplies new persistent IDs.
public struct AssistantSongSection:Codable,Equatable,Sendable {
    public var name:String
    public var bars:Int
    public var chords:[Chord]
    public var durations:[Int]
    public var sourceSectionID:UUID
    public init(name:String,bars:Int,chords:[Chord],durations:[Int],sourceSectionID:UUID){self.name=name;self.bars=bars;self.chords=chords;self.durations=durations;self.sourceSectionID=sourceSectionID}
    func validate(in project:Project)throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=120,!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),(1...64).contains(bars),project.sections.contains(where:{$0.id==sourceSectionID}),(1...64).contains(chords.count),chords.count==durations.count,durations.allSatisfy({(1...64).contains($0)}),durations.reduce(0,+)==bars else{throw AssistantError.unsafe}
    }
}

/// Portable semantic boundary between a real language model and musical edits.
/// Generated values still pass ordinary project validation before any mutation.
public struct AssistantInterpretation:Codable,Equatable,Sendable {
    public enum Intent:String,Codable,Sendable {case editSection,arrangeSong,styleSelected,styleSong,unsupported}
    public struct Part:Codable,Equatable,Sendable {
        public var name:String;public var bars:Int;public var chordSymbols:[String];public var chordBars:[Int];public var sourceSectionIndex:Int
        public init(name:String,bars:Int,chordSymbols:[String],chordBars:[Int],sourceSectionIndex:Int){self.name=name;self.bars=bars;self.chordSymbols=chordSymbols;self.chordBars=chordBars;self.sourceSectionIndex=sourceSectionIndex}
    }
    public var intent:Intent
    public var changeTempo:Bool;public var bpm:Double
    public var changeKey:Bool;public var keyRoot:String;public var minor:Bool
    public var targetSectionIndex:Int;public var harmonyStyle:String
    public var sections:[Part];public var explanation:String
    public init(intent:Intent,changeTempo:Bool=false,bpm:Double=120,changeKey:Bool=false,keyRoot:String="C",minor:Bool=false,targetSectionIndex:Int=0,harmonyStyle:String="expressive",sections:[Part]=[],explanation:String=""){
        self.intent=intent;self.changeTempo=changeTempo;self.bpm=bpm;self.changeKey=changeKey;self.keyRoot=keyRoot;self.minor=minor;self.targetSectionIndex=targetSectionIndex;self.harmonyStyle=harmonyStyle;self.sections=sections;self.explanation=explanation
    }
    public func proposal(for project:Project,selectedSectionID:UUID)throws->AssistantProposal {
        try project.validate()
        guard project.sections.contains(where:{$0.id==selectedSectionID}),project.sections.indices.contains(targetSectionIndex),explanation.count<=500,sections.count<=8 else{throw AssistantError.unsafe}
        guard intent != .unsupported else{throw AssistantError.unsupported}
        let scope=intent == .editSection || intent == .styleSelected ? project.sections[targetSectionIndex].id:selectedSectionID
        var operations:[AssistantOperation]=[]
        if intent == .editSection || intent == .arrangeSong {
            if changeTempo{guard bpm.isFinite,(40...240).contains(bpm)else{throw AssistantError.unsafe};operations.append(.init(.setTempo,bpm:bpm))}
            if changeKey{let root=try Chord.parse(keyRoot);guard root.quality == .major,root.slashBass==nil,root.customIntervals==nil else{throw AssistantError.unsafe};operations.append(.init(.setKey,root:root.root,minor:minor))}
        }
        var assumptions:[String]=[];var warnings:[String]=[]
        if !explanation.isEmpty{assumptions.append(explanation)}
        switch intent {
        case .editSection:
            guard sections.count==1,sections[0].sourceSectionIndex==targetSectionIndex else{throw AssistantError.unsafe}
            let part=try musicalPart(sections[0],project:project)
            operations.append(.init(.renameSection,sectionID:scope,name:part.name))
            operations.append(.init(.resizeSection,sectionID:scope,bars:part.bars))
            operations.append(.init(.setProgression,sectionID:scope,chords:part.chords,durations:part.durations))
            warnings.append(NSLocalizedString("Section length changes can trim notes or add empty space.",comment:"Assistant review"))
        case .arrangeSong:
            guard !sections.isEmpty else{throw AssistantError.unsafe}
            let parts=try sections.map{try musicalPart($0,project:project)}
            guard parts.reduce(0,{$0+$1.bars})<=64 else{throw MusicError.limit}
            operations.append(.init(.arrangeSong,sections:parts))
            warnings.append(NSLocalizedString("This proposal replaces the song form. Existing rhythm and melody repeat or trim from the displayed source sections. Original recordings and the previous version remain available through Undo.",comment:"Assistant review"))
        case .styleSelected:
            guard HarmonyStyle(rawValue:harmonyStyle) != nil else{throw AssistantError.unsafe}
            operations.append(.init(.styleHarmony,sectionID:scope,style:harmonyStyle))
        case .styleSong:
            guard HarmonyStyle(rawValue:harmonyStyle) != nil else{throw AssistantError.unsafe}
            operations.append(.init(.styleSong,style:harmonyStyle))
            warnings.append(NSLocalizedString("Harmony in every section will change. Rhythm and melody stay as written.",comment:"Assistant review"))
        case .unsupported:throw AssistantError.unsupported
        }
        let proposal=AssistantProposal(project:project,scope:scope,operations:operations,assumptions:assumptions,warnings:warnings)
        _ = try proposal.candidate(for:project)
        return proposal
    }
    private func musicalPart(_ part:Part,project:Project)throws->AssistantSongSection {
        guard project.sections.indices.contains(part.sourceSectionIndex),part.chordSymbols.count<=64,part.chordSymbols.allSatisfy({$0.count<=64})else{throw AssistantError.unsafe}
        let value=AssistantSongSection(name:part.name,bars:part.bars,chords:try part.chordSymbols.map{try Chord.parse($0)},durations:part.chordBars,sourceSectionID:project.sections[part.sourceSectionIndex].id)
        try value.validate(in:project);return value
    }
}

extension Arrangement {
    /// Rebuild form from immutable original material; never sequentially copy a
    /// section that was already edited by a previous generated part.
    public static func composing(_ project:Project,parts:[AssistantSongSection],scope:UUID)throws->Project {
        try project.validate()
        guard (1...8).contains(parts.count),project.sections.contains(where:{$0.id==scope})else{throw AssistantError.unsafe}
        for part in parts{try part.validate(in:project)}
        guard parts.reduce(0,{$0+$1.bars})<=64 else{throw MusicError.limit}
        var result=project;result.sections=[];result.patterns=[]
        for i in result.tracks.indices{result.tracks[i].clips=[]}
        var start=0
        for (index,part) in parts.enumerated(){
            let length=part.bars*barTicks,original=project.sections.first{$0.id==part.sourceSectionID}!
            var section=Section(name:part.name,start:start,length:length)
            if index==0{section.id=scope}
            result.sections.append(section)
            for trackIndex in project.tracks.indices where project.tracks[trackIndex].role != .bass {
                let track=project.tracks[trackIndex]
                var pattern=Pattern(length:length)
                if track.role == .harmony {
                    var tick=0
                    for (chord,bars) in zip(part.chords,part.durations){pattern.chords.append(ChordEvent(tick:tick,duration:bars*barTicks,chord:chord));tick+=bars*barTicks}
                }else{
                    let material=materialize(project,track:track,section:original)
                    let repeats=(length+original.length-1)/original.length
                    guard material.drums.count*repeats<=4096,(material.notes ?? []).count*repeats<=4096,material.chords.count*repeats<=256 else{throw MusicError.tooDense}
                    for offset in stride(from:0,to:length,by:original.length){
                        for event in material.drums where offset+event.tick<length{pattern.drums.append(DrumEvent(tick:offset+event.tick,pad:event.pad,velocity:event.velocity))}
                        for event in material.notes ?? [] where offset+event.tick<length{pattern.notes?.append(NoteEvent(tick:offset+event.tick,duration:min(event.duration,length-offset-event.tick),pitch:event.pitch,velocity:event.velocity,confidence:event.confidence))}
                        for event in material.chords where offset+event.tick<length{pattern.chords.append(ChordEvent(tick:offset+event.tick,duration:min(event.duration,length-offset-event.tick),chord:event.chord))}
                    }
                }
                result.patterns.append(pattern)
                var clip=Clip(patternID:pattern.id,start:start,length:length)
                let end=original.start+original.length
                let assets=Set(track.clips.filter{$0.start<end && $0.start+$0.length>original.start}.compactMap(\.sourceAssetID))
                if assets.count==1{clip.sourceAssetID=assets.first}
                result.tracks[trackIndex].clips.append(clip)
            }
            start+=length
        }
        try result.validate();return result
    }
}
