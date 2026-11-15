# R7 — Core MIDI

Twenty actual native XCTest captures from app source `223615f`.

[Successful complete acceptance run 43680458783](https://github.com/alexgazin/la-grilla/actions/runs/43680458783): 62 Swift tests, six C++ suites, both native SDK builds, all 15 Studio user flows and the 20-screen capture test pass. The virtual QA source/destination use actual Core MIDI callbacks, including CC74 Learn, received output notes and emergency Panic.

- [MIDI devices](midi.png) · [Mapped controller](midi-mapped.png)
- [Grid](grid.png) · [Jam](jam.png) · [Mixer](mixer.png)
- [Piano roll](notes.png) · [Perform](perform.png) · [Recorded take](perform-take.png)

These are simulator QA attachments, not generated designs or physical USB/BLE measurements. App Store images are prepared separately in the release stage.
