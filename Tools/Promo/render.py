#!/usr/bin/env python3
"""Deterministic real-screen motion showcase. No screenshot files are rewritten."""
import argparse
import json
import mimetypes
import pathlib
import shutil
import subprocess
import urllib.parse
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONT_ROOT = pathlib.Path('/usr/share/fonts/truetype/noto')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--audio', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--preview', type=float, help='Write one PNG at this time instead of video')
    parser.add_argument('--previews', action='store_true', help='Write chapter and transition PNGs into output directory')
    parser.add_argument('--fps', type=int, default=30)
    parser.add_argument('--regular-font', type=pathlib.Path, default=FONT_ROOT/'NotoSans-Regular.ttf')
    parser.add_argument('--bold-font', type=pathlib.Path, default=FONT_ROOT/'NotoSans-Bold.ttf')
    args = parser.parse_args()
    if not 1 <= args.fps <= 60:
        parser.error('--fps must be between 1 and 60')
    if args.output.resolve() == args.audio.resolve():
        parser.error('Output must differ from audio input')
    for path in (args.audio, args.regular_font, args.bold_font):
        if not path.is_file():
            parser.error(f'Missing input: {path}')
    # Actual soundtrack RMS drives the small waveform, never an app UI control.
    raw = subprocess.check_output(['ffmpeg','-v','error','-i',str(args.audio),'-f','f32le','-ac','1','-ar','48000','-'])
    import numpy as np
    samples = np.frombuffer(raw, dtype='<f4')
    chunks = [samples[i:i+1600] for i in range(0,len(samples),1600)]
    rms = np.array([float(np.sqrt(np.mean(c*c))) for c in chunks])
    envelope = json.dumps((rms / max(float(rms.max()),1e-9)).round(5).tolist()).encode()
    def local_asset(route):
        path = urllib.parse.urlsplit(route.request.url).path
        special = {'/__fonts/regular.ttf':args.regular_font,'/__fonts/bold.ttf':args.bold_font}
        if path == '/__envelope.json':
            route.fulfill(body=envelope,content_type='application/json')
            return
        file = special.get(path) or (ROOT/path.lstrip('/')).resolve()
        if path not in special and not file.is_relative_to(ROOT):
            route.abort();return
        route.fulfill(path=str(file),content_type=mimetypes.guess_type(str(file))[0] or 'application/octet-stream')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=shutil.which('chromium'),args=['--no-sandbox'])
        page = browser.new_page(viewport={'width':1920,'height':1080},device_scale_factor=1)
        page.route('**/*', lambda route: local_asset(route) if urllib.parse.urlsplit(route.request.url).netloc == 'promo.local' else route.abort())
        page.goto('http://promo.local/Tools/Promo/scene.html')
        page.evaluate('window.ready')
        if args.previews:
            args.output.mkdir(parents=True,exist_ok=True)
            times = [2,8,16,24,32,40,48,56,64,72,80,88,94,3.9,4.1,51.9,52.1,91.9,92.1]
            for t in times:
                page.evaluate('t => window.render(t)', t)
                page.screenshot(path=str(args.output/f'{t:05.1f}.png'))
            print(f'Previews: {args.output}',flush=True)
        elif args.preview is not None:
            page.evaluate('t => window.render(t)', args.preview)
            page.screenshot(path=str(args.output))
            print(f'Preview: {args.output}',flush=True)
        else:
            command = ['ffmpeg','-v','warning','-y','-f','image2pipe','-vcodec','mjpeg','-framerate',str(args.fps),'-i','-','-i',str(args.audio),'-map','0:v','-map','1:a','-c:v','libx264','-preset','medium','-crf','22','-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:a','aac','-b:a','192k','-t','96','-movflags','+faststart','-metadata','title=La Grilla — Idea. Groove. Track.','-metadata','comment=Motion showcase composed from authentic app screenshots; original soundtrack rendered by La Grilla AudioDSP.',str(args.output)]
            encoder = subprocess.Popen(command,stdin=subprocess.PIPE)
            try:
                for frame in range(96*args.fps):
                    page.evaluate('t => window.render(t)', frame/args.fps)
                    encoder.stdin.write(page.screenshot(type='jpeg',quality=94))
                    if frame % (8*args.fps) == 0:
                        print(f'Rendered {frame/args.fps:02.0f}/96 seconds',flush=True)
                encoder.stdin.close()
                if encoder.wait() != 0:
                    raise RuntimeError('ffmpeg failed')
            except BaseException:
                encoder.kill();encoder.wait();raise
            print(f'Video: {args.output}',flush=True)
        browser.close()

if __name__ == '__main__':
    main()
