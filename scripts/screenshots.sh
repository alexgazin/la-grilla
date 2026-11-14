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
SCREENSHOT_DIR=${GRILLA_SCREENSHOT_DIR:-Screenshots/R2}
mkdir -p "$SCREENSHOT_DIR"
for SCREEN in grid jam mixer projects export export-wav export-stems notes notes-mixer; do
  run_limited 15 xcrun simctl terminate "$DEVICE" com.alexgazin.LaGrilla || true
  echo "Launching $SCREEN"
  APP_LAUNCH=$(run_limited 180 xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla --uitesting --screen "$SCREEN")
  echo "$APP_LAUNCH"
  APP_PID=$(echo "$APP_LAUNCH" | python3 -c 'import sys,re; print(re.search(r": ([0-9]+)",sys.stdin.read()).group(1))')
  sleep 8
  kill -0 "$APP_PID"
  run_limited 45 xcrun simctl io "$DEVICE" screenshot "$SCREENSHOT_DIR/$SCREEN.png"
done
