import Foundation
import Testing
@testable import MusicDomain

struct StudioEQTests {
    @Test func peakAndBypassUseTheSameResponseAsTheRenderer() throws {
        var eq=StudioEQ()
        eq.bands[1]=EQBand(.bell,1000,6,1.25)
        for rate in [44_100.0,48_000.0,96_000.0] {
            let response=eq.response(at:[1000],rate:rate)
            #expect(abs(response[0]-6)<0.001)
        }
        eq.enabled=false
        #expect(eq.response(at:[100,1000,12000],rate:48000)==[0,0,0])
    }

    @Test func masterDoesNotLeakIntoTheStemRoutingTable() throws {
        var project=Project.demo()
        var eq=StudioEQ()
        eq.bands[1]=EQBand(.bell,800,4)
        project.tracks[0].equalizer=eq
        project.masterEQ=eq
        let stem=project.equalizerBands(includeMaster:false)
        #expect(stem[1].gainDB==4)
        #expect(stem[masterBus*4+1].kind==0)
        let saved=try ProjectDocument.decode(JSONEncoder().encode(project))
        #expect(saved.masterEQ==eq && saved.tracks[0].equalizer==eq)
    }

    @Test func legacyMixesStartWithBypassedEqualizers() throws {
        var legacy=Project.demo()
        legacy.schemaVersion=12
        let restored=try ProjectDocument.decode(JSONEncoder().encode(legacy))
        #expect(restored.equalizerBands().allSatisfy{$0.kind==0})
    }
}
