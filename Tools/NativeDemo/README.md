# Compose the working-app demonstration

`compose.py` creates a 1920×1080 / 30 fps presentation from a **real portrait
iOS Simulator recording and the actual stereo BlackHole sound recorded during
the same four UI journeys**. It does not animate screenshots, synthesize notes,
replace missing sound, draw touches or recreate app controls.

The full native screen remains proportional and uncropped. Titles and the
waveform belong to the presentation, outside the app screen. The waveform uses
the actual selected sound. Actions run at their captured speed; explicit EDL
cuts shorten waits and separate sessions. A 15 ms audio fade at each boundary
avoids cut clicks. Optional presentation gain is measured against actual peak
headroom and recorded; no limiter or automatic mastering is applied.

Requires Python 3, NumPy, FFmpeg/ffprobe with libx264, drawtext and showwaves,
and Noto Sans Regular/Bold with Cyrillic. Defaults match the Linux packages
`ffmpeg` and `fonts-noto-core`; use font path flags elsewhere.

```sh
python3 Tools/NativeDemo/compose.py \
  --video /tmp/native-demo/NativeDemoRaw/screen.mp4 \
  --audio /tmp/native-demo/NativeDemoRaw/audio.caf \
  --timing /tmp/native-demo/NativeDemoRaw/capture-timing.json \
  --audio-receipt /tmp/native-demo/NativeDemoRaw/audio-receipt.json \
  --edl /tmp/native-demo/accepted-edl.json \
  --output /tmp/la-grilla-working-demo.mp4
```

An EDL lists chronological, nonoverlapping intervals in seconds relative to
the original screen MP4. Choose intervals from actual action markers and review
the native video. Never select intervals from a failed tour or hide a failed
operation while describing it as successful. The illustrative schema below is
not an accepted cut list:

```json
{
  "source_sha": "<actual 40-character capture source SHA>",
  "chapters": [
    {
      "start": 12.0,
      "end": 24.0,
      "label": "GRID · АККОРДЫ",
      "title": ["Поймай", "идею."],
      "subtitle": "Настоящее редактирование.\nСлышны изменения этой сессии.",
      "color": "#efbd75"
    }
  ]
}
```

Use `--validate-only` first. The tool requires all four recorded XCTest
journeys to have passed; normal recorder completion; no sample-time
discontinuities; a full CAF decode whose frame count and peak match the capture
receipt; consistent sample/host spans; finite non-silent stereo PCM; and source
coverage for every selected interval. It then completely decodes the final MP4.
Source hashes, cuts, fonts, frame counts and output checks are saved beside the
movie in `.render-receipt.json`.
The fourth journey starts from an Empty project and uses the local House
algorithm with eight bars and seed 42: review, A/B preview, Apply, and actual
eight-bar playback, followed by Settings transpose +2. Describe this as a local
algorithm, without claiming model inference or a human voice demonstration.
The build22 tour additionally captures real Warm kit preview/Apply with an
audible running groove, and the selected-note44pt resize handle with committed
duration and Undo. The original action/assertion sequences remain in order;
the journeys are extended, so their complete bodies are no longer identical
to build20. All five new Sound/resize event phases must appear in the original
log and timing receipt. Review real video frames for the transient endpoint
guide; a post-gesture screenshot alone does not prove its live display.

New captures require the original schema-2 `source-receipt.json` beside
`capture-timing.json`. The EDL source SHA, timing source SHA, source receipt
source SHA and captured Git HEAD must agree; the timing receipt must retain
the exact source receipt SHA-256. The receipt includes version/build/bundle ID
read from the actual built app and the source-file hash inventory. New build22
captures also require native-binary contract1: exact build22/schema11,
Xcode26.3/SDK26.2/runtime26.2, and matching actual host/runner/Simulator
architectures. Preserve the complete extracted artifact, including
`DemoBuiltProducts.zip` beside `NativeDemoRaw` and the actual host audio helper
bundle inside it. The composer independently reads every preserved Mach-O
architecture header and checks all original file/link bytes against the
source-bound lipo/hash inventory. App loader/debug dylib and project XCTest
code must be thin-native; a prebuilt runner or Apple framework may be universal
provided it includes the native architecture. The actual compiled host recorder
must also match its hash and native header. Missing binaries or inconsistent
coverage remain failures, rather than an inferred architecture check.
Keep the separate `HostAudioProbe` directory too. Its passed exact-source receipt
and actual tone/recorder finish times must precede video spawn by the recorded
clock guard; its probe PCM never supplies the movie soundtrack.
The current capture also requires a separately passed actual preparation test,
then all four musical journeys. Preparation and its barrier are film setup;
the visible presentation still contains four journeys. Preserve all four
`capture-barrier-*.json` records and the source-bound recorder-build receipt.
The independent composer verifies their actual runner/source/nonce, preboot
binary identity, original native log, media-before-release ordering and all
four actual outcomes. Missing preparation, any native failure, interrupted
cleanup or changed original files remain failures. The Demo scheme now expects
the recording script to coordinate this barrier; it is outside functional UITests.
The composer
uses that app version/build and four-session count in the visible presentation,
and preserves the source receipt and its hash in the render receipt. It validates
the preserved original built products; it does not compare a later checkout to
historical source files or treat the receipt as app acceptance. The original
finalized `raw-manifest.json` must match the supplied MP4, CAF, timing, audio
receipt, source receipt, build receipt and complete XCTest log. Separate capture
attempts cannot be mixed under a shared commit SHA.
The original `demo-tests.log` must also remain beside the timing receipt. Its
SHA-256 and independently parsed required outcomes must match the capture
receipt. Only actual, anchored XCTest protocol outcomes count; quoted examples
and prose do not. An execution-allowance violation remains a failure even if
XCTest later prints PASS for that method. Historical replay also reparses its
original log, without inventing fields absent from the original timing receipt.
Both selected boundaries shrink inward to the 30 fps delivery grid, retaining
the authored and effective times in the receipt. Adjacent clips cannot repeat
an action through outward rounding. Each intermediate has exactly 1,600 actual
PCM samples per channel per video frame. Final AAC checks include stereo/rate,
start, duration, complete decode and at most one AAC frame of padding.

For a chapter made from several short source intervals, use `blocks` instead
of `chapters`: each block has `id`, two-line `title`, `caption`, optional
`color`, and `clips` containing `source_start`, `source_end`, `speed: 1`.
The tool flattens the actual intervals while retaining the parent chapter's
index, title and continuous progress. Titles fade only on the first clip of
each block; cuts within a chapter do not restart their animation.

The complete VFR video is first sampled once onto the 30 fps delivery clock,
with proportional phone-size scaling and a temporary lossless H.264 QP0 cache.
Held source frames stay held through idle intervals. No optical flow,
interpolated UI states or time rescaling are used; the cache is not published.

## Explicitly qualified unused postroll

A historical capture workflow remained **failed** because its wall-clock post-test
bookkeeping outlasted a recorder, even though every authored UI event and all
actual selected video PTS were covered. The default rejects this mismatch.
Three-method replay is restricted to the published build-15 source SHA
`b4a584fc1cc60d73a97386986c2330ca7e45980c`; its app label remains 1.0.0 (15).
`--allow-uncovered-postroll` is restricted further to its original run
`43813957218`, requiring:

- `--postroll-note`, a verified manual `--video-host-start` and `--sync-note`;
- the original failed `source_run_conclusion` and run ID in the EDL;
- the original `demo-tests.log` (or `--events-log`) with all three `app.ready`
  markers and at least 29 authored events, ending at the actual WAV share sheet;
- capture coverage of every marker, another three seconds after the final
  event, and every selected source interval; normal video completion, all
  three actual UI passes, valid stereo PCM and zero sample-time gaps remain
  mandatory.

The original receipt files are never rewritten. The render receipt retains
the failure, exact qualification, event-log hash, event times, missing wall
tail and whether the **entire actual MP4 PTS span** is sound-covered. This
does not turn a failed workflow into a passing one or allow a failed UI tour.
Keep the failed original job and the independently reviewed media scope
separate in the published provenance.
New four-journey captures cannot use this exception. Any interaction, capture
or coverage failure remains diagnostic until a new successful capture and
independent audiovisual review; this tool never changes workflow conclusions.

The published [working demonstration](../../Media/WorkingDemo/README.md) uses
that explicit qualification. After downloading and extracting its verified
artifact into `/tmp/native-demo`, its accepted EDL can be replayed from the
repository root with:

```sh
python3 Tools/NativeDemo/compose.py \
  --video /tmp/native-demo/NativeDemoRaw/screen.mp4 \
  --audio /tmp/native-demo/NativeDemoRaw/audio.caf \
  --timing /tmp/native-demo/NativeDemoRaw/capture-timing.json \
  --audio-receipt /tmp/native-demo/NativeDemoRaw/audio-receipt.json \
  --events-log /tmp/native-demo/NativeDemoRaw/demo-tests.log \
  --edl Media/WorkingDemo/accepted-edl.json \
  --video-host-start 792.654201 \
  --sync-note 'Play glyph matched PCM onset; independent Compose stop residual 0.1596045s within the 1.203s source VFR gap; no time rescaling.' \
  --allow-uncovered-postroll \
  --postroll-note 'Original run 43813957218 remains failed: wall-stop bookkeeping exceeds PCM. All three native UI methods passed; every authored event and the entire actual MP4 PTS span are covered by captured PCM. See committed provenance.' \
  --gain-db 17 \
  --output /tmp/la-grilla-working-demo.mp4
```

Append `--validate-only` to check the same source inputs without rendering.
The full uncut viewable reference retains the original H.264 packets, with the
same calibrated sound offset and gain:

```sh
ffmpeg -i /tmp/native-demo/NativeDemoRaw/screen.mp4 \
  -i /tmp/native-demo/NativeDemoRaw/audio.caf \
  -filter_complex '[1:a]atrim=start=12.871520875:duration=537.736667,asetpts=PTS-STARTPTS,volume=17dB[a]' \
  -map 0:v:0 -map '[a]' -c:v copy -c:a aac -b:a 192k \
  -t 537.736667 -movflags +faststart /tmp/la-grilla-session-original.mp4
```

The default sync estimate is the midpoint of the measured video-start bracket.
Audio offset is `video_host_start − first_audio_host_seconds`. This is bounded
host-clock synchronization, **not a physical iPhone latency measurement**.
`--video-host-start` can select a verified point inside that bracket.
`--sync-adjust-ms` requires `--sync-note` and is retained verbatim in the receipt;
review Play/onset and later FX/Stop transitions against the actual waveform.
Do not call this frame-exact synchronization without independent evidence.

`--gain-db` defaults to zero and refuses an actual-source peak above 0.98 after
gain. `--preset fast` is useful for a first real-media layout review. Video
chapters encode once into temporary H.264/Float32 intermediates; the final MP4
copies their video and encodes the concatenated sound to AAC once. No input
files are overwritten. Exact encoded bytes may differ with FFmpeg and fonts.
Variable-rate source frames retain their original timing. The seek preserves
pre-cut decoder frames so an idle screen keeps its actual preceding state;
30 fps sampling may delay a visual update by at most one delivery frame.

The capture workflow and four authored UI journeys are documented in
[Demos](../../Demos/README.md). Original capture, source/version, acceptance
results, individual frame review and any remaining limits belong with the
published media. Simulator capture does not establish physical audio-route,
USB/BLE, live-human voice, real-model or App Store acceptance.
