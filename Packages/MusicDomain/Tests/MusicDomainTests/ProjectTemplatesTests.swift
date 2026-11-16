import Foundation
import Testing
@testable import MusicDomain

struct ProjectTemplatesTests {
    @Test func starterHonorsChosenKeyModeTempoAndLengthWithRealEditableParts()throws {
        for root in 0..<12 {for minor in [false,true] {for bars in [1,2,4,8] {
            let p=try ProjectTemplates.make(name:"  Own idea  ",bpm:91,root:root,minor:minor,bars:bars,template:.starter)
            try p.validate()
            #expect(p.name=="Own idea" && p.bpm==91 && p.keyRoot==root && p.minor==minor)
            #expect(p.length==bars*barTicks)
            #expect(p.tracks.map(\.role)==[.harmony,.drums,.bass])
            #expect(p.patterns[0].chords.count==bars)
            #expect(p.patterns[0].chords.first?.chord.root==root)
            #expect(p.patterns[0].chords.first?.chord.quality==(minor ? .minor:.major))
            let scale=Set((minor ? [0,2,3,5,7,8,10]:[0,2,4,5,7,9,11]).map{($0+root)%12})
            let notes=Compiler.notes(p)
            for track in 0..<3{#expect(notes.contains{$0.track==track})}
            #expect(notes.allSatisfy{$0.tick>=0 && $0.tick+$0.duration<=p.length})
            #expect(notes.filter{$0.track != 1}.allSatisfy{scale.contains($0.pitch%12)})
            #expect(p.audioAssets==nil && p.performanceTake==nil)
        }}}
    }

    @Test func emptyRemainsSilentAndIndependentCreationsNeverShareDocumentOrEventIDs()throws {
        let empty=try ProjectTemplates.make(name:"Blank",bpm:140,root:3,minor:true,bars:8,template:.empty)
        #expect(Compiler.notes(empty).isEmpty)
        #expect(empty.tracks.map(\.role)==[.harmony,.drums])
        #expect(empty.bpm==140 && empty.keyRoot==3 && empty.minor && empty.length==8*barTicks)
        let a=try ProjectTemplates.make(name:"A",bpm:120,root:0,minor:false,bars:4,template:.starter)
        let b=try ProjectTemplates.make(name:"B",bpm:120,root:0,minor:false,bars:4,template:.starter)
        #expect(a.id != b.id)
        #expect(Set(a.patterns.map(\.id)).isDisjoint(with:b.patterns.map(\.id)))
        #expect(Set(a.patterns[0].chords.map(\.id)).isDisjoint(with:b.patterns[0].chords.map(\.id)))
        #expect(Set(a.patterns[1].drums.map(\.id)).isDisjoint(with:b.patterns[1].drums.map(\.id)))
        #expect(Set(a.tracks.map(\.id)).isDisjoint(with:b.tracks.map(\.id)))
    }

    @Test func invalidInputsFailBeforeBuildingUnboundedPatterns() {
        for bars in [0,65,Int.max] {
            #expect(throws:MusicError.self){try ProjectTemplates.make(name:"Bad",bpm:120,root:0,minor:false,bars:bars,template:.starter)}
        }
        for bpm in [Double.nan,Double.infinity,39,241] {
            #expect(throws:MusicError.self){try ProjectTemplates.make(name:"Bad",bpm:bpm,root:0,minor:false,bars:4,template:.starter)}
        }
        for root in [-1,12] {
            #expect(throws:MusicError.self){try ProjectTemplates.make(name:"Bad",bpm:120,root:root,minor:false,bars:4,template:.starter)}
        }
    }

    @Test func starterRendersNonzeroAudioWhileEmptyRendersSilence()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let settings=WAVSettings(sampleRate:44100,bitDepth:16,tailSeconds:0,dither:false)
        let starter=try ProjectTemplates.make(name:"Heard",bpm:120,root:5,minor:false,bars:1,template:.starter)
        let empty=try ProjectTemplates.make(name:"Silent",bpm:120,root:5,minor:false,bars:1,template:.empty)
        let heard=try await OfflineRenderer.render(starter,to:folder.appendingPathComponent("starter.wav"),settings:settings)
        let silence=try await OfflineRenderer.render(empty,to:folder.appendingPathComponent("empty.wav"),settings:settings)
        #expect(heard.peak>0.01 && !heard.clipped)
        #expect(silence.peak==0)
        #expect(try Data(contentsOf:heard.url).dropFirst(44).contains{$0 != 0})
        #expect(try Data(contentsOf:silence.url).dropFirst(44).allSatisfy{$0==0})
    }

    @Test func starterEditsUndoAndPersistsWithoutReplacingSourceMusic()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=ProjectStore(root:folder)
        var project=try ProjectTemplates.make(name:"Editable",bpm:108,root:2,minor:true,bars:4,template:.starter)
        let original=project
        var history=History()
        try history.apply(&project){$0.patterns[0].chords[0].chord.quality = .m7;$0.patterns[1].drums.append(DrumEvent(tick:120,pad:4))}
        #expect(Compiler.notes(project) != Compiler.notes(original))
        history.undo(&project)
        #expect(project.patterns==original.patterns)
        _ = try await store.save(project)
        let loaded=try await store.load(project.id)
        #expect(loaded==project)
        #expect(try PortableProject.decode(PortableProject.data(project),asCopy:false)==project)
    }
}
