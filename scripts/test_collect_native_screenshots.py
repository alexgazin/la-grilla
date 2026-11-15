#!/usr/bin/env python3
"""Exercise screenshot naming against a real-shaped xcresult UUID collision."""
import json,pathlib,struct,subprocess,sys,tempfile,zlib

def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))

png=(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))
     +chunk(b'IDAT',zlib.compress(b'\0\x24\x57\x87'))+chunk(b'IEND',b''))
script=pathlib.Path(__file__).with_name('collect_native_screenshots.py')
with tempfile.TemporaryDirectory(prefix='grilla-collector-') as directory:
    root=pathlib.Path(directory);source=root/'attachments';source.mkdir()
    # These identifiers reproduce the actual run43713084377 attachment record.
    exported='6858E196-25BB-45B0-A5C2-D263B9BAE7C4.png'
    (source/exported).write_bytes(png)
    (source/'manifest.json').write_text(json.dumps([{'attachments':[{
        'exportedFileName':exported,
        'suggestedHumanReadableName':'C2-notes_0_2C36F3B4-6E89-4D49-A6EC-50CA7909D94C.png'
    }]}]))
    target=root/'collected'
    subprocess.run([sys.executable,str(script),str(source),str(target),'C2'],check=True)
    assert sorted(p.name for p in target.iterdir())==['notes.png']
    assert (target/'notes.png').read_bytes()==png
    # A UUID by itself is never evidence of a stage-named attachment.
    (source/'manifest.json').unlink();unnamed=root/'unnamed'
    subprocess.run([sys.executable,str(script),str(source),str(unnamed),'C2','--allow-empty'],check=True)
    assert list(unnamed.iterdir())==[]
    # Direct named exports still work without an attachment manifest.
    (source/'C2-grid.png').write_bytes(png);direct=root/'direct'
    subprocess.run([sys.executable,str(script),str(source),str(direct),'C2'],check=True)
    assert sorted(p.name for p in direct.iterdir())==['grid.png']
    assert (direct/'grid.png').read_bytes()==png
    # Runner workspaces contain the prior committed stage. Replace only PNGs,
    # leaving documentation intact, so a partial run has no stale provenance.
    (direct/'previous-run.png').write_bytes(png)
    (direct/'README.md').write_text('Accepted historical capture documentation')
    subprocess.run([sys.executable,str(script),str(source),str(direct),'C2','--replace-pngs'],check=True)
    assert sorted(p.name for p in direct.glob('*.png'))==['grid.png']
    assert (direct/'README.md').exists()
    (source/'C2-grid.png').unlink()
    subprocess.run([sys.executable,str(script),str(source),str(direct),'C2','--replace-pngs','--allow-empty'],check=True)
    assert list(direct.glob('*.png'))==[]
    (direct/'previous-run.png').write_bytes(png)
    failed=subprocess.run([sys.executable,str(script),str(source),str(direct),'C2','--replace-pngs'],capture_output=True)
    assert failed.returncode!=0 and list(direct.glob('*.png'))==[]
print('Screenshot collector regression passed: UUID suffix ignored; named PNG bytes preserved.')
