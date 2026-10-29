from pathlib import Path
import re
import sys
sys.stdout.reconfigure(encoding='utf-8')
p = Path('KhmerDub/Core/Localization.swift')
s = p.read_text(encoding='utf-8')
print('chars', len(s), 'bytes', len(s.encode('utf-8')))
print('khmer chars', sum(1 for c in s if '\u1780' <= c <= '\u17ff'))
print('replacement chars', s.count('\ufffd'))
keys = re.findall(r'"([a-zA-Z0-9_.]+)"\s*:', s)
print('total key occurrences', len(keys), 'unique', len(set(keys)))
en_start = s.find('private static let english')
km_start = s.find('private static let khmer')
print('english block', en_start, 'khmer block', km_start)
print(repr(s[km_start:km_start+400]))
en = s[en_start:km_start]
km = s[km_start:]
en_keys = set(re.findall(r'"([a-zA-Z0-9_.]+)"\s*:', en))
km_keys = set(re.findall(r'"([a-zA-Z0-9_.]+)"\s*:', km))
print('en', len(en_keys), 'km', len(km_keys))
print('missing km', sorted(en_keys-km_keys))
print('extra km', sorted(km_keys-en_keys))
# duplicate within each block
from collections import Counter
for name, block in [('en', en), ('km', km)]:
    c = Counter(re.findall(r'"([a-zA-Z0-9_.]+)"\s*:', block))
    dup = {k: v for k, v in c.items() if v > 1}
    print(name, 'dupes', dup)
