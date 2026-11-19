#!/usr/bin/env bash
# llama-bench Vulkan vs CPU (natif Windows) + VRAM max pendant le bench Vulkan.
#
# Usage : win-bench.sh [vk|cpu|all]        (defaut all)
#   Variables : VK_BUILD=build-vk, P=512 (liste pp, ex. P=512,4096), NT=128, REPS=3, NGL=99,
#               VK_EXTRA / CPU_EXTRA (args llama-bench en plus, ex. "-ub 1024").
#   CPU : -ngl 0 -t 6 -fa 1 --repack 0 (equivalent du -nr de llama-cli/server)
#         (mettre CPU_REPACK=1 pour garder le repack)
# Sortie : results/bench-<stamp>-<commit>.txt (markdown de llama-bench)
set -u
. "$(dirname "$0")/win-common.sh"
WHICH="${1:-all}"
P="${P:-512}"; NT="${NT:-128}"; REPS="${REPS:-3}"; NGL="${NGL:-99}"
COMMIT=$(git -C "$SRC_L" log --oneline -1 2>/dev/null | cut -c1-9)
OUTF="$RESULTS_DIR/bench-$(stamp)-$COMMIT.txt"
OW="$TMP_W\\out"; OL="$TMP_L/out"; mkdir -p "$OL"
echo "commit miroir $COMMIT ; P=$P NT=$NT REPS=$REPS" | tee "$OUTF"

if [ "$WHICH" = vk ] || [ "$WHICH" = all ]; then
    rm -f "$OL/vram.txt" "$OL/vram.stop"
    ( cd /mnt/c && powershell.exe -NoProfile -Command "
\$max=0; while (-not (Test-Path '$OW\\vram.stop')) {
  try { \$v=(Get-Counter '\\GPU Adapter Memory(*)\\Dedicated Usage' -ErrorAction Stop).CounterSamples | Measure-Object CookedValue -Maximum; if (\$v.Maximum -gt \$max) { \$max=\$v.Maximum } } catch {}
  Start-Sleep -Milliseconds 300 }
'{0:F0}' -f (\$max/1MB) | Out-File -Encoding ascii '$OW\\vram.txt'; Remove-Item '$OW\\vram.stop'" </dev/null >/dev/null 2>&1 ) &
    vp=$!
    echo "== Vulkan : -ngl $NGL -fa 1 -p $P -n $NT -r $REPS ${VK_EXTRA:-}" | tee -a "$OUTF"
    run_bat "\"$SRC_W\\${VK_BUILD:-build-vk}\\bin\\llama-bench.exe\" -m $MODEL_W -ngl $NGL -fa 1 -p $P -n $NT -r $REPS ${VK_EXTRA:-} > $OW\\bench-vk.txt 2> $OW\\bench-vk.log"
    rc=$?
    touch "$OL/vram.stop"; wait $vp 2>/dev/null
    cat "$OL/bench-vk.txt" | tr -d '\r' | tee -a "$OUTF"
    [ $rc -ne 0 ] && { echo "ECHEC llama-bench Vulkan (rc=$rc)"; tail -15 "$OL/bench-vk.log"; } | tee -a "$OUTF"
    echo "VRAM dediee max pendant le bench Vulkan (tous process) : $(tr -d '\r\n' < "$OL/vram.txt" 2>/dev/null) Mo" | tee -a "$OUTF"
    cp "$OL/bench-vk.log" "${OUTF%.txt}-vk.log"
fi
if [ "$WHICH" = cpu ] || [ "$WHICH" = all ]; then
    echo "== CPU : -ngl 0 -t 6 -fa 1 --repack ${CPU_REPACK:-0} -p $P -n $NT -r $REPS ${CPU_EXTRA:-}" | tee -a "$OUTF"
    run_bat "\"$SRC_W\\build-cpu\\bin\\llama-bench.exe\" -m $MODEL_W -ngl 0 -t 6 -fa 1 --repack ${CPU_REPACK:-0} -p $P -n $NT -r $REPS ${CPU_EXTRA:-} > $OW\\bench-cpu.txt 2> $OW\\bench-cpu.log"
    rc=$?
    cat "$OL/bench-cpu.txt" | tr -d '\r' | tee -a "$OUTF"
    [ $rc -ne 0 ] && { echo "ECHEC llama-bench CPU (rc=$rc)"; tail -15 "$OL/bench-cpu.log"; } | tee -a "$OUTF"
fi
echo "-> $OUTF"
