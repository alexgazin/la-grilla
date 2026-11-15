#!/bin/bash
# Ephemeral macOS runner fixture, never an app dependency or human-voice test.
# Official HAL driver: https://github.com/ExistentialAudio/BlackHole
# CoreAudio reload workaround confirmed by the runner-images maintainers/users:
# https://github.com/actions/runner-images/issues/11746#issuecomment-2706654115
# Host TCC is separate from iOS permission. This script grants neither: current
# runner images preapprove SimulatorTrampoline; the native harness handles iOS.
# If the VM/Simulator still exposes no input, retain its route diagnostics rather
# than injecting PCM or treating a physical-device acceptance gate as complete.
set -euo pipefail

GRILLA_CI_AUDIO_LOG=${GRILLA_CI_AUDIO_LOG:-ci-audio.log}
exec > >(tee "$GRILLA_CI_AUDIO_LOG") 2>&1

if [[ $(uname -s) != Darwin ]]; then
  echo "Virtual host audio setup requires a macOS runner." >&2
  exit 1
fi
command -v brew >/dev/null
command -v python3 >/dev/null
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
GRILLA_CI_AUDIO_TMP=$(mktemp -d "${TMPDIR:-/tmp}/grilla-ci-audio.XXXXXX")
trap 'rm -rf "$GRILLA_CI_AUDIO_TMP"' EXIT

sw_vers
uname -m
system_profiler SPAudioDataType -json
brew info --json=v2 --cask blackhole-2ch > "$GRILLA_CI_AUDIO_TMP/cask.json"
brew info --json=v2 switchaudio-osx > "$GRILLA_CI_AUDIO_TMP/formula.json"
# Refuse an unreviewed package update instead of silently changing the CI route.
python3 - "$GRILLA_CI_AUDIO_TMP/cask.json" "$GRILLA_CI_AUDIO_TMP/formula.json" <<'PY'
import json,sys
cask=json.load(open(sys.argv[1]))['casks'][0]
formula=json.load(open(sys.argv[2]))['formulae'][0]
assert cask['version']=='0.7.1', 'Review the new official BlackHole version before updating this fixture'
assert formula['versions']['stable']=='1.2.2', 'Review the new SwitchAudioSource version before updating this fixture'
print('Pinned official packages: BlackHole 2ch 0.7.1; switchaudio-osx 1.2.2')
PY
brew fetch --cask blackhole-2ch
GRILLA_CI_AUDIO_PACKAGE=$(brew --cache --cask blackhole-2ch)
pkgutil --check-signature "$GRILLA_CI_AUDIO_PACKAGE"
brew install --cask blackhole-2ch
brew install switchaudio-osx
brew list --cask --versions blackhole-2ch
brew list --versions switchaudio-osx

# No Simulator is running yet. Reload only CoreAudio; a whole-runner reboot
# would discard this job. An installer may already have restarted the daemon.
if pgrep -x coreaudiod >/dev/null; then sudo -n killall coreaudiod; fi
GRILLA_CI_AUDIO_FOUND=0
for ((GRILLA_CI_AUDIO_ATTEMPT=0;GRILLA_CI_AUDIO_ATTEMPT<30;GRILLA_CI_AUDIO_ATTEMPT++)); do
  SwitchAudioSource -a -t input -f json > "$GRILLA_CI_AUDIO_TMP/input.json" || true
  SwitchAudioSource -a -t output -f json > "$GRILLA_CI_AUDIO_TMP/output.json" || true
  # SwitchAudioSource 1.2.2 emits one JSON object per device, not a JSON array.
  if python3 - "$GRILLA_CI_AUDIO_TMP/input.json" "$GRILLA_CI_AUDIO_TMP/output.json" <<'PY'
import json,sys
for path in sys.argv[1:]:
    rows=[json.loads(line) for line in open(path) if line.strip()]
    if not any(row.get('uid')=='BlackHole2ch_UID' for row in rows):sys.exit(1)
PY
  then GRILLA_CI_AUDIO_FOUND=1;break;fi
  sleep 1
done
cat "$GRILLA_CI_AUDIO_TMP/input.json" "$GRILLA_CI_AUDIO_TMP/output.json"
if [[ $GRILLA_CI_AUDIO_FOUND != 1 ]]; then
  system_profiler SPAudioDataType -json
  echo "Official BlackHole HAL did not expose both input and output within 30 seconds." >&2
  exit 1
fi

# Use the same clocked duplex device on both sides. The app's backing track
# loops through the host HAL into its real input tap; it never monitors input
# back to output. With no sender BlackHole supplies finite zero-filled buffers.
SwitchAudioSource -t input -u BlackHole2ch_UID
SwitchAudioSource -t output -u BlackHole2ch_UID
SwitchAudioSource -c -t input -f json > "$GRILLA_CI_AUDIO_TMP/selected-input.json"
SwitchAudioSource -c -t output -f json > "$GRILLA_CI_AUDIO_TMP/selected-output.json"
cat "$GRILLA_CI_AUDIO_TMP/selected-input.json" "$GRILLA_CI_AUDIO_TMP/selected-output.json"
python3 - "$GRILLA_CI_AUDIO_TMP/selected-input.json" "$GRILLA_CI_AUDIO_TMP/selected-output.json" <<'PY'
import json,sys
for path in sys.argv[1:]:
    assert json.load(open(path)).get('uid')=='BlackHole2ch_UID', 'Default host audio device selection failed'
print('Verified actual host duplex defaults; native input/PCM acceptance must still pass.')
PY
system_profiler SPAudioDataType -json
