#!/usr/bin/env python3
"""Independent readers for the real CAF bytes and portable-source fixture."""
import hashlib,json,pathlib,struct,sys,zipfile
folder=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(folder/'voice-source.grillapack') as archive:
    manifest=json.loads(archive.read('manifest.json'))
    for record in manifest['audioAssets']:
        data=archive.read('Assets/'+record['id']+'.caf')
        assert len(data)==record['byteCount']
        assert hashlib.sha256(data).hexdigest()==record['sha256']
        assert data[:4]==b'caff'
        cursor=8;rate=None;frames=None
        while cursor+12<=len(data):
            kind=data[cursor:cursor+4];size=struct.unpack_from('>q',data,cursor+4)[0];cursor+=12
            if size==-1: size=len(data)-cursor
            if kind==b'desc':
                rate,codec,flags,packet,packframes,channels,bits=struct.unpack_from('>d4sIIIII',data,cursor)
                assert codec==b'lpcm' and channels==1 and bits==32
            if kind==b'data': frames=(size-4)//4
            cursor+=size
        assert rate and frames and abs(frames/rate-record['duration'])<0.001
print('Independent CAF/SHA-256/ZIP source-recording validation passed.')
