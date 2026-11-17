import Foundation
import Testing
@testable import MusicDomain

struct MixEditValidationTests {
    @Test func allAllowedMixFieldsMatchTheFullyValidatedPath()throws {
        var full=Project.demo(),fast=full
        var fullHistory=History(),fastHistory=History()
        let change:(inout Project)->Void={project in
            project.master = -2.25;project.masterFX=MasterFX(filter:-0.7,delayWet:0.23)
            for i in project.tracks.indices {
                project.tracks[i].gain = -Double(i+1)*2
                project.tracks[i].pan = Double(i-1)/2
                project.tracks[i].mute=i==1;project.tracks[i].solo=i==2
            }
        }
        try fullHistory.apply(&full,change)
        try fastHistory.applyMix(&fast,change)
        var compared=fast;compared.modified=full.modified
        #expect(compared==full);#expect(fast.revision==1)
        #expect(fastHistory.canUndo);try fast.validate()
    }

    @Test func invalidMixRangesAndNonfiniteNumbersNeverChangeProjectOrHistory()throws {
        let changes:[(inout Project)->Void]=[
            {$0.master = .nan},{$0.master = .infinity},{$0.master = -61.01},{$0.master = 6.01},
            {$0.tracks[0].gain = .nan},{$0.tracks[0].gain = -.infinity},{$0.tracks[0].gain = -62},{$0.tracks[0].gain = 7},
            {$0.tracks[1].pan = .nan},{$0.tracks[1].pan = .infinity},{$0.tracks[1].pan = -1.01},{$0.tracks[1].pan = 1.01},
            {$0.masterFX=MasterFX(filter:.nan)},{$0.masterFX=MasterFX(filter:1.01)},
            {$0.masterFX=MasterFX(delayWet:.infinity)},{$0.masterFX=MasterFX(delayWet:-0.01)},{$0.masterFX=MasterFX(delayWet:0.51)}
        ]
        for change in changes {
            var p=Project.demo();let original=p;var history=History()
            #expect(throws:MusicError.self){try history.applyMix(&p,change)}
            #expect(p==original);#expect(!history.canUndo);#expect(!history.canRedo)
        }
    }

    @Test func structuralMetadataAndMusicChangesAreRejectedEvenWhenValid()throws {
        let changes:[(inout Project)->Void]=[
            {$0.bpm=108},{$0.keyRoot=5},{$0.minor=true},{$0.name="Different name"},
            {$0.id=UUID()},{$0.schemaVersion=8},{$0.bassGate=0.5},{$0.bassOctave=1},
            {$0.sections[0].name="Bridge"},{$0.patterns[0].chords[0].chord.root=2},
            {$0.patterns[1].drums[0].velocity=83},{$0.tracks[0].name="Piano"},
            {$0.tracks[0].presetVersion=1},{$0.tracks[0].id=UUID()},
            {$0.tracks[0].clips[0].offset=240},{$0.midi=MIDISettings()},
            {$0.tracks.removeLast()},{$0.performanceTake=PerformanceTake(source:$0,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:$0.sections[0].id)])}
        ]
        for change in changes {
            var p=Project.demo();var history=History()
            // Establish a genuine certificate; the rejected change must not rely
            // on the unchecked-baseline slow path to detect structural edits.
            try history.applyMix(&p){$0.master = -4}
            let original=p
            #expect(throws:MusicError.self){try history.applyMix(&p,coalescing:true,change)}
            #expect(p==original)
            history.undo(&p);#expect(p.master == -3);#expect(!history.canUndo)
        }
    }

    @Test func uncheckedOrSameRevisionMutatedInvalidBaselineIsNeverCertifiedByIdentity()throws {
        var p=Project.demo();var history=History()
        p.patterns[0].chords[0].tick = -1
        let invalid=p
        #expect(throws:MusicError.self){try history.applyMix(&p){$0.master = -1}}
        #expect(p==invalid);#expect(!history.canUndo)
        p=Project.demo();try history.applyMix(&p){$0.master = -4}
        let id=p.id,revision=p.revision
        p.patterns[1].drums[0].pad=999
        let tampered=p
        #expect(p.id==id && p.revision==revision)
        #expect(throws:MusicError.self){try history.applyMix(&p){$0.tracks[0].gain = -7}}
        #expect(p==tampered)
    }

    @Test func validExternallyChangedMusicIsFullyCheckedAndRetained()throws {
        var p=Project.demo();var history=History()
        try history.applyMix(&p){$0.master = -4}
        p.patterns[0].chords[0].chord=try Chord.parse("Dm7")
        let pattern=p.patterns[0]
        try history.applyMix(&p){$0.tracks[0].gain = -8}
        #expect(p.patterns[0]==pattern);#expect(p.tracks[0].gain == -8)
        try p.validate()
    }

    @Test func coalescingUndoRedoAndRevisionSemanticsStayTheSame()throws {
        var p=Project.demo();let original=p;var history=History()
        try history.applyMix(&p){$0.tracks[0].gain = -7}
        try history.applyMix(&p,coalescing:true){$0.tracks[0].gain = -8}
        try history.applyMix(&p,coalescing:true){$0.tracks[0].pan = 0.25}
        #expect(p.revision==3);let final=p
        history.undo(&p);#expect(p.tracks==original.tracks);#expect(p.revision==4);#expect(!history.canUndo)
        history.redo(&p);#expect(p.tracks==final.tracks);#expect(p.revision==5)
        try history.applyMix(&p){$0.master = -5};#expect(!history.canRedo)
        history.undo(&p);#expect(p.master==final.master);#expect(p.tracks==final.tracks)
        var atLimit=p;atLimit.revision=Project.maximumRevision;let snapshot=atLimit
        #expect(throws:MusicError.self){try history.applyMix(&atLimit){$0.master=0}}
        #expect(atLimit==snapshot)
    }

    @Test func thrownChangesStayAtomicAndFullMusicApplyStillWorks()throws {
        enum Failure:Error{case expected}
        var p=Project.demo();let original=p;var history=History()
        #expect(throws:Failure.self){try history.applyMix(&p){$0.master=0;throw Failure.expected}}
        #expect(p==original);#expect(!history.canUndo)
        try history.apply(&p){$0.patterns[0].chords[0].chord=try Chord.parse("Fmaj7")}
        let music=p.patterns
        try history.applyMix(&p){$0.masterFX=MasterFX(filter:0.3,delayWet:0.1)}
        #expect(p.patterns==music);try p.validate()
    }

    @Test func exportedMidiAndRealAudioMatchTheFullValidationMixPath()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        var full=Project.demo(),fast=full;var normalHistory=History(),fastHistory=History()
        let mix:(inout Project)->Void={$0.master = -2;$0.tracks[0].pan = -0.4;$0.tracks[1].gain = -9;$0.masterFX=MasterFX(filter:0.25,delayWet:0.2)}
        try normalHistory.apply(&full,mix);try fastHistory.applyMix(&fast,mix)
        #expect(try MIDIExporter.data(full)==MIDIExporter.data(fast))
        let settings=WAVSettings(sampleRate:44100,bitDepth:16,tailSeconds:0)
        let fullURL=root.appendingPathComponent("full.wav"),fastURL=root.appendingPathComponent("mix.wav")
        let fullReceipt=try await OfflineRenderer.render(full,to:fullURL,settings:settings,range:0..<barTicks)
        let fastReceipt=try await OfflineRenderer.render(fast,to:fastURL,settings:settings,range:0..<barTicks)
        #expect(fullReceipt.frames==fastReceipt.frames);#expect(fullReceipt.peak==fastReceipt.peak)
        #expect(try Data(contentsOf:fullURL)==Data(contentsOf:fastURL))
    }
}
