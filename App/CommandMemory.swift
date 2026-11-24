import Foundation
import MusicDomain

/// U4 · U13 · Device-local memory of the search field: recent commands and the
/// actions pinned to the quick bar. Never part of a project.
enum CommandMemory {
    private static let recentKey = "commands.recent"
    static let pinnedKey = "commands.pinned"
    static let pinnedLimit = 4

    static var recent: [CommandID] {
        (UserDefaults.standard.stringArray(forKey: recentKey) ?? []).compactMap(CommandID.init(rawValue:))
    }
    static func remember(_ id: CommandID) {
        var list = recent.filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(list.prefix(8).map(\.rawValue), forKey: recentKey)
    }

    /// U65: the last action with its value, for Repeat.
    static var lastRun: CommandMatch? {
        get { UserDefaults.standard.data(forKey: "commands.lastRun").flatMap { try? JSONDecoder().decode(CommandMatch.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "commands.lastRun") }
    }

    /// Pinned actions as a comma-separated string, so views can observe it with @AppStorage.
    static func pinned(_ raw: String) -> [CommandID] { raw.split(separator: ",").compactMap { CommandID(rawValue: String($0)) } }
    static func raw(_ list: [CommandID]) -> String { list.prefix(pinnedLimit).map(\.rawValue).joined(separator: ",") }
    static func toggled(_ id: CommandID, in raw: String) -> String {
        var list = pinned(raw)
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else if list.count < pinnedLimit { list.append(id) }
        return self.raw(list)
    }
}
