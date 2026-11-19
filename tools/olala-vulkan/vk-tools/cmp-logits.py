#!/usr/bin/env python3
"""Compare deux dumps olala-logits (int32 n_tokens, int32 n_vocab, float32[n_tokens*n_vocab]).
Usage : cmp-logits.py ref.bin test.bin
Affiche par position : argmax ref/test, max|diff|, RMSE relative, KL(ref||test) des softmax.
Sans numpy (pur python, array)."""
import sys, struct, math
from array import array

def load(p):
    with open(p, 'rb') as f:
        nt, nv = struct.unpack('<ii', f.read(8))
        a = array('f'); a.frombytes(f.read(nt * nv * 4))
    return nt, nv, a

def softmax_log(row):
    m = max(row); s = sum(math.exp(x - m) for x in row); ls = m + math.log(s)
    return [x - ls for x in row]

r, t = sys.argv[1], sys.argv[2]
nt, nv, A = load(r); nt2, nv2, B = load(t)
if (nt, nv) != (nt2, nv2):
    print(f"FORMES DIFFERENTES ref={nt}x{nv} test={nt2}x{nv2}"); sys.exit(2)
nan = 0; agree = 0; worst_kl = 0.0; worst_rel = 0.0; rels = []; kls = []
print(f"n_tokens={nt} n_vocab={nv}")
print(f"{'pos':>4} {'argmax_ref':>10} {'argmax_tst':>10} {'max|d|':>9} {'relRMSE':>9} {'KL':>10}")
for i in range(nt):
    a = A[i*nv:(i+1)*nv]; b = B[i*nv:(i+1)*nv]
    bad = sum(1 for x in b if x != x or math.isinf(x))
    nan += bad
    ia = max(range(nv), key=a.__getitem__); ib = max(range(nv), key=b.__getitem__) if not bad else -1
    agree += ia == ib
    if bad:
        print(f"{i:>4} {ia:>10} {'NaN/Inf':>10} ({bad} valeurs)"); continue
    md = max(abs(x - y) for x, y in zip(a, b))
    num = sum((x - y) ** 2 for x, y in zip(a, b)); den = sum(x * x for x in a) or 1.0
    rel = math.sqrt(num / den)
    la = softmax_log(a); lb = softmax_log(b)
    kl = sum(math.exp(x) * (x - y) for x, y in zip(la, lb))
    worst_kl = max(worst_kl, kl); worst_rel = max(worst_rel, rel)
    if i > 0: rels.append(rel); kls.append(kl)
    print(f"{i:>4} {ia:>10} {ib:>10} {md:>9.4f} {rel:>9.2e} {kl:>10.2e}")
mr = sum(rels) / len(rels) if rels else 0; mk = sum(kls) / len(kls) if kls else 0
print(f"RESUME: argmax {agree}/{nt}, NaN/Inf={nan}, relRMSE max={worst_rel:.2e} moy(pos>0)={mr:.2e}, KL max={worst_kl:.2e} moy(pos>0)={mk:.2e}")
