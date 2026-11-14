# La Grilla — iOS implementation

The original README remains the product specification. Implementation is in `feat/ios-mvp` / PR #1. This is an internal development build, not a signed App Store or TestFlight release.

## Build

- Deployment: iOS 18.0; Swift 6; C++17; no external audio libraries or network dependencies.
- CI baseline: Xcode 16.4 / iOS Simulator SDK 18.5, macOS 15 ARM64.
- Reference hardware for the remaining physical checks: iPhone 13 or newer, built-in speaker and wired/USB audio. No physical-device measurements have been made in this cloud environment.

On a Mac with Xcode selected:

```sh
brew install xcodegen
xcodegen generate
open LaGrilla.xcodeproj
```

Choose the `LaGrilla` scheme and an iPhone simulator. For a physical iPhone, select the owner's Apple development team in Signing & Capabilities. No signing certificates or Apple Developer credentials are included.

```sh
swift test --package-path Packages/MusicDomain
xcodebuild -project LaGrilla.xcodeproj -scheme LaGrilla \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
bash scripts/screenshots.sh
```

GitHub Actions performs domain tests, audio kernel tests, an iOS build, simulator capture and native UI tests. Its `ios-verification` artifact contains the simulator app, generated Xcode project, screenshots, logs and XCTest results. The simulator app is not an IPA for a physical phone.

## Source map

| Directory | Responsibility |
| --- | --- |
| `Packages/MusicDomain` | Codable schema v1, tick-based patterns/clips, chord dictionary/parser, validation, independent section copies, command history, playback compiler, Type 1 MIDI writer, disk actor |
| `AudioRuntime` | One AVAudioEngine/AVAudioSourceNode, bounded C++ render kernel, sample-clock transport, 16 generated drum sounds, harmonic and bass voices, gain/pan ramps and meters |
| `App` | Shared session and transport, autosave, recording transactions, navigation, audio session notifications |
| `Features` | Project browser, Grid/chord editor, Jam/step editor, Mixer, bass inspector and MIDI/system share sheet |
| `Tests`, `UITests` | Host audio-kernel and native user-flow checks |
| `Resources` | App icon and RU/EN string resources |

## Musical behavior

All positions use integer ticks at PPQ 960. Harmony, generated root bass, playback and MIDI share `Compiler.notes`. The default example is C / Am / F / G at 120 BPM, four bars, with the exact pitches and drum map in README §6.6. New projects contain empty harmony/drum patterns and optional bass.

A song has up to three tracks, eight sequential sections and 64 bars. Clips refer to independent patterns; duplicating a section copies its patterns and event IDs. Chord names are parsed strictly. Changing the key changes suggestions without transposing existing notes. MIDI exports the whole song or the selected section, rebased to tick zero and clipped to its finite duration. Drum events use channel 10. MIDI does not carry sound assets or the app's mix.

The audio clock derives ticks from a stable sample-frame origin. UI timers only read position; they never trigger scheduled notes. Control submits into one of three preallocated snapshot slots. States are `free → writing → ready → reading → free`; control can reclaim ready slots using compare/exchange, and render owns a reading slot until the next bar-boundary adoption. Snapshot sequence numbers are separate from saved project revisions. Snapshot storage is never freed in render. Pad input uses a bounded SPSC queue, with an exposed overflow counter. No file/network operations, locks, logging, SwiftUI objects or allocations occur in render.

Pads are audible immediately. Recording starts after one bar of count-in or at the next bar when already playing. Committed passes are single Undo transactions; intentional hits quantized to the same step are retained. A pass becomes part of the playback snapshot after commit. Replace clears only the selected recording range once, then subsequent passes overdub. Tempo and loop edits are blocked during an unfinished take. Mixer parameters ramp over 5 ms.

## Persistence and recovery

Each project is a local `Documents/Projects/<UUID>.grilla` package with `manifest.json` and `backup.json`. A serial actor validates snapshots and writes atomically. The previous valid manifest is copied to backup before replacement. Autosave is debounced by 700 ms; completed takes and lifecycle transitions request immediate checkpoints. The Saved indicator tracks the exact revision written, not merely the newest in-memory revision. Disk failures retain the in-memory project and show Retry / Save copy. Invalid or newer-schema files remain intact and can be recovered from their backup.

## Audio content and rights

All 16 one-shots are synthesized by this implementation at engine initialization from deterministic oscillators/noise. No downloaded sample pack, copyrighted recording, model-generated music or external SoundFont is embedded. Harmony and bass currently use simple oscillator presets. This intentionally differs from the planned sample-based harmony timbre in README §8.1; evaluating a richer sampled instrument remains an audio-quality gate after device measurement. No repository-wide open-source license has been added; the owner's licensing decision remains unchanged.

## Acceptance boundaries

Automated checks do not establish the physical-device/DAW acceptance criteria in README §21. Before calling v0.1 release-ready:

- Measure touch-to-sound latency, buffer underruns, CPU/memory and a 30-minute load case on physical iPhones.
- Check audio interruptions, unplugging headphones, Bluetooth/USB route changes, background policy and media-services reset on hardware.
- Compare timestamped recordings against an audio/host-time reference and add measured route compensation. Current recording reads the last rendered clock/tick; no unmeasured Bluetooth correction is applied.
- Import exported MIDI into two DAWs and compare pitches, durations, tempo, markers and boundary note-offs.
- Finish accessibility, Dynamic Type, 375 pt and landscape ergonomic acceptance. RU strings cover the primary flows; some dynamic status/metadata text remains English.
- Review voice stealing/choke transients and replace hard voice reuse with a measured short-tail policy if audible. The output guard is a safety clamp, not a mastering limiter.

This branch does not add WAV/stems, AI, voice capture, MIDI controllers, AUv3 or DJ performance. Those remain the gated follow-up versions in the product specification.
