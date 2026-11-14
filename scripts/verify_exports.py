#!/usr/bin/env python3
"""Read real Swift/DSP exports with independent Python standard-library parsers."""
import json,pathlib,sys,wave,zipfile,io
root=pathlib.Path(sys.argv[1])
with wave.open(str(root/'reference-44100-24.wav'),'rb') as w:
    assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(2,3,44100,363825)
    assert any(w.readframes(w.getnframes()))
with zipfile.ZipFile(root/'reference.grillapack') as z:
    assert z.testzip() is None
    assert set(z.namelist())=={'manifest.json','metadata.json'}
    p=json.loads(z.read('manifest.json'));assert p['name']=='First light' and len(p['tracks'])==3
with zipfile.ZipFile(root/'stems.zip') as z:
    assert z.testzip() is None
    manifest=json.loads(z.read('manifest.json'));assert manifest['masterGainApplied'] is False
    lengths=[]
    for name in z.namelist():
        if name.endswith('.wav'):
            with wave.open(io.BytesIO(z.read(name)),'rb') as w:
                assert (w.getnchannels(),w.getframerate(),w.getsampwidth())==(2,44100,2)
                lengths.append(w.getnframes())
                if 'drums' in name:assert not any(w.readframes(w.getnframes()))
    assert len(lengths)==3 and len(set(lengths))==1
print('Independent WAV/ZIP validation passed: PCM format/duration/audio, portable project, aligned stems and muted channel.')
