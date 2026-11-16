import Foundation
import MusicDomain

private struct Samples: Encodable {
    let sampleCount: Int
    let minMilliseconds: Double
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maxMilliseconds: Double
    let rawMilliseconds: [Double]

    init(_ values: [Double]) {
        let sorted = values.sorted()
        sampleCount = values.count
        minMilliseconds = sorted.first ?? 0
        medianMilliseconds = sorted[sorted.count / 2]
        p95Milliseconds = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        maxMilliseconds = sorted.last ?? 0
        rawMilliseconds = values
    }
}

private struct LibraryResult: Encodable {
    let projectCount: Int
    let manifestBytes: Int
    let setupMilliseconds: Double
    let warmupMilliseconds: Double
    let list: Samples
    let summaryWarmupMilliseconds: Double
    let listSummaries: Samples
    let singleSummary: Samples
    let singleSummaryQueries: Int
    let retainedSummaryCount: Int
    let fullProjectsRetainedBySummaryResults = 0
    let successfulEntries: Int
}

private struct FixtureResult: Encodable {
    let fixture: String
    let archiveBytes: Int
    let manifestBytes: Int
    let compiledNotes: Int
    let validate: Samples
    let compile: Samples
    let mixEditWithValidation: Samples
    let drumNoteEditWithValidation: Samples
    let libraries: [LibraryResult]
}

private struct Receipt: Encodable {
    let formatVersion = 2
    let hostOnly = true
    let devicePerformanceVerified = false
    let realTimeAudioDeadlineVerified = false
    let optimizedBuild = true
    let sourceBaselineSHA: String
    let sourceSnapshotDigest: String
    let sourceWorkingTreeChangesIncluded = true
    let sourceState = "Immutable copy of the uncommitted MusicDomain worktree; identified by sourceSnapshotDigest, not a final commit SHA"
    let generatedAt: Date
    let runtime: String
    let os: String
    let processorCount: Int
    let architecture = "x86_64"
    let measurementMethod = "DispatchTime uptime; sequential isolated operations; one unrecorded warmup per operation; library setup and first warmup recorded separately; no concurrent profiling tasks in this executable"
    let percentileMethod = "nearest-rank p95; median selects upper middle when n is even"
    let mixEditDescription = "fresh History and fixture Project per sample; decrement track 0 gain by 0.01 dB inside History.apply, including its complete Project.validate"
    let drumNoteEditDescription = "fresh History and fixture Project per sample; change first existing drum event velocity by one within 1...127 inside History.apply, including complete Project.validate"
    let exclusions = ["No SwiftUI or MainActor timing", "No Session.sync or AVAudioEngine", "No iPhone memory, thermal, touch latency or dropouts", "No cold filesystem cache reset", "No physical file-system crash-consistency test", "Retained summary count describes returned API values, not process RSS"]
    let fixtures: [FixtureResult]
    let checksum: Int
}

private func elapsedMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func measured(_ repetitions: Int, consume: inout Int, operation: () throws -> Int) rethrows -> Samples {
    consume &+= try operation()
    var durations: [Double] = []
    for _ in 0..<repetitions {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try operation()
        let elapsed = elapsedMilliseconds(since: start)
        consume &+= value
        durations.append(elapsed)
    }
    return Samples(durations)
}

@main
private enum Profile {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else {
            fatalError("Usage: GrillaArchitectureProfile <fixture-root> <source-snapshot.json> <receipt.json>")
        }
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let sourceIdentity = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
        let output = URL(fileURLWithPath: args[3])
        let scratch = output.deletingLastPathComponent().appendingPathComponent("libraries", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let repetitions = 15
        let listRepetitions = 5
        var checksum = 0
        var fixtures: [FixtureResult] = []

        for level in [1, 3] {
            let fixtureURL = root.appendingPathComponent("docs/release/fixtures/load-P\(level).grillapack")
            let archive = try Data(contentsOf: fixtureURL)
            let project = try PortableProject.decode(archive, asCopy: false)
            let compiled = Compiler.notes(project)
            let expected = level == 1 ? 768 : 16384
            guard compiled.count == expected else { fatalError("Fixture note count changed") }
            guard !project.patterns[1].drums.isEmpty else { fatalError("Fixture needs a real existing drum event") }
            let manifestBytes = try JSONEncoder().encode(project).count

            let validation = try measured(repetitions, consume: &checksum) {
                try project.validate()
                return project.revision
            }
            let compile = measured(repetitions, consume: &checksum) {
                let notes = Compiler.notes(project)
                return notes.count + (notes.first?.pitch ?? 0) + (notes.last?.pitch ?? 0)
            }
            let mix = try measured(repetitions, consume: &checksum) {
                var candidate = project
                var history = History()
                try history.apply(&candidate) { $0.tracks[0].gain -= 0.01 }
                return candidate.revision + (history.canUndo ? 1 : 0)
            }
            let note = try measured(repetitions, consume: &checksum) {
                var candidate = project
                var history = History()
                try history.apply(&candidate) {
                    let velocity = $0.patterns[1].drums[0].velocity
                    $0.patterns[1].drums[0].velocity = velocity == 127 ? 126 : velocity + 1
                }
                return candidate.revision + (history.canUndo ? 1 : 0)
            }

            var libraries: [LibraryResult] = []
            for count in [10, 50] {
                let folder = scratch.appendingPathComponent("P\(level)-\(count)", isDirectory: true)
                let store = ProjectStore(root: folder)
                var expected: [UUID: (name: String, modified: Date)] = [:]
                var selectedID: UUID?
                let setupStart = DispatchTime.now().uptimeNanoseconds
                for index in 0..<count {
                    var value = project
                    value.id = UUID()
                    value.name = "Host profile P\(level) · \(index)"
                    value.modified = Date(timeIntervalSince1970: Double(index))
                    _ = try await store.save(value)
                    expected[value.id] = (value.name, value.modified)
                    selectedID = value.id
                }
                let setup = elapsedMilliseconds(since: setupStart)
                let warmupStart = DispatchTime.now().uptimeNanoseconds
                let warmup = try await store.list()
                let warmupElapsed = elapsedMilliseconds(since: warmupStart)
                guard warmup.count == count, warmup.allSatisfy({$0.project != nil && $0.error == nil}) else {
                    fatalError("Library setup failed")
                }
                checksum &+= warmup.count
                var times: [Double] = []
                var successful = 0
                for _ in 0..<listRepetitions {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let entries = try await store.list()
                    let elapsed = elapsedMilliseconds(since: start)
                    successful = entries.filter { $0.project != nil && $0.error == nil }.count
                    guard entries.count == count, successful == count else { fatalError("Listing failed") }
                    checksum &+= entries.count
                    times.append(elapsed)
                }
                func assertSummary(_ entry: ProjectStore.SummaryEntry) {
                    guard let value = entry.summary, let wanted = expected[entry.id], entry.error == nil,
                          entry.hasBackup == false, value.id == entry.id, value.name == wanted.name,
                          value.modified == wanted.modified, value.bpm == project.bpm,
                          value.keyRoot == project.keyRoot, value.minor == project.minor,
                          value.revision == project.revision, value.schemaVersion == project.schemaVersion,
                          value.bars == project.length / barTicks, value.length == project.length,
                          value.trackCount == project.tracks.count, value.keyName == project.keyName else {
                        fatalError("Summary metadata differs from the stored canonical project")
                    }
                }
                let summaryWarmupStart = DispatchTime.now().uptimeNanoseconds
                let warmupSummaries = try await store.listSummaries()
                let summaryWarmup = elapsedMilliseconds(since: summaryWarmupStart)
                guard warmupSummaries.count == count else { fatalError("Summary count differs") }
                warmupSummaries.forEach(assertSummary)
                var summaryTimes: [Double] = []
                for _ in 0..<listRepetitions {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let entries = try await store.listSummaries()
                    let elapsed = elapsedMilliseconds(since: start)
                    guard entries.count == count else { fatalError("Summary count differs") }
                    entries.forEach(assertSummary)
                    checksum &+= entries.count
                    summaryTimes.append(elapsed)
                }
                guard let selectedID else { fatalError("No selected document") }
                assertSummary(await store.summary(selectedID))
                var singleTimes: [Double] = []
                for _ in 0..<repetitions {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let entry = await store.summary(selectedID)
                    let elapsed = elapsedMilliseconds(since: start)
                    assertSummary(entry)
                    checksum &+= entry.summary?.trackCount ?? 0
                    singleTimes.append(elapsed)
                }
                let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                let totalBytes = try files.reduce(0) { total, package in
                    total + (try package.appendingPathComponent("manifest.json").resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                }
                libraries.append(LibraryResult(projectCount: count, manifestBytes: totalBytes, setupMilliseconds: setup, warmupMilliseconds: warmupElapsed, list: Samples(times), summaryWarmupMilliseconds: summaryWarmup, listSummaries: Samples(summaryTimes), singleSummary: Samples(singleTimes), singleSummaryQueries: repetitions + 1, retainedSummaryCount: warmupSummaries.count, successfulEntries: successful))
                try FileManager.default.removeItem(at: folder)
            }
            fixtures.append(FixtureResult(fixture: "P\(level)", archiveBytes: archive.count, manifestBytes: manifestBytes, compiledNotes: compiled.count, validate: validation, compile: compile, mixEditWithValidation: mix, drumNoteEditWithValidation: note, libraries: libraries))
        }
        let receipt = Receipt(sourceBaselineSHA: sourceIdentity["sourceBaselineSHA"] as! String, sourceSnapshotDigest: sourceIdentity["sourceSnapshotDigest"] as! String, generatedAt: Date(), runtime: "Swift 6.1.2 x86_64-unknown-linux-gnu; swift run -c release", os: ProcessInfo.processInfo.operatingSystemVersionString, processorCount: ProcessInfo.processInfo.processorCount, fixtures: fixtures, checksum: checksum)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: output, options: .atomic)
        print("Host-only architecture profile written: \(output.path)")
    }
}
