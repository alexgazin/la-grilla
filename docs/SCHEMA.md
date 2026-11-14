# Project schema v1

A `.grilla` directory contains `manifest.json`, optional `backup.json`, and no user-supplied assets in v0.1. Foundation JSONEncoder/Decoder encode UUIDs as strings, dates as seconds since 2001-01-01, enum values as documented Swift raw strings, and integral ticks as JSON integers.

The canonical typed schema is `Packages/MusicDomain/Sources/MusicDomain/Model.swift`. Required top-level fields: `id`, `schemaVersion`, `revision`, `name`, `bpm`, `keyRoot`, `minor`, `modified`, `tracks`, `patterns`, `sections`, `bassOctave`, `bassGate`, `master`.

Tracks have independent stable UUIDs, role/preset version, dB gain, equal-power pan, mute, solo and clip instances. Each clip references a pattern and has start/length/offset ticks. A pattern has length and separate chord/drum event arrays. Chord events contain a UUID, start, duration, pitch-class root, quality and inversion; their actual voicing is compiled deterministically. Drum events contain UUID, tick, pad 0–15 and velocity 1–127. Sections have UUID, name, start and length and cover the song without gaps.

Validation rejects unsupported schemas, missing pattern references, duplicate entity IDs, nonfinite/out-of-range controls, overlapping chords/clips, out-of-bounds events, excessive density and invalid section coverage. Loading also limits manifest size. There is no import/archive extraction API in this build. Unknown newer schemas are not migrated or overwritten. Older schema migration will be implemented when a second schema actually exists.
