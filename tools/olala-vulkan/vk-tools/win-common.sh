# Bibliotheque commune (sourcee par win-*.sh). Pilote Windows natif depuis WSL.
# Variables surchargeables par l'environnement.

WIN_ROOT_W='C:\olala'
WIN_ROOT_L=/mnt/c/olala
SRC_W="${SRC_W:-C:\\olala\\llama.cpp-olala-vulkan}"
SRC_L="${SRC_L:-/mnt/c/olala/llama.cpp-olala-vulkan}"
MODEL_W="${MODEL_W:-C:\\olala\\models\\Olala-v1.0-mini-7A1B-q5_k_m.gguf}"
TMP_W='C:\olala\tmp'
TMP_L=/mnt/c/olala/tmp
VCVARS='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-/home/kevin/olala/vk-tools/results}"  # hors du dépôt (gros)
mkdir -p "$TMP_L" "$RESULTS_DIR"

# Preambule de tout .bat : PATH (cmake/ninja winget) + VULKAN_SDK (les process
# lances depuis WSL ne voient pas les variables ajoutees apres le demarrage de WSL).
_bat_preamble() {
cat <<'EOF'
@echo off
set "WGP=%LOCALAPPDATA%\Microsoft\WinGet\Packages"
set "PATH=%WGP%\Kitware.CMake_Microsoft.Winget.Source_8wekyb3d8bbwe\cmake-4.4.4-windows-x86_64\bin;%WGP%\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe;%LOCALAPPDATA%\Microsoft\WinGet\Links;C:\Program Files\CMake\bin;%PATH%"
if not defined VULKAN_SDK for /d %%d in (C:\VulkanSDK\*) do set "VULKAN_SDK=%%d"
if defined VULKAN_SDK set "PATH=%VULKAN_SDK%\Bin;%PATH%"
EOF
}

# run_bat <contenu> : ecrit un .bat (CRLF) dans C:\olala\tmp et l'execute via cmd.exe.
# Code retour = errorlevel du .bat.
run_bat() {
    local name="run_$$_$RANDOM.bat"
    { _bat_preamble; printf '%s\n' "$1"; } | sed 's/$/\r/' > "$TMP_L/$name"
    ( cd /mnt/c && cmd.exe /d /c "$TMP_W\\$name" )
    local rc=$?
    rm -f "$TMP_L/$name"
    return $rc
}

# run_bat_msvc <contenu> : idem dans un environnement vcvars64.
run_bat_msvc() {
    run_bat "call \"$VCVARS\" >nul || exit /b 99
$1"
}

# Traduit un chemin WSL sous /mnt/c en chemin Windows.
to_win() { wslpath -w "$1"; }

stamp() { date +%Y%m%d-%H%M%S; }

# Synchronise le miroir Windows sur le clone WSL (remote origin = \\wsl.localhost\...).
# Remet le miroir exactement a origin/$BRANCH (reset --hard ; les build-* ignores sont gardes).
# WIP=1 : applique en plus les modifications NON commitees du clone WSL (git diff HEAD +
#         fichiers non suivis), pour tester un shader avant commit.
BRANCH="${BRANCH:-vulkan-olala}"
WSL_CLONE="${WSL_CLONE:-/home/kevin/olala/llama.cpp-olala-vulkan}"
win_pull() {
    run_bat "cd /d $SRC_W || exit /b 1
git fetch -q origin || exit /b 1
git checkout -q $BRANCH 2>nul
git reset -q --hard origin/$BRANCH || exit /b 1
git clean -fdq
git log --oneline -1" || return 1
    if [ "${WIP:-0}" = 1 ]; then
        local p="$TMP_L/wip.patch"
        git -C "$WSL_CLONE" diff --binary HEAD > "$p"
        if [ -s "$p" ]; then
            run_bat "cd /d $SRC_W && git apply --whitespace=nowarn $TMP_W\\wip.patch" || { echo "WIP: git apply a echoue"; return 1; }
            echo "WIP: patch applique ($(grep -c '^diff --git' "$p") fichiers)"
        fi
        git -C "$WSL_CLONE" ls-files --others --exclude-standard | while read -r f; do
            mkdir -p "$SRC_L/$(dirname "$f")"; cp "$WSL_CLONE/$f" "$SRC_L/$f"; echo "WIP: non suivi copie: $f"
        done
        rm -f "$p"
    fi
}
