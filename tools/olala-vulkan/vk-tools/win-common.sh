# Bibliotheque commune (sourcee par win-*.sh). Pilote Windows natif depuis WSL.
# Chemins : voir ../config.sh (OLALA_WIN_ROOT, OLALA_RESULTS, OLALA_MODEL...).
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../config.sh"

WIN_ROOT_W="$OLALA_WIN_ROOT_W"
WIN_ROOT_L="$OLALA_WIN_ROOT_L"
SRC_W="${SRC_W:-$OLALA_SRC_W}"
SRC_L="${SRC_L:-$OLALA_SRC_L}"
MODEL_W="${MODEL_W:-$OLALA_MODELS_W\\$OLALA_MODEL}"
TMP_W="$OLALA_TMP_W"
TMP_L="$OLALA_TMP_L"
VCVARS="${VCVARS:-C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat}"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$OLALA_RESULTS}"  # hors du dépôt (gros)
mkdir -p "$TMP_L" "$RESULTS_DIR"

# Preambule de tout .bat : PATH (cmake/ninja winget) + VULKAN_SDK (les process
# lances depuis WSL ne voient pas les variables ajoutees apres le demarrage de WSL).
_bat_preamble() {
cat <<'EOF'
@echo off
set "WGP=%LOCALAPPDATA%\Microsoft\WinGet\Packages"
set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;C:\Program Files\CMake\bin;%PATH%"
for /d %%d in ("%WGP%\Ninja-build.Ninja_*") do set "PATH=%%~d;%PATH%"
for /d %%d in ("%WGP%\Kitware.CMake_*") do for /d %%e in ("%%~d\cmake-*") do set "PATH=%%~e\bin;%PATH%"
if not defined VULKAN_SDK for /d %%d in (C:\VulkanSDK\*) do set "VULKAN_SDK=%%d"
if defined VULKAN_SDK set "PATH=%VULKAN_SDK%\Bin;%PATH%"
EOF
}

# run_bat <contenu> : ecrit un .bat (CRLF) dans $TMP_W et l'execute via cmd.exe.
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
WSL_CLONE="${WSL_CLONE:-$OLALA_REPO}"
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
