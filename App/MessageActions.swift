import MusicDomain
import SwiftUI
import UIKit

/// U46 · A message that has a fix gets a button that does it: open the mixer to free a
/// track, empty Recently deleted, open Settings for the microphone, finish a take…
enum MessageAction: Equatable {
    case openSettings, openMixer, openSections, openTrash, finishTake, leavePerformance, undo

    var title: LocalizedStringKey {
        switch self {
        case .openSettings: "Open Settings"
        case .openMixer: "Open Mixer"
        case .openSections: "Open song form"
        case .openTrash: "Open Recently deleted"
        case .finishTake: "Finish the take"
        case .leavePerformance: "Back to editing"
        case .undo: "Undo"
        }
    }

    /// The action for a message shown by the studio, if it has one. Messages are stored
    /// either as English keys or already localized, so both are compared.
    static func suggested(for message: String) -> MessageAction? {
        func matches(_ key: String) -> Bool { message == key || message == NSLocalizedString(key, comment: "") }
        func contains(_ fragment: String) -> Bool { message.localizedCaseInsensitiveContains(fragment) }
        if matches(MusicError.trackLimit.errorDescription ?? "") || matches("A project can contain up to eight tracks.") { return .openMixer }
        if matches(MusicError.limit.errorDescription ?? "") { return .openSections }
        if matches(SampleError.limit.errorDescription ?? "") { return .openTrash }
        if matches(MusicError.invalidProject.errorDescription ?? "") { return .undo }
        if matches("Finish the drum take before editing the project.") || matches("Finish the take before changing the loop.") { return .finishTake }
        if matches("Return to editing before changing the source project.") { return .leavePerformance }
        if contains("microphone") || contains("микрофон") { return contains("Settings") || contains("Настройк") ? .openSettings : nil }
        return nil
    }

    @MainActor func perform(in session: Session) {
        session.message = nil
        switch self {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .openMixer: session.sheet = nil; session.tab = 2
        case .openSections: session.presentEditor(.sections)
        case .openTrash: session.presentEditor(.trash)
        case .finishTake: session.finishTake()
        case .leavePerformance: Task { await session.leavePerformance() }
        case .undo: session.undo()
        }
    }
}
