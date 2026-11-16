#!/usr/bin/env python3
"""Record real Simulator video and host BlackHole loopback on one clock."""
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import threading
import time
from host_audio_consent import wait_for_audio_ready

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'NativeDemoRaw'


def receipt(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def consume_test_output(lines, log, timeline, stop_capture):
    """Finish media at the last authored PASS, before xcresult bookkeeping."""
    expected = ['test01ComposeJamAndMix', 'test02HarmonyCommandsAndVoiceSetup', 'test03PerformAndExport']
    observed = set()
    timeline['expected_methods'] = expected
    for line in lines:
        log.write(line);log.flush()
        print(line.rstrip(), flush=True)
        for method in expected:
            if method in line and ' passed' in line.lower():
                observed.add(method)
        if len(observed) == len(expected) and 'all_authored_methods_passed_notice_uptime' not in timeline:
            timeline['all_authored_methods_passed_notice_uptime'] = time.monotonic()
            timeline['actual_passed_methods'] = [method for method in expected if method in observed]
            stop_capture('all-three-authored-methods-passed')
    timeline['actual_passed_methods'] = [method for method in expected if method in observed]


def main():
    if sys.platform != 'darwin':
        raise SystemExit('Real native demonstration recording requires the macOS runner.')
    OUT.mkdir(exist_ok=True)
    device = Path('/tmp/grilla-simulator-id').read_text().strip()
    app = OUT / 'LaGrillaDemoAudioRecorder.app'
    executable = app / 'Contents/MacOS/LaGrillaDemoAudioRecorder'
    executable.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-O', '-swift-version', '5', 'Demos/record_host_audio.swift', '-o', str(executable), '-framework', 'AVFoundation', '-framework', 'AppKit', '-framework', 'CoreAudio', '-framework', 'AudioToolbox'], cwd=ROOT, check=True)
    (app / 'Contents/Info.plist').write_bytes((ROOT / 'Demos/AudioRecorderInfo.plist').read_bytes())
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    audio = subprocess.Popen(['open', '-W', '-n', str(app), '--args', str(OUT), '--max-seconds', '600'])
    video = None
    video_thread = None
    timeline = {'source_sha': os.environ.get('GITHUB_SHA'), 'device': device,
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
        if code != 0:
            raise RuntimeError(f'The real demo interaction failed with xcodebuild status {code}; video is diagnostic, not an accepted promo.')
        if timeline['actual_passed_methods'] != timeline['expected_methods']:
            raise RuntimeError('All three authored demo methods must actually execute and pass; an empty successful suite is not a capture.')
    finally:
        stop_capture('failure-or-final-cleanup')
        receipt('capture-timing.json', timeline)
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
    print('NATIVE_DEMO_CAPTURE_COMPLETE: real video, real loopback audio, three accepted UI journeys.', flush=True)


if __name__ == '__main__':
    main()
