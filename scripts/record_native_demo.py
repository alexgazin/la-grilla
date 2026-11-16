#!/usr/bin/env python3
"""Record real Simulator video and host BlackHole loopback on one clock."""
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
from host_audio_consent import wait_for_audio_ready
from ci.native_scope import observed_outcomes

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'NativeDemoRaw'
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
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def capture_source(device):
    """Bind the actual built app, source, toolchain and device to this session."""
    def command(*args):
        return subprocess.check_output(args, cwd=ROOT, text=True).strip()

    head = command('git', 'rev-parse', 'HEAD')
    requested = os.environ.get('GITHUB_SHA', head)
    if requested != head or command('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Record only the exact clean checkout named by GITHUB_SHA; do not mislabel the source.')
    app = ROOT / 'DerivedData/Build/Products/Debug-iphonesimulator/LaGrilla.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    metadata = {'version': str(info['CFBundleShortVersionString']),
                'build': str(info['CFBundleVersion']), 'bundle_id': info['CFBundleIdentifier']}
    if metadata != {'version': '1.0.0', 'build': '20', 'bundle_id': 'com.alexgazin.LaGrilla'}:
        raise RuntimeError(f'The demo20 capture must use the actual build20 application: {metadata}')
    xcode = command('xcodebuild', '-version')
    sdk = command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    if xcode.splitlines()[0] != 'Xcode 26.3' or sdk != '26.2':
        raise RuntimeError(f'The native demo requires Xcode26.3 / Simulator SDK26.2: {xcode}; SDK {sdk}')
    devices = json.loads(command('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
    runtime = next((key for key, items in devices.items() if any(item['udid'] == device for item in items)), None)
    if runtime != 'com.apple.CoreSimulator.SimRuntime.iOS-26-2':
        raise RuntimeError(f'The selected native Simulator must run iOS26.2: {runtime}')
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
    built_files = sorted(path for path in app.rglob('*') if path.is_file())
    paths += built_files
    result = dict(capture_schema=2, source_sha=head, git_head=head, app=metadata,
                  project_schema_version=schema, built_app_file_count=len(built_files),
                  xcode=xcode, simulator_sdk=sdk,
                  device=device, simulator_runtime=runtime,
                  github_run_id=os.environ.get('GITHUB_RUN_ID'),
                  expected_methods=EXPECTED_METHODS, physical_device=False,
                  status='Capture source identity only; no audiovisual acceptance claimed',
                  files={str(path.relative_to(ROOT)): file_receipt(path) for path in paths})
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
    source = capture_source(device)
    app = OUT / 'LaGrillaDemoAudioRecorder.app'
    executable = app / 'Contents/MacOS/LaGrillaDemoAudioRecorder'
    executable.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', 'Demos/record_host_audio.swift', '-o', str(executable), '-framework', 'AVFoundation', '-framework', 'AppKit', '-framework', 'CoreAudio', '-framework', 'AudioToolbox'], cwd=ROOT, check=True)
    (app / 'Contents/Info.plist').write_bytes((ROOT / 'Demos/AudioRecorderInfo.plist').read_bytes())
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
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
        command = ['xcodebuild', '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '300', '-project', 'LaGrilla.xcodeproj', '-scheme', 'LaGrillaDemo', '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', 'DerivedData', '-resultBundlePath', 'NativeDemoResults.xcresult', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'test-without-building']
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
    main()
