# Configuration commune des outils Olala-Vulkan (sourcé par olala.sh et vk-tools/win-*.sh).
# Aucun chemin personnel : tout est déduit ou surchargeable par variable d'environnement.
#
#   OLALA_WIN_ROOT   dossier Windows de travail            (défaut : C:\olala)
#                    contient llama.cpp-olala-vulkan\ (miroir + builds), models\, gui-vulkan\, tmp\
#   OLALA_RESULTS    résultats tests/bench, hors dépôt      (défaut : <parent du dépôt>/vk-tools/results)
#   OLALA_PY_W       python.exe Windows à utiliser          (défaut : trouvé via py.exe, sinon where python)
#   OLALA_MODEL      modèle par défaut des tests           (défaut : Olala-v1.0-mini-7A1B-q5_k_m.gguf)

OLALA_TOOLS="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
OLALA_REPO="$(cd "$OLALA_TOOLS/../.." && pwd)"

OLALA_WIN_ROOT_W="${OLALA_WIN_ROOT:-C:\\olala}"
OLALA_WIN_ROOT_L="$(wslpath -u "$OLALA_WIN_ROOT_W")"

OLALA_RESULTS="${OLALA_RESULTS:-$(dirname "$OLALA_REPO")/vk-tools/results}"
OLALA_MODEL="${OLALA_MODEL:-Olala-v1.0-mini-7A1B-q5_k_m.gguf}"

# Chemins dérivés (forme Windows _W / forme WSL _L)
OLALA_SRC_W="$OLALA_WIN_ROOT_W\\llama.cpp-olala-vulkan"
OLALA_SRC_L="$OLALA_WIN_ROOT_L/llama.cpp-olala-vulkan"
OLALA_MODELS_W="$OLALA_WIN_ROOT_W\\models"
OLALA_MODELS_L="$OLALA_WIN_ROOT_L/models"
OLALA_GUI_W="$OLALA_WIN_ROOT_W\\gui-vulkan"
OLALA_GUI_L="$OLALA_WIN_ROOT_L/gui-vulkan"
OLALA_TMP_W="$OLALA_WIN_ROOT_W\\tmp"
OLALA_TMP_L="$OLALA_WIN_ROOT_L/tmp"

# python.exe Windows (chemin Windows), résolu à la demande.
olala_find_python() {
    if [ -n "${OLALA_PY_W:-}" ]; then printf '%s\n' "$OLALA_PY_W"; return; fi
    local p=""
    if [ -x /mnt/c/Windows/py.exe ]; then
        p=$(cd /mnt/c && /mnt/c/Windows/py.exe -3 -c "import sys; print(sys.executable)" 2>/dev/null | tr -d '\r')
    fi
    if [ -z "$p" ]; then  # sans lanceur py : premier python.exe qui n'est pas l'alias du Microsoft Store
        p=$(cd /mnt/c && cmd.exe /d /c "where python" 2>/dev/null | tr -d '\r' | grep -iv WindowsApps | head -1)
    fi
    [ -n "$p" ] && printf '%s\n' "$p"
}
