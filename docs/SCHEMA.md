# Project schema v14

A `.grilla` directory contains `manifest.json`, optional `backup.json`, and optional original recordings at `Assets/<UUID>.caf`. Foundation JSONEncoder/Decoder encode UUIDs as strings, dates as seconds since 2001-01-01, enums as their Swift raw strings, and ticks as integers. The canonical storage model and validator are [`Model.swift`](../Packages/MusicDomain/Sources/MusicDomain/Model.swift); assistant proposals have their own version numbers and [JSON contract](assistant-proposal.schema.json).

## Project, timing and limits

Required top-level fields are `id`, `schemaVersion`, `revision`, `name`, `bpm`, `keyRoot`, `minor`, `modified`, `tracks`, `patterns`, `sections`, `bassOctave`, `bassGate` and `master`. Optional fields are `masterFX`, `performanceTakes`, `audioAssets` and `midi`. Computed properties such as `length`, `keyName` and the `performanceTake` convenience accessor are not additional JSON fields.

Timing is 960 ticks per quarter note and 3840 ticks per 4/4 bar. Sections cover the song consecutively without gaps, each with UUID, nonempty name of at most 120 Swift characters, start and length. A project contains 1–8 sections and 1–64 bars. `bpm` is finite and in 40–240; `keyRoot` is 0–11. Names are bounded to 120 characters; project names must also contain non-whitespace text.

`revision` is an integer from 0 through `Int32.max` (2,147,483,647), including revisions in frozen take sources. History edits, Undo and Redo use a monotonically increasing revision. An exhausted revision refuses a new edit; Undo/Redo preserve both the project and history when they cannot advance. A copied/imported project receives a new ID and revision 0. Revisions never wrap to reuse a request/save/playback identity.

Tracks have stable UUIDs, a `role`, optional nonempty `name` of at most 40 characters, `presetVersion`, `gain`, `pan`, `mute`, `solo` and `clips`. There are 2–8 tracks: Harmony and Drums first, then at most one root Bass and independent Melody tracks. Track/master gain is finite −61…6 dB, pan −1…1, bass octave −1…1 and bass gate 0.1…1. Preset versions 1 and 2 are recognized. Master is bus 8; track buses are 0–7. MIDI channels are zero-based 0/1/9 for Harmony/Bass/Drums and 2–7 for melody tracks.

A clip has UUID, `patternID`, `start`, `length`, `offset` and optional `sourceAssetID`. Starts are nonnegative, lengths positive, offsets are within the referenced pattern, and clips cannot overlap on one track or exceed the song. Clips may begin/end between bars; pattern lengths are whole bars from 1 bar through the song length. A source pattern repeats when a clip is longer than it, starting at its offset. At most 64 patterns are retained.

Patterns contain UUID, length, chord/drum arrays and an optional note array (new encodings include notes). Chord events have UUID, tick, positive duration and a chord; they may not overlap. Drum events have UUID, tick, pad 0–15 and velocity 1–127. Melody notes have UUID, tick, positive duration, MIDI pitch 0–127, velocity 1–127 and optional finite confidence 0–1. Events must fit their patterns. Per-pattern limits are 256 chords, 4096 drum hits and 4096 melody notes. Validation also limits the conservative repeated-event expansion to 65,536 and actual compiled notes to 32,768. All entity UUIDs in the current project must be unique; frozen take sources are validated as separate projects.

## Chords, formulas and voicings

A serialized chord has required `root`, `quality` and `inversion`, and optional `slashBass`, `voicedNotes` and `customIntervals`. Roots/bass notes are pitch classes 0–11. `quality` is one of the 65 exact raw strings below; `""` means major. `ChordFamily` is a UI grouping, not a serialized chord field. Likewise `symbol`, `notes`, `effectiveIntervals`, `requiredVoicingIntervals` and complete/compact layout choices are computed/runtime values.

Version 8 adds `customIntervals`: 2–8 strictly increasing integer semitone offsets in 0–48, beginning with 0. When present, this formula supplies the musical intervals and `quality` must be the canonical major marker `""`. The initializer/parser normalizes that marker; a raw decoded formula with another quality is rejected. `inversion` is nonnegative and less than the effective interval count (maximum 7). A formula can deliberately contain octave doublings. The canonical symbol `C{0,4,7,10,14}/E` is text notation for the formula; it is not an extra JSON property.

Without `voicedNotes`, note generation uses MIDI 60 for a C root and `48 + root` for other roots, adds the effective offsets, raises the first `inversion` tones by octaves while avoiding duplicate MIDI pitches, and adds an explicit slash bass below the other tones. A realized chord must contain 1–9 distinct MIDI pitches in 0–127. Root Bass follows `slashBass` when present, otherwise `root`.

With `voicedNotes`, the saved MIDI pitches determine playback/export (ordering is normalized for playback). Let A be the allowed pitch classes from all effective intervals plus slash bass, R the required classes after the table's permitted compact omissions plus slash bass, and V the saved pitch classes. Validation requires **R ⊆ V ⊆ A** and unique MIDI pitches. Ordinary preset voicings may omit only the intervals listed below, including when read from storage; complete Harmony Lab generation keeps all preset intervals. Compact generation requests the required intervals. Custom formulas allow no omissions and preserve the multiplicity of every pitch class, including written octave doublings and an explicit slash bass. The table is the entire omission policy; the `7alt` palette may omit interval 15 while retaining its sharp fifth and flat ninth.

Intervals and omission columns are semitones from the root. A dash means no omissions. The first two columns describe catalog/UI metadata; the exact raw quality string alone is stored in `quality`.

| Family | Raw quality | Intervals | Permitted compact omissions |
| --- | --- | --- | --- |
| Basic chords | `""` (major) | 0, 4, 7 | — |
| Basic chords | `m` | 0, 3, 7 | — |
| Basic chords | `dim` | 0, 3, 6 | — |
| Basic chords | `aug` | 0, 4, 8 | — |
| Suspended chords | `sus2` | 0, 2, 7 | — |
| Suspended chords | `sus4` | 0, 5, 7 | — |
| Sevenths | `7` | 0, 4, 7, 10 | — |
| Sevenths | `maj7` | 0, 4, 7, 11 | — |
| Sevenths | `m7` | 0, 3, 7, 10 | — |
| Sevenths | `m7b5` | 0, 3, 6, 10 | — |
| Basic chords | `6` | 0, 4, 7, 9 | — |
| Basic chords | `m6` | 0, 3, 7, 9 | — |
| Basic chords | `add9` | 0, 4, 7, 14 | 7 |
| Extensions | `9` | 0, 4, 7, 10, 14 | 7 |
| Extensions | `maj9` | 0, 4, 7, 11, 14 | 7 |
| Extensions | `m9` | 0, 3, 7, 10, 14 | 7 |
| Extensions | `11` | 0, 4, 7, 10, 14, 17 | 7, 14 |
| Extensions | `m11` | 0, 3, 7, 10, 14, 17 | 7, 14 |
| Extensions | `13` | 0, 4, 7, 10, 14, 17, 21 | 7, 14, 17 |
| Altered chords | `7b9` | 0, 4, 7, 10, 13 | 7 |
| Altered chords | `7#9` | 0, 4, 7, 10, 15 | 7 |
| Altered chords | `7#11` | 0, 4, 7, 10, 18 | 7 |
| Altered chords | `7b13` | 0, 4, 7, 10, 20 | 7 |
| Sevenths | `dim7` | 0, 3, 6, 9 | — |
| Sevenths | `7#5` | 0, 4, 8, 10 | — |
| Sevenths | `maj7#5` | 0, 4, 8, 11 | — |
| Sevenths | `mMaj7` | 0, 3, 7, 11 | — |
| Extensions | `mMaj9` | 0, 3, 7, 11, 14 | 7 |
| Extensions | `mMaj11` | 0, 3, 7, 11, 14, 17 | 7, 14 |
| Extensions | `mMaj13` | 0, 3, 7, 11, 14, 17, 21 | 7, 14, 17 |
| Extensions | `maj11` | 0, 4, 7, 11, 14, 17 | 7, 14 |
| Extensions | `maj13` | 0, 4, 7, 11, 14, 17, 21 | 7, 14, 17 |
| Extensions | `m13` | 0, 3, 7, 10, 14, 17, 21 | 7, 14, 17 |
| Extensions | `6/9` | 0, 4, 7, 9, 14 | 7 |
| Extensions | `m6/9` | 0, 3, 7, 9, 14 | 7 |
| Basic chords | `add2` | 0, 2, 4, 7 | — |
| Basic chords | `add4` | 0, 4, 5, 7 | — |
| Basic chords | `add11` | 0, 4, 7, 17 | 7 |
| Basic chords | `madd9` | 0, 3, 7, 14 | 7 |
| Basic chords | `madd11` | 0, 3, 7, 17 | 7 |
| Suspended chords | `7sus2` | 0, 2, 7, 10 | — |
| Suspended chords | `7sus4` | 0, 5, 7, 10 | — |
| Suspended chords | `9sus4` | 0, 5, 7, 10, 14 | 7 |
| Suspended chords | `13sus4` | 0, 5, 7, 10, 14, 21 | 7, 14 |
| Altered chords | `7b5` | 0, 4, 6, 10 | — |
| Altered chords | `9b5` | 0, 4, 6, 10, 14 | — |
| Altered chords | `9#5` | 0, 4, 8, 10, 14 | — |
| Altered chords | `maj7b5` | 0, 4, 6, 11 | — |
| Altered chords | `m7#5` | 0, 3, 8, 10 | — |
| Altered chords | `m9b5` | 0, 3, 6, 10, 14 | — |
| Altered chords | `9#11` | 0, 4, 7, 10, 14, 18 | 7 |
| Altered chords | `13#11` | 0, 4, 7, 10, 14, 18, 21 | 7, 14 |
| Altered chords | `13b9` | 0, 4, 7, 10, 13, 21 | 7 |
| Altered chords | `13#9` | 0, 4, 7, 10, 15, 21 | 7 |
| Altered chords | `7b9#11` | 0, 4, 7, 10, 13, 18 | 7 |
| Altered chords | `7#9#11` | 0, 4, 7, 10, 15, 18 | 7 |
| Altered chords | `7b9b13` | 0, 4, 7, 10, 13, 20 | 7 |
| Altered chords | `7#9b13` | 0, 4, 7, 10, 15, 20 | 7 |
| Altered chords | `7#5b9` | 0, 4, 8, 10, 13 | — |
| Altered chords | `7#5#9` | 0, 4, 8, 10, 15 | — |
| Altered chords | `7alt` | 0, 4, 8, 10, 13, 15 | 15 |
| Altered chords | `maj7#11` | 0, 4, 7, 11, 18 | 7 |
| Altered chords | `maj9#11` | 0, 4, 7, 11, 14, 18 | 7 |
| Altered chords | `maj13#11` | 0, 4, 7, 11, 14, 18, 21 | 7, 14 |
| Suspended chords | `7sus4b9` | 0, 5, 7, 10, 13 | 7 |

Text parsing accepts the canonical symbols and documented aliases, including `CM7`/`CΔ7` versus `Cm7`, `C6/9` (internal slash), `C7(b9,#11)` and custom braces. Aliases are normalized into the stored quality/formula. Unknown suffixes are rejected. Assistant command tokenization preserves commas inside parentheses/braces. Input text parsing is distinct from the serialized `quality` raw-string enum.

## Clips and safe editing

Version 8 does not introduce a different clip or drag-storage format. `ClipEditing` uses bounded, project/revision-scoped identity payloads to move/copy/resize clips, set offsets and create/delete clips. Copies clone patterns and event IDs; moves retain their source. Occupied musical material and original-recording associations are not silently overwritten by a drop; only empty, unrecorded placeholders may be split/replaced. Snapping is a UI/operation parameter, not a stored clip field.

Section duplicate/delete/reorder operations split crossing clips and preserve their offset/loop phase and source-asset associations. Duplicated sections clone their copied musical patterns. A shortened song materializes references whose source pattern would otherwise exceed the new song length. A rejected operation leaves the original project unchanged. Source-pattern editors expose loop-sharing behavior. Drum recording separately materializes the focused occurrence into an independent linear draft, maps touches to its actual clip span, then commits the take through one History edit; it does not rewrite another clip's source pattern.

## Assistant proposals

The separate [proposal JSON Schema](assistant-proposal.schema.json) describes the canonical JSONEncoder envelope. Exactly eight top-level fields are used: `id`, `schemaVersion`, `projectID`, `baseRevision`, `scopeSectionID`, `operations`, `assumptions` and `warnings`. Payloads are limited to 64,000 bytes, 1–16 operations, and at most 16 assumptions and 16 warnings of at most 500 Swift characters each. A proposal's project/revision must match the current project and its scope must exist. Section-targeted operations must use that scope ID.

Proposal version 1 permits `setTempo(bpm)`, `setKey(root,minor)`, `renameSection(sectionID,name)`, `resizeSection(sectionID,bars)` and `setProgression(sectionID,chords,durations)`. Version 2 also permits `arrangeSong(sections)`, `styleHarmony(sectionID,style)` and `styleSong(style)`. The constructor selects version 2 when one of those new operations occurs; version 2 may also contain legacy operations. Version 1 still uses the current project's chord representation, including custom formulas; it is not project schema v1. Unknown fields/operation types are rejected by the proposal decoder. Each operation must have precisely its non-nil parameters; the canonical encoder omits nil optional fields. The JSON Schema intentionally forbids unrelated null operation parameters that Codable may otherwise decode as absent.

`setProgression` has 1–256 chords with the same number of positive 1–64-bar durations, summing exactly to the target section length. `arrangeSong.sections` contains 1–8 objects with exactly `name`, `bars`, `chords`, `durations` and `sourceSectionID`. Each has 1–64 bars and 1–64 chords with matching positive bar durations summing to its bars; the complete form fits 64 bars. Arrangement names additionally reject whitespace-only text and control characters. Every source ID refers to the original request project. Rhythm/melody are copied from those immutable sources, repeated/trimmed to the reviewed lengths. The first new section retains the scope ID; other new sections/patterns/events receive fresh IDs. Track IDs, mix/MIDI configuration, source recordings and frozen takes remain available; derived root bass is compiled from the new harmony.

Styles are the exact strings `voiceLeading`, `gentle`, `expressive` and `reharmonize`. They invoke Harmony Lab; `styleSong` skips empty harmony sections and requires at least one nonempty section. They do not carry register/layout/family fields. Harmony changes are materialized without modifying surrounding sections, rhythm or melody. Custom formulas may be revoiced but are not replaced by preset intervals.

The real on-device FoundationModels path is guarded by iOS 26, device/model availability and selected-language support. Its typed musical interpretation is converted to the same checked proposal; portable proposal JSON contains no provider credentials or executable code. Supported local commands, including explicit multi-section `Song:` commands and jazz commands, remain available without that model. Model generation quality still requires supported-device/human verification; SDK compilation and deterministic command tests are not evidence of model responses.

JSON Schema checks shape, enum/range/count bounds and unknown keys. Swift candidate validation additionally checks project identities, equal array lengths, duration sums, total form length, interval ordering, quality/formula/inversion relations, voicing pitch-class/multiplicity math, density and the complete resulting project after **every operation**. Swift counts string bounds in extended grapheme clusters; schema `maxLength` uses the JSON validator's Unicode character definition. A structurally valid JSON document is not authorization to apply it. Review/Cancel leaves the source unchanged; Apply uses one History transaction. Revision advance prevents a duplicate/stale proposal, including after Undo.

## Assets, takes, MIDI and portability

Optional `audioAssets` and clip `sourceAssetID` retain up to eight original recordings. An asset stores UUID, lower-case SHA-256, exact byte count, sample rate/duration, origin (`microphone` or explicitly marked `syntheticFixture`), and optional recording timestamp/input latency/capture tempo. Its `Assets/<UUID>.caf` path is derived, not supplied by an arbitrary archive path. Records require 64…12,000,000 bytes, 44.1/48 kHz and 0.05…30.25 seconds; CAF headers, mono PCM format, content length and checksum are checked before source playback/export. MIDI notes remain separate from original audio. Missing/damaged originals report an error rather than substituting another recording.

`masterFX` stores finite filter −1…1 and delay wet 0…0.5. `performanceTakes` contains at most one finite take (the computed `performanceTake` accesses its first value). A take freezes a separate source project with no nested take, source revision, preset versions, sample rate, deterministic seed, frame duration and bounded ordered automation/live events. Replay/export validate that source recursively. All recordings referenced by its source must still be retained in the enclosing project's assets.

Optional `midi` stores input enablement, selected stable endpoint IDs, output ID, optional input channel, destination track UUID and bounded controller mappings. Sustain CC64 and channel-mode controllers are reserved. Deleting a track removes its stale routing/mappings. Input notes/releases/sustain/per-source disconnects can be represented in finite takes. Live audio routing adopts track identities with the musical snapshot; this changes runtime handover, not the persisted MIDI/clip representation.

Manifests are bounded to 8,000,000 bytes. A `.grillapack` is a bounded standard ZIP of stored entries with manifest/CRC metadata and exact expected asset entries (portable container version 2 when originals exist). Imports validate entry names, counts, lengths, CRCs, checksums and project data without extracting arbitrary paths; the portable import cap is 128,000,000 bytes. Normal import creates a new project identity. Unknown project/preset versions and invalid data are rejected without rewriting the original.

## Migration history

All migrations occur in a value copy. Source bytes remain unchanged until explicit save; save retains the prior valid manifest as backup. `ProjectDocument.decode` checks the outer schema and frozen `performanceTakes[].source` schema **before** typed decoding, so a frozen source with a newer schema is reported as a newer document even if it also contains unknown chord strings; no part is migrated. Nested takes are invalid. The migrated outer project and frozen source are fully validated against v8.

| Version | Change |
| --- | --- |
| 1 → 2 | Initialize missing note arrays; retain the source bytes until save. |
| 2 → 3 | Optional slash bass and explicit voicings. |
| 3 → 4 | Optional original audio assets and clip source-asset references. |
| 4 → 5 | Optional master FX and finite frozen-source performance take. |
| 5 → 6 | Optional MIDI configuration and take input events. |
| 6 → 7 | Explicit instrument interpretation; new tracks use preset 2, existing encoded preset 1 remains preset 1. |
| 7 → 8 | Extended 65-quality chord catalog and optional custom interval formulas; existing chords, IDs, notes, clip positions and encoded preset versions remain unchanged. |

The widened chord vocabulary and compact-voicing validation do not rewrite an existing stored voicing. Both live and offline compilation use its persisted pitches. Unknown future schema headers are preflighted in both outer documents and frozen sources; unsupported preset values are rejected during validation.


### Arranged projects in schema 14

A chord event can carry a MIDI velocity from 1 to 127. An omitted velocity uses the historical value of 88. Materializing or copying a passage preserves its written chord dynamics. A project can store the optional `hasComposedEnding` flag to identify a song that initially plays through its ending. Explicit local transport choices can still enable a loop. Migration from schemas 1–13 preserves the original score and transport defaults, including projects frozen inside a performance take. Use build 41 or later to open newly saved schema 14 projects.
