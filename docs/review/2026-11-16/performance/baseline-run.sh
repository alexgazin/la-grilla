#!/bin/bash
set -euo pipefail
GRILLA_PROFILE_ROOT=$(cd "$(dirname "$0")" && pwd)
GRILLA_PROFILE_REPOSITORY=${1:-/workspace/la-grilla-audit-actions}
GRILLA_PROFILE_SWIFT=${GRILLA_SWIFT_BIN:-/workspace/tools/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swift}
GRILLA_PROFILE_BASE=29adf6c398173faf830de8f6249702628b8a3f76
mkdir -p "$GRILLA_PROFILE_ROOT/baseline"
git -C "$GRILLA_PROFILE_REPOSITORY" archive "$GRILLA_PROFILE_BASE" Packages/MusicDomain docs/release/fixtures/load-P1.grillapack docs/release/fixtures/load-P3.grillapack | tar -x -C "$GRILLA_PROFILE_ROOT/baseline"
SWIFTPM_MODULECACHE_OVERRIDE="$GRILLA_PROFILE_ROOT/module-cache" CLANG_MODULE_CACHE_PATH="$GRILLA_PROFILE_ROOT/clang-cache" "$GRILLA_PROFILE_SWIFT" run --package-path "$GRILLA_PROFILE_ROOT" --scratch-path "$GRILLA_PROFILE_ROOT/build" --cache-path "$GRILLA_PROFILE_ROOT/spm-cache" --config-path "$GRILLA_PROFILE_ROOT/spm-config" --security-path "$GRILLA_PROFILE_ROOT/spm-security" -c release GrillaArchitectureProfile "$GRILLA_PROFILE_ROOT/baseline" "$GRILLA_PROFILE_BASE" "$GRILLA_PROFILE_ROOT/receipt.json"
GRILLA_SWIFT_BIN="$GRILLA_PROFILE_SWIFT" python3 "$GRILLA_PROFILE_ROOT/provenance.py"
