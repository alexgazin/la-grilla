# Motion showcase renderer

Creates a 96-second 1920×1080 / 30 fps H.264 + AAC feature showcase from
the repository's original native screenshots. Motion is authored in Canvas,
captured in Chromium and encoded with FFmpeg. There is no generated/recreated
app UI, simulated touch input or screen recording claim. Original PNG bytes
are never rewritten. Full screenshots preserve their aspect ratio; explicitly
labelled detail crops use proportional cover within the video composition.

## Reproduce

Requires Python 3, `numpy`, `playwright`, Chromium, FFmpeg with libx264, and
Noto Sans Regular/Bold fonts with Cyrillic. For example on Linux, use the
distribution's `chromium`, `ffmpeg`, `fonts-noto-core` packages and:

```sh
python3 -m pip install numpy playwright
```

First render the soundtrack as described in [PromoSoundtrack](../PromoSoundtrack/README.md).
Then, from the repository root:

```sh
python3 Tools/Promo/render.py \
  --audio /tmp/la-grilla-promo-audio/la-grilla-promo-96s-48k24.wav \
  --output /tmp/la-grilla-promo.mp4
```

`--regular-font` and `--bold-font` accept different installed font paths.
The default is `/usr/share/fonts/truetype/noto/NotoSans-{Regular,Bold}.ttf`.
Playwright uses Chromium from PATH, or its installed browser if absent.
All media/font requests are fulfilled from local files by a Playwright route;
there is no HTTP server and no upload to a generation service.

Preview an exact time or export all chapter/transition samples:

```sh
python3 Tools/Promo/render.py --audio /tmp/la-grilla-promo-audio/la-grilla-promo-96s-48k24.wav \
  --output /tmp/promo-frame.png --preview 8
python3 Tools/Promo/render.py --audio /tmp/la-grilla-promo-audio/la-grilla-promo-96s-48k24.wav \
  --output /tmp/promo-frames --previews
```

Scene timing, aspect ratios and motion are deterministic for a given time.
Exact raster/MP4 bytes can differ with Chromium, FFmpeg, fonts and platform.
The MIDI chapter's small waveform is driven by the soundtrack's 30 Hz RMS
envelope; the decorative background pulse follows 120 BPM. Neither changes
the UI shown in the screenshots.

## README teaser

Create the silent first-six-second preview from the finished MP4:

```sh
ffmpeg -y -i /tmp/la-grilla-promo.mp4 -t 6 \
  -filter_complex '[0:v]fps=8,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
  -loop 0 /tmp/teaser.gif
```

The [media README](../../Media/Promo/README.md) records feature qualifications,
source provenance and the delivered artifacts. This tool does not modify the
iOS target, project generator, production packages, tests or CI workflows.
