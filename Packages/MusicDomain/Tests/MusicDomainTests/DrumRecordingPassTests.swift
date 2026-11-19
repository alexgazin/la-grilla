import Foundation
import Testing
@testable import MusicDomain

struct DrumRecordingPassTests {
    private func draft(_ project:Project)throws->DrumRecordingDraft {
        try DrumRecordingDraft(project:project,clipID:project.tracks[1].clips[0].id)
    }

    @Test func acceptedEventsCommitAgainstTheRealValidatorWithoutMutatingTheSource()throws {
        var project=Project(bars:2)
        project.tracks[1].clips[0].length=barTicks+720
        let original=project
        var recording=try draft(project),pass=try DrumRecordingPass(draft:recording)
        for index in 0..<512 {
            try pass.append(DrumEvent(tick:(index*137)%recording.length,pad:index%16,velocity:1+index%127))
        }
        #expect(pass.events.count==512)
        #expect(project==original)
        #expect(recording.project.patterns.first{$0.id==recording.patternID}?.drums.isEmpty==true)
        try recording.commitPass(pass.events)
        try recording.project.validate()
        #expect(Compiler.notes(recording.project).count==512)
        #expect(project==original)
    }

    @Test func replacementReservesOnlyRetainedEventsAndMatchesFullCommit()throws {
        var project=Project(bars:2)
        let replaced=DrumEvent(tick:0,pad:1),retained=DrumEvent(tick:barTicks,pad:2)
        project.patterns[1].drums=[replaced,retained]
        var recording=try draft(project)
        let material=try #require(recording.project.patterns.first{$0.id==recording.patternID})
        let removedID=material.drums[0].id,retainedID=material.drums[1].id
        let range=0..<barTicks
        var pass=try DrumRecordingPass(draft:recording,replacing:range)
        var replacement=DrumEvent(tick:240,pad:15,velocity:127);replacement.id=removedID
        try pass.append(replacement)
        var duplicate=DrumEvent(tick:480,pad:1);duplicate.id=retainedID
        #expect(throws:MusicError.self){try pass.append(duplicate)}
        #expect(pass.events==[replacement])
        try recording.commitPass(pass.events,replacing:range)
        let result=try #require(recording.project.patterns.first{$0.id==recording.patternID})
        #expect(result.drums.count==2 && result.drums.contains{$0.id==retainedID} && result.drums.contains(replacement))
        try recording.project.validate()
    }

    @Test func invalidFieldsAndEveryBaseIdentityFailAtomically()throws {
        var project=Project(bars:1)
        project.patterns[0].chords=[ChordEvent(tick:0,chord:Chord(root:0))]
        project.patterns[1].drums=[DrumEvent(tick:0,pad:0)]
        let recording=try draft(project),base=recording.project
        var pass=try DrumRecordingPass(draft:recording)
        let accepted=DrumEvent(tick:0,pad:15,velocity:127)
        try pass.append(accepted)
        var bad=[DrumEvent(tick:-1,pad:0),DrumEvent(tick:recording.length,pad:0),
                 DrumEvent(tick:Int.max,pad:0),DrumEvent(tick:Int.min,pad:0),
                 DrumEvent(tick:0,pad:-1),DrumEvent(tick:0,pad:16),
                 DrumEvent(tick:0,pad:0,velocity:0),DrumEvent(tick:0,pad:0,velocity:128),accepted]
        var ids=[base.id]
        ids+=base.tracks.map(\.id);ids+=base.patterns.map(\.id);ids+=base.sections.map(\.id)
        for track in base.tracks{ids+=track.clips.map(\.id)}
        for pattern in base.patterns{ids+=pattern.chords.map(\.id);ids+=pattern.drums.map(\.id)}
        for id in ids{var value=DrumEvent(tick:0,pad:1);value.id=id;bad.append(value)}
        for value in bad {
            do{try pass.append(value);Issue.record("Invalid event was accepted")}
            catch MusicError.invalidProject{}
            #expect(pass.events==[accepted])
        }
        #expect(throws:MusicError.self){try DrumRecordingPass(draft:recording,replacing:(-1)..<0)}
        #expect(throws:MusicError.self){try DrumRecordingPass(draft:recording,replacing:0..<(64*barTicks+1))}
    }

    @Test func patternLimitIsCertifiedAndOverflowDoesNotAppend()throws {
        var project=Project(bars:1)
        project.patterns[1].drums=(0..<4095).map{DrumEvent(tick:$0%barTicks,pad:$0%16)}
        var recording=try draft(project),pass=try DrumRecordingPass(draft:recording)
        #expect(pass.capacity==1)
        // A free pad/tick: an identical existing step would merge into one attack.
        try pass.append(DrumEvent(tick:1,pad:0))
        do{try pass.append(DrumEvent(tick:0,pad:1));Issue.record("Pattern overflow was accepted")}
        catch MusicError.tooDense{}
        #expect(pass.events.count==1)
        try recording.commitPass(pass.events);try recording.project.validate()
        #expect(recording.project.patterns.first{$0.id==recording.patternID}?.drums.count==4096)
    }

    private func compiledBoundary(lastLength:Int)throws->Project {
        var project=Project(bars:16)
        project.patterns[0].length=barTicks
        project.patterns[0].chords=(0..<128).map{ChordEvent(tick:$0,duration:1,chord:Chord(root:0,quality:.maj7))}
        let notes=Pattern(length:project.length,notes:(0..<4096).map{NoteEvent(tick:$0,duration:1,pitch:60)})
        project.patterns.append(notes)
        for index in 0..<6 {
            var track=Track(role:.melody)
            track.clips=[Clip(patternID:notes.id,start:0,length:index==5 ? lastLength:project.length)]
            project.tracks.append(track)
        }
        try project.validate();return project
    }

    @Test func actualCompiledLimitAcceptsTheLastNoteAndRejectsTheNext()throws {
        let project=try compiledBoundary(lastLength:4095)
        #expect(Compiler.notes(project).count==32767)
        var recording=try draft(project),pass=try DrumRecordingPass(draft:recording)
        #expect(pass.capacity==1)
        try pass.append(DrumEvent(tick:0,pad:0))
        #expect(throws:MusicError.self){try pass.append(DrumEvent(tick:1,pad:1))}
        try recording.commitPass(pass.events);try recording.project.validate()
        #expect(Compiler.notes(recording.project).count==32768)
        #expect(throws:MusicError.self){try recording.commitPass([DrumEvent(tick:2,pad:2)])}
    }

    @Test func aValidAlreadyFullCompiledProjectProvidesZeroCapacity()throws {
        let project=try compiledBoundary(lastLength:4096)
        #expect(Compiler.notes(project).count==32768)
        var pass=try DrumRecordingPass(draft:draft(project))
        #expect(pass.capacity==0)
        do{try pass.append(DrumEvent(tick:0,pad:0));Issue.record("Compiled overflow was accepted")}
        catch MusicError.tooDense{}
        #expect(pass.events.isEmpty)
    }

    @Test func conservativeGlobalVoiceBoundIsIndependentOfActualCompiledNotes()throws {
        var project=Project(bars:2)
        project.patterns[0].drums=(0..<4095).map{DrumEvent(tick:$0%project.length,pad:$0%16)}
        let shared=project.patterns[0].id
        project.tracks[0].clips=[Clip(patternID:shared,start:0,length:barTicks),Clip(patternID:shared,start:barTicks,length:barTicks)]
        for _ in 0..<6{var track=Track(role:.melody);track.clips=[Clip(patternID:shared,start:0,length:project.length)];project.tracks.append(track)}
        try project.validate()
        #expect(Compiler.notes(project).isEmpty)
        var recording=try draft(project),pass=try DrumRecordingPass(draft:recording)
        #expect(pass.capacity==8)
        for pad in 0..<8{try pass.append(DrumEvent(tick:0,pad:pad))}
        #expect(throws:MusicError.self){try pass.append(DrumEvent(tick:1,pad:0))}
        try recording.commitPass(pass.events);try recording.project.validate()
        #expect(Compiler.notes(recording.project).count==8)
        #expect(throws:MusicError.self){try recording.commitPass([DrumEvent(tick:2,pad:0)])}
    }

    @Test func maximumValidEventEncodingFitsTheReservedBytes()throws {
        var event=DrumEvent(tick:64*barTicks-1,pad:15,velocity:127)
        event.id=try #require(UUID(uuidString:"FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        #expect(try JSONEncoder().encode(event).count+1<=128)
        for tick in [0,9,99,999,9999,99999,64*barTicks-1] {
            event.tick=tick
            #expect(try JSONEncoder().encode(event).count+1<=128)
        }
    }

    @Test func nearEightMegabyteProjectCannotOverrunTheEncodedSizeCertificate()throws {
        var project=Project(bars:64)
        project.tracks[1].clips[0].length=barTicks
        let pattern=project.patterns[0].id
        project.tracks[0].clips=[Clip(patternID:pattern,start:100000,length:1)]
        let one=try draft(project),encoder=JSONEncoder()
        let baselineBytes=try encoder.encode(one.project).count
        let perClip=try encoder.encode(project.tracks[0].clips[0]).count+1
        let count=1+(8_000_000-baselineBytes-16)/perClip
        project.tracks[0].clips=(0..<count).map{Clip(patternID:pattern,start:100000+$0,length:1)}
        var recording=try draft(project),pass=try DrumRecordingPass(draft:recording)
        let bytes=try encoder.encode(recording.project).count
        #expect(bytes<=8_000_000 && bytes>7_999_800)
        #expect(pass.capacity==(8_000_000-bytes)/128 && pass.capacity<=1)
        for pad in 0..<pass.capacity{try pass.append(DrumEvent(tick:0,pad:pad))}
        #expect(throws:MusicError.self){try pass.append(DrumEvent(tick:0,pad:15))}
        try recording.commitPass(pass.events);try recording.project.validate()
        #expect(try encoder.encode(recording.project).count<=8_000_000)
    }
}
