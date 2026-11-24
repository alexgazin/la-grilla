#pragma once
// I32 · Voice treatment for recorded sounds (offline, on the control thread): low cut and tone EQ,
// a compressor and a de-esser. Presets Podcast, Vocal and Warm. Soft pitch correction is applied by
// the caller (whole-sound shift toward the nearest note).
#include <algorithm>
#include <cmath>
#include <vector>

namespace grilla {

struct VoiceBiquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;
    float run(float x) { const double y = b0 * x + z1; z1 = b1 * x - a1 * y + z2; z2 = b2 * x - a2 * y; return float(y); }
    void set(double c0, double c1, double c2, double d0, double d1, double d2) { b0 = c0 / d0; b1 = c1 / d0; b2 = c2 / d0; a1 = d1 / d0; a2 = d2 / d0; }
    static constexpr double Pi = 3.14159265358979323846;
    void highpass(double rate, double frequency, double q = 0.707) {
        const double w = 2 * Pi * frequency / rate, alpha = std::sin(w) / (2 * q), c = std::cos(w);
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha);
    }
    void peaking(double rate, double frequency, double gainDB, double q = 1.0) {
        const double a = std::pow(10, gainDB / 40), w = 2 * Pi * frequency / rate, alpha = std::sin(w) / (2 * q), c = std::cos(w);
        set(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a);
    }
    void highShelf(double rate, double frequency, double gainDB) {
        const double a = std::pow(10, gainDB / 40), w = 2 * Pi * frequency / rate, c = std::cos(w), s = std::sin(w);
        const double alpha = s / 2 * std::sqrt(2.0), root = 2 * std::sqrt(a) * alpha;
        set(a * ((a + 1) + (a - 1) * c + root), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - root),
            (a + 1) - (a - 1) * c + root, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - root);
    }
    void bandpass(double rate, double frequency, double q) {
        const double w = 2 * Pi * frequency / rate, alpha = std::sin(w) / (2 * q), c = std::cos(w);
        set(alpha, 0, -alpha, 1 + alpha, -2 * c, 1 - alpha);
    }
};

/// Feed-forward compressor on a peak envelope (dB domain): above the threshold the level rises
/// 1/ratio as fast; steady-state output = threshold + (input − threshold) / ratio + makeup.
inline void voiceCompress(float *x, int frames, double rate, double thresholdDB, double ratio, double attackMs, double releaseMs, double makeupDB) {
    const double attack = std::exp(-1 / (rate * attackMs / 1000)), release = std::exp(-1 / (rate * releaseMs / 1000));
    double envelope = 0;
    const double makeup = std::pow(10, makeupDB / 20);
    for (int i = 0; i < frames; i++) {
        const double level = std::abs(double(x[i]));
        envelope = level > envelope ? attack * envelope + (1 - attack) * level : release * envelope + (1 - release) * level;
        const double db = 20 * std::log10(std::max(1e-9, envelope));
        const double reduction = db > thresholdDB ? (db - thresholdDB) * (1 - 1 / ratio) : 0;
        x[i] = float(x[i] * std::pow(10, -reduction / 20) * makeup);
    }
}

/// De-esser: a band-pass detector around `frequency` drives a high shelf down while the band is
/// above the threshold (at most `maxReductionDB`); lower frequencies pass unchanged.
inline void voiceDeess(float *x, int frames, double rate, double frequency, double thresholdDB, double maxReductionDB) {
    VoiceBiquad detector, shelf;
    detector.bandpass(rate, frequency * 1.4, 1.2);
    double envelope = 0, applied = 0;
    const double attack = std::exp(-1 / (rate * 0.002)), release = std::exp(-1 / (rate * 0.06)), smooth = std::exp(-1 / (rate * 0.003));
    for (int i = 0; i < frames; i++) {
        const double band = std::abs(double(detector.run(x[i])));
        envelope = band > envelope ? attack * envelope + (1 - attack) * band : release * envelope + (1 - release) * band;
        const double db = 20 * std::log10(std::max(1e-9, envelope));
        const double target = std::min(maxReductionDB, std::max(0.0, db - thresholdDB));
        applied = smooth * applied + (1 - smooth) * target;
        if ((i & 31) == 0) shelf.highShelf(rate, frequency, -applied);
        x[i] = shelf.run(x[i]);
    }
}

/// Presets: 1 Podcast, 2 Vocal, 3 Warm. Returns false for an unknown preset.
inline bool voiceTreat(float *x, int frames, double rate, int preset) {
    if (preset < 1 || preset > 3 || frames <= 0 || rate < 8000) return false;
    VoiceBiquad cut, body, presence, air;
    switch (preset) {
    case 1: cut.highpass(rate, 90); body.peaking(rate, 250, -1.5, 0.9); presence.peaking(rate, 3200, 3, 0.9); air.highShelf(rate, 9000, 1); break;
    case 2: cut.highpass(rate, 100); body.peaking(rate, 300, -2, 1.0); presence.peaking(rate, 4000, 2, 1.0); air.highShelf(rate, 10000, 3); break;
    default: cut.highpass(rate, 70); body.peaking(rate, 200, 2.5, 0.8); presence.peaking(rate, 4000, -1, 1.0); air.highShelf(rate, 8000, -3); break;
    }
    for (int i = 0; i < frames; i++) x[i] = air.run(presence.run(body.run(cut.run(x[i]))));
    switch (preset) {
    case 1: voiceCompress(x, frames, rate, -20, 3, 5, 120, 5); voiceDeess(x, frames, rate, 5500, -30, 6); break;
    case 2: voiceCompress(x, frames, rate, -18, 4, 3, 100, 6); voiceDeess(x, frames, rate, 6000, -32, 9); break;
    default: voiceCompress(x, frames, rate, -22, 2.5, 10, 160, 4); voiceDeess(x, frames, rate, 5000, -28, 4); break;
    }
    // Never clip: bring the peak under −1 dBFS if the treatment raised it.
    float peak = 0; for (int i = 0; i < frames; i++) peak = std::max(peak, std::abs(x[i]));
    if (peak > 0.891f) { const float g = 0.891f / peak; for (int i = 0; i < frames; i++) x[i] *= g; }
    return true;
}

}  // namespace grilla
