# R10 release candidate evidence

Candidate: **1.0.0 (11)**, `com.alexgazin.LaGrilla`, iPhone / iOS 18+. Current acceptance uses **Xcode 26.3 / iOS 26.2 SDK**; the selected simulator runtime is recorded in CI. Apple's Xcode 26 / iOS 26 SDK submission requirement has applied since April 28, 2026. See the [release procedure](release/RELEASE.md).

## Final software acceptance

- Verified app/UI source: `ecfc9b9`. [Verification and Russian recapture run 43689852307](https://github.com/alexgazin/la-grilla/actions/runs/43689852307) passed all three jobs: 64 Swift tests, independent export readers, 11 audio suites, both SDK builds, 19 native Studio flows, two Russian capture tests (21 native tests total), and the optimized device archive. Thirteen new Russian frames replace the affected images and add narrow-screen coverage. The preceding MIDI fix source `a0cf073` passed all checks, including 19 Studio flows, in [run 43688387197](https://github.com/alexgazin/la-grilla/actions/runs/43688387197).
- Local checks on that implementation pass: **64 Swift tests, 11 C++ suites**, release configuration and 466-key EN/RU presentation audits. Render stress fixtures remain finite, with zero measured C++ `new`/`new[]` calls inside the tested render callbacks.
- English native screenshot source: `e1d13da`. [Complete capture run 43686737452](https://github.com/alexgazin/la-grilla/actions/runs/43686737452) passed all three jobs: 64 Swift tests, 11 C++ suites, both SDK builds, 19 Studio flows and three capture tests (22 native tests across Pro Max and SE). All 46 original PNGs and twelve Store frames were exported and validated. Visual review found missing Russian conditional-text translations; affected Russian frames are replaced from source `ecfc9b9`, while unchanged English frames retain their original source/hash.
- Earlier source `3380e38` passed the complete iOS 18.5 simulator suite in [run 43682379245](https://github.com/alexgazin/la-grilla/actions/runs/43682379245). This is backward-compatibility evidence; the release archive must use the current SDK.

## Release fixes and artifacts

- Stop/Panic is processed before chasing active notes onto a changed output destination. Zero-length remaining gates cannot produce a new NoteOn. At a shared sample boundary, the preceding NoteOff is sent before a same-pitch retrigger. Regressions reproduced all three defects against the previous implementation and pass after the fix; the suite also covers Panic during handover.
- Endpoint discovery checks both endpoint and parent-device offline flags, so a disconnected device retained by a MIDI driver cannot remain the selected online endpoint. Actual USB/BLE unplug timing remains a physical-device check.
- Visual review found 13 missing Russian keys inside conditional labels/badges, plus an unlocalized Master fallback and compact quantization option. The presentation audit now parses balanced localized expressions and badges; it fails on the previous missing keys. The Russian UI flow checks the actual rendered Jam hints and rejects their English fallbacks. Russian Pro Max and 375-point captures are regenerated.
- The Perform regression scrolls until the status header is visible. Its previous fixed third downward swipe could dismiss the sheet after reaching the top; the main R9 run exposed that test-harness failure.
- Release auditing verifies version/build, embedded privacy/resources/executable, current SDK fields and matching dSYM UUID. The artifact is an **unsigned archive**, not an installable IPA.
- Store metadata, privacy policy, support and review notes are prepared in English and Russian. Twelve Store screenshots must be original 1320 × 2868 Pro Max PNGs; preparation rejects a missing or differently sized frame and copies the originals unchanged.
- Signing profile installation uses the current Xcode 16+ Developer/UserData path (also used by [Fastlane’s profile installer](https://github.com/fastlane/fastlane/blob/master/fastlane_core/lib/fastlane_core/provisioning_profile.rb)). A pre-existing identical profile is preserved. Shell syntax checks pass; actual certificate/profile signing remains unexercised.
- Signing and optional TestFlight upload run only on `main`, require successful native/SDK/archive checks for that exact commit, validate the owner's distribution profile and use temporary signing files/keychain. No credentials are stored in the app or repository.

## Design and external acceptance still open

The user requested a stronger, simpler and distinctive 2026 design after this technical candidate. **R8.1 is an explicit open release gate** in [ROADMAP.md](../ROADMAP.md). Its OpenArt direction and native implementation must be reviewed, captured and tested before the Store images or archive are treated as the final visual RC. The final evidence/signing-path follow-up leaves this tested app/UI/audio/domain source unchanged.


No signed IPA, TestFlight installation, App Review submission or production publication has been performed. Apple signing/App Store Connect credentials and a physical iPhone/USB/BLE/DAW setup are not available through this environment. Record actual measurements in [DEVICE_ACCEPTANCE.md](release/DEVICE_ACCEPTANCE.md): 30-minute load/thermal/dropout sessions, touch/audio/MIDI timing, route/interruption matrix, human voice quality, USB/BLE sustain/unplug and imports in two DAWs. These remain release gates; simulator and host results do not fill those fields.
