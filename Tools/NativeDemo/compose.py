#!/usr/bin/env python3
"""Compose a real-session showcase; the app display and recorded PCM stay real."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from ci.native_scope import observed_outcomes

LEGACY_SOURCE_SHA = 'b4a584fc1cc60d73a97386986c2330ca7e45980c'
LEGACY_RUN_ID = 43813957218
LEGACY_METHODS = [
    'test01ComposeJamAndMix',
    'test02HarmonyCommandsAndVoiceSetup',
    'test03PerformAndExport',
]
EXPECTED_METHODS = LEGACY_METHODS + ['test04EmptyLocalSketchAndTranspose']
PROTOCOL_CASE = re.compile(
    r"^[ \t]*Test Case '-\[[^\s\]]+ [^\]\s]+\]' "
    r'(?:passed|failed|skipped|exceeded execution time allowance)\b')
FONT_DIR = Path('/usr/share/fonts/truetype/noto')


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text())


def demo_outcomes(output: str):
    """Parse actual protocol fragments; quoted examples cannot create passes."""
    fragments = [match.group(0) for line in output.splitlines()
                 if (match := PROTOCOL_CASE.match(line))]
    # The shared parser keeps allowance failures sticky even after a late PASS.
    return observed_outcomes('\n'.join(fragments))


def capture_contract(timing, edl, timing_path: Path, allow_uncovered_postroll: bool):
    """Bind a cut list to its actual source, preserving one historical replay."""
    source_sha = timing.get('source_sha')
    if not isinstance(source_sha, str) or not re.fullmatch(r'[0-9a-f]{40}', source_sha):
        raise ValueError('The actual capture source SHA is missing or invalid')
    if edl.get('source_sha') != source_sha:
        raise ValueError('EDL source_sha must match the actual capture source SHA')
    legacy = source_sha == LEGACY_SOURCE_SHA
    expected = LEGACY_METHODS if legacy else EXPECTED_METHODS
    if (timing.get('test_exit_code') != 0
            or timing.get('expected_methods') != expected
            or timing.get('actual_passed_methods') != expected):
        raise ValueError(f'All {len(expected)} real UI journeys must have executed and passed')
    if allow_uncovered_postroll and (not legacy or edl.get('source_run_id') != LEGACY_RUN_ID):
        raise ValueError('Unused-postroll qualification is restricted to the original build-15 capture run')
    log_path = timing_path.parent / 'demo-tests.log'
    if not log_path.is_file():
        raise ValueError('The original demo-tests.log is required to verify actual XCTest outcomes')
    outcomes = demo_outcomes(log_path.read_text())
    required = {f'NativeDemoTests/{method}': outcomes.get(f'NativeDemoTests/{method}', 'unobserved')
                for method in expected}
    if any(outcome != 'passed' for outcome in required.values()):
        raise ValueError('Original demo log must show every real UI journey passing without an allowance failure')
    log_sha = digest(log_path)
    common = dict(expected_methods=expected, session_count=len(expected),
                  demo_tests_log_path=log_path, demo_tests_log_sha256=log_sha,
                  required_test_outcomes=required)
    if legacy:
        return dict(source_receipt=None, source_receipt_path=None,
                    app=dict(version='1.0.0', build='15', bundle_id='com.alexgazin.LaGrilla'),
                    **common)
    if timing.get('demo_tests_log_sha256') != log_sha:
        raise ValueError('Original demo log bytes differ from the capture timing hash')
    if timing.get('required_test_outcomes') != required:
        raise ValueError('Capture timing outcomes differ from the independently parsed original demo log')
    source_path = timing_path.parent / 'source-receipt.json'
    if not source_path.is_file():
        raise ValueError('A schema-2 actual capture requires its original source-receipt.json')
    source = read_json(source_path)
    if (timing.get('capture_schema') != 2 or source.get('capture_schema') != 2
            or source.get('source_sha') != source_sha or source.get('git_head') != source_sha):
        raise ValueError('Source receipt schema and Git HEAD must match the actual capture')
    if timing.get('source_receipt_sha256') != digest(source_path):
        raise ValueError('Source receipt bytes differ from the original capture timing hash')
    app = source.get('app')
    if (not isinstance(app, dict)
            or any(not isinstance(app.get(key), (str, int)) or isinstance(app.get(key), bool)
                   or not str(app[key]).strip() for key in ['version', 'build', 'bundle_id'])):
        raise ValueError('The actual built app version, build and bundle ID are required')
    files = source.get('files')
    if (not isinstance(files, dict) or not files
            or any(not isinstance(path, str) or not path
                   or not isinstance(entry, dict)
                   or not isinstance(entry.get('sha256'), str)
                   or not re.fullmatch(r'[0-9a-f]{64}', entry['sha256'])
                   for path, entry in files.items())):
        raise ValueError('The original source receipt must retain its source-file SHA-256 inventory')
    return dict(source_receipt=source, source_receipt_path=source_path,
                app=app, **common)


def probe(path: Path, count_frames: bool = False):
    command = ['ffprobe', '-v', 'error']
    if count_frames:
        command.append('-count_frames')
    return json.loads(subprocess.check_output(command + [
        '-show_streams', '-show_format', '-of', 'json', str(path)
    ]))


def number(value, name: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f'{name} must be finite')
    return result


def decode_pcm(path: Path, channels: int):
    """Inspect every actual sample; neither silence nor gaps are synthesized."""
    command = ['ffmpeg', '-v', 'error', '-i', str(path), '-map', '0:a:0',
               '-f', 'f32le', '-acodec', 'pcm_f32le', '-']
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    count, square_sum, peak = 0, 0.0, 0.0
    try:
        assert process.stdout is not None
        while data := process.stdout.read(262144):
            if len(data) % 4:
                raise ValueError('The decoded Float32 stream has a partial sample')
            values = np.frombuffer(data, dtype='<f4')
            if not np.isfinite(values).all():
                raise ValueError('The recorded audio contains nonfinite samples')
            count += len(values)
            peak = max(peak, float(np.max(np.abs(values))))
            square_sum += float(np.sum(values.astype(np.float64) ** 2))
        if process.wait() != 0:
            raise ValueError('Complete decoding of the recorded audio failed')
    except BaseException:
        process.kill(); process.wait(); raise
    if count == 0 or count % channels:
        raise ValueError('Empty or incomplete recorded stereo PCM')
    return dict(frames=count // channels, samples=count, peak=peak,
                rms=math.sqrt(square_sum / count))


def ffpath(path: Path) -> str:
    return str(path).replace('\\', '\\\\').replace(':', '\\:').replace("'", "\\'")


def draw_text(text: str, name: str, folder: Path, font: Path, size: int,
              x: int, y: int, color: str, fade: bool = False) -> str:
    path = folder / f'{name}.txt'
    path.write_text(text)
    result = (f"drawtext=fontfile='{ffpath(font)}':textfile='{ffpath(path)}':"
              f'fontsize={size}:fontcolor={color}:x={x}:y={y}:line_spacing=14')
    if fade:
        result += ":alpha='min(1,t/0.4)'"
    return result


def validate(args):
    args.sync_adjust_ms = number(args.sync_adjust_ms, 'sync adjustment')
    args.gain_db = number(args.gain_db, 'presentation gain')
    if args.video_host_start is not None:
        args.video_host_start = number(args.video_host_start, 'explicit video host start')
    timing, audio_receipt, edl = map(read_json, [args.timing, args.audio_receipt, args.edl])
    contract = capture_contract(timing, edl, args.timing, args.allow_uncovered_postroll)
    if timing.get('video_error'):
        raise ValueError(f"The native recorder reported {timing['video_error']}")
    if timing.get('video_exit_code') not in (0, 130, -2):
        raise ValueError('The native recorder did not finish normally after SIGINT')
    if audio_receipt.get('error') or audio_receipt.get('sample_time_discontinuities') != 0:
        raise ValueError('Recorded audio has an error or sample-time discontinuity')
    if audio_receipt.get('device_uid') != 'BlackHole2ch_UID':
        raise ValueError('The source is not the declared actual BlackHole capture')
    if audio_receipt.get('offline_audio_substitution') is not False:
        raise ValueError('An actual-session audio receipt is required')
    video, audio = probe(args.video), probe(args.audio)
    streams = [s for s in video['streams'] if s['codec_type'] == 'video']
    audio_streams = [s for s in audio['streams'] if s['codec_type'] == 'audio']
    if len(streams) != 1 or len(audio_streams) != 1:
        raise ValueError('Require one actual video stream and one actual audio stream')
    v, a = streams[0], audio_streams[0]
    if not 0 < v['width'] < v['height'] or a['channels'] != 2:
        raise ValueError('Require the full portrait display and true stereo audio')
    rate = int(a['sample_rate'])
    if not 8000 <= rate <= 192000 or rate != audio_receipt['sample_rate']:
        raise ValueError('Invalid or inconsistent actual PCM sample rate')
    pcm = decode_pcm(args.audio, 2)
    if pcm['frames'] != audio_receipt['frames']:
        raise ValueError('Decoded CAF frame count differs from the capture receipt')
    if pcm['peak'] <= .001 or pcm['rms'] <= .00001 or pcm['peak'] >= 1:
        raise ValueError('Recorded PCM is silent or clipped')
    if abs(pcm['peak'] - audio_receipt['peak']) > 0.000001:
        raise ValueError('Decoded PCM peak differs from the capture receipt')
    first_host = number(audio_receipt['first_host_seconds'], 'first audio host timestamp')
    last_host = number(audio_receipt['last_host_seconds'], 'last audio host timestamp')
    last_frames = pcm['frames'] - (int(audio_receipt['last_sample_time']) - int(audio_receipt['first_sample_time']))
    if not 0 < last_frames <= 65536:
        raise ValueError('Invalid final buffer extent or missing sample-time coverage')
    audio_duration = pcm['frames'] / rate
    host_duration = last_host - first_host + last_frames / rate
    if abs(audio_duration - host_duration) > max(.05, audio_duration * .0005):
        raise ValueError('Actual PCM duration and host timestamp span disagree')
    lower = number(timing['video_spawn_before_uptime'], 'video start lower bound')
    upper = number(timing['video_recording_started_notice_uptime'], 'video start upper bound')
    if not lower <= upper or (upper - lower > 2 and args.video_host_start is None):
        raise ValueError('The screen recording start is not sufficiently bounded')
    video_start = (lower + upper) / 2
    if args.video_host_start is not None:
        video_start = args.video_host_start
        if not lower <= video_start <= upper:
            raise ValueError('The explicit video host start lies outside its measured bracket')
        if not args.sync_note.strip():
            raise ValueError('An explicit host start requires a verification note')
    if args.sync_adjust_ms and not args.sync_note:
        raise ValueError('A nonzero sync adjustment requires an explicit verification note')
    if abs(args.sync_adjust_ms) > 500:
        raise ValueError('Sync adjustment exceeds the 500 ms review limit')
    offset = video_start - first_host + args.sync_adjust_ms / 1000
    video_duration = number(video['format']['duration'], 'video duration')
    expected_span = number(timing['video_stop_signal_uptime'], 'video stop time') - video_start
    audio_end_host = first_host + audio_duration
    if first_host > video_start + 1 / rate:
        raise ValueError('Actual audio must begin before the first native video frame')
    qualification = None
    if args.allow_uncovered_postroll:
        if not args.postroll_note.strip() or args.video_host_start is None or not args.sync_note.strip():
            raise ValueError('Qualified postroll requires manual host start, sync note and postroll note')
        original_conclusion = edl.get('source_run_conclusion', '')
        if not original_conclusion.lower().startswith(('failure', 'failed')):
            raise ValueError('The original failed capture job must remain explicitly recorded in the EDL')
        events_path = args.events_log or args.timing.parent / 'demo-tests.log'
        events = []
        for line in events_path.read_text().splitlines():
            if 'NATIVE_DEMO_EVENT ' in line:
                event = json.JSONDecoder().raw_decode(line.split('NATIVE_DEMO_EVENT ', 1)[1].strip())[0]
                event['uptime_seconds'] = number(event['uptime_seconds'], 'authored event host time')
                events.append(event)
        if len(events) < 29 or sum(e['phase'] == 'app.ready' for e in events) != 3:
            raise ValueError('All three authored journeys and their action markers are required')
        if events[-1]['phase'] != 'export.actual-share-sheet':
            raise ValueError('The final authored WAV share-sheet event is missing')
        if any(e['uptime_seconds'] < first_host or e['uptime_seconds'] > audio_end_host for e in events):
            raise ValueError('Actual PCM does not cover every authored action marker')
        if events[-1]['uptime_seconds'] + 3 > audio_end_host:
            raise ValueError('The final authored UI event needs three seconds of captured audio after it')
        if any(e['uptime_seconds'] < video_start or e['uptime_seconds'] > video_start + video_duration for e in events):
            raise ValueError('An authored action marker lies outside the calibrated native video span')
        qualification = dict(
            accepted_scope='Actual selected video/PCM and all authored UI actions; original capture job remains failed',
            original_capture_job_conclusion=original_conclusion,
            original_capture_run_id=edl.get('source_run_id'), note=args.postroll_note,
            event_log_sha256=digest(events_path), authored_event_count=len(events), authored_events=events,
            first_authored_event_host=events[0]['uptime_seconds'], last_authored_event_host=events[-1]['uptime_seconds'],
            authored_ui_guard_end_host=events[-1]['uptime_seconds'] + 3,
            actual_video_media_end_host=video_start + video_duration,
            entire_actual_video_pts_audio_covered=video_start + video_duration <= audio_end_host,
            audio_end_host=audio_end_host,
            wall_stop_without_pcm_seconds=max(0, timing['video_stop_signal_uptime'] - audio_end_host),
            wall_stop_after_last_encoded_video_pts_seconds=timing['video_stop_signal_uptime'] - video_start - video_duration,
            video_duration_was_not_rescaled=True)
    elif abs(video_duration - expected_span) > .75 or audio_end_host < timing['video_stop_signal_uptime'] - .5:
        raise ValueError('Native MP4 duration does not match the screen recorder host interval')
    blocks = edl.get('blocks')
    if blocks is not None:
        if not isinstance(blocks, list) or not 1 <= len(blocks) <= 30:
            raise ValueError('EDL needs 1–30 parent blocks')
        chapters = []
        for parent_index, block in enumerate(blocks):
            for local_index, clip in enumerate(block['clips']):
                if clip.get('speed', 1) != 1:
                    raise ValueError('App actions cannot be retimed')
                chapters.append(dict(start=clip['source_start'], end=clip['source_end'],
                    label=block.get('label', block['id'].upper()), title=block['title'],
                    subtitle=block.get('caption', ''), color=block.get('color', '#d9fa7b'),
                    parent_index=parent_index, parent_count=len(blocks), parent_id=block['id'],
                    first_in_parent=local_index == 0))
        parent_count = len(blocks)
    else:
        chapters = edl.get('chapters')
        parent_count = len(chapters) if isinstance(chapters, list) else 0
    if not isinstance(chapters, list) or not 1 <= len(chapters) <= 150:
        raise ValueError('EDL needs 1–150 explicit source clips')
    previous_end = 0.0
    for index, chapter in enumerate(chapters):
        start, end = number(chapter['start'], 'clip start'), number(chapter['end'], 'clip end')
        if not 0 <= start < end <= video_duration or end - start < .25:
            raise ValueError(f'Invalid or overflowing EDL clip {index + 1}')
        if start < previous_end:
            raise ValueError('EDL must preserve chronological actions without overlapping or repeating clips')
        if offset + start < 0 or offset + end > audio_duration:
            raise ValueError(f'Actual source PCM does not cover clip {index + 1}')
        previous_end = end
        title = chapter['title']
        if isinstance(title, list):
            title = '\n'.join(title)
        if not isinstance(title, str) or not 1 <= len(title.splitlines()) <= 2:
            raise ValueError('Each chapter title needs one or two authored lines')
        chapter['title'] = title
        if len(chapter.get('subtitle', '').splitlines()) > 3:
            raise ValueError('Subtitle needs at most three lines')
        color = chapter.get('color', '#d9fa7b')
        if not re.fullmatch(r'#[A-Fa-f0-9]{6}', color):
            raise ValueError('Chapter accent must be an RGB hex color')
        # Shrink each selection to the common delivery grid. Extending a
        # duration by rounding could repeat a neighboring chapter's action.
        first_frame = math.ceil(start * 30 - 1e-8)
        end_frame = math.floor(end * 30 + 1e-8)
        if end_frame <= first_frame:
            raise ValueError('The selected clip contains no complete delivery frame')
        chapter['authored_start'], chapter['authored_end'] = start, end
        chapter['start'], chapter['end'] = first_frame / 30, end_frame / 30
    output_cursor = 0.0
    for index, chapter in enumerate(chapters):
        chapter.setdefault('parent_index', index)
        chapter.setdefault('parent_count', parent_count)
        chapter.setdefault('first_in_parent', True)
        chapter['output_start'] = output_cursor
        output_cursor += chapter['end'] - chapter['start']
        chapter['output_end'] = output_cursor
        siblings = [c for c in chapters if c.get('parent_index', chapters.index(c)) == chapter['parent_index']]
        chapter['parent_duration'] = sum(c['end'] - c['start'] for c in siblings)
        chapter['parent_elapsed_before'] = sum(c['end'] - c['start'] for c in siblings[:siblings.index(chapter)])
    gain = 10 ** (args.gain_db / 20)
    if not -24 <= args.gain_db <= 24 or pcm['peak'] * gain > .98:
        raise ValueError('Presentation gain would exceed the headroom limit')
    return dict(timing=timing, audio_receipt=audio_receipt, edl=edl, chapters=chapters,
                **contract,
                pcm=pcm, sample_rate=rate, source_video=v, source_duration=video_duration,
                audio_duration=audio_duration, audio_offset_seconds=offset,
                video_host_start_estimate=video_start,
                video_host_start_bracket=[lower, upper], last_buffer_frames=last_frames,
                host_audio_duration=host_duration, postroll_qualification=qualification,
                parent_count=parent_count)


def render_segment(args, state, chapter, index, folder):
    duration = chapter['end'] - chapter['start']
    # validate() already quantized both source boundaries inward. No action
    # runs faster or slower inside the selected source interval.
    frames = max(1, round(duration * 30))
    duration = frames / 30
    if state['audio_offset_seconds'] + chapter['start'] + duration > state['audio_duration']:
        raise ValueError('Frame-rounded clip exceeds actual recorded PCM coverage')
    if chapter['start'] + duration > state['source_duration']:
        raise ValueError('Frame-rounded clip exceeds actual native video coverage')
    accent = '0x' + chapter.get('color', '#d9fa7b')[1:]
    parent_index = chapter.get('parent_index', index)
    parent_count = chapter.get('parent_count', len(state['chapters']))
    entry_fade = chapter.get('first_in_parent', True)
    segment_dir = folder / f'{index:02d}'
    segment_dir.mkdir()
    texts = [
        draw_text('LA GRILLA', 'brand', segment_dir, args.bold_font, 28, 96, 60, '0xf3f3e9'),
        draw_text('В РАБОТЕ', 'working', segment_dir, args.regular_font, 17, 293, 70, accent),
        draw_text(f'{parent_index + 1:02d}  /  {parent_count:02d}   ' + chapter.get('label', ''), 'label', segment_dir, args.bold_font, 22, 100, 220, accent, entry_fade),
        draw_text(chapter['title'], 'title', segment_dir, args.bold_font, 80, 96, 297, '0xf3f3e9', entry_fade),
        draw_text(chapter.get('subtitle', ''), 'subtitle', segment_dir, args.regular_font, 29, 102, 536, '0xaab2a5', entry_fade),
        draw_text('Звук этой записи', 'audio', segment_dir, args.regular_font, 19, 102, 877, '0xaab2a5'),
        draw_text(f'iOS Simulator · {state["app"]["version"]} ({state["app"]["build"]})', 'device', segment_dir, args.regular_font, 18, 96, 1036, '0xaab2a5'),
        draw_text(f'{state["session_count"]} реальные сессии · Паузы сокращены монтажом', 'editing', segment_dir, args.regular_font, 17, 1190, 1036, '0xaab2a5'),
    ]
    screen_height = 948
    screen_width = round(state['source_video']['width'] / state['source_video']['height'] * screen_height / 2) * 2
    background = (f'color=c=0x0b100d:s=1920x1080:r=30:d={duration:.9f},format=rgba,'
                  'drawgrid=w=96:h=96:t=1:c=0xd9fa7b@0.035,'
                  f'drawbox=x=1274:y=58:w={screen_width + 12}:h=960:c=0x25311f:t=fill,'
                  f'drawbox=x=102:y=675:w=850:h=2:c={accent}@0.25')
    for line in texts:
        background += ',' + line
    step = 1728 / parent_count
    for item in range(parent_count):
        color = '0x657249' if item < parent_index else '0x303c2a'
        background += f',drawbox=x={96 + item * step:.3f}:y=1067:w={step - 10:.3f}:h=3:c={color}:t=fill'
    fade_out = max(0, duration - .015)
    bar_width = int(step - 10)
    bar_offset = chapter.get('parent_elapsed_before', 0)
    bar_duration = chapter.get('parent_duration', duration)
    filters = [
        # Retain the last actual display state through a cut in VFR idle gaps;
        # shifting the first post-seek frame to zero would show future UI early.
        f'[0:v]fps=30:start_time=0:round=up,trim=duration={duration:.9f},setpts=PTS-STARTPTS,scale={screen_width}:{screen_height}:flags=lanczos,setsar=1,format=rgba[screen]',
        background + '[background]',
        '[background][screen]overlay=x=1280:y=64:shortest=1:format=rgb[display]',
        (f'[1:a]atrim=duration={duration:.9f},asetpts=PTS-STARTPTS,aresample=48000:async=0,'
         f'volume={args.gain_db:.6f}dB,afade=t=in:d=0.015,afade=t=out:st={fade_out:.9f}:d=0.015,'
         'asplit=2[sound][meter]'),
        f'[meter]showwaves=s=852x80:mode=cline:rate=30:colors={accent}:scale=sqrt[wave]',
        '[display][wave]overlay=x=102:y=773:shortest=1:format=rgb[displaywave]',
        f'color=c=0x303c2a:s={bar_width}x4:r=30:d={duration:.9f},format=rgba[barbackground]',
        f'color=c={accent}:s={bar_width}x4:r=30:d={duration:.9f},format=rgba[barfill]',
        f"[barbackground][barfill]overlay=x='-{bar_width}+{bar_width}*min(1,(t+{bar_offset:.9f})/{bar_duration:.9f})':y=0:shortest=1:format=rgb[bar]",
        f'[displaywave][bar]overlay=x={96 + parent_index * step:.3f}:y=1067:shortest=1:format=rgb,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[video]',
    ]
    script = segment_dir / 'filter.txt'
    script.write_text(';\n'.join(filters))
    output = folder / f'segment-{index:02d}.mkv'
    command = ['ffmpeg', '-nostdin', '-v', 'warning', '-y', '-noaccurate_seek', '-ss', f'{chapter["start"]:.9f}',
               '-i', str(state.get('render_video', args.video)), '-ss', f'{state["audio_offset_seconds"] + chapter["start"]:.9f}',
               '-i', str(args.audio), '-filter_complex_script', str(script), '-map', '[video]', '-map', '[sound]',
               '-frames:v', str(frames), '-t', f'{duration:.9f}', '-c:v', 'libx264', '-preset', args.preset,
               '-crf', '19', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-colorspace', 'bt709',
               '-color_primaries', 'bt709', '-color_trc', 'bt709', '-c:a', 'pcm_f32le',
               '-ar', '48000', '-ac', '2', str(output)]
    print(f'Chapter {index + 1}/{len(state["chapters"])}: {chapter.get("label", "")} ({duration:.2f}s)', flush=True)
    subprocess.run(command, check=True)
    segment_pcm = decode_pcm(output, 2)
    if segment_pcm['frames'] != frames * 1600:
        raise ValueError('An intermediate sound stream does not completely cover its video frames')
    chapter.update(rendered_video_frames=frames, rendered_audio_frames=segment_pcm['frames'],
                   rendered_duration_seconds=duration)
    return output, frames, duration


def normalize_video(args, state, folder):
    """Sample the complete original VFR clock once before any editorial cuts."""
    path = folder / 'source-cfr-lossless.mp4'
    print('Normalizing the full actual VFR display once; no speed change or optical flow.', flush=True)
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'warning', '-y', '-i', str(args.video),
                    '-map', '0:v:0', '-an', '-vf',
                    'fps=30:start_time=0:round=up,scale=-2:948:flags=lanczos:out_color_matrix=bt709:out_range=tv,setsar=1,format=yuv444p',
                    '-c:v', 'libx264', '-preset', 'ultrafast', '-qp', '0', '-pix_fmt', 'yuv444p',
                    '-color_range', 'tv', '-colorspace', 'bt709', '-video_track_timescale', '30000', str(path)], check=True)
    metadata = probe(path, count_frames=True)
    stream = next(s for s in metadata['streams'] if s['codec_type'] == 'video')
    if stream['r_frame_rate'] != '30/1' or stream['height'] != 948:
        raise ValueError('The full VFR normalization did not retain its declared delivery clock')
    state['render_video'] = path
    return dict(kind='Ephemeral full-source CFR sampling; held original UI frames, no generated UI or optical flow',
                codec='Lossless H.264 QP0 yuv444p, after the single proportional phone-size rescale',
                frames=int(stream['nb_read_frames']), width=stream['width'], height=stream['height'],
                original_duration_seconds=state['source_duration'],
                normalized_duration_seconds=float(metadata['format']['duration']),
                source_pts_not_time_rescaled=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['video', 'audio', 'timing', 'audio-receipt', 'edl', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--regular-font', type=Path, default=FONT_DIR / 'NotoSans-Regular.ttf')
    parser.add_argument('--bold-font', type=Path, default=FONT_DIR / 'NotoSans-Bold.ttf')
    parser.add_argument('--video-host-start', type=float)
    parser.add_argument('--sync-adjust-ms', type=float, default=0)
    parser.add_argument('--sync-note', default='')
    parser.add_argument('--allow-uncovered-postroll', action='store_true')
    parser.add_argument('--postroll-note', default='')
    parser.add_argument('--events-log', type=Path)
    parser.add_argument('--gain-db', type=float, default=0)
    parser.add_argument('--preset', choices=['fast', 'medium', 'slow'], default='medium')
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    args.video, args.audio, args.output = args.video.resolve(), args.audio.resolve(), args.output.resolve()
    destinations = [args.output, args.output.with_suffix('.render-receipt.json')]
    source_path = args.timing.parent / 'source-receipt.json'
    input_paths = [args.video, args.audio, args.timing, args.audio_receipt, args.edl,
                   args.regular_font, args.bold_font, args.timing.parent / 'demo-tests.log']
    if source_path.is_file():
        input_paths.append(source_path)
    for path in input_paths:
        if not path.is_file():
            parser.error(f'Missing input: {path}')
        if path.resolve() in destinations:
            parser.error('Output must not overwrite an input')
    for tool in ['ffmpeg', 'ffprobe']:
        if not shutil.which(tool):
            parser.error(f'{tool} is required')
    state = validate(args)
    inputs = {name: {'path': str(path), 'sha256': digest(path)} for name, path in [
        ('video', args.video), ('audio', args.audio), ('timing', args.timing),
        ('audio_receipt', args.audio_receipt), ('edl', args.edl)]}
    if state['source_receipt_path'] is not None:
        inputs['source_receipt'] = dict(path=str(state['source_receipt_path']),
                                       sha256=digest(state['source_receipt_path']))
    inputs['demo_tests_log'] = dict(path=str(state['demo_tests_log_path']),
                                    sha256=state['demo_tests_log_sha256'])
    receipt = dict(kind='Edited real iOS Simulator sessions with their actual host-loopback sound',
                   inputs=inputs, source_sha=state['timing'].get('source_sha'),
                   app=state['app'], session_count=state['session_count'],
                   expected_methods=state['expected_methods'],
                   actual_passed_methods=state['timing']['actual_passed_methods'],
                   required_test_outcomes=state['required_test_outcomes'],
                   source_receipt=state['source_receipt'],
                   audio_offset_seconds=state['audio_offset_seconds'],
                   video_host_start_estimate=state['video_host_start_estimate'],
                   video_host_start_bracket=state['video_host_start_bracket'],
                   sync_adjustment_ms=args.sync_adjust_ms, sync_verification_note=args.sync_note,
                   sample_time_discontinuities=0, decoded_pcm=state['pcm'],
                   gain_db=args.gain_db, boundary_fade_seconds=.015,
                   physical_device=False, offline_audio_substitution=False,
                   action_speed_changed=False, pauses_shortened_by_explicit_cuts=True,
                   chapters=state['chapters'])
    receipt['postroll_qualification'] = state['postroll_qualification']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.validate_only:
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
        return
    with tempfile.TemporaryDirectory(prefix='grilla-native-compose-') as temporary:
        folder = Path(temporary)
        receipt['ephemeral_source_normalization'] = normalize_video(args, state, folder)
        segments = [render_segment(args, state, chapter, index, folder)
                    for index, chapter in enumerate(state['chapters'])]
        concat = folder / 'segments.txt'
        concat.write_text(''.join(f"file '{path}'\n" for path, _, _ in segments))
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'warning', '-y', '-f', 'concat', '-safe', '0',
                        '-i', str(concat), '-map', '0:v:0', '-map', '0:a:0', '-c:v', 'copy',
                        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart',
                        '-metadata', 'title=La Grilla — В работе', '-metadata',
                        'comment=Actual iOS Simulator UI sessions and actual host-loopback audio. Pauses shortened by disclosed cuts.',
                        str(args.output)], check=True)
    final = probe(args.output, count_frames=True)
    total_frames = sum(frames for _, frames, _ in segments)
    expected_duration = total_frames / 30
    final_video = next(stream for stream in final['streams'] if stream['codec_type'] == 'video')
    if (int(final_video['nb_read_frames']) != total_frames
            or (final_video['width'], final_video['height'], final_video['pix_fmt']) != (1920, 1080, 'yuv420p')):
        raise ValueError('The final video frame count, dimensions or pixel format is invalid')
    if abs(float(final['format']['duration']) - expected_duration) > .15:
        raise ValueError('The final movie duration differs from the declared EDL')
    final_audio = next(stream for stream in final['streams'] if stream['codec_type'] == 'audio')
    if (final_audio['codec_name'] != 'aac' or final_audio['channels'] != 2
            or int(final_audio['sample_rate']) != 48000
            or abs(float(final_audio.get('start_time', 0))) > 1 / 48000
            or abs(float(final_audio['duration']) - expected_duration) > .025):
        raise ValueError('The final AAC format or timeline does not cover the complete movie')
    final_pcm = decode_pcm(args.output, 2)
    if abs(final_pcm['frames'] - total_frames * 1600) > 1024:
        raise ValueError('The final decoded sound length exceeds one AAC-frame tolerance')
    if final_pcm['peak'] >= 1 or final_pcm['peak'] <= .001 or final_pcm['rms'] <= .00001:
        raise ValueError('The final decoded AAC is clipped or silent')
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', str(args.output), '-f', 'null', '-'], check=True)
    receipt.update(output=dict(path=str(args.output), bytes=args.output.stat().st_size,
                              sha256=digest(args.output), duration_seconds=expected_duration,
                              video_frames=total_frames, full_decode_passed=True,
                              decoded_aac=final_pcm, ffprobe=final), fonts={str(p): digest(p) for p in [args.regular_font, args.bold_font]})
    output_receipt = args.output.with_suffix('.render-receipt.json')
    output_receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(f'Written {args.output} and {output_receipt}', flush=True)


if __name__ == '__main__':
    main()
