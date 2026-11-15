# Release procedure

Current candidate: **1.0.0 (12)**, iPhone / iOS 18+, bundle `com.alexgazin.LaGrilla`. Design 2026 is under native acceptance. This is a release procedure, not evidence of an App Store upload.

## Current Apple submission requirement

Checked November 15, 2026: [Apple requires Xcode 26 and iOS 26 SDK or newer since April 28, 2026](https://developer.apple.com/news/upcoming-requirements/). Release and distribution CI explicitly select Xcode 26.3 on macOS 15; archive validation checks the embedded `DTXcode` and `DTSDKName` fields and rejects older SDKs. Native release acceptance selects the newest installed iOS 26 runtime supported by that SDK, with both Pro Max and 375-point SE on the same runtime. The deployment target remains iOS 18. Prior iOS 18.5 checks are compatibility evidence, not a substitute for a current-SDK release archive. Recheck Apple requirements before a later release.

## Reproducible checks

`python3 scripts/generate_project.py` regenerates the committed Xcode project without requiring XcodeGen. `project.yml` and the generator must keep identical version/build settings; `audit_release.py` checks them. After any uploaded build, increment the build number in both sources and regenerate before another upload.

The main verification workflow runs domain/export readers, audio suites, EN/RU/presentation/release audits, both iOS SDK builds, native UI flows, real 375-point and Pro Max screenshots, and an optimized **unsigned** device archive. The archive job verifies the embedded privacy manifest, localized resources, executable, asset catalog, version and matching dSYM UUID. The `unsigned-release-archive` artifact is for review and signing preparation; it cannot be installed on an iPhone.

Store text is in `docs/store/en-US` and `docs/store/ru`; field lengths are checked. Native store images are captured by XCTest on an iPhone 16 Pro Max simulator at **1320 × 2868**, without resizing, fabricated UI or generated screenshots:

```sh
python3 scripts/release/prepare_store_screenshots.py Screenshots/Design2026 Screenshots/AppStore
```

Use English and Russian images with their corresponding listing. Inspect the final images and make sure their source SHA matches the release binary; regenerate after a visible change. OpenArt provenance concerns the app icon, not the native screenshots.

## Signing / TestFlight

Create an App Store Connect app record for the bundle ID, then configure the repository's **app-store** environment with these secrets. Certificates and private keys must stay in GitHub secrets, never in an issue, commit, artifact or chat:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Owner's Apple Developer team ID |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 of an Apple Distribution certificate **with its private key** |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | P12 export password |
| `APP_STORE_PROFILE_BASE64` | Base64 App Store distribution provisioning profile for this exact bundle/team |
| `ASC_API_KEY_ID` | App Store Connect API key ID; upload only |
| `ASC_API_ISSUER_ID` | API issuer UUID; upload only |
| `ASC_API_PRIVATE_KEY_BASE64` | Base64 of the matching `.p8`; upload only |

Generate single-line base64 on a Mac with `base64 -i input-file | tr -d '\n'`. The environment can use GitHub's own reviewers if the owner configures them; this repository adds no mandatory approval request.

Run **Signed archive and optional TestFlight upload** on `main`. It requires successful `ios`, `iphone` and `release-archive` checks for the exact source commit. A documentation-only skipped commit must first get a complete verification run. By default the workflow creates a signed IPA; selecting `upload_testflight` also validates and uploads it. The profile is installed in Xcode 16+’s `~/Library/Developer/Xcode/UserData/Provisioning Profiles` directory. Temporary signing files/keychain are deleted; an identical pre-existing profile is reused and preserved. The workflow never submits the app for App Review or releases it to production.

The profile is checked for team/bundle match, expiry and distribution entitlements before signing. The archive is signed with the owner's certificate, verified, exported using `app-store-connect`, and audited again. Successful upload is followed by Apple's asynchronous processing; install the resulting TestFlight build for device QA. No signing or upload has been exercised without the owner's credentials.

## Final acceptance before App Review

Record results in [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md). Resolve blocker/critical defects against the installed RC, not a later untested build. Verify:

- 30-minute sessions on the minimum supported physical iPhone and a recent device; P1/P2/P3 projects, thermal/CPU/memory, audible dropouts and touch/audio timing.
- Speaker, wired/USB and Bluetooth routes; headphones unplug, call/Siri interruption, screen lock, background Play/Pause/Stop, media reset and denied microphone/speech permissions.
- USB and BLE MIDI input/output, sustain, channel filtering, Learn, disconnect/reconnect and Panic. Compare actual events/timing with two DAWs; check exported MIDI/WAV/stems and portable voice assets.
- Save/reopen/kill/recovery, storage failure, sharing/cancellation, language/appearance, Dynamic Type, VoiceOver and portrait/landscape controls.
- Public support/privacy URLs, actual store text/screenshots, data-not-collected answers, current age-rating questionnaire, content rights, export compliance, pricing/availability (including opting out of untested Mac/visionOS compatibility) and the owner's legal seller information.

App Review notes: no login or demo account; start from the included demo. Grid opens harmony/notes/Assistant; More opens voice, Perform and MIDI. Play starts audio; stopping releases notes; record/microphone access is explicit. USB/BLE require a compatible peripheral. Dictation requires a supported local speech model; typed commands remain available. Voice conversion is monophonic and needs review. Original synthesized instruments can sound different from external MIDI instruments.

Only after the signed RC passes this matrix: choose the processed build in App Store Connect, complete the listing and questionnaire, submit for review, then verify the installed production build after approval. Apple account setup, physical measurements and Apple's review cannot be completed by an unsigned cloud simulator build.
