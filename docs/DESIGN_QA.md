# R8.1 — native Design 2026 acceptance

Candidate **1.0.0 (12)**. [Direction and OpenArt provenance](../Design/2026/README.md) · [current Apple HIG references](../Design/2026/HIG_REVIEW.md).

## What changed

The musical grid and bright vertical playhead establish the identity. A compact project header, one transport and three navigation destinations give more space to the music. Graphite/ivory surfaces have a lime primary action and consistent amber harmony, periwinkle drums and aqua bass colors. The light palette is independently contrast checked.

Harmony keeps original/proposed chords together and fixes A/B audition and Apply at the bottom. Perform prioritizes section launches, live FX and a saved take's replay/export. Jam uses sixteen consistent playable pads with recording guidance on demand. The mixer adapts to a 375-point viewport while keeping pan, Mute/Solo and master reachable. Assistant, voice review, note editing and export use the same surfaces and action hierarchy.

Navigation uses native Liquid Glass on iOS 26; Reduce Transparency and earlier supported systems use an opaque surface. Content remains opaque. Buttons expose press/disabled/selection feedback, with 44-point standard targets and 48-point prominent actions. Precision musical canvases retain accessible editing alternatives. Fixed interface fonts have an 11-point floor; Dynamic Type alternatives, increased contrast and Reduce Motion are implemented. Manual VoiceOver usability still needs device acceptance.

## Verification record

Source `72d81cb8a7be054d2e00457f4d30461a99e67b1f` passes all three jobs in [43700372709](https://github.com/alexgazin/la-grilla/actions/runs/43700372709): **64 Swift tests, independent export readers, 11 C++ suites, both SDK builds, optimized archive and 22 native tests** (19 Studio flows plus three capture methods). [54 original PNGs](../Screenshots/Design2026) and [12 unchanged Store copies](../Screenshots/AppStore) are retained with source/run/dimensions/SHA-256. Root previews follow this collection.

The presentation audit checks 480 matching EN/RU keys, formatting placeholders, fixed font sizes, AA color tokens and the unchanged opaque 1024-pixel OpenArt icon. Release auditing confirms matching version/build settings, bundled resources and the current SDK in the optimized archive.

Native regression exposed an actual touch defect: the custom quiet button style left the empty spacer inside the visible guide row outside its interactive shape. The failure hierarchy recorded a 14.3-point button frame despite the 44-point visual row; a central tap did not expand it. The shared style now defines the complete rectangular label as interactive. Jam Pads/Steps also put their 44-point frames inside the actual button labels. The passing regression taps the guide's empty center, checks localized expanded/collapsed state, checks control bounds and verifies both translated hints without English fallbacks. Tempo assertions use the actual field value: Apply shows 110 BPM, Undo restores 120 BPM, and Cancel leaves 120 BPM unchanged.

The final visual implementation prevents the 11-point Grid tool labels from shrinking and lets effect captions wrap instead of reducing their size. Source `d63be9e` passes all three jobs in [43699657512](https://github.com/alexgazin/la-grilla/actions/runs/43699657512): 64 Swift tests, independent export readers, 11 C++ suites, both SDK builds, optimized archive and all 19 Studio flows. The Russian guide regression passes with actual 44-point control bounds, center taps, translated hints and expanded/collapsed state. This closes the software touch defect.

Capture compares successive raw pixel buffers, waits for a stable frame where possible and preserves the final original PNG bytes. Moving Perform views use a bounded wait. Originals are inspected individually; read-only pixel checks confirm header and transport content in all 15 root-layout fixtures. All 54 PNGs are opaque RGB. Pro Max originals are 1320 × 2868 and compact originals are 750 × 1334; the landscape image retains its native EXIF orientation.

## Remaining release gates

No signed IPA, TestFlight installation, physical audio/MIDI measurements, App Review submission or production publication is established by these checks. The [installed-device acceptance matrix](release/DEVICE_ACCEPTANCE.md) and [release procedure](release/RELEASE.md) remain required. The OpenArt direction is a concept board; product screenshots must be unchanged native captures, with source/run/dimensions/SHA-256 recorded.
