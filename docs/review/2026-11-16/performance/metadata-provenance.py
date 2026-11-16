#!/usr/bin/env python3
"""Verify the immutable source snapshot and envelope host-only measurements."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

root = Path(__file__).resolve().parent
identity = json.loads((root / 'source-snapshot.json').read_text())


def record(path, relative_to):
    data = path.read_bytes()
    return {'path': str(path.relative_to(relative_to)), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


for expected in identity['files']:
    actual = record(root / 'source' / expected['path'], root / 'source')
    if actual != expected:
        raise SystemExit('Immutable source file changed: ' + expected['path'])
digest = hashlib.sha256(json.dumps(identity['files'], sort_keys=True).encode()).hexdigest()
if digest != identity['sourceSnapshotDigest']:
    raise SystemExit('Snapshot digest differs')
if '--verify-snapshot' in sys.argv:
    print('Immutable uncommitted-source snapshot verified:', digest)
    raise SystemExit(0)

receipt = root / 'receipt.json'
measured = json.loads(receipt.read_text())
if measured['sourceBaselineSHA'] != identity['sourceBaselineSHA'] or measured['sourceSnapshotDigest'] != digest:
    raise SystemExit('Receipt uses a different source identity')
swift = os.environ.get('GRILLA_SWIFT_BIN', '/workspace/tools/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swift')
summary = {
    'formatVersion': 2,
    'hostOnly': True,
    'sourceBaselineSHA': identity['sourceBaselineSHA'],
    'sourceSnapshotDigest': digest,
    'sourceWorkingTreeChangesIncluded': True,
    'sourceState': 'Immutable file snapshot; base commit plus pinned uncommitted source, not final committed source SHA',
    'snapshotCapturedAt': identity['capturedAt'],
    'toolchain': subprocess.check_output([swift, '--version'], text=True).strip(),
    'toolchainPath': swift,
    'host': dict(platform.uname()._asdict()),
    'optimizedCommand': 'bash /tmp/grilla-architecture-profile-after/run.sh',
    'receipt': record(receipt, root),
    'harness': [record(root / path, root) for path in ['Package.swift', 'Sources/GrillaArchitectureProfile/main.swift', 'run.sh', 'provenance.py', 'README.md']],
    'sourceManifest': record(root / 'source-snapshot.json', root),
    'sourceFiles': identity['files'],
    'sourceTrackedDiff': record(root / 'source-tracked-diff.patch', root),
    'fixtures': [record(root / f'fixtures/docs/release/fixtures/load-P{level}.grillapack', root / 'fixtures') for level in [1, 3]],
    'beforeReceiptSHA256': '7fc42d3d5585179c0c28e69d4e21d9d48ef70310158542e6ab6d229d10ef039f',
}
(root / 'provenance.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
print('Host-only AFTER provenance written:', root / 'provenance.json')
