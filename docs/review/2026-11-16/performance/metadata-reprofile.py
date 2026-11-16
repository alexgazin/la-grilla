#!/usr/bin/env python3
"""Rebuild a measured source in an external directory; never edit the checkout."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def archive(ref, paths):
    files = {}
    with tarfile.open(fileobj=io.BytesIO(git('archive', ref, *paths))) as tar:
        for item in tar.getmembers():
            path = Path(item.name)
            if path.is_absolute() or '..' in path.parts or (not item.isfile() and not item.isdir()):
                raise ValueError('Unsupported archive member: ' + item.name)
            if item.isfile():
                files[item.name] = tar.extractfile(item).read()
    return files


def apply_text_delta(files, delta):
    """Apply this pinned textual git diff in memory, checking every old line."""
    blocks = re.split(br'(?m)(?=^diff --git )', delta)
    for block in blocks:
        if not block:
            continue
        lines = block.splitlines(keepends=True)
        match = re.fullmatch(br'diff --git a/(\S+) b/(\S+)\n', lines[0])
        if not match or match[1] != match[2] or b'GIT binary patch' in block:
            raise ValueError('Unsupported pinned diff header')
        name = match[1].decode()
        original = files.get(name, b'').splitlines(keepends=True)
        output, cursor, index = [], 0, 1
        while index < len(lines):
            header = re.match(br'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', lines[index])
            if not header:
                index += 1
                continue
            start = max(0, int(header[1]) - 1)
            expected_old = int(header[2] or b'1')
            expected_new = int(header[4] or b'1')
            if start < cursor:
                raise ValueError('Overlapping pinned diff hunks')
            output.extend(original[cursor:start])
            cursor = start
            used_old = used_new = 0
            index += 1
            while index < len(lines) and not lines[index].startswith(b'@@ '):
                line = lines[index]
                prefix, value = line[:1], line[1:]
                if prefix in (b' ', b'-'):
                    if cursor >= len(original) or original[cursor] != value:
                        raise ValueError('Pinned diff old context differs: ' + name)
                    cursor += 1
                    used_old += 1
                if prefix in (b' ', b'+'):
                    output.append(value)
                    used_new += 1
                if prefix not in (b' ', b'-', b'+'):
                    raise ValueError('Unsupported pinned diff line')
                index += 1
            if (used_old, used_new) != (expected_old, expected_new):
                raise ValueError('Pinned diff hunk count differs: ' + name)
        output.extend(original[cursor:])
        if b'+++ /dev/null\n' in block:
            files.pop(name, None)
        else:
            files[name] = b''.join(output)


def records(files):
    return [{'path': name, 'bytes': len(data), 'sha256': sha(data)} for name, data in sorted(files.items())]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['baseline', 'metadata'], required=True)
    parser.add_argument('--source-ref', help='Optional committed source for a new measurement; omitted metadata mode restores the historical uncommitted snapshot')
    parser.add_argument('--output', type=Path, help='New empty directory outside the checkout, e.g. /tmp/grilla-profile-2026')
    parser.add_argument('--swift-bin', default='swift')
    parser.add_argument('--plan', action='store_true', help='Verify delivery and reconstruct/check all source bytes in memory without creating files or compiling')
    args = parser.parse_args()
    delivery = json.loads((HERE / 'metadata-delivery.json').read_text())
    for entry in delivery['historicalCopies'] + delivery['metadataNewSources']:
        if sha((HERE / entry['deliveredFile']).read_bytes()) != entry.get('deliveredSHA256', entry['sha256']):
            raise ValueError('Delivered historical bytes changed: ' + entry['deliveredFile'])
    base = delivery['baselineSourceSHA']
    historical_metadata = args.mode == 'metadata' and not args.source_ref
    source_ref = args.source_ref or base
    source_sha = git('rev-parse', '--verify', source_ref + '^{commit}').decode().strip()
    source = archive(source_sha, ['Packages/MusicDomain'])
    if historical_metadata:
        apply_text_delta(source, (HERE / 'metadata-source-tracked-diff.patch').read_bytes())
        for entry in delivery['metadataNewSources']:
            data = (HERE / entry['deliveredFile']).read_bytes()
            if entry.get('encoding') == 'gzip':
                data = gzip.decompress(data)
            if sha(data) != entry['sha256']:
                raise ValueError('Decoded historical source differs: ' + entry['sourcePath'])
            source[entry['sourcePath']] = data
    source_records = records(source)
    source_digest = sha(json.dumps(source_records, sort_keys=True).encode())
    if historical_metadata:
        expected = json.loads((HERE / 'metadata-source-snapshot.json').read_text())
        if source_records != expected['files'] or source_digest != expected['sourceSnapshotDigest']:
            raise ValueError('Historical AFTER reconstruction differs from the measured snapshot')
    elif args.mode == 'baseline' and not args.source_ref:
        expected = json.loads((HERE / 'baseline-provenance.json').read_text())
        if source_records != expected['sourceFiles']:
            raise ValueError('Historical BEFORE reconstruction differs from the measured source')
    store = source['Packages/MusicDomain/Sources/MusicDomain/ProjectStore.swift']
    if args.mode == 'metadata' and (b'func listSummaries(' not in store or b'func summary(' not in store):
        raise ValueError('Selected committed source has no measured metadata APIs')
    fixtures = archive(base, ['docs/release/fixtures/load-P1.grillapack', 'docs/release/fixtures/load-P3.grillapack'])
    known_fixtures = json.loads((HERE / 'baseline-provenance.json').read_text())['fixtures']
    if records(fixtures) != known_fixtures:
        raise ValueError('Committed fixture bytes differ from the historical protocol')
    prefix = 'baseline' if args.mode == 'baseline' else 'metadata'
    harness_bytes = (HERE / (prefix + '-Profile.swift')).read_bytes()
    plan = {'mode': args.mode, 'sourceCommitBase': source_sha, 'historicalUncommittedMetadata': historical_metadata,
            'sourceSnapshotDigest': source_digest, 'verifiedSourceFiles': len(source),
            'fixtureCommit': base, 'fixtureFiles': records(fixtures), 'deliveredHarnessSHA256': sha(harness_bytes),
            'sourceStatus': 'Pinned historical uncommitted snapshot' if historical_metadata else 'Exact committed source',
            'protocol': '15 direct operations / 5 full lists / 5 metadata lists and 15 single queries when supported; warmups/setup separate',
            'hostOnly': True}
    if args.plan:
        print(json.dumps(plan, indent=2, sort_keys=True))
        return
    if args.output is None:
        parser.error('--output is required unless --plan is used')
    output = args.output.expanduser().resolve()
    if output == REPO or REPO in output.parents or (output.exists() and any(output.iterdir())):
        raise ValueError('Output must be a new empty directory outside the checkout')
    swift = shutil.which(args.swift_bin)
    if swift is None:
        raise ValueError('Swift toolchain not found; pass --swift-bin')
    toolchain = subprocess.check_output([swift, '--version'], text=True).strip()
    output.mkdir(parents=True, exist_ok=True)
    for folder, files in [('source', source), ('fixtures', fixtures)]:
        for name, data in files.items():
            path = output / folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    identity = {'sourceBaselineSHA': source_sha, 'sourceSnapshotDigest': source_digest,
                'sourceWorkingTreeChangesIncluded': historical_metadata, 'files': source_records}
    (output / 'source-snapshot.json').write_text(json.dumps(identity, indent=2, sort_keys=True) + '\n')
    harness = harness_bytes.decode()
    # Only receipt provenance constants are adapted; operations, samples and assertions stay unchanged.
    state = 'Immutable historical uncommitted snapshot restored and verified' if historical_metadata else 'Immutable git archive of exact committed source'
    harness = re.sub(r'(?m)^(\s*)let sourceState =.*$', lambda m: m[1] + 'let sourceState = ' + json.dumps(state), harness)
    harness = re.sub(r'(?m)^(\s*)let sourceWorkingTreeChangesIncluded =.*$', lambda m: m[1] + 'let sourceWorkingTreeChangesIncluded = ' + str(historical_metadata).lower(), harness)
    harness = re.sub(r'(?m)^(\s*)let architecture =.*$', lambda m: m[1] + 'let architecture = ' + json.dumps(platform.machine()), harness)
    harness = harness.replace('runtime: "Swift 6.1.2 x86_64-unknown-linux-gnu; swift run -c release"', 'runtime: ' + json.dumps(toolchain + '; swift run -c release'))
    target = output / 'Sources/GrillaArchitectureProfile/main.swift'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(harness)
    package = (HERE / (prefix + '-Package.swift')).read_text().replace('baseline/Packages/MusicDomain', 'source/Packages/MusicDomain')
    (output / 'Package.swift').write_text(package)
    command = [swift, 'run', '--package-path', str(output), '--scratch-path', str(output / 'build'),
               '--cache-path', str(output / 'spm-cache'), '--config-path', str(output / 'spm-config'),
               '--security-path', str(output / 'spm-security'), '-c', 'release', 'GrillaArchitectureProfile',
               str(output / 'fixtures'), str(output / 'source-snapshot.json') if args.mode == 'metadata' else source_sha,
               str(output / 'receipt.json')]
    env = dict(os.environ, SWIFTPM_MODULECACHE_OVERRIDE=str(output / 'module-cache'), CLANG_MODULE_CACHE_PATH=str(output / 'clang-cache'))
    plan.update(toolchain=toolchain, compiledHarnessSHA256=sha(target.read_bytes()),
                receiptOnlyAdaptations=['source state', 'committed/uncommitted flag', 'actual architecture', 'actual Swift version'], command=command)
    (output / 'reprofile-provenance.json').write_text(json.dumps(plan, indent=2, sort_keys=True) + '\n')
    with (output / 'build-and-run.log').open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            print(line, end='', flush=True)
            log.write(line)
        code = process.wait()
    if code:
        raise SystemExit(code)
    plan['receiptSHA256'] = sha((output / 'receipt.json').read_bytes())
    (output / 'reprofile-provenance.json').write_text(json.dumps(plan, indent=2, sort_keys=True) + '\n')
    print('New host-only receipt:', output / 'receipt.json')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
