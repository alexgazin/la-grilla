#!/usr/bin/env python3
"""Prepare the bundled CC0 mono sample packs from pinned recordings."""
import array
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

SOURCE_COMMIT = "514c926efecdb3c7812bf00eedf8e5c8d61dd681"
SOURCE = f"https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/{SOURCE_COMMIT}/systems/instruments"
RATE = 32_000
PITCHES = {"C": 0, "Cs": 1, "D": 2, "Ds": 3, "E": 4, "F": 5, "Fs": 6, "G": 7, "Gs": 8, "A": 9, "As": 10, "B": 11}
STRING_OPEN = {"LowE": 40, "A": 45, "D": 50, "G": 55, "B": 59, "HighE": 64}


def fetch(collection, path):
    with urllib.request.urlopen(f"{SOURCE}/{collection}/{path}", timeout=35) as response:
        return response.read(8_000_001)


def samples(collection, wanted):
    manifest = json.loads(fetch(collection, "manifest.json"))
    if manifest["license"] != "CC0-1.0":
        raise ValueError(f"Unexpected license for {collection}")
    checksums = {path: digest for digest, path in map(str.split, fetch(collection, "SHA256SUMS").decode().splitlines())}
    choices = {}
    for sample in manifest["samples"]:
        filename = sample["file"]
        match = re.search(r"_(?P<note>[A-G]s?)(?P<octave>\d)_01\.wav$", filename)
        if not match:
            continue
        midi = (int(match["octave"]) + 1) * 12 + PITCHES[match["note"]]
        if midi not in wanted:
            continue
        if collection == "meta-piano":
            if "_Vel02_" not in filename:
                continue
            distance = 0
        else:
            string = re.search(r"_String(\w+?)_Vel01Finger_", filename)
            if not string:
                continue
            distance = midi - STRING_OPEN[string[1]]
            if distance < 0:
                continue
        path = "ogg/" + filename.replace(".wav", ".ogg")
        if path in checksums and (midi not in choices or distance < choices[midi][0]):
            choices[midi] = (distance, path, checksums[path])
    if set(choices) != set(wanted):
        raise ValueError(f"Missing notes for {collection}: {set(wanted) - set(choices)}")
    return choices


def prepare(collection, name, wanted, duration, output):
    chunks = []
    zones = []
    for midi, (_, path, digest) in sorted(samples(collection, wanted).items()):
        media = fetch(collection, path)
        if hashlib.sha256(media).hexdigest() != digest:
            raise ValueError(f"Incorrect recording checksum: {path}")
        pcm = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", "pipe:0", "-t", str(duration), "-ac", "1", "-ar", str(RATE),
            "-f", "s16le", "pipe:1"
        ], input=media)
        values = array.array("h")
        values.frombytes(pcm)
        if sys.byteorder != "little":
            values.byteswap()
        if len(values) < 32 or max(map(abs, values)) < 100:
            raise ValueError(f"Empty recording: {path}")
        chunks.append(values)
        zones.append(dict(pitch=midi, frames=len(values), source=path, sha256=digest))

    gain = min(4, 0.32 * 32767 / max(abs(value) for chunk in chunks for value in chunk))
    stream = bytearray()
    for chunk in chunks:
        for index, value in enumerate(chunk):
            # Gentle fade at the truncated end of a naturally decaying note.
            tail = min(1, (len(chunk) - index - 1) / 768)
            chunk[index] = round(value * gain * tail)
        if sys.byteorder != "little":
            chunk.byteswap()
        stream.extend(chunk.tobytes())
    target = output / (name + ".caf")
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-i", "pipe:0",
        "-c:a", "alac", "-sample_fmt", "s16p", str(target)
    ], input=stream, check=True)
    decoded = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(target), "-f", "s16le", "pipe:1"])
    if decoded != stream:
        raise ValueError(f"CAF encoding changed PCM: {target}")
    return dict(source=collection, rate=RATE, zones=zones, sha256=hashlib.sha256(target.read_bytes()).hexdigest())


def main():
    output = Path(__file__).resolve().parents[1] / "Resources" / "FactoryInstruments"
    output.mkdir(parents=True, exist_ok=True)
    piano = prepare("meta-piano", "piano", range(24, 105, 4), 2.4, output)
    guitar = prepare("meta-nylon-guitar", "nylon-guitar", [*range(40, 83, 3), 83], 2.0, output)
    (output / "manifest.json").write_text(json.dumps(dict(sourceCommit=SOURCE_COMMIT, piano=piano, guitar=guitar), indent=2) + "\n")
    (output / "LICENSE-CC0.txt").write_bytes(fetch("meta-piano", "LICENSE"))
    print(f"Piano {len(piano['zones'])} zones, nylon guitar {len(guitar['zones'])} zones; lossless CAF verified.")


if __name__ == "__main__":
    main()
