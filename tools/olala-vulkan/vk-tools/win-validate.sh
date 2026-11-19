#!/usr/bin/env bash
# Validation complete en un appel : synchro git + build vk/cpu + tests + bench.
# Usage : win-validate.sh [OPS]     (OPS : liste -o pour test-backend-ops, defaut ops Olala)
#   Variables transmises : WIP=1, N, NGL, P, NT, REPS, SKIP_BENCH=1, SKIP_CPU_BUILD=1
set -u
D="$(dirname "$0")"
[ -n "${1:-}" ] && export OPS="$1"
if [ "${SKIP_CPU_BUILD:-0}" = 1 ]; then "$D/win-build.sh" vk || exit 1
else "$D/win-build.sh" all || exit 1; fi
"$D/win-test.sh" ops ops:MUL_MAT:amax=1000000 'ops:MUL_MAT_ID:amax=(1000000|100000)\.' e2e logits sched
[ "${SKIP_BENCH:-0}" = 1 ] || "$D/win-bench.sh" all
