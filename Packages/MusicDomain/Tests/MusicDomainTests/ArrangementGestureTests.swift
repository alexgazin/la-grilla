import Foundation
import Testing
@testable import MusicDomain

struct ArrangementGestureTests {
    private func melodySong() throws -> Project {
        var project=Project(name:"Arrangement",bars:4)
        try project.addMelody(name:"Lead");try project.addMelody(name:"Answer")
        let id=project.tracks[2].clips[0].patternID
        project.patterns[project.patterns.firstIndex(where:{$0.id==id})!].notes=[NoteEvent(tick:240,duration:960,pitch:73,velocity:87)]
        return project
    }
    @Test func dragMovesRealNotesAcrossMelodyTracksAndClearsOnlyEmptyPlaceholders() throws {
        var project=try melodySong();let clip=project.tracks[2].clips[0]
        let token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:clip.id)
        try ClipEditing.move(token,to:project.tracks[3].id,start:0,in:&project)
        try project.validate()
        #expect(project.tracks[2].clips.isEmpty)
        #expect(project.tracks[3].clips.count==1)
        #expect(project.tracks[3].clips[0].id==clip.id)
        #expect(project.tracks[3].clips[0].patternID==clip.patternID)
        let rendered=Compiler.notes(project)
        #expect(rendered.filter{$0.track==2}.isEmpty)
        #expect(rendered.filter{$0.track==3}.map(\.pitch)==[73])
        #expect(rendered.filter{$0.track==3}.map(\.tick)==[240])
    }
    @Test func copyIsIndependentAndExtendsTheSongWithoutInventingOtherClips() throws {
        var project=try melodySong();let clip=project.tracks[2].clips[0]
        let token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:clip.id)
        try ClipEditing.copy(token,to:project.tracks[2].id,start:4*barTicks,in:&project)
        #expect(project.length==8*barTicks)
        #expect(project.tracks[0].clips[0].length==4*barTicks)
        let copied=project.tracks[2].clips[1]
        #expect(copied.id != clip.id);#expect(copied.patternID != clip.patternID)
        let original=project.patterns.first{$0.id==clip.patternID}!,copy=project.patterns.first{$0.id==copied.patternID}!
        #expect(original.notes![0].id != copy.notes![0].id)
        #expect(original.notes![0].pitch==copy.notes![0].pitch)
        project.patterns[project.patterns.firstIndex{$0.id==copied.patternID}!].notes![0].pitch=78
        #expect(project.patterns.first{$0.id==clip.patternID}!.notes![0].pitch==73)
        #expect(Compiler.notes(project).filter{$0.track==2}.map(\.tick)==[240,4*barTicks+240])
    }
    @Test func rejectedDropsAreAtomicAndDoNotOverwriteMutedContent() throws {
        var project=try melodySong();let source=project.tracks[2].clips[0],target=project.tracks[3].clips[0]
        project.patterns[project.patterns.firstIndex{$0.id==target.patternID}!].notes=[NoteEvent(tick:0,pitch:80)]
        project.tracks[3].mute=true
        let before=project,token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:source.id)
        #expect(throws:ClipEditingError.overlap){try ClipEditing.move(token,to:project.tracks[3].id,start:0,in:&project)}
        #expect(project==before)
        #expect(throws:ClipEditingError.incompatible){try ClipEditing.move(token,to:project.tracks[1].id,start:0,in:&project)}
        #expect(project==before)
        #expect(throws:ClipEditingError.bounds){try ClipEditing.move(token,to:project.tracks[2].id,start:4*barTicks,extendingSong:false,in:&project)}
        #expect(project==before)
        #expect(throws:ClipEditingError.bounds){try ClipEditing.move(token,to:project.tracks[2].id,start:Int.max,in:&project)}
        #expect(project==before)
    }
    @Test func resizeAndOffsetPreserveLoopPhaseAndSnapToMusicalTicks() throws {
        var project=try melodySong();let clip=project.tracks[2].clips[0]
        var token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:clip.id)
        try ClipEditing.resize(token,length:barTicks,snap:barTicks,in:&project)
        token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:clip.id)
        try ClipEditing.setOffset(token,offset:500,snap:240,in:&project)
        #expect(project.tracks[2].clips[0].length==barTicks)
        #expect(project.tracks[2].clips[0].offset==480)
        let notes=Compiler.notes(project).filter{$0.track==2}
        #expect(notes.count==1);#expect(notes[0].tick==0);#expect(notes[0].duration==720)
        try ClipEditing.move(token,to:project.tracks[2].id,start:1900,snap:ppq,in:&project)
        #expect(project.tracks[2].clips[0].start==1920)
        #expect(project.tracks[2].clips[0].offset==480)
        #expect(Compiler.notes(project).filter{$0.track==2}[0].tick==1920)
    }
    @Test func staleForeignAndMalformedDragPayloadsCannotChangeMusic() throws {
        var project=try melodySong();let before=project,clip=project.tracks[2].clips[0]
        let token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:clip.id)
        #expect(try ArrangementDragPayload.decode(token.encoded())==token)
        #expect(throws:ClipEditingError.invalidDrag){try ArrangementDragPayload.decode("outside text")}
        var changed=project;changed.revision+=1;let newer=changed
        #expect(throws:ClipEditingError.stale){try ClipEditing.move(token,to:changed.tracks[3].id,start:0,in:&changed)}
        #expect(changed==newer)
        var foreign=project;foreign.id=UUID()
        let other=ArrangementDragPayload(project:foreign,trackID:project.tracks[2].id,clipID:clip.id)
        #expect(throws:ClipEditingError.stale){try ClipEditing.delete(other,in:&project)}
        #expect(project==before)
    }
    @Test func aCompletedDropIsOneUndoAndRedoTransaction() throws {
        var project=try melodySong();let original=project;var history=History()
        let clip=project.tracks[2].clips[0],token=ArrangementDragPayload(project:project,trackID:project.tracks[2].id,clipID:project.tracks[2].clips[0].id)
        try history.apply(&project){try ClipEditing.move(token,to:$0.tracks[3].id,start:0,in:&$0)}
        #expect(project.revision==1);#expect(project.tracks[3].clips[0].id==clip.id)
        history.undo(&project)
        #expect(project.tracks==original.tracks);#expect(project.patterns==original.patterns)
        history.redo(&project)
        #expect(project.tracks[2].clips.isEmpty);#expect(project.tracks[3].clips[0].id==clip.id)
    }
    @Test func sectionDragMovesAllTrackContentAndPreservesCrossingClipPhase() throws {
        var project=Project(name:"Sections",bars:4)
        project.sections=[Section(name:"A",start:0,length:barTicks),Section(name:"B",start:barTicks,length:barTicks),Section(name:"C",start:2*barTicks,length:2*barTicks)]
        project.patterns[0].chords=[ChordEvent(tick:0,duration:barTicks,chord:Chord(root:0)),ChordEvent(tick:barTicks,duration:barTicks,chord:Chord(root:2)),ChordEvent(tick:2*barTicks,duration:2*barTicks,chord:Chord(root:4))]
        project.tracks[0].clips[0].offset=240
        let original=project,source=project.sections[0].id,target=project.sections[2].id
        try ClipEditing.reorderSection(.init(project:project,sectionID:source),to:target,in:&project)
        #expect(project.sections.map(\.name)==["B","C","A"])
        #expect(project.sections.map(\.start)==[0,barTicks,3*barTicks])
        #expect(project.tracks[0].clips.count==3)
        let a=project.tracks[0].clips.first{$0.start==3*barTicks}!
        #expect(a.offset==240);#expect(a.length==barTicks)
        let b=project.tracks[0].clips.first{$0.start==0}!
        #expect(b.offset==barTicks+240)
        #expect(project.patterns==original.patterns)
        try project.validate()
        // All sounded durations from the original section slices remain represented.
        #expect(Compiler.notes(project).reduce(0){$0+$1.duration}==Compiler.notes(original).reduce(0){$0+$1.duration})
    }
    @Test func createDeleteAndDerivedBassHaveExplicitSemantics() throws {
        var project=try melodySong();project.tracks.append(Track(role:.bass));let before=project
        #expect(throws:ClipEditingError.derivedBass){try ClipEditing.create(on:project.tracks.last!.id,start:0,in:&project)}
        #expect(project==before)
        try ClipEditing.create(on:project.tracks[3].id,start:barTicks,length:barTicks,in:&project)
        #expect(project.tracks[3].clips.count==3)
        let created=project.tracks[3].clips.first{$0.start==barTicks}!
        #expect(created.length==barTicks)
        try ClipEditing.delete(.init(project:project,trackID:project.tracks[3].id,clipID:created.id),in:&project)
        #expect(project.tracks[3].clips.count==2)
        try project.validate()
    }
    @Test func duplicateAndDeleteSectionsPreserveCrossingContent() throws {
        var project=Project(name:"Crossing",bars:4)
        project.sections=[Section(name:"Verse",start:0,length:barTicks),Section(name:"Chorus",start:barTicks,length:3*barTicks)]
        project.patterns[0].chords=[ChordEvent(tick:0,duration:4*barTicks,chord:Chord(root:2,quality:.minor))]
        let original=project
        try project.duplicateSection(project.sections[0].id,name:"Verse copy")
        #expect(project.length==5*barTicks)
        #expect(project.sections.map(\.name)==["Verse","Verse copy","Chorus"])
        #expect(Compiler.notes(project).filter{$0.track==0}.reduce(0){$0+$1.duration}==15*barTicks)
        let copied=project.tracks[0].clips.first{$0.start==barTicks}!
        #expect(copied.patternID != original.tracks[0].clips[0].patternID)
        try project.deleteSection(project.sections[1].id)
        #expect(project.length==4*barTicks)
        #expect(Compiler.notes(project).filter{$0.track==0}.reduce(0){$0+$1.duration}==12*barTicks)
        try project.deleteSection(project.sections[0].id)
        #expect(project.length==3*barTicks)
        #expect(project.patterns.allSatisfy{$0.length<=project.length})
        #expect(Compiler.notes(project).filter{$0.track==0}.reduce(0){$0+$1.duration}==9*barTicks)
        try project.validate()
    }
    @Test func chordCellsFollowClipLoopsTrimsAndSourceIdentity() {
        let event=ChordEvent(tick:240,duration:480,chord:Chord(root:2))
        let pattern=Pattern(length:barTicks,chords:[event])
        var clip=Clip(patternID:pattern.id,start:barTicks,length:2*barTicks)
        clip.offset=480
        let slices=ClipEditing.chordSlices(clip:clip,pattern:pattern)
        #expect(slices.reduce(0){$0+$1.duration}==clip.length)
        #expect(Set(slices.map(\.id)).count==slices.count)
        #expect(slices.first?.timelineTick==barTicks)
        #expect(slices.first?.duration==240)
        #expect(slices.first?.event?.id==event.id)
        #expect(slices.first?.sourceTick==240)
        #expect(slices.filter{$0.event != nil}.map(\.timelineTick)==[barTicks,2*barTicks-240,3*barTicks-240])
        #expect(slices.last!.timelineTick+slices.last!.duration==3*barTicks)
        let corrupt=Pattern(length:Int.max,chords:[ChordEvent(tick:Int.max,duration:Int.max,chord:Chord(root:0))])
        #expect(ClipEditing.chordSlices(clip:clip,pattern:corrupt).isEmpty)
    }
    @Test func sourceRecordingSurvivesClipCopiesMovesAndSectionSplits() throws {
        var project=try melodySong()
        let record=AudioAssetRecord(sha256:String(repeating:"a",count:64),byteCount:128,sampleRate:48000,duration:0.1)
        project.audioAssets=[record];project.tracks[2].clips[0].sourceAssetID=record.id
        project.sections=[Section(name:"A",start:0,length:barTicks),Section(name:"B",start:barTicks,length:3*barTicks)]
        let id=project.tracks[2].clips[0].id
        try ClipEditing.copy(.init(project:project,trackID:project.tracks[2].id,clipID:id),to:project.tracks[3].id,start:0,in:&project)
        #expect(project.tracks[3].clips[0].sourceAssetID==record.id)
        try ClipEditing.reorderSection(.init(project:project,sectionID:project.sections[0].id),to:project.sections[1].id,in:&project)
        #expect(project.tracks.filter{$0.role == .melody}.flatMap(\.clips).allSatisfy{$0.sourceAssetID==record.id})
        #expect(project.audioAssets==[record]);try project.validate()
    }
}
