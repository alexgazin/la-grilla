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
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if "iPhone 16" == x["name"]))')
echo "$DEVICE" > /tmp/grilla-simulator-id
run_limited 60 open -a Simulator --args -CurrentDeviceUDID "$DEVICE" || true
run_limited 60 xcrun simctl boot "$DEVICE" || true
run_limited 300 xcrun simctl bootstatus "$DEVICE" -b
# Keep the simulator's status bar; appearance overrides can block on hosted runners.
echo "Ad-hoc signing simulator application"
codesign --force --deep --sign - DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
echo "Installing simulator application"
run_limited 300 xcrun simctl install "$DEVICE" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
if test "${GRILLA_CAPTURE_SCREENS:-1}" = 0; then
  run_limited 180 xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla --uitesting --screen grid
  sleep 5
  exit 0
fi
SCREENSHOT_DIR=${GRILLA_SCREENSHOT_DIR:-Screenshots/R8}
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
COMPACT=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for group in d["devices"].values() for x in group if x["name"]=="iPhone SE (3rd generation)"),""))')
if test -z "$COMPACT"; then
  RUNTIME=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); target=open("/tmp/grilla-simulator-id").read().strip(); print(next(k for k,v in d["devices"].items() if any(x["udid"]==target for x in v)))')
  COMPACT=$(run_limited 60 xcrun simctl create GrillaCompact com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$RUNTIME")
fi
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
