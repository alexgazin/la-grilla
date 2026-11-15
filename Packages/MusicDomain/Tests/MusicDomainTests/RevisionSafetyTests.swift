import Foundation
import Testing
@testable import MusicDomain

struct RevisionSafetyTests {
    @Test func documentAcceptsRevisionBoundariesAndRejectsInvalidImports()throws {
        for revision in [0,1,42,Project.maximumRevision] {
            var project=Project.demo();project.revision=revision
            try project.validate()
            #expect(try ProjectDocument.decode(JSONEncoder().encode(project))==project)
        }
        for revision in [-1,Int.min,Project.maximumRevision+1,Int.max] {
            var project=Project.demo();project.revision=revision
            let source=try JSONEncoder().encode(project)
            #expect(throws:MusicError.self){try project.validate()}
            #expect(throws:MusicError.self){try ProjectDocument.decode(source)}
        }
        var source=Project.demo();source.revision=Int.max
        var parent=Project.demo()
        parent.performanceTake=PerformanceTake(source:source,sampleRate:48000,durationFrames:48000,events:[PerformanceEvent(frame:0,kind:.section,sectionID:source.sections[0].id)])
        #expect(throws:MusicError.self){try ProjectDocument.decode(JSONEncoder().encode(parent))}
    }

    private func archive(_ project:Project)throws->Data {
        // Forge a CRC-valid portable file rather than using the exporter, whose
        // own validation must reject the invalid revision before writing it.
        let manifest=try JSONEncoder().encode(project)
        let metadata=["version":"1","manifestCRC32":String(format:"%08x",ProjectArchive.checksum(manifest))]
        return try ProjectArchive.encode([.init("manifest.json",manifest),.init("metadata.json",JSONSerialization.data(withJSONObject:metadata))])
    }

    @Test func portableCopyCannotHideAnInvalidSourceRevision()throws {
        var project=Project.demo();project.revision=Project.maximumRevision
        let valid=try PortableProject.data(project)
        #expect(try PortableProject.decode(valid,asCopy:false).revision==Project.maximumRevision)
        #expect(try PortableProject.decode(valid).revision==0)
        for revision in [-1,Int.max] {
            project.revision=revision
            let source=try archive(project)
            #expect(throws:MusicError.self){try PortableProject.decodeBundle(source,asCopy:false)}
            #expect(throws:MusicError.self){try PortableProject.decodeBundle(source)}
            #expect(throws:MusicError.self){try PortableProject.data(project)}
        }
    }

    @Test func storeRejectsInvalidRevisionsWithoutChangingSourceOrBackup()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ProjectStore(root:root)
        var project=Project.demo();project.revision=10;try await store.save(project)
        project.name="Latest valid";project.revision=11;try await store.save(project)
        let folder=root.appendingPathComponent(project.id.uuidString+".grilla")
        let manifest=folder.appendingPathComponent("manifest.json"),backup=folder.appendingPathComponent("backup.json")
        let valid=try Data(contentsOf:manifest),savedBackup=try Data(contentsOf:backup)
        for revision in [-1,Int.max] {
            var invalid=project;invalid.revision=revision
            do{try await store.save(invalid);Issue.record("Invalid revision was saved")}
            catch let error as MusicError{if case .invalidProject=error{}else{Issue.record("Unexpected save error: \(error)")}}
            #expect(try Data(contentsOf:manifest)==valid)
            #expect(try Data(contentsOf:backup)==savedBackup)
        }
        for revision in [-1,Int.max] {
            var invalid=project;invalid.revision=revision
            let source=try JSONEncoder().encode(invalid);try source.write(to:manifest)
            do{_ = try await store.load(project.id);Issue.record("Invalid manifest was loaded")}
            catch let error as MusicError{if case .invalidProject=error{}else{Issue.record("Unexpected load error: \(error)")}}
            let entries=try await store.list()
            #expect(entries.count==1 && entries[0].project==nil && entries[0].error != nil)
            #expect(try Data(contentsOf:manifest)==source)
            #expect(try Data(contentsOf:backup)==savedBackup)
            #expect(try await store.load(project.id,backup:true).revision==10)
        }
    }

    @Test func ordinaryHistoryAndLastValidIncrementRemainMonotonic()throws {
        var project=Project.demo(),history=History()
        try history.apply(&project){$0.name="Edited"}
        #expect(project.revision==1 && project.name=="Edited")
        history.undo(&project)
        #expect(project.revision==2 && project.name=="First light")
        history.redo(&project)
        #expect(project.revision==3 && project.name=="Edited")
        var boundary=Project.demo();boundary.revision=Project.maximumRevision-1
        var last=History();try last.apply(&boundary){$0.name="Last edit"}
        #expect(boundary.revision==Project.maximumRevision)
        try boundary.validate()
        let copy=try PortableProject.decode(PortableProject.data(boundary))
        #expect(copy.revision==0 && copy.name.hasSuffix(" imported"))
    }

    @Test func exhaustedOrInvalidHistoryNeverOverflowsOrConsumesStacks()throws {
        var project=Project.demo();project.revision=Project.maximumRevision-1
        var history=History();try history.apply(&project){$0.name="Last edit"}
        let exhausted=project;var changeRan=false
        #expect(throws:MusicError.self){try history.apply(&project){changeRan=true;$0.name="Must not run"}}
        #expect(!changeRan && project==exhausted && history.canUndo && !history.canRedo)
        history.undo(&project)
        #expect(project==exhausted && history.canUndo && !history.canRedo)
        // Retry with available revision space to prove the refused Undo kept
        // its stack entry; do the equivalent check for Redo at exhaustion.
        project.revision=Project.maximumRevision-1;history.undo(&project)
        #expect(project.name=="First light" && project.revision==Project.maximumRevision && history.canRedo)
        let undone=project;history.redo(&project)
        #expect(project==undone && history.canRedo)
        project.revision=Project.maximumRevision-1;history.redo(&project)
        #expect(project.name=="Last edit" && project.revision==Project.maximumRevision && !history.canRedo)
        for revision in [-1,Int.max] {
            var value=Project.demo(),stack=History()
            try stack.apply(&value){$0.name="First edit"};try stack.apply(&value){$0.name="Second edit"};stack.undo(&value)
            value.revision=revision;let invalid=value
            #expect(throws:MusicError.self){try stack.apply(&value){$0.master = -12}}
            stack.undo(&value);stack.redo(&value)
            #expect(value==invalid && stack.canUndo && stack.canRedo)
        }
    }
}
