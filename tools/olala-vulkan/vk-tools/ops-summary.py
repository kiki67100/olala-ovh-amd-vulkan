#!/usr/bin/env python3
"""Resume par op d'un log test-backend-ops (mode test) : OK / FAIL / non supporte + lignes FAIL."""
import sys, re, collections
c = collections.defaultdict(collections.Counter); fails = []
for l in open(sys.argv[1], encoding='utf-8', errors='replace'):
    l = re.sub(r'\x1b\[[0-9;]*m', '', l)
    m = re.match(r'\s+([A-Z0-9_]+)\((.*)\): (OK|FAIL|not supported)', l)
    if m:
        c[m.group(1)][m.group(3)] += 1
        if m.group(3) == 'FAIL': fails.append(l.strip()[:220])
    elif re.search(r'NMSE|ERR|nan', l) and fails and len(l) < 400:
        fails.append('     ' + l.strip()[:220])
    elif 'tests passed' in l or 'backends passed' in l:
        print(l.strip())
print(f"{'op':28s} {'OK':>4s} {'FAIL':>5s} {'non-supp':>8s}")
for op, k in sorted(c.items()):
    print(f"{op:28s} {k['OK']:4d} {k['FAIL']:5d} {k['not supported']:8d}")
for f in fails[:40]: print('  ' + f)
