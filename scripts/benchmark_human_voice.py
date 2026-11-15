#!/usr/bin/env python3
"""Manual Vocadito benchmark against the actual production MusicDomain analyzer.

No network without --download. Corpus, Swift build cache, raw analysis, protocol,
and metrics must stay outside Git worktrees. Only the fixed development split is
exposed; the reserved holdout is not read. See docs/VOICE_HUMAN_BASELINE.md.
"""

import argparse
import array
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import wave
import zipfile


REPO = Path(__file__).resolve().parents[1]
PACKAGE = REPO / "Tools/VoiceBenchmark"
MANIFEST = PACKAGE / "vocadito-v3-manifest.json"
ANALYZER = REPO / "Packages/MusicDomain/Sources/MusicDomain/VoiceAnalyzer.swift"


def digest(path, algorithm="sha256"):
    result = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=".voice-report-", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, indent=2, ensure_ascii=False, allow_nan=False)
            stream.write("\n")
            stream.flush()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def external_path(value, description):
    """Resolve symlinks and reject paths inside this or any other Git worktree."""
    path = Path(value).expanduser().resolve()
    # Includes non-existing destinations in all related worktrees.
    worktrees = subprocess.check_output(
        ["git", "worktree", "list", "--porcelain"], cwd=REPO, text=True
    )
    for line in worktrees.splitlines():
        if line.startswith("worktree "):
            root = Path(line[len("worktree "):]).resolve()
            if path == root or root in path.parents:
                raise ValueError(f"{description} must be outside Git worktrees: {path}")
    nearest = path if path.is_dir() else path.parent
    while not nearest.exists():
        nearest = nearest.parent
    check = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"],
                           cwd=nearest, capture_output=True, text=True)
    if check.returncode == 0 and check.stdout.strip() == "true":
        raise ValueError(f"{description} must be outside Git worktrees: {path}")
    return path


def source_file(cache, entry):
    relative = Path(entry["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Unsafe source path in pinned manifest")
    lexical = cache / relative
    # Never replace another source (including a reserved holdout member) through
    # a cached symlink, even when both endpoints happen to be outside Git.
    for component in (lexical, *lexical.parents):
        if component == cache:
            break
        if component.is_symlink():
            raise ValueError(f"Corpus members must not use symlinks: {relative}")
    path = external_path(lexical, "Corpus member")
    if cache not in path.parents:
        raise ValueError(f"Corpus member escapes cache: {relative}")
    return path


def valid_file(path, entry):
    return (path.is_file() and path.stat().st_size == entry["bytes"]
            and digest(path) == entry["sha256"])


def download_sources(cache, manifest):
    """Bounded full archive; verify primary license, size, MD5 and member SHA256."""
    print("Downloading pinned Vocadito archive; source license CC BY 4.0.", file=sys.stderr)
    with urllib.request.urlopen(manifest["sourceRecord"], timeout=30) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("Primary metadata exceeds expected size")
    record = json.loads(raw)
    if record.get("metadata", {}).get("license", {}).get("id") != manifest["license"]["id"]:
        raise ValueError("Primary source license differs from the pinned CC BY 4.0 record")
    archive = manifest["archive"]
    candidates = [item for item in record.get("files", []) if item.get("key") == archive["name"]]
    if (len(candidates) != 1 or candidates[0].get("size") != archive["bytes"]
            or candidates[0].get("checksum") != "md5:" + archive["md5"]):
        raise ValueError("Primary source archive differs from pinned metadata")
    cache.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=cache, prefix=".vocadito-", suffix=".zip",
                                         delete=False) as output:
            temporary = Path(output.name)
            total = 0
            with urllib.request.urlopen(archive["url"], timeout=30) as response:
                while block := response.read(1024 * 1024):
                    total += len(block)
                    if total > archive["bytes"]:
                        raise ValueError("Archive exceeds pinned download size")
                    output.write(block)
        if total != archive["bytes"] or digest(temporary, "md5") != archive["md5"]:
            raise ValueError("Downloaded archive failed pinned byte-size/MD5 verification")
        with zipfile.ZipFile(temporary) as zipped:
            for entry in manifest["files"]:
                destination = source_file(cache, entry)
                if valid_file(destination, entry):
                    continue
                member = zipped.getinfo(entry["path"])
                if member.file_size != entry["bytes"]:
                    raise ValueError(f"Unexpected member size: {entry['path']}")
                data = zipped.read(member)  # zipfile also verifies the member CRC32.
                if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                    raise ValueError(f"Source member SHA256 mismatch: {entry['path']}")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(dir=destination.parent,
                                                 prefix=".voice-source-", delete=False) as out:
                    stage = Path(out.name)
                    try:
                        out.write(data)
                        out.flush()
                        stage.replace(destination)
                    finally:
                        stage.unlink(missing_ok=True)
        write_json(source_file(cache, {"path": "benchmark-source-record.json"}), record)
        attribution = (manifest["license"]["attribution"] + "\n" + manifest["sourcePage"]
                       + "\nLicense: " + manifest["license"]["url"]
                       + "\nSelected source files unchanged; lyrics not extracted.\n")
        source_file(cache, {"path": "BENCHMARK_ATTRIBUTION.txt"}).write_text(attribution, encoding="utf-8")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def ensure_sources(cache, manifest, allow_download):
    bad = [entry["path"] for entry in manifest["files"]
           if not valid_file(source_file(cache, entry), entry)]
    if bad and not allow_download:
        raise ValueError("Missing or corrupt pinned corpus files: " + ", ".join(bad[:3])
                         + ". Re-run this command with --download to fetch them explicitly.")
    if bad:
        download_sources(cache, manifest)
    for entry in manifest["files"]:
        if not valid_file(source_file(cache, entry), entry):
            raise ValueError(f"Pinned source verification failed: {entry['path']}")
    return bool(bad)


def run_analyzer(cache, output, scratch):
    swift = os.environ.get("GRILLA_SWIFT_BIN") or os.environ.get("GRILLA_SWIFT") or "swift"
    if not shutil.which(swift):
        raise ValueError("Swift executable unavailable; set GRILLA_SWIFT_BIN or GRILLA_SWIFT")
    directories = {}
    for name in ("modules", "build", "swiftpm-cache", "swiftpm-config", "swiftpm-security"):
        directory = external_path(scratch / name, "Swift scratch child")
        if scratch not in directory.parents:
            raise ValueError(f"Swift scratch child escapes scratch directory: {name}")
        directories[name] = directory
    env = os.environ.copy()
    for key in ("SWIFT_MODULECACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE", "CLANG_MODULE_CACHE_PATH"):
        env[key] = str(directories["modules"])
    directories["modules"].mkdir(parents=True, exist_ok=True)
    common = ["--package-path", str(PACKAGE), "--scratch-path", str(directories["build"]),
              "--cache-path", str(directories["swiftpm-cache"]),
              "--config-path", str(directories["swiftpm-config"]),
              "--security-path", str(directories["swiftpm-security"]), "-c", "release"]
    subprocess.run([swift, "build", *common], env=env, check=True, stdout=sys.stderr)
    binary_dir = subprocess.check_output([swift, "build", *common, "--show-bin-path"],
                                         env=env, text=True).strip()
    subprocess.run([str(Path(binary_dir) / "VoiceBenchmark"), str(cache), str(output)],
                   env=env, check=True, stdout=sys.stderr)
    return subprocess.check_output([swift, "--version"], env=env, text=True).strip()


def note_metrics(reference, predicted, strict=False):
    import numpy as np
    from scipy.optimize import linear_sum_assignment

    matches = []
    if len(reference) and len(predicted):
        onset = np.abs(reference[:, 0, None] - predicted[None, :, 0])
        pitch = np.abs(reference[:, 1, None] - predicted[None, :, 1])
        valid = (onset <= 0.05 + 1e-12) & (pitch <= 0.5 + 1e-12)
        if strict:
            offset = np.abs(reference[:, 2, None] - predicted[None, :, 2])
            tolerance = np.maximum(0.05, 0.2 * (reference[:, 2] - reference[:, 0]))
            valid &= offset <= tolerance[:, None] + 1e-12
        # Invalid cost dominates the sum of every valid cost. This first
        # maximizes cardinality, then chooses close onsets among equal matches.
        rows, cols = linear_sum_assignment(np.where(valid, onset + pitch * 0.01, 1e6))
        matches = [(i, j) for i, j in zip(rows, cols) if valid[i, j]]
    count = len(matches)
    precision = count / len(predicted) if len(predicted) else 0
    recall = count / len(reference) if len(reference) else 0
    return {
        "referenceNotes": len(reference), "predictedNotes": len(predicted), "matched": count,
        "precision": precision, "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0,
        "matchedOnsetMAEms": (sum(abs(reference[i, 0] - predicted[j, 0]) * 1000
                                  for i, j in matches) / count) if count else None,
    }


def aggregate_notes(rows):
    result = {}
    for mode in ("onsetPitch", "onsetPitchOffset"):
        counts = {key: sum(row[mode][key] for row in rows)
                  for key in ("referenceNotes", "predictedNotes", "matched")}
        precision = counts["matched"] / counts["predictedNotes"] if counts["predictedNotes"] else 0
        recall = counts["matched"] / counts["referenceNotes"] if counts["referenceNotes"] else 0
        result[mode] = {**counts, "precision": precision, "recall": recall,
                        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0}
    return result


def ratio(numerator, denominator):
    return numerator / denominator if denominator else None


def f0_metrics(counts):
    return {
        "confidenceQualifiedPitchAccuracy": ratio(counts["correctWithin50Cents"], counts["confidentReferenceVoicedFrames"]),
        "pitchAccuracyIncludingVoicedMisses": ratio(counts["correctWithin50Cents"], counts["referenceVoicedFrames"]),
        "voicedRecall": ratio(counts["confidentReferenceVoicedFrames"], counts["referenceVoicedFrames"]),
        "confidentFrameCoverage": ratio(counts["confidentPredictedFrames"], counts["evaluableFrames"]),
        "unvoicedFalsePositiveRate": ratio(counts["falsePositiveVoicedFrames"], counts["referenceUnvoicedFrames"]),
    }


def score(cache, analysis):
    import numpy as np

    metadata = {int(row["track_id"]): row for row in
                csv.DictReader((cache / "vocadito_metadata.csv").open(encoding="utf-8"))}
    tracks, agreement = [], []
    ticks_per_second = analysis["bpmForMIDIConversion"] / 60 * analysis["ppq"]
    if [track["id"] for track in analysis["reports"]] != list(range(1, 9)):
        raise ValueError("Analyzer did not return the fixed development split")
    for track in analysis["reports"]:
        track_id, duration = track["id"], track["duration"]
        frames = track["frames"]
        gt = np.loadtxt(cache / f"Annotations/F0/vocadito_{track_id}_f0.csv", delimiter=",")
        if (gt.ndim != 2 or gt.shape[1] != 2 or not np.isfinite(gt).all()
                or np.any(np.diff(gt[:, 0]) <= 0) or np.any(gt[:, 1] < 0)):
            raise ValueError(f"Invalid original F0 annotation: track {track_id}")
        times = np.array([frame["time"] for frame in frames])
        predicted = np.array([frame["frequency"] or 0 for frame in frames])
        confidence = np.array([frame["confidence"] for frame in frames])
        right = np.minimum(np.searchsorted(gt[:, 0], times), len(gt) - 1)
        left = np.maximum(0, right - 1)
        nearest = np.where(np.abs(gt[left, 0] - times) <= np.abs(gt[right, 0] - times), left, right)
        evaluable = np.abs(gt[nearest, 0] - times) <= np.max(np.diff(gt[:, 0])) / 2 + 1e-9
        reference = gt[nearest, 1]
        voiced = (reference > 0) & evaluable
        unvoiced = (reference == 0) & evaluable
        confident = (predicted > 0) & (confidence >= 0.72) & evaluable
        both = voiced & confident
        error = np.full(len(frames), np.inf)
        error[both] = np.abs(1200 * np.log2(predicted[both] / reference[both]))
        counts = {
            "evaluableFrames": int(evaluable.sum()), "referenceVoicedFrames": int(voiced.sum()),
            "referenceUnvoicedFrames": int(unvoiced.sum()), "confidentPredictedFrames": int(confident.sum()),
            "confidentReferenceVoicedFrames": int(both.sum()), "correctWithin50Cents": int(((error <= 50) & both).sum()),
            "falsePositiveVoicedFrames": int((unvoiced & confident).sum()),
            "octaveErrorFrames": int((both & (np.abs(error - 1200) <= 50)).sum()),
        }
        predicted_notes = np.array([[note["tick"] / ticks_per_second, note["pitch"],
                                     (note["tick"] + note["duration"]) / ticks_per_second]
                                    for note in track["notes"]]).reshape(-1, 3)
        annotated, note_results = [], {}
        for annotator in ("A1", "A2"):
            raw = np.loadtxt(cache / f"Annotations/Notes/vocadito_{track_id}_notes{annotator}.csv",
                             delimiter=",").reshape(-1, 3)
            if not np.isfinite(raw).all() or np.any(raw[:, 1:] <= 0) or np.any(raw[:, 0] < 0):
                raise ValueError(f"Invalid original note annotation: {track_id}/{annotator}")
            raw = raw[raw[:, 0] < duration]
            reference_notes = np.column_stack((raw[:, 0], 69 + 12 * np.log2(raw[:, 1] / 440),
                                               np.minimum(duration, raw[:, 0] + raw[:, 2])))
            annotated.append(reference_notes)
            note_results[annotator] = {"onsetPitch": note_metrics(reference_notes, predicted_notes),
                                       "onsetPitchOffset": note_metrics(reference_notes, predicted_notes, True)}
        agreement.append({"id": track_id, "onsetPitch": note_metrics(*annotated),
                           "onsetPitchOffset": note_metrics(*annotated, strict=True)})
        with wave.open(str(cache / f"Audio/vocadito_{track_id}.wav")) as audio:
            pcm = audio.readframes(track["inputSamples"])
        integers = array.array("h")
        integers.frombytes(pcm)
        if sys.byteorder != "little":
            integers.byteswap()
        floats = array.array("f", (value / 32768 for value in integers))
        if sys.byteorder != "little":
            floats.byteswap()
        tracks.append({
            "id": track_id, "singer": metadata[track_id]["singer_id"], "language": metadata[track_id]["language"],
            "rawSampleFrames": track["rawSampleFrames"], "analyzedDurationSeconds": duration,
            "processedInputFloat32LESHA256": hashlib.sha256(floats.tobytes()).hexdigest(),
            "processedInputSampleCount": len(floats), "f0Counts": counts,
            "f0Metrics": {**f0_metrics(counts), "medianAbsoluteCents": float(np.median(error[both])) if both.any() else None},
            "notes": note_results,
        })
    totals = {key: sum(track["f0Counts"][key] for track in tracks) for key in tracks[0]["f0Counts"]}
    aggregate = {
        "tracks": len(tracks), "singers": len({track["singer"] for track in tracks}),
        "analyzedSeconds": sum(track["analyzedDurationSeconds"] for track in tracks),
        "f0Counts": totals, **f0_metrics(totals),
        "notes": {annotator: aggregate_notes([track["notes"][annotator] for track in tracks])
                  for annotator in ("A1", "A2")},
    }
    accuracy = aggregate["confidenceQualifiedPitchAccuracy"]
    aggregate["meetsPredeclaredExploratory90PercentCriterion"] = accuracy is not None and accuracy >= 0.90
    return {"aggregate": aggregate, "tracks": tracks,
            "humanAgreement": {"purpose": "Descriptive A1-versus-A2 context, not a pass criterion",
                               "aggregate": aggregate_notes(agreement), "tracks": agreement}}


def main():
    initial_scorer_hash = digest(Path(__file__))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default_cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "la-grilla/voice-benchmark/vocadito-v3"
    parser.add_argument("--cache-dir", type=Path, default=default_cache, help="External corpus cache (default: %(default)s)")
    parser.add_argument("--output", type=Path, required=True, help="External report.json; adjacent .analysis.json/.protocol.json also written")
    parser.add_argument("--scratch-dir", type=Path, help="External Swift build/cache directory (default: isolated directory under system temp)")
    parser.add_argument("--download", action="store_true", help="Explicitly fetch missing/corrupt source files; otherwise remain offline")
    args = parser.parse_args()
    cache = external_path(args.cache_dir, "Corpus cache")
    output = external_path(args.output, "Report output")
    if output.suffix.lower() != ".json":
        raise ValueError("Report output must end in .json")
    scratch_name = "la-grilla-voice-benchmark-" + hashlib.sha256(str(REPO).encode()).hexdigest()[:12]
    scratch = external_path(args.scratch_dir or Path(tempfile.gettempdir()) / scratch_name, "Swift scratch directory")
    analysis_path = external_path(output.with_suffix(".analysis.json"), "Raw analysis output")
    protocol_path = external_path(output.with_suffix(".protocol.json"), "Protocol output")
    if len({output, analysis_path, protocol_path}) != 3:
        raise ValueError("Output filenames collide; use a report.json filename")
    for target in (output, analysis_path, protocol_path):
        if target == cache or target == scratch or target.is_dir():
            raise ValueError("Output must be a file, not the cache or scratch directory")
    try:
        import numpy as np
        import scipy
    except ImportError as error:
        raise ValueError("Install benchmark requirements in an external venv: "
                         "python3 -m pip install -r Tools/VoiceBenchmark/requirements.txt") from error
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest["developmentIDs"] != list(range(1, 9)):
        raise ValueError("Pinned development split changed; declare a new protocol first")
    source_paths = {source_file(cache, entry) for entry in manifest["files"]}
    if any(target in source_paths for target in (output, analysis_path, protocol_path)):
        raise ValueError("Report destinations must not overwrite pinned corpus source files")
    downloaded = ensure_sources(cache, manifest, args.download)
    output.parent.mkdir(parents=True, exist_ok=True)
    source_hash = digest(ANALYZER)
    protocol = {
        "declaredBeforeAnalysisAt": datetime.now(timezone.utc).isoformat(),
        "dataset": manifest["dataset"], "doi": manifest["doi"], "license": manifest["license"],
        "selection": "Fixed numeric IDs1–8; first min(30.000s, full duration), offset0. Holdout9–16 is not read.",
        "f0Rules": "Nearest reference sample at each frame center within half reference hop; 0Hz unvoiced; conf>=0.72, pitch<=50cents, no octave folding; report coverage/recall/falsepositives.",
        "noteRules": "Production MIDI at120BPM/PPQ960, quantize.off, no scale projection. A1/A2 separately; maximum-cardinality one-to-one onset<=50ms/pitch<=50cents; strict offset<=max(50ms,20%reference duration). Clip reference notes to analysis end.",
        "exploratoryCriterion": "Aggregate confidence-qualified F0 accuracy>=90%; not a release gate, per-track guarantee or note-transcription criterion.",
        "sourceSHA256": source_hash, "manifestSHA256": digest(MANIFEST),
        "modelSHA256": digest(ANALYZER.with_name("Model.swift")),
        "packageSHA256": digest(PACKAGE / "Package.swift"),
        "compilerConfiguration": "SwiftPM release; production local MusicDomain dependency",
        "sourceIntegrity": {
            "memberVerification": "Pinned byte size and SHA256 for all34 source members, every run",
            "expectedArchiveBytes": manifest["archive"]["bytes"],
            "expectedArchiveMD5": manifest["archive"]["md5"],
            "fullArchiveSizeAndMD5VerifiedThisRun": downloaded,
            "livePrimaryLicenseCheckedThisRun": downloaded,
            "offlineLicenseEvidence": manifest["sourceRecord"] + " pinned CC BY4.0 declaration",
        },
        "swiftHarnessSHA256": digest(PACKAGE / "Sources/VoiceBenchmark/main.swift"),
        "scorerSHA256": initial_scorer_hash,
        "gitHead": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "environment": {"platform": platform.platform(), "python": sys.version,
                        "numpy": np.__version__, "scipy": scipy.__version__},
        "limitations": ["Recorded human algorithm evidence; not physical iPhone microphone/route/noise/bleed validation.",
                        "Eight fixed development excerpts, six singers, not a full-corpus or unseen-holdout evaluation.",
                        "Human note annotations are subjective; both annotators and their agreement remain separate."],
    }
    write_json(protocol_path, protocol)
    swift_version = run_analyzer(cache, analysis_path, scratch)
    if (digest(ANALYZER) != source_hash
            or digest(ANALYZER.with_name("Model.swift")) != protocol["modelSHA256"]
            or digest(Path(__file__)) != protocol["scorerSHA256"]
            or digest(PACKAGE / "Sources/VoiceBenchmark/main.swift") != protocol["swiftHarnessSHA256"]
            or digest(PACKAGE / "Package.swift") != protocol["packageSHA256"]
            or digest(MANIFEST) != protocol["manifestSHA256"]):
        raise ValueError("Benchmark or production source changed during the run; re-run on a stable checkout")
    analysis = json.loads(analysis_path.read_text())
    result = score(cache, analysis)
    expected_inputs = {item["id"]: item for item in manifest["historicalBaseline"]["processedInputs"]}
    for track in result["tracks"]:
        expected = expected_inputs[track["id"]]
        if (track["processedInputSampleCount"] != expected["inputSamples"]
                or track["processedInputFloat32LESHA256"] != expected["float32LESHA256"]):
            raise ValueError("Analyzer input differs from the declared PCM16/Float32 and30-second protocol")
    result.update({
        "source": manifest["sourcePage"], "license": manifest["license"], "protocol": protocol,
        "swiftVersion": swift_version, "analysisSHA256": digest(analysis_path),
        "rawInputs": manifest["files"], "inputTransform": "Original mono44100Hz PCM16 divided by32768 toFloat32, firstmin(30s,full duration); production preprocessing unchanged.",
        "sourceMatchesHistoricalBaseline": source_hash == manifest["historicalBaseline"]["productionSourceSHA256"],
        "artifacts": {"analysis": str(analysis_path), "protocol": str(protocol_path)},
    })
    write_json(output, result)
    print(json.dumps({"report": str(output), "aggregate": result["aggregate"],
                      "humanAgreement": result["humanAgreement"]["aggregate"]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Voice benchmark: {error}", file=sys.stderr)
        sys.exit(1)
