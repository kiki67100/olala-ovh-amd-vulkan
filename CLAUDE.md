IMPORTANT: Ensure you’ve thoroughly reviewed the [AGENTS.md](AGENTS.md) file before beginning any work.

# Fork Olala — branche `vulkan-olala` (portage Vulkan, AMD RX 6600)

Réponds en français. Doc complète : [docs/olala-vulkan.md](docs/olala-vulkan.md) (aussi `docs/olala*.md`).

## Règles
- **Ne jamais modifier ni recompiler `~/olala/llama.cpp-olala`** : fork CPU en production.
- **Ports 7860/8080 interdits** (GUI + llama-server CPU en service) ; Vulkan utilise 7861 (GUI) et 8081.
- Ne pas toucher au dossier LM Studio (`%USERPROFILE%\.lmstudio`). Demander avant toute installation sous Windows.
- Commits locaux sur `vulkan-olala`, **pas de push** sans accord. Pas d'identité git configurée :
  `git -c user.name=... -c user.email=...`.
- Disque C: presque plein (~10 Go libres) : pas de copies ni de builds superflus.
- Un shader n'est « fini » qu'avec `test-backend-ops -b Vulkan0` OK **et** une validation de bout en
  bout contre le CPU (greedy + `olala-logits`) ; rapporter les chiffres réels.

## Environnement
- WSL2 ne voit pas la RX 6600 (pas de pilote) → build/exécution GPU en natif Windows via
  `tools/olala-vulkan/vk-tools/win-*.sh` (miroir `%OLALA_WIN_ROOT%\llama.cpp-olala-vulkan`, défaut
  `C:\olala`, remis à
  `origin/vulkan-olala` à chaque build ; `WIP=1` pour inclure le non-commité).
- Tous les chemins viennent de `tools/olala-vulkan/config.sh` (variables `OLALA_*`) : ne jamais
  écrire de chemin personnel en dur ; vérifier `olala status` et `win-build.sh` après modification.
- WSL (mode NAT) ne joint pas les ports Windows : interroger 8081/7861 via `powershell.exe`.
- Tests de justesse Vulkan possibles sous WSL avec lavapipe (voir la doc), sans GPU.
- Arrêter la GUI (`olala stop`) avant un build Windows (DLL verrouillées).

## Code
- Graphe : `src/models/olala.cpp`. Sur Vulkan, chemin **portable** (`OLALA_PORTABLE=1` pour le
  reproduire sur CPU). Ne pas changer les chemins CPU/Metal.
- Ops Vulkan ajoutées : `MAMBA3_MIMO`, `GEODESIC` (`ggml/src/ggml-vulkan/vulkan-shaders/*.comp`,
  `ggml-vulkan.cpp`) + matmuls fp32 quand le graphe pose un hint de précision (activations ~1e8 :
  q8_1/f16 → NaN). États récurrents et accumulations toujours en f32.
- Vérité terrain : `ggml/src/ggml-cpu/ops.cpp` ; références de découpage : `ggml-cuda/mamba3-mimo.cu`,
  `ggml-metal/kernels/mamba3.metal`. Tests : `tests/test-backend-ops.cpp` (`test_mamba3_mimo`…).
- Le modèle amplifie le bruit flottant : comparer Vulkan↔CPU au bruit CPU↔`OLALA_PORTABLE=1`,
  pas à zéro.
