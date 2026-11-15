import Testing
@testable import MusicDomain

struct VoiceCapturePlanTests {
    @Test func loopBeginsAtActualRangeAfterWholeCountIn()throws {
        let p=Project.demo(),section=p.sections[0],range=section.start..<section.start+barTicks
        let plan=try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:Double(range.upperBound-ppq/2),playing:true,loop:true,range:range,minimumLead:2.2)
        #expect(plan.startTick==range.lowerBound)
        #expect(plan.delay>=2.2)
        #expect(plan.captureTicks==barTicks)
        #expect(abs(plan.delay-(4.5*60/p.bpm))<0.000_001)
        #expect(abs(plan.duration-(240/p.bpm))<0.000_001)
    }
    @Test func linearCaptureUsesActualNextSectionAndRemainingBars()throws {
        var p=Project.demo();p.sections.append(Section(name:"Chorus",start:p.length,length:4*barTicks))
        let first=p.sections[0],next=p.sections[1]
        let plan=try VoiceCapturePlan.make(project:p,selectedSectionID:first.id,tick:Double(first.start+first.length-ppq),playing:true,loop:false,range:0..<p.length,minimumLead:0.2)
        #expect(plan.sectionID==next.id);#expect(plan.startTick==next.start);#expect(plan.offsetTicks==0)
        let middle=try VoiceCapturePlan.make(project:p,selectedSectionID:first.id,tick:Double(next.start+100),playing:true,loop:false,range:0..<p.length,minimumLead:0.2)
        #expect(middle.sectionID==next.id);#expect(middle.offsetTicks==barTicks)
        #expect(middle.captureTicks<=next.length-barTicks)
        let note=NoteEvent(tick:0,duration:ppq,pitch:60,velocity:100)
        let placed=try middle.place([note],sectionLength:next.length)
        #expect(placed[0].tick==barTicks);#expect(placed[0].id==note.id)
    }
    @Test func captureNeverCrossesLoopOrSectionAndNeverSilentlyDropsNotes()throws {
        let p=Project.demo(),section=p.sections[0]
        let short=try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:1,playing:true,loop:true,range:0..<barTicks,minimumLead:0.2)
        #expect(short.captureTicks==barTicks)
        let long=try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:1,playing:true,loop:true,range:0..<p.length,minimumLead:0.2)
        #expect(long.captureTicks<=section.length)
        let outside=NoteEvent(tick:short.captureTicks,duration:1,pitch:60,velocity:100)
        #expect(throws:MusicError.self){try short.place([outside],sectionLength:section.length)}
        #expect(throws:VoiceCapturePlanError.self){try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:Double(p.length-100),playing:true,loop:false,range:0..<p.length,minimumLead:0.2)}
    }
    @Test func subrangePreservesPhaseAndEveryCapturedNote()throws {
        let p=Project.demo(),section=p.sections[0]
        let plan=try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:Double(barTicks+ppq),playing:true,loop:true,range:barTicks..<3*barTicks,minimumLead:0.2)
        #expect(plan.offsetTicks==barTicks);#expect(plan.captureTicks==2*barTicks)
        let first=NoteEvent(tick:0,duration:ppq,pitch:60,velocity:100)
        let last=NoteEvent(tick:plan.captureTicks-120,duration:120,pitch:64,velocity:100)
        let placed=try plan.place([first,last],sectionLength:section.length)
        #expect(placed.count==2);#expect(placed[0].tick==barTicks)
        #expect(placed[1].tick+placed[1].duration==3*barTicks)
        #expect(placed.map(\.id)==[first.id,last.id])
        let invalid=NoteEvent(tick:Int.max,duration:Int.max,pitch:60,velocity:100)
        #expect(throws:MusicError.self){try plan.place([invalid],sectionLength:section.length)}
    }
    @Test func idleTakeAndThirtySecondCeilingAreExplicit()throws {
        var p=Project.demo();p.bpm=40
        let section=p.sections[0]
        let plan=try VoiceCapturePlan.make(project:p,selectedSectionID:section.id,tick:Double(p.length),playing:false,loop:true,range:0..<barTicks,minimumLead:6.2)
        #expect(plan.startTick==section.start);#expect(plan.delay==6.2);#expect(plan.duration<=30)
        #expect(plan.captureTicks==min(section.length,Int(30*p.bpm/60*Double(ppq))))
    }
}
