import Foundation

/// ITU-R BS.1770-4 integrated loudness (LUFS) with K-weighting, 400 ms blocks
/// at 75 % overlap, the −70 LUFS absolute gate and the −10 LU relative gate.
/// Used to match palette A/B auditions to within 1 LU on the same passage.
public enum LoudnessMeter {
    public struct Measurement: Equatable, Sendable {
        public var integratedLUFS: Double
        public var samplePeak: Double
        public var samplePeakDBFS: Double { samplePeak > 0 ? 20 * log10(samplePeak) : -200 }
    }

    struct Biquad {
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0, z2 = 0.0
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// K-weighting coefficients for any sample rate (pre-filter shelf + RLB high-pass).
    static func kWeighting(rate: Double) -> (Biquad, Biquad) {
        var f0 = 1681.974450955533, q = 0.7071752369554196
        let gain = 3.999843853973347
        var k = tan(Double.pi * f0 / rate)
        let vh = pow(10, gain / 20), vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        f0 = 38.13547087602444; q = 0.5003270373238773
        k = tan(Double.pi * f0 / rate)
        a0 = 1 + k / q + k * k
        let highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        return (shelf, highPass)
    }

    public static func measure(channels: [[Float]], rate: Int) -> Measurement {
        let frames = channels.map(\.count).min() ?? 0
        var peak = 0.0
        guard frames > 0, rate > 0 else { return Measurement(integratedLUFS: -.infinity, samplePeak: 0) }
        let block = Int(0.4 * Double(rate)), hop = Int(0.1 * Double(rate))
        var squares = [[Double]](repeating: [], count: channels.count)
        for (c, channel) in channels.enumerated() {
            var (shelf, highPass) = kWeighting(rate: Double(rate))
            var filtered = [Double](repeating: 0, count: frames)
            for i in 0..<frames {
                let x = Double(channel[i])
                peak = max(peak, abs(x))
                let y = highPass.process(shelf.process(x))
                filtered[i] = y * y
            }
            squares[c] = filtered
        }
        guard frames >= block else {
            // Shorter than one gating block: one ungated mean square.
            let z = squares.map { $0.reduce(0, +) / Double(frames) }.reduce(0, +)
            return Measurement(integratedLUFS: z > 0 ? -0.691 + 10 * log10(z) : -.infinity, samplePeak: peak)
        }
        // Prefix sums give every block's mean square in O(1).
        var prefix = [[Double]](repeating: [], count: channels.count)
        for c in channels.indices {
            var running = 0.0
            prefix[c] = [0] + squares[c].map { running += $0; return running }
        }
        var blocks: [Double] = []
        var start = 0
        while start + block <= frames {
            var z = 0.0
            for c in channels.indices { z += (prefix[c][start + block] - prefix[c][start]) / Double(block) }
            blocks.append(z)
            start += hop
        }
        func loudness(_ z: Double) -> Double { z > 0 ? -0.691 + 10 * log10(z) : -.infinity }
        let absolute = blocks.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return Measurement(integratedLUFS: -.infinity, samplePeak: peak) }
        let relativeGate = loudness(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { loudness($0) > relativeGate }
        return Measurement(integratedLUFS: loudness(gated.reduce(0, +) / Double(gated.count)), samplePeak: peak)
    }

    /// Stereo PCM of a 16/24-bit WAV written by OfflineRenderer.
    public static func readWAV(_ url: URL) throws -> (channels: [[Float]], rate: Int) {
        let data = try Data(contentsOf: url)
        guard data.count > 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else { throw ExportError.invalidArchive }
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var offset = 12, channels = 2, rate = 48_000, bits = 24
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self), size = u32(offset + 4)
            if id == "fmt " { channels = u16(offset + 10); rate = u32(offset + 12); bits = u16(offset + 22) }
            if id == "data" {
                let bytesPerSample = bits / 8
                guard [2, 3].contains(bytesPerSample), channels > 0 else { throw ExportError.invalidArchive }
                let end = min(data.count, offset + 8 + size)
                let frameBytes = bytesPerSample * channels
                let count = (end - offset - 8) / frameBytes
                var out = [[Float]](repeating: [Float](repeating: 0, count: count), count: channels)
                data.withUnsafeBytes { raw in
                    let p = raw.bindMemory(to: UInt8.self)
                    for frame in 0..<count {
                        for c in 0..<channels {
                            let o = offset + 8 + frame * frameBytes + c * bytesPerSample
                            if bytesPerSample == 2 {
                                out[c][frame] = Float(Int16(bitPattern: UInt16(p[o]) | UInt16(p[o + 1]) << 8)) / 32_768
                            } else {
                                var v = Int32(p[o]) | Int32(p[o + 1]) << 8 | Int32(p[o + 2]) << 16
                                if v & 0x800000 != 0 { v -= 0x1000000 }
                                out[c][frame] = Float(v) / 8_388_608
                            }
                        }
                    }
                }
                return (out, rate)
            }
            offset += 8 + size + (size & 1)
        }
        throw ExportError.invalidArchive
    }
}
