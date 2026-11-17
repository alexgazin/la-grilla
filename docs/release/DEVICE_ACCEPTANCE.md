# Physical release acceptance record

**Downloadable app source: main `82e4dfb02d2016dcbe31e7b34af6cd09b0f0457a`, 1.0.0 (23), schema 11. Formal physical acceptance: Pending. Completed full73: 71 PASS / 2 FAIL / 0 allowance. Next coherent full73 with the reviewed fixture correction: Pending.** All four fresh SDK/archive/compatibility jobs passed on original attempt 1 of [run 44120318741](https://github.com/alexgazin/la-grilla/actions/runs/44120318741). Full native73 in attempt 2 completed without supervisor timeout in 3227.618s; its two failures do not accept the software or any physical device. The newly integrated fixture has no fresh runtime acceptance yet. The integration includes stable, separate Start/Stop actions first introduced in `db8a022` and current Assistant fixture/availability corrections. Previous `7564fe7` strict4 and SDK4 passes remain source-bound feature evidence, not full native acceptance for this main. The owner has installed and tried the app on an iPhone, but its exact model, iOS version and installed source/build have not yet been recorded. The latest feedback likes the night theme and chord/parallel-melody editing, while reporting uncertain pad onset, unclear note resizing and hard-to-find sound selection. These are observations on an unidentified installed build, not acceptance of 23. This execution environment has no connected physical iPhone, USB/BLE controller or two DAWs. Simulator and host benchmarks must not populate hardware fields.

Use the [package identities and signing instructions](../../Builds/Testing/README.md); [CURRENT](CURRENT.md) separates exact app/test sources and software outcomes. The current manual download is the fresh exact-main 82e4dfb original unsigned IPA: **3,693,136bytes**, SHA-256 `93de06cf30a23acf186dd9a2427e98c2097136a0f53c671789cb8612662245a8`, [artifact 14346460625 from run 44120318741](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/artifacts/14346460625). New-source/receipt binding, CRC, all 16 app files and matching dSYM passed independent static verification; [public receipt](../../Builds/Testing/candidate23-main-82e4dfb-verification.json). Actual byte comparison found equality with `7564fe7`/`db8a022`; the new source-bound package was downloaded and verified independently, not relabelled. It remains a manual-alpha preview with source 82 full73 at 71 PASS / 2 FAIL; the next coherent run with the fixture correction is Pending. Tester signing and physical acceptance remain required. Previous candidate `7564fe7` retains its own [artifact 14342868829, archive attempt 2](https://github.com/alexgazin/la-grilla/actions/runs/44112860068/artifacts/14342868829), strict4 and SDK4 history. None of that evidence fills a physical field.

Historical pre-Assistant-fix main `0cfd12e3e1a821d50c7a1502f627329b7d60ff02` passed four SDK/archive/compatibility jobs and independent static IPA audits. Its [full native73 44083683395](https://github.com/alexgazin/la-grilla/actions/runs/44083683395) observed all 73: **70 PASS / 2 FAIL / 1 allowance**, exit65, no supervisor timeout. All five prior regressions and ten touch/sound/recording/landscape feedback cases passed there; this remains a historical manual-test preview with incomplete software acceptance. Its separately downloaded IPA bytes match prior c9 because those two app sources were unchanged. That historical byte equality does not transfer any native outcome to current main 82e4dfb.

Historical results stay source-bound: e2ec/576 each passed full transpose 118.102s/115.086s and failed Flats 81.171s/111.366s without allowance. Source 66 passed transpose 100.510s but failed Flats 90.890s and Bass→Melody (assertion then original 120s allowance). C9 focused3 ended 0 PASS / 1 assertion FAIL / 2 original 120s allowances; Bass failed 104.540s without allowance despite visible restoration, while both Transposition cases reached 120s without terminal durations. All four SDK/archive/compatibility jobs for those sources passed; the failed native scopes remain failed and do not accept later code. Db8 Assistant3 passed Jazz 77.591s and Composition 45.288s but hit the original Speech 120s allowance. Source 6504 passed Composition 84.779s and complete Granted Speech 94.857s, but failed Jazz 48.698s before generation on actual `unsupportedLanguage`. Source `7564fe7` [strict4 run 44112860068](https://github.com/alexgazin/la-grilla/actions/runs/44112860068) passed local Jazz 46.884s, sibling setup/recheck 43.305s, Composition 36.929s and Granted Speech 74.992s. Real RU request availability was `unsupportedLanguage`, and actual UI-selected EN was `available`; global model unavailability and real model generation are not claimed. This selected4 PASS does not replace full73 or physical acceptance. App source 82e4dfb has its own passed archive/static checks and completed 71 PASS / 2 FAIL native scope; none is reclassified as a full pass. [Detailed Assistant evidence](../review/2026-11-17/ASSISTANT23.md). None of these results fills a physical field.

The source 82 full73 failures were a playback-state observation and the following app launch. After section Move earlier, original frames at case 47.057s/49.257s already show PLAYING and correct order within the failed 45.66–49.69s predicate window; the later genuine AX node also says PLAYING. The reviewed fixture now reads a fresh actual native snapshot/type/identifier/label inside the same 5s guard. This does not claim measured acoustic zero-gap behavior. The following Pad case could not terminate prior PID 49770 before any Pad UI/contact assertion; the OS lifecycle cause is unresolved, and App/Pad behavior or teardown is not changed. [SECTION23 evidence](../review/2026-11-17/SECTION23.md).

One fresh coherent full73 `[ui-only]` run is planned for the integrated fixture, preserving the original LiveEditing→Pad order in the long-running suite, all other helper callers, original actions/assertions, 5s checks and 180s LiveEditing budget. There is no additional focused2 mode, skip or cap change. Its runtime status remains **Pending**. All hardware fields below remain Pending regardless of the unchanged app bytes or prior source 82/7564 software evidence.

Record actual installed source, signed IPA hash, build, device and date. Export important projects as portable bundles before upgrading: 23 reads schemas 1…11 and saves schema 11; older apps cannot open a saved schema 11 project. Every formal hardware evidence field below remains **Pending** until that identified device session is recorded.

## Preliminary owner report — 16 November 2026

| Reported observation | Acceptance status |
| --- | --- |
| Audio banner/alert shows `com.apple.coreaudio.avfaudio`, code `2003329396` (`what`); playback is unavailable. | Pending: repeat cold launch, Play and route recovery on installed candidate 23. |
| Tapping Dictate reportedly terminates the app; no crash stack or exact installed build is recorded. | Pending: repeat authorization allowed/denied and capture on the actual phone. |
| New screenshots show Mic and Speech permissions granted, but capture still reports `LiveInputError.unavailable`. | Pending: repeat authorized capture, record actual route/formats and retain sanitized audio diagnostics; permission alone does not establish usable input. |
| Assistant reports unavailable Apple Intelligence; owner says it is enabled. The supplied settings page shows per-app Siri suggestions, not global model readiness. No real-model proposal is recorded. | Pending: record global Apple Intelligence/model readiness and selected request language, use Recheck, and verify local Commands separately. |
| New projects/tracks reportedly do not work. | Pending: distinguish empty content from audio failure; repeat create → add content → save → reopen → export. |

These observations are defect reports, not completed hardware measurements or proof of a specific crash cause. Exact `main` 16 source `9dfec7e117ef768c28cdfe12f342baf466f55682` passed [43858734785](https://github.com/alexgazin/la-grilla/actions/runs/43858734785): all three jobs SUCCESS, 51 functional native PASS / 0 FAIL / 1 diagnostic SKIP. Earlier `01fb8b7` / `224e248` failures remain recorded in the [implementation log](../IMPLEMENTATION_LOG.md); neither an earlier failure nor this later Simulator pass determines the owner's phone result.

Historical repair candidate 17 ([PR #20](https://github.com/alexgazin/la-grilla/pull/20), schema 8) added controlled authorized-input preparation and retirement of input-using I/O, retaining DSP/kernel/music/MIDI state while permitting a new input-free engine identity after Stop. Transitions may interrupt output; physical zero-gap behavior and the mic indicator are unmeasured. Partial native results already prove actual host PCM, retirement and the splash component on their own sources, but incomplete Speech/AI methods are not marked passed. These historical partial results do not accept 23; current code and exact-source software outcomes are recorded separately in [CURRENT](CURRENT.md).

AI has independent request/dictation languages and Recheck. Per-app Siri controls do not establish global model readiness. Static launch and animated loading are implemented; a held QA preview of the same component is explicitly distinguished from actual cold-launch timing. No software result populates a physical evidence field below.

## Formal acceptance record

Software-only evidence stays separate: [C1–C7](C7_ACCEPTANCE.md) preserves historical version 14 source `77fb72a`; version 15 full regression is source `838b4847`, [run 43812214574](https://github.com/alexgazin/la-grilla/actions/runs/43812214574), with 46 functional native methods and 623 EN/RU keys. The later appearance fix has only the recorded [two-method focused verification](https://github.com/alexgazin/la-grilla/actions/runs/43819149979), source `014a00b9`. Neither substitutes for exact-final-main verification or any field in this physical matrix. The [professional finishing checklist](../PRODUCT_FINISHING.md), [original welcome/settings frames](../../Screenshots/ProfessionalShell/README.md) and [132.2-second real working-app video](../../Media/WorkingDemo/README.md) document separate Simulator/software scopes; none establishes C8 device/model/signing acceptance.

Copy this record per tested release candidate. Keep the source SHA, version/build and installation method together; record a TestFlight build identifier only when TestFlight was actually used. An unsigned IPA signed locally with a Personal Team is a valid manual-test route, not App Store distribution.

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
| Command Start/Stop/repeat, automatic end→late Stop, independent AI/dictation languages and real Recheck status | Pending |
| Save/kill/reopen, backup recovery and full-storage behavior | Pending |
| VoiceOver / Dynamic Type / language / orientation | Pending |
| MIDI/WAV/stem/project imports; source audio retained | Pending |
| Defects / evidence links / tester / date | Pending |

P1: 3 tracks / sparse 64 bars. P2: 8 tracks / 8,192 events. P3: 8 tracks / 16,384 events, live pads, filter/delay and repeated section/transport actions. Use the real instrument/mix presets and export/import the same project between tests. Keep audio recordings or Instruments traces where they substantiate timing or dropout claims. Repeat failed cases after fixes on the new build.

## Build 23 touch, sound and tilt retest

Run these cases on the identified installed 23 in the night theme, portrait and landscape, using the same saved project. Retain original screenshots and captured audio where needed; record what was heard as well as what the UI showed. New video production is cancelled. For timing, declare the contact/audio reference, sample count and threshold before testing, and record median/p95 plus the spread for each route. Do not infer zero latency from contact-triggered code or from a screen recording. Keep Bluetooth device/model/codec or the unavailable field with its result.

| Area / device action | Required observed result and evidence | Recorded result |
| --- | --- | --- |
| Pads: alternating two fingers on different pads; both contacts together; hold, release, slide across a boundary and repeat quickly | Each new contact sounds once without waiting for finger-up; holding/sliding does not add unintended retriggers; two fingers do not suppress each other. Record missed/extra hits and contact-to-audio onset for speaker, wired/USB and Bluetooth separately. | Pending |
| Pads while the loop plays: record the same rhythm with Q Off, 1/8 and 1/16; inspect and replay the stored events; Undo | Live audition remains responsive; quantization affects stored positions rather than delaying the heard hit. Compare actual saved tick positions with the intended grid, repeat at loop edges, and verify Undo removes the recorded change. Route latency and jitter remain measured, not assumed. | Pending |
| Piano roll: select a note, drag its end with a real finger, pause while holding, then release | The note draft, endpoint guide and musical-length readout track the drag before release, with the grip usable under a finger. The committed duration matches the last preview; one Undo restores the prior note length, and Redo restores the edit. Retain held and released frames plus the musical/tick values. | Pending |
| Piano roll at clip/start/end edges and different zoom levels; move a note; scroll/pinch; cancel a held edit by backgrounding or changing editing context | Bounds and snap remain predictable. Changing zoom, snap or editing context during a held edit cancels the draft without committing; a fresh gesture aligns to the grid at the new zoom and snap. Scrolling does not cause a phantom edit. An interrupted/stale edit leaves no committed partial change; returning permits a fresh gesture. Check a long note near the visible edge on the smallest tested display. | Pending |
| Jam/Mixer → Sound: compare Classic/Warm/Bright with Preview, Cancel and Apply while the backing loop plays | The previews produce audibly distinct actual instruments/kits; Cancel restores the original sound and Apply keeps only the selected track's intended change. The backing loop remains musically continuous; retain any gap/dropout rather than accepting only a playing indicator. | Pending |
| Sound after Apply: one Undo/Redo, save/kill/reopen, portable export/import and audio export | The correct kit/preset returns after Undo/Redo and reopen; the loaded project and audio export use that sound. Capture before/after preset values and a short audible reference. | Pending |
| Command dictation: explicit Start→Stop; repeat; Start→automatic end→late Stop, then a new explicit Start | Each explicit Start begins only one capture. Stop ends or cancels its current request; a late Stop after automatic completion never restarts capture. A new capture requires the separate Start action. Record real permissions, recording/requesting/finalizing state, mic indicator, route/output continuity and any unintended restart on the identified phone. | Pending |
| Assistant: choose AI request and dictation languages independently; Recheck actual device/model/selected-locale capability, then review a typed local command | Language choices remain independent; input and project music stay unchanged until Apply. Recheck shows the real availability reason and matching guidance, including available when supported. Unsupported selected language is distinguished from global model unavailability; local Commands remain usable. Record actual locale/status and Apply/one Undo separately from real model generation. | Pending |
| Perform: start playback with Tilt control off; choose Filter, enable while holding comfortably, use Set neutral, tilt gently and disable | Explicit opt-in only; enabling/calibrating holds the current filter at neutral, with a visible live-input response and bounded smooth changes. Disable stops sensor control; manual filter adjustment/reset takes control without motion fighting it. Observe clipping/dropouts and unintended parameter jumps. | Pending |
| Perform → Volume: record the actual master dB, switch target, explicitly enable, tilt, Set neutral and adjust the master manually | Changing target stops tilt and requires re-enabling. Volume starts from the current master, recalibration retains its current value, and gentle tilt stays bounded. Manual master/MIDI adjustment takes over; phone system-volume buttons remain independent. Test initially at a comfortable listening level and record actual dB values. | Pending |
| Both tilt targets: Stop, replay, Done/dismiss, background/lock, interruption and portrait↔landscape rotation; return to Perform | Tilt becomes inactive, does not wake audio or change a parameter after leaving, and never resumes automatically. Rotation requires explicit enabling and a new neutral position. Recheck Filter and Volume after returning; retain sensor/parameter traces where available. | Pending |
| Record a Perform take with filter and volume gestures, replay and export it; Undo the completed take | Heard/recorded parameter changes agree with replay and exported audio; take Undo restores the prior project/take state. This verifies the actual performance/mix paths rather than merely the moving input indicator. | Pending |

These cases supplement the existing 30-minute P1/P2/P3, voice/model, USB/BLE MIDI and two-DAW gates below; they do not replace them. Use the [blank device receipt](newdevice-receipt-template.json) with evidence IDs and SHA-256 files; all current hardware outcomes remain Pending.

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
| Independent AI request/dictation locales; actual Recheck after changing each, input/project preservation and matching guidance for available/unavailable selected locale | Pending |
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
