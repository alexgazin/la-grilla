import Foundation
import Testing
@testable import MusicDomain

struct DrumRecordingTests {
    private func sharedLoop()throws->Project {
        var p=Project(name:"Shared loop",bars:4)
        p.patterns[1].length=barTicks;p.patterns[1].drums=[DrumEvent(tick:0,pad:0),DrumEvent(tick:960,pad:1),DrumEvent(tick:2880,pad:2)]
        p.tracks[1].clips=[Clip(patternID:p.patterns[1].id,start:0,length:2*barTicks),Clip(patternID:p.patterns[1].id,start:2*barTicks,length:2*barTicks)]
        p.tracks[1].clips[1].offset=960;try p.validate();return p
    }
    @Test func offsetRepeatsMaterializeOneIndependentClipWithExactHeardNotes()throws {
        let p=try sharedLoop(),clip=p.tracks[1].clips[1],before=Compiler.notes(p)
        let draft=try DrumRecordingDraft(project:p,clipID:clip.id)
        #expect(Compiler.notes(draft.project)==before)
        #expect(draft.project.tracks[1].clips[0]==p.tracks[1].clips[0])
        #expect(draft.project.patterns.first{$0.id==p.patterns[1].id}==p.patterns[1])
        #expect(draft.project.tracks[1].clips[1].offset==0)
        #expect(draft.patternID != p.patterns[1].id);#expect(!draft.changed)
        #expect(draft.project.patterns.first{$0.id==draft.patternID}?.drums.map(\.tick)==[0,1920,2880,3840,5760,6720])
    }
    @Test func outsideTouchesNeverWrapIntoFocusedClipAndFractionalEdgesRemainBounded()throws {
        var p=try sharedLoop();p.tracks[1].clips[1].start+=240;p.tracks[1].clips[1].length-=480
        let draft=try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[1].id)
        #expect(draft.localTick(draft.start-1)==nil);#expect(draft.localTick(draft.start)==0)
        #expect(draft.localTick(draft.start+draft.length-1)==draft.length-1);#expect(draft.localTick(draft.start+draft.length)==nil)
        #expect(draft.localTick(Int.max)==nil);#expect(draft.localTick(Int.min)==nil)
        #expect(draft.project.patterns.first{$0.id==draft.patternID}?.length==2*barTicks)
        try draft.project.validate()
    }
    @Test func multiplePassesAndMaterializationApplyAsOneUndoWhilePreservingMixerChanges()throws {
        var p=try sharedLoop();let original=p;var draft=try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[1].id),history=History()
        try draft.commitPass([DrumEvent(tick:240,pad:3)],replacing:draft.start..<draft.start+barTicks)
        try draft.commitPass([DrumEvent(tick:barTicks+240,pad:4)])
        #expect(p==original)
        try history.apply(&p){$0.tracks[1].gain = -15}
        let mixed=p
        try history.apply(&p){$0=try draft.candidate(for:$0)}
        #expect(p.tracks[1].gain == -15);#expect(p.tracks[1].clips[0]==original.tracks[1].clips[0])
        #expect(Compiler.notes(p,range:0..<2*barTicks)==Compiler.notes(original,range:0..<2*barTicks))
        #expect(p.patterns.first{$0.id==draft.patternID}?.drums.contains{$0.pad==4} == true)
        history.undo(&p);#expect(p.patterns==mixed.patterns);#expect(p.tracks==mixed.tracks)
        history.undo(&p);#expect(p.patterns==original.patterns);#expect(p.tracks==original.tracks)
    }
    @Test func replacingRangeDoesNotEraseOtherPassesAndRejectsBadEventsAtomically()throws {
        let p=try sharedLoop();var draft=try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[1].id)
        let latter=Compiler.notes(draft.project,range:3*barTicks..<4*barTicks)
        try draft.commitPass([],replacing:draft.start..<draft.start+barTicks)
        #expect(draft.changed);#expect(Compiler.notes(draft.project,range:3*barTicks..<4*barTicks)==latter)
        let before=draft.project
        #expect(throws:MusicError.self){try draft.commitPass([DrumEvent(tick:draft.length,pad:0)])}
        #expect(throws:MusicError.self){try draft.commitPass([DrumEvent(tick:0,pad:99)])}
        #expect(draft.project==before)
    }
    @Test func staleOrForeignClipCannotReceiveRecordedNotes()throws {
        let p=try sharedLoop(),draft=try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[1].id)
        var foreign=p;foreign.id=UUID();#expect(throws:AssistantError.self){try draft.candidate(for:foreign)}
        var removed=p;removed.tracks[1].clips.removeLast();#expect(throws:AssistantError.self){try draft.candidate(for:removed)}
        var changed=p;changed.tracks[1].clips[1].patternID=p.patterns[0].id;#expect(throws:AssistantError.self){try draft.candidate(for:changed)}
    }
}

struct SingleAttackRecordingTests {
    private func loop()throws->(Project,DrumRecordingDraft) {
        var p=Project(name:"Overdub",bars:1)
        p.patterns[1].drums=[DrumEvent(tick:0,pad:0,velocity:90),DrumEvent(tick:960,pad:1,velocity:100)]
        try p.validate()
        return (p,try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[0].id))
    }
    @Test func overdubOnASoundingStepKeepsOneAttackAndTheLouderVelocity()throws {
        var (_,draft)=try loop()
        let existing=draft.project.patterns.first{$0.id==draft.patternID}!.drums
        try draft.commitPass([DrumEvent(tick:0,pad:0,velocity:120),DrumEvent(tick:0,pad:2,velocity:70)])
        let drums=draft.project.patterns.first{$0.id==draft.patternID}!.drums
        #expect(drums.filter{$0.tick==0 && $0.pad==0}.count==1)
        #expect(drums.first{$0.tick==0 && $0.pad==0}?.id==existing.first{$0.tick==0 && $0.pad==0}?.id)
        #expect(drums.first{$0.tick==0 && $0.pad==0}?.velocity==120)
        #expect(drums.contains{$0.tick==0 && $0.pad==2})
        #expect(drums.count==3)
    }
    @Test func twoTouchesQuantizedToOneStepGiveOneEventAndQuieterRepeatNeverLowersVelocity()throws {
        var (_,draft)=try loop()
        let a=Quantize.sixteenth.tick(1890,length:barTicks),b=Quantize.sixteenth.tick(1950,length:barTicks)
        #expect(a==b)
        try draft.commitPass([DrumEvent(tick:a,pad:3,velocity:80),DrumEvent(tick:b,pad:3,velocity:110)])
        try draft.commitPass([DrumEvent(tick:a,pad:3,velocity:40)])
        let hits=draft.project.patterns.first{$0.id==draft.patternID}!.drums.filter{$0.pad==3}
        #expect(hits.count==1);#expect(hits.first?.velocity==110)
        #expect(Compiler.notes(draft.project).filter{$0.pad==3}.count==1)
    }
    @Test func loopBoundaryWrapIsOneEventAtTheDownbeat()throws {
        var (_,draft)=try loop()
        // A hit 20 ticks before the loop end quantizes forward to the downbeat.
        let wrapped=Quantize.sixteenth.tick(barTicks-20,length:barTicks)
        #expect(wrapped==0)
        try draft.commitPass([DrumEvent(tick:wrapped,pad:0,velocity:100)])
        #expect(draft.project.patterns.first{$0.id==draft.patternID}!.drums.filter{$0.pad==0}.count==1)
    }
}

struct DrumPassUndoTests {
    private func drums(_ draft:DrumRecordingDraft)->[DrumEvent] {draft.project.patterns.first{$0.id==draft.patternID}?.drums ?? []}
    @Test func undoLastPassRestoresEachPassInOrder()throws {
        var p=Project(name:"Undo passes",bars:2)
        p.patterns[1].drums=[DrumEvent(tick:0,pad:0),DrumEvent(tick:960,pad:1)]
        try p.validate()
        var draft=try DrumRecordingDraft(project:p,clipID:p.tracks[1].clips[0].id)
        let original=drums(draft)
        #expect(!draft.canUndoPass)
        let nothing=draft.undoLastPass()
        #expect(!nothing)
        try draft.commitPass([DrumEvent(tick:240,pad:3)])
        try draft.commitPass([])
        let afterFirst=drums(draft)
        let second=[DrumEvent(tick:480,pad:4),DrumEvent(tick:720,pad:5)]
        try draft.commitPass(second,replacing:draft.start..<(draft.start+barTicks))
        #expect(draft.canUndoPass)
        let first=draft.undoLastPass()
        #expect(first && drums(draft)==afterFirst)
        let secondUndo=draft.undoLastPass()
        #expect(secondUndo && drums(draft)==original)
        let empty=draft.undoLastPass()
        #expect(!empty)
        try draft.project.validate()
        let candidate=try draft.candidate(for:p)
        #expect(Compiler.notes(candidate)==Compiler.notes(p))
    }
}
