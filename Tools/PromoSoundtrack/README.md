# La Grilla promo soundtrack

An original 96-second instrumental composition rendered through the repository's
unmodified `MusicDomain.OfflineRenderer.renderPerformance` and C++ `AudioDSP`.
This is an authored offline engine render, **not a live recording from an iPhone**.
It contains no speech, borrowed music, external samples, or Vocadito recordings.

The composition uses the app's version 2 procedural harmony, bass, melody and
16-pad percussion instruments. The melodic motif and score were authored for the
promo; the recurring progression is C–Am–F–G, with F–G–Am–G variations and a
C6/9 resolution. Tempo is 120 BPM, 4/4, 48 bars, 960 PPQ.

## Reproduce

With Swift 6 installed, run from the repository root:

```sh
GRILLA_REPOSITORY="$PWD" swift run \
  --package-path Tools/PromoSoundtrack \
  --scratch-path /tmp/la-grilla-promo-build \
  -c release PromoSoundtrack /tmp/la-grilla-promo-audio
```

When this package lives elsewhere, replace `Tools/PromoSoundtrack` with its path.
`GRILLA_REPOSITORY` must point at a checkout containing `Packages/MusicDomain`.
No downloaded dependencies are needed. The reference render used Swift 6.1.2 on
Linux and source commit `8e5b1f768fafe28d8de4b8154c786039e2a1fa71`.

Outputs:

- `la-grilla-promo-96s-48k24.wav`: exact 96.000-second stereo PCM master, 48 kHz,
  24-bit; no external mastering/limiter, no appended export tail.
- `la-grilla-promo.grillapack`: editable native project plus the exact automated
  performance take. The original score is also retained in the app project.
- `la-grilla-promo-project.json`: readable native schema 8 project snapshot.
- `la-grilla-promo-score.mid`: note score only, with the original track structure.
  This MIDI file does not reproduce gain/filter/delay automation or app timbres.

The project stores random document/event IDs, so regenerated project/MIDI files
may differ in metadata. Two reference WAV renders were byte-identical. Recheck
the result if the engine source or Swift/compiler/platform changes.

## Musical chapter cues

| Seconds | Promo chapter | Score / engine behavior |
| --- | --- | --- |
| 0–4 | Intro | Warm harmonic pulse; bass and lead muted |
| 4–12 | Grid | Drums enter; short offbeat chord replies |
| 12–20 | Arrange | The recurring melody enters |
| 20–28 | Jam | Brighter drum accents, shaker, short fill |
| 28–36 | Piano / Bass | Native bass and quiet upper arpeggio enter |
| 36–44 | Harmony | Chord layer comes forward with add9/m7/sus9 colors |
| 44–52 | Assistant | Full instrumental motif returns |
| 52–60 | Voice | Instrumental breath with lead removed; no synthetic singer |
| 60–68 | Perform | Native low-pass/high-pass movement and tempo-synced delay |
| 68–76 | Mixer | Brief drum/bass/chord/lead focus, then full arrangement |
| 76–84 | MIDI | Full groove with airy upper notes |
| 84–92 | Export | Final statement, short transition into the resolution |
| 92–96 | Outro | C6/9 resolution, native delay release, slow master fade |

The final master uses the app's permitted +6 dB gain setting; all buses and
automation remain within validated app limits. The reference PCM peak is about
−3.59 dBFS, true peak −3.2 dBTP and integrated loudness −18.5 LUFS, leaving room
for AAC/video encoding. There is no clipping. See the delivered provenance and
PCM analysis JSON for exact measurements. Analysis is automated; no human
listening approval is implied.
