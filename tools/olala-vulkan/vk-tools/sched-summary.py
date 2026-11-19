#!/usr/bin/env python3
"""Resume un log GGML_SCHED_DEBUG=2 : pour chaque graphe (bloc commencant a '## SPLIT #0'),
nb de splits, et ops par backend. Affiche le 1er graphe (pp/reserve) et le dernier (tg)."""
import sys, re, collections
graphs = []; cur = None
rx = re.compile(r'node #\s*\d+ \(\s*([^)]*?)\s*\):\s*(.{20}) \(\s*[^)]*\) \[\s*([^ \]]+)')
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if '## SPLIT #0:' in line:
        cur = {'splits': [], 'ops': collections.Counter(), 'names': collections.defaultdict(set)}; graphs.append(cur)
    if cur is None: continue
    if '## SPLIT #' in line:
        m = re.search(r'## SPLIT #(\d+): (\S+) # (\d+) inputs(.*)', line)
        if m: cur['splits'].append((m.group(2), int(m.group(3)), m.group(4).strip()[:300]))
    m = rx.search(line)
    if m:
        op, name, be = m.group(1), m.group(2).strip(), m.group(3)
        cur['ops'][(be, op)] += 1
        if not be.startswith('Vulka'): cur['names'][op].add(re.sub(r'-\d+$', '-N', name))
print(f"{len(graphs)} graphes imprimes")
sel = {'premier': graphs[0], 'dernier': graphs[-1]} if graphs else {}
for k, g in sel.items():
    by = collections.Counter(b for b, _, _ in g['splits'])
    print(f"\n== graphe {k} : {len(g['splits'])} splits ({dict(by)})")
    print("  ops hors Vulkan (backend op : nb noeuds) :")
    for (be, op), n in sorted(g['ops'].items(), key=lambda x: -x[1]):
        if not be.startswith('Vulka'):
            print(f"    {be:6s} {op:12s} {n:5d}   ex: {', '.join(sorted(g['names'][op])[:4])}")
    tot = sum(g['ops'].values()); vk = sum(n for (be, _), n in g['ops'].items() if be.startswith('Vulka'))
    print(f"  noeuds Vulkan {vk}/{tot}")
    print("  exemples d'entrees de splits CPU :")
    for be, ni, inp in [s for s in g['splits'] if not s[0].startswith('Vulka')][:5]:
        print(f"    {be} {ni} inputs: {inp[:160]}")
