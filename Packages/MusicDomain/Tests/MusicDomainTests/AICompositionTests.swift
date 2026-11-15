import Foundation
import Testing
@testable import MusicDomain

/// These tests exercise the untrusted interpretation boundary, not the quality
/// or availability of Apple's on-device model (which needs supported hardware).
struct AICompositionTests {
    private func fixture()throws->Project {
        var p=Project.demo();try p.addMelody(name:"Lead")
        p.patterns[2].notes=[NoteEvent(tick:240,duration:480,pitch:72,confidence:0.94),NoteEvent(tick:3*barTicks+240,duration:480,pitch:76)]
        p.tracks[3].gain = -11;p.tracks[3].pan=0.2
        try p.duplicateSection(p.sections[0].id,name:"Chorus")
        let pid=p.tracks[3].clips[1].patternID,index=try #require(p.patterns.firstIndex{$0.id==pid})
        p.patterns[index].notes=[NoteEvent(tick:0,duration:barTicks,pitch:81)]
        var midi=MIDISettings();midi.trackID=p.tracks[3].id;midi.mappings=[MIDIMapping(sourceID:7,channel:0,controller:20,target:.trackGain,trackID:p.tracks[3].id)];p.midi=midi
        let asset=AudioAssetRecord(sha256:String(repeating:"a",count:64),byteCount:128,sampleRate:48000,duration:0.1)
        p.audioAssets=[asset];p.tracks[3].clips[0].sourceAssetID=asset.id
        p.performanceTake=PerformanceTake(source:p,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id)])
        try p.validate();return p
    }
    private func plan()->AssistantInterpretation {
        .init(intent:.arrangeSong,changeTempo:true,bpm:108,changeKey:true,keyRoot:"D",minor:true,sections:[
            .init(name:"Intro",bars:2,chordSymbols:["Dm7","A7"],chordBars:[1,1],sourceSectionIndex:0),
            .init(name:"Verse",bars:8,chordSymbols:["Dm7","Gm7","A7","Dm7"],chordBars:[2,2,2,2],sourceSectionIndex:0),
            .init(name:"Chorus",bars:4,chordSymbols:["Fmaj9","C9","Gm9","A7(b9)"],chordBars:[1,1,1,1],sourceSectionIndex:1)
        ],explanation:"Existing rhythm and melody are reused from the selected sources.")
    }
    @Test func multiSectionInterpretationUsesImmutableSourcesAndPreservesStudioState()throws {
        let original=try fixture(),proposal=try plan().proposal(for:original,selectedSectionID:original.sections[0].id)
        let result=try proposal.candidate(for:original)
        #expect(proposal.schemaVersion==2);#expect(proposal.changesWholeSong);#expect(!proposal.warnings.isEmpty)
        #expect(result.sections.map(\.name)==["Intro","Verse","Chorus"])
        #expect(result.sections.map(\.length)==[2,8,4].map{$0*barTicks})
        #expect(result.sections.map(\.start)==[0,2,10].map{$0*barTicks})
        #expect(result.bpm==108);#expect(result.keyRoot==2);#expect(result.minor)
        #expect(result.id==original.id);#expect(result.tracks.map(\.id)==original.tracks.map(\.id))
        #expect(result.midi==original.midi);#expect(result.audioAssets==original.audioAssets);#expect(result.performanceTake==original.performanceTake)
        #expect(result.tracks[3].gain == -11);#expect(result.tracks[3].pan==0.2)
        #expect(result.tracks[3].clips.prefix(2).allSatisfy{$0.sourceAssetID==original.audioAssets?.first?.id})
        let lead=result.tracks[3],intro=Arrangement.materialize(result,track:lead,section:result.sections[0]),verse=Arrangement.materialize(result,track:lead,section:result.sections[1]),chorus=Arrangement.materialize(result,track:lead,section:result.sections[2])
        #expect(intro.notes?.map(\.pitch)==[72]);#expect(intro.notes?.first?.confidence==0.94)
        #expect(verse.notes?.map(\.pitch)==[72,76,72,76]);#expect(verse.notes?.map(\.tick)==[240,3*barTicks+240,4*barTicks+240,7*barTicks+240])
        #expect(chorus.notes?.map(\.pitch)==[81])
        #expect(Arrangement.materialize(result,track:result.tracks[1],section:result.sections[1]).drums.count==96)
        #expect(original.sections.count==2);#expect(original.bpm==120)
        try result.validate()
    }
    @Test func wholeSongIsOneAtomicUndoAndRejectsStaleDuplicateOrForeignProjects()throws {
        var p=try fixture();let original=p,proposal=try plan().proposal(for:p,selectedSectionID:p.sections[0].id);var history=History()
        try history.apply(&p){try proposal.apply(to:&$0)}
        #expect(p.revision==1);#expect(p.sections.count==3)
        #expect(throws:AssistantError.self){try proposal.candidate(for:p)}
        history.undo(&p);#expect(p.patterns==original.patterns);#expect(p.tracks==original.tracks);#expect(p.sections==original.sections);#expect(p.bpm==original.bpm)
        #expect(throws:AssistantError.self){try proposal.candidate(for:p)}
        var foreign=original;foreign.id=UUID();#expect(throws:AssistantError.self){try proposal.candidate(for:foreign)}
    }
    @Test func generatedInvalidNotesDurationsSourcesAndBoundsNeverMutateProject()throws {
        let p=try fixture(),original=p
        var cases:[AssistantInterpretation]=[]
        var invalid=plan();invalid.sections[0].chordSymbols[0]="Dm(fake)";cases.append(invalid)
        invalid=plan();invalid.sections[0].chordBars=[1];cases.append(invalid)
        invalid=plan();invalid.sections[0].sourceSectionIndex=99;cases.append(invalid)
        invalid=plan();invalid.sections[0].bars=Int.max;cases.append(invalid)
        invalid=plan();invalid.sections[0].name="Intro\nHidden command";cases.append(invalid)
        invalid=plan();invalid.sections=Array(repeating:invalid.sections[1],count:9);cases.append(invalid)
        invalid=plan();invalid.bpm = .nan;cases.append(invalid)
        invalid=plan();invalid.keyRoot="C{0,4,7}";cases.append(invalid)
        invalid=plan();invalid.targetSectionIndex = -1;cases.append(invalid)
        for value in cases{#expect(throws:(any Error).self){try value.proposal(for:p,selectedSectionID:p.sections[0].id)}}
        #expect(p==original)
        invalid=plan();invalid.sections=Array(repeating:invalid.sections[1],count:8);invalid.sections[0].bars=9;invalid.sections[0].chordBars=[3,2,2,2]
        #expect(throws:MusicError.self){try invalid.proposal(for:p,selectedSectionID:p.sections[0].id)}
    }
    @Test func singleSectionInterpretationKeepsOtherSectionsAndRequiresExactTargetSource()throws {
        let p=try fixture(),before=Compiler.notes(p,range:0..<4*barTicks)
        var value=AssistantInterpretation(intent:.editSection,targetSectionIndex:1,sections:[.init(name:"Lift",bars:4,chordSymbols:["F6/9","C7(b9,#11)"],chordBars:[2,2],sourceSectionIndex:1)])
        let proposal=try value.proposal(for:p,selectedSectionID:p.sections[0].id),result=try proposal.candidate(for:p)
        #expect(!proposal.changesWholeSong);#expect(proposal.scopeSectionID==p.sections[1].id);#expect(result.sections[1].name=="Lift")
        #expect(Compiler.notes(result,range:0..<4*barTicks)==before)
        value.sections[0].sourceSectionIndex=0
        #expect(throws:AssistantError.self){try value.proposal(for:p,selectedSectionID:p.sections[0].id)}
    }
    @Test func localSongCommandSupportsFullFormAndExplicitDistributionOnOlderDevices()throws {
        let p=try fixture()
        let en=try AssistantEngine.propose("Song: Tempo 108; Key D minor; Intro 4 bars: Dm Gm A Dm; Chorus 8 bars: Dm Gm C F each 2 bars",project:p,sectionID:p.sections[0].id)
        let ru=try AssistantEngine.propose("Песня: Темп 108; Тональность Ре минор; Интро 4 такта: Dm Gm A Dm; Припев 8 тактов: Dm Gm C F по два такта",project:p,sectionID:p.sections[0].id)
        #expect(Compiler.notes(try en.candidate(for:p))==Compiler.notes(try ru.candidate(for:p)))
        #expect(en.changesWholeSong);#expect(try en.candidate(for:p).sections.count==2)
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Song: Intro 8 bars: Dm Gm A Dm",project:p,sectionID:p.sections[0].id)}
        let repeated=try AssistantEngine.propose("Song: Intro 8 bars: Dm Gm A Dm",project:p,sectionID:p.sections[0].id,distribution:.repeatBars)
        #expect(!repeated.assumptions.isEmpty);#expect(try repeated.candidate(for:p).patterns[0].chords.count==8)
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Song: Intro 8 bars: Dm Gm A Dm each 1 bar",project:p,sectionID:p.sections[0].id)}
    }
    @Test func localJazzCommandsUseRealHarmonyLabAndPreserveRhythmAndMelody()throws {
        let p=try fixture(),scope=p.sections[0].id
        let ru=try AssistantEngine.propose("Поджазуй",project:p,sectionID:scope),en=try AssistantEngine.propose("Make it jazzy",project:p,sectionID:scope)
        let a=try ru.candidate(for:p),b=try en.candidate(for:p),expected=try HarmonyLab.propose(p,sectionID:scope,options:HarmonyOptions(style:.expressive)).candidate
        #expect(Compiler.notes(a)==Compiler.notes(b));#expect(Compiler.notes(a)==Compiler.notes(expected))
        #expect(Arrangement.harmony(a,section:a.sections[0]).map(\.chord.quality) != Arrangement.harmony(p,section:p.sections[0]).map(\.chord.quality))
        #expect(a.tracks[1]==p.tracks[1]);#expect(a.tracks[3]==p.tracks[3]);#expect(a.audioAssets==p.audioAssets)
        #expect(Compiler.notes(a,range:4*barTicks..<8*barTicks)==Compiler.notes(p,range:4*barTicks..<8*barTicks))
        let whole=try AssistantEngine.propose("Поджазовать весь трек",project:p,sectionID:scope)
        #expect(whole.changesWholeSong);#expect(try whole.candidate(for:p).patterns.filter{!$0.chords.isEmpty}.allSatisfy{$0.chords.allSatisfy{![Quality.major,.minor].contains($0.chord.quality)}})
    }
    @Test func wholeSongJazzSkipsEmptyHarmonySectionsWithoutFailingOtherSections()throws {
        var p=try fixture();try Arrangement.replaceHarmony([],in:p.sections[1],project:&p)
        let interpretation=AssistantInterpretation(intent:.styleSong,harmonyStyle:"gentle")
        let result=try interpretation.proposal(for:p,selectedSectionID:p.sections[0].id).candidate(for:p)
        #expect(Arrangement.harmony(result,section:result.sections[1]).isEmpty)
        #expect(Arrangement.harmony(result,section:result.sections[0]).first?.chord.quality == .maj7)
        let invalid=AssistantInterpretation(intent:.styleSelected,harmonyStyle:"invented")
        #expect(throws:AssistantError.self){try invalid.proposal(for:p,selectedSectionID:p.sections[0].id)}
    }
    @Test func structuredSongRejectsUnknownNestedKeysExtraParametersAndSchemaDowngrade()throws {
        let p=try fixture(),proposal=try plan().proposal(for:p,selectedSectionID:p.sections[0].id),data=try JSONEncoder().encode(proposal)
        #expect(try AssistantProposal.decode(data,for:p).operations==proposal.operations)
        var json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any]);var ops=try #require(json["operations"] as? [[String:Any]]);var parts=try #require(ops[2]["sections"] as? [[String:Any]])
        parts[0]["execute"]="unsafe";ops[2]["sections"]=parts;json["operations"]=ops
        #expect(throws:AssistantError.self){try AssistantProposal.decode(JSONSerialization.data(withJSONObject:json),for:p)}
        var invalid=proposal;invalid.schemaVersion=1;#expect(throws:AssistantError.self){try invalid.candidate(for:p)}
        invalid=proposal;invalid.operations[2].bpm=130;#expect(throws:AssistantError.self){try invalid.candidate(for:p)}
        invalid=proposal;invalid.operations[2].sections?[0].sourceSectionID=UUID();#expect(throws:AssistantError.self){try invalid.candidate(for:p)}
    }
    @Test func chordTokenizationRetainsFormulaAndAlterationCommas()throws {
        let p=Project.demo()
        let proposal=try AssistantEngine.propose("Chords C{0,4,7,10,14} C7(b9,#11) F6/9 Gm7",project:p,sectionID:p.sections[0].id)
        let chords=try proposal.candidate(for:p).patterns.first{$0.chords.count==4}!.chords.map(\.chord)
        #expect(chords[0].effectiveIntervals==[0,4,7,10,14]);#expect(chords[1].quality == .sevenFlat9Sharp11)
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Chords C{0,4,7 G F C",project:p,sectionID:p.sections[0].id)}
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Key C{0,4,7}",project:p,sectionID:p.sections[0].id)}
    }
    @Test func denseRepeatedSourcesAreRejectedBeforeCreatingAnUnboundedPattern()throws {
        var p=Project(name:"Dense",bars:1)
        p.patterns[1].drums=(0..<100).map{DrumEvent(tick:$0,pad:0)};try p.validate()
        let part=AssistantSongSection(name:"Long",bars:64,chords:[Chord(root:0)],durations:[64],sourceSectionID:p.sections[0].id)
        #expect(throws:MusicError.self){try Arrangement.composing(p,parts:[part],scope:p.sections[0].id)}
        var huge=part;huge.bars=Int.max
        #expect(throws:AssistantError.self){try Arrangement.composing(p,parts:[huge],scope:p.sections[0].id)}
        #expect(p.sections[0].length==barTicks)
    }
}
