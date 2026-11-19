import Foundation

// Waves 1–3 of the 100-idea roadmap: musical logic for live playing and note
// editing. Everything here is deterministic and independent of UIKit/audio so
// the same rules serve live recording, editing and tests.

// MARK: I06 / I07 · Swing, groove templates and quantize strength

public struct GrooveQuantizer: Equatable, Sendable {
    /// Grid in ticks (e.g. 240 = 1/16, 480 = 1/8); 0 means no quantization.
    public var grid: Int
    /// 0…1: how far a hit moves toward the grid (1 = exactly on the grid).
    public var strength: Double
    /// 0.5 = straight; 0.54–0.75 delays every second grid step (MPC-style swing).
    public var swing: Double

    public init(grid: Int, strength: Double = 1, swing: Double = 0.5) {
        self.grid = max(0, grid); self.strength = min(1, max(0, strength)); self.swing = min(0.75, max(0.5, swing))
    }
    public init(_ quantize: Quantize, strength: Double = 1, swing: Double = 0.5) { self.init(grid: quantize.rawValue, strength: strength, swing: swing) }

    /// Position of a swung grid step.
    public func gridTick(step: Int) -> Int {
        guard grid > 0 else { return step }
        let pair = step / 2 * 2 * grid
        return step % 2 == 0 ? pair : pair + Int((Double(2 * grid) * swing).rounded())
    }

    /// Recorded position of a hit played at `tick` inside a loop of `length` ticks.
    public func tick(_ raw: Int, length: Int) -> Int {
        guard length > 0 else { return 0 }
        let tick = max(0, raw)
        guard grid > 0 else { return min(length - 1, tick) }
        // Nearest swung step (search the neighbouring pair).
        let base = tick / (2 * grid) * 2
        var best = gridTick(step: base), distance = abs(best - tick)
        for step in (base - 1)...(base + 2) where step >= 0 {
            let candidate = gridTick(step: step)
            if abs(candidate - tick) < distance { best = candidate; distance = abs(candidate - tick) }
        }
        let moved = Int((Double(tick) + Double(best - tick) * strength).rounded())
        return ((moved % length) + length) % length
    }
}

public enum GrooveTemplate: String, CaseIterable, Sendable {
    case straight, light, medium, heavy, triplet
    /// Swing amount for the template.
    public var swing: Double {
        switch self { case .straight: 0.5; case .light: 0.54; case .medium: 0.58; case .heavy: 0.62; case .triplet: 2.0 / 3.0 }
    }
    /// Apply as a non-destructive copy of a drum pattern (events on the grid move to swung positions).
    public func applied(to pattern: Pattern, grid: Int = ppq / 4) -> Pattern {
        var result = pattern
        let quantizer = GrooveQuantizer(grid: grid, strength: 1, swing: swing)
        for i in result.drums.indices {
            let tick = result.drums[i].tick
            guard grid > 0, tick % grid == 0 else { continue }
            result.drums[i].tick = min(pattern.length - 1, quantizer.gridTick(step: tick / grid))
        }
        return result
    }
}

// MARK: I11 · Tap tempo and tempo from a played pattern

public enum TempoEstimator {
    /// BPM from tap times (seconds). Uses the median interval and ignores outliers.
    public static func fromTaps(_ times: [TimeInterval]) -> Double? {
        guard times.count >= 3 else { return nil }
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0.2 && $0 < 2 }
        guard intervals.count >= 2 else { return nil }
        let median = intervals.sorted()[intervals.count / 2]
        let kept = intervals.filter { abs($0 - median) <= median * 0.15 }
        guard !kept.isEmpty else { return nil }
        let bpm = 60 / (kept.reduce(0, +) / Double(kept.count))
        return min(240, max(40, (bpm * 10).rounded() / 10))
    }

    /// Most likely tempo of onset times (seconds) within 60…180 BPM, from an
    /// inter-onset-interval histogram that also counts multiples of the beat.
    public static func fromOnsets(_ times: [TimeInterval]) -> Double? {
        guard times.count >= 4 else { return nil }
        let sorted = times.sorted()
        var scores: [Int: Double] = [:]
        for i in sorted.indices {
            for j in (i + 1)..<min(sorted.count, i + 8) {
                let gap = sorted[j] - sorted[i]
                guard gap > 0.1 else { continue }
                for multiple in [0.5, 1, 2, 4] {
                    let bpm = 60 * multiple / gap
                    guard (60...180).contains(bpm) else { continue }
                    scores[Int(bpm.rounded()), default: 0] += 1 / multiple
                }
            }
        }
        guard let best = scores.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) else { return nil }
        // Refine with neighbours.
        let neighbourhood = (best.key - 1...best.key + 1).map { (Double($0), scores[$0] ?? 0) }
        let weight = neighbourhood.reduce(0) { $0 + $1.1 }
        return weight > 0 ? (neighbourhood.reduce(0) { $0 + $1.0 * $1.1 } / weight * 10).rounded() / 10 : Double(best.key)
    }
}

// MARK: I01 / I02 · Route latency calibration

public struct RouteLatencyCalibration: Equatable, Sendable {
    public var medianMilliseconds: Double
    public var spreadMilliseconds: Double
    public var accepted: Int
    public var rejected: Int

    /// Offsets (ms) between a click and the user's tap on it. Outliers beyond
    /// 3 × MAD are rejected; at least 8 accepted taps are required.
    public static func estimate(_ offsets: [Double]) -> RouteLatencyCalibration? {
        let finite = offsets.filter { $0.isFinite && abs($0) < 500 }
        guard finite.count >= 8 else { return nil }
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
        let m = median(finite)
        let mad = max(1, median(finite.map { abs($0 - m) }))
        let kept = finite.filter { abs($0 - m) <= 3 * mad }
        guard kept.count >= 8 else { return nil }
        let center = median(kept)
        return RouteLatencyCalibration(medianMilliseconds: (center * 10).rounded() / 10,
                                       spreadMilliseconds: (median(kept.map { abs($0 - center) }) * 10).rounded() / 10,
                                       accepted: kept.count, rejected: finite.count - kept.count)
    }

    /// Transport tick the musician heard when touching at `tick` on a route that is `milliseconds` late.
    public static func heardTick(_ tick: Int, milliseconds: Double, bpm: Double) -> Int {
        guard milliseconds.isFinite, bpm.isFinite, bpm > 0 else { return tick }
        return tick - Int((milliseconds / 1000 * bpm * Double(ppq) / 60).rounded())
    }

    /// Recorded tick of a hit heard late by `milliseconds` on this route.
    public func compensated(tick: Int, bpm: Double, length: Int) -> Int {
        let ticks = Int((medianMilliseconds / 1000 * bpm * Double(ppq) / 60).rounded())
        guard length > 0 else { return tick }
        return (((tick - ticks) % length) + length) % length
    }
}

// MARK: I03 · Note repeat

public enum NoteRepeat {
    public enum Rate: Int, CaseIterable, Sendable {
        case eighth = 480, sixteenth = 240, thirtySecond = 120, eighthTriplet = 320, sixteenthTriplet = 160
    }
    /// Hit ticks for a pad held from `start` to `end` (absolute ticks), locked to the transport grid.
    public static func hits(from start: Int, to end: Int, rate: Rate, swing: Double = 0.5) -> [Int] {
        guard end > start else { return [] }
        let step = rate.rawValue
        let quantizer = GrooveQuantizer(grid: step, strength: 1, swing: [.eighthTriplet, .sixteenthTriplet].contains(rate) ? 0.5 : swing)
        var result: [Int] = []
        var index = start / step
        if quantizer.gridTick(step: index) < start { index += 1 }
        while true {
            let tick = quantizer.gridTick(step: index)
            if tick >= end { break }
            result.append(tick); index += 1
            if result.count > 4096 { break }
        }
        return result
    }
}

// MARK: I08 / I09 · Retro buffer of live hits

/// Fixed-capacity ring of the most recent live pad hits (played without Record).
public struct PadRetroBuffer: Sendable {
    public struct Hit: Equatable, Sendable {
        public var tick: Int; public var pad: Int; public var velocity: Int
        /// Output sample clock of the hit; orders hits across loop wraps.
        public var clock: UInt64
        public init(tick: Int, pad: Int, velocity: Int, clock: UInt64 = 0) { self.tick = tick; self.pad = pad; self.velocity = velocity; self.clock = clock }
    }
    public let capacity: Int
    private var storage: [Hit] = []
    private var next = 0
    public init(capacity: Int = 512) { self.capacity = max(1, capacity); storage.reserveCapacity(self.capacity) }
    public mutating func append(_ hit: Hit) {
        if storage.count < capacity { storage.append(hit) } else { storage[next] = hit }
        next = (next + 1) % capacity
    }
    public var hits: [Hit] { storage.count < capacity ? storage : Array(storage[next...] + storage[..<next]) }
    /// Hits played since `clock` that fall inside a clip, at their transport
    /// position in that clip, quantized, one attack per pad and step.
    public func events(since clock: UInt64, clipStart: Int, clipLength: Int, quantizer: GrooveQuantizer) -> [DrumEvent] {
        var best: [Int: DrumEvent] = [:]
        for hit in hits where hit.clock >= clock {
            let local = hit.tick - clipStart
            guard local >= 0, local < clipLength else { continue }
            let tick = quantizer.tick(local, length: clipLength), key = tick * 16 + hit.pad
            if let existing = best[key], existing.velocity >= hit.velocity { continue }
            best[key] = DrumEvent(tick: tick, pad: hit.pad, velocity: hit.velocity)
        }
        return best.values.sorted { ($0.tick, $0.pad) < ($1.tick, $1.pad) }
    }
    /// The last `bars` bars before `now`, as drum events relative to the start of that window.
    public func lastBars(_ bars: Int, endingAt now: Int) -> [DrumEvent] {
        let length = max(1, bars) * barTicks, start = max(0, now - length)
        return hits.filter { $0.tick >= start && $0.tick < now }.map { DrumEvent(tick: $0.tick - start, pad: $0.pad, velocity: $0.velocity) }
    }
}

// MARK: I23–I25, I28 · Note editing tools

public enum NoteTools {
    /// Deterministic humanize: timing ±`timing` ticks and velocity ±`velocity`, from `seed`.
    public static func humanize(_ notes: [NoteEvent], ids: Set<UUID>, timing: Int, velocity: Int, seed: UInt64, length: Int) -> [NoteEvent] {
        var state = seed &+ 0x9E3779B97F4A7C15
        func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state % 10_000) / 10_000 * 2 - 1
        }
        return notes.map { note in
            guard ids.contains(note.id) else { return note }
            var n = note
            n.tick = min(max(0, length - n.duration), max(0, n.tick + Int((next() * Double(timing)).rounded())))
            n.velocity = min(127, max(1, n.velocity + Int((next() * Double(velocity)).rounded())))
            return n
        }
    }

    /// Extend each selected note to the next note start (any pitch), without overlapping.
    public static func legato(_ notes: [NoteEvent], ids: Set<UUID>, length: Int) -> [NoteEvent] {
        let starts = Set(notes.map(\.tick)).sorted()
        return notes.map { note in
            guard ids.contains(note.id) else { return note }
            var n = note
            let next = starts.first { $0 > note.tick } ?? length
            n.duration = max(1, min(length - n.tick, next - n.tick))
            return n
        }
    }

    /// Shorten selected notes to `ratio` of their length (minimum 1/32).
    public static func staccato(_ notes: [NoteEvent], ids: Set<UUID>, ratio: Double = 0.5) -> [NoteEvent] {
        notes.map { note in
            guard ids.contains(note.id) else { return note }
            var n = note
            n.duration = max(min(note.duration, ppq / 8), Int((Double(note.duration) * min(1, max(0.05, ratio))).rounded()))
            return n
        }
    }

    public static func scale(root: Int, minor: Bool) -> [Int] {
        (minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]).map { ($0 + root) % 12 }
    }

    /// Move selected notes by scale degrees of the project key. Notes outside
    /// the scale move to the nearest scale tone first.
    public static func scaleTranspose(_ notes: [NoteEvent], ids: Set<UUID>, steps: Int, root: Int, minor: Bool) -> [NoteEvent] {
        // Scale tones in ascending pitch-class order give a monotonic degree number.
        let tones = scale(root: root, minor: minor).sorted()
        func degree(_ pitch: Int) -> Int {
            let octave = Int(floor(Double(pitch) / 12)), pc = pitch - octave * 12
            let index = tones.enumerated().min { abs($0.element - pc) < abs($1.element - pc) }!.offset
            return octave * 7 + index
        }
        func pitch(_ degree: Int) -> Int {
            let octave = Int(floor(Double(degree) / 7)), index = degree - octave * 7
            return octave * 12 + tones[index]
        }
        return notes.map { note in
            guard ids.contains(note.id) else { return note }
            var n = note
            n.pitch = min(127, max(0, pitch(degree(note.pitch) + steps)))
            return n
        }
    }

    /// Copy a phrase written over one chord to a place with another chord,
    /// keeping each note's relation to its chord (chord tone index or the
    /// interval above the root for passing tones).
    public static func chordAwarePaste(_ notes: [NoteEvent], from source: Chord, to target: Chord) -> [NoteEvent] {
        let sourceTones = source.effectiveIntervals.map { ($0 + source.root) % 12 }
        let targetTones = target.effectiveIntervals.map { ($0 + target.root) % 12 }
        return notes.map { note in
            var n = note; n.id = UUID()
            let pc = ((note.pitch % 12) + 12) % 12
            if let index = sourceTones.firstIndex(of: pc), index < targetTones.count {
                var delta = targetTones[index] - pc
                if delta > 6 { delta -= 12 } else if delta < -6 { delta += 12 }
                n.pitch = min(127, max(0, note.pitch + delta))
            } else {
                var delta = (target.root - source.root) % 12
                if delta > 6 { delta -= 12 } else if delta < -6 { delta += 12 }
                n.pitch = min(127, max(0, note.pitch + delta))
            }
            return n
        }
    }
}

// MARK: I13 / I14 · Scale-only keys and one-finger chords

public enum ScaleKeyboard {
    /// MIDI pitches of the project scale between `low` and `high`.
    public static func pitches(root: Int, minor: Bool, low: Int, high: Int) -> [Int] {
        let tones = Set(NoteTools.scale(root: root, minor: minor))
        return (max(0, low)...min(127, high)).filter { tones.contains($0 % 12) }
    }

    /// Diatonic chord on scale degree 0…6 (triad or seventh), voiced closest to `previous`.
    public static func chord(degree: Int, root: Int, minor: Bool, seventh: Bool = false, previous: [Int] = []) -> [Int] {
        let scale = NoteTools.scale(root: root, minor: minor)
        let steps = seventh ? [0, 2, 4, 6] : [0, 2, 4]
        let d = ((degree % 7) + 7) % 7
        var tones: [Int] = []
        for s in steps {
            let i = d + s
            tones.append(scale[i % 7] + 12 * (i / 7))
        }
        let base = 60 + scale[d] - (scale[d] > 6 ? 12 : 0) - scale[d]
        var voiced = tones.map { $0 + base }
        guard !previous.isEmpty else { return voiced }
        // Voice leading: choose the inversion and octave that moves the least.
        var best = voiced, bestCost = Int.max
        for inversion in 0..<voiced.count {
            var candidate = voiced
            for i in 0..<inversion { candidate[i] += 12 }
            candidate.sort()
            for shift in [-12, 0, 12] {
                let shifted = candidate.map { $0 + shift }
                guard shifted.allSatisfy({ (36...96).contains($0) }) else { continue }
                let cost = zip(shifted, previous.sorted()).reduce(0) { $0 + abs($1.0 - $1.1) }
                if cost < bestCost { bestCost = cost; best = shifted }
            }
        }
        voiced = best
        return voiced
    }
}

// MARK: I15 · Arpeggiator

public enum Arpeggiator {
    public enum Pattern: String, CaseIterable, Sendable { case up, down, upDown, asPlayed, random }
    /// Notes for held `pitches` from `start` for `duration` ticks.
    public static func notes(_ pitches: [Int], pattern: Pattern, rate: Int = ppq / 4, octaves: Int = 1,
                             start: Int, duration: Int, velocity: Int = 90, seed: UInt64 = 1, gate: Double = 0.8) -> [NoteEvent] {
        guard !pitches.isEmpty, rate > 0, duration > 0 else { return [] }
        var tones: [Int] = []
        for octave in 0..<max(1, min(3, octaves)) { tones += (pattern == .asPlayed ? pitches : pitches.sorted()).map { $0 + 12 * octave } }
        tones = tones.filter { (0...127).contains($0) }
        var order: [Int]
        switch pattern {
        case .up, .asPlayed: order = tones
        case .down: order = tones.reversed()
        case .upDown: order = tones.count > 2 ? tones + tones.dropFirst().dropLast().reversed() : tones
        case .random:
            var state = seed | 1
            order = (0..<max(1, duration / rate)).map { _ in
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                return tones[Int(state % UInt64(tones.count))]
            }
        }
        var result: [NoteEvent] = []
        var tick = start, index = 0
        while tick < start + duration {
            let length = max(1, min(Int(Double(rate) * gate), start + duration - tick))
            result.append(NoteEvent(tick: tick, duration: length, pitch: order[index % order.count], velocity: index % 4 == 0 ? min(127, velocity + 8) : velocity))
            tick += rate; index += 1
        }
        return result
    }
}

// MARK: I44 · Bass from the groove and chords

public enum BassFromGroove {
    /// A bass line that follows the kick rhythm and plays the chord root,
    /// with a fifth on off-beat kicks and an approach tone before a chord change.
    public static func line(kicks: [Int], chords: [ChordEvent], length: Int, register: Int = 36) -> [NoteEvent] {
        let sortedKicks = Array(Set(kicks.filter { $0 >= 0 && $0 < length })).sorted()
        let sortedChords = chords.sorted { $0.tick < $1.tick }
        guard !sortedKicks.isEmpty, !sortedChords.isEmpty else { return [] }
        func chord(at tick: Int) -> ChordEvent { sortedChords.last { $0.tick <= tick } ?? sortedChords[0] }
        var notes: [NoteEvent] = []
        for (i, kick) in sortedKicks.enumerated() {
            let current = chord(at: kick)
            let next = i + 1 < sortedKicks.count ? sortedKicks[i + 1] : length
            let root = register + ((current.chord.slashBass ?? current.chord.root) % 12)
            var pitch = root
            if kick % ppq != 0 { pitch = root + 7 }
            // Approach: the last kick before a chord change leads a semitone into the next root.
            if let change = sortedChords.first(where: { $0.tick > kick && $0.tick <= next }), change.tick == next {
                let target = register + ((change.chord.slashBass ?? change.chord.root) % 12)
                if next - kick <= ppq { pitch = target + (target > root ? -1 : 1) }
            }
            notes.append(NoteEvent(tick: kick, duration: max(ppq / 8, min(next - kick, ppq * 2) - 30), pitch: pitch, velocity: kick % barTicks == 0 ? 104 : 92))
        }
        return notes
    }
}

// MARK: I45 · Melodic hook over existing chords

public enum HookGenerator {
    /// A one- or two-bar motif in the key, built on chord tones at strong beats
    /// with scale steps between, then developed: repeated, sequenced to follow
    /// the chords, and resolved on a chord tone at the end of the range.
    public static func hook(chords: [ChordEvent], start: Int, bars: Int, root: Int, minor: Bool, seed: UInt64 = 1) -> [NoteEvent] {
        guard bars > 0, !chords.isEmpty else { return [] }
        let scale = Set(NoteTools.scale(root: root, minor: minor))
        var state = seed | 1
        func random(_ n: Int) -> Int { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return Int(state % UInt64(max(1, n))) }
        func chord(at tick: Int) -> Chord { (chords.last { $0.tick <= tick } ?? chords[0]).chord }
        func nearestTone(_ pitch: Int, in tones: Set<Int>) -> Int {
            (0...12).flatMap { [pitch + $0, pitch - $0] }.first { tones.contains((($0 % 12) + 12) % 12) } ?? pitch
        }
        // Rhythm of the motif (in eighths within one bar): strong-beat chord tones, passing steps.
        let rhythms: [[(Int, Int)]] = [[(0, 2), (2, 1), (3, 1), (4, 3), (7, 1)], [(0, 1), (1, 1), (2, 2), (4, 2), (6, 2)], [(0, 3), (3, 1), (4, 1), (5, 1), (6, 2)]]
        let rhythm = rhythms[random(rhythms.count)]
        let contour = [0, 1, 2, -1, 1].shuffledDeterministic(seed: seed)
        var notes: [NoteEvent] = []
        let motifBars = bars >= 4 ? 2 : 1
        for bar in 0..<bars {
            let barStart = start + bar * barTicks
            let current = chord(at: barStart)
            let tones = Set(current.effectiveIntervals.map { ($0 + current.root) % 12 })
            var pitch = nearestTone(72 + (bar / motifBars % 2 == 1 ? 2 : 0), in: tones)
            let lastBar = bar == bars - 1
            for (i, (eighth, length)) in rhythm.enumerated() {
                let tick = barStart + eighth * ppq / 2
                let strong = eighth % 4 == 0
                if i > 0 { pitch += contour[i % contour.count] * 2 }
                pitch = strong ? nearestTone(pitch, in: tones) : nearestTone(pitch, in: scale)
                pitch = min(84, max(64, pitch))
                if lastBar && i == rhythm.count - 1 { pitch = nearestTone(pitch, in: tones) }
                notes.append(NoteEvent(tick: tick, duration: max(ppq / 4, length * ppq / 2 - 40), pitch: pitch, velocity: strong ? 100 : 86))
            }
        }
        return notes
    }
}

extension Array {
    func shuffledDeterministic(seed: UInt64) -> [Element] {
        var state = seed | 1, result = self
        guard count > 1 else { return result }
        for i in stride(from: count - 1, to: 0, by: -1) {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            result.swapAt(i, Int(state % UInt64(i + 1)))
        }
        return result
    }
}

// MARK: I04 · Velocity from the touch

public enum PadVelocity {
    public enum Curve: String, CaseIterable, Sendable { case soft, linear, hard
        var exponent: Double { switch self { case .soft: 0.6; case .linear: 1; case .hard: 1.6 } }
    }
    /// Velocity 30…127 from 3D-touch force when the screen reports it, otherwise
    /// from the contact radius (a firmer, flatter finger covers more glass).
    public static func fromTouch(force: Double, maximumForce: Double, radius: Double, curve: Curve = .linear) -> Int {
        var amount: Double
        if maximumForce > 0, force > 0 { amount = min(1, force / (maximumForce * 0.6)) }
        else { amount = min(1, max(0, (radius - 8) / 26)) }
        amount = pow(amount, curve.exponent)
        return Int((30 + 97 * amount).rounded())
    }
}

// MARK: I53 · Slice a loop into one-shots at its transients

public enum TransientSlicer {
    /// Frame ranges of up to `maximum` slices, each from an attack to the next
    /// (at most `maxSeconds`), found with a rising block-peak envelope.
    public static func slices(_ samples: [Int16], rate: Int, maximum: Int = 16, minimumGap: Double = 0.07, maxSeconds: Double = 2) -> [Range<Int>] {
        guard rate > 0, samples.count >= 64 else { return [] }
        let hop = max(16, rate / 1000)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        guard peak > 0 else { return [] }
        let blocks = stride(from: 0, to: samples.count - hop, by: hop).map { start in samples[start..<start + hop].map { abs(Int($0)) }.max() ?? 0 }
        let level = Double(peak) * 0.12, back = max(1, Int(0.008 * Double(rate)) / hop)
        let gap = Int(minimumGap * Double(rate))
        var onsets: [Int] = []
        for b in blocks.indices {
            let earlier = b >= back ? blocks[(b - back)..<b].max() ?? 0 : 0
            guard Double(blocks[b]) >= level, Double(blocks[b]) >= 2 * Double(earlier) else { continue }
            let frame = max(0, b * hop - rate / 500)   // 2 ms before the attack
            if let last = onsets.last, frame - last < gap { continue }
            onsets.append(frame)
            if onsets.count == maximum { break }
        }
        if onsets.isEmpty { onsets = [0] }
        let limit = Int(maxSeconds * Double(rate))
        return onsets.enumerated().map { i, start in
            let next = i + 1 < onsets.count ? onsets[i + 1] : samples.count
            return start..<min(next, start + limit, samples.count)
        }.filter { $0.count >= 32 }
    }

    /// The slice as a one-shot: a 1 ms fade-in and a 3 ms fade-out avoid clicks.
    public static func oneShot(_ samples: [Int16], _ range: Range<Int>, rate: Int) -> [Int16] {
        let part = Array(samples[range])
        let fadeIn = max(1, rate / 1000), fadeOut = max(1, rate * 3 / 1000)
        return part.enumerated().map { i, v in
            let g = min(1, Double(i) / Double(fadeIn), Double(part.count - 1 - i) / Double(fadeOut))
            return Int16((Double(v) * max(0, g)).rounded())
        }
    }
}

// MARK: I12 · Finger-drumming lessons

public struct DrumLesson: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// One bar per line: (pad, sixteenth steps 0…15).
    public let hits: [(pad: Int, steps: [Int])]
    public static func == (a: DrumLesson, b: DrumLesson) -> Bool { a.id == b.id }

    public static let library: [DrumLesson] = [
        DrumLesson(id: "four-floor", title: "Four on the floor", hits: [(0, [0, 4, 8, 12]), (2, [2, 6, 10, 14]), (4, [4, 12])]),
        DrumLesson(id: "basic-rock", title: "Basic rock beat", hits: [(0, [0, 8]), (1, [4, 12]), (2, [0, 2, 4, 6, 8, 10, 12, 14])]),
        DrumLesson(id: "boom-bap", title: "Boom bap", hits: [(0, [0, 7, 10]), (1, [4, 12]), (2, [0, 2, 4, 6, 8, 10, 12, 14])]),
        DrumLesson(id: "trap-hats", title: "Trap hats", hits: [(0, [0, 11]), (1, [8]), (2, Array(0..<16))]),
        DrumLesson(id: "half-time", title: "Half-time groove", hits: [(0, [0, 3, 10]), (1, [8]), (2, [0, 4, 8, 12])]),
    ]

    /// Expected events in one bar.
    public var events: [DrumEvent] { hits.flatMap { h in h.steps.map { DrumEvent(tick: $0 * ppq / 4, pad: h.pad) } } }

    public struct Score: Equatable, Sendable {
        public var hit: Int, missed: Int, extra: Int
        public var accuracy: Int { hit + missed + extra == 0 ? 0 : Int((Double(hit) / Double(hit + missed + extra) * 100).rounded()) }
    }

    /// Compare played hits (every bar of `bars`) with the lesson; a hit counts
    /// within ±`tolerance` ticks of the expected step on the same pad.
    public func score(_ played: [DrumEvent], bars: Int, tolerance: Int = ppq / 8) -> Score {
        var expected: [DrumEvent] = []
        for bar in 0..<max(1, bars) { expected += events.map { DrumEvent(tick: $0.tick + bar * barTicks, pad: $0.pad) } }
        var remaining = played.filter { $0.tick < max(1, bars) * barTicks }
        var hit = 0, missed = 0
        for e in expected {
            if let i = remaining.firstIndex(where: { $0.pad == e.pad && abs($0.tick - e.tick) <= tolerance }) { hit += 1; remaining.remove(at: i) }
            else { missed += 1 }
        }
        return Score(hit: hit, missed: missed, extra: remaining.count)
    }

    /// A compact grid, e.g. "Kick  x . . . x . . ." per pad.
    public var notation: [String] {
        hits.map { h in
            let name = NSLocalizedString(Compiler.padNames[h.pad], comment: "Pad name")
            return name + ": " + (0..<16).map { h.steps.contains($0) ? "●" : "·" }.joined()
        }
    }
}
