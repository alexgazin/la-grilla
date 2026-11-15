# Recorded human singing: reproducible development baseline

The unchanged production `VoiceAnalyzer` reaches **95.88% confidence-qualified F0 accuracy** on eight fixed Vocadito recordings, but note onset/pitch F1 is only **60.28% / 54.95%** against the two annotators. Track 2 fails the exploratory 90% F0 criterion. Voice-to-MIDI still requires review and correction; these results do not establish physical iPhone capture or release readiness.

## Source and attribution

Rachel M. Bittner, Katherine Pasalo, Juan José Bosch, Gabriel Meseguer-Brocal and David Rubinstein (2021), *vocadito: A dataset of solo vocals with f0, note, and lyric annotations*, v3. Source: [DOI 10.5281/zenodo.5578807](https://zenodo.org/records/5578807); [authors' paper](https://arxiv.org/abs/2110.05580). The primary record specifies [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): retain attribution, link the license and identify changes when sharing derived material.

The corpus contains recorded solo human singing, reference F0 and two independent note annotations, A1 and A2. Reference notes contain onset seconds, frequency Hz and duration seconds. Note boundaries, ornaments and pitch glides involve human judgement; neither annotation is an absolute physical truth. This benchmark converts/truncates analyzer input and derives metrics; the cached source files remain unchanged. Lyrics are not extracted or used.

The published ZIP is 58,492,257 bytes with published MD5 `dea40fd18f14d899643c4ba221b33a46`. The repository downloader verifies full-archive size/MD5 before extracting the selected files, then verifies their pinned SHA-256 in [the manifest](../Tools/VoiceBenchmark/vocadito-v3-manifest.json). The original experiment instead fetched selected members by HTTP Range and verified CRC32/SHA-256; it **did not** recompute the full-archive MD5. Existing source files can be reused after SHA-256 verification. The development subset contains 17,846,965 uncompressed bytes including annotations and metadata. Keep corpus files, processed audio and generated reports outside every repository checkout; none belong in the app bundle.

## Manual reproduction

From the repository root, use Python 3.12 or newer and Swift 6.1 or newer. Install the pinned scientific dependencies into an external environment:

```sh
python3 -m venv /tmp/la-grilla-voice-venv
/tmp/la-grilla-voice-venv/bin/python -m pip install -r Tools/VoiceBenchmark/requirements.txt
/tmp/la-grilla-voice-venv/bin/python scripts/benchmark_human_voice.py --cache-dir /tmp/la-grilla-voice-cache --output /tmp/la-grilla-voice-report.json --download
```

Repeat the last command **without `--download`** for offline reuse. Missing or corrupt inputs must fail without that explicit flag; even with it, an intact cache needs no network. The required `--output` also produces adjacent `.analysis.json` and `.protocol.json` files. `--cache-dir` defaults under `XDG_CACHE_HOME` or `~/.cache/la-grilla/voice-benchmark/vocadito-v3`; optional `--scratch-dir` defaults under `/tmp/la-grilla-voice-benchmark-<worktreehash>`. Cache, output and Swift scratch/build paths inside any Git worktree are rejected.

`GRILLA_SWIFT_BIN`, then `GRILLA_SWIFT`, then `swift` on `PATH` selects the Swift **executable path**, for example `/opt/swift/usr/bin/swift`; no shell command is evaluated. Dependencies are pinned in [requirements.txt](../Tools/VoiceBenchmark/requirements.txt).

The CLI evaluates development IDs **1–8 only**. There is no holdout-selection option. Ordinary builds, unit tests and CI do not invoke this manual downloader/benchmark, and the Swift executable calls the real production MusicDomain implementation instead of copying the analyzer.

## Fixed protocol

The original protocol was declared before analysis on 2026-11-15. IDs 1–8 were selected in ascending numeric order, without looking at scores: eight excerpts, six singers, 183.765306 analyzed seconds. Analyze from time zero for `min(30.000 seconds, original duration)`; tracks 1 and 2 are truncated. Original mono PCM16 at 44.1 kHz becomes Float32 by division by 32768. Production preprocessing, default YIN, internal 8 kHz analysis, 64 ms windows and 10 ms hops remain unchanged. Score actual `VoiceAnalyzer.frames`, `analyze` and `notes`; MIDI conversion uses 120 BPM, PPQ 960, quantization off and no scale projection.

- **F0:** match the nearest reference sample to each analysis-window center, within half the maximum reference hop. Reference F0 = 0 is unvoiced. Pitch tolerance is ±50 cents, with no octave folding. The primary denominator is reference-voiced frames with predicted F0 and confidence ≥0.72. Also report voiced misses, recall, confident-frame coverage and false voiced frames among reference-unvoiced frames.
- **Notes:** score A1 and A2 separately with one-to-one maximum-cardinality matching, pitch ±50 cents and onset ±50 ms. The stricter score also requires offset error ≤`max(50 ms, 20% of reference duration)`. Exclude reference notes starting beyond the analyzed interval; truncate overlapping reference offsets at its end. Score all predicted notes, including difficult and quiet passages.
- **Criterion:** aggregate confidence-qualified F0 accuracy ≥90% was exploratory, with coverage and recall disclosed. It is not a per-track pass, a note-transcription threshold, a population estimate or a release gate.

## Measured production baseline

These are the preserved Linux/Swift 6.1.2 release-build results, with NumPy 2.3.5 and SciPy 1.17.0. A new run must report its own source/input/tool hashes; it must not silently inherit these historical values.

| Metric | Baseline |
| --- | ---: |
| Confidence-qualified F0 accuracy | 95.88% = 11,577 / 12,075 |
| Correct F0 including reference-voiced misses | 94.27% = 11,577 / 12,281 |
| Voiced recall | 98.32% = 12,075 / 12,281 |
| Confident predictions / all evaluated frames | 70.51% = 12,924 / 18,329 |
| False voiced / reference-unvoiced frames | 14.04% = 849 / 6,048 |
| One-octave errors, within ±50 cents | 270 frames |
| Note onset+pitch F1, A1 / A2 | 60.28% / 54.95% |
| Note onset+pitch+offset F1, A1 / A2 | 42.76% / 38.36% |
| Predicted notes / A1 notes / A2 notes | 587 / 498 / 414 |

**Track 2 reaches only 88.04% F0 accuracy**, with 250 of the 270 octave-error frames; its onset+pitch F1 is 49.30% / 45.80%. Aggregate F0 success therefore does not imply reliable transcription of every singer, note, pause or boundary.

Post-hoc A1↔A2 agreement, using the same matching/truncation rules, is **72.37% onset+pitch F1** (330 matches; 498 versus 414 notes), or **60.09% with offsets** (274 matches). This contextual comparison is neither a replacement pass criterion nor a theoretical ceiling. Production still differs materially from both annotators.

Historical SHA-256 anchors:

| Artifact | SHA-256 |
| --- | --- |
| Production `VoiceAnalyzer.swift` | `40d3716929973607990355be89d7f7fa8dcb04cf46354846de380b01ab10b47a` |
| Original subset manifest | `e3740a3a993dcc54c0fb765d09f4a8bf4c4c82b9d3dfe9b56129115a257cf8a8` |
| Original production analysis | `35acf896be008c43a63c83ce9ef5956b8e6404b76603e8a4ba1d537cbd441dbe` |
| Original benchmark report | `1199af61b650fc19eda72a136679fff219ffbd48cf5c04fd8c9107615d0deaa0` |

The original declaration recorded source HEAD `265410fa0c094c2467851cc99421c4918d38afed`; these hashes describe that experiment, not future revisions. Preserve raw member hashes, exact Float32 input hashes, frame/note output, counts, protocol and tool/source provenance with each external report.

## Experiments, reserved holdout and limits

Four offline segmentation variants tested hysteresis, short-gap merging, higher confidence and shorter release. The control exactly reproduced all 587 production MIDI notes. **No candidate met the predeclared improvement guards**, so production remains unchanged. Mean onset+pitch F1 fell from 57.61% to 52.63–53.00%. A confidence variant reduced false-positive **MIDI occupancy** from 13.54% to 7.41%, but recall fell from 91.26% to 88.51%; shorter release reduced recall to 80.97%. These occupancy figures are distinct from the raw F0 false-voiced rate of 14.04% above.

IDs **9–16 remain reserved and unevaluated**: a separate external preparation downloaded and integrity-checked their opaque annotation bytes and WAV headers, but did not inspect F0/note values or compute scores. This CLI does not extract, select or score them; the transient complete ZIP still contains their compressed members. IDs 1–8 are now development data and must never be relabelled unseen. Evaluate a justified frozen candidate on the holdout once under a declared protocol; do not spend it on already inferior variants.

The separate 52 synthetic sustained/repeated-note/transition/silence/noise controls passed for the control and all four variants; that did not make the human-data regressions acceptable. See [VOICE_QA.md](VOICE_QA.md) for synthetic software checks and outstanding device acceptance. This recorded-corpus benchmark does not verify microphone permissions, physical iPhone routes, count-in latency, acoustic bleed, room noise, interruptions, real-time performance or physical dropout absence.
