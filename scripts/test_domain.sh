#!/bin/bash
set -euo pipefail
# Optional portable toolchain for Linux development; macOS uses Xcode's swift.
SWIFT_BIN=${GRILLA_SWIFT_BIN:-swift}
CACHE_ROOT=${GRILLA_CACHE_ROOT:-/tmp/la-grilla-swift-cache}
mkdir -p "$CACHE_ROOT"/{modules,clang,spm,config,security}
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/modules" CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang" "$SWIFT_BIN" test --package-path Packages/MusicDomain --cache-path "$CACHE_ROOT/spm" --config-path "$CACHE_ROOT/config" --security-path "$CACHE_ROOT/security" "$@"
