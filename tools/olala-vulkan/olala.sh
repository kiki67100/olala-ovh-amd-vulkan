#!/usr/bin/env bash
# olala : chat Olala sur le GPU AMD (Vulkan, Windows natif) depuis le terminal WSL.
#   olala          lance la GUI (http://localhost:7861) + llama-server Vulkan (port 8081), modèle q5_k_m
#   olala q8       idem avec le modèle q8_0-safe2 (plus précis, plus lent : une partie reste sur le CPU)
#   olala stop     arrête la GUI Vulkan et le llama-server Vulkan (ex. après une fermeture brutale)
#   olala status   indique ce qui tourne
#   olala help
# Ne touche jamais à la GUI CPU (7860) ni au llama-server CPU (8080).
set -u
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$HERE/config.sh"   # chemins (OLALA_WIN_ROOT, défaut C:\olala) et recherche du Python Windows
DEST_L="$OLALA_GUI_L"
DEST_W="$OLALA_GUI_W"
EXE_L="$OLALA_SRC_L/build-vk/bin/llama-server.exe"

ps1() { (cd /mnt/c && powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'); }

# PID Windows qui écoute sur un port (vide si rien)
listener() { ps1 "(Get-NetTCPConnection -LocalPort $1 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess"; }

stop_port() {
    local pid; pid=$(listener "$1")
    if [ -n "$pid" ]; then
        local name; name=$(ps1 "(Get-Process -Id $pid).ProcessName")
        case "$name" in
            python|llama-server) ps1 "Stop-Process -Id $pid -Force"; echo "Arrêté : $name (port $1, PID $pid)";;
            *) echo "Port $1 occupé par '$name' (PID $pid) : je n'y touche pas.";;
        esac
    fi
}

case "${1:-start}" in
    help|-h|--help)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    stop)
        stop_port 7861; stop_port 8081; exit 0;;
    status)
        g=$(listener 7861); s=$(listener 8081)
        if [ -n "$g" ]; then echo "GUI Vulkan (7861)          : en marche (PID $g) → http://localhost:7861"; else echo "GUI Vulkan (7861)          : arrêtée"; fi
        if [ -n "$s" ]; then echo "llama-server Vulkan (8081) : en marche (PID $s)"; else echo "llama-server Vulkan (8081) : arrêté"; fi
        exit 0;;
    start|q5) MODEL=q5_k_m;;
    q8) MODEL=q8_0-safe2;;
    *) echo "Commande inconnue : $1 (voir 'olala help')"; exit 1;;
esac

PY_W="$(olala_find_python)"
[ -n "$PY_W" ] || { echo "Python pour Windows introuvable (installer Python 3, ou définir OLALA_PY_W)."; exit 1; }
PY_L="$(wslpath -u "$PY_W")"
MODEL_L="$OLALA_MODELS_L/$([ "$MODEL" = q8_0-safe2 ] && echo Olala-v1.0-mini-7A1B-q8_0-safe2.gguf || echo Olala-v1.0-mini-7A1B-q5_k_m.gguf)"
for f in "$PY_L" "$EXE_L" "$MODEL_L"; do
    [ -e "$f" ] || { echo "Introuvable : $f"; exit 1; }
done

if [ -n "$(listener 7861)" ]; then
    echo "La GUI Vulkan tourne déjà : http://localhost:7861"
    (cd /mnt/c && cmd.exe /c start "" http://localhost:7861 >/dev/null 2>&1)
    exit 0
fi
# Un llama-server Vulkan orphelin (GUI fermée brutalement) bloquerait le port 8081.
stop_port 8081

# Déploie la GUI (source dans le dépôt) vers $OLALA_WIN_ROOT\gui-vulkan
mkdir -p "$DEST_L"
cp "$HERE/gui/app.py" "$HERE/gui/index.html" "$HERE/gui/lancer.bat" "$DEST_L/"

echo "Chargement du modèle sur la RX 6600 (~10 s)… Ctrl+C pour arrêter."
OPEN=--open; [ "${OLALA_NO_BROWSER:-0}" = 1 ] && OPEN=
# Ctrl+C tue python.exe sans lui laisser arrêter son llama-server : on nettoie ici.
cleanup() { trap - INT TERM EXIT; echo; echo "Arrêt…"; stop_port 7861 >/dev/null; stop_port 8081; }
trap cleanup INT TERM EXIT
export OLALA_WIN_ROOT="$OLALA_WIN_ROOT_W" WSLENV="${WSLENV:+$WSLENV:}OLALA_WIN_ROOT"  # transmis au Python Windows
cd "$DEST_L" && "$PY_L" -u "$DEST_W\\app.py" $OPEN "$MODEL"
