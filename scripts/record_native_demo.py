#!/usr/bin/env python3
"""Record real Simulator video and host BlackHole loopback on one clock."""
import argparse
import json
import hashlib
import math
import os
from pathlib import Path
import plistlib
import queue
import re
import secrets
import signal
import shutil
import subprocess
import sys
import threading
import time
import zipfile
from host_audio_consent import wait_for_audio_ready
from host_audio_probe import recorder_build_receipt
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
PREPARATION_METHOD = 'test00PrepareActualAppAndCaptureReadiness'
EXPECTED_FEATURE_PHASES = ['sound.warm-kit-real-preview', 'sound.warm-kit-applied-groove',
                           'notes.resize-before-real-touch', 'notes.resize-committed', 'notes.resize-single-undo']
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


def preboot_host_probe(head):
    path = ROOT / 'HostAudioProbe/probe-receipt.json'
    probe = json.loads(path.read_text())
    finish, stopped = probe.get('tone_finish_uptime'), probe.get('finished_uptime')
    if (probe.get('status') != 'passed' or probe.get('source_sha') != head
            or type(finish) not in (int, float) or type(stopped) not in (int, float)
            or not math.isfinite(finish) or not math.isfinite(stopped) or not 0 < finish <= stopped):
        raise RuntimeError('The separate exact-source normal host probe must have completed and stopped before recording')
    return dict(file=str(path.relative_to(ROOT)), tone_finish_uptime=finish,
                finished_uptime=stopped, **file_receipt(path))


def verify_probe_before_video(probe, video_start):
    if not math.isfinite(video_start) or not video_start > probe['tone_finish_uptime'] + 0.5 or video_start < probe['finished_uptime']:
        raise RuntimeError('The independent probe tone and recorder must finish before any actual movie recording')


def reuse_preboot_recorder():
    """Copy the probe's verified executable, never its recorded sound."""
    probe = json.loads((ROOT / 'HostAudioProbe/probe-receipt.json').read_text())
    original = ROOT / 'HostAudioProbe/LaGrillaDemoAudioRecorder.app'
    if probe.get('status') != 'passed' or probe.get('source_sha') != os.environ.get('GITHUB_SHA'):
        raise RuntimeError('The actual preboot recorder requires a passed exact-source probe')
    built = recorder_build_receipt(original)
    if built != probe.get('recorder_build'):
        raise RuntimeError('The original preboot recorder source, signature or native bundle bytes differ')
    target = OUT / original.name
    shutil.copytree(original, target)
    copied = recorder_build_receipt(target)
    if {key: value for key, value in copied.items() if key != 'bundle'} != {
            key: value for key, value in built.items() if key != 'bundle'}:
        raise RuntimeError('The fresh capture must use exactly the independently probed recorder bundle')
    receipt('recorder-build-receipt.json', dict(source_sha=probe['source_sha'],
            original=built, reused=copied, recorded_pcm_reused=False))
    return target, target / 'Contents/MacOS/LaGrillaDemoAudioRecorder'


def runner_bundle_identifier():
    candidates = []
    for info in BUILD_PRODUCTS.glob('*-Runner.app/Info.plist'):
        if (info.parent / 'PlugIns/LaGrillaDemoTests.xctest').is_dir():
            candidates.append(plistlib.loads(info.read_bytes())['CFBundleIdentifier'])
    if len(candidates) != 1 or not isinstance(candidates[0], str) or not candidates[0].endswith('.xctrunner'):
        raise RuntimeError('The actual built Demo XCTest runner must have one unambiguous bundle identity')
    return candidates[0]


def actual_runner_container(device, bundle, observed):
    """Resolve after XCTest installed/launched its actual selected runner."""
    if observed.get('device') != device or observed.get('runner_bundle_id') != bundle:
        raise RuntimeError('The actual ready runner differs from the selected device or built bundle')
    value = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'],
                                    text=True, timeout=30).strip()
    container = Path(value).resolve(strict=True)
    expected_parent = (Path.home() / 'Library/Developer/CoreSimulator/Devices' / device /
                       'data/Containers/Data/Application').resolve(strict=True)
    if (container.parent != expected_parent or not re.fullmatch(r'[0-9A-Fa-f-]{36}', container.name)
            or Path(observed.get('runner_home', '')).resolve(strict=True) != container):
        raise RuntimeError('The actual runner container must belong to the selected Simulator and ready process')
    directory = container / 'tmp/LaGrillaDemoMedia'
    if not directory.is_dir() or directory.is_symlink() or directory.resolve(strict=True) != directory:
        raise RuntimeError('The actual runner must create its own ordinary, source-challenged preparation directory')
    if any((directory / name).exists() or (directory / name).is_symlink()
           for name in ('challenge.json', 'ready.json', 'release.json', 'prepared.json')):
        raise RuntimeError('Refusing a stale or already released capture preparation')
    return container, directory


def write_gate(path, value):
    if path.parent.is_symlink() or path.exists() or path.is_symlink():
        raise RuntimeError('Refusing to replace an existing capture preparation record')
    temporary = path.with_name('.' + path.name + '.' + secrets.token_hex(8))
    try:
        with temporary.open('x') as output:
            json.dump(value, output, sort_keys=True)
            output.write('\n')
        os.link(temporary, path)  # Atomic publication with no overwrite.
    finally:
        temporary.unlink(missing_ok=True)


def read_gate(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16384:
        raise RuntimeError('Capture preparation requires a small ordinary JSON file')
    return json.loads(path.read_text())


def simulator_inventory(source_sha):
    """One actual snapshot shares the former two metadata RPCs' 60s total."""
    command = ['xcrun', 'simctl', 'list', '-j']
    began = time.monotonic()
    stdout = stderr = b''
    status = dict(source_sha=source_sha, command=command, maximum_total_seconds=60,
                  started_at_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                  started_uptime=began, timed_out=False, retry_count=0)
    try:
        remaining = float(os.environ.get('GRILLA_DEMO_DEADLINE_EPOCH', time.time() + 60)) - time.time()
        if not math.isfinite(remaining) or remaining <= 0:
            raise RuntimeError('The shared capture deadline expired before Simulator metadata acquisition')
        status['effective_timeout_seconds'] = min(60, remaining)
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=status['effective_timeout_seconds'])
        stdout, stderr = result.stdout, result.stderr
        status['exit_code'] = result.returncode
        if result.returncode != 0:
            raise RuntimeError('The actual combined Simulator inventory command failed')
        inventory = json.loads(stdout)
        if not isinstance(inventory.get('devices'), dict) or not isinstance(inventory.get('runtimes'), list):
            raise RuntimeError('The actual combined Simulator inventory must contain devices and runtimes')
        return inventory
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        status.update(exit_code=124, timed_out=True, error='combined-simulator-inventory-timeout')
        raise RuntimeError('The actual combined Simulator inventory exceeded its shared metadata budget') from error
    except BaseException as error:
        status.setdefault('exit_code', 127 if isinstance(error, OSError) else None)
        status['error'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        for name, data in [('simulator-inventory.json', stdout), ('simulator-inventory-stderr.log', stderr)]:
            (OUT / name).write_bytes(data)
        status.update(finished_uptime=time.monotonic(), elapsed_seconds=time.monotonic() - began,
                      stdout=file_receipt(OUT / 'simulator-inventory.json'),
                      stderr=file_receipt(OUT / 'simulator-inventory-stderr.log'))
        receipt('simulator-inventory-status.json', status)


def capture_source(device, audio_helper):
    """Bind the actual built app, source, toolchain and device to this session."""
    def command(*args):
        return subprocess.check_output(args, cwd=ROOT, text=True, timeout=30).strip()

    head = command('git', 'rev-parse', 'HEAD')
    requested = os.environ.get('GITHUB_SHA', head)
    if requested != head or command('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Record only the exact clean checkout named by GITHUB_SHA; do not mislabel the source.')
    probe = preboot_host_probe(head)
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
    if metadata != {'version': '1.0.0', 'build': '22', 'bundle_id': 'com.alexgazin.LaGrilla'}:
        raise RuntimeError(f'The demo22 capture must use the actual build22 application: {metadata}')
    xcode = command('xcodebuild', '-version')
    sdk = command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    iphone_sdk = command('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    if xcode.splitlines()[0] != 'Xcode 26.3' or sdk != '26.2' or iphone_sdk != '26.2':
        raise RuntimeError(f'The native demo requires Xcode26.3 / Simulator SDK26.2: {xcode}; SDK {sdk}')
    inventory = simulator_inventory(head)
    devices = inventory['devices']
    selected = [(key, item) for key, items in devices.items() for item in items if item['udid'] == device]
    runtime = selected[0][0] if len(selected) == 1 else None
    if (runtime != 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'
            or selected[0][1].get('state') != 'Booted' or selected[0][1].get('isAvailable') is not True):
        raise RuntimeError(f'The selected native Simulator must be uniquely available and Booted on iOS26.2: {runtime}')
    runtimes = inventory['runtimes']
    runtime_info = next((item for item in runtimes if item['identifier'] == runtime), None)
    if not runtime_info or not runtime_info.get('isAvailable') or runtime_info.get('version') != '26.2':
        raise RuntimeError('The actual selected iOS26.2 runtime identity is unavailable')
    schema = int(re.search(r'currentSchemaVersion\s*=\s*(\d+)',
                 (ROOT / 'Packages/MusicDomain/Sources/MusicDomain/Model.swift').read_text()).group(1))
    if schema != 11:
        raise RuntimeError(f'The demo22 source must retain project schema11, observed {schema}')
    tracked = command('git', 'ls-files', '-z', '--', 'App', 'Features', 'AudioRuntime',
                      'Packages', 'Resources', 'project.yml', 'LaGrilla.xcodeproj', 'Demos',
                      'scripts/record_native_demo.py', 'scripts/select_simulator.py',
                      'scripts/ci/native_scope.py', 'scripts/host_audio_consent.py', 'scripts/host_audio_probe.py',
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
                  preboot_host_probe=probe,
                  github_run_id=os.environ.get('GITHUB_RUN_ID'),
                  expected_methods=EXPECTED_METHODS, physical_device=False,
                  expected_feature_phases=EXPECTED_FEATURE_PHASES,
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


def consume_test_output(lines, log, timeline, stop_capture, observe_line=None):
    """Finish media at the last authored PASS, before xcresult bookkeeping."""
    expected = EXPECTED_METHODS
    outcomes = {}
    protocol_lines = []
    timeline['expected_methods'] = expected
    timeline['expected_preparation_method'] = PREPARATION_METHOD
    def update_timeline():
        timeline['required_test_outcomes'] = {
            'NativeDemoTests/' + method: outcomes.get('NativeDemoTests/' + method, 'not-observed')
            for method in expected}
        timeline['actual_passed_methods'] = [method for method in expected
                                             if outcomes.get('NativeDemoTests/' + method) == 'passed']
        timeline['preparation_test_outcome'] = outcomes.get('NativeDemoTests/' + PREPARATION_METHOD, 'not-observed')
    for line in lines:
        log.write(line);log.flush()
        print(line.rstrip(), flush=True)
        if observe_line:
            observe_line(line)
        if re.match(r'^[ \t]*Restarting after unexpected exit, crash, or test timeout;', line):
            timeline['first_native_failure'] = dict(kind='runner-restart', notice_uptime=time.monotonic())
            stop_capture('first-native-failure')
            raise RuntimeError('An unexpected actual runner restart cannot become a hidden successful retry')
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
        failures = {key: value for key, value in outcomes.items() if value != 'passed'}
        if failures:
            timeline['first_native_failure'] = dict(outcomes=failures, notice_uptime=time.monotonic())
            stop_capture('first-native-failure')
            raise RuntimeError('The first actual native failure ends this capture; original failure is retained')
        if (timeline['preparation_test_outcome'] == 'passed' and timeline['actual_passed_methods'] == expected
                and 'all_authored_methods_passed_notice_uptime' not in timeline):
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
    try:
        capture_native_demo()
    finally:
        preserve_raw_manifest()


def capture_native_demo():
    device = Path('/tmp/grilla-simulator-id').read_text().strip()
    app, executable = reuse_preboot_recorder()
    source = capture_source(device, executable)
    preparation = dict(version='1', source_sha=source['source_sha'], device=device,
                       nonce=secrets.token_hex(24), runner_bundle_id=runner_bundle_identifier(),
                       preparation_method=PREPARATION_METHOD)
    source['capture_preparation'] = preparation
    source['prepared_recorder_receipt'] = dict(file='recorder-build-receipt.json',
                                              **file_receipt(OUT / 'recorder-build-receipt.json'))
    receipt('source-receipt.json', source)
    timeline = {'capture_schema': 2, 'source_sha': source['source_sha'], 'device': device,
                'source_receipt_sha256': file_receipt(OUT / 'source-receipt.json')['sha256'],
                'preboot_host_probe_receipt_sha256': source['preboot_host_probe']['sha256'],
                'preboot_host_probe_tone_finish_uptime': source['preboot_host_probe']['tone_finish_uptime'],
                'preboot_host_probe_finished_uptime': source['preboot_host_probe']['finished_uptime'],
                'kind': 'Real simctl video plus actual host BlackHole loopback',
                'offline_soundtrack_substitution': False, 'physical_device': False}
    deadline = float(os.environ.get('GRILLA_DEMO_DEADLINE_EPOCH', time.time() + 28 * 60))
    if not math.isfinite(deadline) or deadline <= time.time():
        raise RuntimeError('The original job-clock budget must leave time for owned capture cleanup')
    timeline['capture_deadline_epoch'] = deadline
    audio = video = test = video_thread = None
    directory = challenge = None
    capture_stopped = False
    test_stop_requested = False

    def interrupt_test():
        nonlocal test_stop_requested
        if test is not None and not test_stop_requested:
            test_stop_requested = True
            timeline['test_stop_signal_uptime'] = time.monotonic()
            try:
                os.killpg(test.pid, signal.SIGINT)
            except ProcessLookupError:
                pass

    def finish_test():
        if test is None:
            return
        if test.poll() is None:
            interrupt_test()
            for seconds, next_signal in ((20, signal.SIGTERM), (10, signal.SIGKILL), (2, None)):
                try:
                    test.wait(timeout=seconds)
                    break
                except subprocess.TimeoutExpired:
                    if next_signal is not None:
                        try:
                            os.killpg(test.pid, next_signal)
                        except ProcessLookupError:
                            pass
        timeline['test_exit_code'] = test.returncode
        timeline['test_finish_uptime'] = time.monotonic()

    def stop_capture(reason):
        nonlocal capture_stopped
        if reason != 'all-four-authored-methods-passed':
            interrupt_test()  # Cancel the runner immediately, before closing media.
        if capture_stopped:
            return
        capture_stopped = True
        timeline['capture_stop_reason'] = reason
        if video is not None:
            timeline['video_stop_signal_uptime'] = time.monotonic()
            try:
                if video.poll() is not None:
                    raise RuntimeError('Screen recorder ended before its owned stop signal')
                video.send_signal(signal.SIGINT)
                try:
                    timeline['video_exit_code'] = video.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    video.kill();video.wait(timeout=2)
                    raise RuntimeError('Screen recorder did not finalize within its bounded stop')
            except BaseException as error:
                timeline['video_error'] = type(error).__name__ + ': ' + str(error)
        if video_thread:
            video_thread.join(timeout=3)
        if audio is not None:
            (OUT / 'stop-audio').touch()
            try:
                try:
                    timeline['audio_launcher_exit_code'] = audio.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    audio.terminate()
                    try:
                        audio.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        audio.kill();audio.wait(timeout=2)
                    raise RuntimeError('Actual audio did not finish within its bounded stop')
            except BaseException as error:
                timeline['audio_stop_error'] = type(error).__name__ + ': ' + str(error)
        timeline['capture_finished_uptime'] = time.monotonic()
        receipt('capture-timing.json', timeline)

    def start_capture():
        nonlocal audio, video, video_thread
        if time.time() + 120 >= deadline or capture_stopped or audio is not None:
            raise RuntimeError('Actual capture must start once with enough reserved initialization/cleanup time')
        # The probe's compiled/signed bundle is reused, but this is new PCM.
        audio = subprocess.Popen(['open', '-W', '-n', str(app), '--args', str(OUT), '--max-seconds', '900'])
        wait_for_audio_ready(OUT, audio)
        timeline['audio_ready_uptime'] = time.monotonic()
        timeline['video_spawn_before_uptime'] = time.monotonic()
        verify_probe_before_video(source['preboot_host_probe'], timeline['video_spawn_before_uptime'])
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
        if not started.wait(15) or video.poll() is not None:
            raise RuntimeError('simctl did not confirm actual running screen recording')
        release = dict(challenge, audio_ready_uptime=str(timeline['audio_ready_uptime']),
                       video_ready_uptime=str(timeline['video_recording_started_notice_uptime']),
                       released_uptime=str(time.monotonic()))
        write_gate(directory / 'release.json', release)
        receipt('capture-barrier-release.json', release)
        timeline['capture_release_uptime'] = float(release['released_uptime'])
        receipt('capture-timing.json', timeline)

    def observe_line(line):
        nonlocal directory, challenge
        if line.startswith('NATIVE_DEMO_CONTAINER_READY '):
            if directory is not None:
                raise RuntimeError('The actual capture runner must initialize once; no hidden restart')
            observed = json.loads(line.split(' ', 1)[1])
            container, directory = actual_runner_container(device, preparation['runner_bundle_id'], observed)
            challenge = dict(preparation, runner_home=str(container))
            write_gate(directory / 'challenge.json', challenge)
            receipt('capture-barrier-challenge.json', challenge)
            timeline['runner_container_verified_uptime'] = time.monotonic()
        elif line.startswith('NATIVE_DEMO_CAPTURE_READY '):
            ready = json.loads(line.split(' ', 1)[1])
            if directory is None or any(ready.get(key) != value for key, value in challenge.items()):
                raise RuntimeError('Actual capture readiness must answer the selected source/nonce/container challenge')
            if (ready != read_gate(directory / 'ready.json') or ready.get('actual_app_foreground') != '1'
                    or ready.get('actual_controls_hittable') != '1'
                    or not re.fullmatch(r'[1-9][0-9]*', ready.get('runner_pid', ''))):
                raise RuntimeError('The actual ready file and runner control observations must agree')
            observed = float(ready['observed_uptime'])
            if not math.isfinite(observed) or not timeline['test_start_uptime'] <= observed <= time.monotonic() + 2:
                raise RuntimeError('Actual application readiness must belong to this test process clock interval')
            receipt('capture-barrier-ready.json', ready)
            timeline['actual_application_ready_notice_uptime'] = time.monotonic()
            start_capture()
        elif line.startswith('NATIVE_DEMO_EVENT '):
            event = json.loads(line.split(' ', 1)[1])
            if event.get('phase') != 'app.ready' and 'capture_release_uptime' not in timeline:
                raise RuntimeError('A demonstrated action cannot precede actual audio/video readiness')
            if event.get('phase') in EXPECTED_FEATURE_PHASES:
                timeline.setdefault('observed_feature_phases', []).append(event['phase'])
        elif re.match(r"^Test Case '-\[[^\]]+ " + PREPARATION_METHOD + r"\]' passed\b", line):
            prepared = read_gate(directory / 'prepared.json') if directory else {}
            if (challenge is None or any(prepared.get(key) != value for key, value in challenge.items())
                    or prepared.get('preparation_complete') != '1' or 'capture_release_uptime' not in timeline):
                raise RuntimeError('Actual preparation PASS requires its completed source-bound media barrier')
            receipt('capture-barrier-prepared.json', prepared)
            timeline['preparation_pass_notice_uptime'] = time.monotonic()

    old_handlers = {value: signal.getsignal(value) for value in (signal.SIGINT, signal.SIGTERM)}
    def interrupted(number, _frame):
        timeline['received_signal'] = number
        raise RuntimeError('Native capture was interrupted; close owned media and retain diagnostics')
    for value in old_handlers:
        signal.signal(value, interrupted)
    try:
        command = ['xcodebuild', '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '300', '-project', 'LaGrilla.xcodeproj', '-scheme', 'LaGrillaDemo', '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', 'DerivedData', '-resultBundlePath', 'NativeDemoResults.xcresult', 'ARCHS=' + source['simulator_architecture'], 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'test-without-building']
        with (OUT / 'demo-tests.log').open('w') as log, open(os.devnull, 'w') as protocol_sink:
            timeline['test_start_uptime'] = time.monotonic()
            receipt('capture-timing.json', timeline)
            test = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, bufsize=1, start_new_session=True)
            pending = queue.Queue()
            def read_lines():
                try:
                    for line in test.stdout:
                        log.write(line);log.flush()
                        pending.put(line)
                finally:
                    pending.put(None)
            reader = threading.Thread(target=read_lines, daemon=True)
            reader.start()
            def lines():
                while True:
                    if time.time() >= deadline:
                        raise RuntimeError('The shared job-clock deadline reserved time for media finalization and original artifacts')
                    if not capture_stopped:
                        if audio is not None and audio.poll() is not None:
                            raise RuntimeError('The real PCM recorder ended before all four journeys completed')
                        if video is not None and video.poll() is not None:
                            raise RuntimeError('The real screen recorder ended before all four journeys completed')
                    try:
                        line = pending.get(timeout=0.5)
                    except queue.Empty:
                        continue
                    if line is None:
                        return
                    yield line
            try:
                consume_test_output(lines(), protocol_sink, timeline, stop_capture, observe_line)
                code = test.wait(timeout=30)
                timeline['test_exit_code'] = code
                if code != 0:
                    raise RuntimeError(f'The actual native demo failed with xcodebuild status {code}')
                if (timeline.get('preparation_test_outcome') != 'passed'
                        or timeline.get('actual_passed_methods') != EXPECTED_METHODS
                        or timeline.get('observed_feature_phases') != EXPECTED_FEATURE_PHASES):
                    raise RuntimeError('Actual preparation, four journeys and the build22 sound/touch scenes must pass without any allowance failure')
            except BaseException:
                stop_capture('failure-or-final-cleanup')
                raise
            finally:
                # The reader owns the original log, including failure/cancel
                # finalization output, until our process group has stopped.
                finish_test()
                reader.join(timeout=3)
                if reader.is_alive():
                    timeline['test_output_error'] = 'owned child stdout did not close after bounded process cleanup'
    except BaseException as error:
        timeline['failure_reason'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        for value in old_handlers:
            signal.signal(value, signal.SIG_IGN)
        try:
            if timeline.get('capture_stop_reason') != 'all-four-authored-methods-passed':
                stop_capture('failure-or-final-cleanup')
            finish_test()
            if (OUT / 'demo-tests.log').exists():
                timeline['demo_tests_log_sha256'] = file_receipt(OUT / 'demo-tests.log')['sha256']
            receipt('capture-timing.json', timeline)
        finally:
            for value, handler in old_handlers.items():
                signal.signal(value, handler)
    audio_receipt = json.loads((OUT / 'audio-receipt.json').read_text())
    if timeline.get('video_error') or timeline.get('audio_stop_error') or timeline.get('test_output_error'):
        raise RuntimeError('Every actual media process must finalize cleanly; retain the failed capture')
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
    print('NATIVE_DEMO_CAPTURE_COMPLETE: readiness and four real UI journeys passed; original video/loopback audio await audiovisual review.', flush=True)


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
