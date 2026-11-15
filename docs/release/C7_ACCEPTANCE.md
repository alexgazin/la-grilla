# C1–C7 software acceptance — 1.0.0 (14)

Accepted implementation/capture source: **`77fb72ab82cd800eb8131136628c416ad83c9046`**, [normal full run 43771988471](https://github.com/alexgazin/la-grilla/actions/runs/43771988471), project schema 8, iPhone/iOS 18+. All three jobs (`ios`, `iphone`, `release-archive`) succeeded on Xcode 26.3 / iOS 26.2. [Current main CI](https://github.com/alexgazin/la-grilla/actions/workflows/ios.yml?query=branch%3Amain) and [PR #13](https://github.com/alexgazin/la-grilla/pull/13) retain the integration/exact-main results; signing requires all three checks for the exact main commit.

| Check | Actual result |
| --- | --- |
| Swift domain/export suite | 118 tests / 19 suites passed |
| C++ audio, concurrency, stress and allocation checks | 15 suites passed |
| Localization/presentation | 603 EN/RU keys, placeholder parity, 11 pt floor, AA tokens/icon passed |
| Native functional workflows | 44/44 passed |
| Native capture methods | 3/3 passed; one separately opt-in diagnostic control skipped |
| Complete native method inventory | 48 declared: 47 passed, 1 diagnostic skip, 0 failed; matches source inventory |
| Original screenshots | 73/73 individually viewed and accepted; two ZIPs/native attachments match exactly |
| Store/root copies | 12 Store originals and 4 root previews copied unchanged |

The [capture manifest](../../Screenshots/OriginalVision/manifest.json) preserves every native test ID, actual result, source/run/job, dimensions/EXIF and SHA-256. Original artifact `14186130887` is 62782338 bytes / SHA-256 `cc89fd14df3fb269ea46b1846de3201faa6e0fb9d128ddc0b0df04ccc5e6a38e`; original `14186510163` is 104139429 bytes / SHA-256 `f4fdbde3ace089ad3635fe636d83371a3cffb2354a015e621ec509a27fb18816`. Both hashes were recomputed over the complete original ZIPs, not a subset or repacked archive.

## Connected scenarios

The expanded catalog of 65 chord qualities and custom harmony, schema migration/frozen sources, actual clip/section move/copy/resize, live structural edits, snapshot/mix/MIDI coherence, DJ recording/replay/export, Assistant review/Apply/Undo and voice source lifecycle pass together. Timeline pinch retains the musical point after a real scroll and during playback. The independent [retention diagnostic run 43773609600](https://github.com/alexgazin/la-grilla/actions/runs/43773609600) passed 3 fixed fresh-app cases; all 6 original synthesized XCTest two-finger records match the framework input and actual ruler geometry. Maximum measured anchor error is 0.0006359169718392899 bar. These are Simulator input events, not physical iPhone touch measurements. Earlier wrong-center expectations and failed runs remain in the [implementation log](../IMPLEMENTATION_LOG.md).

Both production microphone scenarios recorded actual 139200 frames / 48 kHz / 2.9 s / 560896 bytes. Detected pitches 60/64/67 were manually reviewed as 61/64/67; Apply revision 2, hashes of original sources, save/reopen, one Undo and Redo all passed with the same engine/kernel. The cold path retained undetermined permission during output-only playback and requested permission only after explicit Start. Source CAF SHA-256 values are `408c4e4a7da86e6f73db654c8f486ec1ca43699bea35a267698904b169bb53e9` and `cdee9eaf91455a429539356db476cb7170ed13c70e028a29b7f4ed8a27e17135`. These are genuine AVAudioEngine input captures from the hosted HAL fixture, not recorded human singing.

Actual same-process CoreMIDI capture checks connected input/output/probe before real Learn/Send and verifies the source/channel 1 / CC74 filter mapping afterwards. The earlier CoreMIDI client error −304 remains an unexplained observed API return; this acceptance does not claim that the API/server fault was repaired.

## Material limits and external C8 gates

- Render `mHostTime` spacing still shows excess 167.572167 ms in the cold production path and 76.532417 ms in standalone capture. Baseline excess was 0; no backward/rate changes were observed. This is not separately measured callback-entry wall time or a physical waveform. Attribution and absence of audible dropouts are unverified. The generic 50.309542 ms result includes an intentional pause/prepare and is not an unforced-production comparison.
- Real eligible-device FoundationModels availability/locale/generation quality, installed startup on minimum iOS 18, live human voice, physical microphone indicator/routes, USB/BLE/DAWs and 30-minute latency/thermal/dropout tests remain [Pending](DEVICE_ACCEPTANCE.md). The weak-link/current-SDK audit is static evidence.
- The [recorded-human Vocadito baseline](../VOICE_HUMAN_BASELINE.md) gives 95.88% confidence-qualified F0 but 60.28% / 54.95% onset/pitch note F1. Manual review/correction remains part of voice workflow; this corpus does not fill phone/live-singing fields.
- Archives are unsigned. No IPA installation, signing, TestFlight upload, App Review submission or publication has been performed. [Local iPhone Run instructions](../DEVELOPMENT.md#run-on-your-own-iphone) explain development signing with your own team.
