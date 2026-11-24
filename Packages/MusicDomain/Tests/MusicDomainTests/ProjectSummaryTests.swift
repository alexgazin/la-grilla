import Foundation
import Testing
@testable import MusicDomain

struct ProjectSummaryTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ProjectSummary-" + UUID().uuidString)
    }
    private func manifest(_ root: URL, _ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString + ".grilla").appendingPathComponent("manifest.json")
    }
    private func json(_ project: Project) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
    }
    private func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
    }

    @Test func largeProjectSummaryHasExactMetadataAndOneRefreshSeesOnlyItsCanonicalChanges() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/release/fixtures/load-P3.grillapack").standardizedFileURL
        var project = try PortableProject.decode(Data(contentsOf: fixture), asCopy: false)
        #expect(Compiler.notes(project).count == 16384)
        try await store.save(project)
        let first = await store.summary(project.id)
        let summary = try #require(first.summary)
        #expect(first.id == project.id && first.error == nil && !first.hasBackup)
        #expect(summary.id == project.id && summary.name == project.name && summary.bpm == project.bpm)
        #expect(summary.keyRoot == project.keyRoot && summary.minor == project.minor && summary.keyName == project.keyName)
        #expect(summary.bars == 64 && summary.length == project.length && summary.trackCount == 8)
        #expect(summary.revision == project.revision && summary.modified == project.modified)
        #expect(summary.schemaVersion == Project.currentSchemaVersion)
        project.name = "Latest canonical title"
        project.revision += 1
        project.modified = project.modified.addingTimeInterval(1)
        try await store.save(project)
        let refreshed = await store.summary(project.id)
        #expect(refreshed.summary?.name == project.name && refreshed.summary?.revision == project.revision)
        #expect(refreshed.hasBackup && refreshed.error == nil)
        // A previously returned summary is an immutable metadata value.
        #expect(summary.name != refreshed.summary?.name)
    }

    @Test func malformedMusicCanBeListedAsMetadataButMustFailFullOpenAndRetainRecoveryRow() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        try await store.save(project)
        project.revision += 1
        try await store.save(project)
        var object = try json(project)
        object["patterns"] = "Not musical data and intentionally not decoded by the catalogue"
        try write(object, to: manifest(folder, project.id))
        let entries = try await store.listSummaries()
        let metadata = try #require(entries.first)
        #expect(metadata.summary?.id == project.id && metadata.error == nil && metadata.hasBackup)
        do {
            _ = try await store.load(project.id)
            Issue.record("Metadata bypassed full musical validation")
        } catch {
            let failure = ProjectStore.SummaryEntry(id: metadata.id, summary: nil,
                                                   error: error.localizedDescription, hasBackup: metadata.hasBackup)
            #expect(failure.summary == nil && failure.error != nil && failure.hasBackup)
        }
        let legacy = try await store.list()
        #expect(legacy.count == 1 && legacy[0].project == nil && legacy[0].error != nil)
        #expect(try await store.load(project.id, backup: true).revision == 0)
    }

    @Test func corruptJSONFutureSchemaAndFutureFrozenSourceRemainVisibleWithoutTouchingBackup() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        try await store.save(project)
        project.revision += 1
        try await store.save(project)
        let url = manifest(folder, project.id), backup = url.deletingLastPathComponent().appendingPathComponent("backup.json")
        let backupBytes = try Data(contentsOf: backup)
        try Data("{broken json".utf8).write(to: url)
        let broken = try await store.listSummaries()
        #expect(broken.count == 1 && broken[0].summary == nil && broken[0].error != nil && broken[0].hasBackup)
        var future = try json(project)
        future["schemaVersion"] = Project.newestSchemaVersion + 1
        try write(future, to: url)
        let unsupported = await store.summary(project.id)
        #expect(unsupported.summary == nil && unsupported.error == MusicError.unsupportedSchema.localizedDescription)
        var nested = try json(project)
        nested["performanceTakes"] = [["source": ["schemaVersion": Project.newestSchemaVersion + 1]]]
        try write(nested, to: url)
        let futureSource = await store.summary(project.id)
        #expect(futureSource.summary == nil && futureSource.error == MusicError.unsupportedSchema.localizedDescription)
        let futureBytes = try Data(contentsOf: url)
        do {
            try await store.save(project)
            Issue.record("A future frozen source was overwritten by an older snapshot")
        } catch MusicError.unsupportedSchema {}
        #expect(try Data(contentsOf: url) == futureBytes)
        #expect(try Data(contentsOf: backup) == backupBytes)
        #expect(try await store.load(project.id, backup: true).revision == 0)
    }

    @Test func supportedLegacySchemaMetadataDoesNotMigrateOrRewriteUntilFullOpen() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project.demo()
        try await store.save(project)
        let url = manifest(folder, project.id)
        for version in 1...Project.currentSchemaVersion {
            project.schemaVersion = version
            let bytes = try JSONEncoder().encode(project)
            try bytes.write(to: url)
            let metadata = await store.summary(project.id)
            #expect(metadata.summary?.schemaVersion == version && metadata.error == nil)
            #expect(try await store.load(project.id).schemaVersion == Project.currentSchemaVersion)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func invalidMetadataIdentityAndOversizeFilesCannotCreateMisleadingEntries() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project.demo()
        try await store.save(project)
        let url = manifest(folder, project.id), canonical = try json(project)
        let invalidFields: [(String, Any)] = [
            ("name", " "), ("name", String(repeating: "a", count: 121)), ("bpm", 0),
            ("keyRoot", 12), ("revision", -1), ("tracks", [[:]]),
            ("sections", [["start": 0, "length": Int.max]]), ("id", UUID().uuidString)
        ]
        for (key, value) in invalidFields {
            var object = canonical
            object[key] = value
            try write(object, to: url)
            let entry = await store.summary(project.id)
            #expect(entry.id == project.id && entry.summary == nil && entry.error != nil)
        }
        // Full load must also reject a valid project in another package's path.
        var another = project
        another.id = UUID()
        try JSONEncoder().encode(another).write(to: url)
        do {
            _ = try await store.load(project.id)
            Issue.record("A package returned another document's identity")
        } catch MusicError.invalidProject {}
        try Data(repeating: 32, count: 8_000_001).write(to: url)
        let oversized = await store.summary(project.id)
        #expect(oversized.summary == nil && oversized.error == MusicError.tooDense.localizedDescription)
        let missing = await store.summary(UUID())
        #expect(missing.summary == nil && missing.error != nil && !missing.hasBackup)
    }

    @Test func listOrderingAndBackupPresenceStaySeparateFromBackupValidity() async throws {
        let folder = root(), store = ProjectStore(root: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var first = Project(name: "First"), latest = Project(name: "Latest")
        first.modified = Date(timeIntervalSince1970: 10)
        latest.modified = Date(timeIntervalSince1970: 20)
        try await store.save(first)
        try await store.save(latest)
        let backup = manifest(folder, first.id).deletingLastPathComponent().appendingPathComponent("backup.json")
        try Data("invalid backup".utf8).write(to: backup)
        let summaries = try await store.listSummaries()
        #expect(summaries.map(\.id) == [latest.id, first.id])
        #expect(summaries[1].hasBackup && summaries[1].error == nil)
        do {
            _ = try await store.load(first.id, backup: true)
            Issue.record("Presence was mistaken for a validated backup")
        } catch {}
        let legacy = try await store.list()
        #expect(legacy.map(\.id) == summaries.map(\.id))
        #expect(legacy.allSatisfy { $0.project != nil && $0.error == nil })
    }
}

struct StyleProfileTests {
    private func summary(_ bpm: Double, _ key: Int, _ minor: Bool, bars: Int = 8, age: Double) -> ProjectSummary {
        ProjectSummary(id: UUID(), name: "S", bpm: bpm, keyRoot: key, minor: minor, bars: bars, revision: 1, modified: Date(timeIntervalSince1970: 1_000_000 - age), schemaVersion: 15, trackCount: 3)
    }
    @Test func usualTempoKeyAndLengthFromOwnProjects() {
        #expect(StyleProfile.from([summary(90, 2, true, age: 1), summary(92, 2, true, age: 2)]) == nil)
        let profile = StyleProfile.from([summary(90, 2, true, age: 3), summary(96, 2, true, bars: 4, age: 2), summary(140, 7, false, age: 1), summary(84, 9, true, age: 4)])
        #expect(profile?.bpm == 93 && profile?.keyRoot == 2 && profile?.minor == true && profile?.bars == 8 && profile?.projects == 4)
        // A tie goes to the most recently modified key.
        let tie = StyleProfile.from([summary(90, 2, true, age: 3), summary(91, 7, false, age: 1), summary(92, 0, false, age: 2)])
        #expect(tie?.keyRoot == 7 && tie?.minor == false && tie?.bpm == 91)
    }
}

struct BackupPlannerTests {
    private func summary(_ age: Double) -> ProjectSummary {
        ProjectSummary(id: UUID(), name: "S", bpm: 90, keyRoot: 0, minor: false, bars: 4, revision: 1, modified: Date(timeIntervalSince1970: 1_000_000 - age), schemaVersion: 15, trackCount: 2)
    }
    @Test func dailyAndOnlyChangedProjects() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(BackupPlanner.due(last: nil, now: now))
        #expect(!BackupPlanner.due(last: now.addingTimeInterval(-3600), now: now))
        #expect(BackupPlanner.due(last: now.addingTimeInterval(-21 * 3600), now: now))
        #expect(BackupPlanner.due(last: now.addingTimeInterval(3600), now: now))           // clock moved back
        let old = summary(100_000), fresh = summary(10), newer = summary(5)
        #expect(BackupPlanner.changed([old, fresh, newer], since: now.addingTimeInterval(-3600)) == [newer.id, fresh.id])
        #expect(BackupPlanner.changed([old, fresh], since: nil).count == 2)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(BackupPlanner.fileName(Date(timeIntervalSince1970: 0), calendar: calendar) == "La Grilla backup 1970-01-01.zip")
    }
}
