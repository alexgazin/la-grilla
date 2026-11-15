import Foundation
import Testing
@testable import MusicDomain

struct HarmonyTests {
    @Test func extendedAndSlashVocabularyRoundTrips() throws {
        for root in 0..<12{for q in Quality.allCases{for bass in [nil,0,4,11] as [Int?]{let c=Chord(root:root,quality:q,slashBass:bass);#expect(try Chord.parse(c.symbol)==c);#expect(c.notes.count==q.intervals.count+(bass==nil ? 0:1));if let bass{#expect(c.notes.min()!%12==bass)}}}}
        #expect(try Chord.parse("dbmaj9/ab")==Chord(root:1,quality:.maj9,slashBass:8))
        for invalid in ["C/","C/E/G","C/Em","C14","C7b9#11garbage"]{#expect(throws:MusicError.self){try Chord.parse(invalid)}}
        #expect(Chord(root:0,quality:.thirteenth).notes==[60,64,67,70,74,77,81])
    }
    @Test func slashBassCompilesToBothHarmonyAndBass() throws {
        var p=Project.demo();p.patterns[0].chords[0].chord=try Chord.parse("Cmaj9/E");try p.validate()
        let notes=Compiler.notes(p).filter{$0.tick==0 && $0.pad<0}
        #expect(notes.filter{$0.track==2}.map(\.pitch)==[28])
        #expect(notes.filter{$0.track==0}.map(\.pitch).contains(52))
    }
    @Test func proposalsLeaveOriginalUntouchedAndApplyOnce() throws {
        var p=Project.demo();let original=p;var history=History()
        let proposal=try HarmonyLab.propose(p,sectionID:p.sections[0].id)
        #expect(p==original);#expect(proposal.changes.count==4)
        #expect(proposal.changes[0].after.quality == .maj7)
        #expect(proposal.changes[1].after.quality == .m7)
        #expect(proposal.changes[3].after.quality == .seventh)
        try history.apply(&p){try proposal.apply(to:&$0)}
        #expect(p.patterns != original.patterns);#expect(p.revision==1)
        #expect(throws:HarmonyError.self){try proposal.apply(to:&p)}
        history.undo(&p);#expect(p.patterns==original.patterns);#expect(p.tracks==original.tracks)
        var other=original;other.id=UUID();#expect(throws:HarmonyError.self){try proposal.apply(to:&other)}
    }
    @Test func voicingsRespectRegisterAndKeepEveryChordTone() throws {
        var p=Project.demo();p.patterns[0].chords[0].chord=try Chord.parse("C13/E")
        for style in HarmonyStyle.allCases {
            let proposal=try HarmonyLab.propose(p,sectionID:p.sections[0].id,options:HarmonyOptions(style:style,low:36,high:96))
            try proposal.candidate.validate()
            for change in proposal.changes{#expect(change.after.notes.allSatisfy{(36...96).contains($0)});let actual=Set(change.after.notes.map{$0%12});let expected=Set(change.after.quality.intervals.map{($0+change.after.root)%12});#expect(expected.isSubset(of:actual))}
        }
        #expect(throws:HarmonyError.self){try HarmonyLab.propose(p,sectionID:p.sections[0].id,options:HarmonyOptions(low:84,high:72))}
        let empty=Project();#expect(throws:HarmonyError.self){try HarmonyLab.propose(empty,sectionID:empty.sections[0].id)}
    }
    @Test func scopedReplacementSplitsCrossingClipsWithoutChangingOtherSections() throws {
        var p=Project.demo();p.sections=[Section(name:"A",length:barTicks),Section(name:"B",start:barTicks,length:barTicks*2),Section(name:"C",start:barTicks*3,length:barTicks)]
        try p.validate();let beforeFirst=Compiler.notes(p,range:0..<barTicks);let beforeLast=Compiler.notes(p,range:barTicks*3..<barTicks*4)
        let proposal=try HarmonyLab.propose(p,sectionID:p.sections[1].id,options:HarmonyOptions(style:.expressive))
        let candidate=proposal.candidate
        #expect(Compiler.notes(candidate,range:0..<barTicks)==beforeFirst)
        #expect(Compiler.notes(candidate,range:barTicks*3..<barTicks*4)==beforeLast)
        #expect(candidate.tracks[0].clips.count==3)
        #expect(candidate.tracks[0].clips[2].offset==barTicks*3)
        #expect(candidate.patterns[1].drums==p.patterns[1].drums)
    }
    @Test func reharmonizationMarksBorrowedAndTritoneChanges() throws {
        var p=Project.demo();p.patterns[0].chords[2].chord=Chord(root:7,quality:.seventh);p.patterns[0].chords[3].chord=Chord(root:0)
        let proposal=try HarmonyLab.propose(p,sectionID:p.sections[0].id,options:HarmonyOptions(style:.reharmonize))
        #expect(proposal.changes[2].after.root==1);#expect(proposal.changes[2].after.quality == .flat9);#expect(proposal.changes[2].chromatic)
        p=Project.demo();let borrowed=try HarmonyLab.propose(p,sectionID:p.sections[0].id,options:HarmonyOptions(style:.reharmonize))
        #expect(borrowed.changes[2].after.quality == .m7);#expect(borrowed.changes[2].chromatic)
    }
    @Test func customVoicingsAndOldSchemasRoundTrip() throws {
        var p=Project.demo();let proposal=try HarmonyLab.propose(p,sectionID:p.sections[0].id);p=proposal.candidate
        #expect(try PortableProject.decode(PortableProject.data(p),asCopy:false)==p)
        p.schemaVersion=2;for i in p.patterns.indices{for j in p.patterns[i].chords.indices{p.patterns[i].chords[j].chord.voicedNotes=nil}}
        let data=try JSONEncoder().encode(p);let migrated=try ProjectDocument.decode(data);#expect(migrated.schemaVersion==Project.currentSchemaVersion)
        var invalid=migrated;let index=invalid.patterns.firstIndex{!$0.chords.isEmpty}!;invalid.patterns[index].chords[0].chord.voicedNotes=[60,61,67];#expect(throws:MusicError.self){try invalid.validate()}
    }
}
