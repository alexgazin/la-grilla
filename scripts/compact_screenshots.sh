#!/bin/bash
set -euo pipefail
run_limited() {
  python3 - "$@" <<'PY'
import subprocess,sys
try:sys.exit(subprocess.run(sys.argv[2:],timeout=int(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:sys.exit(124)
PY
}
COMPACT=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for group in d["devices"].values() for x in group if x["name"]=="iPhone SE (3rd generation)"),""))')
if test -z "$COMPACT"; then
  RUNTIME=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); target=open("/tmp/grilla-simulator-id").read().strip(); print(next(k for k,v in d["devices"].items() if any(x["udid"]==target for x in v)))')
  COMPACT=$(run_limited 60 xcrun simctl create GrillaCompact com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$RUNTIME")
fi
DEVICE=$(cat /tmp/grilla-simulator-id)
run_limited 60 xcrun simctl shutdown "$DEVICE" || true
run_limited 60 xcrun simctl boot "$COMPACT" || true
run_limited 300 xcrun simctl bootstatus "$COMPACT" -b
set -o pipefail
run_limited 360 xcodebuild -test-timeouts-enabled YES -maximum-test-execution-time-allowance 180 -project LaGrilla.xcodeproj -scheme LaGrilla -destination "platform=iOS Simulator,id=$COMPACT" -derivedDataPath DerivedData -resultBundlePath CompactResults.xcresult ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -only-testing:LaGrillaUITests/ScreenshotTests/testCaptureCompactScreens test-without-building | tee compact-tests.log
