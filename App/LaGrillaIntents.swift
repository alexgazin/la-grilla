import AppIntents
import CoreSpotlight
import Foundation
import MusicDomain

/// I84 · U3 · Shortcuts, Siri and Spotlight. Intents only open the app and leave a
/// request that the running session handles on the main actor; project data never
/// passes through the system except a project's name and tempo for the picker.
struct LaunchRequest: Codable, Equatable {
    enum Kind: String, Codable { case newBeat, openProject, recordIdea, export }
    var kind: Kind
    var bpm: Int?
    var keyRoot: Int?
    var minor: Bool?
    var projectID: UUID?

    static let key = "studio.launchRequest"
    static func post(_ request: LaunchRequest) {
        if let data = try? JSONEncoder().encode(request) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: .laGrillaLaunchRequest, object: nil)
    }
    static func take() -> LaunchRequest? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        if let data = UserDefaults.standard.data(forKey: key) { return try? JSONDecoder().decode(LaunchRequest.self, from: data) }
        // Requests saved by builds before 49 were a plain string.
        if UserDefaults.standard.string(forKey: key) == "studio.launchRequest.newBeat" { return LaunchRequest(kind: .newBeat) }
        return nil
    }
}

/// The twelve keys for Siri and Shortcuts.
enum KeyOption: String, AppEnum {
    case c, cSharp, d, eFlat, e, f, fSharp, g, aFlat, a, bFlat, b
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Key" }
    static var caseDisplayRepresentations: [KeyOption: DisplayRepresentation] {
        [.c: "C", .cSharp: "C♯", .d: "D", .eFlat: "E♭", .e: "E", .f: "F", .fSharp: "F♯", .g: "G", .aFlat: "A♭", .a: "A", .bFlat: "B♭", .b: "B"]
    }
    var root: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct NewBeatIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a new beat" }
    static var description: IntentDescription { IntentDescription("Opens La Grilla in the track builder, with a tempo and key if you give them.") }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Tempo (BPM)") var bpm: Int?
    @Parameter(title: "Key") var key: KeyOption?
    @Parameter(title: "Minor") var minor: Bool?
    static var parameterSummary: some ParameterSummary { Summary("New beat at \(\.$bpm) BPM in \(\.$key)") { \.$minor } }
    @MainActor func perform() async throws -> some IntentResult {
        LaunchRequest.post(LaunchRequest(kind: .newBeat, bpm: bpm.map { min(240, max(40, $0)) }, keyRoot: key?.root, minor: minor))
        return .result()
    }
}

struct OpenStudioIntent: AppIntent {
    static var title: LocalizedStringResource { "Open my last project" }
    static var description: IntentDescription { IntentDescription("Opens La Grilla with the project you worked on last.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { .result() }
}

/// Also what Spotlight runs when a project found there is tapped (OpenIntent).
struct OpenProjectIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open a project" }
    static var description: IntentDescription { IntentDescription("Opens one of your La Grilla projects.") }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Project") var target: ProjectEntity
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target)") }
    @MainActor func perform() async throws -> some IntentResult {
        LaunchRequest.post(LaunchRequest(kind: .openProject, projectID: target.id))
        return .result()
    }
}

struct RecordIdeaIntent: AppIntent {
    static var title: LocalizedStringResource { "Record an idea" }
    static var description: IntentDescription { IntentDescription("Opens La Grilla ready to hum a melody into MIDI.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        LaunchRequest.post(LaunchRequest(kind: .recordIdea))
        return .result()
    }
}

struct ExportProjectIntent: AppIntent {
    static var title: LocalizedStringResource { "Export my song" }
    static var description: IntentDescription { IntentDescription("Opens the export of your current La Grilla project.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        LaunchRequest.post(LaunchRequest(kind: .export))
        return .result()
    }
}

/// A project as Shortcuts, Siri and Spotlight see it: name and a short detail, nothing musical.
struct ProjectEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Project" }
    static var defaultQuery: ProjectQuery { ProjectQuery() }
    var id: UUID
    var name: String
    var detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }
}

struct ProjectQuery: EntityStringQuery {
    func all() async -> [ProjectEntity] {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Projects")
        let entries = (try? await ProjectStore(root: root).listSummaries()) ?? []
        return entries.compactMap { entry in
            guard let summary = entry.summary else { return nil }
            return ProjectEntity(id: summary.id, name: summary.name, detail: "\(Int(summary.bpm)) BPM · \(summary.keyName)")
        }
    }
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        let wanted = Set(identifiers)
        return await all().filter { wanted.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ProjectEntity] {
        let query = string.lowercased()
        return await all().filter { $0.name.lowercased().contains(query) }
    }
    func suggestedEntities() async throws -> [ProjectEntity] { Array(await all().prefix(10)) }
}

struct LaGrillaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewBeatIntent(), phrases: ["Start a new beat in \(.applicationName)", "New beat in \(.applicationName)"],
                    shortTitle: "New beat", systemImageName: "square.grid.3x3")
        AppShortcut(intent: RecordIdeaIntent(), phrases: ["Record an idea in \(.applicationName)", "Hum an idea in \(.applicationName)"],
                    shortTitle: "Record idea", systemImageName: "mic")
        AppShortcut(intent: OpenProjectIntent(), phrases: ["Open \(\.$target) in \(.applicationName)"],
                    shortTitle: "Open project", systemImageName: "music.note.list")
        AppShortcut(intent: OpenStudioIntent(), phrases: ["Open \(.applicationName)", "Continue in \(.applicationName)"],
                    shortTitle: "Open last project", systemImageName: "music.note.list")
        AppShortcut(intent: ExportProjectIntent(), phrases: ["Export my song from \(.applicationName)"],
                    shortTitle: "Export song", systemImageName: "square.and.arrow.up")
    }
}

/// U3 · Keeps Spotlight's list of projects current (names and tempo only).
enum ProjectSpotlight {
    static func refresh() async {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        let entities = await ProjectQuery().all()
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

extension Notification.Name {
    static let laGrillaLaunchRequest = Notification.Name("laGrillaLaunchRequest")
}
