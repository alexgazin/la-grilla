import AudioDSP
import Foundation

/// I37 · A track's recorded or drawn knob movement: level in dB or pan, by song tick.
/// The kernel reads it over the mixer while playing (linear between points, held outside).
public struct AutomationLane: Codable, Equatable, Sendable {
    public enum Parameter: String, Codable, CaseIterable, Sendable {
        case level, pan
        public var range: ClosedRange<Double> { self == .level ? -60...6 : -1...1 }
        /// Recording keeps a change only when it differs this much from the line.
        var tolerance: Double { self == .level ? 0.5 : 0.03 }
        var kernelIndex: Int32 { self == .level ? 0 : 1 }
        public var title: String { self == .level ? "Level" : "Pan" }
    }

    public struct Point: Codable, Equatable, Sendable {
        public var tick: Int
        public var value: Double
        public init(tick: Int, value: Double) { self.tick = tick; self.value = value }
    }

    public static let maxPoints = 64

    public var parameter: Parameter
    public var points: [Point]

    public init(parameter: Parameter, points: [Point]) {
        self.parameter = parameter
        self.points = points
    }

    public func validate() throws {
        guard (1...Self.maxPoints).contains(points.count) else { throw MusicError.invalidProject }
        var previous = -1
        for point in points {
            guard point.tick > previous, point.tick < songTickLimit, point.value.isFinite, parameter.range.contains(point.value) else { throw MusicError.invalidProject }
            previous = point.tick
        }
    }

    /// The value at a tick, as the kernel computes it.
    public func value(at tick: Int) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if tick <= first.tick { return first.value }
        if tick >= last.tick { return last.value }
        guard let upper = points.firstIndex(where: { $0.tick > tick }) else { return last.value }
        let a = points[upper - 1], b = points[upper]
        return a.value + (b.value - a.value) * Double(tick - a.tick) / Double(max(1, b.tick - a.tick))
    }

    func kernelPoints(rangeStart: Int) -> [LGAutomationPoint] {
        var result: [LGAutomationPoint] = []
        for point in points {
            let tick = point.tick - rangeStart
            if tick < 0 {
                // A lane that starts before an exported range begins at its value at the range start.
                if result.isEmpty, let value = value(at: rangeStart) { result = [LGAutomationPoint(tick: 0, value: Float(value))] }
                continue
            }
            if let last = result.last, Int(last.tick) >= tick { continue }
            result.append(LGAutomationPoint(tick: Int32(tick), value: Float(point.value)))
        }
        if result.isEmpty, let value = value(at: rangeStart) { result = [LGAutomationPoint(tick: 0, value: Float(value))] }
        return result
    }
}

/// I37 · Turning knob movements into a lane and editing its points.
public enum AutomationEditing {
    /// A recorded pass replaces the lane between its first and last tick; points outside stay.
    /// The movement is thinned to the points that matter, at most 64 in the whole lane.
    public static func record(_ samples: [(tick: Int, value: Double)], parameter: AutomationLane.Parameter,
                              into existing: AutomationLane?) -> AutomationLane? {
        var byTick: [Int: Double] = [:]
        for sample in samples where sample.tick >= 0 && sample.tick < songTickLimit && sample.value.isFinite {
            byTick[sample.tick] = min(parameter.range.upperBound, max(parameter.range.lowerBound, sample.value))
        }
        let pass = byTick.keys.sorted().map { AutomationLane.Point(tick: $0, value: byTick[$0]!) }
        guard let first = pass.first, let last = pass.last else { return existing }
        let kept = (existing?.parameter == parameter ? existing?.points ?? [] : []).filter { $0.tick < first.tick || $0.tick > last.tick }
        var tolerance = parameter.tolerance
        var thinned = simplify(pass, tolerance: tolerance)
        while thinned.count + kept.count > AutomationLane.maxPoints {
            tolerance *= 1.6
            thinned = simplify(pass, tolerance: tolerance)
            if thinned.count <= 2 { break }
        }
        var points = (kept + thinned).sorted { $0.tick < $1.tick }
        if points.count > AutomationLane.maxPoints { points = Array(points.suffix(AutomationLane.maxPoints)) }
        return AutomationLane(parameter: parameter, points: points)
    }

    /// Ramer–Douglas–Peucker on (tick, value): keeps the corners of the movement.
    static func simplify(_ points: [AutomationLane.Point], tolerance: Double) -> [AutomationLane.Point] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            var worst = start, distance = 0.0
            for index in (start + 1)..<end {
                let p = points[index]
                let line = a.value + (b.value - a.value) * Double(p.tick - a.tick) / Double(max(1, b.tick - a.tick))
                let error = abs(p.value - line)
                if error > distance { distance = error; worst = index }
            }
            if distance > tolerance { keep[worst] = true; stack.append((start, worst)); stack.append((worst, end)) }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Adds or replaces the point at a tick; returns false at the point limit.
    @discardableResult
    public static func set(_ lane: inout AutomationLane, tick: Int, value: Double) -> Bool {
        let value = min(lane.parameter.range.upperBound, max(lane.parameter.range.lowerBound, value))
        if let index = lane.points.firstIndex(where: { $0.tick == tick }) { lane.points[index].value = value; return true }
        guard lane.points.count < AutomationLane.maxPoints, tick >= 0, tick < songTickLimit else { return false }
        lane.points.append(.init(tick: tick, value: value))
        lane.points.sort { $0.tick < $1.tick }
        return true
    }

    /// Moves a point, keeping the order (a point cannot pass its neighbours).
    public static func move(_ lane: inout AutomationLane, index: Int, tick: Int, value: Double) {
        guard lane.points.indices.contains(index) else { return }
        let lower = index > 0 ? lane.points[index - 1].tick + 1 : 0
        let upper = index + 1 < lane.points.count ? lane.points[index + 1].tick - 1 : songTickLimit - 1
        guard lower <= upper else { return }
        lane.points[index] = .init(tick: min(upper, max(lower, tick)),
                                   value: min(lane.parameter.range.upperBound, max(lane.parameter.range.lowerBound, value)))
    }

    /// Lanes follow their sections when sections move, like markers; points past the end go.
    public static func remap(from old: Project, to new: inout Project) {
        guard old.sections != new.sections else { trim(&new); return }
        for index in new.tracks.indices {
            guard let lanes = new.tracks[index].automation, old.tracks.contains(where: { $0.id == new.tracks[index].id }) else { continue }
            new.tracks[index].automation = lanes.compactMap { lane in
                var moved = lane.points.compactMap { point -> AutomationLane.Point? in
                    guard let section = old.sections.first(where: { $0.start <= point.tick && point.tick < $0.start + $0.length }),
                          let target = new.sections.first(where: { $0.id == section.id }) else { return nil }
                    let offset = point.tick - section.start
                    return offset < target.length ? .init(tick: target.start + offset, value: point.value) : nil
                }
                moved.sort { $0.tick < $1.tick }
                var unique: [AutomationLane.Point] = []
                for point in moved where unique.last?.tick != point.tick { unique.append(point) }
                return unique.isEmpty ? nil : AutomationLane(parameter: lane.parameter, points: unique)
            }
            if new.tracks[index].automation?.isEmpty == true { new.tracks[index].automation = nil }
        }
        trim(&new)
    }

    static func trim(_ project: inout Project) {
        let length = project.length
        for index in project.tracks.indices {
            guard var lanes = project.tracks[index].automation else { continue }
            for lane in lanes.indices { lanes[lane].points.removeAll { $0.tick >= length } }
            lanes.removeAll { $0.points.isEmpty }
            project.tracks[index].automation = lanes.isEmpty ? nil : lanes
        }
    }
}

public extension Project {
    /// I37: every track's lanes to the kernel (rebased to an exported range); missing lanes clear.
    func applyTrackAutomation(to kernel: OpaquePointer, rangeStart: Int = 0) {
        for index in 0..<masterBus {
            for parameter in AutomationLane.Parameter.allCases {
                let lane = index < tracks.count ? tracks[index].automation?.first { $0.parameter == parameter } : nil
                let points = lane?.kernelPoints(rangeStart: rangeStart) ?? []
                _ = points.withUnsafeBufferPointer { lg_track_automation(kernel, Int32(index), parameter.kernelIndex, $0.baseAddress, Int32($0.count)) }
            }
        }
    }
}
