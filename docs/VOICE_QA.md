# Voice-to-MIDI — controlled software checks

The feature is labelled **Beta / monophonic**. It records one mono phrase, analyses after capture, preserves original PCM until Apply/Cancel, exposes confidence and manual correction, and applies editable MIDI notes as one History transaction. Microphone monitoring is off. Count-in uses scheduled recorder/player device times; recording-offset correction starts at zero. API-reported input latency is recorded as diagnostic metadata, not claimed as measured route compensation.

Two dependency-free candidates use the same 8 kHz/DC-free windows: YIN CMND and normalized autocorrelation. On 48 deterministic harmonic tones (MIDI 36–83), each correctly classified **432/432 stable frames within 50 cents**, with **0 octave errors** and **0 voiced white-noise frames**. Both reject digital silence/noise; repeated-tone pauses remain separate; 44.1 kHz resampling preserves pitch; source notes remain available after optional grid/scale projection. The clean fixture is a tie; YIN is the initial detector because its CMND confidence is directly available for review. This does not establish superiority on human voices.

Fixtures and metrics are reproducible in VoiceTests and CI ExportFixtures/voice-metrics.json. Independent Python hashlib/CAF/ZIP readers validate portable original-source bytes. SHA-256 uses published empty/abc/million-a vectors. Package duplication, backup recovery and import retain source recordings. A valid ZIP CRC cannot hide source corruption from SHA-256 validation.

## Required device acceptance

Real human voices/whistling, consonants, vibrato, falsetto/missing fundamentals, glissandi, repeated notes without silence and different noisy rooms are not represented by the clean synthetic set. Pitch F1 ≥0.90 and onset F1 ≥0.85 on a human-voice acceptance set are not claimed. Actual microphone permissions, count-in/route offset, interruptions, clipping and original/instrument A/B require a physical iPhone/headphones. Keep the beta label until these checks close. Native QA fixtures are explicitly marked synthetic in both UI and asset metadata; they never masquerade as microphone recordings.
