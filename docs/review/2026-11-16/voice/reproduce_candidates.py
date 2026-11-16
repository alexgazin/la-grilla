#!/usr/bin/env python3
"""Replay rejected segmentation hypotheses on development IDs 1–8 only.

No downloads, production edits, audio synthesis or holdout selection. Input is
the real VoiceBenchmark .analysis.json; corpus members are verified offline.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("voice_scorer", ROOT / "scripts/benchmark_human_voice.py")
scorer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scorer)


def rounded(value):
    return math.floor(value + 0.5)


def pitches(frames):
    original = [rounded(69 + 12 * math.log2(f["frequency"] / 440))
                if f["frequency"] and f["confidence"] >= 0.72 else None for f in frames]
    result = original.copy()
    for i, pitch in enumerate(original):
        if pitch is None:
            continue
        neighbors = sorted(p for p in original[max(0, i - 2):min(len(original), i + 3)] if p is not None)
        if len(neighbors) >= 3:
            result[i] = neighbors[len(neighbors) // 2]
    for i in range(1, len(result) - 1):
        if result[i] is None and result[i - 1] is not None and result[i - 1] == result[i + 1]:
            result[i] = result[i - 1]
    return result


def runs(values):
    result, start = [], 0
    while start < len(values):
        end = start + 1
        while end < len(values) and values[end] == values[start]:
            end += 1
        result.append((start, end, values[start]))
        start = end
    return result


def prediction(track, mode):
    frames, duration = track["frames"], track["duration"]
    values = pitches(frames)
    if mode == "short-island":
        grouped = runs(values)
        for left, middle, right in zip(grouped, grouped[1:], grouped[2:]):
            if (left[2] is not None and middle[2] is not None and left[2] == right[2]
                    and abs(left[2] - middle[2]) == 1 and middle[1] - middle[0] < 6
                    and left[1] - left[0] >= 6 and right[1] - right[0] >= 6):
                values[middle[0]:middle[1]] = [left[2]] * (middle[1] - middle[0])
    rms = [float(np.median([f["rms"] for f in frames[max(0, i - 1):min(len(frames), i + 2)]]))
           for i in range(len(frames))] if mode == "energy-reattack" else []
    intervals = []
    for start, end, pitch in runs(values):
        if pitch is None:
            continue
        first = max(0, frames[start]["time"] - 0.032 + 0.015)
        last = min(duration, frames[end - 1]["time"] - 0.032 + 0.010 + 0.035)
        if last - first < 0.08:
            continue
        cuts = []
        if mode == "energy-reattack":
            for i in range(start + 10, end - 10):
                if rms[i] > min(rms[i - 1], rms[i + 1]):
                    continue
                left, right = max(rms[i - 10:i - 1]), max(rms[i + 2:i + 11])
                threshold = 0.5 * min(left, right)
                if min(left, right) < 0.02 or rms[i] > threshold:
                    continue
                low = high = i
                while low > start and rms[low - 1] < threshold:
                    low -= 1
                while high + 1 < end and rms[high + 1] < threshold:
                    high += 1
                if high - low + 1 > 12:
                    continue
                stop, begin = frames[low]["time"], frames[high + 1]["time"]
                if stop - first < 0.08 or last - begin < 0.08 or (cuts and low - cuts[-1][0] <= 8):
                    continue
                cuts.append((high + 1, stop, begin))
        for _, stop, begin in cuts:
            if stop - first < 0.08:
                continue
            intervals.append((first, stop, pitch))
            first = begin
        intervals.append((first, last, pitch))
    output = []
    for first, last, pitch in intervals:
        start, end = rounded(first * 1920), min(64 * 3840, rounded(last * 1920))
        if end <= start:
            continue
        if output and output[-1]["tick"] + output[-1]["duration"] > start:
            output[-1]["duration"] = start - output[-1]["tick"]
        output.append({"tick": start, "duration": end - start, "pitch": min(127, max(0, pitch))})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    analysis_path = scorer.external_path(args.analysis, "Production analysis")
    cache = scorer.external_path(args.cache_dir, "Corpus cache")
    output = scorer.external_path(args.output, "Candidate output")
    manifest = json.loads(scorer.MANIFEST.read_text())
    if manifest["developmentIDs"] != list(range(1, 9)):
        raise ValueError("The fixed development protocol changed")
    scorer.ensure_sources(cache, manifest, False)
    if output == analysis_path or output in {scorer.source_file(cache, e) for e in manifest["files"]}:
        raise ValueError("Output must not replace an input")
    analysis = json.loads(analysis_path.read_text())
    if [t["id"] for t in analysis["reports"]] != list(range(1, 9)):
        raise ValueError("Only development IDs 1–8 are accepted")
    for track in analysis["reports"]:
        original = [{k: n[k] for k in ("tick", "duration", "pitch")} for n in track["notes"]]
        if prediction(track, "control") != original:
            raise ValueError("Control does not exactly reproduce the supplied production notes")
    before = scorer.score(cache, analysis)
    results = {}
    for mode in ("short-island", "energy-reattack"):
        candidate = {**analysis, "reports": [{**t, "notes": prediction(t, mode)} for t in analysis["reports"]]}
        protocol = HERE / (mode + "-protocol.json")
        results[mode] = {"protocol": json.loads(protocol.read_text()),
                         "historicalProtocolSHA256": hashlib.sha256(protocol.read_bytes()).hexdigest(),
                         "before": before, "after": scorer.score(cache, candidate),
                         "promotedToProduction": False}
    report = {"hostOnly": True, "holdoutAudioOrAnnotationsAccessed": False,
              "controlReproduced": True, "productionSegmentationChanged": False,
              "analysisSHA256": hashlib.sha256(analysis_path.read_bytes()).hexdigest(), "results": results}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print("Rejected development hypotheses replayed:", output)


if __name__ == "__main__":
    main()
