# C2 — circular live filter, native captures

**55 original PNGs**, candidate **1.0.0 (13)**, source `4fcf4c3a3594af67871d05f3d8ccefcc5dc0b70e`. [Capture run 43713084377](https://github.com/alexgazin/la-grilla/actions/runs/43713084377) passed all three Perform control tests and all three capture methods: general screens, Store localizations and compact iPhone screens.

[manifest.json](manifest.json) records each original's source, run, artifact, dimensions and SHA-256. All files are opaque 8-bit RGB PNGs, preserved byte-for-byte. Pro Max frames are 1320 × 2868; iPhone SE (3rd generation) frames are 750 × 1334. The landscape original retains its native EXIF orientation. Toolchain: Xcode 26.3 / iOS 26.2.

The collector initially misnamed `notes.png` after matching `C2-` inside an exported UUID. Its native attachment name and bytes were verified against the original verification artifact; only the filename was repaired. The manifest records that attachment. The collector now anchors stage prefixes, with a host regression using the actual collision identifiers.

[Perform](perform.png) · [Live filter and saved take](perform-take.png) · [Large text, actual rotary gesture +67%](qa-large-perform.png) · [Russian Perform](store-ru-perform-take.png)

[Grid](grid.png) · [Jam](jam.png) · [Mixer](mixer.png) · [Piano roll](notes.png) · [Harmony](harmony-proposal.png) · [Assistant](assistant-proposal.png) · [Voice](voice-draft.png) · [MIDI](midi-mapped.png) · [Projects](projects.png)

[Small Grid RU](compact-grid-ru.png) · [Small Jam RU](compact-jam-ru.png) · [Small Mixer RU](compact-mixer-ru.png) · [Light Grid](grid-light.png) · [Large notes](notes-large.png) · [Landscape Jam](qa-landscape-jam.png)

The capture run's overall result was failure because an existing MIDI UI test tried to tap a virtualized Form row after a fixed swipe. The product app and all screenshots are unchanged by its test-only correction. Final native regression: [43716116613](https://github.com/alexgazin/la-grilla/actions/runs/43716116613), source `bcc9f60c0dc639fe5ac6bf9f36fae6df644900b8`, **all three jobs successful**: 64 Swift tests, 11 C++ suites, independent export readers, both SDK builds, unsigned Release archive and **22/22 native user flows, zero failures**. The repaired MIDI flow passed. The three capture methods were verified in the capture run, not rerun in this `[ui-only]` regression.

At this milestone the twelve `store-*` originals were copied unchanged into Store assets. Those historical source originals remain here; the current [AppStore](../AppStore) folder now follows the latest accepted collection. [C2-progress](../C2-progress) preserves a separately labelled decoded video preview; it is excluded from these originals and from Store screenshots. Physical audio/MIDI, Apple signing, TestFlight and App Review remain external release gates.
