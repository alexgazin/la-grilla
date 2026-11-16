# Native working demonstration

This target records genuine interactions with the running SwiftUI iOS app.
It is separate from `UITests` and does not add methods to the release acceptance
inventory. The app uses its built-in demonstration project in a disposable
`--uitesting` store; all subsequent musical edits are visible taps, typing,
pinches and slider gestures through production controls.

`LaGrillaDemoTests` has four authored journeys: grid/chord editing, zoom,
drum pads and overdub, step editing, mixer and notes; harmony A/B and local
typed Commands with Apply/Undo plus Voice recording preparation; and live
filter/delay/repeat/take recording followed by actual WAV export to the iOS
share sheet; then a genuinely empty project, the built-in local House / eight
bars / seed 42 command, A/B review, Apply, a continuous full eight-bar playback,
and Settings transposition by +2 semitones with Apply during playback. The last
journey uses a separate disposable store and reads existing runtime diagnostics;
it does not inject a score, proposal, PCM or model response. Its visible LOCAL
label and recorded score facts identify the algorithm correctly. Voice
preparation does not demonstrate live human singing recognition. Commands and
the local sketch do not establish FoundationModels generation.

Run the **Native app demonstration recording** workflow. It builds the
`LaGrillaDemo` scheme on the official `macos-15` runner with exact Xcode 26.3 /
SDK 26.2 / iOS 26.2 Simulator, and uses the existing BlackHole fixture.
The first build 20 attempt on `macos-26` failed before recording because the
normal host microphone prompt remained unanswered alongside an Accessibility
Access alert. Its original failed evidence is retained. The same consent helper
previously reached actual BlackHole PCM on `macos-15`; this host choice still
requires a fresh successful capture and does not transfer old media acceptance.
`simctl io recordVideo` captures the real display; a standalone macOS helper
captures timestamped stereo host-loopback PCM. The helper checks the actual
BlackHole UID, uses normal system microphone authorization, and refuses
invalid or silent captures. It does not change TCC databases or attribute
itself to another application's preapproval. The orchestrator may accept
only the ordinary system dialog naming **La Grilla Demo Audio Recorder**.
The capture host needs no FFmpeg installation. If `ffprobe` is available it
records a probe; otherwise an explicit pending receipt requires independent
full video/audio decoding after artifact download before publication.

The raw artifact keeps `screen.mp4`, `audio.caf`, audio/frame/timing receipts,
the complete XCTest log/result bundle and event screenshots. `source-receipt.json`
binds the clean actual Git HEAD to the built app's version/build, executable,
project schema, source hashes and actual toolchain/runtime. The current capture
requires version 1.0.0 / build 20 / schema 10. `raw-manifest.json` hashes original
capture files, including diagnostic failures. Action markers
contain host uptime and Unix timestamps. `capture-timing.json` records a
bounded video startup interval; `ready.json`/`audio-receipt.json` retain actual
first/last PCM host timestamps. These are inputs for subsequent synchronization
and editing, not a claim of frame-exact hardware latency. Preserve original
raw media and disclose cuts in any edited version. Never replace missing
actual sound with an offline soundtrack while calling it live app audio.

Failure of an interaction or sound capture makes the recording diagnostic.
It must not be published as a successful demonstration. Simulator recording
does not establish physical iPhone, USB/BLE hardware or App Store acceptance.

Capture ends when all four actual method PASS lines arrive. The orchestrator
then continues reading Xcode's result-writing output and still requires its
final exit status to be zero. This avoids recording an unrelated long static
bookkeeping tail after the authored interaction has finished; it does not
shorten a test, increase its 300-second allowance, or relax sound
coverage/continuity. The workflow remains 35 minutes. Only the standalone host
PCM recorder ceiling grows from 600 to 900 seconds: the original three-journey
video already lasted 537.7 seconds, before adding the fourth journey.

Download and inspect all original video/PCM before selecting an edit. The new
scene's cuts should show Empty, the actual command and LOCAL review, A then B,
Apply, the uninterrupted eight-bar interval, and the +2 review/Apply. Preserve
the prior Grid/Jam/Mixer/Harmony/Commands/Perform/WAV scenes at their actual
action speed. Exact source times and any visual/audio acceptance are decided
from the new recording. The old build 15 EDL and its narrowly qualified failed
capture remain historical evidence; they cannot authorize the new capture.
