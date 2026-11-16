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

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'NativeDemoRaw'


def receipt(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def allow_expected_virtual_audio_dialog():
    # Click only the ordinary system prompt naming this exact purpose-built
    # recorder. No privacy database writes, resets or identity substitutions.
    script = '''tell application "System Events"
repeat with appProcess in application processes
 try
  repeat with dialogWindow in windows of appProcess
   set allControls to entire contents of dialogWindow
   set joinedText to name of dialogWindow as text
   repeat with aControl in allControls
    try
     if role of aControl is "AXStaticText" then
      set joinedText to joinedText & " " & (value of aControl as text)
     end if
    end try
   end repeat
   if joinedText contains "La Grilla Demo Audio Recorder" then
    repeat with aControl in allControls
     try
      if role of aControl is "AXButton" and (name of aControl is "Allow" or name of aControl is "OK") then
       perform action "AXPress" of aControl
       return "Allowed the expected virtual-audio recorder system prompt"
      end if
     end try
    end repeat
   end if
  end repeat
 end try
end repeat
end tell'''
    try:
        result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, timeout=3)
        if result.stdout.strip():
            print(result.stdout.strip(), flush=True)
    except subprocess.TimeoutExpired:
        pass


def main():
    if sys.platform != 'darwin':
        raise SystemExit('Real native demonstration recording requires the macOS runner.')
    OUT.mkdir(exist_ok=True)
    device = Path('/tmp/grilla-simulator-id').read_text().strip()
    app = OUT / 'LaGrillaDemoAudioRecorder.app'
    executable = app / 'Contents/MacOS/LaGrillaDemoAudioRecorder'
    executable.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', 'Demos/record_host_audio.swift', '-o', str(executable), '-framework', 'AVFoundation', '-framework', 'CoreAudio', '-framework', 'AudioToolbox'], cwd=ROOT, check=True)
    (app / 'Contents/Info.plist').write_bytes((ROOT / 'Demos/AudioRecorderInfo.plist').read_bytes())
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    audio = subprocess.Popen(['open', '-W', '-n', str(app), '--args', str(OUT), '--max-seconds', '600'])
    video = None
    video_thread = None
    timeline = {'source_sha': os.environ.get('GITHUB_SHA'), 'device': device,
                'kind': 'Real simctl video plus actual host BlackHole loopback',
                'offline_soundtrack_substitution': False, 'physical_device': False}
    try:
        deadline = time.monotonic() + 45
        while not (OUT / 'ready.json').exists():
            if time.monotonic() >= deadline or audio.poll() is not None:
                raise RuntimeError('Host audio recorder did not produce timestamped PCM; retain normal permission diagnostics.')
            allow_expected_virtual_audio_dialog()
            time.sleep(0.2)
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
                for line in test.stdout:
                    log.write(line);log.flush()
                    print(line.rstrip(), flush=True)
                code = test.wait(timeout=900)
            finally:
                if test.poll() is None:
                    test.terminate();test.wait(timeout=15)
        timeline['test_finish_uptime'] = time.monotonic()
        timeline['test_exit_code'] = code
        if code != 0:
            raise RuntimeError(f'The real demo interaction failed with xcodebuild status {code}; video is diagnostic, not an accepted promo.')
        test_log = (OUT / 'demo-tests.log').read_text()
        expected = ['test01ComposeJamAndMix', 'test02HarmonyCommandsAndVoiceSetup', 'test03PerformAndExport']
        actual_passed = [name for name in expected if any(name in line and ' passed' in line.lower() for line in test_log.splitlines())]
        timeline['expected_methods'] = expected
        timeline['actual_passed_methods'] = actual_passed
        if actual_passed != expected:
            raise RuntimeError('All three authored demo methods must actually execute and pass; an empty successful suite is not a capture.')
    finally:
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
    audio_receipt = json.loads((OUT / 'audio-receipt.json').read_text())
    if audio_receipt.get('error') or audio_receipt.get('peak', 0) <= 0.001 or audio_receipt.get('frames', 0) == 0:
        raise RuntimeError('Captured native sound is invalid or silent; no music replacement is allowed.')
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
