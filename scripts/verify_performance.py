#!/usr/bin/env python3
"""Independent SMF/PCM reader for exports produced by the actual Swift renderer."""
import pathlib,struct,sys,wave
root=pathlib.Path(sys.argv[1])
with wave.open(str(root/'performance.wav'),'rb') as w:
    assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(2,3,48000,48000)
    assert any(w.readframes(w.getnframes()))
data=(root/'performance.mid').read_bytes()
assert data[:4]==b'MThd'
size,fmt,count,ppq=struct.unpack('>IHHH',data[4:14]);assert (size,fmt,count,ppq)==(6,1,4,960)
offset=14;notes=[];controls=[];ends=[];markers=[];tempos=[]
for track in range(count):
    assert data[offset:offset+4]==b'MTrk'
    length=int.from_bytes(data[offset+4:offset+8],'big');offset+=8
    chunk=data[offset:offset+length];offset+=length;cursor=0;tick=0;last_priority={}
    def vlq():
        global cursor
        value=0
        for _ in range(4):
            byte=chunk[cursor];cursor+=1;value=(value<<7)|(byte&127)
            if byte<128:return value
        raise AssertionError('Invalid VLQ')
    while cursor<len(chunk):
        tick+=vlq();status=chunk[cursor];cursor+=1
        if status==255:
            kind=chunk[cursor];cursor+=1;n=vlq();payload=chunk[cursor:cursor+n];cursor+=n
            if kind==47:assert n==0;ends.append(tick);assert cursor==len(chunk)
            if kind==81:tempos.append(int.from_bytes(payload,"big"))
            if kind==6:markers.append((tick,payload.decode()))
        else:
            assert status&240 in (128,144,176)
            a,b=chunk[cursor:cursor+2];cursor+=2;assert a<128 and b<128 and tick<=1920
            if status&240==176:controls.append((tick,status&15,a,b))
            else:
                # NoteOff must precede NoteOn at the same tick within each track.
                priority=0 if status&240==128 else 1
                assert priority>=last_priority.get(tick,0);last_priority[tick]=priority
                notes.append((tick,status&240,status&15,a,b))
assert offset==len(data) and ends==[1920]*4 and tempos==[500000]
assert (1200,144,9,36,110) in notes and (1320,128,9,36,0) in notes
assert (960,0,74,32) in controls and any(t==0 for t,_ in markers)
print('Independent performance PCM/SMF: finite 1-second audio, PPQ/tempo tracks, live pad, filter CC and NoteOff ordering passed.')
