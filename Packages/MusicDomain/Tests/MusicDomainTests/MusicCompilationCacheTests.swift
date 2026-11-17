import Foundation
import Testing
@testable import MusicDomain

struct MusicCompilationCacheTests {
    private func fixture()throws->Project {
        var project=Project.demo()
        try project.addMelody()
        let pattern=project.patterns.count-1
        project.patterns[pattern].notes=[
            NoteEvent(tick:0,duration:ppq,pitch:60,velocity:91),
            NoteEvent(tick:barTicks+ppq,duration:ppq,pitch:67,velocity:79)
        ]
        try project.validate()
        return project
    }

    @Test func mixerMetadataAndPublicationInputsReuseOneActualCompilation()throws {
        var project=try fixture(),cache=MusicCompilationCache()
        let expected=Compiler.notes(project)
        #expect(cache.notes(project)==expected)
        for step in 0..<128 {
            project.tracks[0].gain = -Double(step%50)
            project.tracks[1].pan=Double(step%11)/10
            project.tracks[2].mute=step%2==0;project.tracks[3].solo=step%3==0
            project.master = -Double(step%30)
            project.masterFX=MasterFX(filter:Double(step%10)/10,delayWet:0.2)
            project.name="Fader revision \(step)";project.tracks[0].name="Harmony \(step)"
            project.sections[0].name="Verse \(step)";project.revision=step
            project.modified=project.modified.addingTimeInterval(1)
            project.bpm=Double(80+step%80);project.keyRoot=step%12;project.minor=step%2==0
            project.tracks[0].presetVersion=step%2+1
            #expect(cache.notes(project)==expected)
            #expect(cache.compileCount==1)
            #expect(cache.retainedCompilationCount==1)
        }
        try project.validate()
        // A new project/track identity still has the same tick-based notes.
        // AudioController separately retains its identity/layout/BPM guards.
        project.id=UUID();project.tracks[2].id=UUID()
        #expect(cache.notes(project)==Compiler.notes(project))
        #expect(cache.compileCount==1)
    }

    @Test func musicalChangesInvalidateEvenWithUnchangedUUIDAndRevision()throws {
        let original=try fixture()
        let edits:[(String,(inout Project)->Void)]=[
            ("chord duration",{$0.patterns[0].chords[0].duration=ppq}),
            ("chord quality",{$0.patterns[0].chords[0].chord.quality = .minor}),
            ("chord inversion",{$0.patterns[0].chords[0].chord.inversion=1}),
            ("chord voicing",{$0.patterns[0].chords[0].chord.voicedNotes=[48,52,55]}),
            ("custom formula",{$0.patterns[0].chords[0].chord.customIntervals=[0,3,7,10]}),
            ("schema 9 root bass",{$0.patterns[0].chords[0].chord.rootBassPitch=48}),
            ("bass register",{$0.bassOctave = -1}),
            ("bass gate",{$0.bassGate=0.5}),
            ("drum onset",{$0.patterns[1].drums[0].tick+=120}),
            ("drum pad",{$0.patterns[1].drums[0].pad=3}),
            ("drum velocity",{$0.patterns[1].drums[0].velocity=71}),
            ("note pitch",{$0.patterns[2].notes?[0].pitch=61}),
            ("note onset",{$0.patterns[2].notes?[0].tick=120}),
            ("note duration",{$0.patterns[2].notes?[0].duration=480}),
            ("note velocity",{$0.patterns[2].notes?[0].velocity=66}),
            ("clip offset",{$0.tracks[0].clips[0].offset=240}),
            ("clip duration",{$0.tracks[0].clips[0].length=3*barTicks}),
            ("clip position",{$0.tracks[0].clips[0].start=barTicks;$0.tracks[0].clips[0].length=3*barTicks}),
            ("clip pattern",{$0.tracks[0].clips[0].patternID=$0.patterns[1].id}),
            ("pattern cycles",{$0.patterns[2].length=2*barTicks}),
            ("track reorder",{$0.tracks.swapAt(2,3)}),
            ("track role",{$0.tracks[2].role = .melody}),
            ("project length",{$0.sections[0].length=8*barTicks})
        ]
        for (name,edit) in edits {
            var changed=original,cache=MusicCompilationCache()
            let baseline=cache.notes(original)
            edit(&changed)
            try changed.validate()
            #expect(changed.id==original.id && changed.revision==original.revision)
            #expect(cache.notes(changed)==Compiler.notes(changed),"\(name)")
            #expect(cache.compileCount==2,"\(name)")
            #expect(cache.notes(changed)==Compiler.notes(changed))
            #expect(cache.compileCount==2)
            // Retaining the first result cannot alias a later mutable project.
            #expect(baseline==Compiler.notes(original))
        }
    }

    @Test func schemaNineExactBassPitchIsNotHiddenByAnEqualChordSymbol()throws {
        var project=try fixture(),cache=MusicCompilationCache()
        let before=cache.notes(project),symbol=project.patterns[0].chords[0].chord.symbol
        project.patterns[0].chords[0].chord.rootBassPitch=48
        try project.validate()
        let after=cache.notes(project)
        #expect(project.schemaVersion==Project.currentSchemaVersion)
        #expect(project.patterns[0].chords[0].chord.symbol==symbol)
        #expect(after != before && after==Compiler.notes(project))
        #expect(after.first{$0.track==2 && $0.tick==0}?.pitch==48)
        #expect(cache.compileCount==2)
    }

    @Test func rangeChangesAndResetRequireFreshNotesButReturnedArraysAreValues()throws {
        let project=try fixture();var cache=MusicCompilationCache()
        #expect(cache.retainedCompilationCount==0 && cache.cachedNoteCount==0)
        let firstRange=barTicks..<3*barTicks
        var result=cache.notes(project,range:firstRange)
        #expect(result==Compiler.notes(project,range:firstRange))
        result[0].pitch=1
        #expect(cache.notes(project,range:firstRange)==Compiler.notes(project,range:firstRange))
        #expect(cache.compileCount==1)
        #expect(cache.notes(project)==Compiler.notes(project))
        #expect(cache.compileCount==2)
        cache.reset()
        #expect(cache.retainedCompilationCount==0 && cache.cachedNoteCount==0)
        #expect(cache.compileCount==2)
        #expect(cache.notes(project)==Compiler.notes(project))
        #expect(cache.compileCount==3)
    }

    @Test func onlyTheMostRecentMusicalValueIsRetained()throws {
        let original=try fixture();var cache=MusicCompilationCache(),changed=original
        _=cache.notes(original)
        changed.patterns[2].notes?[0].pitch=62
        #expect(cache.notes(changed)==Compiler.notes(changed))
        #expect(cache.compileCount==2 && cache.retainedCompilationCount==1)
        #expect(cache.notes(original)==Compiler.notes(original))
        #expect(cache.compileCount==3 && cache.retainedCompilationCount==1)
        #expect(cache.cachedNoteCount==Compiler.notes(original).count)
    }

    @Test func denseP3FaderEditsRetainExact16384NotesWithoutRecompiling()throws {
        let path=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/release/fixtures/load-P3.grillapack").standardizedFileURL
        var project=try PortableProject.decode(Data(contentsOf:path),asCopy:false)
        var cache=MusicCompilationCache()
        let expected=Compiler.notes(project)
        #expect(expected.count==16384)
        #expect(cache.notes(project)==expected)
        for step in 0..<64 {
            project.tracks[step%project.tracks.count].gain = -Double(step%50)
            project.masterFX=MasterFX(filter:Double(step%10)/10,delayWet:0.1)
            project.revision+=1
            #expect(cache.notes(project)==expected)
        }
        #expect(cache.compileCount==1 && cache.retainedCompilationCount==1)
        #expect(cache.cachedNoteCount==16384)
    }
}
