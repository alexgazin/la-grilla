#!/usr/bin/env python3
"""Write a host-only evidence envelope without reading any credentials."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

root = Path(__file__).resolve().parent
baseline = root / "baseline"


def record(path, relative_to):
    data = path.read_bytes()
    return {"path": str(path.relative_to(relative_to)), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


receipt = root / "receipt.json"
measured = json.loads(receipt.read_text())
harness = [record(root / path, root) for path in ["Package.swift", "Sources/GrillaArchitectureProfile/main.swift", "run.sh", "provenance.py", "README.md"]]
sources = [record(path, baseline) for path in sorted((baseline / "Packages/MusicDomain").rglob("*")) if path.is_file()]
fixtures = [record(baseline / f"docs/release/fixtures/load-P{level}.grillapack", baseline) for level in [1, 3]]
swift = os.environ.get("GRILLA_SWIFT_BIN", "/workspace/tools/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swift")
version = subprocess.check_output([swift, "--version"], text=True).strip()
summary = {
    "formatVersion": 1,
    "hostOnly": True,
    "sourceSHA": measured["sourceSHA"],
    "sourceState": "Immutable git archive; working tree edits excluded",
    "toolchain": version,
    "toolchainPath": swift,
    "host": dict(platform.uname()._asdict()),
    "optimizedCommand": "bash /tmp/grilla-architecture-profile/run.sh /workspace/la-grilla-audit-actions",
    "receipt": record(receipt, root),
    "harness": harness,
    "sourceFiles": sources,
    "fixtures": fixtures,
    "sourceFilesDigest": hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest(),
    "initialAttempt": {"accepted": False, "reason": "SwiftPM rejected input file ProjectStore.swift modified during shared-worktree build; that attempt yielded no accepted measurements"},
}
(root / "provenance.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print("Host-only profile provenance written:", root / "provenance.json")
