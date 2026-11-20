import AppIntents
import Foundation

/// I84 · Shortcuts and Siri. Intents only open the app and leave a request
/// that the running session handles on the main actor; no project data is
/// passed through the system.
enum LaunchRequest: String {
    case newBeat = "studio.launchRequest.newBeat"
    static let key = "studio.launchRequest"
    static func post(_ request: LaunchRequest) { UserDefaults.standard.set(request.rawValue, forKey: key) }
    static func take() -> LaunchRequest? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return LaunchRequest(rawValue: raw)
    }
}

struct NewBeatIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a new beat" }
    static var description: IntentDescription { IntentDescription("Opens La Grilla in the track builder.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        LaunchRequest.post(.newBeat)
        NotificationCenter.default.post(name: .laGrillaLaunchRequest, object: nil)
        return .result()
    }
}

struct OpenStudioIntent: AppIntent {
    static var title: LocalizedStringResource { "Open my last project" }
    static var description: IntentDescription { IntentDescription("Opens La Grilla with the project you worked on last.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { .result() }
}

struct LaGrillaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewBeatIntent(), phrases: ["Start a new beat in \(.applicationName)", "New beat in \(.applicationName)"],
                    shortTitle: "New beat", systemImageName: "square.grid.3x3")
        AppShortcut(intent: OpenStudioIntent(), phrases: ["Open \(.applicationName)", "Continue in \(.applicationName)"],
                    shortTitle: "Open last project", systemImageName: "music.note.list")
    }
}

extension Notification.Name {
    static let laGrillaLaunchRequest = Notification.Name("laGrillaLaunchRequest")
}
