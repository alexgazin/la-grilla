import Foundation

/// U60 · How much of the studio is shown. Simple hides the advanced panels until "Show more";
/// nothing is removed from the song, and every hidden feature keeps working.
public enum FeatureLevel: String, CaseIterable, Codable, Sendable {
    case simple, full

    public var title: String { self == .simple ? "Simple" : "Full" }
    public var detail: String {
        self == .simple ? "Pads, chords, melody and export. Advanced panels wait behind “Show more”."
            : "Everything: mixer inserts, MIDI devices, automation and fine timing."
    }

    /// True when `feature` is shown without "Show more".
    public func shows(_ feature: AdvancedFeature) -> Bool { self == .full }
}

/// Panels that simple mode keeps behind "Show more".
public enum AdvancedFeature: String, CaseIterable, Sendable {
    /// Per-track EQ, effects and sends in Mixer.
    case mixerInserts
    /// MIDI devices, mapping and MPE.
    case midi
    /// Recording and editing knob moves.
    case automation
    /// Latency calibration and other timing settings.
    case timing
    /// Backup folders and settings files.
    case backup
}

/// U39 · Interface density: how much fits on screen versus how big each control is.
public enum InterfaceDensity: String, CaseIterable, Codable, Sendable {
    case compact, normal, large

    public var title: String {
        switch self {
        case .compact: "Compact"
        case .normal: "Normal"
        case .large: "Large"
        }
    }

    /// Height of tabs, bars and list rows in points (never under the 44 pt touch minimum).
    public var controlHeight: Double {
        switch self {
        case .compact: 44
        case .normal: 48
        case .large: 58
        }
    }

    /// Multiplier for spacing and padding.
    public var spacing: Double {
        switch self {
        case .compact: 0.7
        case .normal: 1
        case .large: 1.3
        }
    }

    /// Steps added to the text size (−1 smaller, +1 larger); accessibility sizes are never reduced.
    public var typeStep: Int {
        switch self {
        case .compact: -1
        case .normal: 0
        case .large: 1
        }
    }

    /// The text size index after the density step, given the system's index among the standard
    /// sizes (0 = extra small … 6 = extra extra extra large; 7+ = accessibility sizes).
    public func typeIndex(system: Int, standardCount: Int = 7) -> Int {
        if system >= standardCount { return typeStep > 0 ? system + 1 : system }
        return min(standardCount - 1, max(0, system + typeStep))
    }
}

/// U63 · Eco mode in Low Power Mode: the sound never changes; the screen does less.
public enum EcoMode {
    /// How often level meters and the playhead are read (per second).
    public static func meterRate(lowPower: Bool) -> Double { lowPower ? 15 : 30 }
    /// The living background and decorative motion stop in eco mode.
    public static func animatesBackground(lowPower: Bool, reduceMotion: Bool) -> Bool { !lowPower && !reduceMotion }
    /// How long a pad stays lit after it sounds (seconds); shorter refreshes need a longer glow.
    public static func padGlow(lowPower: Bool) -> Double { lowPower ? 0.2 : 0.12 }
}
