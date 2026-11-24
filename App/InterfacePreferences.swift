import MusicDomain
import os
import SwiftUI

/// U14 · U39 · U60 · Interface preferences kept on this iPhone (never in a song).
enum InterfacePreferences {
    static let featureLevelKey = "studio.featureLevel"
    static let densityKey = "studio.density"
    static let oneHandKey = "studio.oneHand"

    /// UI tests start from the defaults unless a launch argument asks otherwise:
    /// `--feature-level simple`, `--density compact|large`, `--one-hand`.
    static func prepareForTesting(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("--uitesting") else { return }
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
            return arguments[index + 1]
        }
        let defaults = UserDefaults.standard
        defaults.set(FeatureLevel(rawValue: value(after: "--feature-level") ?? "")?.rawValue ?? FeatureLevel.full.rawValue, forKey: featureLevelKey)
        defaults.set(InterfaceDensity(rawValue: value(after: "--density") ?? "")?.rawValue ?? InterfaceDensity.normal.rawValue, forKey: densityKey)
        defaults.set(arguments.contains("--one-hand"), forKey: oneHandKey)
    }
}

private struct StudioDensityKey: EnvironmentKey {
    static let defaultValue = InterfaceDensity.normal
}

extension EnvironmentValues {
    /// U39 · The interface density chosen in Settings.
    var studioDensity: InterfaceDensity {
        get { self[StudioDensityKey.self] }
        set { self[StudioDensityKey.self] = newValue }
    }
}

extension InterfaceDensity {
    var height: CGFloat { CGFloat(controlHeight) }
    func space(_ value: CGFloat) -> CGFloat { (value * CGFloat(spacing)).rounded() }
}

/// U39 · Applies the density: text one step smaller or larger (accessibility sizes are never made
/// smaller) and the density value for bars, tabs and lanes.
struct StudioDensityModifier: ViewModifier {
    @AppStorage(InterfacePreferences.densityKey) private var densityValue = InterfaceDensity.normal.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let density = InterfaceDensity(rawValue: densityValue) ?? .normal
        let sizes = DynamicTypeSize.allCases
        let current = sizes.firstIndex(of: typeSize) ?? 3
        let index = min(sizes.count - 1, density.typeIndex(system: current))
        content
            .environment(\.studioDensity, density)
            .dynamicTypeSize(sizes[index])
    }
}

/// U20 · Time from the app starting to the studio being ready to play (shown to UI tests).
enum LaunchClock {
    nonisolated(unsafe) private static var started: TimeInterval = 0
    static func mark() { if started == 0 { started = ProcessInfo.processInfo.systemUptime } }
    static func elapsedMilliseconds() -> Int {
        guard started > 0 else { return 0 }
        return Int(((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded())
    }
}

/// U49 · Signposts around opening the heavy screens, read by the UI performance tests
/// (XCTOSSignpostMetric) and by Instruments.
enum StudioSignposts {
    static let subsystem = "com.lagrilla.studio"
    static let category = "Screens"
    static let signposter = OSSignposter(subsystem: subsystem, category: category)
    @MainActor private static var open: [String: OSSignpostIntervalState] = [:]

    @MainActor static func beginPianoRoll() { open["notes"] = signposter.beginInterval("Open piano roll") }
    @MainActor static func endPianoRoll() { if let state = open.removeValue(forKey: "notes") { signposter.endInterval("Open piano roll", state) } }
    @MainActor static func beginMixer() { open["mixer"] = signposter.beginInterval("Open mixer") }
    @MainActor static func endMixer() { if let state = open.removeValue(forKey: "mixer") { signposter.endInterval("Open mixer", state) } }
}

/// U49 · Builds the mixer and the piano roll once, out of sight, shortly after launch, so their
/// first real opening does not pay for loading their views.
struct SheetPrewarm: View {
    let session: Session
    var body: some View {
        ZStack {
            MixerView(session: session)
            PianoRollView(session: session)
        }
        .frame(width: 390, height: 640)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
