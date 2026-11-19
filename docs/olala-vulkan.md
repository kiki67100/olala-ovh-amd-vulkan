# Olala sur GPU AMD via Vulkan (Windows natif)

Branche `vulkan-olala`. Cible : AMD Radeon RX 6600 (RDNA2, 8 Go), Windows 11, pilote AMD.
Sous WSL2, la RX 6600 n'a pas de vrai pilote Vulkan : **les builds et l'exécution GPU se font en
natif Windows**, pilotés depuis WSL.

## Utilisation au quotidien

Depuis le terminal WSL (alias défini dans `~/.bashrc`) :

| Commande | Effet |
|---|---|
| `olala` | lance le chat sur le GPU (modèle q5_k_m) et ouvre http://localhost:7861 |
| `olala q8` | idem avec q8_0-safe2 (une partie des experts reste sur le CPU, voir plus bas) |
| `olala status` | indique ce qui tourne |
| `olala stop` | arrête la GUI et le llama-server Vulkan (après une fermeture brutale du terminal) |
| `Ctrl+C` | arrête tout proprement |

Sans WSL : double-cliquer `C:\olala\gui-vulkan\lancer.bat` (fermer la fenêtre pour arrêter ; si le
serveur reste en mémoire, `olala stop`).

Le modèle se change aussi depuis la liste déroulante de la GUI (le serveur est relancé).
L'API compatible OpenAI est sur `http://127.0.0.1:8081/v1` **côté Windows uniquement** (WSL en mode
NAT ne voit pas les ports Windows).

llama-server seul, dans un `cmd` Windows :

```bat
C:\olala\llama.cpp-olala-vulkan\build-vk\bin\llama-server.exe ^
  -m C:\olala\models\Olala-v1.0-mini-7A1B-q5_k_m.gguf -ngl 99 -fa on ^
  -ctk q8_0 -ctv q8_0 -c 32768 -np 1 --cache-reuse 256 ^
  --ctx-checkpoints 8 --cache-ram 1024 --host 127.0.0.1 --port 8081
```

Mémoire hôte : chaque *context checkpoint* copie l'état récurrent Mamba (≈ 60 Mio) ; avec les
valeurs par défaut (32 checkpoints par slot + cache de prompts de 8 Gio contenant aussi des
checkpoints), llama-server dépasse vite 15 Go de mémoire privée et épuise la mémoire virtuelle
(commit) de Windows quand WSL tourne aussi : `std::bad_alloc` (« bad allocation »), et le fichier
d'échange grossit sur un C: presque plein. D'où `--ctx-checkpoints 8 --cache-ram 1024` (GUI
comprise). Le serveur survit désormais à ce manque de mémoire (checkpoint abandonné, limite
abaissée, requête fautive en erreur) au lieu de planter sur
`GGML_ASSERT(batch.slot_batched || batch.size() == 0)`.

Ports : 7861 (GUI Vulkan) et 8081 (llama-server Vulkan). Les ports 7860/8080 sont réservés à la GUI
et au llama-server CPU de `~/olala` et ne sont jamais touchés.

## Configuration des chemins

Aucun chemin n'est écrit en dur : tout vient de `tools/olala-vulkan/config.sh`.

| Variable | Défaut | Rôle |
|---|---|---|
| `OLALA_WIN_ROOT` | `C:\olala` | dossier Windows : miroir + builds, `models\`, `gui-vulkan\`, `tmp\` |
| `OLALA_RESULTS` | `<parent du dépôt>/vk-tools/results` | résultats tests/bench |
| `OLALA_PY_W` | trouvé via `py.exe`, sinon `where python` | Python Windows utilisé par la GUI |
| `OLALA_MODEL` | `Olala-v1.0-mini-7A1B-q5_k_m.gguf` | modèle des tests/bench |
| `OLALA_LLAMA_SERVER`, `OLALA_MODELS_DIR`, `OLALA_CTX` | dérivés / 32768 | surcharges propres à la GUI (`app.py`) |

## Arborescence (valeurs par défaut)

| Emplacement | Rôle |
|---|---|
| `~/olala/llama.cpp-olala-vulkan` (WSL) | **clone principal**, on y édite et commite |
| `C:\olala\llama.cpp-olala-vulkan` | miroir Windows (remote = clone WSL) ; builds `build-vk`, `build-cpu` |
| `C:\olala\models\` | modèles q5_k_m et q8_0-safe2 |
| `C:\olala\gui-vulkan\` | GUI déployée (copiée depuis `tools/olala-vulkan/gui/` à chaque `olala`) |
| `tools/olala-vulkan/olala.sh` | lanceur (cible de l'alias `olala`) |
| `tools/olala-vulkan/gui/` | source de la GUI (Python stdlib, exécutée par le Python Windows) |
| `tools/olala-vulkan/vk-tools/` | scripts build / tests / bench Windows pilotés depuis WSL |
| `~/olala/vk-tools/results/` | résultats des tests et benchs (hors dépôt, volumineux) |
| `~/olala/llama.cpp-olala` | fork CPU **en production** : ne pas modifier ni recompiler |

## Rebuild et validation (depuis WSL)

Outils Windows installés : VS 2022 Build Tools (MSVC 14.44), CMake 4.4.4, Ninja 1.13.2,
Vulkan SDK 1.4.363 (`C:\VulkanSDK`). Les scripts injectent PATH/VULKAN_SDK eux-mêmes.

```bash
cd ~/olala/llama.cpp-olala-vulkan/tools/olala-vulkan/vk-tools
./win-build.sh vk            # synchronise le miroir sur origin/vulkan-olala (reset --hard) puis build
WIP=1 ./win-build.sh vk      # idem + modifications non commitées du clone WSL
./win-validate.sh            # build + test-backend-ops + e2e CPU vs Vulkan + logits + splits + bench
./win-test.sh ops:MAMBA3_MIMO:.   # une seule op
./win-bench.sh vk            # llama-bench -p 512 -n 128
```

**Arrêter la GUI (`olala stop`) avant un build** : `llama-server.exe` verrouille les DLL.

Options cmake : `-G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF
-DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=ON -DLLAMA_OPENSSL=OFF -DGGML_NATIVE=OFF -DGGML_AVX2=ON`.

Build Vulkan sous WSL (compilation et tests de justesse sans GPU, via lavapipe) :

```bash
export VULKAN_SDK=<dossier-du-SDK-LunarG>/x86_64 PATH=$VULKAN_SDK/bin:$PATH
cmake -B build-vk -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF -DCMAKE_BUILD_TYPE=Release \
      -DVulkan_LIBRARY=/usr/lib/x86_64-linux-gnu/libvulkan.so.1
cmake --build build-vk -j8
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json GGML_VK_VISIBLE_DEVICES=0 \
  build-vk/bin/test-backend-ops -b Vulkan0 -o MAMBA3_MIMO
```

## Ce qui a été porté

Le graphe Olala prend, sur un GPU non-Metal, le **chemin portable** de `src/models/olala.cpp`
(`OLALA_PORTABLE=1` le force sur CPU). Ce chemin n'atteint aucun `ggml_custom_4d` ni les ops
`OLALA_MOE / OLALA_MMV / OLALA_TPA_* / OLALA_DIFF_GATE` (utilisées seulement par les chemins CPU/Metal).

| Élément | Commit | Détail |
|---|---|---|
| `GGML_OP_MAMBA3_MIMO` (mode résultat) | 29ad69d01 | `mamba3_mimo.comp` : 1 workgroup de 256 threads par (tête, séquence), état f32 en registres, récurrence séquentielle. Le mode in-place reste CPU. |
| `GGML_OP_GEODESIC` | 29ad69d01 | `geodesic.comp` : 1 workgroup par ligne |
| Matmuls à précision imposée | 29ad69d01, 9c9225661 | le graphe pose un hint de précision (`op_params[3]`) car les activations montent à ~1e8. Vulkan l'ignorait et quantifiait src1 en q8_1 (échelles fp16) ou le passait en f16 → **NaN**. Ajout de pipelines matmul/matmul_id à shared memory fp32 ; plus de q8_1/f16 quand le hint est posé. |

Avant ces commits : 204 graph splits et sortie NaN (« ???? »). Après : 2 splits (seul le GET_ROWS
d'embedding reste sur CPU), pas de NaN.

## Résultats (RX 6600, q5_k_m, 2026-11-19)

| | CPU `-t 6 -fa 1` | Vulkan `-ngl 99 -fa 1` |
|---|---|---|
| pp512 (tok/s) | 145 – 169 | 436 |
| tg128 (tok/s) | 27 – 30 | 83 – 85 |
| VRAM (c=4096) | — | ≈ 6,0 – 6,1 Go |

Tests : `test-backend-ops -b Vulkan0` MAMBA3_MIMO + CACHE_FUSION 14/14, GEODESIC 4/4,
MUL_MAT amax=1e6 12/12, MUL_MAT_ID amax=1e5–1e6 12/12.

Justesse de bout en bout : l'écart Vulkan↔CPU sur les logits (relRMSE ≈ 6e-2, KL 2e-3 – 8e-3) est du
même ordre que l'écart CPU normal ↔ CPU `OLALA_PORTABLE=1` : le modèle amplifie le bruit flottant.
En greedy, le texte Vulkan est identique au CPU sur certains prompts et diverge sur d'autres au
niveau de quasi-égalités. Non expliqué : sur un prompt FR, `llama-completion` diverge dès le 1er
token alors que `olala-logits` donne le même argmax.

## Limites / suite

- Contexte long (pp4096, prompt de 12k) et VRAM à 32k non encore mesurés.
- `MAMBA3_MIMO` est séquentiel par (tête, séquence) : 48 workgroups seulement. Pour le prefill long,
  version par chunks à faire (cf. `ggml/src/ggml-cuda/mamba3-mimo.cu`).
- Devices avec coopmat (RDNA3+, NVIDIA, Intel) : pipelines fp32 non créés → matmuls à hint sur CPU.
- q8_0-safe2 (6,9 Go) ne tient pas entièrement dans 8 Go : `--fit on` garde une partie des experts sur CPU.
- Phase LM Studio (remplacement des DLL d'une copie du runtime) non tentée.
