# Verified implementation — 14 November 2026

App source commit: `79e15c6650b4beeea8e39e3d099aa09e26176c41`.

[Successful macOS/iOS workflow](https://github.com/alexgazin/la-grilla/actions/runs/43619270902) — all steps completed successfully. Later documentation/screenshot-only commits do not change this tested app source.

| Check | Actual result |
| --- | --- |
| Swift musical domain and storage | **14 tests passed**, 0 failures |
| C++ audio kernel, macOS ARM64 | **Passed**: output, loop boundary, pending revision, Stop, pad preview, bounded input queue, empty snapshot, count-in cancellation, concurrent snapshot ownership |
| Stop/seek regression | **Passed**: Stop with a pending revision remains silent; stopped seek remains silent; Play restores the active chord |
| Long sample-clock regression | **Passed**: 600 seconds rendered offline at 44.1 kHz / 123 BPM match the reference musical position within 0.1 tick; this is not a physical-device latency/drift measurement |
| Linux C++ sanitizer check | **AddressSanitizer and UndefinedBehaviorSanitizer passed**; leak detection disabled because this executor runs under ptrace |
| Native app compilation | **BUILD SUCCEEDED**, Xcode 16.4 / iOS Simulator SDK 18.5 / Swift 6 language mode / ARM64 |
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

WAV/stems, AI/voice, Perform, external MIDI and AUv3 remain the explicitly gated follow-up features; they are not represented by inactive controls in this build.
