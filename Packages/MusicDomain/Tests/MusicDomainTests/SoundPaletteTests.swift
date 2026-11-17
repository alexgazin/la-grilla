import Foundation
import Testing
@testable import MusicDomain

struct SoundPaletteTests {
    @Test func oldProjectsAndFrozenTakesKeepTheirExactPresetAndMusic()throws {
        for schema in 1...10 {
            var old=Project.demo();old.schemaVersion=schema
            for index in old.tracks.indices{old.tracks[index].presetVersion=index.isMultiple(of:2) ? 1:2}
            old.performanceTake=PerformanceTake(source:old,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:old.sections[0].id)])
            let data=try JSONEncoder().encode(old)
            let loaded=try ProjectDocument.decode(data)
            #expect(loaded.schemaVersion==11)
            #expect(loaded.tracks==old.tracks)
            #expect(loaded.patterns==old.patterns)
            #expect(Compiler.notes(loaded)==Compiler.notes(old))
            #expect(loaded.performanceTake?.source.tracks==old.tracks)
            #expect(loaded.performanceTake?.source.schemaVersion==11)
            #expect(try JSONDecoder().decode(Project.self,from:data)==old)
            var malformed=old;malformed.tracks[0].presetVersion=3
            #expect(throws:MusicError.self){try ProjectDocument.decode(JSONEncoder().encode(malformed))}
        }
        var future=Project.demo();future.schemaVersion=Project.currentSchemaVersion+1
        #expect(throws:MusicError.unsupportedSchema){try ProjectDocument.decode(JSONEncoder().encode(future))}
    }

    @Test func soundChangeIsOneUndoAndPortableAndStorePreserveIt()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=ProjectStore(root:folder)
        var project=Project.demo(),history=History()
        let original=project
        try history.apply(&project){$0.tracks[0].presetVersion=SoundPalette.warm.rawValue}
        #expect(project.tracks[0].presetVersion==3)
        #expect(project.patterns==original.patterns && project.sections==original.sections)
        #expect(Compiler.notes(project)==Compiler.notes(original))
        history.undo(&project)
        #expect(project.tracks==original.tracks && !history.canUndo)
        history.redo(&project)
        #expect(project.tracks[0].presetVersion==3)
        project.tracks[1].presetVersion=4
        _=try await store.save(project)
        #expect(try await store.load(project.id)==project)
        #expect(try PortableProject.decode(PortableProject.data(project),asCopy:false)==project)
        var invalid=project;invalid.tracks[0].presetVersion=5
        #expect(throws:MusicError.self){try invalid.validate()}
    }

    @Test func shortAuditionIsIsolatedAndLeavesTheSourceUntouched()throws {
        var source=Project.demo();try source.addMelody()
        source.patterns[source.patterns.count-1].notes=[NoteEvent(tick:0,pitch:72)]
        source.master = -12;source.tracks[0].gain = -18
        source.performanceTake=PerformanceTake(source:source,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:source.sections[0].id)])
        let unchanged=source
        for selected in source.tracks.indices {
            for palette in SoundPalette.selectable {
                let preview=try TrackSoundPreview.project(from:source,trackID:source.tracks[selected].id,palette:palette)
                try preview.validate()
                #expect(preview.id==source.id && preview.revision==source.revision)
                #expect(preview.length==barTicks && preview.tracks.map(\.id)==source.tracks.map(\.id))
                #expect(preview.performanceTake==nil)
                #expect(preview.tracks[selected].presetVersion==palette.rawValue)
                #expect(preview.master<=source.master && preview.tracks[selected].gain<=source.tracks[selected].gain)
                let audible=Compiler.notes(preview).filter{!preview.tracks[$0.track].mute}
                #expect(!audible.isEmpty && audible.allSatisfy{$0.track==selected})
                #expect(source==unchanged)
            }
        }
    }

    @Test func alternateSoundsRemainFrozenWithTheTake()throws {
        var project=Project.demo();project.tracks[0].presetVersion=3;project.tracks[1].presetVersion=4
        let take=PerformanceTake(source:project,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:project.sections[0].id)])
        project.performanceTake=take
        project.tracks[0].presetVersion=4;project.tracks[1].presetVersion=2
        let loaded=try PortableProject.decode(PortableProject.data(project),asCopy:false)
        #expect(loaded.tracks[0].presetVersion==4 && loaded.tracks[1].presetVersion==2)
        #expect(loaded.performanceTake?.source.tracks[0].presetVersion==3)
        #expect(loaded.performanceTake?.source.tracks[1].presetVersion==4)
    }

    @Test func actualOfflineExportsUseEveryTrackPalette()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        var source=Project.demo();try source.addMelody()
        for track in source.tracks {
            var audio:[Data]=[]
            for palette in SoundPalette.selectable {
                let project=try TrackSoundPreview.project(from:source,trackID:track.id,palette:palette)
                let url=folder.appendingPathComponent("\(track.role.rawValue)-\(palette.rawValue).wav")
                let result=try await OfflineRenderer.render(project,to:url,settings:WAVSettings(sampleRate:48000,bitDepth:24,tailSeconds:0,dither:false))
                #expect(result.frames==96000 && result.peak>0.001 && result.peak.isFinite && !result.clipped)
                audio.append(try Data(contentsOf:url))
            }
            #expect(audio[0] != audio[1] && audio[1] != audio[2] && audio[0] != audio[2])
        }
    }
}
