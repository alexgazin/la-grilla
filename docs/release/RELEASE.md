# Release procedure

Current implementation candidate: **1.0.0 (20), schema10**, iPhone/iOS18+, bundle `com.alexgazin.LaGrilla`, in [PR21](https://github.com/alexgazin/la-grilla/pull/21). **Functional alpha; exact-source full software and physical acceptance are open.** The published [manual-test IPA19](../../Builds/Testing/README.md) is an unsigned test candidate from its own source, not accepted distribution signing. Use [CURRENT](CURRENT.md) for actual source/run/build outcomes. Candidate20 adds complete imported-project listening ranges to the new sketch/notation/reliability work, and accurately describes brief capture-setup/finish interruptions. No physical or zero-gap result is implied.

The exact base `main` 16 `9dfec7e` passed [43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): all three verification jobs SUCCESS, 51 functional native PASS / 0 FAIL / 1 diagnostic SKIP. The previous branch `01fb8b7` and partial 17 failures remain in the [journal](../IMPLEMENTATION_LOG.md); main 16 acceptance does not validate new 17 changes. Before distribution, the exact release source must have its own complete required software verification and installed-device acceptance. The owner's reported crash/audio problems remain in [DEVICE_ACCEPTANCE](DEVICE_ACCEPTANCE.md). This alpha summary does not authorize distribution.

Previous software candidate **1.0.0 (15)** added native launch/welcome surfaces, clearer settings and a bootstrap/save guard; the existing brand icon is retained. Source `838b4847c63d97f1ee57fd9a423e6489746603a4`, [full verification 43812214574](https://github.com/alexgazin/la-grilla/actions/runs/43812214574), passed all three jobs, 118 Swift tests / 19 suites, 15 C++ suites, 623 EN/RU keys and 46 functional native methods; one opt-in diagnostic was skipped. The subsequent presented-Form appearance fix is source `014a00b9d6069e55150ae1f794810216cea63be3`, [focused run 43819149979](https://github.com/alexgazin/la-grilla/actions/runs/43819149979): Theme and Welcome both passed. That focused run is not a new full 46-method verification or proof for the final exact `main` commit.

[Product finishing](../PRODUCT_FINISHING.md), [three original EN welcome/settings frames](../../Screenshots/ProfessionalShell/README.md) and the [132.2-second working-app demonstration](../../Media/WorkingDemo/README.md) keep their own sources and acceptance scope. The film shows genuine UI actions and recorded app output; its source workflow's post-roll coverage failure remains documented and is not converted into release acceptance.

Historical **1.0.0 (14)** [C1–C7 acceptance](C7_ACCEPTANCE.md) remains source `77fb72ab82cd800eb8131136628c416ad83c9046`, [full run 43771988471](https://github.com/alexgazin/la-grilla/actions/runs/43771988471): all three verification jobs, 44 functional flows, three capture methods and 73 reviewed original PNGs. [Implementation log](../IMPLEMENTATION_LOG.md) preserves the detailed stages/failures; [Design QA](../DESIGN_QA.md) retains the historical version12 design acceptance. Exact-main checks remain mandatory before distribution. Formal physical acceptance, an identified and accepted installed candidate, TestFlight and App Store publication remain unperformed; the owner's local installation reports are separate defect evidence.

## Current Apple submission requirement

Checked November 15, 2026: [Apple requires Xcode 26 and iOS 26 SDK or newer since April 28, 2026](https://developer.apple.com/news/upcoming-requirements/). Release and distribution CI explicitly select Xcode 26.3 on macOS 15; archive validation checks the embedded `DTXcode` and `DTSDKName` fields and rejects older SDKs. Native release acceptance selects the newest installed iOS 26 runtime supported by that SDK, with both Pro Max and 375-point SE on the same runtime. The deployment target remains iOS 18. Prior iOS 18.5 checks are compatibility evidence, not a substitute for a current-SDK release archive. Recheck Apple requirements before a later release.

## Reproducible checks

`python3 scripts/generate_project.py` regenerates the committed Xcode project without requiring XcodeGen. `project.yml` and the generator must keep identical version/build settings; `audit_release.py` checks them. After any uploaded build, increment the build number in both sources and regenerate before another upload.

The main verification workflow runs domain/export readers, audio suites, EN/RU/presentation/release audits, both iOS SDK builds, native UI flows, real 375-point and Pro Max screenshots, and an optimized **unsigned** device archive. The archive job verifies the embedded privacy manifest, localized resources, executable, asset catalog, version and matching dSYM UUID. The `unsigned-release-archive` artifact contains the archive plus a CRC/SHA/file-verified unsigned IPA and receipt. The archive itself cannot be installed; the unsigned IPA requires tester signing (for example Sideloadly with a Personal Team). It is not a signed App Store build.

Store text is in `docs/store/en-US` and `docs/store/ru`; field lengths are checked. Native store images are captured by XCTest on an iPhone 16 Pro Max simulator at **1320 × 2868**, without resizing, fabricated UI or generated screenshots:

```sh
python3 scripts/release/prepare_store_screenshots.py Screenshots/OriginalVision Screenshots/AppStore
```

The existing `Screenshots/OriginalVision` and Store copies retain their accepted version 14 / `77fb72a` source. For the current candidate, run Store preparation only after a complete matching capture has succeeded and been reviewed. Use English and Russian images with their corresponding listing. Record actual capture SHA/run/hashes against the release source; regenerate after a visible change. The separate version 15 [ProfessionalShell frames](../../Screenshots/ProfessionalShell/README.md) are not a complete new Store batch. Do not relabel historical Design2026/C2/version14/version15 images or a partial QA export as captures of a newer candidate. OpenArt provenance concerns the app icon, not the native screenshots.

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

Run **Signed archive and optional TestFlight upload** on `main`. It requires successful `ios`, `iphone` and `release-archive` checks from one coherent verification run for the exact source commit. Full push and `[ui-only]` runs execute every functional native class; `[integration-only]`, `[input-diagnostic]`, `[ru-capture]` and `[device-only]` pushes cannot authorize signing. An actual `ios.yml` manual verification run is full because that workflow has no test-scope inputs. The distribution workflow's own manual trigger or `upload_testflight` input does not turn a focused verification into full acceptance. A documentation-only skipped commit must first get a complete verification run. By default the workflow creates a signed IPA; selecting `upload_testflight` also validates and uploads it. The profile is installed in Xcode 16+’s `~/Library/Developer/Xcode/UserData/Provisioning Profiles` directory. Temporary signing files/keychain are deleted; an identical pre-existing profile is reused and preserved. The workflow never submits the app for App Review or releases it to production.

The profile is checked for team/bundle match, expiry and distribution entitlements before signing. The archive is signed with the owner's certificate, verified, exported using `app-store-connect`, and audited again. Successful upload is followed by Apple's asynchronous processing; install the resulting TestFlight build for device QA. No signing or upload has been exercised without the owner's credentials.

## Final acceptance before App Review

Record results in [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md). Resolve blocker/critical defects against the installed RC, not a later untested build. Verify:

- 30-minute sessions on the minimum supported physical iPhone and a recent device; P1/P2/P3 projects, thermal/CPU/memory, audible dropouts and touch/audio timing.
- Speaker, wired/USB and Bluetooth routes; headphones unplug, call/Siri interruption, screen lock, background Play/Pause/Stop, media reset and denied microphone/speech permissions.
- USB and BLE MIDI input/output, sustain, channel filtering, Learn, disconnect/reconnect and Panic. Compare actual events/timing with two DAWs; check exported MIDI/WAV/stems and portable voice assets.
- Save/reopen/kill/recovery, storage failure, sharing/cancellation, language/appearance, Dynamic Type, VoiceOver and portrait/landscape controls.
- Actual iOS 18 startup without Foundation Models; shared-graph human voice against a referenced note corpus; live structural/mix/MIDI continuity; and real Foundation Models generation/latency/cancellation plus unavailable-device/model/language fallbacks. Keep these physical/model results separate from deterministic fixtures.
- Public support/privacy URLs, actual store text/screenshots, data-not-collected answers, current age-rating questionnaire, content rights, export compliance, pricing/availability (including opting out of untested Mac/visionOS compatibility) and the owner's legal seller information.

App Review notes: no login or demo account; start from the included demo. Grid opens harmony/notes/Assistant; More opens voice, Perform and MIDI. Play starts audio; stopping releases notes; record/microphone access is explicit. USB/BLE require a compatible peripheral. Optional on-device AI needs an eligible iPhone with iOS 26, enabled Apple Intelligence, a ready model and a supported selected language; local Commands work without that model, including on iOS 18. Dictation separately requires supported on-device speech recognition. Voice conversion is monophonic, can record over the backing loop and needs review. Prompts, music and recordings are processed on the device. Original synthesized instruments can sound different from external MIDI instruments.

Only after the signed RC passes this matrix: choose the processed build in App Store Connect, complete the listing and questionnaire, submit for review, then verify the installed production build after approval. Apple account setup, physical measurements and Apple's review cannot be completed by an unsigned cloud simulator build.
