import Foundation

/// U16 · What kind of output the sound goes to and whether it suits recording.
public enum AudioRouteKind: String, Sendable, CaseIterable {
    case speaker, wired, usb, bluetooth, airPlay, other
    public var title: String {
        switch self {
        case .speaker: "Speaker"; case .wired: "Wired"; case .usb: "USB audio"
        case .bluetooth: "Bluetooth"; case .airPlay: "AirPlay"; case .other: "Audio output"
        }
    }
    public var symbol: String {
        switch self {
        case .speaker: "speaker.wave.2"; case .wired: "headphones"; case .usb: "cable.connector"
        case .bluetooth: "airpods"; case .airPlay: "airplayaudio"; case .other: "hifispeaker"
        }
    }
}

public enum AudioRouteAdvice {
    /// From AVAudioSession port type raw values (the first output decides).
    public static func kind(portTypes: [String]) -> AudioRouteKind {
        guard let port = portTypes.first else { return .other }
        switch port {
        case "Speaker", "Receiver": return .speaker
        case "Headphones", "LineOut": return .wired
        case "USBAudio": return .usb
        case "BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE": return .bluetooth
        case "AirPlay": return .airPlay
        default: return .other
        }
    }

    /// Typical output latency in milliseconds when nothing was measured.
    public static func typicalLatency(_ kind: AudioRouteKind) -> Int {
        switch kind {
        case .speaker, .wired: 12
        case .usb: 10
        case .bluetooth: 160
        case .airPlay: 2000
        case .other: 25
        }
    }

    /// The latency to show: measured when calibrated, otherwise typical (and marked as such).
    public static func latency(_ kind: AudioRouteKind, measured: Double?) -> (milliseconds: Int, measured: Bool) {
        if let measured, measured.isFinite, measured >= 0 { return (Int(measured.rounded()), true) }
        return (typicalLatency(kind), false)
    }

    /// Recording through this route would land noticeably late.
    public static func warnsBeforeRecording(_ kind: AudioRouteKind, measured: Double?) -> Bool {
        if kind == .bluetooth || kind == .airPlay { return true }
        return (measured ?? 0) > 60
    }
}
