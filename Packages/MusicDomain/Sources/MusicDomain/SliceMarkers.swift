import Foundation

/// I6 · Where a loop is cut before it goes onto the pads: found from its attacks with a
/// sensitivity and a minimum interval, then moved, added or removed by hand.
public struct SliceMarkers: Equatable, Sendable {
    public static let maximum = 16
    /// Frames between two markers at least.
    public static let spacing = 32

    /// Sorted start frames; never empty for a loop with sound.
    public private(set) var frames: [Int]
    public let length: Int

    public init(frames: [Int], length: Int) {
        self.length = max(0, length)
        var clean: [Int] = []
        for frame in frames.sorted() where frame >= 0 && frame < length - Self.spacing {
            if let last = clean.last, frame - last < Self.spacing { continue }
            clean.append(frame)
            if clean.count == Self.maximum { break }
        }
        self.frames = clean.isEmpty && length > Self.spacing ? [0] : clean
    }

    /// Sensitivity 0 (only strong hits) … 1 (quiet ones too); `minimumGap` in seconds.
    public static func detect(_ samples: [Int16], rate: Int, sensitivity: Double = 0.7, minimumGap: Double = 0.07) -> SliceMarkers {
        let share = 0.3 - 0.26 * min(1, max(0, sensitivity))
        return SliceMarkers(frames: TransientSlicer.onsets(samples, rate: rate, maximum: maximum, minimumGap: max(0.02, minimumGap), level: share), length: samples.count)
    }

    /// Adds a marker at `frame`; false when it is too close to another one or the loop is full.
    @discardableResult public mutating func add(_ frame: Int) -> Bool {
        guard frames.count < Self.maximum, frame >= 0, frame < length - Self.spacing,
              !frames.contains(where: { abs($0 - frame) < Self.spacing }) else { return false }
        frames.append(frame); frames.sort()
        return true
    }

    /// Removes a marker; the last one stays.
    @discardableResult public mutating func remove(at index: Int) -> Bool {
        guard frames.indices.contains(index), frames.count > 1 else { return false }
        frames.remove(at: index)
        return true
    }

    /// Moves a marker, never past its neighbours.
    public mutating func move(_ index: Int, to frame: Int) {
        guard frames.indices.contains(index) else { return }
        let low = index > 0 ? frames[index - 1] + Self.spacing : 0
        let high = index + 1 < frames.count ? frames[index + 1] - Self.spacing : length - Self.spacing - 1
        guard low <= high else { return }
        frames[index] = min(high, max(low, frame))
    }

    /// The slice a frame falls in.
    public func slice(containing frame: Int) -> Int? {
        guard let first = frames.first, frame >= first, frame < length else { return nil }
        return frames.lastIndex { $0 <= frame }
    }

    /// Each marker to the next (at most `maxSeconds`).
    public func ranges(rate: Int, maxSeconds: Double = 2) -> [Range<Int>] {
        let limit = Int(maxSeconds * Double(max(1, rate)))
        return frames.enumerated().map { index, start in
            let next = index + 1 < frames.count ? frames[index + 1] : length
            return start..<min(next, start + limit, length)
        }
    }

    /// A slice as a short WAV to hear it.
    public static func previewWAV(_ samples: [Int16], _ range: Range<Int>, rate: Int) -> Data {
        let shot = TransientSlicer.oneShot(samples, range.clamped(to: 0..<samples.count), rate: rate)
        var body = Data(capacity: shot.count * 2)
        for value in shot { body.little(value) }
        return pcmWAVHeader(rate: rate, channels: 1, bits: 16, byteCount: body.count) + body
    }
}
