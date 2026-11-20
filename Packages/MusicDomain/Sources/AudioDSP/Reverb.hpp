#pragma once
// I58 · shared send reverb: a compact Schroeder/Freeverb-style room (four
// damped combs and two allpasses per channel, decorrelated stereo). All delay
// memory is allocated when the kernel is created; process() never allocates.
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

class SendReverb {
public:
    explicit SendReverb(double rate) {
        const double scale = rate / 44100.0;
        constexpr int combs[4] = {1116, 1188, 1277, 1356}, allpasses[2] = {556, 441}, spread = 23;
        for (int c = 0; c < 2; c++) {
            for (int i = 0; i < 4; i++) comb[c][i].resize(static_cast<size_t>(std::max(1.0, std::round((combs[i] + c * spread) * scale))));
            for (int i = 0; i < 2; i++) allpass[c][i].resize(static_cast<size_t>(std::max(1.0, std::round((allpasses[i] + c * spread) * scale))));
        }
        idleLimit = int(rate * 4);
    }
    void reset() {
        for (auto &channel : comb) for (auto &line : channel) std::fill(line.begin(), line.end(), 0.f);
        for (auto &channel : allpass) for (auto &line : channel) std::fill(line.begin(), line.end(), 0.f);
        combState = {}; combPos = {}; allPos = {}; idle = idleLimit;
    }
    /// True while there is input or a tail still ringing.
    bool active(float input) { if (input != 0.f) { idle = 0; return true; } return idle < idleLimit; }
    void process(float input, float &left, float &right) {
        ++idle;
        const float in = input * 0.05f;
        float out[2] = {0, 0};
        for (int c = 0; c < 2; c++) {
            for (int i = 0; i < 4; i++) {
                auto &line = comb[c][i]; auto &pos = combPos[c][i];
                const float y = line[pos];
                combState[c][i] = y * (1 - damp) + combState[c][i] * damp;
                line[pos] = in + combState[c][i] * feedback;
                if (++pos >= line.size()) pos = 0;
                out[c] += y;
            }
            for (int i = 0; i < 2; i++) {
                auto &line = allpass[c][i]; auto &pos = allPos[c][i];
                const float buffered = line[pos];
                line[pos] = out[c] + buffered * 0.5f;
                out[c] = buffered - out[c];
                if (++pos >= line.size()) pos = 0;
            }
        }
        left += out[0] * wet; right += out[1] * wet;
    }
private:
    std::array<std::array<std::vector<float>, 4>, 2> comb;
    std::array<std::array<std::vector<float>, 2>, 2> allpass;
    std::array<std::array<float, 4>, 2> combState{};
    std::array<std::array<size_t, 4>, 2> combPos{};
    std::array<std::array<size_t, 2>, 2> allPos{};
    float feedback = 0.84f, damp = 0.2f, wet = 3.0f;
    int idle = 1 << 30, idleLimit = 1;
};
