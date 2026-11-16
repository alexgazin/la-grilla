# Native working demonstration

This target records genuine interactions with the running SwiftUI iOS app.
It is separate from `UITests` and does not add methods to the release acceptance
inventory. The app uses its built-in demonstration project in a disposable
`--uitesting` store; all subsequent musical edits are visible taps, typing,
pinches and slider gestures through production controls.

`LaGrillaDemoTests` has three authored journeys: grid/chord editing, zoom,
drum pads and overdub, step editing, mixer and notes; harmony A/B and local
typed Commands with Apply/Undo plus Voice recording preparation; and live
filter/delay/repeat/take recording followed by actual WAV export to the iOS
share sheet. Voice preparation is not a demonstration of live human singing
recognition. Commands are not FoundationModels generation.

Run the **Native app demonstration recording** workflow. It builds the
`LaGrillaDemo` scheme and uses the repository's existing BlackHole fixture.
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
the complete XCTest log/result bundle and event screenshots. Action markers
contain host uptime and Unix timestamps. `capture-timing.json` records a
bounded video startup interval; `ready.json`/`audio-receipt.json` retain actual
first/last PCM host timestamps. These are inputs for subsequent synchronization
and editing, not a claim of frame-exact hardware latency. Preserve original
raw media and disclose cuts in any edited version. Never replace missing
actual sound with an offline soundtrack while calling it live app audio.

Failure of an interaction or sound capture makes the recording diagnostic.
It must not be published as a successful demonstration. Simulator recording
does not establish physical iPhone, USB/BLE hardware or App Store acceptance.
