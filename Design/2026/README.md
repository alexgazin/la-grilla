# R8.1 — La Grilla / Design 2026

The owner requested a modern, strong, simple and distinctive interface before the final release candidate. This is a native SwiftUI implementation pass, with the existing musical behavior preserved.

[OpenArt direction](openart-direction.png) is a **concept board**, not an application screenshot. [Generation record](openart-generation.json): GPT Image 2.6 Sunburst, one 4K/high 16:9 image, 54 credits actually charged; balance 583 → 529. The matching [app icon](openart-icon.png) is an unchanged opaque RGB 1024 × 1024 OpenArt output, with [provenance](openart-icon-generation.json). It cost 32 credits, leaving 497; this design pass used 86 credits total. The same grid/playhead mark is drawn natively in the project header. Native product evidence belongs in Screenshots/Design2026 after current-SDK acceptance.

## Visual decisions

- A bright vertical playhead and proportional musical grid are the recognizable motif. The interface gives most space to music.
- Matte graphite, warm text and a lime primary action; amber harmony, periwinkle drums and aqua bass retain distinct musical roles. Light appearance has corresponding contrast-tested tokens.
- Compact project context, one clear transport, a consistent three-mode navigation, precise spacing and restrained bordered surfaces.
- Harmony keeps the original/proposal relationship visible and fixes audition/Apply at the bottom. Advanced register settings are secondary.
- Perform puts section launches and live effects first. Capture, Stop and return to editing remain reachable; less frequent controls are grouped.
- Jam uses a consistent playable 4×4 surface. Mixer geometry adapts to small phones. Guidance appears where it helps the action.

The concept's illustrative pad names, timing values and controls are translated into the app's actual supported functionality: original GM pad order, four real harmony styles, global A/B, fixed eighth-note delay and supported beat-repeat sizes.

[Apple HIG review](HIG_REVIEW.md) records the official typography, color, materials, button and accessibility references, including the 11 pt minimum, explicit press states and the iOS 26 navigation material.

## Acceptance

- [x] OpenArt direction and provenance retained.
- [x] Shared contrast tokens, compact shell, Grid, Harmony and Perform implemented in SwiftUI.
- [x] Jam, adaptive Mixer and secondary surfaces implemented and reviewed natively.
- [x] Current-SDK iPhone/simulator/Release builds and all 19 functional scenarios.
- [x] 54 original native EN/RU, light/dark, large text, landscape and 375-point frames.
- [x] Regenerated twelve Store frames, source/hash records and reviewable [PR #12](https://github.com/alexgazin/la-grilla/pull/12).

Source `72d81cb` passes all three jobs in [43700372709](https://github.com/alexgazin/la-grilla/actions/runs/43700372709): 64 Swift tests, 11 C++ suites, both SDK builds, optimized archive and 22 native tests across Pro Max/SE. [Native evidence](../../Screenshots/Design2026) · [Design QA](../../docs/DESIGN_QA.md). Physical audio/MIDI, manual VoiceOver usability and installed signed-build acceptance remain separate release gates.
