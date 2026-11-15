#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${GRILLA_ASC_KEY_ID:?Missing App Store Connect key ID}"
: "${GRILLA_ASC_ISSUER_ID:?Missing App Store Connect issuer ID}"
: "${GRILLA_ASC_PRIVATE_KEY_BASE64:?Missing App Store Connect private key}"
[[ "$GRILLA_ASC_KEY_ID" =~ ^[A-Za-z0-9]{10}$ ]]
GRILLA_PRIVATE_KEY="$HOME/private_keys/AuthKey_${GRILLA_ASC_KEY_ID}.p8"
test ! -e "$GRILLA_PRIVATE_KEY"
mkdir -p "$HOME/private_keys"
export GRILLA_PRIVATE_KEY
trap 'rm -f "$GRILLA_PRIVATE_KEY"' EXIT
python3 - <<'PY'
import os,pathlib,base64
p=pathlib.Path(os.environ['GRILLA_PRIVATE_KEY']);p.write_bytes(base64.b64decode(os.environ['GRILLA_ASC_PRIVATE_KEY_BASE64'],validate=True));p.chmod(0o600)
PY
unset GRILLA_ASC_PRIVATE_KEY_BASE64
xcrun altool --validate-app --type ios --file ReleaseArtifacts/Export/LaGrilla.ipa --apiKey "$GRILLA_ASC_KEY_ID" --apiIssuer "$GRILLA_ASC_ISSUER_ID"
xcrun altool --upload-app --type ios --file ReleaseArtifacts/Export/LaGrilla.ipa --apiKey "$GRILLA_ASC_KEY_ID" --apiIssuer "$GRILLA_ASC_ISSUER_ID"
