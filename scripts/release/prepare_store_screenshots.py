#!/usr/bin/env python3
"""Copy genuine full-screen Pro Max captures without resizing/compositing."""
import argparse,pathlib,shutil,struct
p=argparse.ArgumentParser();p.add_argument('source',type=pathlib.Path);p.add_argument('destination',type=pathlib.Path);a=p.parse_args()
for locale in ['en-US','ru']:
 for index,screen in enumerate(['grid','jam','notes','harmony-proposal','perform-take','export'],1):
  source=a.source/f'store-{locale}-{screen}.png';header=source.read_bytes()[:24]
  assert header[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',header[16:24])==(1320,2868),f'Expected native iPhone 16 Pro Max frame: {source}'
  destination=a.destination/locale/f'{index:02d}-{screen}.png';destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,destination)
print('Prepared 12 unchanged native App Store screenshots (1320 × 2868, EN/RU).')
