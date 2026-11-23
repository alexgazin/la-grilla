#!/usr/bin/env python3
"""Slice a clean 4 x 6 sheet of genre covers into the asset catalog.

Usage: scripts/slice_genre_art.py SHEET.png
Tiles are read left to right, top to bottom in BeatPreset.Genre order, plus the
24th tile for the beat machine itself. Use only an image without a watermark that
the project may ship.
"""
import json, sys
from pathlib import Path
from PIL import Image

GENRES = ["trap","drill","boomBap","westCoast","lofi","phonk","rnb","pop","house","techno","garage","dnb",
          "bass","reggaeton","afro","jersey","funk","rock","synthwave","electro","chiptune","jazz","world","machine"]
ROOT = Path(__file__).resolve().parent.parent / "Resources" / "Assets.xcassets"

def main(path):
    sheet = Image.open(path).convert("RGB")
    cell_w, cell_h = sheet.width / 4, sheet.height / 6
    inset = 0.06  # skip the gutters
    for index, name in enumerate(GENRES):
        col, row = index % 4, index // 4
        box = (int((col + inset) * cell_w), int((row + inset) * cell_h), int((col + 1 - inset) * cell_w), int((row + 1 - inset) * cell_h))
        tile = sheet.crop(box)
        side = min(tile.size)
        tile = tile.crop(((tile.width - side) // 2, (tile.height - side) // 2, (tile.width + side) // 2, (tile.height + side) // 2)).resize((384, 384), Image.LANCZOS)
        folder = ROOT / f"genre-{name}.imageset"
        folder.mkdir(exist_ok=True)
        tile.save(folder / "art.jpg", quality=82, optimize=True, progressive=True)
        (folder / "Contents.json").write_text(json.dumps({"images": [{"filename": "art.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print(f"Wrote {len(GENRES)} genre covers to {ROOT}")

if __name__ == "__main__":
    main(sys.argv[1])
