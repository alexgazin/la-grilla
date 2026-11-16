#!/usr/bin/env python3
"""Audio-only real BlackHole capture probe; its test tone never enters the demo."""
from array import array
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import wave

from host_audio_consent import wait_for_audio_ready

ROOT = Path(__file__).resolve().parents[1]


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def make_probe_tone(path):
    """Independent known source: stereo 440/660 Hz, 8 s with 10 ms fades."""
    rate, frames = 48000, 8 * 48000
    pcm = array('h')
    for frame in range(frames):
        fade = min(1.0, frame / 480, (frames - frame - 1) / 480)
        for frequency in (440, 660):
            pcm.append(round(0.2 * 32767 * fade * math.sin(2 * math.pi * frequency * frame / rate)))
    if sys.byteorder != 'little':
        pcm.byteswap()
    with wave.open(str(path), 'wb') as output:
        output.setparams((2, 2, rate, frames, 'NONE', 'not compressed'))
        output.writeframes(pcm.tobytes())


def spectral_power(samples, frequency, rate):
    coefficient = 2 * math.cos(2 * math.pi * frequency / rate)
    previous = before_previous = 0.0
    for sample in samples:
        current = sample / 32768 + coefficient * previous - before_previous
        before_previous, previous = previous, current
    return max(0.0, previous * previous + before_previous * before_previous - coefficient * previous * before_previous) / max(1, len(samples) ** 2)


def analyze_capture(path):
    with wave.open(str(path), 'rb') as source:
        channels, width, rate, frames = source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getnframes()
        assert channels == 2 and width == 2 and frames > 0, 'Expected actual stereo PCM16 conversion'
        pcm = array('h', source.readframes(frames))
    if sys.byteorder != 'little':
        pcm.byteswap()
    assert len(pcm) == frames * channels, 'Decoded capture length mismatch'
    peak = max(abs(value) for value in pcm) / 32768
    rms = math.sqrt(sum((value / 32768) ** 2 for value in pcm) / len(pcm))
    powers = []
    for channel, expected in enumerate((440, 660)):
        samples = pcm[channel::2]
        on = spectral_power(samples, expected, rate)
        off = spectral_power(samples, 997, rate)
        powers.append({'channel': channel, 'expected_frequency_hz': expected,
                       'expected_frequency_power': on, 'off_frequency_997hz_power': off,
                       'power_ratio': on / max(off, 1e-20)})
    assert peak > 0.01 and rms > 0.001, 'Actual loopback is silent or too quiet'
    assert all(item['expected_frequency_power'] > 1e-7 and item['power_ratio'] > 100 for item in powers), 'The actual capture does not contain the played stereo probe signature'
    return {'channels': channels, 'sample_width_bytes': width, 'sample_rate': rate,
            'frames': frames, 'duration_seconds': frames / rate, 'peak': peak, 'rms': rms,
            'stereo_probe_signature': powers, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def tcc_observations(output):
    # Read only this purpose-built recorder's TCC messages, never mutate policy.
    predicate = 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS "LaGrillaDemoAudioRecorder" OR eventMessage CONTAINS "com.alexgazin.LaGrilla.DemoAudioRecorder")'
    try:
        result = subprocess.run(['/usr/bin/log', 'show', '--last', '2m', '--style', 'compact', '--predicate', predicate], capture_output=True, text=True, timeout=10)
        (output / 'tcc-observations.log').write_text(result.stdout + '\nSTDERR:\n' + result.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        (output / 'tcc-observations.log').write_text(type(error).__name__ + ': ' + str(error) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'HostAudioProbe')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This probe requires macOS and the real BlackHole HAL driver')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ('ready.json', 'failure.json', 'audio-receipt.json', 'stop-audio'):
        (output / name).unlink(missing_ok=True)
    app = output / 'LaGrillaDemoAudioRecorder.app'
    executable = app / 'Contents/MacOS/LaGrillaDemoAudioRecorder'
    executable.parent.mkdir(parents=True, exist_ok=True)
    command = ['xcrun', 'swiftc', '-O', '-swift-version', '5', 'Demos/record_host_audio.swift', '-o', str(executable), '-framework', 'AppKit', '-framework', 'AVFoundation', '-framework', 'CoreAudio', '-framework', 'AudioToolbox']
    subprocess.run(command, cwd=ROOT, check=True)
    shutil.copyfile(ROOT / 'Demos/AudioRecorderInfo.plist', app / 'Contents/Info.plist')
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    probe = {'kind': 'Audio-only normal-consent host-loopback probe',
             'source_sha': os.environ.get('GITHUB_SHA'),
             'probe_tone_in_final_film': False, 'simulator_launched': False,
             'tcc_policy_mutated': False, 'physical_microphone_selected': False,
             'launched_uptime': time.monotonic()}
    with (output / 'launcher.log').open('w') as launcher_log:
        process = subprocess.Popen(['open', '-W', '-n', str(app), '--args', str(output), '--max-seconds', '90'], stdout=launcher_log, stderr=subprocess.STDOUT)
        try:
            wait_for_audio_ready(output, process, timeout=75)
            probe['ready_uptime'] = time.monotonic()
            tone = output / 'probe-only-440-660hz.wav'
            make_probe_tone(tone)
            probe['tone_sha256'] = hashlib.sha256(tone.read_bytes()).hexdigest()
            probe['tone_start_uptime'] = time.monotonic()
            subprocess.run(['/usr/bin/afplay', '-v', '0.5', str(tone)], check=True, timeout=15)
            probe['tone_finish_uptime'] = time.monotonic()
            # Preserve the route's actual short release before finalizing CAF.
            time.sleep(0.5)
        except BaseException as error:
            probe['status'] = 'failed'
            probe['error'] = type(error).__name__ + ': ' + str(error)
            raise
        finally:
            (output / 'stop-audio').touch()
            try:
                probe['launcher_exit_code'] = process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
                probe['launcher_stop_timeout'] = True
            probe['finished_uptime'] = time.monotonic()
            write_json(output / 'probe-receipt.json', probe)
            tcc_observations(output)
    try:
        receipt = json.loads((output / 'audio-receipt.json').read_text())
        assert receipt.get('device_uid') == 'BlackHole2ch_UID', 'Actual capture must identify the expected virtual input'
        assert receipt.get('error') is None and receipt.get('frames', 0) > 0 and receipt.get('peak', 0) > 0.001, 'Actual capture receipt is invalid/silent'
        converted = output / 'actual-loopback.wav'
        subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16', str(output / 'audio.caf'), str(converted)], check=True)
        probe['actual_pcm_analysis'] = analyze_capture(converted)
        probe['status'] = 'passed'
    except BaseException as error:
        probe['status'] = 'failed'
        probe['error'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        write_json(output / 'probe-receipt.json', probe)
    print('HOST_AUDIO_PROBE_PASS: normal macOS consent; actual BlackHole capture contains the independently played stereo tone.', flush=True)


if __name__ == '__main__':
    main()
