# La Grilla development

Native iPhone studio: iOS 18+, Swift 6, SwiftUI, AVAudioEngine and a C++17 render kernel. The [archived product specification](PRODUCT_SPECIFICATION.md) and [DESIGN_PROMPT](../DESIGN_PROMPT.txt) preserve the original requirements; the [README](../README.md) presents the current app, and delivery status is in [ROADMAP](../ROADMAP.md) and [release QA](RELEASE_QA.md). Signing and publishing are described in [release procedure](release/RELEASE.md).


## Run on your own iPhone

Use **Xcode 26.3 or newer** for the complete feature set and release workflow;
the iPhone can run **iOS 18 or newer**. Local development builds are also checked
with Xcode **16.4** and **26.0.1**. The Xcode version must support the OS installed
on the connected phone; source compatibility does not establish device pairing.

### Xcode compatibility

| Toolchain | Recorded build scope |
| --- | --- |
| Xcode 26.3 | Complete iPhone Debug build and optimized Release archive, including resources and binary audits. This remains the release CI baseline. |
| Xcode 26.0.1 / SDK 26.0 | Complete unsigned iPhone Debug app, including all resources. |
| Xcode 16.4 / SDK 18.5 | Complete unsigned iPhone Debug app, including all resources. Uses the existing StudioSurface fallback and does not compile FoundationModels. |
| Xcode 16.2 / Swift 6.0.3 / SDK 18.2 — historical probe | Earlier scoped checks compiled/linked the actual Swift/C++ target with the asset catalog and launch storyboard omitted. That historical PASS does **not** validate packaging, icons, launch resources or installation, and is no longer a default matrix row. |

The current default [compatibility workflow](../.github/workflows/xcode-compatibility.yml)
builds complete apps with all resources on **16.4 / 26.0.1**. After the earlier
16.2 scoped PASS, [main run 43836782541](https://github.com/alexgazin/la-grilla/actions/runs/43836782541)
failed because the hosted image could not supply a generic iOS destination:
`iOS 18.2 is not installed`. Source `01fb8b7` adds an optional manual
`legacy_xcode_16_2` input: it installs and verifies the iOS 18.2 runtime, then
attempts a **full-resource** 16.2 build. This new optional path has not yet been
executed; it does not inherit acceptance from the historical source-only check.

The older SDK build retains local Commands, audio and editing; it does not
contain the optional FoundationModels adapter, even if later installed on an
eligible iOS 26 phone. Current SDK builds retain their existing Glass and
Reduce Transparency behavior. Compatibility builds publish logs, not installable
IPAs, and do not replace current-SDK distribution checks. The original failed
16.2 resource attempts and successful scoped checks are recorded in the
[implementation log](IMPLEMENTATION_LOG.md).

### Install and run

1. Pull the latest `main` and open the committed `LaGrilla.xcodeproj` in Xcode. Select the **LaGrilla** scheme and app target.
2. In **Xcode → Settings → Accounts**, add your Apple ID. In the app target's **Signing & Capabilities**, enable **Automatically manage signing** and select your own **Team**.
3. Connect an iPhone running **iOS 18 or later** by USB. Complete pairing and **Trust** prompts; enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode requests it.
4. Select that iPhone as the run destination and press **Run**. Xcode builds and signs a local development app. If Xcode says the bundle identifier is unavailable for your team, use a unique identifier for your local build.

A free **Personal Team** can support local development installation; its provisioning normally expires after seven days and can be renewed by running from Xcode again. App Store/TestFlight distribution uses the owner's distribution certificate and provisioning profile. The unsigned CI device archive is evidence of compilation, **not an installable IPA**. Actual installed-device results belong in [device acceptance](release/DEVICE_ACCEPTANCE.md); opening the project does not fill those pending fields.

### Local build troubleshooting

- **“Signing requires a development team”:** choose your **Personal Team** in
  the **LaGrilla app target → Signing & Capabilities → Team**, leaving automatic
  signing enabled. Personal Team is a valid development team; paid Apple Developer
  Program membership is not required for this local installation.
- **“Expected type” in the microphone scheduling parameters:** pull current
  `main`, which spells the global-actor closure types with an explicit separator,
  for example `(@MainActor (Double) -> Double?)?`. Check **Xcode → About Xcode**
  against the toolchain requirement above. If old diagnostics remain after the
  update, use **Product → Clean Build Folder** (Shift–Command–K), then Run.
- **“Unable to type-check this expression in reasonable time” in ChordTile:**
  pull current `main`; its note-preview layout computes explicitly typed values
  before building views. Clean Build Folder if the old diagnostic remains.
- **Keep local signing choices:** the checked-in project intentionally has no
  development team. Regenerating it with `scripts/generate_project.py` resets
  that field; select your Personal Team again afterward. A normal source update
  does not require project regeneration. Select Team on the **LaGrilla app target**
  for **All** configurations, not only on the project or test target. The ChordTile
  compatibility patch does not modify the checked-in signing configuration.

On a Mac with Xcode 26.3 (or an App Store-supported newer toolchain) selected:

```sh
python3 scripts/generate_project.py
open LaGrilla.xcodeproj
swift test --package-path Packages/MusicDomain
bash scripts/test_audio.sh
python3 scripts/audit_presentation.py
python3 scripts/release/audit_release.py
xcodebuild -project LaGrilla.xcodeproj -scheme LaGrilla \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
bash scripts/release/archive_unsigned.sh
```

The committed project is generated by the repository's Python script; XcodeGen is optional through `project.yml`. Update both version sources together. Local device signing uses your selected development team; distribution requires the owner's certificate/profile. No credentials are checked in. An unsigned simulator app or device archive cannot be installed as a distribution IPA.

On Linux, `scripts/test_domain.sh` supports `GRILLA_SWIFT_BIN` for a locally installed Swift 6 toolchain. `scripts/test_audio.sh` supports `GRILLA_CXX_BIN` and uses no Apple frameworks. Swift frontend parsing can check UI syntax on Linux, but only native SDK compilation and simulator/device execution establish iOS behavior.

| Directory | Responsibility |
| --- | --- |
| `Packages/MusicDomain` | Schema 8, notes/chords/custom formulas/sections, validation/history, compiler, harmony/whole-song proposals, clip operations, local commands, voice analysis, project store, safe portable archives, MIDI/WAV/stems/finite performance exports |
| `Packages/MusicDomain/Sources/AudioDSP` | Bounded render kernel, triple snapshots, synthesized versioned instruments, sample clock, master effects, performance capture/replay and timestamped MIDI queues |
| `AudioRuntime` | AVAudioEngine, on-device dictation, microphone recording, Core MIDI/BLE adapters, performance and system transport controllers |
| `App`, `Features` | Shared session, autosave/recovery, Grid/Jam/Mixer/editors, explicit capture ownership and native share/import flows |
| `Tests`, `UITests` | Host DSP/stress tests and actual iOS user-flow/screenshot tests |
| `Resources`, `Design` | EN/RU strings/plurals/purpose strings, adaptive colors, privacy manifest, icon and OpenArt provenance |
| `Screenshots/Design2026`, `Screenshots/C2`, `Screenshots/OriginalVision`, `Screenshots/AppStore` | Historical and current original native PNG evidence and unchanged localized Store copies, with per-source/run/dimensions/SHA-256 records |
| `docs/release`, `docs/store` | Hardware acceptance record, importable P1/P2/P3 projects, signing procedure, privacy/support and localized store metadata |

Up to 8 tracks, 8 sections and 64 bars; PPQ 960. Harmony/Drums are first, with optional root Bass and independent Melody tracks. All music uses the same compiler for live playback, MIDI and offline audio. New preset version 2 uses rate-independent one-shots and bounded retirement tails; migrations preserve preset version 1, including frozen performance sources.

The render callback performs no file/network access, locking, actor work or dynamic allocation. Control data crosses bounded queues or triple-owned snapshots. Musical snapshots adopt notes, track layout/presets, mix and FX together at a musical boundary; controls for that generation wait for its adoption. Same-layout mixer gestures remain responsive at buffer boundaries. Stable UUID routing resolves in the callback, including keyed previews. MIDI input preserves source/channel/timestamps and does not echo to output. The serial output worker uses conditional destination activation; current input Off/output None does not wait for a structural edit. Panic, disconnect and destination changes release notes.

Projects live in `Documents/Projects/<UUID>.grilla` with atomic `manifest.json`, a prior valid backup and optional validated original voice assets. Autosave is debounced; completed takes/lifecycle changes checkpoint immediately. Source originals remain attached to portable exports. Import creates an independent project, validates limits/path/CRC/hash/schema and never extracts arbitrary paths. See [schema](SCHEMA.md).

The Assistant supports local RU/EN commands and optional Foundation Models guided generation on eligible iOS 26 devices. Availability, model readiness and selected language are checked; Commands remain available without the model. Section/whole-song proposals are scoped to a project/revision and applied as one Undo transaction. No cloud service or client API credential is used. Dictation uses only on-device Apple Speech; unavailable speech models fall back to typed input. Voice-to-MIDI is monophonic, preserves original audio and exposes uncertainty/correction. Synthetic fixtures do not establish human-voice or model quality.

Playback can continue in the background after the user starts it, with system Play/Pause/Stop. Idle background graphs stop and release MIDI/audio resources. A single microphone consumer owns the shared engine input tap; output playback and MIDI continue. A bounded SPSC ring moves PCM to serial CAF/conversion/Speech workers. Voice placement is scheduled from a fresh clock after route preparation and bounded to the target section/loop edge. Background/interruption stops capture; returning does not automatically resume recording. A changed project requires explicit draft review while retaining the original audio and manual notes.

CI saves both SDK logs, real XCTest screenshots, result bundles, portable/export fixtures, a simulator app and an optimized unsigned device archive. Screenshots are not generated artwork. Host timing, sanitizer and simulator results do not substitute for the final 30-minute physical/audio/MIDI/DAW matrix. [Hardening evidence](HARDENING_QA.md) records what is measured and what remains open.

The default verification run captures the complete native design. A commit message containing `[ui-only]` retains every functional native test class, domain/audio checks, both SDK builds and the Release archive while skipping duplicate bulk captures. Combining `[ui-only] [integration-only]` runs the arrangement, live editing, shared-engine and voice review suites for a focused diagnostic; it never replaces final full acceptance. `[input-diagnostic]`, `[ru-capture]` and `[device-only]` also select partial scopes and cannot authorize distribution. The normal full run captures all ten English/Russian 375-point views; `[ui-only]` skips the bulk capture methods. Capture waits for settled raw pixels where possible and keeps the selected native PNG unchanged. The runner clears only its destination-stage PNGs before collection so a partial run cannot inherit old frames. Use a full capture after a visible interface change; record actual source/run/artifact hashes and inspect individual originals before preparing Store copies. Distribution still requires all three verification jobs to pass for the exact `main` commit.

For the real input-tap acceptance test, hosted macOS CI configures a signed official BlackHole HAL loopback through `scripts/setup_ci_audio.sh` before booting Simulator. This is an ephemeral test-machine dependency, never an iOS app dependency; local Xcode builds do not install it. Reviewed Homebrew package versions, selected duplex UIDs and CoreAudio reload results are saved in `ci-audio.log`. CI requires actual finite microphone PCM and does not accept an unavailable-input skip. Route JSON distinguishes absent host input from an advertised input with an invalid graph format, and checks that output kernel/engine/clock/phase survive failure as well as capture. This fixture does not establish human singing, physical USB/Bluetooth or iPhone latency/thermal performance; those remain in device acceptance.

The optimized archive runs `scripts/release/audit_binary.py` against the actual arm64 Mach-O: deployment/SDK, UUID and weak FoundationModels load/imports/chained bindings are checked. This verifies static back-deployment constraints; signed startup on older physical devices is a separate acceptance test.

All instrument audio is synthesized by the app. The icon was generated through OpenArt; provenance is retained. No downloaded sample pack, telemetry SDK, account backend, client API key or repository-wide open-source license is included.
