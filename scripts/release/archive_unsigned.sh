#!/bin/bash
set -euo pipefail
GRILLA_RELEASE_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$GRILLA_RELEASE_ROOT"
python3 scripts/release/audit_release.py
python3 scripts/release/assert_sdk.py
mkdir -p ReleaseArtifacts
xcodebuild -project LaGrilla.xcodeproj -scheme LaGrilla -configuration Release -destination 'generic/platform=iOS' -archivePath ReleaseArtifacts/LaGrilla-unsigned.xcarchive -derivedDataPath ReleaseDerivedData CODE_SIGNING_ALLOWED=NO archive | tee ReleaseArtifacts/archive.log
python3 scripts/release/audit_release.py --app ReleaseArtifacts/LaGrilla-unsigned.xcarchive/Products/Applications/LaGrilla.app
xcrun dwarfdump --uuid ReleaseArtifacts/LaGrilla-unsigned.xcarchive/Products/Applications/LaGrilla.app/LaGrilla > ReleaseArtifacts/binary-uuid.txt
xcrun dwarfdump --uuid ReleaseArtifacts/LaGrilla-unsigned.xcarchive/dSYMs/LaGrilla.app.dSYM > ReleaseArtifacts/dsym-uuid.txt
diff -u ReleaseArtifacts/binary-uuid.txt ReleaseArtifacts/dsym-uuid.txt >/dev/null || python3 - <<'PY'
import pathlib,re
a,b=[re.findall(r'UUID: ([0-9A-F-]+)',pathlib.Path('ReleaseArtifacts/'+x+'-uuid.txt').read_text()) for x in ['binary','dsym']]
assert a and a==b,'Binary and dSYM UUID mismatch'
PY
python3 scripts/release/audit_binary.py ReleaseArtifacts/LaGrilla-unsigned.xcarchive/Products/Applications/LaGrilla.app/LaGrilla --report ReleaseArtifacts/binary-audit.log
python3 scripts/release/package_sideload_ipa.py --app ReleaseArtifacts/LaGrilla-unsigned.xcarchive/Products/Applications/LaGrilla.app --output ReleaseArtifacts/LaGrilla-unsigned.ipa --source-sha "$(git rev-parse HEAD)"
ditto -c -k --sequesterRsrc --keepParent ReleaseArtifacts/LaGrilla-unsigned.xcarchive ReleaseArtifacts/LaGrilla-unsigned-archive.zip
echo 'Unsigned archive and sideload IPA verified. Testers sign the IPA on their own laptop; distribution uses its separate workflow.'
