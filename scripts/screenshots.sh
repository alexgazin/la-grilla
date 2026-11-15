#!/bin/bash
set -euo pipefail
run_limited() {
  python3 - "$@" <<'PYTHON'
import subprocess,sys
try:
    result=subprocess.run(sys.argv[2:],timeout=int(sys.argv[1]))
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    print("Simulator command timed out:", " ".join(sys.argv[2:]),flush=True)
    sys.exit(124)
PYTHON
}
test -f DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app/Info.plist
DEVICE=$(python3 scripts/select_simulator.py --name "iPhone 16 Pro Max" --type com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max)
echo "$DEVICE" > /tmp/grilla-simulator-id
GRILLA_XCODE_DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
run_limited 60 xcrun simctl boot "$DEVICE" || true
run_limited 300 xcrun simctl bootstatus "$DEVICE" -b
# A fresh Simulator must open an already booted device. Launching the GUI first
# intermittently exposed a windowless I/O menu with no audio-device entries.
run_limited 60 open -a "$GRILLA_XCODE_DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$DEVICE"
if test -f ci-audio.log; then
  {
    echo "Simulator audio preferences after actual device boot:"
    defaults read com.apple.iphonesimulator RecentAudioInputDeviceUIDs || true
    defaults read com.apple.iphonesimulator RecentAudioOutputDeviceUIDs || true
  } 2>&1 | tee -a ci-audio.log
  # AX menus provide supplementary routing evidence. Never let a stale desktop
  # prevent the strict native HAL/CAF tests from measuring actual input: those
  # tests still fail on unavailable input, silence or invalid recorded music.
  if bash scripts/select_ci_simulator_audio.sh 2>&1 | tee -a ci-audio.log; then
    echo "Supplementary Simulator GUI routing verified." | tee -a ci-audio.log
  else
    echo "SUPPLEMENTARY ROUTING UNVERIFIED: Simulator GUI selection failed. Actual native PCM/CAF acceptance is still mandatory; no checkmarks are claimed." | tee -a ci-audio.log
  fi
fi
if test "${GRILLA_CAPTURE_SCREENS:-1}" = 0; then
  # XCTest installs and launches its own correctly signed application.
  exit 0
fi
# Keep the simulator's status bar; appearance overrides can block on hosted runners.
echo "Ad-hoc signing simulator application"
codesign --force --deep --sign - DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
echo "Installing simulator application"
run_limited 300 xcrun simctl install "$DEVICE" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
SCREENSHOT_DIR=${GRILLA_SCREENSHOT_DIR:-Screenshots/Design2026}
mkdir -p "$SCREENSHOT_DIR"
rm -f "$SCREENSHOT_DIR/"*.png
for SCREEN in grid jam mixer projects export export-wav export-stems notes notes-mixer harmony harmony-proposal assistant assistant-proposal voice voice-draft perform perform-take perform-export midi midi-mapped grid-light jam-light mixer-light notes-light export-light grid-ru assistant-ru notes-large mixer-large jam-large; do
  run_limited 15 xcrun simctl terminate "$DEVICE" com.alexgazin.LaGrilla || true
  echo "Launching $SCREEN"
  TARGET="$SCREEN"
  ARGS=(--uitesting)
  case "$SCREEN" in
    *-light) TARGET="${SCREEN%-light}"; ARGS+=(--appearance light);;
    *-ru) TARGET="${SCREEN%-ru}"; ARGS+=(-AppleLanguages '(ru)' -AppleLocale ru_RU);;
    *-large) TARGET="${SCREEN%-large}"; ARGS+=(--large-type);;
  esac
  APP_LAUNCH=$(run_limited 180 xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla "${ARGS[@]}" --screen "$TARGET")
  echo "$APP_LAUNCH"
  APP_PID=$(echo "$APP_LAUNCH" | python3 -c 'import sys,re; print(re.search(r": ([0-9]+)",sys.stdin.read()).group(1))')
  sleep 8
  kill -0 "$APP_PID"
  run_limited 90 xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT_DIR/$SCREEN.png" || run_limited 90 xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT_DIR/$SCREEN.png"
done
# A real 375-point iPhone simulator complements the main iPhone 16 captures.
COMPACT=$(python3 scripts/select_simulator.py --name "iPhone SE (3rd generation)" --type com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation --same-runtime-as "$DEVICE")
run_limited 60 xcrun simctl shutdown "$DEVICE" || true
run_limited 60 xcrun simctl boot "$COMPACT" || true
run_limited 300 xcrun simctl bootstatus "$COMPACT" -b
run_limited 180 xcrun simctl install "$COMPACT" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
for SCREEN in grid jam mixer; do
  run_limited 15 xcrun simctl terminate "$COMPACT" com.alexgazin.LaGrilla || true
  APP_LAUNCH=$(run_limited 180 xcrun simctl launch "$COMPACT" com.alexgazin.LaGrilla --uitesting --appearance light --screen "$SCREEN")
  APP_PID=$(echo "$APP_LAUNCH" | python3 -c 'import sys,re; print(re.search(r": ([0-9]+)",sys.stdin.read()).group(1))')
  sleep 8
  kill -0 "$APP_PID"
  run_limited 90 xcrun simctl io "$COMPACT" screenshot "$SCREENSHOT_DIR/compact-$SCREEN.png" || run_limited 90 xcrun simctl io "$COMPACT" screenshot "$SCREENSHOT_DIR/compact-$SCREEN.png"
done
run_limited 60 xcrun simctl shutdown "$COMPACT"
run_limited 60 xcrun simctl boot "$DEVICE"
run_limited 300 xcrun simctl bootstatus "$DEVICE" -b
