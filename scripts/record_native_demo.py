#!/usr/bin/env python3
"""Record real Simulator video and host BlackHole loopback on one clock."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import plistlib
import re
import signal
import shutil
import subprocess
import sys
import threading
import time
import zipfile
from host_audio_consent import wait_for_audio_ready
from ci.native_scope import observed_outcomes

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'NativeDemoRaw'
BUILD_PRODUCTS = ROOT / 'DerivedData/Build/Products/Debug-iphonesimulator'
BUILD_RECEIPT = ROOT / 'demo-build-products.json'
BUILD_ARCHIVE = ROOT / 'DemoBuiltProducts.zip'
MACHO_MAGIC = {bytes.fromhex(value) for value in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca',
)}
EXPECTED_METHODS = [
    'test01ComposeJamAndMix', 'test02HarmonyCommandsAndVoiceSetup',
    'test03PerformAndExport', 'test04EmptyLocalSketchAndTranspose',
]
PROTOCOL_CASE = re.compile(
    r"^[ \t]*Test Case '-\[[^\s\]]+ [^\]\s]+\]' "
    r"(?:passed|failed|skipped|exceeded execution time allowance)\b"
)


def receipt(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def file_receipt(path):
    if path.is_symlink():
        target = os.readlink(path)
        data = os.fsencode(target)
        return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'symlink_target': target}
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def native_architecture(command):
    architecture = command('uname', '-m')
    runner = os.environ.get('RUNNER_ARCH')
    expected_runner = {'arm64': 'ARM64', 'x86_64': 'X64'}.get(architecture)
    if expected_runner is None or (runner and runner != expected_runner):
        raise RuntimeError(f'Unsupported or inconsistent actual native capture host: {architecture}; runner {runner}')
    requested = os.environ.get('GRILLA_DEMO_ARCH', architecture)
    if requested != architecture:
        raise RuntimeError(f'Demo build architecture {requested} differs from actual host {architecture}')
    return architecture, runner or expected_runner


def built_products_contract(command):
    """Inspect every actual Mach-O, including the loader, debug and test code."""
    architecture, runner = native_architecture(command)
    products = sorted(path for path in BUILD_PRODUCTS.rglob('*') if path.is_file() or path.is_symlink())
    if not products:
        raise RuntimeError('The actual Simulator build products are missing')
    main_app = BUILD_PRODUCTS / 'LaGrilla.app'
    required = [main_app / 'LaGrilla', main_app / 'LaGrilla.debug.dylib']
    tests = []
    for info_path in BUILD_PRODUCTS.rglob('Info.plist'):
        if info_path.parent.name != 'LaGrillaDemoTests.xctest':
            continue
        info = plistlib.loads(info_path.read_bytes())
        executable = info.get('CFBundleExecutable')
        if not isinstance(executable, str) or not executable or Path(executable).name != executable:
            raise RuntimeError('The actual Demo XCTest bundle has no safe executable name')
        tests.append(info_path.parent / executable)
    if not tests:
        raise RuntimeError('The actual built LaGrillaDemoTests.xctest executable is missing')
    required += tests
    inventory = {str(path.relative_to(ROOT)): file_receipt(path) for path in products}
    native = {str(path.relative_to(ROOT)) for path in required}
    macho = {}
    for path in products:
        if path.is_symlink():
            continue  # The preserved alias is a link; its real file is inventoried separately.
        with path.open('rb') as binary:
            magic = binary.read(4)
        if magic not in MACHO_MAGIC:
            continue
        name = str(path.relative_to(ROOT))
        architectures = command('xcrun', 'lipo', '-archs', str(path)).split()
        # Xcode's prebuilt UI-test runner and embedded Apple frameworks may
        # be universal. Our app/debug library and project test executable
        # are compiled for the one actual native Simulator architecture.
        project_built = name in native or (
            path.name == 'LaGrillaDemoTests.debug.dylib' and path.parent.name == 'LaGrillaDemoTests.xctest')
        if architecture not in architectures or (project_built and architectures != [architecture]):
            raise RuntimeError(f'Incompatible native Simulator Mach-O {name}: {architectures}; host {architecture}')
        macho[name] = dict(inventory[name], architectures=architectures, project_built=project_built)
    if not native.issubset(macho):
        raise RuntimeError('A required real app/debug/XCTest executable is absent from the Mach-O inventory')
    return dict(native_binary_contract_version=1, host_architecture=architecture,
                simulator_architecture=architecture, runner_architecture=runner,
                build_products_root=str(BUILD_PRODUCTS.relative_to(ROOT)),
                built_product_files=list(inventory), files=inventory,
                macho_files=macho, required_native_macho=sorted(native))


def preserve_build_products(build):
    """Preserve actual file bytes and symbolic links for independent auditing."""
    with zipfile.ZipFile(BUILD_ARCHIVE, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in build['built_product_files']:
            path = ROOT / name
            if file_receipt(path) != build['files'][name]:
                raise RuntimeError('A native build product changed while preserving its original bytes: ' + name)
            archived_name = str(Path(BUILD_PRODUCTS.name) / path.relative_to(BUILD_PRODUCTS))
            if path.is_symlink():
                info = zipfile.ZipInfo(archived_name)
                info.create_system = 3
                info.external_attr = 0o120777 << 16
                archive.writestr(info, os.fsencode(os.readlink(path)))
            else:
                archive.write(path, archived_name)


def capture_source(device, audio_helper):
    """Bind the actual built app, source, toolchain and device to this session."""
    def command(*args):
        return subprocess.check_output(args, cwd=ROOT, text=True, timeout=30).strip()

    head = command('git', 'rev-parse', 'HEAD')
    requested = os.environ.get('GITHUB_SHA', head)
    if requested != head or command('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Record only the exact clean checkout named by GITHUB_SHA; do not mislabel the source.')
    build = built_products_contract(command)
    prior_build = json.loads(BUILD_RECEIPT.read_text())
    if prior_build.get('source_sha') != head or prior_build.get('native_products') != build:
        raise RuntimeError('Actual build products differ from the original source-bound native build receipt')
    shutil.copyfile(BUILD_RECEIPT, OUT / 'build-products-receipt.json')
    helper_architectures = command('xcrun', 'lipo', '-archs', str(audio_helper)).split()
    if helper_architectures != [build['host_architecture']]:
        raise RuntimeError('The actual audio recorder must be native to this capture host')
    app = BUILD_PRODUCTS / 'LaGrilla.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    metadata = {'version': str(info['CFBundleShortVersionString']),
                'build': str(info['CFBundleVersion']), 'bundle_id': info['CFBundleIdentifier']}
    if metadata != {'version': '1.0.0', 'build': '20', 'bundle_id': 'com.alexgazin.LaGrilla'}:
        raise RuntimeError(f'The demo20 capture must use the actual build20 application: {metadata}')
    xcode = command('xcodebuild', '-version')
    sdk = command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    iphone_sdk = command('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    if xcode.splitlines()[0] != 'Xcode 26.3' or sdk != '26.2' or iphone_sdk != '26.2':
        raise RuntimeError(f'The native demo requires Xcode26.3 / Simulator SDK26.2: {xcode}; SDK {sdk}')
    devices = json.loads(command('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
    selected = [(key, item) for key, items in devices.items() for item in items if item['udid'] == device]
    runtime = selected[0][0] if len(selected) == 1 else None
    if runtime != 'com.apple.CoreSimulator.SimRuntime.iOS-26-2' or selected[0][1].get('state') != 'Booted':
        raise RuntimeError(f'The selected native Simulator must run iOS26.2: {runtime}')
    runtimes = json.loads(command('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
    runtime_info = next((item for item in runtimes if item['identifier'] == runtime), None)
    if not runtime_info or not runtime_info.get('isAvailable') or runtime_info.get('version') != '26.2':
        raise RuntimeError('The actual selected iOS26.2 runtime identity is unavailable')
    schema = int(re.search(r'currentSchemaVersion\s*=\s*(\d+)',
                 (ROOT / 'Packages/MusicDomain/Sources/MusicDomain/Model.swift').read_text()).group(1))
    if schema != 10:
        raise RuntimeError(f'The demo20 source must retain project schema10, observed {schema}')
    tracked = command('git', 'ls-files', '-z', '--', 'App', 'Features', 'AudioRuntime',
                      'Packages', 'Resources', 'project.yml', 'LaGrilla.xcodeproj', 'Demos',
                      'scripts/record_native_demo.py', 'scripts/select_simulator.py',
                      'scripts/ci/native_scope.py', 'scripts/host_audio_consent.py',
                      'Tools/NativeDemo', '.github/workflows/native-demo.yml').split('\0')
    paths = [ROOT / name for name in tracked if name]
    # Xcode's Debug executable can be a small loader. Bind every built bundle
    # file, including LaGrilla.debug.dylib, frameworks, assets and signatures.
    built_files = sorted(path for path in app.rglob('*') if path.is_file() or path.is_symlink())
    helper_files = sorted(path for path in audio_helper.parents[2].rglob('*') if path.is_file() or path.is_symlink())
    paths += [ROOT / name for name in build['built_product_files']] + helper_files
    files = {str(path.relative_to(ROOT)): file_receipt(path) for path in paths}
    result = dict(capture_schema=2, source_sha=head, git_head=head, app=metadata,
                  project_schema_version=schema, built_app_file_count=len(built_files),
                  xcode=xcode, simulator_sdk=sdk, iphone_os_sdk=iphone_sdk, host_os=command('sw_vers'),
                  device=device, simulator_device=selected[0][1], simulator_runtime=runtime, simulator_runtime_info=runtime_info,
                  native_binary_contract_version=build['native_binary_contract_version'],
                  host_architecture=build['host_architecture'], simulator_architecture=build['simulator_architecture'],
                  runner_architecture=build['runner_architecture'],
                  build_products_root=build['build_products_root'], built_product_files=build['built_product_files'],
                  macho_files=build['macho_files'], required_native_macho=build['required_native_macho'],
                  build_products_receipt_sha256=file_receipt(BUILD_RECEIPT)['sha256'],
                  build_products_archive=dict(file=BUILD_ARCHIVE.name, **file_receipt(BUILD_ARCHIVE)),
                  host_audio_helper=dict(path=str(audio_helper.relative_to(ROOT)),
                                         architectures=helper_architectures, **file_receipt(audio_helper)),
                  github_run_id=os.environ.get('GITHUB_RUN_ID'),
                  expected_methods=EXPECTED_METHODS, physical_device=False,
                  status='Capture source identity only; no audiovisual acceptance claimed',
                  files=files)
    receipt('source-receipt.json', result)
    return result


def preserve_raw_manifest():
    """Hash original capture files even when an actual interaction fails."""
    receipt('raw-manifest.json', {
        'kind': 'Original capture hashes; failed captures remain diagnostic',
        'files': {str(path.relative_to(OUT)): file_receipt(path)
                  for path in sorted(OUT.rglob('*'))
                  if path.is_file() and path.name != 'raw-manifest.json'
                  and 'LaGrillaDemoAudioRecorder.app' not in path.parts},
    })


def consume_test_output(lines, log, timeline, stop_capture):
    """Finish media at the last authored PASS, before xcresult bookkeeping."""
    expected = EXPECTED_METHODS
    outcomes = {}
    protocol_lines = []
    timeline['expected_methods'] = expected
    def update_timeline():
        timeline['required_test_outcomes'] = {
            'NativeDemoTests/' + method: outcomes.get('NativeDemoTests/' + method, 'not-observed')
            for method in expected}
        timeline['actual_passed_methods'] = [method for method in expected
                                             if outcomes.get('NativeDemoTests/' + method) == 'passed']
    for line in lines:
        log.write(line);log.flush()
        print(line.rstrip(), flush=True)
        match = PROTOCOL_CASE.match(line)
        if match is None:
            continue
        # Keep actual protocol fragments only. Quoted examples/prose and long
        # runtime diagnostics cannot become outcomes or cause repeated log scans.
        protocol_lines.append(match.group(0) + '\n')
        for identity, outcome in observed_outcomes(protocol_lines[-1]).items():
            if outcomes.get(identity) != 'time-allowance-exceeded':
                outcomes[identity] = outcome
        update_timeline()
        if timeline['actual_passed_methods'] == expected and 'all_authored_methods_passed_notice_uptime' not in timeline:
            timeline['all_authored_methods_passed_notice_uptime'] = time.monotonic()
            stop_capture('all-four-authored-methods-passed')
    # A late PASS must never erase an explicit allowance violation, even if
    # xcodebuild eventually exits zero. Parse the small protocol inventory once.
    outcomes = observed_outcomes(''.join(protocol_lines))
    update_timeline()


def main():
    if sys.platform != 'darwin':
        raise SystemExit('Real native demonstration recording requires the macOS runner.')
    if OUT.exists() and any(OUT.iterdir()):
        raise SystemExit('Refusing to overwrite an existing original NativeDemoRaw capture.')
    OUT.mkdir(exist_ok=True)
    device = Path('/tmp/grilla-simulator-id').read_text().strip()
    app = OUT / 'LaGrillaDemoAudioRecorder.app'
    executable = app / 'Contents/MacOS/LaGrillaDemoAudioRecorder'
    executable.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', 'Demos/record_host_audio.swift', '-o', str(executable), '-framework', 'AVFoundation', '-framework', 'AppKit', '-framework', 'CoreAudio', '-framework', 'AudioToolbox'], cwd=ROOT, check=True)
    (app / 'Contents/Info.plist').write_bytes((ROOT / 'Demos/AudioRecorderInfo.plist').read_bytes())
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    source = capture_source(device, executable)
    # Build15's real video already lasted537.7s; the fourth user journey needs
    # more than the old600s PCM ceiling. Per-case300s and workflow35m stay fixed.
    audio = subprocess.Popen(['open', '-W', '-n', str(app), '--args', str(OUT), '--max-seconds', '900'])
    video = None
    video_thread = None
    timeline = {'capture_schema': 2, 'source_sha': source['source_sha'], 'device': device,
                'source_receipt_sha256': file_receipt(OUT / 'source-receipt.json')['sha256'],
                'kind': 'Real simctl video plus actual host BlackHole loopback',
                'offline_soundtrack_substitution': False, 'physical_device': False}
    capture_stopped = False
    def stop_capture(reason):
        nonlocal capture_stopped
        if capture_stopped:
            return
        capture_stopped = True
        timeline['capture_stop_reason'] = reason
        if video is not None and video.poll() is None:
            timeline['video_stop_signal_uptime'] = time.monotonic()
            video.send_signal(signal.SIGINT)
            try:
                timeline['video_exit_code'] = video.wait(timeout=30)
            except subprocess.TimeoutExpired:
                video.kill();video.wait();timeline['video_error'] = 'stop-timeout'
        if video_thread:
            video_thread.join(timeout=3)
        (OUT / 'stop-audio').touch()
        try:
            audio.wait(timeout=20)
        except subprocess.TimeoutExpired:
            audio.terminate();audio.wait(timeout=10)
        timeline['capture_finished_uptime'] = time.monotonic()
        receipt('capture-timing.json', timeline)
    try:
        wait_for_audio_ready(OUT, audio)
        timeline['audio_ready_uptime'] = time.monotonic()
        timeline['video_spawn_before_uptime'] = time.monotonic()
        video = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', '--force', str(OUT / 'screen.mp4')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        timeline['video_spawn_after_uptime'] = time.monotonic()
        started = threading.Event()
        def watch_video():
            with (OUT / 'screen-recorder.log').open('w') as log:
                for line in video.stdout:
                    now = time.monotonic()
                    log.write(f'{now:.9f} {line}');log.flush()
                    print(line.rstrip(), flush=True)
                    if 'recording started' in line.lower():
                        timeline['video_recording_started_notice_uptime'] = now
                        started.set()
        video_thread = threading.Thread(target=watch_video, daemon=True)
        video_thread.start()
        if not started.wait(15):
            raise RuntimeError('simctl did not confirm that actual screen recording started.')
        timeline['test_start_uptime'] = time.monotonic()
        receipt('capture-timing.json', timeline)
        command = ['xcodebuild', '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '300', '-project', 'LaGrilla.xcodeproj', '-scheme', 'LaGrillaDemo', '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', 'DerivedData', '-resultBundlePath', 'NativeDemoResults.xcresult', 'ARCHS=' + source['simulator_architecture'], 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'test-without-building']
        with (OUT / 'demo-tests.log').open('w') as log:
            test = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            try:
                consume_test_output(test.stdout, log, timeline, stop_capture)
                code = test.wait(timeout=900)
            finally:
                if test.poll() is None:
                    test.terminate();test.wait(timeout=15)
        timeline['test_finish_uptime'] = time.monotonic()
        timeline['test_exit_code'] = code
        timeline['demo_tests_log_sha256'] = file_receipt(OUT / 'demo-tests.log')['sha256']
        if code != 0:
            raise RuntimeError(f'The real demo interaction failed with xcodebuild status {code}; video is diagnostic, not an accepted promo.')
        if timeline['actual_passed_methods'] != timeline['expected_methods']:
            raise RuntimeError('All four authored demo methods must execute and pass within their allowance; missing, skipped, failed or timed-out cases remain diagnostic.')
    finally:
        stop_capture('failure-or-final-cleanup')
        receipt('capture-timing.json', timeline)
        preserve_raw_manifest()
    audio_receipt = json.loads((OUT / 'audio-receipt.json').read_text())
    if audio_receipt.get('error') or audio_receipt.get('peak', 0) <= 0.001 or audio_receipt.get('frames', 0) == 0:
        raise RuntimeError('Captured native sound is invalid or silent; no music replacement is allowed.')
    if audio_receipt.get('sample_time_discontinuities') != 0:
        raise RuntimeError('Actual host PCM contains sample-time discontinuities; retain diagnostics instead of accepting the capture.')
    if audio_receipt.get('first_host_seconds', float('inf')) > timeline['video_spawn_before_uptime'] + 0.5 or audio_receipt.get('last_host_seconds', 0) < timeline['video_stop_signal_uptime'] - 0.5:
        raise RuntimeError('Actual sound capture must cover the video interval; a short unrelated sound cannot authorize the whole tour.')
    if (OUT / 'screen.mp4').stat().st_size < 1024:
        raise RuntimeError('The native screen recording is empty.')
    if shutil.which('ffprobe'):
        with (OUT / 'video-probe.json').open('w') as probe:
            subprocess.run(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(OUT / 'screen.mp4')], stdout=probe, check=True)
    else:
        receipt('video-probe-pending.json', {'status': 'Requires independent FFmpeg verification after artifact download', 'ffprobe_available_on_capture_host': False})
    preserve_raw_manifest()
    print('NATIVE_DEMO_CAPTURE_COMPLETE: four real UI journeys passed; original video/loopback audio await audiovisual review.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-built-products', action='store_true')
    arguments = parser.parse_args()
    if arguments.verify_built_products:
        if sys.platform != 'darwin':
            parser.error('Real native build verification requires the macOS capture host')
        def command(*args):
            return subprocess.check_output(args, cwd=ROOT, text=True, timeout=30).strip()
        head = command('git', 'rev-parse', 'HEAD')
        if os.environ.get('GITHUB_SHA', head) != head or command('git', 'status', '--porcelain', '--untracked-files=no'):
            parser.error('Native build verification requires the actual exact clean source')
        snapshot = dict(source_sha=head, native_products=built_products_contract(command))
        preserve_build_products(snapshot['native_products'])
        BUILD_RECEIPT.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + '\n')
        print('Verified every built Simulator Mach-O for native ' + snapshot['native_products']['host_architecture'])
    else:
        main()
