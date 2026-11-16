import Foundation
import Testing
@testable import MusicDomain

struct StoreRenameTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StoreRename-" + UUID().uuidString)
    }
    private func manifest(_ root: URL, _ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString + ".grilla").appendingPathComponent("manifest.json")
    }

    @Test func inactiveRenamePreservesCanonicalMusicAndUpdatesRevisionOrderingAndBackup() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var inactive = Project.demo(), active = Project(name: "Active")
        inactive.revision = 12
        inactive.bpm = 147
        inactive.masterFX = MasterFX(filter: -0.25, delayWet: 0.2)
        inactive.modified = Date().addingTimeInterval(-7200)
        active.modified = Date().addingTimeInterval(-3600)
        try await store.save(inactive)
        try await store.save(active)
        #expect(try await store.list().first?.id == active.id)
        let activeBytes = try Data(contentsOf: manifest(folder, active.id))
        let renamed = try await store.rename(inactive.id, expectedRevision: inactive.revision, to: "  New title  ")
        var expected = inactive
        expected.name = "New title"
        expected.revision += 1
        expected.modified = renamed.modified
        #expect(renamed == expected)
        #expect(renamed.modified > inactive.modified)
        #expect(try await store.load(inactive.id) == expected)
        #expect(try await store.load(inactive.id, backup: true) == inactive)
        #expect(try await store.list().first?.id == inactive.id)
        #expect(try Data(contentsOf: manifest(folder, active.id)) == activeBytes)
        // An old catalogue snapshot cannot later overwrite the accepted rename.
        #expect(try await store.save(inactive) == renamed.revision)
        #expect(try await store.load(inactive.id) == expected)
        #expect(try await store.load(inactive.id, backup: true) == inactive)
    }

    @Test func staleRenameRejectsBeforeChangingCanonicalManifestOrBackup() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let displayed = Project.demo()
        try await store.save(displayed)
        var canonical = displayed
        canonical.revision += 1
        canonical.bpm = 108
        canonical.name = "Updated elsewhere"
        try await store.save(canonical)
        let currentURL = manifest(folder, canonical.id)
        let backupURL = currentURL.deletingLastPathComponent().appendingPathComponent("backup.json")
        let currentBytes = try Data(contentsOf: currentURL), backupBytes = try Data(contentsOf: backupURL)
        do {
            try await store.rename(displayed.id, expectedRevision: displayed.revision, to: "Stale title")
            Issue.record("A stale rename was accepted")
        } catch ProjectStore.RenameError.staleRevision {}
        #expect(try Data(contentsOf: currentURL) == currentBytes)
        #expect(try Data(contentsOf: backupURL) == backupBytes)
        #expect(try await store.load(canonical.id) == canonical)
    }

    @Test func concurrentRenamesUseOneExpectedRevisionAndOnlyOneWins() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project.demo()
        try await store.save(project)
        let accepted = await withTaskGroup(of: Bool.self) { group in
            for title in ["First request", "Second request"] {
                group.addTask {
                    do {
                        try await store.rename(project.id, expectedRevision: project.revision, to: title)
                        return true
                    } catch ProjectStore.RenameError.staleRevision {
                        return false
                    } catch {
                        Issue.record("Unexpected rename failure: \(error)")
                        return false
                    }
                }
            }
            var count = 0
            for await result in group where result { count += 1 }
            return count
        }
        #expect(accepted == 1)
        let saved = try await store.load(project.id)
        #expect(saved.revision == project.revision + 1)
        #expect(["First request", "Second request"].contains(saved.name))
        #expect(try await store.load(project.id, backup: true) == project)
    }

    @Test func invalidNamesAndExhaustedRevisionLeaveStoredProjectUntouched() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        try await store.save(project)
        let url = manifest(folder, project.id), original = try Data(contentsOf: url)
        for title in ["", "  \n ", "A\nB", "A\u{2028}B", "A\u{0}B", String(repeating: "a", count: 121)] {
            do {
                try await store.rename(project.id, expectedRevision: project.revision, to: title)
                Issue.record("An invalid project name was accepted")
            } catch ProjectStore.RenameError.invalidName {}
            #expect(try Data(contentsOf: url) == original)
        }
        project.revision = Project.maximumRevision
        try await store.save(project)
        let exhausted = try Data(contentsOf: url)
        do {
            try await store.rename(project.id, expectedRevision: project.revision, to: "Too late")
            Issue.record("An exhausted revision was incremented")
        } catch MusicError.revisionLimit {}
        #expect(try Data(contentsOf: url) == exhausted)
    }

    @Test func modifiedRemainsStrictlyMonotonicEvenWhenClockPrecedesDocument() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        project.modified = Date().addingTimeInterval(86400)
        try await store.save(project)
        let first = try await store.rename(project.id, expectedRevision: 0, to: "Future clock")
        #expect(first.modified > project.modified)
        let second = try await store.rename(project.id, expectedRevision: 1, to: "Future clock again")
        #expect(second.modified > first.modified)
        #expect(try await store.load(project.id).modified == second.modified)
    }

    @Test func backupWriteFailureDoesNotPublishRenamedManifest() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project.demo()
        try await store.save(project)
        let url = manifest(folder, project.id), original = try Data(contentsOf: url)
        // A directory occupying the backup URL produces a real filesystem error
        // on both Linux and Darwin, without depending on chmod/root behavior.
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("backup.json")
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: false)
        do {
            try await store.rename(project.id, expectedRevision: project.revision, to: "Must not publish")
            Issue.record("A failed backup write was ignored")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try await store.load(project.id) == project)
    }
}
