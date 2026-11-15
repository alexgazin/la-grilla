#!/usr/bin/env python3
"""Release checks for the bilingual catalog, contrast tokens and opaque app icon."""
import json,pathlib,re,struct
root=pathlib.Path(__file__).resolve().parents[1]
pattern=re.compile(r'^\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");\s*$',re.M)
catalogs={}
for language in ('en','ru'):
    source=(root/f'Resources/{language}.lproj/Localizable.strings').read_text()
    entries=[(json.loads(k),json.loads(v)) for k,v in pattern.findall(source)]
    assert len(dict(entries))==len(entries),f'Duplicate {language} keys'
    catalogs[language]=dict(entries)
assert catalogs['en'].keys()==catalogs['ru'].keys()
placeholder=re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[diuoxXfFeEgGaAcsp@%]')
for key,value in catalogs['ru'].items():
    assert placeholder.findall(key)==placeholder.findall(value),f'Changed formatting: {key}'
literal=r'"((?:[^"\\]|\\.)*)"'
ui=re.compile(r'(?:Text|Button|Label|Section|navigationTitle|accessibilityLabel|ContentUnavailableView|NSLocalizedString)\(\s*'+literal+r'|SmallHeading\(text:\s*'+literal)
def localized_expressions(source):
    # Ternary keys and badge text are not the first literal of Text(...).
    # Read balanced arguments, ignoring parentheses inside Swift string literals.
    for match in re.finditer(r'(?:LocalizedStringKey|CapsuleLabel)\(',source):
        start=position=match.end();depth=1;quoted=escaped=False
        while position<len(source) and depth:
            char=source[position]
            if quoted:
                if escaped:escaped=False
                elif char=='\\':escaped=True
                elif char=='"':quoted=False
            elif char=='"':quoted=True
            elif char=='(':depth+=1
            elif char==')':depth-=1
            position+=1
        assert depth==0,'Unbalanced localized expression'
        value=re.sub(r'comment:\s*'+literal,'',source[start:position-1])
        yield from re.findall(literal,value)
missing=set()
paths=list((root/'App').glob('*.swift'))+list((root/'Features').glob('*.swift'))
for path in paths:
    source=path.read_text()
    for size in re.findall(r'\.system\(size:\s*(\d+(?:\.\d+)?)(?=[,)])',source):
        assert float(size)>=11,f'iOS HIG minimum font size is 11 pt: {path.name} uses {size}'
    keys=[match[1] or match[2] for match in ui.finditer(source)]+list(localized_expressions(source))
    for key in keys:
        if '\\(' in key or not re.search('[A-Za-zА-Яа-я]',placeholder.sub('',key)):continue
        key=json.loads('"'+key+'"')
        if key not in catalogs['ru']:missing.add(key)
assert not missing,'Missing UI keys: '+repr(sorted(missing))
def luminance(hex_value):
    values=[int(hex_value[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in values]
    return sum(x*y for x,y in zip(linear,(.2126,.7152,.0722)))
def contrast(a,b):
    x,y=sorted((luminance(a),luminance(b)));return (y+.05)/(x+.05)
theme=(root/'App/Theme.swift').read_text()
tokens={name:(dark,light) for name,dark,light in re.findall(r'static let (\w+)=adaptive\(0x([A-Fa-f0-9]{6}),0x([A-Fa-f0-9]{6})\)',theme)}
for index in (0,1):
    for background in ('ink','panel','raised'):
        assert contrast(tokens['muted'][index],tokens[background][index])>=4.5
    for accent in ('mint','harmony','drums','bass','record'):
        assert contrast(tokens[accent][index],tokens['ink'][index])>=4.5
icon=root/'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
data=icon.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n'
width,height,depth,color=struct.unpack('>IIBB',data[16:26])
assert (width,height,depth,color)==(1024,1024,8,2),'App Store icon must be opaque RGB 1024×1024'
print(f'Presentation audit passed: {len(catalogs["ru"])} EN/RU keys, placeholder parity, 11pt font floor, AA contrast tokens and opaque 1024px icon.')
