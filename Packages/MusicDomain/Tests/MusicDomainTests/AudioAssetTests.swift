import Foundation
import Testing
@testable import MusicDomain

struct AudioAssetTests {
    static func source()->(Data,AudioAssetRecord) {
        var data=Data("caff".utf8)
        func big<T:FixedWidthInteger>(_ value:T){var v=value.bigEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        big(UInt16(1));big(UInt16(0));data.append(contentsOf:"desc".utf8);big(UInt64(32));big(Double(48000).bitPattern);data.append(contentsOf:"lpcm".utf8);big(UInt32(3));big(UInt32(4));big(UInt32(1));big(UInt32(1));big(UInt32(32))
        let samples=(0..<9600).map{Float(sin(Double($0)*2*Double.pi*220/48000)*0.5)}
        data.append(contentsOf:"data".utf8);big(UInt64(samples.count*4+4));big(UInt32(0))
        for sample in samples{data.little(sample.bitPattern)}
        return (data,AudioAssetRecord(sha256:try! AssetIntegrity.sha256(data),byteCount:data.count,sampleRate:48000,duration:0.2,origin:.syntheticFixture))
    }
    @Test func sha256MatchesPublishedKnownVectors()throws {
        #expect(try AssetIntegrity.sha256(Data())=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(try AssetIntegrity.sha256(Data("abc".utf8))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(try AssetIntegrity.sha256(Data(repeating:97,count:1_000_000))=="cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
    @Test func sourceRecordingsSurvivePackageCopyExportImportAndBackup()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),store=ProjectStore(root:root)
        defer{try? FileManager.default.removeItem(at:root)}
        let (data,record)=Self.source();try AssetIntegrity.validate(data,record:record)
        var p=Project.demo();try p.addMelody();p.audioAssets=[record];p.tracks[3].clips[0].sourceAssetID=record.id;p.patterns[2].notes=[NoteEvent(tick:0,pitch:57,confidence:0.95)]
        try await store.writeAsset(data,record:record,projectID:p.id);try await store.save(p)
        let copy=try await store.duplicate(p)
        #expect(copy.id != p.id);#expect(copy.audioAssets==p.audioAssets)
        #expect(try Data(contentsOf:await store.assetURL(record,projectID:copy.id))==data)
        let zip=root.appendingPathComponent("source.grillapack");try await store.portable(p,to:zip)
        let bundle=try PortableProject.decodeBundle(Data(contentsOf:zip));#expect(bundle.project.id != p.id);#expect(bundle.assets[record.relativePath]==data)
        let installed=try await store.install(bundle);let loaded=try await store.load(installed.id)
        #expect(loaded.patterns==p.patterns);#expect(loaded.tracks==p.tracks)
        #expect(try Data(contentsOf:await store.assetURL(record,projectID:loaded.id))==data)
        p.revision+=1;p.name="Changed";try await store.save(p)
        let backup=try await store.load(p.id,backup:true);let recovered=try await store.duplicate(backup,suffix:" recovered")
        #expect(try Data(contentsOf:await store.assetURL(record,projectID:recovered.id))==data)
        if let path=ProcessInfo.processInfo.environment["GRILLA_VOICE_FIXTURES"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try Data(contentsOf:zip).write(to:folder.appendingPathComponent("voice-source.grillapack"))}
    }
    @Test func validZipCRCCannotHideADamagedSourceRecording()throws {
        let (data,record)=Self.source();var p=Project.demo();p.audioAssets=[record]
        let archive=try PortableProject.data(p,assets:[record.relativePath:data])
        var entries=try ProjectArchive.decode(archive);let i=entries.firstIndex{$0.name==record.relativePath}!
        entries[i].data[entries[i].data.count-1] ^= 1
        let repacked=try ProjectArchive.encode(entries)
        #expect(throws:ExportError.self){try PortableProject.decodeBundle(repacked)}
        #expect(throws:ExportError.self){try PortableProject.data(p)}
        var invalid=record;invalid.duration=20;#expect(throws:ExportError.self){try AssetIntegrity.validate(data,record:invalid)}
    }
    @Test func missingSourceFilesNeverProduceAnIncompletePortableProject()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),store=ProjectStore(root:root)
        defer{try? FileManager.default.removeItem(at:root)}
        let (_,record)=Self.source();var p=Project.demo();p.audioAssets=[record];try await store.save(p)
        do{try await store.portable(p,to:root.appendingPathComponent("bad.grillapack"));Issue.record("Missing source was silently omitted")}catch{}
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("bad.grillapack").path))
    }
    @Test func voicePlacementIsScopedAndUndoPreservesTheOriginal()throws {
        var p=Project.demo();try p.duplicateSection(p.sections[0].id,name:"Chorus");try p.addMelody()
        let (_,record)=Self.source();let original=p;var history=History()
        let section=p.sections[1],before=Compiler.notes(p,range:0..<section.start)
        let placement=try Arrangement.voiceCandidate(p,sectionID:section.id,target:p.tracks[3].id,notes:[NoteEvent(tick:240,pitch:74,confidence:0.91)],source:record)
        #expect(p==original);#expect(Compiler.notes(placement.project,range:0..<section.start)==before)
        #expect(placement.project.audioAssets==[record]);#expect(placement.project.tracks[3].clips.last?.sourceAssetID==record.id)
        try history.apply(&p){$0=placement.project};history.undo(&p);#expect(p.patterns==original.patterns);#expect(p.audioAssets==nil)
        history.redo(&p);#expect(p.audioAssets==[record]);try p.validate()
    }
    @Test func redundantAutosaveKeepsThePreviousWorkingBackup()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),store=ProjectStore(root:root)
        defer{try? FileManager.default.removeItem(at:root)}
        var p=Project.demo();try await store.save(p);p.name="New name";p.revision=1;try await store.save(p);try await store.save(p)
        #expect(try await store.load(p.id,backup:true).name=="First light")
    }
}
