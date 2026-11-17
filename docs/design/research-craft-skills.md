# Design 26: craft-skill research for LaGrilla

Research date: **2026-11-17 UTC**. Scope: the four user-requested repositories, applied to the existing **native iOS / SwiftUI** LaGrilla instrument. The user's liked Night direction, musical grid, pads, piano roll, mixer, voice, AI and Perform workflows are the brief. This document is research and implementation guidance; it does not claim that the app has been edited or tested.

## Recommendation

Keep Night and make its musical surfaces the distinctive visual identity. Build richness from a coherent hierarchy of graphite surfaces, clear type, precise track colors, useful waveform/step/note information and responsive instrument states. Spend the strongest visual treatment on the playable grid or pads. Keep navigation, transport and editing chrome quieter. The product should feel like a well-made instrument in a native iOS shell.

The strongest common principle across the sources is **intentional, subject-specific design plus small, consistent interaction details**. A source's website template, randomized palette generator, React dependency, review output format or installation command is not an iOS requirement. None was installed or executed for this research.

## Sources and provenance

All reads used the connected GitHub tools: `github_fetch` for repository metadata, `branches/main` and the recursive Git tree; `github_fetch_file` for the actual README, SKILL and reference contents. The four recursive trees reported `truncated: false`. Files were fetched at the resolved commit, rather than an unpinned moving `main` URL. Commit dates below are commit metadata, not an assertion about when every individual sentence changed.

| Repository | Resolved commit | Commit date (UTC) | Relevant paths actually read |
| --- | --- | --- | --- |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | [`f6b76575f949707b4e3c37cd86cb44b0b98643e8`](https://github.com/Leonxlnx/taste-skill/commit/f6b76575f949707b4e3c37cd86cb44b0b98643e8) | 2026-11-07 12:33:21 | README; the current `design-taste-frontend` SKILL; `references/system.md`; `references/motion.md` |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | [`64eb3deb9a5fbfa041faf783e0bc3fd635872e9c`](https://github.com/emilkowalski/skills/commit/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c) | 2026-11-15 12:42:50 | README; `emil-design-eng`, `apple-design`, `mobile-native`, `write-swift`, `animate`, `gestures`; `ui-cheatsheet.md` |
| [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) | [`1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62`](https://github.com/vercel-labs/agent-skills/commit/1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62) | 2026-10-27 21:40:02 | README; `web-design-guidelines/SKILL.md`; `react-native-skills/SKILL.md` |
| [anthropics/skills](https://github.com/anthropics/skills) | [`e4bb5d960d87126ff3b3a8af1a104b7db67560ba`](https://github.com/anthropics/skills/commit/e4bb5d960d87126ff3b3a8af1a104b7db67560ba) | 2026-11-16 14:22:47 | README; `skills/frontend-design/SKILL.md` |

Vercel's web-design SKILL delegates its actual rules to another repository. That referenced file was also read at a pinned commit:

| Additional referenced source | Commit | Date (UTC) | Read |
| --- | --- | --- | --- |
| [vercel-labs/web-interface-guidelines](https://github.com/vercel-labs/web-interface-guidelines) | [`434b7f91364665f2f733b310ec54809bf8f37937`](https://github.com/vercel-labs/web-interface-guidelines/commit/434b7f91364665f2f733b310ec54809bf8f37937) | 2026-10-05 20:49:16 | [`command.md`](https://github.com/vercel-labs/web-interface-guidelines/blob/434b7f91364665f2f733b310ec54809bf8f37937/command.md), the complete rules |

### Exact file links

Taste Skill:

- [`README.md`](https://github.com/Leonxlnx/taste-skill/blob/f6b76575f949707b4e3c37cd86cb44b0b98643e8/README.md)
- [`skills/taste-skill/SKILL.md`](https://github.com/Leonxlnx/taste-skill/blob/f6b76575f949707b4e3c37cd86cb44b0b98643e8/skills/taste-skill/SKILL.md)
- [`skills/taste-skill/references/system.md`](https://github.com/Leonxlnx/taste-skill/blob/f6b76575f949707b4e3c37cd86cb44b0b98643e8/skills/taste-skill/references/system.md)
- [`skills/taste-skill/references/motion.md`](https://github.com/Leonxlnx/taste-skill/blob/f6b76575f949707b4e3c37cd86cb44b0b98643e8/skills/taste-skill/references/motion.md)

Emil Kowalski:

- [`README.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/README.md)
- [`skills/emil-design-eng/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/emil-design-eng/SKILL.md)
- [`skills/apple-design/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/apple-design/SKILL.md)
- [`skills/mobile-native/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/mobile-native/SKILL.md)
- [`skills/write-swift/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/write-swift/SKILL.md)
- [`skills/animate/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/animate/SKILL.md)
- [`skills/gestures/SKILL.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/gestures/SKILL.md)
- [`ui-cheatsheet.md`](https://github.com/emilkowalski/skills/blob/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/ui-cheatsheet.md)

Vercel:

- [`README.md`](https://github.com/vercel-labs/agent-skills/blob/1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62/README.md)
- [`skills/web-design-guidelines/SKILL.md`](https://github.com/vercel-labs/agent-skills/blob/1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62/skills/web-design-guidelines/SKILL.md)
- [`skills/react-native-skills/SKILL.md`](https://github.com/vercel-labs/agent-skills/blob/1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62/skills/react-native-skills/SKILL.md)

Anthropic:

- [`README.md`](https://github.com/anthropics/skills/blob/e4bb5d960d87126ff3b3a8af1a104b7db67560ba/README.md)
- [`skills/frontend-design/SKILL.md`](https://github.com/anthropics/skills/blob/e4bb5d960d87126ff3b3a8af1a104b7db67560ba/skills/frontend-design/SKILL.md)

All listed resources were available. The research does not claim to have read every file in these repositories, run their bundled checkers, fetched every external article or independently verified each attribution in the secondary skills. In particular, Emil's `apple-design` is its author's interpretation of Apple talks, explicitly translated to the web; treat it as craft guidance, not an official Apple specification. Swift language/version advice must be checked against LaGrilla's actual toolchain and deployment target before adoption.

## What the actual sources say

### Taste Skill: one system, real subject matter, quiet consistency

The current README identifies **tasteskill 2.5.1**. This is a company-website kit, not the older broad taste prompt often quoted elsewhere. Its README says the older `high-end-visual-design`, `minimalist-ui`, `industrial-brutalist-ui` and other skills moved to `Leonxlnx/taste-skill-classics`; those moved repositories were not part of this read.

Useful portable principles, grounded in the current SKILL and its `system.md` and `motion.md`:

- Show the actual product and its real working information. The SKILL's software example asks for its own UI at true size rather than a generic dashboard. For LaGrilla, that means a legible step grid, note events, waveform, mixer channels and actual transport state.
- Use one token system. `system.md` says, **“never add a second grid, spacing scale, type scale, radius, button, card, hairline, fade or link style.”** Its spacing scale is 4, 8, 12, 16, 24, 32, 48, 64, 96, 128. Adapt the smaller values to points and native layouts; do not copy its website section heights or 80–120px gutters.
- Align related edges and avoid boxes nested inside boxes. The SKILL limits nesting and asks for one coherent component family.
- Keep structure mostly neutral and spend accent color deliberately. The website recipe uses 90–95% neutral interface and one accent; LaGrilla additionally needs semantic track colors, with controlled saturation and consistent assignments.
- Every interactive element visibly responds. Motion exists for a named purpose; it never causes layout pushes, randomized blinking or gratuitous tilting. The source's quiet press numbers include a 90ms press and a subtle `.985` scale.
- Under reduced motion, retain state through color/opacity or instant changes, and keep content readable at rest. Controls have accessible names, visible focus, and phone targets of at least 44px.

**Do not port its website mandates.** The no-violet rule, random “deal, never choose by taste” procedure, mandatory 1.1s hero entrance, full-screen sections, photography quotas, obligatory creative moments, shader budgets, one website card recipe, fixed opaque navigation with no blur, logo sourcing scripts and finish-gate scripts are specific to that kit. They can conflict with a native music instrument and with the user's chosen Night palette. No script or hook was run. There is no reason to convert LaGrilla into HTML or React to satisfy them.

### Emil: responsiveness, frequency, physical gestures and system typography

`emil-design-eng` and `animate` ask first whether an animation should exist and what purpose it serves. Their frequency table removes motion from actions repeated 100+ times per day, reduces frequent effects, and allows normal transitions for occasional sheets or modals. This is highly relevant to step taps, pad strikes, mute/solo and transport controls: the user needs immediate state and audio, not an entrance ceremony on each use.

The same sources recommend press feedback around 100–160ms, small popovers around 125–200ms, dropdowns around 150–250ms, and most ordinary UI under 300ms. These are useful starting ranges, not native platform laws. They recommend an immediate responsive curve rather than slow acceleration, small scale changes, origin-aware popovers, and retargetable transitions instead of restarting an animation from zero. Source CSS curves and Motion library APIs should not be copied literally into SwiftUI.

`gestures` makes the most valuable distinction: **“while the finger is down, the UI is the finger; the moment it lifts, physics takes over.”** Tracking is 1:1, with no spring lag. Release uses velocity and distance; linked values derive from one progress value. Interruptibility, respecting the grab offset and avoiding sudden jumps are the craft target. Its recommendation to use Vaul is web-only; native sheets and native gesture primitives serve the same purpose in SwiftUI.

`apple-design` reinforces instant touch-down feedback, reversible/interruptible motion, spatially consistent entrance and exit, restrained spring bounce, and purposeful haptics. It recommends the system font by default, Dynamic Type, size-sensitive tracking and a hierarchy built from size, weight and leading together. It describes material depth as functional hierarchy and warns against stacked low-contrast translucent surfaces. It separately addresses reduced motion, reduced transparency and increased contrast.

`mobile-native` is explicitly a **web app** skill. Its CSS fixes for sticky hover, `100vh`, Safari input zoom, tap highlights, viewport meta tags and `touch-action` are not missing SwiftUI features. The portable lessons are immediate press feedback, honest safe-area/keyboard handling, capability-aware pointer support and checking touch on actual hardware. It explicitly distinguishes code inspection from what requires a phone.

`write-swift` supplies one directly relevant implementation principle: SwiftUI time-sensitive state changes belong in the synchronous event callback so feedback happens in the same frame; a task is for subsequent long-running work. It also recommends enums for mutually exclusive state and a clear seam between UI state and async work. This research does **not** recommend moving a music app's audio render work onto the main actor based on the skill's general app-concurrency defaults.

### Vercel: useful quality floor, stack-specific implementation

The actual `web-design-guidelines/SKILL.md` is an index and workflow; the substantial rules are in the referenced `web-interface-guidelines/command.md`, which was fetched and read.

Portable rules include named icon controls, labels, meaningful hierarchy, visible focus, a focused element never hidden under an overlay, reduced motion, interruptibility, stable numeric columns, empty/long-content handling, safe areas, recoverable errors, localized numbers/dates, and alternatives to nonessential drag/swipe actions. It specifically says interactive states should increase contrast. These map naturally to native accessibility and controls.

The `react-native-skills/SKILL.md` additionally favors native navigation, context menus and modals, safe-area-aware scrolling, minimal subscriptions, and keeping expensive work out of interactive list items. The principle is native platform behavior and responsive rendering. FlashList, Reanimated, Expo Image, Pressable, Nativewind and React Compiler are implementation choices for another stack. They are not recommendations to replace SwiftUI.

Do not copy ARIA/DOM/CSS APIs, browser hydration advice, URL state synchronization for every native view, Next.js data fetching, Vercel deployment or React dependency instructions into the app. Vercel's command file asks for Title Case; Anthropic and Taste ask for sentence case. For LaGrilla, keep the established native vocabulary and sentence case where appropriate. This disagreement is evidence that source styles require judgment, not wholesale adoption.

### Anthropic: distinct point of view that follows this brief

The current `frontend-design/SKILL.md` asks for deliberate choices specific to the subject, audience and primary job. It explicitly says **“Where the brief pins down a visual direction, follow it exactly — the brief's own words always win.”** Night therefore remains a valid direction even though the skill lists near-black with a single acid accent among common generated defaults.

Concrete guidance to apply:

- Start from the subject's vernacular. A music instrument's grid, channel strips, performance pads, note events and transport should create identity; generic productivity statistics should not.
- Create a compact token plan with 4–6 core named colors, type roles, layout and principles before coding. Semantic track/state colors can sit alongside that compact structural palette.
- Use one or two deliberate type families. Native SF with carefully assigned roles is intentional; it does not need an ornamental web display font to seem premium.
- Structural devices must encode information. Bar numbers belong on a timeline; arbitrary “01 / 02” labels and repeated eyebrow labels do not. Avoid identical rounded cards for unrelated material, excessive shadow, decorative gradient washes, a monospace label on everything and tracked all-caps chrome.
- **“Spend your boldness in one place.”** Let the primary musical canvas be memorable and keep supporting tools disciplined.
- Prefer motion that answers an action and explains change. Repeated fade/slide entrances everywhere are the generic default.
- Write clear actions and preserve vocabulary through the flow: a Generate action reports generation progress and produces an explicit result to audition or apply. Empty states tell the user the next useful action; errors explain recovery.
- Critique with screenshots and remove decoration that does not help the brief. Accessibility, responsive layouts, reduced motion and visible focus are a quality floor.

## Application to SwiftUI

These are recommendations derived from the sources, not quotations or claims about the current code.

| Area | Apply to LaGrilla | Native implementation direction |
| --- | --- | --- |
| Visual hierarchy | Night background → editor surface → quiet inset lanes → bright played/selected events. Keep transport and mode position stable across tools. | Shared `Color`, spacing, radius, stroke and typography tokens; a small set of shared `ViewModifier` and `ButtonStyle` implementations. Use explicit surface roles rather than per-screen arbitrary opacity. |
| Typography | SF for interface and content; rounded treatment only where it supports the existing identity. Clearly separate screen title, tool title, value and supporting label. Tempo, bars, time and dB should not jitter. | Semantic text styles, appropriate weights, `monospacedDigit()` for changing numbers; `@ScaledMetric` for scalable custom metrics. Reserve monospaced faces for musical/numeric data that benefits. |
| Spacing | Use a compact 4/8/12/16/24/32 point vocabulary. Group by proximity and align headings, rails and action edges. Dense editors may use tighter internal rhythm without shrinking hit areas. | Consistent layout constants, adaptive stacks/layouts, safe-area-aware insets. Avoid fixed text heights and broad `minimumScaleFactor` fixes that hide a broken hierarchy. |
| Color | Preserve Night. Make structural surfaces neutral; use one primary action accent and stable musical colors for tracks, with separate warning/error/success semantics. Richness should come from information and material depth. | Named semantic colors, selected outline/marker plus fill, sensible contrast variants. Do not use color alone to distinguish mute, solo, recording or selected steps. |
| Component states | Every control distinguishes rest, pressed, selected/on, disabled, focused and progress/error where applicable. State feedback should keep labels and geometry stable. | A shared `ButtonStyle` reads `configuration.isPressed`; `Toggle`/`Button` semantics; enums for generation/recording lifecycle; accessibility value/traits. Preserve native cancellation behavior for ordinary buttons. |
| Touch | Small icon artwork can sit in a minimum 44×44pt target. Pads respond at contact, while normal destructive/commit buttons preserve release/cancellation semantics. | Expand the actual interactive frame and use `contentShape` where needed. Instrument touch tracking may need a dedicated gesture/UIKit bridge for the app's multi-touch requirements; do not assume a general `Button` provides musical touch-down timing. |
| Motion | Instant step/pad state; no stagger or entrance delay in a repeatedly used instrument. Short settling for occasional selection/sheet changes; no global animation on the whole grid. | Animate a specific changing value, not a broad tree. Use reduced-motion-aware opacity/state changes. Direct manipulation uses gesture translation without an interpolating spring; release can use an available native spring. |
| Haptics | Sparse feedback for a snap, recording commit, successful apply or a meaningful mode boundary. Avoid a haptic on every sequencer pulse. | `sensoryFeedback` where supported or existing haptic infrastructure. Trigger from the causal state change; do not add synthetic UX sounds that compete with music or delay audio for a visual effect. |
| Materials | A subtle floating toolbar/sheet can read as a separate layer; the editing canvas stays stable and legible. Avoid glass on glass and constant glow. | Native material appropriate to the deployment target; solid fallback for `accessibilityReduceTransparency`, explicit separation for increased contrast. Use system sheets/menus/popovers before custom approximations. |
| Accessibility | Name icon controls by action; expose track/note/step state. Provide button/menu alternatives for nonessential gestures and usable value adjustment for faders. | `accessibilityLabel`, `accessibilityValue`, appropriate traits/actions, adjustable controls, grouping and focus order; Dynamic Type and VoiceOver checks. Consider an accessible structured editor alternative to a dense visual grid. |
| Performance | Musical timing and touch feedback take priority over ornament. Update playhead/meter displays without invalidating the entire app or creating tasks per frame. | Narrow observed state and view updates, profile actual grids/meters, keep audio engine constraints separate from view animations, avoid expensive blur/layout changes on every beat. |

## Surface-by-surface design direction

| Surface | Characteristic treatment | Interaction and state requirement |
| --- | --- | --- |
| Grid / sequencer | The identity surface: strong bar grouping, restrained minor subdivisions, clear lane labels, active steps with meaningful velocity/accent treatment. | Selected step, enabled step and currently playing step are distinct. Tap feedback is immediate. The playhead reflects transport, rather than a decorative repeated loop. Preserve useful empty grid structure. |
| Pads | Large tactile targets with concise sound names and useful bank/record state; deeper face/inset contrast without ornamental skeuomorphism. | Immediate contact highlight and release, independent simultaneous touches where supported, clear armed/held/muted states. A pad strike must never wait for a scale animation to finish. |
| Piano roll | Notes and timeline are the primary information; editing tools stay close to the selection. Emphasize bar/beat mapping and selected notes. | Drag starts at the grabbed offset and tracks directly. Quantized snap and duration changes are explicit. Offer accessible nudge/length controls and undo for edits. |
| Mixer | Shared channel-strip grammar, readable level values, stable meter widths, mute/solo states with text or symbols. | Faders track directly and expose adjustable values; no spring lag on a meaningful reading. Meter motion is real audio status. Avoid expensive whole-screen updates for each meter sample. |
| Voice | Waveform, duration and recording state carry identity. One obvious record/stop action, then an explicit take to audition/use. | Recording state cannot look like idle with a different hue. Permission/error/no-input states should give a concrete recovery path. Preserve a recorded take through follow-up actions. |
| AI | A calm musical assistant panel using the same surfaces and type. Specific requests and editable musical results belong near their destination. | Idle → generating → result/error/cancelled are explicit. Preserve user input; show real progress/status; make audition/apply/replace scope clear. Do not fabricate an applied result on a decorative timer. |
| Perform | Fewer, larger controls and a confident shared transport. The performance surface should have stronger immediacy and less editing chrome. | High-frequency actions have direct state change. Scenes, queued launches, active scenes and recording are distinguishable; avoid an animated marketing treatment every time the mode opens. |

## Decision rules and review evidence

1. **Follow the actual brief over source defaults.** Retain Night and native SwiftUI. No aesthetic rule in these external repositories authorizes replacing the product's platform, installing a package, publishing a website, spending credits or initiating a permission flow.
2. **Define a shared token and state vocabulary before spreading styling across tools.** A coherent family can include distinct pads, grid cells, channel strips and sheets; “one system” does not require all of them to be the same rounded card.
3. **Treat high-frequency musical interaction differently from occasional navigation.** Cut ornamental travel/stagger from repeated input. Feedback and musical transport remain immediate and informative.
4. **Use native APIs by deployment availability.** SwiftUI materials, sheets, sensory feedback, focus, Dynamic Type and accessibility environments are the implementation starting point. No React, CSS, Vaul, Expo or Vercel migration is implied.
5. **Verify the result in context.** Inspect screenshots of each core surface at the supported device sizes; inspect pressed/selected/armed/disabled/loading/error states; check long track names, empty and busy sessions, large text and orientation. Play back motion slowly to catch inconsistent origins or jumps. Test touch, cancellation, simultaneous pad use, safe areas and keyboard behavior on physical hardware before claiming their feel is verified.

Research completion: all four requested repositories and their selected actual skills were read, with current commit links above. No external repository scripts, installers or hooks were executed. No project dependencies, repository settings, publication destinations or generated media were changed. Device-level feel and app-specific contrast/performance remain implementation validation work.

## Shared-theme implementation handoff

The subsequent authorized implementation changed only [`App/Theme.swift`](/workspace/la-grilla-design26/App/Theme.swift) in the app source. It preserves every existing color and shared-component name and initializer contract. It adds `StudioMetrics` (4/8/12/16/24/32 spacing; 44pt hit target; 48pt action; 12/18/22 radii), `StudioTypography` (Dynamic Type SF roles), and `StudioMotion` (120ms release, 180ms selection, critically damped 320ms panel spring). These constants do not themselves start any animation.

Visible changes include a neutral graphite chassis, coordinated periwinkle/champagne/teal musical colors, fine solid seams and subtle surface depth, native-material navigation with solid accessibility fallbacks, inset segmented controls, outlined status badges, a coordinated musical mark, immediate pressed surfaces/focus rings and stable full-opacity text. Normal action press uses a subtle scale with a short release; reduced motion removes that scale. No audio, pad, transport, controller or navigation semantics were changed here, and no haptics were added.

Validation performed: Swift 6.1.2 `swiftc -frontend -parse` passed; `git diff --check -- App/Theme.swift` passed. A direct sRGB/WCAG contrast calculation checked semantic text/accent colors on the solid `ink`, `panel` and `raised` colors, the corresponding filled action labels, the implemented black press overlay, the implemented quiet-press background and the badge tint. Results are minimum ratios within each set:

| Palette | Solid text/accent | Filled action label | Pressed action label | Pressed quiet label | Badge label |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dark | 6.21:1 | 8.27:1 | 7.03:1 | 5.14:1 | 5.44:1 |
| Light | 5.42:1 | 6.10:1 | 6.86:1 | 4.80:1 | 4.89:1 |
| Dark, increased contrast | 8.40:1 | 11.14:1 | 9.41:1 | 7.48:1 | 6.10:1 |
| Light, increased contrast | 7.37:1 | 8.86:1 | 9.76:1 | 6.80:1 | 5.69:1 |

The normal surface seams are decorative, with roughly 1.5:1 contrast against `panel`; they are not the selected/recording state signal. Increased-contrast seams are 6.20:1 Dark and 4.54:1 Light. State also uses text, symbols and selected fill. Disabled controls are not included in the text minima. These are source-color/compositing calculations, not rendered screenshot or all-screen accessibility certification. Swift parsing on Linux does not type-check SwiftUI/UIKit or replace an Xcode build. Native rendering, clipped/fixed-height callers, large text, materials over content, hardware touch, VoiceOver and audio performance still require the integrated app's validation.
