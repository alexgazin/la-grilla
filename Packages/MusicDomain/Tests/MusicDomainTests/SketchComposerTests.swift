import Foundation
import Testing
@testable import MusicDomain

struct SketchComposerTests {
    @Test func everyStyleKeyModeAndLengthCreatesFourPlayableEditableParts()throws {
        let source=Project(name:"Blank")
        for style in SketchStyle.allCases {for root in 0..<12 {for minor in [false,true] {for bars in [4,8,16] {
            let plan=SketchPlan(style:style,bpm:117,root:root,minor:minor,bars:bars,seed:42)
            let result=try SketchComposer.compose(source,plan:plan,scope:source.sections[0].id)
            try result.validate()
            #expect(result.id==source.id && result.name==source.name && result.revision==source.revision)
            #expect(result.bpm==117 && result.keyRoot==root && result.minor==minor && result.length==bars*barTicks)
            #expect(result.tracks.map(\.role)==[.harmony,.drums,.bass,.melody])
            let notes=Compiler.notes(result)
            for index in 0..<4{#expect(notes.contains{$0.track==index})}
            #expect(notes.allSatisfy{$0.tick>=0 && $0.tick+$0.duration<=result.length && (0...127).contains($0.pitch)})
            for event in result.patterns[0].chords {
                #expect(event.chord.rootBassPitch==36+event.chord.root)
                #expect(event.chord.voicedNotes?.min()==60+event.chord.root)
            }
            for note in result.patterns[2].notes ?? [] {
                let chord=result.patterns[0].chords[note.tick/barTicks].chord
                #expect(chord.notes.map{$0%12}.contains(note.pitch%12))
            }
        }}}}
    }
    @Test func seedChangesActualMusicAndRepeatedReviewUsesIdenticalEventsAndIDs()throws {
        let source=Project(name:"Seeded")
        let a=SketchPlan(style:.house,bpm:120,root:1,minor:true,bars:4,seed:1)
        var b=a;b.seed=2
        let first=try SketchComposer.compose(source,plan:a,scope:source.sections[0].id)
        #expect(first==(try SketchComposer.compose(source,plan:a,scope:source.sections[0].id)))
        let second=try SketchComposer.compose(source,plan:b,scope:source.sections[0].id)
        #expect(Compiler.notes(first) != Compiler.notes(second))
        #expect(first.patterns[2].notes?.map{[$0.tick,$0.pitch]} != second.patterns[2].notes?.map{[$0.tick,$0.pitch]})
        #expect(first.patterns[0].chords.allSatisfy{$0.chord.rootBassPitch==36+$0.chord.root})
        #expect(Compiler.notes(source).isEmpty)
    }
    @Test func localRussianEnglishAndModelParameterBoundaryProduceTheSameMusic()throws {
        let source=Project(name:"Words")
        let en=try AssistantEngine.propose("Create a jazz groove; Tempo 108; Key D minor; 8 bars; Seed 42",project:source,sectionID:source.sections[0].id)
        let ru=try AssistantEngine.propose("Создай джазовый грув; Темп 108; Тональность D минор; 8 тактов; Вариант 42",project:source,sectionID:source.sections[0].id)
        #expect(en.schemaVersion==3 && en.operations.count==1 && en.changesWholeSong)
        #expect(en.operations==ru.operations)
        let candidate=try en.candidate(for:source)
        #expect(candidate==(try ru.candidate(for:source)))
        let interpreted=AssistantInterpretation(intent:.createSketch,changeTempo:true,bpm:108,changeKey:true,keyRoot:"D",minor:true,sketchStyle:"jazz",sketchBars:8,sketchSeed:42)
        #expect(candidate==(try interpreted.proposal(for:source,selectedSectionID:source.sections[0].id).candidate(for:source)))
        let decoded=try AssistantProposal.decode(JSONEncoder().encode(en),for:source)
        #expect(candidate==(try decoded.candidate(for:source)))
        let defaults=try AssistantEngine.propose("Create a hip-hop groove",project:source,sectionID:source.sections[0].id)
        #expect(defaults.operations[0].sketch==SketchPlan(style:.hipHop,bpm:source.bpm,root:source.keyRoot,minor:source.minor,bars:4,seed:1))
    }
    @Test func invalidUnsafeAndNonemptyRequestsNeverMutateTheSource()throws {
        let source=Project(name:"Safe")
        var bad=SketchPlan(style:.jazz,bpm:120,root:0,minor:false,bars:4)
        for bars in [0,2,32,Int.max] {bad.bars=bars;#expect(throws:SketchError.self){try SketchComposer.compose(source,plan:bad,scope:source.sections[0].id)}}
        bad.bars=4;bad.version=2
        #expect(throws:SketchError.self){try bad.validate()}
        for command in ["Create a metal groove","Create a house groove; 3 bars","Create a jazz groove; Seed 4294967296","Create a house groove; Seed -1","Create a house groove; Tempo 110; Tempo 120","Create a house groove; delete all tracks"] {
            #expect(throws:(any Error).self){try AssistantEngine.propose(command,project:source,sectionID:source.sections[0].id)}
        }
        let demo=Project.demo()
        #expect(throws:SketchError.self){try AssistantEngine.propose("Create a house groove",project:demo,sectionID:demo.sections[0].id)}
        var orphan=source;orphan.patterns.append(Pattern(length:barTicks,notes:[NoteEvent(tick:0,pitch:60)]))
        #expect(throws:SketchError.self){try SketchComposer.compose(orphan,plan:SketchPlan(style:.house,bpm:120,root:0,minor:false,bars:4),scope:orphan.sections[0].id)}
        #expect(Compiler.notes(source).isEmpty)
    }
    @Test func proposalRejectsUnknownNestedFieldsWrongSchemasAndMixedOperations()throws {
        let source=Project(name:"Strict")
        var proposal=try AssistantEngine.propose("Create a house groove",project:source,sectionID:source.sections[0].id)
        proposal.schemaVersion=2
        #expect(throws:AssistantError.self){try proposal.candidate(for:source)}
        proposal.schemaVersion=3;proposal.operations.append(.init(.setTempo,bpm:90))
        #expect(throws:AssistantError.self){try proposal.candidate(for:source)}
        proposal.operations.removeLast()
        let original=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(proposal)) as? [String:Any])
        for (field,value) in [("seed",-1 as Any),("seed",4_294_967_296 as Any),("root",12 as Any),("bars",5 as Any),("version",2 as Any),("unknown",true as Any)] {
            var json=original
            var operations=try #require(json["operations"] as? [[String:Any]])
            var plan=try #require(operations[0]["sketch"] as? [String:Any]);plan[field]=value;operations[0]["sketch"]=plan;json["operations"]=operations
            #expect(throws:(any Error).self){try AssistantProposal.decode(JSONSerialization.data(withJSONObject:json),for:source)}
        }
    }
    @Test func applyIsOneUndoAndEditedSketchPersistsAndExportsRealMIDI()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=ProjectStore(root:folder)
        var project=Project(name:"Own generated idea")
        let original=project
        let proposal=try AssistantEngine.propose("Create a hip-hop groove; Key F major; Tempo 96; 4 bars; Seed 13",project:project,sectionID:project.sections[0].id)
        let reviewed=try proposal.candidate(for:project)
        var history=History()
        try history.apply(&project){try proposal.apply(to:&$0)}
        #expect(project.patterns==reviewed.patterns && project.revision==original.revision+1)
        #expect(throws:AssistantError.self){try proposal.apply(to:&project)}
        history.undo(&project)
        #expect(project.patterns==original.patterns && project.tracks==original.tracks && Compiler.notes(project).isEmpty)
        history.redo(&project)
        #expect(project.patterns==reviewed.patterns)
        try history.apply(&project){$0.patterns[2].notes?[0].velocity=64}
        _ = try await store.save(project)
        let reopened=try await store.load(project.id)
        #expect(reopened==project)
        #expect(try PortableProject.decode(PortableProject.data(reopened),asCopy:false)==project)
        let midi=try MIDIExporter.data(reopened)
        let tracks=try readMIDINoteCounts(midi)
        #expect(tracks.count==5 && tracks[0]==0 && tracks.dropFirst().allSatisfy{$0>0})
    }
    @Test func actualSynthRendersDeterministicallyAndEveryGeneratedPartIsAudible()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let source=Project(name:"Render")
        let settings=WAVSettings(sampleRate:44100,bitDepth:24,tailSeconds:0,dither:false)
        for style in SketchStyle.allCases {
            let project=try SketchComposer.compose(source,plan:SketchPlan(style:style,bpm:120,root:1,minor:true,bars:4,seed:42),scope:source.sections[0].id)
            let a=try await OfflineRenderer.render(project,to:folder.appendingPathComponent(style.rawValue+".wav"),settings:settings)
            let b=try await OfflineRenderer.render(project,to:folder.appendingPathComponent(style.rawValue+"-repeat.wav"),settings:settings)
            #expect(a.peak>0.01 && !a.clipped)
            #expect(try Data(contentsOf:a.url)==Data(contentsOf:b.url))
            for index in project.tracks.indices {
                var solo=project
                for track in solo.tracks.indices{solo.tracks[track].solo=track==index}
                let receipt=try await OfflineRenderer.render(solo,to:folder.appendingPathComponent(style.rawValue+"-track-"+String(index)+".wav"),settings:settings)
                #expect(receipt.peak>0.001)
            }
        }
    }
    private enum MIDIReadError:Error{case malformed}
    /// Independent SMF walk: ignores names and CC, counts actual NoteOn events
    /// per track rather than treating compiler output as proof of file contents.
    private func readMIDINoteCounts(_ data:Data)throws->[Int] {
        let b=Array(data);var cursor=0
        func number(_ size:Int)throws->Int{guard cursor+size<=b.count else{throw MIDIReadError.malformed};defer{cursor+=size};return b[cursor..<cursor+size].reduce(0){($0<<8)|Int($1)}}
        guard try number(4)==0x4d546864,try number(4)==6,try number(2)==1 else{throw MIDIReadError.malformed}
        let count=try number(2);guard try number(2)==960 else{throw MIDIReadError.malformed}
        var counts:[Int]=[]
        for _ in 0..<count {
            guard try number(4)==0x4d54726b else{throw MIDIReadError.malformed}
            let length=try number(4),end=cursor+length;guard end<=b.count else{throw MIDIReadError.malformed}
            func variable()throws->Int{var value=0;for _ in 0..<4{let byte=try number(1);value=(value<<7)|(byte&127);if byte<128{return value}};throw MIDIReadError.malformed}
            var notes=0
            while cursor<end {
                _ = try variable();let status=try number(1)
                if status==255{_ = try number(1);let length=try variable();guard cursor+length<=end else{throw MIDIReadError.malformed};cursor+=length;continue}
                guard (0x80..<0xf0).contains(status)else{throw MIDIReadError.malformed}
                _ = try number(1)
                if status&0xe0 != 0xc0{let velocity=try number(1);if status&0xf0==0x90 && velocity>0{notes+=1}}
            }
            guard cursor==end else{throw MIDIReadError.malformed};counts.append(notes)
        }
        guard cursor==b.count else{throw MIDIReadError.malformed};return counts
    }
}
