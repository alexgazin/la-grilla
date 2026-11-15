#!/bin/bash
set -euo pipefail
run_limited() {
  python3 - "$@" <<'PY'
import subprocess,sys
try:sys.exit(subprocess.run(sys.argv[2:],timeout=int(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:sys.exit(124)
PY
}
DEVICE=$(cat /tmp/grilla-simulator-id)
COMPACT=$(python3 scripts/select_simulator.py --name "iPhone SE (3rd generation)" --type com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation --same-runtime-as "$DEVICE")
run_limited 60 xcrun simctl shutdown "$DEVICE" || true
run_limited 60 xcrun simctl boot "$COMPACT" || true
run_limited 300 xcrun simctl bootstatus "$COMPACT" -b
set -o pipefail
# Ten real launches plus editor/menu interactions share this capture method.
# Match ScreenshotTests' bounded allowance and leave time for xcodebuild startup
# and xcresult finalization, so a failed assertion still produces its evidence.
run_limited 900 xcodebuild -test-timeouts-enabled YES -maximum-test-execution-time-allowance 600 -project LaGrilla.xcodeproj -scheme LaGrilla -destination "platform=iOS Simulator,id=$COMPACT" -derivedDataPath DerivedData -resultBundlePath CompactResults.xcresult ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -only-testing:LaGrillaUITests/ScreenshotTests/testCaptureCompactScreens test-without-building | tee compact-tests.log
