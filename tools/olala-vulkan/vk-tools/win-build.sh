#!/usr/bin/env bash
# Build Windows natif (MSVC + Ninja) du miroir C:\olala\llama.cpp-olala-vulkan.
#
# Usage : win-build.sh [vk|cpu|all] [cible ...]
#   vk  -> build-vk  (GGML_VULKAN=ON)      cpu -> build-cpu (CPU seul, AVX2)
#   cibles par defaut : test-backend-ops llama-completion llama-cli llama-bench
#                       llama-server olala-logits
#   Variables : NOPULL=1 (pas de synchro git), WIP=1 (inclut les modifs non commitees
#               du clone WSL), RECONF=1 (reconfigure cmake), JOBS=N.
# Log : results/build-<kind>-<stamp>.log
set -u
. "$(dirname "$0")/win-common.sh"

KIND="${1:-vk}"; shift || true
TARGETS="${*:-test-backend-ops llama-completion llama-cli llama-bench llama-server olala-logits}"
JOBS="${JOBS:-10}"

if [ "${NOPULL:-0}" != 1 ]; then
    echo "== synchro du miroir Windows"; win_pull || { echo "ECHEC synchro git"; exit 1; }
fi

COMMON="-G Ninja -DCMAKE_BUILD_TYPE=Release -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_OPENSSL=OFF -DGGML_NATIVE=OFF -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON"

build_one() {
    local k="$1" dir flags
    case "$k" in
        vk)  dir=build-vk;  flags="$COMMON -DGGML_VULKAN=ON" ;;
        cpu) dir=build-cpu; flags="$COMMON" ;;
        *) echo "kind inconnu: $k"; return 2 ;;
    esac
    local log="$RESULTS_DIR/build-$k-$(stamp).log"
    local conf=""
    if [ "${RECONF:-0}" = 1 ] || [ ! -f "$SRC_L/$dir/build.ninja" ]; then
        conf="cmake -S . -B $dir $flags || exit /b 1"
    fi
    echo "== build $k ($dir) -> $log"
    local t0=$(date +%s)
    run_bat_msvc "cd /d $SRC_W || exit /b 1
if defined VULKAN_SDK echo VULKAN_SDK=%VULKAN_SDK%
$conf
cmake --build $dir --config Release -j $JOBS --target $TARGETS || exit /b 1" > "$log" 2>&1
    local rc=$?
    local t1=$(date +%s)
    if [ $rc -ne 0 ]; then
        echo "ECHEC build $k (rc=$rc, $((t1-t0)) s). Erreurs :"
        grep -aE "error|FAILED|Error" "$log" | head -40
        return $rc
    fi
    echo "OK build $k en $((t1-t0)) s ; binaires : $SRC_W\\$dir\\bin"
}

rc=0
case "$KIND" in
    all) build_one vk || rc=$?; build_one cpu || rc=$? ;;
    *)   build_one "$KIND" || rc=$? ;;
esac
df -h /mnt/c | tail -1 | awk '{print "C: libre: "$4}'
exit $rc
