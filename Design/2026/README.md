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

## Acceptance

- [x] OpenArt direction and provenance retained.
- [x] Shared contrast tokens, compact shell, Grid, Harmony and Perform implemented in SwiftUI.
- [x] Implement Jam, adaptive Mixer and secondary surfaces; native review remains pending.
- [ ] Current-SDK iPhone/simulator/Release builds and all functional scenarios.
- [ ] Original native EN/RU, light/dark, large text, landscape and 375-point evidence.
- [ ] Regenerated Store sets, source/hash records and verified merge into main.

Physical audio/MIDI, manual VoiceOver usability and installed signed-build acceptance remain separate release gates. The first foundation passes the iPhone SDK build and optimized archive in run 43693468957. The complete interface still requires native flow and screenshot acceptance.
