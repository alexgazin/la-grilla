import Foundation
import Testing
@testable import MusicDomain

struct PerformanceTests {
    @Test func instrumentUpgradePreservesVersionedFrozenSources()throws {
        var legacy=Project.demo();legacy.schemaVersion=6
        for i in legacy.tracks.indices{legacy.tracks[i].presetVersion=1}
        legacy.performanceTake=PerformanceTake(source:legacy,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:legacy.sections[0].id)])
        let migrated=try ProjectDocument.decode(JSONEncoder().encode(legacy))
        #expect(migrated.schemaVersion==Project.currentSchemaVersion)
        #expect(migrated.tracks.allSatisfy{$0.presetVersion==1})
        #expect(migrated.performanceTake?.source.tracks.allSatisfy{$0.presetVersion==1}==true)
        #expect(Project.demo().tracks.allSatisfy{$0.presetVersion==2})
        var invalid=migrated;invalid.tracks[0].presetVersion=3;#expect(throws:MusicError.self){try invalid.validate()}
    }
    @Test func finiteTimelineFollowsLaunchJumpRepeatAndLiveInputs()throws {
        var p=Project(name:"Timeline",bars:2);p.bpm=120
        p.patterns[0].chords=[ChordEvent(tick:0,duration:960,chord:Chord(root:0)),ChordEvent(tick:3840,duration:960,chord:Chord(root:7))]
        p.sections=[Section(name:"A",start:0,length:3840),Section(name:"B",start:3840,length:3840)]
        let events=[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id),PerformanceEvent(frame:24000,kind:.repeatSize,value:960),PerformanceEvent(frame:48000,kind:.repeatSize,value:0),PerformanceEvent(frame:96000,kind:.section,sectionID:p.sections[1].id),PerformanceEvent(frame:108000,kind:.pad,value:100,track:1,pad:0)]
        let take=PerformanceTake(source:p,sampleRate:48000,durationFrames:144000,events:events)
        let backing=try PerformanceTimeline.backingNotes(take),expanded=try PerformanceTimeline.notes(take)
        #expect(PerformanceTimeline.durationTicks(take)==5760)
        #expect(backing.contains{$0.tick==3840 && $0.pitch==55})
        #expect(!backing.contains{$0.tick==960 && $0.track==0})
        #expect(expanded.contains{$0.tick==960 && $0.pitch==60})
        #expect(expanded.contains{$0.tick==4320 && $0.pad==0})
        #expect(expanded.allSatisfy{$0.tick+$0.duration<=5760})
        let midi=try PerformanceTimeline.midi(take);#expect(midi.prefix(4)==Data("MThd".utf8));#expect(midi.contains(0xb0))
        var invalid=take;invalid.events[1].frame=1;#expect(throws:MusicError.self){try invalid.validate()}
    }
    @Test func fullLengthTakeAllowsRoundedFractionalFrameLimit()throws {
        var p=Project.demo();p.bpm=123
        let frames=UInt64((Double(64*barTicks)/Double(ppq)*60/p.bpm*44100).rounded())
        var take=PerformanceTake(source:p,sampleRate:44100,durationFrames:frames,events:[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id)])
        try take.validate();take.durationFrames+=1;#expect(throws:MusicError.self){try take.validate()}
    }
    @Test func frozenTakeRoundTripsAndRejectsInvalidActions()throws {
        var p=Project.demo()
        let events=[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id),PerformanceEvent(frame:24000,kind:.filter,value:-0.5),PerformanceEvent(frame:48000,kind:.repeatSize,value:480),PerformanceEvent(frame:72000,kind:.repeatSize,value:0)]
        let take=PerformanceTake(source:p,sampleRate:48000,durationFrames:96000,events:events)
        try take.validate();p.performanceTake=take;try p.validate()
        #expect(try PortableProject.decode(PortableProject.data(p),asCopy:false)==p)
        #expect(take.source.performanceTake==nil);#expect(take.source.patterns==p.patterns)
        var invalid=take;invalid.events[0].sectionID=UUID();#expect(throws:MusicError.self){try invalid.validate()}
        invalid=take;invalid.events[1].value = .nan;#expect(throws:MusicError.self){try invalid.validate()}
        invalid=take;invalid.events[2].frame=100000;#expect(throws:MusicError.self){try invalid.validate()}
        invalid=take;invalid.source.performanceTake=take;#expect(throws:MusicError.self){try invalid.validate()}
        invalid=take;invalid.events[2].value=3840;#expect(throws:MusicError.self){try invalid.validate()}
    }
    @Test func masterEffectsAreSharedByMixAndExcludedFromStems()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        var p=Project(name:"Effects",bars:1);p.patterns[0].chords=[ChordEvent(tick:0,duration:960,chord:Chord())]
        let settings=WAVSettings(sampleRate:48000,bitDepth:24,tailSeconds:1,dither:false)
        let dryURL=folder.appendingPathComponent("dry.wav"),lowURL=folder.appendingPathComponent("low.wav"),wetURL=folder.appendingPathComponent("wet.wav")
        let dry=try await OfflineRenderer.render(p,to:dryURL,settings:settings)
        p.masterFX=MasterFX(filter:-1);let low=try await OfflineRenderer.render(p,to:lowURL,settings:settings)
        #expect(low.peak<dry.peak*0.1)
        p.masterFX=MasterFX(delayWet:0.5);let wet=try await OfflineRenderer.render(p,to:wetURL,settings:settings)
        #expect(wet.frames==dry.frames);#expect(try Data(contentsOf:wetURL) != Data(contentsOf:dryURL))
        let stemURL=folder.appendingPathComponent("stem.wav"),controlURL=folder.appendingPathComponent("control.wav")
        _ = try await OfflineRenderer.render(p,to:stemURL,settings:settings,isolatedTrack:p.tracks[0].id)
        p.masterFX=nil;_ = try await OfflineRenderer.render(p,to:controlURL,settings:settings,isolatedTrack:p.tracks[0].id)
        #expect(try Data(contentsOf:stemURL)==Data(contentsOf:controlURL))
    }
    @Test func versionFourProjectsMigrateWithoutEffectsOrTakes()throws {
        var p=Project.demo();p.schemaVersion=4
        let migrated=try ProjectDocument.decode(JSONEncoder().encode(p))
        #expect(migrated.schemaVersion==Project.currentSchemaVersion);#expect(migrated.masterFX==nil);#expect(migrated.performanceTake==nil)
        var invalid=migrated;invalid.masterFX=MasterFX(filter:2);#expect(throws:MusicError.self){try invalid.validate()}
    }
    @Test func finitePerformanceWAVUsesTheCapturedTimelineAndCanResample()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let source=Project.demo(),section=source.sections[0]
        let take=PerformanceTake(source:source,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:section.id),PerformanceEvent(frame:24000,kind:.filter,value:-0.5),PerformanceEvent(frame:30000,kind:.pad,value:110,track:1,pad:0)])
        let first=folder.appendingPathComponent("first.wav"),second=folder.appendingPathComponent("second.wav")
        let receipt=try await OfflineRenderer.renderPerformance(take,to:first,settings:WAVSettings(sampleRate:48000,bitDepth:24,tailSeconds:0,dither:false))
        #expect(receipt.frames==48000);#expect(receipt.peak>0.01)
        if let path=ProcessInfo.processInfo.environment["GRILLA_EXPORT_FIXTURES"] {
            let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try Data(contentsOf:first).write(to:dir.appendingPathComponent("performance.wav"))
            try PerformanceTimeline.midi(take).write(to:dir.appendingPathComponent("performance.mid"))
        }
        _ = try await OfflineRenderer.renderPerformance(take,to:second,settings:WAVSettings(sampleRate:48000,bitDepth:24,tailSeconds:0,dither:false))
        #expect(try Data(contentsOf:first)==Data(contentsOf:second))
        let alternate=try await OfflineRenderer.renderPerformance(take,to:second,settings:WAVSettings(sampleRate:44100,bitDepth:16,tailSeconds:0.5,dither:false))
        #expect(alternate.frames==66150)
        let raw=try PerformanceCodec.kernelEvents(take,targetRate:44100)
        #expect(raw[1].frame==22050);#expect(raw[0].a==section.start);#expect(raw[0].b==section.length)
    }
}
