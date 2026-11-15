# Verified implementation — 14 November 2026

App source commit: `79e15c6650b4beeea8e39e3d099aa09e26176c41`.

[Successful macOS/iOS workflow](https://github.com/alexgazin/la-grilla/actions/runs/43619270902) — all steps completed successfully. Later documentation, screenshot and verification-configuration commits do not change this tested app source.

| Check | Actual result |
| --- | --- |
| Swift musical domain and storage | **14 tests passed**, 0 failures |
| C++ audio kernel, macOS ARM64 | **Passed**: output, loop boundary, pending revision, Stop, pad preview, bounded input queue, empty snapshot, count-in cancellation, concurrent snapshot ownership |
| Stop/seek regression | **Passed**: Stop with a pending revision remains silent; stopped seek remains silent; Play restores the active chord |
| Long sample-clock regression | **Passed**: 600 seconds rendered offline at 44.1 kHz / 123 BPM match the reference musical position within 0.1 tick; this is not a physical-device latency/drift measurement |
| Linux C++ sanitizer check | **AddressSanitizer and UndefinedBehaviorSanitizer passed**; leak detection disabled because this executor runs under ptrace |
| Native app compilation | **BUILD SUCCEEDED**, Xcode 16.4 / iOS Simulator SDK 18.5 / Swift 6 language mode / ARM64 |
| Physical iPhone SDK compilation | **BUILD SUCCEEDED**, unsigned `iphoneos` build; [separate verification run](https://github.com/alexgazin/la-grilla/actions/runs/43620956440). App source unchanged from the tested commit. This confirms compilation, not execution on hardware. |
| Native iPhone UI flows | **4 tests passed**, 0 failures, iPhone 16 simulator running iOS 18.5 |
| Simulator screenshots | Grid, Jam, Mixer and Projects captured from a live app process and visually inspected |

The four native UI scenarios actually executed:

1. Create a named project, add a minor chord, apply it, Undo and verify Redo availability.
2. Start a drum take with count-in, hit Kick and Snare, finish and Undo the take.
3. Export MIDI and verify the system activity/share interface appears.
4. Play continuously while changing Grid → Jam → Mixer, trigger a pad, verify mixer navigation stays reachable and Stop.

Domain coverage includes every supported root/quality/inversion, strict chord parsing, the exact C/Am/F/G reference pitches, root bass, quantization at loop boundaries, atomic rejection of invalid commands, independent duplicated sections, section ripple deletion/reorder, grouped fader Undo, range clipping/rebasing, MIDI event round-trip and key-signature spelling, project/backup recovery, malformed large ticks, stale saves and protection of newer schemas.

Native launch initially exposed a Swift 6 actor-isolation trap in AVAudioSourceNode's legacy render block. The block is now built in an explicitly nonisolated factory with a Sendable capture. Successful live screenshots and UI tests include actual engine initialization/playback and provide the regression check for that crash.

## Artifacts

- [Signed simulator build and generated Xcode project](https://github.com/alexgazin/la-grilla/actions/runs/43619270902/artifacts/14123692358)
- [Screenshots](https://github.com/alexgazin/la-grilla/actions/runs/43619270902/artifacts/14123887716)
- [Full build/test logs and XCTest result bundle](https://github.com/alexgazin/la-grilla/actions/runs/43619270902/artifacts/14123018272)
- Checked-in images: [Grid](../Screenshots/grid.png), [Jam](../Screenshots/jam.png), [Mixer](../Screenshots/mixer.png), [Projects](../Screenshots/projects.png).

The simulator binary is a **Debug ARM64 iOS Simulator app**, not an installable iPhone IPA. The packaged simulator ZIP delivered in chat restores executable file modes that GitHub's raw directory artifact can flatten. A physical build needs the owner's Apple development team/signing configuration in Xcode.

## Remaining release gates

This is an internal development build. No physical iPhone, Apple Developer signing identity, TestFlight/App Store account or DAW was attached to this environment. Consequently the following are **not verified** and the release gates in README §21 are not closed:

- Physical touch-to-sound latency, route compensation, 30-minute device load/CPU/memory, multitouch behavior and voice-stealing/choke sound quality.
- Phone-call interruptions, headphone/USB/Bluetooth route changes, background behavior and media-services reset on hardware.
- MIDI import into two actual DAWs.
- Full accessibility/Dynamic Type, narrow/landscape ergonomic acceptance and complete localization of dynamic status text.
- Signed device distribution, TestFlight, App Store privacy/metadata/submission.

AI/voice, Perform, external MIDI and AUv3 remain the explicitly gated follow-up features; they are not represented by inactive controls in this build.

## R1 — WAV, stems and portable projects

Verified app/config source: `b373fca91306b8672904629d821187ad3d60e59c`. [Successful workflow](https://github.com/alexgazin/la-grilla/actions/runs/43653433531).

- 21 Swift tests passed, including exact WAV frame count/header/audio/determinism, one-shot release tail, cancellation cleanup, aligned muted stems and safe ZIP/project round-trip.
- Independent Python `wave` and `zipfile` readers validated generated files.
- C++ timing/concurrency/stop/seek regressions passed.
- Both native SDK builds passed: ARM64 simulator and unsigned physical-iPhone target.
- Six native UI flows passed: prior navigation/create/chord/drum/MIDI flows plus WAV export during live playback and portable-project system sharing.
- Seven native screens captured from live processes, including format/rate/depth/tail/stem settings, in [Screenshots/R1](../Screenshots/R1). Images first captured from `02a2c14`; the subsequent verified commit only fixes the CI test architecture.

Import safety/copy semantics are domain-tested; file-provider interaction, real DAW interoperability, physical audio, signing and App Store distribution remain release checks.

## R2 — piano roll and eight tracks

Verified source/config: `59834d0a1937c4a16860dca23439612d63aa7960`. [Successful workflow, attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/43655337342/attempts/2).

- 28 Swift tests pass: note editing/Undo, independent track/section copies, offsets/repeats, v1 source-preserving migration/backup, MIDI channels and eighth-track WAV/mute.
- C++ eighth-track/master independence and existing timing/concurrency regressions pass.
- Both native SDK builds pass; 8 UI scenarios pass, including piano-roll add/copy/paste/Undo/list/playback and eight-track mixer mute/transport.
- Nine live simulator screens are stored in [Screenshots/R2](../Screenshots/R2). These images were captured from `e24380a`; later source changes only add accessibility IDs/test selectors, while CI configuration handles cold simulator startup.

Physical gestures, performance/latency and external DAW interoperability remain release checks.

## R3 — harmony lab

Verified app/config source: `cf82a44fb1839d2307783e6bc38e4caf0193569b`. [Successful workflow](https://github.com/alexgazin/la-grilla/actions/runs/43655352838).

- 35 Swift tests pass, covering extended/slash vocabulary, register/pitch-class preservation, section-scoped replacement with crossing clips, borrowed/tritone substitutions, stale/repeated proposal guards and migration.
- C++ immediate audition-snapshot restart and existing timing/routing regressions pass.
- Both native SDK builds and 9 native UI flows pass, including generate → B → A → Apply → Undo for harmony proposals.
- Eleven actual live-process screenshots, including harmony settings and original/proposed chords, are checked in at [Screenshots/R3](../Screenshots/R3).
- Reconciliation with R2 main changes only documentation, screenshots and commit ancestry; app/domain/audio/test sources remain identical to the verified source.

These are deterministic local musical proposals; no cloud LLM is used. Physical A/B audio-quality acceptance remains a release gate.

## R4 — local Assistant and dictation adapter

Verified app/config source: `56091ed` (Speech capability API fix on top of `eba8be4`). [Successful workflow](https://github.com/alexgazin/la-grilla/actions/runs/43656289939).

- 42 Swift tests pass: equivalent RU/EN commands, explicit chord durations, ambiguity choices, section resize/trimming/empty space, one-transaction Undo, strict structured-operation/ID validation and stale/duplicate rejection.
- Both native SDK builds pass. All 11 native UI scenarios pass, including Assistant ambiguity → explicit distribution → Cancel, and command → review → Apply → Undo.
- Thirteen real simulator screenshots are stored in [Screenshots/R4](../Screenshots/R4).
- Apple Speech uses `supportsOnDeviceRecognition`/`requiresOnDeviceRecognition`, RU/EN selection, permission-on-use and manual-input fallback. Real microphone input, language/model availability, permission denial and interruption behavior need device acceptance; simulator text-flow tests do not prove ASR quality.
- App/domain/audio/test sources remain unchanged when reconciling verified R3 main.

No free-form cloud provider or client API key is included.

## R5 — monophonic voice-to-MIDI and original sources

Verified app/config source: `4dc5f5d0260a6dca1c5edb7bbb9ffb093229036a`. [Successful workflow](https://github.com/alexgazin/la-grilla/actions/runs/43658663933).

- 54 Swift tests pass, including two pitch detectors on identical clean fixtures, silence/noise/pause/resampling/cancellation, source-preserving quantize/scale projection, scoped voice placement/Undo, SHA-256 known vectors, CAF metadata/byte validation, package copy/recovery/import and redundant-save backup preservation.
- Independent Python CAF/hashlib/ZIP readers validate the portable source fixture.
- Both native SDK builds and all 12 UI scenarios pass. The new flow analyses an explicitly labelled synthetic PCM source, verifies three notes, auditions Original/Instrument, applies/Undo/Redo and exports a portable project with its source.
- Fifteen real screenshots are checked in at [Screenshots/R5](../Screenshots/R5); `voice-draft` visibly labels its synthetic QA source.
- [Voice QA](VOICE_QA.md) records the controlled metrics and hardware/human-voice gates. The feature remains **Beta / monophonic**. Simulator fixtures prove software flow, not microphone permission/route/count-in quality or recognition accuracy for human voices.

The implementation compiles the actual AVAudioRecorder scheduled-count-in and Apple Speech adapters. Physical microphone and language-model acceptance remain unverified.

## R6 — finite Perform recording and replay

Verified app/config source: `f1ffe17a9be69ac0053b44f0e07ca6ac2142e36a`. Final full acceptance run: [`43671884623`](https://github.com/alexgazin/la-grilla/actions/runs/43671884623), test/CI revision `b7ff805`. That revision changes the Assistant test to type its command and skips duplicate screenshot capture; both SDK builds, all domain/kernel checks and all 14 native UI flows still run. The app/audio/domain source is unchanged.

- 60 Swift tests pass, including finite takes, frozen source validation, migration, sample-rate conversion, repeat/section/live-input projection, WAV determinism and rejected invalid actions.
- Three C++ suites pass: existing kernel timing/concurrent snapshot regressions, filter/delay/repeat DSP, and actual-frame Perform control/capture/replay. The latter includes section cancel/latest-wins, beat jump, repeat, pad, gain, pan, filter, delay, stop and Panic. PCM replay matches within `1e-6` across 512/257-frame render blocks.
- Independent Python PCM/SMF readers verify finite one-second WAV, Type 1/PPQ 960/tempo, live pad notes, filter CC and NoteOff ordering.
- Both native SDK builds and all 14 native UI scenarios pass. Perform is recorded, kept while navigating to Jam, replayed and exported to the system Share sheet.
- Eighteen real live-process captures from app source `f1ffe17` are checked in at [Screenshots/R6](../Screenshots/R6).

[Perform QA](PERFORM_QA.md) documents controller semantics and the remaining physical-audio gates. This stage does not claim measured iPhone latency, USB/BLE compatibility or identical MIDI timbres in external music software.

## R7 — Core MIDI devices and Learn

Verified app source: `223615f`. [Complete successful workflow 43680458783](https://github.com/alexgazin/la-grilla/actions/runs/43680458783).

- 62 Swift tests and six C++ suites pass, covering MIDI settings/track cleanup, bounded parsing/running status, sample timestamps, sustain/source disconnect, finite input capture/PCM replay, output gates/channels, destination epochs, no input echo and Panic.
- Both native SDK builds, all 15 Studio UI flows and the 20-screen capture test pass. The new scenario creates actual Core MIDI virtual endpoints, learns CC74, receives real output notes and returns to stopped transport after emergency Panic.
- Twenty genuine captures are committed in [Screenshots/R7](../Screenshots/R7). [MIDI QA](MIDI_QA.md) records software behavior and the remaining physical-controller checks.

USB/BLE peripherals, hot unplug, actual route latency and import into two DAWs still require the installed signed build and physical equipment. Virtual simulator endpoints are not substituted for those measurements.

## R8 — product polish and accessible layouts

Verified source: `595d4a3`. [Successful workflow 43682961615](https://github.com/alexgazin/la-grilla/actions/runs/43682961615).

- Adaptive system/light/dark appearance, an OpenArt-generated opaque app icon with provenance, EN/RU strings/plurals and localized model labels are implemented. The audit checks 448 static UI keys, format parity, AA token contrast and icon format.
- Large text opens the note list and native mixer/pad controls. Landscape retains transport and navigation beside the pads; compact portrait keeps the sixteen pads above transport. Source geometry remains proportional to musical time/pitch.
- Both SDK builds, 62 Swift tests, six C++ suites and all 18 native user scenarios pass, including Russian/light export, accessible note list/mixer and landscape pad/transport interaction. Explicit orientation reset and window-layout waits isolate scenarios from previous rotations.
- Three additional original-PNG QA views are committed in [Screenshots/R8](../Screenshots/R8). The final flow retry skips duplicate bulk capture; the integrated hardening/release runs retain broader captures and the real 375-point simulator check.

Manual VoiceOver usability and physical-device accessibility remain part of installed release-candidate acceptance.
