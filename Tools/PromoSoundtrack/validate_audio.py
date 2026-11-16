#!/usr/bin/env python3
"""Inspect the rendered 24-bit WAV; requires Python 3 + numpy, no audio device."""
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

import numpy as np

path = Path(sys.argv[1])
with wave.open(str(path), "rb") as wav:
    assert wav.getnchannels() == 2
    assert wav.getsampwidth() == 3
    assert wav.getframerate() == 48_000
    assert wav.getnframes() == 4_608_000
    assert wav.getcomptype() == "NONE"
    raw = np.frombuffer(wav.readframes(wav.getnframes()), dtype=np.uint8).reshape(-1, 3)
    value = raw[:, 0].astype(np.int32) | raw[:, 1].astype(np.int32) << 8 | raw[:, 2].astype(np.int32) << 16
    pcm = (((value ^ (1 << 23)) - (1 << 23)).astype(np.float64) / (1 << 23)).reshape(-1, 2)


def db(value):
    return float(20 * math.log10(value)) if value > 0 else None


def measure(audio):
    peak = float(np.abs(audio).max())
    rms = float(np.sqrt(np.mean(audio * audio)))
    return {
        "finite_pcm": bool(np.isfinite(audio).all()),
        "sample_peak_linear": peak,
        "sample_peak_dbfs": db(peak),
        "rms_linear": rms,
        "rms_dbfs": db(rms),
        "dc_offset": [float(value) for value in audio.mean(axis=0)],
        "samples_at_or_above_engine_ceiling_0_98": int((np.abs(audio) >= 0.98).sum()),
        "zero_samples": int((audio == 0).sum()),
    }


chapters = [
    (0, 4, "Intro"), (4, 12, "Grid"), (12, 20, "Arrange"),
    (20, 28, "Jam"), (28, 36, "Piano / Bass"), (36, 44, "Harmony"),
    (44, 52, "Assistant"), (52, 60, "Voice"), (60, 68, "Perform"),
    (68, 76, "Mixer"), (76, 84, "MIDI"), (84, 92, "Export"),
    (92, 96, "Outro"),
]
result = {
    "file": path.name,
    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    "format": {"sample_rate": 48_000, "bit_depth": 24, "channels": 2, "frames": len(pcm), "duration_seconds": len(pcm)/48_000},
    "whole_file": measure(pcm),
    "channels": [measure(pcm[:, i:i+1]) for i in range(2)],
    "last_100ms": measure(pcm[-4_800:]),
    "first_stereo_frame": pcm[0].tolist(),
    "last_stereo_frame": pcm[-1].tolist(),
    "chapters": [{"start": start, "end": end, "name": name, **measure(pcm[start*48_000:end*48_000])} for start, end, name in chapters],
    "qualification": "Programmatic PCM and level checks only; no human listening approval. PCM finite checks do not inspect intermediate floating-point engine buffers.",
}
assert result["whole_file"]["finite_pcm"]
assert result["whole_file"]["samples_at_or_above_engine_ceiling_0_98"] == 0
assert result["whole_file"]["sample_peak_linear"] < 0.9
assert result["last_100ms"]["sample_peak_linear"] < 0.001
print(json.dumps(result, ensure_ascii=False, indent=2))
