#!/usr/bin/env python3
"""Map named XCTest screenshots exported by xcresulttool into the stage folder."""
import json,pathlib,re,shutil,sys
source,destination,stage=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3]
files={p.name:p for p in source.rglob('*') if p.is_file() and p.suffix.lower() in ('.png','.jpg','.jpeg')}
pattern=re.compile(re.escape(stage)+r'-([a-z][a-z-]*)')
mapped={}
def strings(value):
    if isinstance(value,str):yield value
    elif isinstance(value,dict):
        for item in value.values():yield from strings(item)
    elif isinstance(value,list):
        for item in value:yield from strings(item)
def walk(value):
    if isinstance(value,dict):
        values=list(strings(value));names={m.group(1).rstrip('-') for text in values for m in pattern.finditer(text)}
        candidates={files[pathlib.Path(text).name] for text in values if pathlib.Path(text).name in files}
        if len(names)==1 and len(candidates)==1:mapped[next(iter(names))]=next(iter(candidates))
        for child in value.values():walk(child)
    elif isinstance(value,list):
        for child in value:walk(child)
for manifest in source.rglob('*.json'):
    try:walk(json.loads(manifest.read_text()))
    except (ValueError,UnicodeError):pass
for name,file in files.items():
    match=pattern.search(name)
    if match:mapped.setdefault(match.group(1).rstrip('-'),file)
assert mapped,'xcresulttool did not export named '+stage+' screenshots; inspect NativeAttachments/manifest.json'
destination.mkdir(parents=True,exist_ok=True)
for name,file in mapped.items():shutil.copyfile(file,destination/(name+file.suffix.lower()))
print(f'Collected {len(mapped)} real {stage} screenshots from XCTest attachments.')
