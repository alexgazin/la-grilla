import Foundation

/// Build 44: one velocity for the built-in keybed. The live note, the recorded
/// phrase and the WAV export use the same value, so level differences can only
/// come from the project's own track fader and master.
public enum KeyboardPerformance {
    public static let velocity = 100
}
