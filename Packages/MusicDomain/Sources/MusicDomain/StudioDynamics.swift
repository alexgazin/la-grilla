import AudioDSP
import Foundation

/// Ideas I5, I56, I57: per-track choke groups, sidechain ducking from the kick
/// and simple insert colour (drive, bit depth). Absent (nil) on every track of
/// older projects, which keeps their sound bit-identical.
public struct TrackDynamics: Codable, Equatable, Sendable {
    /// Each inner array is one group of pad indexes (0...15). A pad belongs to
    /// at most one group; at most eight groups.
    public var chokeGroups: [[Int]]
    /// Duck depth (0...12 dB) applied to this track whenever the kick pad plays.
    public var sidechainDB: Double
    /// Saturation amount 0...1.
    public var drive: Double
    /// 0 = off, else 4...16 bits.
    public var crushBits: Int

    public init(chokeGroups: [[Int]] = [], sidechainDB: Double = 0, drive: Double = 0, crushBits: Int = 0) {
        self.chokeGroups = chokeGroups; self.sidechainDB = sidechainDB; self.drive = drive; self.crushBits = crushBits
    }

    public var isNeutral: Bool { chokeGroups.isEmpty && sidechainDB == 0 && drive == 0 && crushBits == 0 }

    public func validate() throws {
        let pads = chokeGroups.flatMap { $0 }
        guard chokeGroups.count <= 8, chokeGroups.allSatisfy({ (2...16).contains($0.count) }), pads.allSatisfy({ (0...15).contains($0) }),
              Set(pads).count == pads.count, sidechainDB.isFinite, (0...12).contains(sidechainDB), drive.isFinite, (0...1).contains(drive),
              crushBits == 0 || (4...16).contains(crushBits) else { throw MusicError.invalidProject }
    }

    var kernel: LGTrackDynamics {
        var value = LGTrackDynamics()
        withUnsafeMutableBytes(of: &value.choke) { raw in
            let slots = raw.bindMemory(to: Int32.self)
            for (group, pads) in chokeGroups.enumerated() { for pad in pads { slots[pad] = Int32(group + 1) } }
        }
        value.sidechainDB = Float(sidechainDB); value.drive = Float(drive); value.crushBits = Int32(crushBits)
        return value
    }

    /// Common starting points offered in the mixer.
    public static let hatChoke = TrackDynamics(chokeGroups: [[2, 3]])
}

public extension Project {
    /// I59: master limiter ceiling while `masterFX.limiter` is on.
    static let limiterCeilingDB: Float = -1

    /// Applies the project's dynamics to a kernel (live or offline). Stems pass
    /// `includeMaster: false` so the limiter stays a master-only stage.
    @discardableResult
    func applyDynamics(to kernel: OpaquePointer, includeMaster: Bool = true) -> Bool {
        let values = tracks.prefix(masterBus).map { ($0.dynamics ?? TrackDynamics()).kernel }
        let limiter: Int32 = includeMaster && masterFX?.limiter == true ? 1 : 0
        return values.withUnsafeBufferPointer { lg_dynamics(kernel, $0.baseAddress, Int32($0.count), limiter, Self.limiterCeilingDB) } != 0
    }
}

/// I10 · app-wide metronome preferences (not saved in projects).
public struct MetronomeSettings: Codable, Equatable, Sendable {
    public enum Sound: Int, Codable, CaseIterable, Sendable { case beep, high, low }
    public var gainDB: Double
    public var accent: Bool
    public var sound: Sound
    /// Click only during the count-in, not while playing.
    public var countInOnly: Bool

    public init(gainDB: Double = 0, accent: Bool = true, sound: Sound = .beep, countInOnly: Bool = false) {
        self.gainDB = min(6, max(-24, gainDB.isFinite ? gainDB : 0)); self.accent = accent; self.sound = sound; self.countInOnly = countInOnly
    }

    @discardableResult
    public func apply(to kernel: OpaquePointer) -> Bool {
        lg_metronome_config(kernel, Float(gainDB), accent ? 1 : 0, Int32(sound.rawValue)) != 0
    }
}
