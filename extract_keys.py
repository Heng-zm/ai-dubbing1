from pathlib import Path
import re, json, sys
sys.stdout.reconfigure(encoding='utf-8')
p = Path('KhmerDub/Core/Localization.swift')
s = p.read_text(encoding='utf-8')
km_start = s.find('private static let khmer')
en = s[s.find('private static let english'):km_start]
km = s[km_start:]

def parse(block):
    pairs = {}
    for m in re.finditer(r'"([a-zA-Z0-9_.]+)"\s*:\s*"((?:[^"\\]|\\.)*)"', block):
        key = m.group(1)
        val = m.group(2)
        val = val.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
        pairs[key] = val
    return pairs
en_d = parse(en)
km_d = parse(km)
Path('en.json').write_text(json.dumps(en_d, ensure_ascii=False, indent=2), encoding='utf-8')
Path('km.json').write_text(json.dumps(km_d, ensure_ascii=False, indent=2), encoding='utf-8')
for k in en_d:
    print(f'{k}\t{en_d[k]}')
