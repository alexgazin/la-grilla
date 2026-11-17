# Design26 visual research — LaGrilla

Accessed: **2026-11-17 (UTC)**. Scope: the six requested public sources, with native SwiftUI translation. No account was created, no purchase was made, no paywalled source code was copied, and no video was generated. This is research and design guidance; it does not modify the app.

## Selected direction

**A precise night-time musical instrument with a luminous signal.** Keep LaGrilla's existing dark identity, acid-lime action accent, purple drums, gold harmony, and teal bass. Make it feel richer through measured surface depth, generous playing areas, typography, useful interaction feedback, and a single coherent motion language. Premium should come from execution and legibility. Treat the musical workspace as the visual centerpiece; navigation and chrome support it.

The numerical palette, spacing, sizing, and timing below are **original implementation proposals**, not values extracted from the source websites. Reconcile them with the app's existing tokens before adopting them.

## Evidence and access limits

The web tool opened all six requested primary domains in one batch. Scrolltide's bare domain failed, but its `www` address succeeded. Snapblocks failed at its bare, `www`, and HTTP addresses, plus public `/components`, `/robots.txt`, and `/sitemap.xml` paths. Exact-domain search returned third-party mentions but no accessible primary page.

The successful results supplied page text, link structure, author descriptions, and public image links. Image clicks returned image placeholders for two sources and fetch errors for Navbar Gallery; they did **not** provide an inspectable rendered image in this tool context. Consequently, this report does not claim to have visually inspected screenshots or experienced live motion. Source-described behavior is identified as such. No screenshot proves persistence, latency, touch ergonomics, or accessibility.

## Six-source coverage

| Requested source | Primary evidence and factual observations | Translation to LaGrilla; inference, not a source claim | Pitfall |
|---|---|---|---|
| [Scrolltide](https://www.scrolltide.co/) | Public library organizes templates, components, sections, UI, and shaders. The [component directory](https://www.scrolltide.co/components) describes Tuner as a ruler picker with a tape, needle, coasting, and station snapping. [Noemi Keys](https://www.scrolltide.co/templates/noemi-keys) describes keyboard presses with sound and physical feedback. These are the site's descriptions, not independently observed animations. | Give tempo a precise ruler/dial identity, clear current value, discrete snap feedback, and direct numeric entry. Pad presses should acknowledge immediately and retain a physical sense of contact. Instrument input is a strong source of character. | The website's keyboard wobble, headline changes, gravity arrival, and cinematic scrolling are unsuitable defaults for a working sequencer. Do not introduce inertia into time-critical editing. |
| [Snapblocks](https://snapblocks.site/) | Primary content was unavailable through the research tool on this date. Alternate protocol/host and likely public paths also failed. Third-party descriptions were found but are insufficient to establish its components, appearance, or behavior. | No specific visual or motion decision is attributed to Snapblocks. Use a shared native component vocabulary for coherence as our own design decision. | Do not fabricate study findings, substitute an unrelated Snapblocks product, or imply its paid materials were inspected. |
| [Scroll Shaders](https://scrollshaders.com/) | Public homepage describes seamless shader loops and components. It explicitly describes pausing offscreen/background, capping rendering density, and replacing motion with a still for reduced motion. [Contour](https://scrollshaders.com/shaders/waves-lines/contour) is described as dark topographic lines with periodic orange signal lines. | A quiet contour or signal field could give the instrument stage subtle depth. Derive its energy from playback or note activity. Keep it behind a clear, opaque editing plane. Apply lifecycle and reduced-motion discipline to native rendering. | Do not place a WebGL marketing background under notes, labels, meters, or touch targets. Constant full-screen effects spend battery and compete with useful signal. Do not copy paid shaders. |
| [Navbar Gallery](https://www.navbar.gallery/) | Public taxonomy separates static/sticky bars, dropdowns, sidebars, search, full-screen menus, breadcrumbs, and other patterns. The [Velt entry](https://www.navbar.gallery/navbar/velt) labels distinct desktop and mobile reference images and classifies the example as a mega menu. Image fetches failed, so its geometry was not inspected. | Separate persistent mode selection, local track selection, and occasional project/settings actions. Adapt navigation to device width using native patterns. Stable navigation should leave space for performance gestures. | A web mega menu, announcement strip, full-screen promotional menu, or desktop navbar copied into an iPhone would obscure the musical task. |
| [Uizze](https://uizze.com/) | Public [design-system index](https://uizze.com/design) describes measured color/font/type references. Its [SwiftUI guide](https://uizze.com/guides/swiftui-design-with-ai) recommends native navigation/controls, semantic type, flexible spacing, safe areas, and native accessibility/interruption checks. Its [reference workflow](https://uizze.com/guides/ui-reference-workflow) distinguishes observation, interpretation, unknown behavior, and verified implementation. | Define the existing app's tokens and interaction contract before spreading the redesign. Use SwiftUI controls and semantics, preserve selection and work across interruption, and judge success on actual devices or simulators. | A polished browser mockup does not establish native accessibility or successful musical interaction. Avoid rigid screenshot-coordinate reconstruction. |
| [Impeccable](https://impeccable.style/) | [Design-system guidance](https://impeccable.style/docs/design-system/) treats implementation and existing screens as evidence and recommends shared components/tokens. [Animate](https://impeccable.style/docs/animate/) ties motion to feedback, continuity, meaningful attention, interruption, repeated actions, and reduced motion. The [slop catalog](https://impeccable.style/slop/) calls out purposeless pulse, decorative glow/glass, nested cards, and excessive bounce. | Make every motion explain input, timing, selection, or continuity. Use one reusable vocabulary for surfaces and control states. Keep activity alive while playback runs; keep the stopped workspace composed. | 'Rich' cannot mean every surface glows or every control moves. Applying anti-slop advice mechanically would also erase LaGrilla's justified purple/gold/teal instrument semantics. |

Additional public Uizze documents read: [design contract](https://uizze.com/guides/design-md-for-coding-agents), [AI UI slop](https://uizze.com/ai-ui-slop), and [guides index](https://uizze.com/guides). Impeccable's [designing workflow](https://impeccable.style/designing/) and [documentation index](https://impeccable.style/docs/) were also read. Their common practical contribution is concrete product constraints, reusable decisions, and inspection of rendered results rather than an adjective-only brief. No plugin installation is required to apply that reasoning.

## Native visual contract — proposed

### Color and surface roles

Use a single cool-neutral family. Suggested working palette:

| Role | Proposed value | Purpose |
|---|---|---|
| Canvas | `#0C0E12` | Stable night background, especially around the editing plane |
| Recessed workspace | `#11151B` | Piano roll and sequencing well |
| Panel | `#171C23` | Track inspector, transport support, sheets |
| Raised control | `#222A34` | Touch controls and selected neutral surfaces |
| Divider/border | `#343E4C` | Structural separation; subtle on large surfaces |
| Primary text | `#F3F5F0` | Values, titles, selected labels |
| Secondary text | `#A8B2BE` | Descriptions and control labels |
| Acid-lime | `#D3F45B` | Main action, play state, global selection |
| Drums | `#B8A1F4` | Drum identity and associated notes/pads |
| Harmony | `#E5BE69` | Harmony identity and associated notes |
| Bass | `#5ACBB9` | Bass identity and associated notes |

Keep instrument hues as role colors; use lime for global action. They need not all appear at full intensity at once. An active purple drum pad can retain purple while a lime transport remains globally active. Use dark text on bright filled controls and verify actual contrast in the implementation. Distinguish recording/destruction with a dedicated red plus icon/label. Do not use a track hue to imply error.

Opaque, lightly differentiated surfaces should carry dense musical content. A native material is appropriate for a floating transport or sheet chrome when it preserves legibility; it is not a universal card texture. Limit depth to a recessed workspace, one panel level, and one raised control level. Prefer a thin top highlight or restrained edge to repeated shadows. The largest radius belongs to the instrument stage, not every cell.

### Typography and rhythm

Use SF's native semantic styles, with a small set of explicit roles. Proposed visual targets at default text size: 28 pt screen title, 20 pt panel title, 17 pt body/action, 13 pt control label, and 11–12 pt compact timing labels. Use monospaced digits for BPM, bars/beats, step numbers, and parameter values. Avoid all-caps microcopy outside a few short section/track identifiers. Keep tab and action names consistent across screens.

Build from a 4 pt rhythm: 16 pt page margins on compact phones, 8 pt between related controls, 16–20 pt between groups. Proposed radii: 10–12 pt controls, 18–20 pt panels, 24 pt main performance stage; pill geometry only for actual chips or segmented selections. Make a deliberate exception for a grid cell. Avoid wrapping every row in an individual card. Typography, alignment, and separators can group information with less visual clutter.

### Navigation and hierarchy

Use persistent native top-level destinations where the product's actual structure calls for them; do not invent destinations just to fill a tab bar. Keep project context and occasional file/settings actions in the header. Keep mode selection distinct from track selection. Track selection should retain the same location, order, icon, and hue across pad, roll, mixer, and instrument views.

Keep a compact transport in a stable reachable location. Reserve the visually dominant central/lower area for the current playing/editing task. Present a track inspector as a native sheet on compact phones and an adjacent inspector on a sufficiently wide layout. Preserve play state, selected track, scroll position, and unsaved edits when opening and dismissing an inspector. Every icon-only action needs an accessible name; unfamiliar actions benefit from a visible text label.

## Interaction and motion contract — proposed

Use touch-down acknowledgement, not a delayed animation that waits for audio or persistence. Functional audio and sequencing must not depend on animation completion. These timings are starting points for device review, not borrowed specifications.

| Interaction | Visible response | Motion proposal | Recovery/access behavior |
|---|---|---|---|
| Pad down / up | Pad compresses, edge brightens, instrument hue becomes more present; label remains readable | Immediate state change; about 70–100 ms compression and 120–160 ms return | Multiple fingers and rapid retriggers remain independent. Cancelled touches release correctly. Optional haptic should never double-trigger audio. |
| Play / stop | Explicit play/pause symbol and active transport fill; playhead shows actual time | 120–180 ms state transition; no startup flourish | Reduced motion keeps the functional position indicator and removes decorative pulse. Stop settles immediately. |
| Track selection | Color, icon, label, and selected surface agree | 160–200 ms restrained transition | Never rely on hue alone; VoiceOver announces selected state. |
| Tempo / parameter drag | Value changes immediately beside the control; focused tick/needle indicates position | Direct manipulation during drag; no animation lag. Short snap feedback after release where appropriate | Tap value for precise entry; accessible adjustable action; restore valid value after invalid input. |
| Note creation / selection | A clear selected note and enlarged handles; duration/velocity feedback near the gesture | Immediate edit; 100–150 ms emphasis only | Undo is reachable. Do not require a hidden long press for the sole path to an essential action. |
| Inspector open / close | Selected track remains visually anchored; editing context survives | Native presentation or restrained 220–280 ms continuity | Dismissal preserves edits and focus predictably. Test interactive dismissal and interruption. |
| Save / export / load | Named pending state, success confirmation, actionable failure | Progress responds to real work; success may receive one brief accent | Retry, cancel, disabled, and unavailable states must be explicit. A decorative spinner must not imply a fake completed operation. |

The 'breathing' layer should be low amplitude and connected to actual music: a soft instrument-stage halo follows envelope energy, a meter reacts to output, a beat emphasis reflects transport timing. It should settle when playback stops. Do not pulse static 'ready' labels. Avoid simultaneous glow, scale, blur, and floating motion on the same control. Under Reduce Motion, keep selection, levels, and timing understandable through static state changes and essential indicators.

For SwiftUI, keep gesture tracking direct, isolate drawing invalidation to the region that changes, respect `accessibilityReduceMotion`, and stop any decorative timeline when inactive or offscreen. Review the cost on supported phones; effects must not compromise audio responsiveness. The appropriate final implementation may use a simple gradient, Canvas, or native shader, but the design does not require copying a third-party renderer.

## Pad and piano-roll ergonomics — proposed

For a 4-column pad grid, preserve approximately 72–88 pt targets on normal phone widths with 8 pt gutters, adjusting to the real supported devices. Put instrument names/short labels consistently in one corner and avoid squeezing two unrelated actions into a pad. Selected, held, sounding, muted, and unavailable are different states and should remain distinguishable. Preserve enough stable blank area for a thumb grip around performance controls.

For the piano roll, separate 'perform' and 'edit' intentions. A 16-step-wide grid squeezed into roughly 320 pt makes each time cell about 20 pt; it is not a reliable precision target by itself. Offer a zoomed editing view (for example eight visible steps), clear note selection, direct drag, explicit handles, and reversible edits. Keep pitch labels anchored while the timeline scrolls. Differentiate bar boundaries from beat subdivisions without equally bright gridlines. The playhead should remain unmistakable without making notes flicker.

Use at least approximately 44 pt comfortable targets for discrete controls and selected-note handles; do not claim that a visually tiny note becomes ergonomic by adding overlapping invisible hitboxes. Support pan/zoom deliberately, give immediate feedback about whether the user is scrolling or editing, and keep gesture cancellation safe. Test rapid pad alternation, simultaneous pads, note dragging near edges, accidental touches, one-handed transport, narrow width, large text, and VoiceOver navigation on the native app.

## What must be checked in the actual app

- Compare at least two existing screens after changing shared primitives so the contract proves useful across different tasks.
- Inspect all control states: default, pressed, selected, held, disabled, busy, success, error, and interrupted where applicable.
- Verify safe areas, landscape/compact widths if supported, larger text, VoiceOver labels/order, Reduce Motion, and increased contrast on native builds. Web research cannot establish these results.
- Test rapid/repeated interaction during playback. A visual flourish must not delay a note, alter audio scheduling, steal a gesture, or move a target under the finger.
- Keep source observations and original LaGrilla decisions distinct in the handoff. Snapblocks remains an explicitly unavailable reference until its primary material can be inspected.

