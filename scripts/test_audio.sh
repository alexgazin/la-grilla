#!/bin/bash
set -euo pipefail
GRILLA_AUDIO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$GRILLA_AUDIO_ROOT"
GRILLA_AUDIO_TMP=$(mktemp -d "${TMPDIR:-/tmp}/la-grilla-audio.XXXXXX")
trap 'rm -rf "$GRILLA_AUDIO_TMP"' EXIT
GRILLA_AUDIO_CXX=${GRILLA_CXX_BIN:-c++}
FLAGS=(-std=c++17 -O2 -Wall -Wextra -Werror -pthread -I Packages/MusicDomain/Sources/AudioDSP -I Packages/MusicDomain/Sources/AudioDSP/include)
for TEST in kernel kernel_allocation_failure performance_control performance_fx midi_hub midi_kernel midi_output midi_layout repeat_freeze mix_snapshot live_snapshot output_timing input_buffer instrument_version sound_palette voice_retirement keyboard_level studio_dynamics note_repeat midi_clock live_arp synth glide pad_layers automation mpe convolution sampler_pitch voice_chain pad_activity audio_tracks render_stress; do
  SOURCES=("Tests/${TEST}_test.cpp")
  case "$TEST" in
    performance_fx|repeat_freeze) ;;
    midi_hub) SOURCES+=(Packages/MusicDomain/Sources/AudioDSP/MIDIHub.cpp);;
    input_buffer) SOURCES+=(Packages/MusicDomain/Sources/AudioDSP/LiveInputBuffer.cpp);;
    *) SOURCES+=(Packages/MusicDomain/Sources/AudioDSP/GrillaKernel.cpp Packages/MusicDomain/Sources/AudioDSP/MIDIHub.cpp);;
  esac
  "$GRILLA_AUDIO_CXX" "${FLAGS[@]}" "${SOURCES[@]}" -o "$GRILLA_AUDIO_TMP/$TEST"
  "$GRILLA_AUDIO_TMP/$TEST"
done
