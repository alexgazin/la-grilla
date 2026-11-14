import Foundation
import Testing
@testable import MusicDomain

struct AssistantTests {
    @Test func russianAndEnglishCommandsProduceTheSameMusic() throws {
        let p=Project.demo(),scope=p.sections[0].id
        let en=try AssistantEngine.propose("Tempo 110; Key D minor; Chorus 8 bars: Am F C G each 2 bars",project:p,sectionID:scope)
        let ru=try AssistantEngine.propose("Темп 110; Тональность Ре минор; Припев 8 тактов: Am F C G по два такта",project:p,sectionID:scope)
        let a=try en.candidate(for:p),b=try ru.candidate(for:p)
        #expect(a.bpm==110);#expect(a.keyRoot==2);#expect(a.minor);#expect(a.sections[0].name=="Chorus");#expect(a.length==8*barTicks)
        #expect(Compiler.notes(a)==Compiler.notes(b));#expect(a.sections.map(\.length)==b.sections.map(\.length))
        #expect(Arrangement.harmony(a,section:a.sections[0]).map(\.duration)==Array(repeating:2*barTicks,count:4))
        #expect(!en.assumptions.isEmpty)
        #expect(p.bpm==120);#expect(p.length==4*barTicks)
    }
    @Test func ambiguousDurationsRequireAVisibleChoice() throws {
        let p=Project.demo(),scope=p.sections[0].id
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Chorus 8 bars: Am F C G",project:p,sectionID:scope)}
        let stretched=try AssistantEngine.propose("Chorus 8 bars: Am F C G",project:p,sectionID:scope,distribution:.stretch).candidate(for:p)
        let repeated=try AssistantEngine.propose("Chorus 8 bars: Am F C G",project:p,sectionID:scope,distribution:.repeatBars).candidate(for:p)
        #expect(Arrangement.harmony(stretched,section:stretched.sections[0]).count==4)
        #expect(Arrangement.harmony(repeated,section:repeated.sections[0]).count==8)
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Chorus 8 bars: Am F C G each 1 bar",project:p,sectionID:scope)}
        #expect(throws:AssistantError.self){try AssistantEngine.propose("Chorus 7 bars: Am F C G",project:p,sectionID:scope,distribution:.stretch)}
    }
    @Test func proposalApplyIsOneUndoAndRejectsStaleOrDuplicateRequests() throws {
        var p=Project.demo();let original=p;var history=History()
        let proposal=try AssistantEngine.propose("Tempo 94; rename section Sunset; chords Dm G C Am",project:p,sectionID:p.sections[0].id)
        try history.apply(&p){try proposal.apply(to:&$0)}
        #expect(p.bpm==94);#expect(p.sections[0].name=="Sunset");#expect(p.revision==1)
        #expect(throws:AssistantError.self){try proposal.apply(to:&p)}
        history.undo(&p);#expect(p.patterns==original.patterns);#expect(p.tracks==original.tracks);#expect(p.bpm==120)
        #expect(throws:AssistantError.self){try proposal.candidate(for:p)}
        var foreign=original;foreign.id=UUID();#expect(throws:AssistantError.self){try proposal.candidate(for:foreign)}
    }
    @Test func structuredOperationsRejectUnknownFieldsAndInventedIDs() throws {
        let p=Project.demo();let proposal=try AssistantEngine.propose("Tempo 110",project:p,sectionID:p.sections[0].id)
        let data=try JSONEncoder().encode(proposal)
        #expect(try AssistantProposal.decode(data,for:p).candidate(for:p).bpm==110)
        var json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any]);json["executeShell"]="anything"
        #expect(throws:AssistantError.self){try AssistantProposal.decode(JSONSerialization.data(withJSONObject:json),for:p)}
        var unsafe=proposal;unsafe.operations=[.init(.resizeSection,sectionID:UUID(),bars:8)]
        #expect(throws:AssistantError.self){try unsafe.candidate(for:p)}
        unsafe=proposal;unsafe.operations=[.init(.setTempo,bpm:100,root:2)]
        #expect(throws:AssistantError.self){try unsafe.candidate(for:p)}
        unsafe=proposal;unsafe.operations=[.init(.setTempo,bpm:500),.init(.setTempo,bpm:100)]
        #expect(throws:MusicError.self){try unsafe.candidate(for:p)}
    }
    @Test func resizingSectionsPreservesSurroundingsAndTrimsNotes() throws {
        var p=Project.demo();try p.addMelody();p.patterns[2].notes=[NoteEvent(tick:barTicks-240,duration:480,pitch:72)]
        try p.duplicateSection(p.sections[0].id,name:"Chorus");let chorus=p.sections[1]
        let before=Compiler.notes(p,range:chorus.start..<chorus.start+chorus.length)
        let shorter=try Arrangement.resized(p,sectionID:p.sections[0].id,bars:1)
        #expect(shorter.sections[1].start==barTicks)
        #expect(Compiler.notes(shorter,range:barTicks..<barTicks+chorus.length)==before)
        #expect(Compiler.notes(shorter).filter{$0.track==3 && $0.tick<barTicks}.map(\.duration)==[240])
        let longer=try Arrangement.resized(p,sectionID:p.sections[0].id,bars:8)
        #expect(Compiler.notes(longer,range:barTicks*4..<barTicks*8).isEmpty)
        #expect(Compiler.notes(longer,range:barTicks*8..<barTicks*12)==before)
    }
    @Test func commandsAreBoundedAndKeepTheOriginalOnFailure() throws {
        let p=Project.demo(),scope=p.sections[0].id
        for command in ["Delete everything", "Tempo 999", "Key C13", "Chorus 65 bars", "Tempo 110; rm -rf",String(repeating:"a",count:2001)]{
            #expect(throws:(any Error).self){try AssistantEngine.propose(command,project:p,sectionID:scope)}
        }
        let proposal=try AssistantEngine.propose("Припев 8 тактов; ам фа до соль",project:p,sectionID:scope,distribution:.stretch)
        #expect(try proposal.candidate(for:p).length==8*barTicks)
    }
    @Test func matchingSectionScopeDoesNotOverwriteOtherSections() throws {
        var p=Project.demo();try p.duplicateSection(p.sections[0].id,name:"Chorus")
        let first=Compiler.notes(p,range:0..<barTicks*4)
        let proposal=try AssistantEngine.propose("In chorus Dm G C Am each 1 bar",project:p,sectionID:p.sections[0].id)
        let result=try proposal.candidate(for:p)
        #expect(Compiler.notes(result,range:0..<barTicks*4)==first)
        #expect(proposal.scopeSectionID==p.sections[1].id)
    }
}
