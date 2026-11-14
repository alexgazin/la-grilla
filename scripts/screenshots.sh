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
open -a Simulator --args -CurrentDeviceUDID "$DEVICE" || true
run_limited 60 xcrun simctl boot "$DEVICE" || true
run_limited 300 xcrun simctl bootstatus "$DEVICE" -b
# Keep the simulator's status bar; appearance overrides can block on hosted runners.
echo "Ad-hoc signing simulator application"
codesign --force --deep --sign - DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
echo "Installing simulator application"
run_limited 90 xcrun simctl install "$DEVICE" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
mkdir -p Screenshots
for SCREEN in grid jam mixer projects; do
  run_limited 15 xcrun simctl terminate "$DEVICE" com.alexgazin.LaGrilla || true
  echo "Launching $SCREEN"
  run_limited 60 xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla --screen "$SCREEN"
  sleep 3
  xcrun simctl spawn "$DEVICE" launchctl list | python3 -c 'import sys,re; lines=sys.stdin.read().splitlines(); active=[x for x in lines if re.match(r"^[0-9]+\s+",x) and "com.alexgazin.LaGrilla" in x]; print("Active app:",active); sys.exit(0 if active else 1)'
  run_limited 45 xcrun simctl io "$DEVICE" screenshot "Screenshots/$SCREEN.png"
done
