import Foundation
import Testing
@testable import MusicDomain

struct MIDITests {
    @Test func sustainedInputIsFiniteAndRetainsItsInstrumentInTakeExports()async throws {
        let p=Project.demo()
        let events=[PerformanceEvent(frame:0,kind:.section,sectionID:p.sections[0].id),PerformanceEvent(frame:100,kind:.midiNoteOn,track:0,note:NoteEvent(tick:0,duration:1,pitch:72,velocity:108),instrument:0,midiKey:17),PerformanceEvent(frame:4800,kind:.midiSustain,value:1,midiKey:17),PerformanceEvent(frame:9600,kind:.midiNoteOff,track:0,note:NoteEvent(tick:0,duration:1,pitch:72,velocity:1),instrument:0,midiKey:17),PerformanceEvent(frame:24000,kind:.midiSustain,value:0,midiKey:17)]
        let take=PerformanceTake(source:p,sampleRate:48000,durationFrames:48000,events:events)
        try take.validate();let notes=try PerformanceTimeline.backingNotes(take)
        let note=try #require(notes.first{$0.pitch==72 && $0.velocity==108})
        #expect(note.tick==4);#expect(note.duration==956);#expect(note.instrument==0)
        let raw=try PerformanceCodec.kernelEvents(take,targetRate:44100)
        #expect(raw[1].b==17);#expect(raw[1].kind==10);#expect(raw[1].value==108)
        #expect(try PerformanceCodec.event(raw[1],source:p).midiKey==17)
        #expect(try PerformanceTimeline.midi(take).count>100)
        var old=p;old.schemaVersion=5;var frozen=take;frozen.source=old;old.performanceTake=frozen
        let migrated=try ProjectDocument.decode(JSONEncoder().encode(old));#expect(migrated.schemaVersion==6);#expect(migrated.performanceTake?.source.schemaVersion==6)
    }
    @Test func mappingsUseStableSourcesAndProtectSustainAndChannelMode()throws {
        let p=Project.demo();var settings=MIDISettings();settings.inputIDs=[123,456];settings.trackID=p.tracks[0].id
        let gain=MIDIMapping(sourceID:123,channel:0,controller:7,target:.trackGain,trackID:p.tracks[0].id)
        settings.mappings=[gain];try settings.validate(p)
        #expect(settings.mapping(sourceID:123,channel:0,controller:7)==gain)
        #expect(settings.mapping(sourceID:456,channel:0,controller:7)==nil)
        #expect(gain.value(0)==(-61));#expect(gain.value(127)==6)
        let filter=MIDIMapping(sourceID:123,channel:0,controller:74,target:.filter);#expect(filter.value(64)==0);#expect(filter.value(0)==(-1));#expect(filter.value(127)==1)
        for cc in [64,120,123,127]{var invalid=gain;invalid.controller=cc;#expect(throws:MusicError.self){try invalid.validate(p)}}
        settings.mappings.append(gain);#expect(throws:MusicError.self){try settings.validate(p)}
        settings.mappings=[gain];settings.inputIDs=[123,123];#expect(throws:MusicError.self){try settings.validate(p)}
    }
}
