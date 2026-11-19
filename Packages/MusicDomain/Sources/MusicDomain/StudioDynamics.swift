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
    /// I58: send level 0...1 to the shared room reverb.
    public var reverbSend: Double

    public init(chokeGroups: [[Int]] = [], sidechainDB: Double = 0, drive: Double = 0, crushBits: Int = 0, reverbSend: Double = 0) {
        self.chokeGroups = chokeGroups; self.sidechainDB = sidechainDB; self.drive = drive; self.crushBits = crushBits; self.reverbSend = reverbSend
    }

    private enum CodingKeys: String, CodingKey { case chokeGroups, sidechainDB, drive, crushBits, reverbSend }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(chokeGroups: try c.decodeIfPresent([[Int]].self, forKey: .chokeGroups) ?? [],
                  sidechainDB: try c.decodeIfPresent(Double.self, forKey: .sidechainDB) ?? 0,
                  drive: try c.decodeIfPresent(Double.self, forKey: .drive) ?? 0,
                  crushBits: try c.decodeIfPresent(Int.self, forKey: .crushBits) ?? 0,
                  reverbSend: try c.decodeIfPresent(Double.self, forKey: .reverbSend) ?? 0)
    }

    public var isNeutral: Bool { chokeGroups.isEmpty && sidechainDB == 0 && drive == 0 && crushBits == 0 && reverbSend == 0 }

    public func validate() throws {
        let pads = chokeGroups.flatMap { $0 }
        guard chokeGroups.count <= 8, chokeGroups.allSatisfy({ (2...16).contains($0.count) }), pads.allSatisfy({ (0...15).contains($0) }),
              Set(pads).count == pads.count, sidechainDB.isFinite, (0...12).contains(sidechainDB), drive.isFinite, (0...1).contains(drive),
              crushBits == 0 || (4...16).contains(crushBits), reverbSend.isFinite, (0...1).contains(reverbSend) else { throw MusicError.invalidProject }
    }

    var kernel: LGTrackDynamics {
        var value = LGTrackDynamics()
        withUnsafeMutableBytes(of: &value.choke) { raw in
            let slots = raw.bindMemory(to: Int32.self)
            for (group, pads) in chokeGroups.enumerated() { for pad in pads { slots[pad] = Int32(group + 1) } }
        }
        value.sidechainDB = Float(sidechainDB); value.drive = Float(drive); value.crushBits = Int32(crushBits); value.reverbSend = Float(reverbSend)
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

/// I36 · a master filter sweep over one section.
public struct FilterSweep: Codable, Equatable, Sendable {
    public var from: Double
    public var to: Double
    public init(from: Double, to: Double) { self.from = from; self.to = to }
    public var isValid: Bool { from.isFinite && to.isFinite && (-1...1).contains(from) && (-1...1).contains(to) && from != to }
    /// Ready-made sweeps offered in the section menu.
    public static let openUp = FilterSweep(from: -0.8, to: 0), closeDown = FilterSweep(from: 0, to: -0.8)
    public static let riseUp = FilterSweep(from: 0, to: 0.6), dropIn = FilterSweep(from: 0.6, to: 0)
}

public extension Project {
    /// Filter ramps in kernel ticks, relative to `rangeStart` (exports rebase ticks to their range).
    func filterRamps(rangeStart: Int = 0) -> [LGFilterRamp] {
        sections.sorted { $0.start < $1.start }.compactMap { section in
            guard let sweep = section.filterSweep, sweep.isValid else { return nil }
            let start = section.start - rangeStart, end = section.start + section.length - rangeStart
            guard end > 0 else { return nil }
            return LGFilterRamp(start: Int32(max(0, start)), end: Int32(end), from: Float(sweep.from), to: Float(sweep.to))
        }.prefix(32).map { $0 }
    }
    @discardableResult
    func applyAutomation(to kernel: OpaquePointer, rangeStart: Int = 0) -> Bool {
        let ramps = filterRamps(rangeStart: rangeStart)
        return ramps.withUnsafeBufferPointer { lg_filter_automation(kernel, $0.baseAddress, Int32($0.count)) } != 0
    }
}
