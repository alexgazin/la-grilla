#!/usr/bin/env python3
"""Package a verified unsigned iPhone app for signing on a tester's laptop."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import stat
import zipfile

from audit_binary import audit_binary


def package(app: pathlib.Path, output: pathlib.Path, source_sha: str):
    if not re.fullmatch(r'[0-9a-f]{40}', source_sha):
        raise ValueError('Pass the exact source SHA that built this app')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = info['CFBundleExecutable']
    if '/' in executable or executable in ('.', '..'):
        raise ValueError('Invalid bundle executable name')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Expected a physical iPhone app, not a Simulator build')
    if (app / 'embedded.mobileprovision').exists():
        raise ValueError('Personal provisioning profiles must not enter this unsigned package')
    binary = audit_binary((app / executable).read_bytes())
    if binary['hasCodeSignatureCommand']:
        raise ValueError('Expected the original unsigned archive executable')
    output.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_symlink():
                raise ValueError('Unexpected symlink in this iPhone app: ' + str(path))
            if path.is_dir():
                continue
            relative = pathlib.PurePosixPath('Payload', app.name, *path.relative_to(app).parts)
            content = path.read_bytes()
            entry = zipfile.ZipInfo(str(relative), (2026, 1, 1, 0, 0, 0))
            entry.create_system = 3
            mode = 0o755 if path == app / executable or path.suffix == '.dylib' else 0o644
            entry.external_attr = (stat.S_IFREG | mode) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, content)
            entries.append({'path': str(relative), 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()})
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != {item['path'] for item in entries}:
            raise ValueError('IPA contents/CRC verification failed')
        for entry in entries:
            if hashlib.sha256(archive.read(entry['path'])).hexdigest() != entry['sha256']:
                raise ValueError('IPA changed original app bytes: ' + entry['path'])
        packaged_info = plistlib.loads(archive.read(f'Payload/{app.name}/Info.plist'))
        if packaged_info != info:
            raise ValueError('Packaged Info.plist changed')
        executable_entry = archive.getinfo(f'Payload/{app.name}/{executable}')
        if not executable_entry.external_attr >> 16 & stat.S_IXUSR:
            raise ValueError('IPA executable lost its executable permission')
    receipt = {'file': output.name, 'bytes': output.stat().st_size,
               'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
               'sourceSHA': source_sha, 'version': info['CFBundleShortVersionString'],
               'build': info['CFBundleVersion'], 'bundleID': info['CFBundleIdentifier'],
               'signed': False, 'requiresTesterSigning': True, 'appReviewReady': False,
               'originalAppBytesPreserved': True, 'binary': binary, 'entries': entries}
    output.with_suffix('.json').write_text(json.dumps(receipt, indent=2) + '\n')
    output.with_suffix('.sha256').write_text(receipt['sha256'] + '  ' + output.name + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    parser.add_argument('--source-sha', required=True)
    args = parser.parse_args()
    result = package(args.app, args.output, args.source_sha)
    print(f"Verified unsigned IPA: {result['file']}, {result['bytes']} bytes, SHA-256 {result['sha256']}")
