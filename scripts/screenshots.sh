#!/bin/bash
set -euo pipefail
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if "iPhone 16" == x["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app
mkdir -p Screenshots
for SCREEN in grid jam mixer projects; do
  xcrun simctl terminate "$DEVICE" com.alexgazin.LaGrilla || true
  xcrun simctl launch "$DEVICE" com.alexgazin.LaGrilla --screen "$SCREEN"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "Screenshots/$SCREEN.png"
done
