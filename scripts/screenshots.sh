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
xcrun simctl boot "$DEVICE" || true
run_limited 300 xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
run_limited 90 xcrun simctl install "$DEVICE" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
mkdir -p Screenshots
for SCREEN in grid jam mixer projects; do
  xcrun simctl terminate "$DEVICE" com.alexgazin.LaGrilla || true
  run_limited 60 xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla --screen "$SCREEN"
  sleep 3
  run_limited 45 xcrun simctl io "$DEVICE" screenshot "Screenshots/$SCREEN.png"
done
