# R8 — product UI and accessibility

Three actual original-PNG native captures from source `595d4a3` and [successful workflow 43682961615](https://github.com/alexgazin/la-grilla/actions/runs/43682961615).

- [Russian interface / light appearance](russian-light-export.png)
- [Large Dynamic Type / accessible note list](large-type-piano-roll.png)
- [Landscape pads and persistent transport](landscape-jam.png)

All 18 native Studio scenarios, 62 Swift tests, six C++ suites and both SDK builds pass. The presentation audit checks 448 EN/RU keys and format parity, color-token contrast and the opaque 1024px icon. The OpenArt source and provenance are in `Design/OpenArt`; these app captures are not generated artwork.

This final UI-flow run skips duplicate bulk capture. Broader integrated capture and compact-device checks are documented with the hardening/release stages; App Store images are prepared separately.
