# La Grilla — Nocturne

Native iPhone design contract, 17 November 2026. This contract governs the SwiftUI app, including new editors. The implementation is build **1.0.0 (24)**; build 23 screenshots and QA remain historical evidence. Runtime validation of 24 must use its own source SHA, screenshots and receipts.

## Product and point of view

La Grilla is a pocket composition and performance instrument. Its character comes from the arrangement, playable pads, notes and channel strips. The user should want to touch the instrument and should understand what the touch will do. Keep the Night identity that the user liked; support an equally deliberate Light appearance.

**A precise night studio, with a luminous musical signal.** Cool graphite, warm ivory, champagne harmony, periwinkle drums, teal bass and citron transport. Richness comes from precise type, optical depth, calibrated controls, immediate contact feedback and useful musical information. Navigation supports the musical surface. Avoid adding decorative dashboards, perpetual animation, competing glass layers or arbitrary marketing illustrations to the editor.

## Shared system

The executable source of truth is [App/Theme.swift](App/Theme.swift).

| Role | Night | Use |
| --- | --- | --- |
| `ink` | `#0C0E12` | Stable canvas and recessed controls |
| `panel` | `#171C23` | Editor panels and console chassis |
| `raised` | `#222A34` | Raised controls and selected navigation |
| `studioText` | `#F3F5F0` | Content, title and principal values |
| `muted` | `#A8B2BE` | Secondary readable labels |
| `outline` | `#343E4C` | Decorative seams; stronger variant for increased contrast |
| `mint` | `#D8F780` | Global primary action, Play and melody |
| `harmony` | `#E5BE69` | Harmony clips and instrument identity |
| `drums` | `#B7BCEF` | Rhythm, pads and drum channels |
| `bass` | `#85D6C3` | Bass clips and channels |
| `record` | `#FF858D` | Recording, errors and destructive actions |

Light and increased-contrast values are explicit semantic variants, rather than an opacity applied to Night. Physical piano keys retain ivory/graphite identity in both appearances. Selection, recording and mute/solo also use an outline, marker, symbol, label or accessibility trait; color is supplementary.

Use SF semantic text styles. Reserve monospaced numerals for bar/beat, BPM, note positions, gain and other changing musical values. Explicit small text stays at least 11 pt. Spacing follows 4/8/12/16/24/32 pt. Shared hit target is 44 pt; primary action height is 48 pt. Controls use radius 12, panels 18 and navigation 22, with deliberate exceptions for instrument faces. Do not put every line of content inside another card.

Surfaces have a readable fill, a restrained edge and occasional top seam. Dense musical planes stay opaque. Navigation may use native material, with a solid Reduce Transparency fallback and a stronger increased-contrast edge. No effect should make text, playhead or note boundaries harder to see.

## Screen and action contract

| Surface | Hierarchy and detail | Required behavior |
| --- | --- | --- |
| Studio shell | Project context above the instrument; related Undo/Redo controls together; one bottom console combines timing, transport and Grid/Jam/Mixer modes. Save color distinguishes saved, unsaved/saving and failed. | Projects, tempo/key/settings, Undo, Redo and Export retain their actions. Play/Stop, Record, Rewind and Loop remain reachable. The four beat marks read the actual engine clock and remain quiet while stopped. No independent fake progress timer. |
| Arrangement | Bar ruler, weaker beat lines, alternating bar planes, continuous role rails and quiet clip faces. Chord name is ivory; voicing and harmony detail use champagne. | Tap, native drag/drop, pinch anchor, section order and inspector remain intact. A playing clip perimeter follows the actual transport; live resize takes visual precedence. No change to musical geometry to create decoration. |
| Jam | Large periwinkle pad faces with inset seams, readable sound identity, exact contact highlight and distinct recording controls. Sound and beat/quantize utilities are discoverable. | Native multi-touch enqueues sound at contact **before** publishing visual held state. Keep the 4×4 hit geometry and accessible named-pad path. Holding or sliding does not create extra strikes. No delayed sound, per-hit spring or haptic queue. |
| Piano roll | Clear ruler/keyboard division, selected note boundary, visible endpoint while resizing and precise position/length readout away from the finger. Sound entry beside editing tools. | Held notes follow the finger without interpolation. Existing draft is visible before release, cancel restores the origin, and commit creates one Undo step. Keep the 44 pt resize target and numeric/list alternative. Large text reflows controls. |
| Sound browser | Current track/instrument at the top, one coherent palette list, selected checkmark, explicit audition action and reserved status area. | Selection and preview remain separate. Preview/Stop use the real engine. Loading/error feedback does not move the main control. Cancel leaves musical data intact; Apply is one undoable change and persists. |
| Mixer | Continuous console, aligned channel slots, calibrated gain ruler, ribbed fader cap, real output meter, visible pan and M/S. Master has a stable separate rail. | Up is louder; reset is explicit; fader edit groups end correctly. Preserve real meters, mute/solo, pan, replay lock and VoiceOver adjustments. Smaller height uses scrolling rather than shrinking targets. Accessibility text sizes use a native Form. |
| Other editors | Existing native sheets, section/track identity, shared buttons, colors, typography and surfaces. | Keep Assistant availability/recovery, dictation Start/Stop, voice analysis, Perform replay/tilt, MIDI, export and project management functional. A redesign must not replace an unavailable model with a fictional success state. |

## Motion and lifecycle

- Audio scheduling and held state are immediate. Frequent instrument actions need no custom animation.
- A held note, resize handle, fader or other direct manipulation follows input without a spring. Release may settle in about 120 ms; infrequent selection can use about 180 ms and a panel about 320 ms with no overshoot. Prefer the existing native sheet transition.
- Changing state can interrupt the previous transition. No delayed enablement, moving target or broad animation attached to the whole grid.
- Reduce Motion removes spatial flourishes; all final states and actions remain. Reduce Transparency supplies solid chrome. Increased Contrast strengthens necessary boundaries.
- Real meters and the engine playhead can move during playback. Stop, background, cancellation and disappearance must stop optional decorative work. No perpetual background shader was introduced.

## Source research and interpretation

The requested primary sites and skill files were researched. Full evidence, pinned repository commits, read paths and transfer limits are in [visual sources](docs/design/research-visual.md), [craft skills](docs/design/research-craft-skills.md), [interaction skills](docs/design/research-interaction-skills.md) and [Stageshow](docs/design/research-stageshow-sub.md).

| Source | Applied principle |
| --- | --- |
| [Scrolltide](https://www.scrolltide.co/) | Instrument-like precision and responsive key/contact feedback, based on public component descriptions |
| [Snapblocks](https://snapblocks.site/) | Primary site unavailable through the research tools; no component or observed behavior attributed to it |
| [Scroll Shaders](https://scrollshaders.com/) | Lifecycle and reduced-motion discipline; no paid shader code copied |
| [Navbar Gallery](https://www.navbar.gallery/) | Separate persistent modes, local tools and occasional project actions |
| [Uizze](https://uizze.com/) | Native SwiftUI contract, semantic type, safe areas and honest distinction between reference and verification |
| [Impeccable](https://impeccable.style/) | Shared tokens, purposeful motion, restrained depth and removal of decorative clutter |
| [Taste Skill](https://github.com/Leonxlnx/taste-skill) | One system, real product information and coherent density; website-specific hero rules do not govern iOS |
| [Emil Design Engineering](https://github.com/emilkowalski/skills) | Immediate input, finger tracking, frequency-aware motion, native type and accessibility |
| [Vercel guidelines](https://github.com/vercel-labs/agent-skills) | Named controls, stable numeric values, recoverable states and native behavior |
| [Anthropic frontend-design](https://github.com/anthropics/skills) | Deliberate subject-specific identity; the user's chosen Night direction takes precedence |
| [Hallmark](https://github.com/Nutlope/hallmark) | Consistent depth, purposeful micro-interactions and reduced-motion states |
| [Make Interfaces Feel Better](https://github.com/jakubkrehel/make-interfaces-feel-better) | Restraint for repeated actions and interruptible transitions |
| [UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Stable 44 pt native targets, feedback, accessibility and gesture alternatives |
| [Stageshow](https://github.com/benjitaylor/skills) | Stable changing controls and geometry that follows the hand; authored fake UI is not runtime evidence |

Research tools returned primary text and links; they did not provide inspectable rendered reference images or interactive motion. No paid component library was copied or installed. Recommendations above are our native implementation decisions, not a claim that those websites supplied a SwiftUI app.

## Delivery and acceptance

1. **Research and contract:** primary-source findings, existing workflow constraints, semantic palette and interaction states.
2. **Implementation:** shared Theme; Studio shell; Grid; Jam; Piano/Sound; Mixer. All screens retain existing action identifiers and musical data contracts. Build 24 distinguishes this work from previously distributed 23.
3. **Static checks:** Swift syntax parse; bilingual catalog and 11 pt floor; semantic token contrast; generated project; release configuration. Linux parsing is not Apple SDK compilation.
4. **Native focused review:** actual Night/Light screen navigation and screenshot attachments; existing pad onset/multi-touch, piano move/resize/Undo, sound preview/apply/store and landscape flows. Inspect actual exported PNGs before calling the design verified.
5. **Integration:** preserve a source-bound focused receipt, screenshots/provenance in the repository and an updated README. Full native inventory remains a separate gate; new real design cases increase that inventory rather than replacing old tests.
6. **Device and distribution:** unsigned IPA with the actual build/source. Physical audio routes, acoustic touch latency, CoreMIDI hardware, real FoundationModels generation and App Store signing remain separate device/release acceptance.

The previous `e22f487` full run observed 73 methods: 70 passed, three failed, no case allowances and no global timeout. Its two Arrangement failures remain recorded; its MIDI fixture queued a seek and admitted edits before render acknowledged it. Build 24 settles that test's positioning while stopped and adds pre-cleanup diagnostics without changing MIDI assertions or production audio behavior. Historical failure evidence must not be relabeled as a pass.

Screenshots must come from the actual app and name source/run/owner. No new custom video recording is authorized.
