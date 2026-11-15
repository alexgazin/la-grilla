#!/usr/bin/env python3
"""Fail closed on version, store text and bundled privacy-manifest drift."""
import argparse,pathlib,plistlib,re
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--app',type=pathlib.Path);a=p.parse_args()
source=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
manifest=plistlib.loads((ROOT/'Resources/PrivacyInfo.xcprivacy').read_bytes())
assert manifest['NSPrivacyTracking'] is False and not manifest['NSPrivacyTrackingDomains'] and not manifest['NSPrivacyCollectedDataTypes']
reasons={x['NSPrivacyAccessedAPIType']:x['NSPrivacyAccessedAPITypeReasons'] for x in manifest['NSPrivacyAccessedAPITypes']}
assert reasons=={'NSPrivacyAccessedAPICategoryUserDefaults':['CA92.1'],'NSPrivacyAccessedAPICategorySystemBootTime':['35F9.1']}
assert source['ITSAppUsesNonExemptEncryption'] is False
assert source['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False
assert source['UIBackgroundModes']==['audio']
project=(ROOT/'project.yml').read_text();version=re.search(r"MARKETING_VERSION: '([^']+)'",project)[1];build=re.search(r"CURRENT_PROJECT_VERSION: '(\d+)'",project)[1]
generator=(ROOT/'scripts/generate_project.py').read_text();pbx=(ROOT/'LaGrilla.xcodeproj/project.pbxproj').read_text()
assert f"MARKETING_VERSION='{version}'" in generator and f"CURRENT_PROJECT_VERSION='{build}'" in generator
assert f'"MARKETING_VERSION" = "{version}"' in pbx and f'"CURRENT_PROJECT_VERSION" = "{build}"' in pbx
limits={'name':30,'subtitle':30,'keywords':100,'promotional_text':170,'description':4000,'release_notes':4000}
for locale in ['en-US','ru']:
 for field,limit in limits.items():
  value=(ROOT/f'docs/store/{locale}/{field}.txt').read_text().strip();assert value and len(value)<=limit,(locale,field,len(value),limit)
 for field in ['privacy_url','support_url','marketing_url']:
  assert (ROOT/f'docs/store/{locale}/{field}.txt').read_text().startswith('https://')
if a.app:
 info=plistlib.loads((a.app/'Info.plist').read_bytes());assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==build
 assert info['CFBundleIdentifier']=='com.alexgazin.LaGrilla'
 assert plistlib.loads((a.app/'PrivacyInfo.xcprivacy').read_bytes())==manifest
 assert (a.app/info['CFBundleExecutable']).is_file() and (a.app/'Assets.car').is_file()
 assert (a.app/'en.lproj/Localizable.strings').is_file() and (a.app/'ru.lproj/Localizable.strings').is_file()
print(f'Release audit passed: {version} ({build}), EN/RU store limits, encryption declaration and two required-reason API categories'+(', archived binary/resources verified' if a.app else ''))
