import Testing
import Foundation
@testable import MusicDomain
struct ExportTests {
    private func folder()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    private func number(_ data:Data,_ offset:Int,_ count:Int)->Int {(0..<count).reduce(0){$0 | Int(data[offset+$1]) << ($1*8)}}
    @Test func waveHeaderLengthAudioAndDeterminism() async throws {
        let root=folder();defer{try? FileManager.default.removeItem(at:root)}
        let settings=WAVSettings(sampleRate:44100,bitDepth:24,tailSeconds:0.25)
        let a=try await OfflineRenderer.render(Project.demo(),to:root.appendingPathComponent("a.wav"),settings:settings)
        let b=try await OfflineRenderer.render(Project.demo(),to:root.appendingPathComponent("b.wav"),settings:settings)
        let data=try Data(contentsOf:a.url)
        #expect(data == (try Data(contentsOf:b.url)));#expect(String(data:data.prefix(4),encoding:.utf8)=="RIFF")
        #expect(number(data,20,2)==1);#expect(number(data,22,2)==2);#expect(number(data,24,4)==44100);#expect(number(data,34,2)==24)
        #expect(a.frames==363825);#expect(data.count==44+a.frames*6);#expect(number(data,40,4)==a.frames*6);#expect(a.peak>0.01);#expect(!a.clipped)
        #expect(data.dropFirst(44).contains{$0 != 0})
        if let path=ProcessInfo.processInfo.environment["GRILLA_EXPORT_FIXTURES"] {
            let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try data.write(to:dir.appendingPathComponent("reference-44100-24.wav"))
            try PortableProject.data(Project.demo()).write(to:dir.appendingPathComponent("reference.grillapack"))
        }
    }
    @Test func oneShotTailSurvivesSongEnd() async throws {
        let root=folder();defer{try? FileManager.default.removeItem(at:root)}
        var p=Project(name:"Tail",bars:1);p.patterns[1].drums=[DrumEvent(tick:barTicks-120,pad:9)]
        let receipt=try await OfflineRenderer.render(p,to:root.appendingPathComponent("tail.wav"),settings:WAVSettings(sampleRate:48000,bitDepth:16,tailSeconds:0.5,dither:false))
        let data=try Data(contentsOf:receipt.url);let songEnd=44+96000*4
        #expect(data[songEnd...].contains{$0 != 0});#expect(receipt.frames==120000)
    }
    @Test func cancelledRenderLeavesNoPartialFile() async throws {
        let root=folder();let file=root.appendingPathComponent("cancelled.wav");defer{try? FileManager.default.removeItem(at:root)}
        let task=Task{try await OfflineRenderer.render(Project.demo(),to:file)};task.cancel()
        do{_ = try await task.value;Issue.record("Cancelled render completed")}catch is CancellationError{}catch{Issue.record("Wrong cancellation error: \(error)")}
        #expect(!FileManager.default.fileExists(atPath:file.path))
    }
    @Test func invalidSettingsAndRangeRejected() async throws {
        let root=folder();defer{try? FileManager.default.removeItem(at:root)}
        do{_ = try await OfflineRenderer.render(Project.demo(),to:root.appendingPathComponent("bad.wav"),settings:WAVSettings(sampleRate:32000));Issue.record("Invalid sample rate accepted")}catch is ExportError{}
        do{_ = try await OfflineRenderer.render(Project.demo(),to:root.appendingPathComponent("bad.wav"),range:0..<999999);Issue.record("Out-of-song range accepted")}catch is ExportError{}
    }
    @Test func standardZipAndProjectRoundTrip() throws {
        #expect(ProjectArchive.checksum(Data("123456789".utf8))==0xcbf43926)
        let p=Project.demo();let archive=try PortableProject.data(p);let entries=try ProjectArchive.decode(archive)
        #expect(Set(entries.map(\.name))==["manifest.json","metadata.json"])
        #expect(try PortableProject.decode(archive,asCopy:false)==p)
        let copy=try PortableProject.decode(archive);#expect(copy.id != p.id);#expect(copy.patterns==p.patterns);#expect(copy.revision==0)
    }
    @Test func corruptAndUnsafeArchivesRejected() throws {
        #expect(throws:ExportError.self){try ProjectArchive.encode([.init("../escape",Data([1]))])}
        #expect(throws:ExportError.self){try ProjectArchive.encode([.init("/absolute",Data([1]))])}
        #expect(throws:ExportError.self){try ProjectArchive.encode([.init("a",Data()),.init("a",Data())])}
        var data=try PortableProject.data(Project.demo());data[60] ^= 0xff
        #expect(throws:ExportError.self){try PortableProject.decode(data)}
        #expect(throws:ExportError.self){try ProjectArchive.decode(Data([1,2,3]))}
    }
    @Test func stemsAlignedAndMutedChannelsSilent() async throws {
        let root=folder();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        var p=Project.demo();p.tracks[1].mute=true
        let url=try await StemExporter.render(p,to:root.appendingPathComponent("stems.zip"),settings:WAVSettings(sampleRate:44100,bitDepth:16,tailSeconds:0,dither:false))
        let entries=try ProjectArchive.decode(Data(contentsOf:url),maxBytes:8_000_000)
        let waves=entries.filter{$0.name.hasSuffix(".wav")};#expect(waves.count==3);#expect(Set(waves.map{$0.data.count}).count==1)
        let drums=try #require(waves.first{$0.name.contains("drums")});#expect(drums.data.dropFirst(44).allSatisfy{$0==0})
        #expect(entries.contains{$0.name=="manifest.json"})
        if let path=ProcessInfo.processInfo.environment["GRILLA_EXPORT_FIXTURES"] {let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try Data(contentsOf:url).write(to:dir.appendingPathComponent("stems.zip"))}
    }
}
