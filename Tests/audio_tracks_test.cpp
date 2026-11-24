// 54 audio tracks: a recorded take plays from memory at its song position, sample-accurately,
// with its trim offset, clip gain, lane mute and level meter; seeking into a clip starts in the
// middle; a new layout replaces the old one; bad layouts are refused.
#include "GrillaKernel.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

static std::vector<float> render(LGKernel *k, int frames) {
    std::vector<float> out; out.reserve(size_t(frames));
    std::vector<float> l(256), r(256);
    for (int done = 0; done < frames; done += 256) { lg_render(k, l.data(), r.data(), 256); for (int i = 0; i < 256 && done + i < frames; i++) out.push_back(l[size_t(i)]); }
    return out;
}
static int loudest(const std::vector<float> &out, float *value = nullptr) {
    int best = -1; float peak = 0;
    for (size_t i = 0; i < out.size(); i++) if (std::abs(out[i]) > peak) { peak = std::abs(out[i]); best = int(i); }
    if (value) *value = peak;
    return best;
}

int main() {
    auto *k = lg_create(48000);
    const LGNote none[1] = {};
    // 120 BPM: a bar (3840 ticks) is two seconds, 1920 ticks one second.
    assert(lg_submit(k, none, 0, 120, 0, 15360, 0, 1));
    // A take: silence with one click 0.1 s in.
    std::vector<float> take(48000 * 2, 0.f); take[4800] = 0.5f;
    LGAudioBuffer *buffer = lg_audio_create(take.data(), int32_t(take.size()), 48000);
    assert(buffer);
    const LGTrackMix lane = {0, 0, 1};
    LGAudioClip clip = {0, 1920, 1920 + 3840, 0, 0, 0, 0};
    assert(lg_audio_submit(k, &clip, &buffer, 1, &lane, 1));

    // Stopped: nothing sounds.
    auto quiet = render(k, 4096);
    float peak = 0; loudest(quiet, &peak); assert(peak == 0);

    // Playing from the start: the click lands 1.1 s in.
    lg_seek(k, 0); lg_play(k, 1);
    auto out = render(k, 48000 * 2);
    float level = 0; int at = loudest(out, &level);
    assert(std::abs(at - (48000 + 4800)) <= 2);
    assert(level > 0.1f);
    assert(lg_audio_meter(k, 0) > 0.f && lg_audio_meter(k, 1) == 0.f && lg_audio_meter(nullptr, 0) == 0.f);
    lg_play(k, 0); render(k, 2048);

    // Trimmed by 0.05 s and 6 dB quieter: earlier and half as loud.
    LGAudioClip trimmed = {0, 1920, 1920 + 3840, 0.05, -6.0206f, 0, 0};
    assert(lg_audio_submit(k, &trimmed, &buffer, 1, &lane, 1));
    lg_seek(k, 0); lg_play(k, 1);
    out = render(k, 48000 * 2);
    float half = 0; at = loudest(out, &half);
    assert(std::abs(at - (48000 + 2400)) <= 2);
    assert(std::abs(half / level - 0.5f) < 0.03f);
    lg_play(k, 0); render(k, 2048);

    // A muted lane is silent.
    const LGTrackMix muted = {0, 0, 0};
    assert(lg_audio_submit(k, &clip, &buffer, 1, &muted, 1));
    lg_seek(k, 0); lg_play(k, 1);
    out = render(k, 48000 * 2);
    loudest(out, &peak); assert(peak < 1e-6f);
    lg_play(k, 0); render(k, 2048);

    // Seeking into the clip starts the take in the middle: the click is 0.05 s after the seek.
    assert(lg_audio_submit(k, &clip, &buffer, 1, &lane, 1));
    lg_seek(k, 1920 + 96); lg_play(k, 1);   // 96 ticks = 0.05 s into the clip
    out = render(k, 48000);
    at = loudest(out, &peak);
    assert(std::abs(at - 2400) <= 3 && peak > 0.1f);
    lg_play(k, 0); render(k, 2048);

    // A layout without clips replaces it; the take is freed only after both owners let go.
    assert(lg_audio_submit(k, nullptr, nullptr, 0, nullptr, 0));
    lg_seek(k, 0); lg_play(k, 1);
    out = render(k, 48000 * 2);
    loudest(out, &peak); assert(peak < 1e-6f);
    lg_audio_release(buffer);
    lg_play(k, 0); render(k, 2048);

    // Refused: a lane that does not exist, a clip that ends before it starts, NaN gain, no buffer.
    LGAudioBuffer *other = lg_audio_create(take.data(), int32_t(take.size()), 44100);
    LGAudioClip bad = {1, 0, 100, 0, 0, 0, 0};
    assert(!lg_audio_submit(k, &bad, &other, 1, &lane, 1));
    bad = {0, 200, 100, 0, 0, 0, 0}; assert(!lg_audio_submit(k, &bad, &other, 1, &lane, 1));
    bad = {0, 0, 100, 0, NAN, 0, 0}; assert(!lg_audio_submit(k, &bad, &other, 1, &lane, 1));
    LGAudioBuffer *missing = nullptr; bad = {0, 0, 100, 0, 0, 0, 0}; assert(!lg_audio_submit(k, &bad, &missing, 1, &lane, 1));
    assert(!lg_audio_create(nullptr, 100, 48000) && !lg_audio_create(take.data(), 1, 48000));
    lg_audio_release(other);
    lg_destroy(k);
    std::printf("Audio tracks: take at bar 1.5 lands at 1.1 s (±2 frames); 0.05 s trim and −6 dB move and halve it; mute silent; seek starts mid-take; bad layouts refused\n");
}
