# Physical release acceptance record

**Status: owner-reported device failures; formal acceptance Pending.** The owner has installed and tried the app on an iPhone, but its exact model, iOS version and installed source/build have not yet been recorded. This execution environment has no connected physical iPhone, USB/BLE controller, two DAWs or distribution signing credentials. Simulator and host benchmarks must not be entered as hardware results.

Prepared repair candidate: **1.0.0 (16), schema 8**, app/test source **`01fb8b7f9891e04287c91b21d5998f98e66cbad7`**; original P0 verification is separately source `27cbf09a0d6266d728df9fef889d2caa94ee0c8b`. This identifies the software to retest, not an accepted physical build. Every formal evidence field below remains **Pending** until the actual device/model/signing session is recorded.

## Preliminary owner report — 16 November 2026

| Reported observation | Acceptance status |
| --- | --- |
| Audio banner/alert shows `com.apple.coreaudio.avfaudio`, code `2003329396` (`what`); playback is unavailable. | Pending: repeat cold launch, Play and route recovery on candidate 16. |
| Tapping Dictate reportedly terminates the app; no crash stack or exact installed build is recorded. | Pending: repeat authorization allowed/denied and capture on the actual phone. |
| Assistant displays that Apple Intelligence is disabled. No successful real-model proposal is recorded. | Pending: verify clear availability and working local Commands separately from an eligible, ready model. |
| New projects/tracks reportedly do not work. | Pending: distinguish empty content from audio failure; repeat create → add content → save → reopen → export. |

These observations are defect reports, not completed hardware measurements or proof of a specific crash cause. Candidate 16 has a successful [Release archive](https://github.com/alexgazin/la-grilla/actions/runs/43845748680), [16.4 / 26.0.1 full-resource compatibility builds](https://github.com/alexgazin/la-grilla/actions/runs/43847686116) and 634 EN/RU keys. Its [native recovery / strict PCM run](https://github.com/alexgazin/la-grilla/actions/runs/43845748716) passed 8 methods with zero failures/skips; [five accepted original screenshots](../../Screenshots/DeviceRepair) retain that source. Integration `01fb8b7` has successful current Debug/archive and full 16.4 / 26.0.1 builds; its expanded ten-method run was cancelled at the 35-minute workflow limit, with unavailable logs/artifacts and unknown individual outcomes. The full native regression is still running; integration acceptance remains open. None verifies the reported phone fix. Exact `main` source `224e248` also retains two Arrangement failures and a separate 16.2 infrastructure failure in the [implementation log](../IMPLEMENTATION_LOG.md).

## Formal acceptance record

Software-only evidence stays separate: [C1–C7](C7_ACCEPTANCE.md) preserves historical version 14 source `77fb72a`; version 15 full regression is source `838b4847`, [run 43812214574](https://github.com/alexgazin/la-grilla/actions/runs/43812214574), with 46 functional native methods and 623 EN/RU keys. The later appearance fix has only the recorded [two-method focused verification](https://github.com/alexgazin/la-grilla/actions/runs/43819149979), source `014a00b9`. Neither substitutes for exact-final-main verification or any field in this physical matrix. The [professional finishing checklist](../PRODUCT_FINISHING.md), [original welcome/settings frames](../../Screenshots/ProfessionalShell/README.md) and [132.2-second real working-app video](../../Media/WorkingDemo/README.md) document separate Simulator/software scopes; none establishes C8 device/model/signing acceptance.

Copy this record per tested release candidate. Keep the source SHA, version/build and installed TestFlight build identifier together.

| Field | Recorded result |
| --- | --- |
| Source SHA / installed build | Pending |
| iPhone / iOS / audio route / interface firmware | Pending |
| MIDI controller / firmware / USB or BLE | Pending |
| DAW 1 / DAW 2 / versions | Pending |
| 30-minute P1/P2/P3 CPU, memory, thermal and dropout observations | Pending |
| Touch-to-sound measurement method, median/p95 and route latency | Pending |
| MIDI timestamp/reference method, median/p95 and stuck-note checks | Pending |
| Screen lock/background/remote Stop; unplug/call/Siri/media reset | Pending |
| Microphone denied/revoked, local speech unavailable, count-in cancel | Pending |
| Save/kill/reopen, backup recovery and full-storage behavior | Pending |
| VoiceOver / Dynamic Type / language / orientation | Pending |
| MIDI/WAV/stem/project imports; source audio retained | Pending |
| Defects / evidence links / tester / date | Pending |

P1: 3 tracks / sparse 64 bars. P2: 8 tracks / 8,192 events. P3: 8 tracks / 16,384 events, live pads, filter/delay and repeated section/transport actions. Use the real instrument/mix presets and export/import the same project between tests. Keep audio recordings or Instruments traces where they substantiate timing or dropout claims. Repeat failed cases after fixes on the new build.

## Minimum iOS 18 startup and compatibility

| Required evidence | Recorded result |
| --- | --- |
| Oldest supported available iPhone, exact iOS 18 build, installed signed candidate/version/source and installation method | Pending |
| Cold launch, relaunch after kill and opening a schema 7 project; console/crash/launch trace | Pending |
| Demo Play/Jam/Mixer/clip editing/save/export and local Commands without Foundation Models | Pending |
| Actual on-device AI unavailable message on iOS 18; no dyld missing-framework/symbol crash | Pending |
| Current iOS 26 eligible iPhone comparison; matching submitted source and build | Pending |

The arm64 weak-link audit is static evidence only. Record an actual installed launch on iOS 18; do not copy the unsigned archive audit into these fields. Keep the original legacy project and compare its compiled music after migration, save and reopen.

## Human voice over the shared backing loop

The reproducible [recorded-human development baseline](../VOICE_HUMAN_BASELINE.md) is separate algorithm evidence. It reports 95.88% confidence-qualified F0 accuracy and 60.28% / 54.95% onset/pitch note F1; it does not populate any installed-device field below.

| Required evidence | Recorded result |
| --- | --- |
| Singer/corpus ID, original CAF/WAV SHA-256, sample rate, duration, room/noise conditions, monitoring route | Pending |
| Expected MIDI pitches/onsets/durations and reference method/DAW; sustained notes, short notes, silence and a monophonic phrase | Pending |
| Declared pitch/onset/false-positive acceptance thresholds before the session | Pending |
| Headphone clean reference and speaker/backing-loop bleed trial; register, articulation and repeat counts | Pending |
| Correct pitches within ±50 cents, octave errors, false voiced notes, onset/offset error and confidence/manual corrections against the reference | Pending |
| Target track/section, BPM, loop range, capture request/ready/first-frame/end times and resulting placement/offset/duration | Pending |
| Backing audio before/during/after capture; engine/kernel identity or continuity trace, musical/sample-clock progression, observed gaps | Pending |
| Source recording retained after review/correction/Apply, Undo/Redo, save/reopen and portable export/import | Pending |
| Draft reviewed after a live project edit; original audio/manual corrections retained; stale Apply rejected until review | Pending |
| Cancel, second microphone consumer, permission denial/revocation, background/interruption, route/sample-rate change and count-in/loop-edge cancellation | Pending |

Use the same referenced human take for comparisons; generated tones and the CI virtual microphone are separate fixtures. Distinguish capture request time from the fresh clock sampled after route preparation. Check that normal capture/review does not stop the backing loop, that capture is bounded to its target, and that an interrupted capture does not resume automatically. Record system-forced route/interruption behavior separately from normal shared-graph continuity. Mark diagnostic builds explicitly and repeat user-facing checks on the installed release candidate.

## Actual on-device Foundation Models generation

| Required evidence | Recorded result |
| --- | --- |
| Eligible iPhone, exact iOS build, Apple Intelligence enabled state, model readiness and supported selected locale | Pending |
| Model version if Apple exposes it; otherwise record “not exposed”, OS build and readiness state | Pending |
| Exact free-form prompts and resulting proposal JSON/music; distinguish real model output from Commands and injected fixtures | Pending |
| Whole-song form/tempo/key request, selected-section harmonic edit and jazz/style request; before/after scope and musical review | Pending |
| Generation latency samples, first/warm run distinction, sample count, failures and timeout behavior | Pending |
| Cancel during generation; project unchanged after cancellation/error; stale/foreign/repeated Apply rejected | Pending |
| A/B while the loop plays, Apply as one Undo, save/reopen and MIDI/WAV agreement for the accepted proposal | Pending |
| Ineligible device, Apple Intelligence off, model not ready and unsupported selected language: visible reason and working local Commands | Pending |
| iOS 18 fallback: Commands available; no attempt to invoke the unavailable model | Pending |

Record language support independently for the UI, Commands, Apple Speech and Foundation Models. A successful Russian Commands fixture does not establish Russian model support. Real generation and its musical quality remain unmeasured until an eligible model/device produces the recorded result; a synthetically supplied proposal is not that evidence.

## Live structure, mix, MIDI and touch ergonomics

| Required evidence | Recorded result |
| --- | --- |
| Signed candidate, project fixture/hash, P1/P2/P3 preset/layout, route, connected USB/BLE endpoint and firmware | Pending |
| During playback: add/duplicate/delete melody tracks; clip move/copy/resize/offset and section duplicate/reorder/delete | Pending |
| Before/pending/after revision, boundary adoption time, track identity/preset/mix/FX state and continuous clock/audio trace | Pending |
| Held/sustained external notes across layout changes; correct new bus, current input Off/output None, reconnect and Panic | Pending |
| Simultaneous fader/FX/preset changes and structural edits; no partial generation, unintended restart, stale MIDI delivery or stuck notes | Pending |
| Undo/Redo, sourceAsset association, save/reopen and actual MIDI/WAV/stem imports in both recorded DAWs | Pending |
| Actual finger long-press drag/drop, resizing, incompatible drop rejection, pinch/scroll arbitration and clip-specific editor selection | Pending |
| Smallest tested display, regular/large text, one/two-handed reach, track/section switches, visible 44-point controls and VoiceOver adjustment | Pending |
| 30-minute repeated edits/pads/capture/section/FX session; CPU/memory/thermal/dropouts and touch-to-sound/MIDI measurements | Pending |

Record the heard and captured result, not only a playing indicator. Musical changes must adopt as one generation at the intended boundary; immediate controls must target the currently adopted layout. Compare exported events with the expected arrangement, including offsets/repeats and incompatible drops. An actual external device/DAW trace is required for physical MIDI timing; virtual CoreMIDI and host PCM evidence stays separate.

## Installed signing and distribution receipt

| Required evidence | Recorded result |
| --- | --- |
| Apple team/profile/certificate expiry, signed IPA/archive source/version and successful exact-main verification run | Pending |
| App Store Connect processing/TestFlight build identifier and installed candidate matching that source | Pending |
| Completion of the device/model matrix above, defects/retest evidence and release decision | Pending |
| Store listing/privacy/age-rating/export compliance/support URLs and App Review submission receipt | Pending |
| Approved production build installation and post-release smoke result | Pending |

Record identifiers and expiry dates without recording private keys, certificate passwords or API credentials. Signing, upload, installation and review are distinct actions; none is established by an unsigned archive or a prepared workflow.
