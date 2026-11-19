#!/usr/bin/env bash
# Validation Vulkan (RX 6600) vs CPU, en natif Windows.
#
# Usage : win-test.sh [etape ...]      (defaut : ops e2e logits)
#   support      test-backend-ops support -b Vulkan0 (toutes les ops ; liste des non supportees)
#   ops          test-backend-ops test -b Vulkan0 -o $OPS [-p $PARAMS] (defaut : ops Olala)
#   ops:OP[,OP]:REGEX   idem avec op(s) et regex de params dans l'etape (ex. 'ops:MUL_MAT:amax=1000000')
#                (ne pas mettre ':' dans la regex)
#   allops       test-backend-ops test -b Vulkan0 complet (long)
#   e2e          llama-completion greedy, 4 prompts (fr, code, reason, long), CPU vs Vulkan
#                + reference CPU OLALA_PORTABLE=1 (meme graphe que le GPU). Splits + VRAM.
#   logits       olala-logits CPU vs Vulkan sur fr/long, compare par cmp-logits.py
#   sched        un run Vulkan avec GGML_SCHED_DEBUG=2 -v (placement des ops) -> sched.log
# Variables : VK_BUILD=build-vk (dossier de build Vulkan), N=64 (tokens generes), NGL=99, CTX=4096, REF=1 (recalcule les refs CPU),
#             VK_EXTRA / CPU_EXTRA (args en plus), OUT=dir de sortie.
# Le build n'est PAS relance ici : faire win-build.sh all avant.
set -u
. "$(dirname "$0")/win-common.sh"

STEPS="${*:-ops e2e logits}"
N="${N:-64}"; NGL="${NGL:-99}"; CTX="${CTX:-4096}"
OLALA_OPS_DEFAULT="MAMBA3_MIMO,MAMBA3_MIMO_CACHE_FUSION,OLALA_MOE,OLALA_MMV,OLALA_TPA_PREP,OLALA_DIFF_GATE,OLALA_TPA_ATTN,OLALA_TPA_EXPAND,GEODESIC"
VK_BIN="$SRC_W\\${VK_BUILD:-build-vk}\\bin"; CPU_BIN="$SRC_W\\build-cpu\\bin"
COMMIT=$(git -C "$SRC_L" log --oneline -1 2>/dev/null | cut -c1-9)
OUT="${OUT:-$RESULTS_DIR/test-$(stamp)-$COMMIT}"; mkdir -p "$OUT"
REFDIR="$RESULTS_DIR/ref-cpu"; mkdir -p "$REFDIR"
OW="$TMP_W\\out"; OL="$TMP_L/out"; mkdir -p "$OL"
PROMPTS_L="$TOOLS_DIR/prompts"
cp "$PROMPTS_L"/*.txt "$OL/"
echo "Sorties : $OUT   (commit miroir : $COMMIT)"

COMPL_ARGS="-n $N --temp 0 --seed 1 -no-cnv -fa 1 -c $CTX --no-display-prompt -fit off"

# --- echantillonneur VRAM (compteur Windows GPU Adapter Memory, max sur la duree) ---
vram_start() {
    rm -f "$OL/vram.txt"
    ( cd /mnt/c && powershell.exe -NoProfile -Command "
\$max=0; while (-not (Test-Path '$OW\\vram.stop')) {
  try { \$v=(Get-Counter '\\GPU Adapter Memory(*)\\Dedicated Usage' -ErrorAction Stop).CounterSamples | Measure-Object CookedValue -Maximum; if (\$v.Maximum -gt \$max) { \$max=\$v.Maximum } } catch {}
  Start-Sleep -Milliseconds 300 }
'{0:F0}' -f (\$max/1MB) | Out-File -Encoding ascii '$OW\\vram.txt'; Remove-Item '$OW\\vram.stop'" </dev/null >/dev/null 2>&1 ) &
    VRAM_PID=$!
}
# (appele dans $(...) : pas de wait possible -> on attend le fichier)
vram_stop() { touch "$OL/vram.stop"; local i; for i in $(seq 1 60); do [ -s "$OL/vram.txt" ] && break; sleep 0.5; done; cat "$OL/vram.txt" 2>/dev/null | tr -d '\r\n'; }
vram_idle() { ( cd /mnt/c && powershell.exe -NoProfile -Command "'{0:F0}' -f (((Get-Counter '\\GPU Adapter Memory(*)\\Dedicated Usage').CounterSamples | Measure-Object CookedValue -Maximum).Maximum/1MB)" 2>/dev/null | tr -d '\r\n' ); }

step_support() {
    echo "== test-backend-ops support -b Vulkan0"
    run_bat "\"$VK_BIN\\test-backend-ops.exe\" support -b Vulkan0 --output csv > $OW\\support.csv 2> $OW\\support.err"
    cp "$OL/support.csv" "$OL/support.err" "$OUT/" 2>/dev/null
    head -40 "$OUT/support.err"
    # csv : colonnes test_mode,supported,passed,... -> on resume par op
    python3 - "$OUT/support.csv" <<'EOF' | tee "$OUT/support-summary.txt"
import csv, sys, collections
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8', errors='replace')))
if not rows: print("CSV vide"); sys.exit()
keyop = 'op_name' if 'op_name' in rows[0] else list(rows[0].keys())[2]
by = collections.defaultdict(lambda: [0, 0])
for r in rows:
    if r.get('backend_name', 'Vulkan0').startswith('CPU'): continue
    s = r.get('supported', '').lower() in ('1', 'true', 'yes')
    by[r[keyop]][0 if s else 1] += 1
print("op : cas supportes / non supportes (ops avec au moins 1 non supporte)")
for op, (y, n) in sorted(by.items()):
    if n: print(f"  {op:32s} {y:4d} / {n:4d}{'   <-- AUCUN' if y == 0 else ''}")
print(f"total ops testees : {len(by)} ; entierement supportees : {sum(1 for v in by.values() if not v[1])}")
EOF
}

# step_ops [OPS] [PARAMS_REGEX] [tag]
step_ops() {
    local ops="${1:-${OPS:-$OLALA_OPS_DEFAULT}}" par="${2:-${PARAMS:-}}" tag="${3:-ops}"
    local pf=""; [ -n "$par" ] && pf="-p \"$par\""
    echo "== test-backend-ops test -b Vulkan0 -o $ops ${par:+-p '$par'}"
    run_bat "\"$VK_BIN\\test-backend-ops.exe\" test -b Vulkan0 -o $ops $pf > $OW\\$tag.txt 2>&1"
    cp "$OL/$tag.txt" "$OUT/$tag.txt"
    grep -aE "Vulkan0|Device|subgroup|fp16|coopmat|matrix cores|int dot" "$OUT/$tag.txt" | head -3
    python3 "$TOOLS_DIR/ops-summary.py" "$OUT/$tag.txt" | tee "$OUT/$tag-summary.txt"
}

step_allops() {
    echo "== test-backend-ops test -b Vulkan0 (complet)"
    run_bat "\"$VK_BIN\\test-backend-ops.exe\" test -b Vulkan0 > $OW\\allops.txt 2>&1"
    cp "$OL/allops.txt" "$OUT/"
    python3 "$TOOLS_DIR/ops-summary.py" "$OUT/allops.txt" > "$OUT/allops-summary.txt"
    grep -aE "passed|^ *[A-Z].* [0-9]+ +[1-9][0-9]* +[0-9]+$" "$OUT/allops-summary.txt"; grep -a "FAIL" "$OUT/allops-summary.txt" | head -30
}

# run_compl <bin> <tag> <prompt> <extra env (set X=Y&)> <args>
run_compl() {
    local bin="$1" tag="$2" p="$3" envs="$4" args="$5"
    run_bat "$envs
\"$bin\\llama-completion.exe\" -m $MODEL_W -f $OW\\$p.txt $COMPL_ARGS $args > $OW\\$tag-$p.txt 2> $OW\\$tag-$p.log"
    local rc=$?
    cp "$OL/$tag-$p.txt" "$OL/$tag-$p.log" "$OUT/" 2>/dev/null
    return $rc
}

step_e2e() {
    echo "== e2e greedy (N=$N) : CPU (-t 6) / CPU OLALA_PORTABLE=1 / Vulkan (-ngl $NGL)"
    local idle; idle=$(vram_idle); echo "VRAM dediee au repos : ${idle} Mo"
    printf "%-7s %-10s %-10s %-9s %-14s %-12s %s\n" prompt vs_cpu vs_portab splits_vk "vk pp/tg t/s" "VRAM max Mo" "sortie" | tee "$OUT/e2e-summary.txt"
    for p in fr code reason long; do
        for ref in cpu cpuport; do
            local env=""; [ $ref = cpuport ] && env="set OLALA_PORTABLE=1"
            if [ "${REF:-0}" = 1 ] || [ ! -s "$REFDIR/$ref-$p-n$N.txt" ]; then
                run_compl "$CPU_BIN" "$ref" "$p" "$env" "-t 6 -ngl 0 ${CPU_EXTRA:-}" || echo "  ECHEC $ref $p"
                cp "$OUT/$ref-$p.txt" "$REFDIR/$ref-$p-n$N.txt"; cp "$OUT/$ref-$p.log" "$REFDIR/$ref-$p-n$N.log"
            fi
        done
        vram_start
        run_compl "$VK_BIN" vk "$p" "" "-ngl $NGL -v ${VK_EXTRA:-}"; local rc=$?
        local vram; vram=$(vram_stop)
        local f="$OUT/vk-$p.txt" l="$OUT/vk-$p.log"
        local c1 c2
        cmp -s "$REFDIR/cpu-$p-n$N.txt" "$f" && c1=IDENT || c1=DIFF
        cmp -s "$REFDIR/cpuport-$p-n$N.txt" "$f" && c2=IDENT || c2=DIFF
        [ $rc -ne 0 ] && c1="ECHEC(rc=$rc)"
        local splits; splits=$(grep -aoE "splits = [0-9]+( / [0-9]+)?" "$l" | tail -1 | sed 's/splits = //;s/ //g')
        local pp tg
        pp=$(grep -aE "prompt eval time" "$l" | grep -aoE "[0-9.]+ tokens per second" | awk '{print $1}')
        tg=$(grep -aE "^\S*\s*eval time|common_perf_print:\s+eval time|llama_perf_context_print:\s+eval time" "$l" | grep -av prompt | grep -aoE "[0-9.]+ tokens per second" | awk '{print $1}')
        local nan=""; grep -aqE '[?]{16}' "$f" && nan="CORROMPU(????)"
        printf "%-7s %-10s %-10s %-9s %-14s %-12s %s\n" "$p" "$c1" "$c2" "${splits:-?}" "${pp:-?}/${tg:-?}" "${vram:-?}" "$nan" | tee -a "$OUT/e2e-summary.txt"
        if [ "$c1" != IDENT ]; then
            # premier point de divergence (en caracteres)
            python3 - "$REFDIR/cpu-$p-n$N.txt" "$f" <<'EOF' | tee -a "$OUT/e2e-summary.txt"
import sys
a=open(sys.argv[1],encoding='utf-8',errors='replace').read(); b=open(sys.argv[2],encoding='utf-8',errors='replace').read()
i=next((k for k in range(min(len(a),len(b))) if a[k]!=b[k]), min(len(a),len(b)))
print(f"    divergence au caractere {i}/{len(a)} ; cpu: {a[i:i+60]!r}\n    {'':28s}vk : {b[i:i+60]!r}")
EOF
        fi
    done
    grep -aE "ggml_vulkan: [0-9] =|Vulkan0|using device" "$OUT/vk-fr.log" | head -3
    grep -aE "load_tensors: .*(Vulkan|CPU).*buffer size|offloaded" "$OUT/vk-fr.log" | head -6
}

step_logits() {
    echo "== olala-logits CPU vs Vulkan"
    for p in fr long; do
        if [ "${REF:-0}" = 1 ] || [ ! -s "$REFDIR/logits-cpu-$p.bin" ]; then
            run_bat "\"$CPU_BIN\\olala-logits.exe\" -m $MODEL_W -t 6 -o $OW\\logits-cpu-$p.bin -p \"$(cat "$PROMPTS_L/$p.txt" | head -c 400 | tr -d '"')\" > nul 2> $OW\\logits-cpu-$p.log"
            mv "$OL/logits-cpu-$p.bin" "$REFDIR/"; cp "$OL/logits-cpu-$p.log" "$OUT/"
        fi
        # bruit de fond : CPU graphe portable (celui du GPU) vs CPU graphe par defaut
        if [ "${REF:-0}" = 1 ] || [ ! -s "$REFDIR/logits-cpuport-$p.txt" ]; then
            run_bat "set OLALA_PORTABLE=1
\"$CPU_BIN\\olala-logits.exe\" -m $MODEL_W -t 6 -o $OW\\logits-cpuport-$p.bin -p \"$(cat "$PROMPTS_L/$p.txt" | head -c 400 | tr -d '"')\" > nul 2> $OW\\logits-cpuport-$p.log"
            python3 "$TOOLS_DIR/cmp-logits.py" "$REFDIR/logits-cpu-$p.bin" "$OL/logits-cpuport-$p.bin" > "$REFDIR/logits-cpuport-$p.txt"
            mv "$OL/logits-cpuport-$p.bin" "$REFDIR/"
        fi
        echo "[$p] ref CPU portable vs CPU : $(tail -1 "$REFDIR/logits-cpuport-$p.txt")"
        run_bat "\"$VK_BIN\\olala-logits.exe\" -m $MODEL_W -ngl $NGL -o $OW\\logits-vk-$p.bin -p \"$(cat "$PROMPTS_L/$p.txt" | head -c 400 | tr -d '"')\" > nul 2> $OW\\logits-vk-$p.log"
        cp "$OL/logits-vk-$p.log" "$OUT/"
        if [ -s "$OL/logits-vk-$p.bin" ]; then
            python3 "$TOOLS_DIR/cmp-logits.py" "$REFDIR/logits-cpu-$p.bin" "$OL/logits-vk-$p.bin" > "$OUT/logits-$p.txt"
            echo "[$p] Vulkan vs CPU          : $(tail -1 "$OUT/logits-$p.txt")"
            python3 "$TOOLS_DIR/cmp-logits.py" "$REFDIR/logits-cpuport-$p.bin" "$OL/logits-vk-$p.bin" > "$OUT/logits-$p-vs-portable.txt"
            echo "[$p] Vulkan vs CPU portable : $(tail -1 "$OUT/logits-$p-vs-portable.txt")"
            mv "$OL/logits-vk-$p.bin" "$OUT/"
        else
            echo "[$p] ECHEC olala-logits Vulkan :"; tail -5 "$OUT/logits-vk-$p.log"
        fi
    done
}

step_sched() {
    echo "== placement des ops (GGML_SCHED_DEBUG=2) sur prompt fr"
    run_compl "$VK_BIN" sched fr "set GGML_SCHED_DEBUG=2" "-ngl $NGL -v -n 4"
    local l="$OUT/sched-fr.log"
    echo "splits : $(grep -aoE 'splits = [0-9]+( / [0-9]+)?' "$l" | tail -2 | tr '\n' ' ')"
    python3 "$TOOLS_DIR/sched-summary.py" "$l" | tee "$OUT/sched-summary.txt"
}

for s in $STEPS; do
    case "$s" in
        support) step_support ;;
        ops) step_ops ;;
        ops:*) IFS=: read -r _ o pr <<< "$s"; step_ops "$o" "$pr" "ops-$(echo "$o" | tr ',' '_' | cut -c1-40)$( [ -n "$pr" ] && echo "-p$(echo "$pr" | md5sum | cut -c1-6)")" ;;
        allops) step_allops ;;
        e2e) step_e2e ;;
        logits) step_logits ;;
        sched) step_sched ;;
        *) echo "etape inconnue : $s" ;;
    esac
done
echo "Resultats dans $OUT"
