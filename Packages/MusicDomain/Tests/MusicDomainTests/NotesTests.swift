import Foundation
import Testing
@testable import MusicDomain

struct NotesTests {
    @Test func versionOneMigrationPreservesSourceAndBackup() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        var p=Project.demo();p.schemaVersion=1
        var json=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
        json["patterns"]=(json["patterns"] as! [[String:Any]]).map{entry in var v=entry;v.removeValue(forKey:"notes");return v}
        let old=try JSONSerialization.data(withJSONObject:json,options:.sortedKeys)
        let folder=root.appendingPathComponent(p.id.uuidString+".grilla");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let manifest=folder.appendingPathComponent("manifest.json");try old.write(to:manifest)
        let store=ProjectStore(root:root);var migrated=try await store.load(p.id)
        #expect(migrated.schemaVersion==2);#expect(migrated.patterns.allSatisfy{$0.notes==[]})
        #expect(try Data(contentsOf:manifest)==old)
        #expect(Compiler.notes(migrated)==Compiler.notes(Project.demo()))
        migrated.revision+=1;try await store.save(migrated)
        #expect(try Data(contentsOf:folder.appendingPathComponent("backup.json"))==old)
        #expect(try await store.load(p.id,backup:true).schemaVersion==2)
    }
    @Test func eightTracksHaveIndependentPatternsAndRouting() throws {
        var p=Project.demo()
        for i in 0..<5{try p.addMelody(name:"Lead \(i)");let pid=p.tracks.last!.clips[0].patternID;let j=p.patterns.firstIndex{$0.id==pid}!;p.patterns[j].notes=[NoteEvent(tick:240,duration:960,pitch:72+i,velocity:80+i)]}
        try p.validate();#expect(p.tracks.count==8)
        for i in 3..<8{let notes=Compiler.notes(p).filter{$0.track==i};#expect(notes.count==1);#expect(notes[0].pitch==69+i);#expect(notes[0].instrument==3)}
        let before=p
        #expect(throws:MusicError.self){try p.addMelody()};#expect(p==before)
        try p.deleteTrack(p.tracks[3].id);try p.validate();#expect(p.tracks.count==7)
        #expect(Compiler.notes(p).contains{$0.track==3 && $0.pitch==73})
        #expect(throws:MusicError.self){try p.deleteTrack(p.tracks[0].id)}
    }
    @Test func noteEditsAreAtomicBoundedAndUndoable() throws {
        var p=Project(name:"Notes",bars:1);try p.addMelody();var history=History();let index=2
        try history.apply(&p){try NoteEditing.insert(NoteEvent(tick:3700,duration:480,pitch:72),into:&$0.patterns[index])}
        let n=try #require(p.patterns[index].notes?.first);#expect(n.tick==3360)
        try history.apply(&p){NoteEditing.move(n.id,in:&$0.patterns[index],tick:510,pitch:75,step:240)}
        #expect(p.patterns[index].notes?[0].tick==480);#expect(p.patterns[index].notes?[0].pitch==75)
        try history.apply(&p){NoteEditing.resize(n.id,in:&$0.patterns[index],duration:Int.max)}
        #expect(p.patterns[index].notes?[0].duration==3360)
        history.undo(&p);#expect(p.patterns[index].notes?[0].duration==480)
        history.redo(&p);#expect(p.patterns[index].notes?[0].duration==3360)
        let before=p
        #expect(throws:MusicError.self){try history.apply(&p){$0.patterns[index].notes?[0].velocity=0}}
        #expect(p==before)
        try history.apply(&p){try NoteEditing.duplicate(n.id,in:&$0.patterns[index])}
        #expect(p.patterns[index].notes?.count==2);#expect(p.patterns[index].notes?[0].id != p.patterns[index].notes?[1].id)
    }
    @Test func melodyCopiesAndSectionOperationsKeepIDsIndependent() throws {
        var p=Project.demo();try p.addMelody();p.patterns[2].notes=[NoteEvent(tick:240,pitch:74)]
        try p.duplicateTrack(p.tracks[3].id);try p.validate()
        #expect(p.patterns[2].notes?[0].id != p.patterns[3].notes?[0].id)
        p.patterns[3].notes?[0].pitch=78;#expect(p.patterns[2].notes?[0].pitch==74)
        try p.duplicateSection(p.sections[0].id,name:"Chorus");try p.validate()
        let chorus=Compiler.notes(p,range:15360..<30720).filter{$0.instrument==3}
        #expect(chorus.map(\.pitch).sorted()==[74,78])
        try p.deleteSection(p.sections[0].id);try p.validate()
        #expect(Compiler.notes(p).filter{$0.instrument==3}.map(\.pitch).sorted()==[74,78])
    }
    @Test func repeatingAndOffsetMelodyClipsChaseAndRebase() throws {
        var p=Project(name:"Repeat",bars:2);try p.addMelody()
        p.patterns[2].length=barTicks;p.patterns[2].notes=[NoteEvent(tick:0,duration:1920,pitch:72)]
        p.tracks[2].clips[0].offset=960
        try p.validate();let notes=Compiler.notes(p).filter{$0.track==2}
        #expect(notes.map(\.tick)==[0,2880,6720]);#expect(notes.map(\.duration)==[960,1920,960])
        let range=Compiler.notes(p,range:1000..<5000).filter{$0.track==2}
        #expect(range.map(\.tick)==[1880]);#expect(range[0].duration==1920)
        try p.duplicateSection(p.sections[0].id,name:"Copy");try p.validate()
        #expect(p.tracks[2].clips[1].offset==960)
    }
    @Test func midiMelodiesUseDistinctNonDrumChannels() throws {
        var p=Project(name:"Eight",bars:1)
        for i in 0..<6{try p.addMelody();p.patterns[i+2].notes=[NoteEvent(tick:0,pitch:70+i)]}
        let bytes=[UInt8](try MIDIExporter.data(p));var cursor=14;var channels:[Int]=[]
        func read(_ count:Int)->Int{var n=0;for _ in 0..<count{n=n*256+Int(bytes[cursor]);cursor+=1};return n}
        func vlq()->Int{var n=0;while true{let b=bytes[cursor];cursor+=1;n=n*128+Int(b&127);if b<128{return n}}}
        while cursor<bytes.count{cursor+=4;let size=read(4);let end=cursor+size
            while cursor<end{_ = vlq();let status=bytes[cursor];cursor+=1;if status==255{cursor+=1;let size=vlq();cursor+=size}else{if status&240==144{channels.append(Int(status&15))};cursor+=2}}
        }
        #expect(channels==[2,3,4,5,6,7])
    }
    @Test func portableNotesAndOfflineEighthTrackSurviveRoundTrip() async throws {
        var p=Project(name:"Eighth",bars:1)
        for _ in 0..<6{try p.addMelody()};p.patterns[7].notes=[NoteEvent(tick:240,duration:1920,pitch:76,velocity:94)]
        let copy=try PortableProject.decode(PortableProject.data(p),asCopy:false);#expect(copy==p)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".wav")
        defer{try? FileManager.default.removeItem(at:url)}
        let settings=WAVSettings(sampleRate:48000,bitDepth:24,tailSeconds:0,dither:false)
        let receipt=try await OfflineRenderer.render(copy,to:url,settings:settings)
        #expect(receipt.frames==96000);#expect(receipt.peak>0.005)
        p.tracks[7].mute=true;let muted=try await OfflineRenderer.render(p,to:url,settings:settings)
        #expect(muted.peak==0)
    }
}
