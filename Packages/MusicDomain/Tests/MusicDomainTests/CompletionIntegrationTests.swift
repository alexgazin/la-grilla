import Foundation
import Testing
@testable import MusicDomain

/// One short studio journey crosses the new feature boundaries and then checks
/// the files a musician actually takes out of the app, using independent readers.
struct CompletionIntegrationTests {
    private struct ScoreNote:Equatable {
        var track:Int;var channel:Int;var tick:Int;var duration:Int;var pitch:Int;var velocity:Int
        var key:[Int]{[track,tick,pitch,duration,velocity,channel]}
    }
    private struct MIDIRead {var notes:[ScoreNote]=[];var tempo=0;var markers:[String]=[]}
    private enum InvalidFixture:Error {case malformedMIDI,malformedWAV}
    private struct MIDIReader {
        let bytes:[UInt8];var cursor=0
        mutating func integer(_ count:Int)throws->Int {
            guard count>=0,cursor<=bytes.count-count else{throw InvalidFixture.malformedMIDI}
            var value=0;for _ in 0..<count{value=(value<<8)|Int(bytes[cursor]);cursor+=1};return value
        }
        mutating func variable()throws->Int {
            var value=0;for _ in 0..<4{let byte=try integer(1);value=(value<<7)|(byte&127);if byte&128==0{return value}}
            throw InvalidFixture.malformedMIDI
        }
        mutating func data(_ count:Int)throws->[UInt8] {
            guard count>=0,cursor<=bytes.count-count else{throw InvalidFixture.malformedMIDI}
            defer{cursor+=count};return Array(bytes[cursor..<cursor+count])
        }
    }
    /// Reads delta times and pairs NoteOn/Off rather than comparing SMF bytes or
    /// invoking the production compiler as its own correctness reference.
    private func readMIDI(_ data:Data)throws->MIDIRead {
        var file=MIDIReader(bytes:Array(data));var result=MIDIRead()
        guard try file.data(4)==Array("MThd".utf8),try file.integer(4)==6,try file.integer(2)==1 else{throw InvalidFixture.malformedMIDI}
        let tracks=try file.integer(2);guard try file.integer(2)==960 else{throw InvalidFixture.malformedMIDI}
        for track in 0..<tracks {
            guard try file.data(4)==Array("MTrk".utf8) else{throw InvalidFixture.malformedMIDI}
            let length=try file.integer(4);var reader=MIDIReader(bytes:try file.data(length))
            var tick=0,running=0;var held:[Int:(tick:Int,velocity:Int)]=[:]
            while reader.cursor<reader.bytes.count {
                tick+=try reader.variable();var status=try reader.integer(1)
                if status<128{guard running>=128 else{throw InvalidFixture.malformedMIDI};reader.cursor-=1;status=running}
                if status==255 {
                    let kind=try reader.integer(1),size=try reader.variable(),payload=try reader.data(size)
                    if kind==0x51{guard size==3 else{throw InvalidFixture.malformedMIDI};result.tempo=payload.reduce(0){($0<<8)|Int($1)}}
                    if kind==6{result.markers.append(String(decoding:payload,as:UTF8.self))}
                    if kind==0x2f{guard size==0,reader.cursor==reader.bytes.count else{throw InvalidFixture.malformedMIDI};break}
                    continue
                }
                if status==0xf0 || status==0xf7{let size=try reader.variable();_ = try reader.data(size);running=0;continue}
                guard (0x80..<0xf0).contains(status) else{throw InvalidFixture.malformedMIDI}
                running=status;let a=try reader.integer(1),b=try (status&0xe0==0xc0 ? 0:reader.integer(1))
                let channel=status&15,key=channel*128+a
                if status&0xf0==0x90 && b>0 {
                    guard held[key]==nil else{throw InvalidFixture.malformedMIDI};held[key]=(tick,b)
                }else if status&0xf0==0x80 || (status&0xf0==0x90 && b==0) {
                    guard let on=held.removeValue(forKey:key),tick>on.tick else{throw InvalidFixture.malformedMIDI}
                    result.notes.append(ScoreNote(track:track-1,channel:channel,tick:on.tick,duration:tick-on.tick,pitch:a,velocity:on.velocity))
                }
            }
            guard held.isEmpty else{throw InvalidFixture.malformedMIDI}
        }
        guard file.cursor==file.bytes.count else{throw InvalidFixture.malformedMIDI}
        result.notes.sort{$0.key.lexicographicallyPrecedes($1.key)};return result
    }
    private struct WaveRead {let frames:Int;let samples:[Int]}
    private func readWave(_ data:Data)throws->WaveRead {
        let bytes=Array(data)
        func number(_ start:Int,_ count:Int)->Int{(0..<count).reduce(0){$0|Int(bytes[start+$1])<<($1*8)}}
        guard bytes.count>=44,String(decoding:bytes[0..<4],as:UTF8.self)=="RIFF",String(decoding:bytes[8..<12],as:UTF8.self)=="WAVE",number(4,4)==bytes.count-8 else{throw InvalidFixture.malformedWAV}
        var cursor=12,pcm:[UInt8]?;var validFormat=false
        while cursor+8<=bytes.count {
            let size=number(cursor+4,4),start=cursor+8;guard size<=bytes.count-start else{throw InvalidFixture.malformedWAV}
            switch String(decoding:bytes[cursor..<cursor+4],as:UTF8.self) {
            case "fmt ":guard size>=16 else{throw InvalidFixture.malformedWAV};validFormat=number(start,2)==1 && number(start+2,2)==2 && number(start+4,4)==48000 && number(start+14,2)==16
            case "data":pcm=Array(bytes[start..<start+size])
            default:break
            }
            cursor=start+size+(size&1)
        }
        guard validFormat,let pcm,pcm.count%4==0 else{throw InvalidFixture.malformedWAV}
        let samples=stride(from:0,to:pcm.count,by:2).map{Int(Int16(bitPattern:UInt16(pcm[$0])|UInt16(pcm[$0+1])<<8))}
        return WaveRead(frames:pcm.count/4,samples:samples)
    }

    private func editedSong()throws->Project {
        var p=Project(name:"Completion integration",bars:2);p.tracks.append(Track(role:.bass));try p.addMelody(name:"Lead");try p.addMelody(name:"Answer")
        p.patterns[1].drums=[DrumEvent(tick:0,pad:0,velocity:100),DrumEvent(tick:960,pad:1,velocity:80)]
        let leadPattern=p.tracks[3].clips[0].patternID,index=try #require(p.patterns.firstIndex{$0.id==leadPattern})
        p.patterns[index].notes=[NoteEvent(tick:240,duration:960,pitch:73,velocity:87),NoteEvent(tick:barTicks+480,duration:480,pitch:76,velocity:91)]
        p.bassGate=0.5;p.master=0
        for i in p.tracks.indices{p.tracks[i].gain = -18}
        p.tracks[1].mute=true;p.tracks[3].pan = -1;p.tracks[4].pan=1
        let plan=AssistantInterpretation(intent:.arrangeSong,changeTempo:true,bpm:240,sections:[
            .init(name:"A",bars:1,chordSymbols:["C{0,3,7,11,14}/E"],chordBars:[1],sourceSectionIndex:0),
            .init(name:"B",bars:1,chordSymbols:["D7(b9,#11)"],chordBars:[1],sourceSectionIndex:0)
        ])
        let proposal=try plan.proposal(for:p,selectedSectionID:p.sections[0].id)
        // Exercise the portable proposal review boundary before applying it.
        let reviewed=try AssistantProposal.decode(JSONEncoder().encode(proposal),for:p)
        try reviewed.apply(to:&p)
        let lead=p.tracks[3].id,answer=p.tracks[4].id,clip=p.tracks[3].clips[0].id
        try ClipEditing.move(.init(project:p,trackID:lead,clipID:clip),to:answer,start:0,in:&p)
        try ClipEditing.resize(.init(project:p,trackID:answer,clipID:clip),length:1920,snap:ppq,in:&p)
        try ClipEditing.setOffset(.init(project:p,trackID:answer,clipID:clip),offset:480,in:&p)
        try ClipEditing.copy(.init(project:p,trackID:answer,clipID:clip),to:lead,start:0,in:&p)
        let a=p.sections[0].id,b=p.sections[1].id
        try SectionEditing.duplicate(a,name:"A copy",in:&p)
        let copy=try #require(p.sections.first{$0.name=="A copy"})
        try ClipEditing.reorderSection(.init(project:p,sectionID:b),to:a,in:&p)
        try SectionEditing.delete(copy.id,in:&p)
        p.revision+=1;try p.validate();return p
    }
    private var expected:[ScoreNote] {
        var notes:[ScoreNote]=[]
        // The reviewed proposal voices D7(b9,#11) as D3 F#3 A3 C4 Eb4 Ab4
        // against the custom chord's E3 bass, retaining all six written tones.
        for (tick,pitches) in [(0,[50,54,57,60,63,68]),(barTicks,[52,60,63,67,71,74])] {
            notes+=pitches.map{ScoreNote(track:0,channel:0,tick:tick,duration:barTicks,pitch:$0,velocity:88)}
            notes.append(ScoreNote(track:2,channel:1,tick:tick,duration:1920,pitch:tick==0 ? 26:28,velocity:94))
            notes.append(ScoreNote(track:1,channel:9,tick:tick,duration:120,pitch:36,velocity:100))
            notes.append(ScoreNote(track:1,channel:9,tick:tick+960,duration:120,pitch:38,velocity:80))
        }
        notes.append(ScoreNote(track:3,channel:2,tick:240,duration:960,pitch:73,velocity:87))
        for track in [3,4]{notes.append(ScoreNote(track:track,channel:track-1,tick:barTicks,duration:720,pitch:73,velocity:87))}
        return notes.sorted{$0.key.lexicographicallyPrecedes($1.key)}
    }

    @Test func studioJourneyReopensWithTheSameMusicalMIDIAndAlignedRealAudio()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),store=ProjectStore(root:folder.appendingPathComponent("projects"))
        defer{try? FileManager.default.removeItem(at:folder)}
        let edited=try editedSong();try await store.save(edited)
        let reopened=try await store.load(edited.id)
        #expect(reopened.sections.map(\.name)==["B","A"]);#expect(reopened.length==2*barTicks)
        let archive=folder.appendingPathComponent("song.grillapack");try await store.portable(reopened,to:archive)
        let installed=try await store.install(PortableProject.decodeBundle(Data(contentsOf:archive))),portable=try await store.load(installed.id)
        #expect(portable.id != reopened.id)
        for project in [edited,reopened,portable] {
            let exported=try readMIDI(MIDIExporter.data(project))
            #expect(exported.tempo==250000);#expect(exported.markers==["B","A"])
            #expect(exported.notes==expected)
            let custom=Arrangement.harmony(project,section:project.sections[1]).first?.chord
            #expect(custom?.customIntervals==[0,3,7,11,14]);#expect(custom?.slashBass==4)
        }
        let settings=WAVSettings(sampleRate:48000,bitDepth:16,tailSeconds:0,dither:false)
        let before=try await OfflineRenderer.render(edited,to:folder.appendingPathComponent("before.wav"),settings:settings)
        let after=try await OfflineRenderer.render(portable,to:folder.appendingPathComponent("after.wav"),settings:settings)
        let mixedData=try Data(contentsOf:after.url),mixed=try readWave(mixedData)
        #expect(try Data(contentsOf:before.url)==mixedData);#expect(mixed.frames==96000)
        #expect(after.peak>0.001 && !after.clipped);#expect(mixed.samples.contains{$0 != 0})
        let stemsURL=try await StemExporter.render(portable,to:folder.appendingPathComponent("stems.zip"),settings:settings)
        let entries=try ProjectArchive.decode(Data(contentsOf:stemsURL)),waves=entries.filter{$0.name.hasSuffix(".wav")}.sorted{$0.name<$1.name}
        #expect(waves.count==5)
        var summed=[Int](repeating:0,count:mixed.samples.count)
        for (index,entry) in waves.enumerated() {
            let wave=try readWave(entry.data);#expect(wave.frames==mixed.frames)
            if index==1{#expect(wave.samples.allSatisfy{$0==0})}else{#expect(wave.samples.contains{$0 != 0})}
            for sample in summed.indices{summed[sample]+=wave.samples[sample]}
        }
        // With unity master and no clipping/FX, alignment is sample-exact; only
        // independent 16-bit quantization introduces a few units of rounding.
        #expect(zip(mixed.samples,summed).allSatisfy{abs($0-$1)<=5})
        let answer=try readWave(waves[4].data)
        #expect(answer.samples.prefix(48000*2).allSatisfy{$0==0})
        #expect(answer.samples.dropFirst(48000*2).contains{$0 != 0})
        if let path=ProcessInfo.processInfo.environment["GRILLA_EXPORT_FIXTURES"] {
            let destination=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            try MIDIExporter.data(portable).write(to:destination.appendingPathComponent("completion-integration.mid"))
            try mixedData.write(to:destination.appendingPathComponent("completion-integration.wav"))
            try Data(contentsOf:stemsURL).write(to:destination.appendingPathComponent("completion-integration-stems.zip"))
            try Data(contentsOf:archive).write(to:destination.appendingPathComponent("completion-integration.grillapack"))
        }
    }
}
