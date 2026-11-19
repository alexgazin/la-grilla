#!/usr/bin/env python3
"""Build 44 touch-to-sound analysis for the physical pad protocol.

Record each route with a shared time reference:
  * two synchronised channels: channel 1 = contact microphone / piezo on the
    glass (registers the finger), channel 2 = acoustic or line output; or
  * one external microphone that hears both the finger click and the sound
    (--single-mic): onsets then alternate contact, output.

    python3 scripts/device/pad_latency.py take.wav --route speaker --model "iPhone 15" \
        --ios 18.6 --rate 48000 --buffer 256 --bpm 90 --quantize 1/16 --build 44 \
        --method "piezo L + line R" --json out.json
    python3 scripts/device/pad_latency.py --compare 43.json 44.json
    python3 scripts/device/pad_latency.py --self-test

Reported per take: median, p95, spread (IQR, min/max), missed contacts
(no sound within --window) and duplicate attacks (more than one output onset
for one contact). The uncertainty combines sample period, onset-detector
resolution and the optional --calibration-ms channel skew estimate.
"""
import argparse, json, math, statistics, sys, wave
import numpy as np

def read_wav(path):
    with wave.open(path, 'rb') as w:
        rate, channels, width, frames = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(frames)
    if width == 2: data = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768
    elif width == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        v = np.where(v >= 1 << 23, v - (1 << 24), v); data = v.astype(np.float64) / (1 << 23)
    elif width == 4: data = np.frombuffer(raw, dtype='<i4').astype(np.float64) / 2**31
    else: raise SystemExit(f'unsupported sample width {width}')
    return rate, data.reshape(-1, channels).T

def onsets(signal, rate, threshold_db=-30.0, refractory_ms=35.0, hop=32, rise=2.0, lookback_ms=5.0):
    """Attack onsets from a block-peak envelope. A block starts an onset when it
    is above the level threshold (relative to the take's peak, never below the
    noise floor) and at least `rise` times louder than the envelope
    `lookback_ms` earlier, so a decaying tone does not retrigger but a second
    attack during its tail does. The onset is refined to the first sample above
    half of that block's peak."""
    x = np.abs(np.asarray(signal, dtype=np.float64))
    if x.size == 0 or x.max() <= 0: return []
    blocks = x[: x.size // hop * hop].reshape(-1, hop).max(axis=1)
    smooth = np.maximum.accumulate(np.lib.stride_tricks.sliding_window_view(np.pad(blocks, (3, 0)), 4), axis=1)[:, -1]
    level = max(x.max() * 10 ** (threshold_db / 20), float(np.median(x)) * 4)
    back = max(1, int(round(rate * lookback_ms / 1000 / hop)))
    refractory = rate * refractory_ms / 1000
    result, last = [], -math.inf
    for b in range(blocks.size):
        earlier = smooth[b - back] if b >= back else 0.0
        if blocks[b] >= level and blocks[b] >= rise * earlier and b * hop - last >= refractory:
            segment = x[b * hop:(b + 1) * hop]
            j = b * hop + int(np.argmax(segment >= blocks[b] * 0.5))
            result.append(j); last = j
    return result

def pair(contacts, outputs, rate, window_ms=400.0, duplicate_ms=120.0):
    window, dup = rate * window_ms / 1000, rate * duplicate_ms / 1000
    latencies, misses, duplicates, k = [], 0, 0, 0
    for index, c in enumerate(contacts):
        limit = contacts[index + 1] if index + 1 < len(contacts) else math.inf
        while k < len(outputs) and outputs[k] < c: k += 1
        hits = [o for o in outputs[k:] if o - c <= window and o < limit]
        if not hits: misses += 1; continue
        latencies.append((hits[0] - c) / rate * 1000)
        duplicates += sum(1 for o in hits[1:] if o - hits[0] <= dup)
    return latencies, misses, duplicates

def percentile(values, p):
    s = sorted(values)
    if not s: return None
    rank = (len(s) - 1) * p / 100; lo = math.floor(rank); hi = math.ceil(rank)
    return s[lo] + (s[hi] - s[lo]) * (rank - lo)

def summarize(latencies, misses, duplicates, contacts, rate, calibration_ms, hop=32):
    stats = {'contacts': contacts, 'measured': len(latencies), 'missed': misses, 'duplicates': duplicates}
    if latencies:
        lat = [v - calibration_ms for v in latencies]
        stats.update({'medianMs': round(statistics.median(lat), 2), 'p95Ms': round(percentile(lat, 95), 2),
                      'minMs': round(min(lat), 2), 'maxMs': round(max(lat), 2),
                      'iqrMs': round(percentile(lat, 75) - percentile(lat, 25), 2),
                      'stdevMs': round(statistics.pstdev(lat), 2)})
    # Sample period plus detector hop on each of two channels.
    stats['uncertaintyMs'] = round(math.sqrt(2 * (1000 / rate) ** 2 + 2 * (hop / rate * 1000 / math.sqrt(12)) ** 2), 2)
    return stats

def analyse(path, args):
    rate, channels = read_wav(path)
    if args.single_mic:
        all_onsets = onsets(channels[0], rate, args.threshold_db, args.refractory_ms / 3)
        contacts, outputs = all_onsets[0::2], all_onsets[1::2]
    else:
        if channels.shape[0] < 2: raise SystemExit('two channels required (or --single-mic)')
        contacts = onsets(channels[0], rate, args.threshold_db, args.refractory_ms)
        outputs = onsets(channels[1], rate, args.threshold_db, args.refractory_ms / 3)
    latencies, misses, duplicates = pair(contacts, outputs, rate, args.window_ms)
    return summarize(latencies, misses, duplicates, len(contacts), rate, args.calibration_ms)

def compare(a, b):
    rows = ['| Route | Metric | ' + a.get('build', 'A') + ' | ' + b.get('build', 'B') + ' |', '| --- | --- | --- | --- |']
    for key in ['medianMs', 'p95Ms', 'iqrMs', 'missed', 'duplicates']:
        rows.append(f"| {a.get('route','?')} | {key} | {a['stats'].get(key)} | {b['stats'].get(key)} |")
    return '\n'.join(rows)

def synth(rate=48000, latencies=None, miss_index=7, duplicate_index=11):
    latencies = latencies or [38 + 6 * math.sin(i) for i in range(32)]
    period = int(rate * 60 / 90 / 2)
    n = period * (len(latencies) + 2)
    left, right = np.zeros(n), np.zeros(n)
    rng = np.random.default_rng(4)
    left += rng.normal(0, 0.002, n); right += rng.normal(0, 0.002, n)
    click = np.exp(-np.arange(200) / 30) * np.sin(np.arange(200) * 0.9)
    hit = np.exp(-np.arange(4000) / 900) * np.sin(np.arange(4000) * 0.11)
    for i, ms in enumerate(latencies):
        c = period * (i + 1); left[c:c + 200] += 0.6 * click
        if i == miss_index: continue
        o = c + int(round(ms * rate / 1000)); right[o:o + 4000] += 0.7 * hit
        if i == duplicate_index: right[o + 2400:o + 6400] += 0.7 * hit
    return rate, left, right, latencies

def self_test():
    rate, left, right, truth = synth()
    contacts = onsets(left, rate); outputs = onsets(right, rate, refractory_ms=12)
    latencies, misses, duplicates = pair(contacts, outputs, rate)
    stats = summarize(latencies, misses, duplicates, len(contacts), rate, 0)
    expected = [v for i, v in enumerate(truth) if i != 7]
    assert stats['contacts'] == 32, stats
    assert stats['missed'] == 1 and stats['duplicates'] == 1, stats
    assert abs(stats['medianMs'] - statistics.median(expected)) < 1.0, stats
    assert abs(stats['p95Ms'] - percentile(expected, 95)) < 1.0, stats
    print('pad_latency self-test passed:', json.dumps(stats))

def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('wav', nargs='?'); p.add_argument('--self-test', action='store_true')
    p.add_argument('--compare', nargs=2, metavar=('A', 'B'))
    p.add_argument('--single-mic', action='store_true')
    p.add_argument('--threshold-db', type=float, default=-30); p.add_argument('--refractory-ms', type=float, default=35)
    p.add_argument('--window-ms', type=float, default=400); p.add_argument('--calibration-ms', type=float, default=0)
    for key in ['route', 'model', 'ios', 'rate', 'buffer', 'bpm', 'quantize', 'build', 'method', 'recording']:
        p.add_argument('--' + key)
    p.add_argument('--json')
    args = p.parse_args()
    if args.self_test: self_test(); return
    if args.compare:
        a, b = (json.load(open(x)) for x in args.compare); print(compare(a, b)); return
    if not args.wav: p.error('wav required')
    result = {k: getattr(args, k) for k in ['route', 'model', 'ios', 'rate', 'buffer', 'bpm', 'quantize', 'build', 'method', 'recording']}
    result['source'] = args.wav; result['stats'] = analyse(args.wav, args)
    text = json.dumps(result, indent=2, ensure_ascii=False); print(text)
    if args.json: open(args.json, 'w').write(text + '\n')

if __name__ == '__main__':
    main()
