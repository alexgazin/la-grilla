# Design 2026 — native acceptance

**54 original PNGs**, candidate **1.0.0 (12)**, source `72d81cb8a7be054d2e00457f4d30461a99e67b1f`. [Complete successful run 43700372709](https://github.com/alexgazin/la-grilla/actions/runs/43700372709) passes all three jobs: 64 Swift tests, independent export readers, 11 C++ suites, both SDK builds, optimized Release archive, 19 Studio flows and three capture methods (22 native tests across Pro Max and SE).

[manifest.json](manifest.json) records every original's source, run, dimensions and SHA-256. All 54 files are opaque 8-bit RGB PNGs retained byte-for-byte. Pro Max frames are 1320 × 2868; the 375-point iPhone SE (3rd generation) simulator frames are 750 × 1334. The landscape original retains its native EXIF orientation. Toolchain: Xcode 26.3 / iOS 26.2.

[Grid](grid.png) · [Jam](jam.png) · [Mixer](mixer.png) · [Notes](notes.png) · [Harmony](harmony-proposal.png) · [Perform](perform-take.png) · [Assistant](assistant-proposal.png) · [Voice](voice-draft.png) · [MIDI](midi-mapped.png) · [Projects](projects.png)

[Grid RU](grid-ru.png) · [Mixer RU](mixer-ru.png) · [Voice RU](voice-ru.png) · [Light Grid](grid-light.png) · [Large notes](notes-large.png) · [Large mixer](mixer-large.png) · [Large pads](jam-large.png) · [Landscape Jam](qa-landscape-jam.png)

[Small Grid RU](compact-grid-ru.png) · [Small Jam RU](compact-jam-ru.png) · [Small Mixer RU](compact-mixer-ru.png)

The twelve `store-*` originals are copied unchanged into [AppStore](../AppStore). The four root previews follow this accepted collection; [R0](../R0) preserves the former root images. [Design QA](../../docs/DESIGN_QA.md) records the actual touch regression and verification. Physical audio/MIDI, manual VoiceOver usability, signing, TestFlight and App Review remain release gates.
