import Foundation

/// I61 · Mastering in words: "louder", "brighter", "warmer", "more space". Each tweak is a
/// small step on the master (level, EQ shelves, delay) and is one Undo.
public enum MasterTweak: String, CaseIterable, Sendable {
    case louder, quieter, brighter, warmer, moreSpace, drier

    public var title: String {
        switch self {
        case .louder: "Louder"
        case .quieter: "Quieter"
        case .brighter: "Brighter"
        case .warmer: "Warmer"
        case .moreSpace: "More space"
        case .drier: "Drier"
        }
    }

    public func apply(to project: inout Project) {
        switch self {
        case .louder: project.master = min(6, project.master + 1.5)
        case .quieter: project.master = max(-60, project.master - 1.5)
        case .brighter: Self.shelves(&project, low: 0, high: 1.5)
        case .warmer: Self.shelves(&project, low: 1.5, high: -1)
        case .moreSpace:
            var fx = project.masterFX ?? MasterFX()
            fx.delayWet = min(0.5, fx.delayWet + 0.06)
            project.masterFX = fx
        case .drier:
            var fx = project.masterFX ?? MasterFX()
            fx.delayWet = max(0, fx.delayWet - 0.06)
            project.masterFX = fx
        }
    }

    private static func shelves(_ project: inout Project, low: Double, high: Double) {
        var eq = project.masterEQ ?? StudioEQ()
        eq.enabled = true
        guard eq.bands.count == 4 else { return }
        eq.bands[0].gain = max(-18, min(18, eq.bands[0].gain + low))
        eq.bands[3].gain = max(-18, min(18, eq.bands[3].gain + high))
        project.masterEQ = eq
    }
}
