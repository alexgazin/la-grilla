#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 scripts/release/assert_sdk.py
: "${GRILLA_CERTIFICATE_BASE64:?Missing distribution certificate}"
: "${GRILLA_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${GRILLA_PROFILE_BASE64:?Missing App Store provisioning profile}"
: "${GRILLA_TEAM_ID:?Missing Apple team ID}"
GRILLA_SIGNING_TEMP=$(mktemp -d "${RUNNER_TEMP:-/tmp}/grilla-signing.XXXXXX")
GRILLA_KEYCHAIN="$GRILLA_SIGNING_TEMP/signing.keychain-db"
GRILLA_KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
GRILLA_PROFILE_PATH=''
cleanup(){ security delete-keychain "$GRILLA_KEYCHAIN" >/dev/null 2>&1 || true; if test -n "$GRILLA_PROFILE_PATH"; then rm -f "$GRILLA_PROFILE_PATH"; fi; rm -rf "$GRILLA_SIGNING_TEMP"; }
trap cleanup EXIT
export GRILLA_SIGNING_TEMP
python3 - <<'PY'
import os,pathlib,base64
p=pathlib.Path(os.environ['GRILLA_SIGNING_TEMP'])
for name,key in [('distribution.p12','GRILLA_CERTIFICATE_BASE64'),('profile.mobileprovision','GRILLA_PROFILE_BASE64')]:
 f=p/name;f.write_bytes(base64.b64decode(os.environ[key],validate=True));f.chmod(0o600)
PY
security cms -D -i "$GRILLA_SIGNING_TEMP/profile.mobileprovision" > "$GRILLA_SIGNING_TEMP/profile.plist"
python3 - <<'PY'
import os,pathlib,plistlib,datetime
p=pathlib.Path(os.environ['GRILLA_SIGNING_TEMP']);d=plistlib.loads((p/'profile.plist').read_bytes());team=os.environ['GRILLA_TEAM_ID']
assert team in d['TeamIdentifier'] and d['Entitlements']['application-identifier']==team+'.com.alexgazin.LaGrilla'
assert not d['Entitlements'].get('get-task-allow',False) and not d.get('ProvisionedDevices') and not d.get('ProvisionsAllDevices',False)
assert d['ExpirationDate']>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Expired profile'
(p/'profile-name').write_text(d['Name']);(p/'profile-uuid').write_text(d['UUID'])
options={'method':'app-store-connect','signingStyle':'manual','teamID':team,'manageAppVersionAndBuildNumber':False,'uploadSymbols':True,'provisioningProfiles':{'com.alexgazin.LaGrilla':d['Name']}}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
GRILLA_PROFILE_NAME=$(cat "$GRILLA_SIGNING_TEMP/profile-name")
GRILLA_PROFILE_UUID=$(cat "$GRILLA_SIGNING_TEMP/profile-uuid")
# Xcode 16+ (including the selected Xcode 26) uses the Developer/UserData location.
GRILLA_PROFILE_DIRECTORY="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$GRILLA_PROFILE_DIRECTORY"
GRILLA_PROFILE_CANDIDATE="$GRILLA_PROFILE_DIRECTORY/$GRILLA_PROFILE_UUID.mobileprovision"
if test -e "$GRILLA_PROFILE_CANDIDATE"; then
  # Reuse an identical installed profile without deleting it during cleanup.
  cmp "$GRILLA_SIGNING_TEMP/profile.mobileprovision" "$GRILLA_PROFILE_CANDIDATE"
else
  install -m 600 "$GRILLA_SIGNING_TEMP/profile.mobileprovision" "$GRILLA_PROFILE_CANDIDATE"
  GRILLA_PROFILE_PATH="$GRILLA_PROFILE_CANDIDATE"
fi
security create-keychain -p "$GRILLA_KEYCHAIN_PASSWORD" "$GRILLA_KEYCHAIN"
security set-keychain-settings -lut 21600 "$GRILLA_KEYCHAIN"
security unlock-keychain -p "$GRILLA_KEYCHAIN_PASSWORD" "$GRILLA_KEYCHAIN"
security import "$GRILLA_SIGNING_TEMP/distribution.p12" -P "$GRILLA_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$GRILLA_KEYCHAIN" >/dev/null
unset GRILLA_CERTIFICATE_BASE64 GRILLA_CERTIFICATE_PASSWORD GRILLA_PROFILE_BASE64
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$GRILLA_KEYCHAIN_PASSWORD" "$GRILLA_KEYCHAIN" >/dev/null
security list-keychains -d user -s "$GRILLA_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
mkdir -p ReleaseArtifacts
python3 scripts/release/audit_release.py
xcodebuild -project LaGrilla.xcodeproj -scheme LaGrilla -configuration Release -destination 'generic/platform=iOS' -archivePath ReleaseArtifacts/LaGrilla.xcarchive CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$GRILLA_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$GRILLA_PROFILE_NAME" CODE_SIGN_IDENTITY='Apple Distribution' archive | tee ReleaseArtifacts/signed-archive.log
GRILLA_APP=ReleaseArtifacts/LaGrilla.xcarchive/Products/Applications/LaGrilla.app
codesign --verify --deep --strict "$GRILLA_APP"
python3 scripts/release/audit_release.py --app "$GRILLA_APP"
xcodebuild -exportArchive -archivePath ReleaseArtifacts/LaGrilla.xcarchive -exportOptionsPlist "$GRILLA_SIGNING_TEMP/ExportOptions.plist" -exportPath ReleaseArtifacts/Export | tee ReleaseArtifacts/export.log
test -f ReleaseArtifacts/Export/LaGrilla.ipa
