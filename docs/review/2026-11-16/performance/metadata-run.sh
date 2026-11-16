#!/bin/bash
set -euo pipefail
GRILLA_PROFILE_ROOT=$(cd "$(dirname "$0")" && pwd)
GRILLA_PROFILE_SWIFT=${GRILLA_SWIFT_BIN:-/workspace/tools/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swift}
python3 "$GRILLA_PROFILE_ROOT/provenance.py" --verify-snapshot
SWIFTPM_MODULECACHE_OVERRIDE="$GRILLA_PROFILE_ROOT/module-cache" CLANG_MODULE_CACHE_PATH="$GRILLA_PROFILE_ROOT/clang-cache" "$GRILLA_PROFILE_SWIFT" run --package-path "$GRILLA_PROFILE_ROOT" --scratch-path "$GRILLA_PROFILE_ROOT/build" --cache-path "$GRILLA_PROFILE_ROOT/spm-cache" --config-path "$GRILLA_PROFILE_ROOT/spm-config" --security-path "$GRILLA_PROFILE_ROOT/spm-security" -c release GrillaArchitectureProfile "$GRILLA_PROFILE_ROOT/fixtures" "$GRILLA_PROFILE_ROOT/source-snapshot.json" "$GRILLA_PROFILE_ROOT/receipt.json"
GRILLA_SWIFT_BIN="$GRILLA_PROFILE_SWIFT" python3 "$GRILLA_PROFILE_ROOT/provenance.py"
