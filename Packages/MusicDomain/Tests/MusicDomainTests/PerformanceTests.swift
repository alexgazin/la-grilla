import Foundation
import Testing
@testable import MusicDomain

struct PerformanceTests {
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
        #expect(migrated.schemaVersion==5);#expect(migrated.masterFX==nil);#expect(migrated.performanceTake==nil)
        var invalid=migrated;invalid.masterFX=MasterFX(filter:2);#expect(throws:MusicError.self){try invalid.validate()}
    }
}
