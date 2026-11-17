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

The current **build22/schema11 tour** keeps every original visible musical
action and assertion, then extends two journeys. After the command/voice setup
chapter, it previews and applies the real Warm kit while the groove plays;
readonly runtime traces and the freshly recorded PCM retain the actual result.
After the full local-sketch/transpose chapter, it adds a note, uses the actual
44pt selected-note end handle, verifies1440 ticks and one Undo, then undoes Add.
The live endpoint guide is a production interaction: its visible appearance
must be checked in the resulting video frames, not drawn into screenshots.
These are extended build22 journeys, not byte-identical build20 test bodies.
The second journey enables the existing readonly runtime-trace launch flag
in its disposable test store. No actual Tilt, human singing or model response
is claimed from a Simulator film.

Run the **Native app demonstration recording** workflow. It builds the
`LaGrillaDemo` scheme on the official `macos-15-intel` runner with exact Xcode 26.3 /
SDK 26.2 / iOS 26.2 Simulator, and uses the existing BlackHole fixture.
The first build 20 attempt on `macos-26` failed before recording because the
normal host microphone prompt remained unanswered alongside an Accessibility
Access alert. The subsequent ARM host was not acquired. Both failed attempts
remain historical evidence. The separate Intel [host preflight43951090113](https://github.com/alexgazin/la-grilla/actions/runs/43951090113)
actually passed normal recorder consent, independently identified stereo
loopback PCM and iOS26.2 boot in147.79s. Its probe tone never enters a movie.
That host result does not establish app UI or audiovisual acceptance: every
new recording still requires its own complete successful capture and review.
The current environment-readiness workflow runs the real host-only probe
after HAL setup and before Simulator boot. Its tone and recorder finish before
the movie starts; source SHA, receipt hash and monotonic ordering are checked
again before video capture. `HostAudioProbe` stays separate from movie media.
The prior `ad88672` attempt remains failed: XCTest timed out initializing AX
before any of the four cases executed; its silent screen/audio are diagnostic.
The subsequent `deeb701` attempt reached the real app: two journeys passed,
one hit its300s allowance and the fourth was interrupted. Its900s actual PCM
ended before the third journey, and cancellation left an unfinalized MP4.
Those originals remain diagnostic. The next candidate adds a separate
`test00PrepareActualAppAndCaptureReadiness`: it warms the real app/AX session
without editing music, answers a source/nonce challenge inside the actual
selected runner container, then waits for real audio/video readiness. Only
then may the four musical journeys begin; this is no cold-launch claim.
The already probed native signed recorder bundle is verified and copied before
capture; every recording still creates new PCM. The first native failure closes
owned media immediately, with a30-minute shared deadline inside the35-minute job
reserving five minutes for finalization and original artifacts. These changes
are prepared source, not a successful new capture.
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
requires version 1.0.0 / build 22 / schema 11. Build and test architecture follow
the actual native host (`x86_64` on this Intel runner). A pre-recording lipo
inventory verifies every actual Mach-O in all built products, including the
app loader/debug dylib, Demo XCTest executable, prebuilt runner and embedded
frameworks. Project code must be thin-native; universal Apple binaries must
include that architecture. `DemoBuiltProducts.zip` retains original file bytes
and symbolic links for independent header/hash verification. The source receipt
also hashes and verifies the actual native host audio helper after compilation
and signing, before it starts. `raw-manifest.json` hashes original
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
