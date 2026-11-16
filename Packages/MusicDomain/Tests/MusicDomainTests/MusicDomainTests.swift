import Testing
import Foundation
@testable import MusicDomain
struct MusicDomainTests {
    @Test func exactReferenceNotes() throws {
        let p=Project.demo();try p.validate();let notes=Compiler.notes(p)
        #expect(notes.filter{$0.track==0&&$0.tick==0}.map(\.pitch).sorted()==[60,64,67])
        #expect(notes.filter{$0.track==0&&$0.tick==3840}.map(\.pitch).sorted()==[57,60,64])
        #expect(notes.filter{$0.track==0&&$0.tick==7680}.map(\.pitch).sorted()==[53,57,60])
        #expect(notes.filter{$0.track==0&&$0.tick==11520}.map(\.pitch).sorted()==[55,59,62])
        #expect(notes.filter{$0.track==2}.map(\.pitch)==[36,33,29,31])
        #expect(notes.filter{$0.pad>=0}.count==48)
        #expect(notes.allSatisfy{$0.tick+$0.duration<=15360})
    }
    @Test func chordVocabularyAndParser() throws {
        for root in 0..<12 {for quality in Quality.allCases {let c=Chord(root:root,quality:quality);var written=c;written.rootSpelling=Chord.roots[root];#expect(try Chord.parse(c.symbol)==written);for inversion in 0..<quality.intervals.count {let n=Chord(root:root,quality:quality,inversion:inversion).notes;#expect(n==n.sorted());#expect(n.count==quality.intervals.count)}}}
        #expect(try Chord.parse("Dbm7").root==1)
        #expect(throws:MusicError.self){try Chord.parse("Cmaj15")}
        #expect(throws:MusicError.self){try Chord.parse("C nonsense")}
        #expect(Chord(root:0,quality:.m7b5).notes==[60,63,66,70])
    }
    @Test func quantizationBoundaries(){#expect(Quantize.sixteenth.tick(15359,length:15360)==0);#expect(Quantize.eighth.tick(244,length:15360)==480);#expect(Quantize.off.tick(15359,length:15360)==15359)}
    @Test func invalidCommandIsAtomic() throws {
        var p=Project.demo();let before=p;var h=History()
        #expect(throws:MusicError.self){try h.apply(&p){$0.bpm=300}}
        #expect(p==before);#expect(!h.canUndo)
        try h.apply(&p){$0.patterns[0].chords[0].chord=Chord(root:2)}
        h.undo(&p);#expect(p.patterns==before.patterns);#expect(p.revision==2)
        h.redo(&p);#expect(p.patterns[0].chords[0].chord.root==2);#expect(p.revision==3)
    }
    @Test func duplicatedSectionsAreIndependent() throws {
        var p=Project.demo();try p.duplicateSection(p.sections[0].id,name:"Chorus");try p.validate()
        #expect(p.length==30720);#expect(p.patterns.count==4)
        p.patterns[2].chords[0].chord.root=2
        #expect(p.patterns[0].chords[0].chord.root==0)
        let chorus=p.sections[1].id;try p.moveSection(chorus,by:-1);try p.validate()
        #expect(p.sections[0].id==chorus);#expect(Compiler.notes(p).filter{$0.track==0&&$0.tick==0}.map(\.pitch).sorted()==[50,54,57])
    }
    @Test func sectionDeletionRipplesAndUndoIsAtomic() throws {
        var p=Project.demo(); var h=History()
        try h.apply(&p){try $0.duplicateSection($0.sections[0].id,name:"Chorus")}
        let before=p
        try h.apply(&p){try $0.deleteSection($0.sections[0].id)}
        try p.validate(); #expect(p.sections.count==1); #expect(p.sections[0].start==0); #expect(p.patterns.count==2)
        h.undo(&p); #expect(p.patterns==before.patterns); #expect(p.sections==before.sections)
    }
    @Test func faderGestureIsOneUndo() throws {
        var p=Project.demo(); let initial=p; var h=History()
        try h.apply(&p){$0.master = -10}
        try h.apply(&p,coalescing:true){$0.master = -15}
        h.undo(&p); #expect(p.master==initial.master); #expect(!h.canUndo)
    }
    @Test func corruptLargeTicksCannotOverflow() {
        var p=Project.demo();p.patterns[0].chords[0].tick=Int.max
        #expect(throws:MusicError.self){try p.validate()}
        p=Project.demo();p.sections[0].length=Int.max;p.sections.append(MusicDomain.Section(name:"Corrupt",length:Int.max))
        #expect(throws:MusicError.self){try p.validate()}
    }
    @Test func invalidReferencesAndRangesRejected() {
        var p=Project.demo();p.tracks[0].clips[0].patternID=UUID();#expect(throws:MusicError.self){try p.validate()}
        p=Project.demo();p.sections[0].start=1;#expect(throws:MusicError.self){try p.validate()}
        p=Project.demo();p.patterns[1].drums[0].velocity=0;#expect(throws:MusicError.self){try p.validate()}
        p=Project.demo();p.schemaVersion=99;#expect(throws:MusicError.self){try p.validate()}
    }
    @Test func rangeClipsAndRebases() {
        let p=Project.demo();let notes=Compiler.notes(p,range:1000..<5000)
        #expect(notes.allSatisfy{$0.tick>=0&&$0.tick+$0.duration<=4000})
        #expect(notes.contains{$0.pitch==60&&$0.tick==0&&$0.duration==2840})
    }
    @Test func midiRoundTrip() throws {
        let p=Project.demo();let data=try MIDIExporter.data(p);let bytes=[UInt8](data)
        #expect(String(bytes:bytes[0..<4],encoding:.utf8)=="MThd")
        #expect(Array(bytes[8..<14])==[0,1,0,4,3,192])
        var cursor=14;var noteOns:[(Int,Int,Int)]=[];var track=0
        func number(_ count:Int)->Int{var n=0;for _ in 0..<count{n=n*256+Int(bytes[cursor]);cursor+=1};return n}
        func vlq()->Int{var n=0;while true{let b=bytes[cursor];cursor+=1;n=n*128+Int(b&127);if b&128==0{return n}}}
        while cursor<bytes.count{
            #expect(String(bytes:bytes[cursor..<cursor+4],encoding:.utf8)=="MTrk");cursor+=4
            let length=number(4);let end=cursor+length;var tick=0;var ended=false
            while cursor<end{
                tick+=vlq();let status=bytes[cursor];cursor+=1
                if status==255 {let type=bytes[cursor];cursor+=1;let len=vlq();if type==47{#expect(tick==p.length);ended=true};cursor+=len}
                else{let pitch=Int(bytes[cursor]);let velocity=Int(bytes[cursor+1]);cursor+=2;if status&240==144 && velocity>0{noteOns.append((track,tick,pitch))};if track==2{#expect(status&15==9)}}
            }
            #expect(ended);track+=1
        }
        #expect(noteOns.count==Compiler.notes(p).count)
        #expect(noteOns.contains{$0.0==1&&$0.1==3840&&$0.2==57})
    }
    @Test func midiKeySignatureMatchesDisplayedSpelling() throws {
        var p=Project.demo();p.keyRoot=1
        let sharp=Array(try MIDIExporter.data(p))
        #expect((0...sharp.count-5).contains{Array(sharp[$0..<$0+5])==[255,89,2,7,0]})
        p.keyRoot=10;p.minor=true
        let flat=Array(try MIDIExporter.data(p))
        #expect((0...flat.count-5).contains{Array(flat[$0..<$0+5])==[255,89,2,251,1]})
    }
    @Test func staleSavesAndNewerSchemaNeverOverwriteNewerData() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ProjectStore(root:root);var p=Project.demo();let old=p
        p.revision=2;p.name="Newest";try await store.save(p)
        #expect(try await store.save(old)==2)
        #expect(try await store.load(p.id).name=="Newest")
        let manifest=root.appendingPathComponent(p.id.uuidString+".grilla/manifest.json")
        p.schemaVersion=99;let future=try JSONEncoder().encode(p);try future.write(to:manifest)
        do {try await store.save(old);Issue.record("A newer schema was overwritten")} catch {}
        #expect(try Data(contentsOf:manifest)==future)
    }
    @Test func persistenceRecoveryAndNewerSchema() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ProjectStore(root:root);var p=Project.demo();try await store.save(p);p.name="Second";p.revision=1;try await store.save(p)
        #expect(try await store.load(p.id).name=="Second")
        let manifest=root.appendingPathComponent(p.id.uuidString+".grilla/manifest.json")
        try Data("broken".utf8).write(to:manifest)
        let entries=try await store.list();#expect(entries.count==1);#expect(entries[0].project==nil)
        #expect(try await store.load(p.id,backup:true).name=="First light")
        p.schemaVersion=99;#expect(throws:MusicError.self){try p.validate()}
    }
}
