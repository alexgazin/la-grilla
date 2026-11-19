import Foundation

/// I63 · a small spectrum for the mixer: Hann-windowed radix-2 FFT of the
/// latest master samples, folded into logarithmic bands (dB, −90…0).
public enum Spectrum {
    public static func bands(_ samples: [Float], rate: Double, count: Int = 24, low: Double = 30, high: Double = 16_000) -> [Float] {
        let n = 1 << Int(log2(Double(max(64, min(4096, samples.count)))))
        guard samples.count >= n, count > 0, rate > 0 else { return [Float](repeating: -90, count: max(0, count)) }
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        let start = samples.count - n
        for i in 0..<n { re[i] = Double(samples[start + i]) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))) }
        fft(&re, &im)
        let binHz = rate / Double(n)
        let top = min(high, rate / 2)
        var result: [Float] = []
        for b in 0..<count {
            let f0 = low * pow(top / low, Double(b) / Double(count)), f1 = low * pow(top / low, Double(b + 1) / Double(count))
            let i0 = max(1, Int(f0 / binHz)), i1 = max(i0 + 1, min(n / 2, Int(ceil(f1 / binHz))))
            var peak = 0.0
            for i in i0..<i1 { peak = max(peak, (re[i] * re[i] + im[i] * im[i]).squareRoot()) }
            // A full-scale sine with a Hann window peaks at n/4.
            let level = 20 * log10(max(1e-9, peak / (Double(n) / 4)))
            result.append(Float(min(0, max(-90, level))))
        }
        return result
    }

    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let wr = cos(angle), wi = sin(angle)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<(length / 2) {
                    let a = i + k, b = a + length / 2
                    let tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    let next = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = next
                }
                i += length
            }
            length <<= 1
        }
    }
}
