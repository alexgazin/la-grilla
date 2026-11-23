import Foundation

/// I55 · A game controller as drum pads: face buttons play kick, snare and hats, the
/// shoulders clap and open hat, the D-pad the toms and percussion; the triggers play
/// their pad with the pressure as velocity.
public enum GamepadControl: String, CaseIterable, Codable, Sendable {
    case a, b, x, y, leftShoulder, rightShoulder, leftTrigger, rightTrigger, up, down, left, right, menu, options
}

public struct GamepadMapping: Equatable, Codable, Sendable {
    public var pads: [GamepadControl: Int]

    public static let standard = GamepadMapping(pads: [
        .a: 0, .b: 1, .x: 2, .y: 3, .leftShoulder: 4, .rightShoulder: 9,
        .leftTrigger: 0, .rightTrigger: 1, .up: 8, .left: 6, .right: 7, .down: 5, .menu: 12, .options: 14,
    ])

    public init(pads: [GamepadControl: Int]) { self.pads = pads.filter { (0..<16).contains($0.value) } }

    /// The pad and velocity for a press; nil for a release or an unmapped control.
    public func hit(_ control: GamepadControl, value: Float, wasPressed: Bool) -> (pad: Int, velocity: Int)? {
        guard let pad = pads[control] else { return nil }
        let pressed = value > (control == .leftTrigger || control == .rightTrigger ? 0.15 : 0.5)
        guard pressed && !wasPressed else { return nil }
        let velocity = control == .leftTrigger || control == .rightTrigger ? Int((40 + Float(87) * min(1, value)).rounded()) : 104
        return (pad, max(1, min(127, velocity)))
    }
}
