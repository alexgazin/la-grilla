#pragma once
// I33 · Spaces: a convolution reverb on the shared send with impulse responses generated on the
// device (room, hall, plate, spring; at most 2 s). Uniformly partitioned FFT convolution in
// blocks of 512 frames: the audio thread only transforms, multiplies and adds into memory
// that was allocated when the space was prepared on the control thread.
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <vector>

namespace grilla {

using cfloat = std::complex<float>;

/// In-place iterative radix-2 FFT of a fixed power-of-two size.
class FFT {
public:
    explicit FFT(int size) : n(size), twiddles(size_t(size / 2)), reversed(size_t(size)) {
        for (int i = 0; i < n / 2; i++) twiddles[size_t(i)] = std::polar(1.0f, float(-2 * 3.14159265358979323846 * i / n));
        int bits = 0; while ((1 << bits) < n) bits++;
        for (int i = 0; i < n; i++) { int r = 0; for (int b = 0; b < bits; b++) if (i & (1 << b)) r |= 1 << (bits - 1 - b); reversed[size_t(i)] = r; }
    }
    void forward(cfloat *data) const { run(data, false); }
    /// Inverse without the 1/n scale (the convolution folds it into the impulse response).
    void inverse(cfloat *data) const { run(data, true); }
    int size() const { return n; }
private:
    void run(cfloat *data, bool inverse) const {
        for (int i = 0; i < n; i++) { const int j = reversed[size_t(i)]; if (j > i) std::swap(data[i], data[j]); }
        for (int length = 2; length <= n; length <<= 1) {
            const int half = length / 2, step = n / length;
            for (int start = 0; start < n; start += length) {
                for (int k = 0; k < half; k++) {
                    const cfloat w = inverse ? std::conj(twiddles[size_t(k * step)]) : twiddles[size_t(k * step)];
                    const cfloat a = data[start + k], b = data[start + k + half] * w;
                    data[start + k] = a + b; data[start + k + half] = a - b;
                }
            }
        }
    }
    int n;
    std::vector<cfloat> twiddles;
    std::vector<int> reversed;
};

/// One channel's partitioned convolution state.
class PartitionedConvolver {
public:
    static constexpr int Block = 512, FFTSize = 2 * Block;

    /// Control thread: transforms the impulse response into partitions; allocates everything.
    PartitionedConvolver(const FFT &fft, const std::vector<float> &impulse) : fft(&fft) {
        partitions = std::max(1, int((impulse.size() + Block - 1) / Block));
        spectra.assign(size_t(partitions) * FFTSize, cfloat{});
        delay.assign(size_t(partitions) * FFTSize, cfloat{});
        scratch.assign(FFTSize, cfloat{});
        input.assign(FFTSize, 0.f);
        output.assign(Block, 0.f);
        for (int p = 0; p < partitions; p++) {
            cfloat *spectrum = &spectra[size_t(p) * FFTSize];
            for (int i = 0; i < Block; i++) {
                const size_t index = size_t(p) * Block + size_t(i);
                spectrum[i] = index < impulse.size() ? cfloat(impulse[index] / FFTSize, 0) : cfloat{};
            }
            fft.forward(spectrum);
        }
    }

    void reset() {
        std::fill(delay.begin(), delay.end(), cfloat{});
        std::fill(input.begin(), input.end(), 0.f);
        std::fill(output.begin(), output.end(), 0.f);
        position = 0; head = 0;
    }

    /// Audio thread: one sample in, one sample out, Block frames of latency.
    float process(float sample) {
        input[size_t(Block + position)] = sample;
        const float out = output[size_t(position)];
        if (++position == Block) { position = 0; convolveBlock(); }
        return out;
    }

private:
    void convolveBlock() {
        // Overlap-save: the last 2 × Block inputs, transformed into the newest delay-line slot.
        head = (head + partitions - 1) % partitions;
        cfloat *slot = &delay[size_t(head) * FFTSize];
        for (int i = 0; i < FFTSize; i++) slot[i] = cfloat(input[size_t(i)], 0);
        fft->forward(slot);
        std::fill(scratch.begin(), scratch.end(), cfloat{});
        for (int p = 0; p < partitions; p++) {
            const cfloat *x = &delay[size_t((head + p) % partitions) * FFTSize];
            const cfloat *h = &spectra[size_t(p) * FFTSize];
            for (int i = 0; i < FFTSize; i++) scratch[size_t(i)] += x[i] * h[i];
        }
        fft->inverse(scratch.data());
        for (int i = 0; i < Block; i++) output[size_t(i)] = scratch[size_t(Block + i)].real();
        std::copy(input.begin() + Block, input.end(), input.begin());
    }

    const FFT *fft;
    int partitions = 1, position = 0, head = 0;
    std::vector<cfloat> spectra, delay, scratch;
    std::vector<float> input, output;
};

/// The four generated spaces.
enum class Space : int { room = 1, hall = 2, plate = 3, spring = 4 };

struct SpaceShape { double seconds, rt60, predelay, damping, earlyLevel; bool spring; };

inline SpaceShape spaceShape(Space space) {
    switch (space) {
    case Space::room: return {0.7, 0.45, 0.004, 0.55, 0.9, false};
    case Space::hall: return {2.0, 1.7, 0.022, 0.35, 0.5, false};
    case Space::plate: return {1.6, 1.25, 0.0, 0.12, 0.0, false};
    case Space::spring: return {1.2, 0.9, 0.0, 0.3, 0.0, true};
    }
    return {0.7, 0.45, 0.004, 0.55, 0.9, false};
}

/// A deterministic impulse response for one channel (seed differs per channel for width).
inline std::vector<float> generateImpulse(Space space, double rate, uint32_t seed) {
    const SpaceShape shape = spaceShape(space);
    const int length = std::min(int(rate * 2), int(rate * shape.seconds));
    std::vector<float> impulse(size_t(length), 0.f);
    uint32_t state = seed * 2654435761u + 12345u;
    auto noise = [&] { state = state * 1664525u + 1013904223u; return float(int32_t(state >> 8) - (1 << 23)) / float(1 << 23); };
    const double decay = std::log(1000.0) / (shape.rt60 * rate);     // −60 dB at rt60
    const int start = int(shape.predelay * rate);
    float lowpass = 0;
    for (int i = start; i < length; i++) {
        const double t = double(i - start);
        float value = noise() * float(std::exp(-decay * t));
        // Darker as it decays: the low-pass closes over the tail.
        const float coefficient = float(std::min(0.95, shape.damping + 0.5 * t / rate));
        lowpass = lowpass * coefficient + value * (1 - coefficient);
        value = lowpass;
        if (shape.spring) {
            // A spring's dispersive "boing": a falling chirp repeating every 32 ms.
            const double cycle = std::fmod(t / rate, 0.032) / 0.032;
            value += float(0.35 * std::sin(2 * 3.14159265358979323846 * (900 - 600 * cycle) * cycle * 0.032) * std::exp(-decay * t));
        }
        impulse[size_t(i)] = value;
    }
    // Early reflections of a room or hall: a few discrete taps.
    if (shape.earlyLevel > 0) {
        const double taps[] = {0.007, 0.011, 0.017, 0.023, 0.031, 0.041};
        for (double tap : taps) {
            const int index = start + int(tap * rate * (space == Space::hall ? 2.2 : 1.0) * (1 + 0.03 * (seed & 1)));
            if (index < length) impulse[size_t(index)] += float(shape.earlyLevel * (noise() > 0 ? 1 : -1) * std::exp(-decay * (index - start)));
        }
    }
    // Unit energy, so every space returns about the same level from the same send.
    double energy = 0; for (float v : impulse) energy += double(v) * v;
    const float scale = energy > 0 ? float(1 / std::sqrt(energy)) : 0.f;
    for (float &v : impulse) v *= scale;
    return impulse;
}

/// A prepared stereo space: allocated on the control thread, processed on the audio thread.
class SpaceReverb {
public:
    SpaceReverb(Space space, double rate)
        : fft(PartitionedConvolver::FFTSize),
          left(fft, generateImpulse(space, rate, 1)), right(fft, generateImpulse(space, rate, 2)),
          idleLimit(int(rate * 2.5)) {}
    void reset() { left.reset(); right.reset(); idle = idleLimit; }
    bool active(float input) { if (input != 0.f) { idle = 0; return true; } return idle < idleLimit; }
    void process(float input, float &l, float &r) {
        ++idle;
        const float in = input * 0.35f;
        l += left.process(in); r += right.process(in);
    }
private:
    FFT fft;
    PartitionedConvolver left, right;
    int idle = 1 << 30, idleLimit;
};

}  // namespace grilla
