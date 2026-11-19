# Olala (OVHai) on AMD GPUs with Vulkan — llama.cpp fork

**Run the French LLM Olala-v1.0-mini-7A1B on an AMD Radeon GPU, without CUDA or ROCm.**
Vulkan backend for llama.cpp, tested on an RX 6600 (8 GB) under Windows 11: **~3× faster than the CPU**,
with an OpenAI-compatible server that works with coding agents such as opencode.

**Faire tourner le LLM français Olala-v1.0-mini-7A1B sur une carte graphique AMD Radeon, sans CUDA ni ROCm.**
Backend Vulkan pour llama.cpp, testé sur une RX 6600 (8 Go) sous Windows 11 : **environ 3× plus rapide que
le CPU**, avec un serveur compatible OpenAI qui fonctionne avec des agents de code comme opencode.

**[English](#english)** · **[Français](#français)**

> Keywords / mots-clés : Olala, Olala 7A1B, OVHai, OVH, French LLM, LLM français, AMD, Radeon, RX 6600,
> RDNA2, Vulkan, llama.cpp, GGUF, llama-server, Windows, Mamba3, MoE, local LLM, IA locale, opencode.

Unofficial community port, not affiliated with OVHai. / Portage communautaire non officiel, sans lien avec
OVHai. The original llama.cpp README is in / le README d'origine de llama.cpp est dans
[README-llama.cpp.md](README-llama.cpp.md).

---

<a id="english"></a>
## English

### What this is

The Olala fork of llama.cpp ([OVHai-LLM/llama.cpp](https://github.com/OVHai-LLM/llama.cpp)) supports the
model on CPU, Apple Metal and NVIDIA CUDA. On Vulkan, the model loaded but produced only `NaN`
(`????` output) and constantly bounced between CPU and GPU (204 graph splits).

This branch (`vulkan-olala`) makes it run **fully on the GPU through Vulkan**, which works on AMD
cards (and in principle on any Vulkan 1.3 GPU) without CUDA or ROCm.

### Results (RX 6600, `q5_k_m`, `llama-bench -p 512 -n 128`)

| | CPU (Ryzen 5 5600, 6 threads) | Vulkan (RX 6600, `-ngl 99`) |
|---|---|---|
| Prompt processing (pp512) | 145 – 169 tok/s | **436 tok/s** |
| Generation (tg128) | 27 – 30 tok/s | **83 – 85 tok/s** |
| Graph splits | — | 2 (only the embedding lookup stays on CPU) |
| VRAM (4k context) | — | ≈ 6.0 – 6.1 GB |

- **No NaN.** The Olala tests in `test-backend-ops` pass on the GPU (details below).
- **Outputs vs CPU:** the logit difference between Vulkan and CPU is of the same order as the
  difference between two CPU code paths of the fork. This model amplifies floating-point noise, so
  greedy (`--temp 0`) text is sometimes identical to the CPU output and sometimes diverges at a
  near-tie token. More detail under *Known limitations*.
- **`q8_0-safe2` also works** on the 8 GB card: 48.6 tok/s generation (one short reply measured, no full
  benchmark), same top-1 token as the CPU on 28/28 and 101/101 positions, no NaN. With a 32k context,
  `--fit on` keeps part of it on the CPU.
- **Coding agents:** the 3 opencode test tasks (read a file, create and run a script, fix a bug) pass
  on the GPU server.

### What was changed

On a non-Metal GPU, the model graph (`src/models/olala.cpp`) uses the fork's **portable path**. That path
only needs two model-specific ops plus standard ggml ops. The work:

| Change | Files |
|---|---|
| Vulkan shader for `GGML_OP_MAMBA3_MIMO`: one 256-thread workgroup per (head, sequence), recurrent state in f32 | `ggml/src/ggml-vulkan/vulkan-shaders/mamba3_mimo.comp` |
| Vulkan shader for `GGML_OP_GEODESIC` (geodesic-rotation residual) | `ggml/src/ggml-vulkan/vulkan-shaders/geodesic.comp` |
| **Precision fix**, see below | `ggml/src/ggml-vulkan/ggml-vulkan.cpp` |
| New test cases (long sequences, several sequences, very large activations) | `tests/test-backend-ops.cpp` |

**The precision fix:**
- The Olala graph marks some quantized matmuls as "needs high precision", because activations reach
  ~1e8.
- Vulkan ignored that marker. It converted the activations to `q8_1` (fp16 scales) or `f16`, which
  overflows and causes the NaNs.
- These matmuls (`MUL_MAT` and `MUL_MAT_ID`) now keep their activations in **fp32** on GPUs without
  cooperative matrices (fp32 shared-memory pipelines).

The CPU, Metal and CUDA paths are unchanged.

**llama-server fixes** (these affect every backend, CPU included):
- **Unique tool-call ids** (`common/chat.h`). The Olala chat template numbers tool calls `call_0`,
  `call_1`… again in every turn. The server now always generates its own unique ids; without this,
  opencode v2 stops with `Duplicate tool input start: call_0`.
- **No crash when host memory runs out** (`tools/server/server-context.cpp`, `server-task.cpp`).
  - On this hybrid model, every context checkpoint copies the Mamba state (~60 MB). With the defaults
    (32 checkpoints, 8 GB prompt cache), memory grew from 7 to 17 GB over a few long conversations.
  - Before, a failed allocation then killed the process on
    `GGML_ASSERT(batch.slot_batched || batch.size() == 0)`. Now the checkpoint is skipped and the server
    keeps running.
  - Recommended options: `--ctx-checkpoints 8 --cache-ram 1024`.

### Requirements

- A GPU with a Vulkan 1.3 driver (tested: RX 6600, AMD driver 26.10.1).
- 8 GB VRAM is enough for `q5_k_m` with a 32k context.
- Windows build: **Visual Studio 2022 Build Tools** (workload *Desktop development with C++*),
  **CMake**, **Ninja**, **Vulkan SDK** (provides `glslc`):

  ```powershell
  winget install Kitware.CMake Ninja-build.Ninja KhronosGroup.VulkanSDK
  winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ```

- Linux build: a C++17 compiler, CMake, the Vulkan SDK (or `glslc` + `libvulkan-dev`).
- The model in GGUF format, e.g. `Olala-v1.0-mini-7A1B-q5_k_m.gguf`. For conversion and quantization,
  see [docs/olala.md](docs/olala.md).

> **WSL2 note:** WSL does not see AMD GPUs through Vulkan (at best the slow `dzn` layer). Build and run
> natively on Windows.

### Build

**Windows**: open *x64 Native Tools Command Prompt for VS 2022*, then:

```bat
git clone -b vulkan-olala https://gitlab.com/kiki67100/olala-ovh-amd-vulkan.git llama.cpp-olala-vulkan
cd llama.cpp-olala-vulkan
cmake -B build-vk -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_OPENSSL=OFF
cmake --build build-vk
```

**Linux**:

```bash
cmake -B build-vk -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF
cmake --build build-vk -j
```

Binaries are in `build-vk/bin/`. Add `-DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=ON` for
`test-backend-ops` and `olala-logits`.

### Run

OpenAI-compatible server (Windows; on Linux drop the `.exe` and use `\` for line continuation):

```bat
build-vk\bin\llama-server.exe -m Olala-v1.0-mini-7A1B-q5_k_m.gguf -ngl 99 -fa on ^
  -ctk q8_0 -ctv q8_0 -c 32768 --ctx-checkpoints 8 --cache-ram 1024 --host 127.0.0.1 --port 8081
```

Then use `http://127.0.0.1:8081/v1` from any OpenAI-compatible client.

- **No built-in web UI**: the build uses `LLAMA_USE_PREBUILT_UI=OFF`, so the server's root page
  returns 404. Use the chat GUI below or an API client.
- **Interactive chat**: `build-vk\bin\llama-cli.exe -m <model> -ngl 99 -fa on -c 8192`
- **Benchmark**: `build-vk\bin\llama-bench.exe -m <model> -ngl 99 -fa 1 -p 512 -n 128`
- **Models larger than VRAM** (e.g. `q8_0`, 6.9 GB on an 8 GB card): replace `-ngl 99` with `--fit on`.
  llama.cpp then keeps part of the MoE experts on the CPU (slower).

### Chat GUI (optional)

`tools/olala-vulkan/gui/` holds a small chat page served by a Python script that uses only the
standard library. It starts `llama-server`, offers a model selector, a reasoning-effort setting,
Markdown rendering with syntax highlighting, and token and speed statistics.

```bat
python tools\olala-vulkan\gui\app.py --open
```

It serves `http://localhost:7861` and starts `llama-server` on port 8081. By default it expects
`C:\olala\llama.cpp-olala-vulkan\build-vk\bin\llama-server.exe` and the models in `C:\olala\models\`.
Override with `OLALA_WIN_ROOT`, `OLALA_LLAMA_SERVER` or `OLALA_MODELS_DIR`.
On Windows, `tools\olala-vulkan\gui\lancer.bat` does the same with a double-click.

### Validate

Each new op is checked against the CPU backend (normalized mean squared error, NMSE):

```bat
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MAMBA3_MIMO
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o GEODESIC
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MUL_MAT -p "amax=1000000"
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MUL_MAT_ID -p "amax=(1000000|100000)\."
```

Results on the RX 6600:

| Tests | Passed |
|---|---|
| `MAMBA3_MIMO` + `MAMBA3_MIMO_CACHE_FUSION` | 14/14 |
| `GEODESIC` | 4/4 |
| `MUL_MAT` with very large activations | 12/12 |
| `MUL_MAT_ID` with very large activations | 12/12 |

**End to end:**
- `examples/olala-logits` dumps per-token logits. Compare a CPU run against a Vulkan run.
- `OLALA_PORTABLE=1` forces the portable path on the CPU, i.e. the same graph Vulkan executes. Use it
  to measure the noise floor.

**Without a GPU (Linux/WSL):** correctness tests run on Mesa's software Vulkan driver (lavapipe):

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json GGML_VK_VISIBLE_DEVICES=0 \
  build-vk/bin/test-backend-ops -b Vulkan0 -o MAMBA3_MIMO
```

### Windows-from-WSL helpers (author's setup)

`tools/olala-vulkan/olala.sh` and `tools/olala-vulkan/vk-tools/` drive native Windows builds, tests and
the GUI from a WSL terminal:
- `olala`, `olala q8`, `olala stop` and `olala status` to run the chat;
- `win-build.sh`, `win-test.sh`, `win-bench.sh` and `win-validate.sh` to build, test and benchmark.

No path is hard-coded. Everything comes from `tools/olala-vulkan/config.sh`:
- `OLALA_WIN_ROOT` (default `C:\olala`): Windows working folder (mirror + builds, `models\`, `gui-vulkan\`);
- `OLALA_PY_W`: Windows Python, found automatically through `py.exe`;
- `OLALA_RESULTS`: test and benchmark results;
- `OLALA_MODEL`: model used by tests and benchmarks.

Full walkthrough: [docs/olala-vulkan.md](docs/olala-vulkan.md) (French).

### Known limitations

- **`MAMBA3_MIMO` is sequential over tokens** inside one workgroup per (head, sequence). Long prompts
  are therefore not optimal; a chunked version like the CUDA kernel is the next step.
- **Not yet measured:** throughput at long context (4k–12k prompts) and VRAM at 32k.
- **GPUs with cooperative matrices** (RDNA3+, recent NVIDIA, Intel Arc): the fp32 pipelines are not
  created there. The high-precision matmuls then fall back to the CPU: correct but slow.
- **Fork-only ops not ported:** `OLALA_MOE`, `OLALA_MMV`, `OLALA_TPA_*` and `OLALA_DIFF_GATE`. The
  portable path does not use them. They would only be speed optimizations.
- **Unexplained divergence:** on one French prompt, greedy generation differs from the CPU from the
  first token, while `olala-logits` gives the same top-1 token. Not investigated yet.
- **`q8_0`** on 8 GB cards: works, but slower than `q5_k_m` (about 49 vs 80 tok/s).

### Documentation

| File | Content |
|---|---|
| [docs/olala.md](docs/olala.md) | architecture, conversion, quantization, usage |
| [docs/olala-setup.md](docs/olala-setup.md) | setup per hardware (CPU, Mac, NVIDIA) |
| [docs/olala-vulkan.md](docs/olala-vulkan.md) | Vulkan port: build, validation, results (FR) |
| [docs/olala-metal-testing.md](docs/olala-metal-testing.md) | Metal validation checklist |

### More projects

Other Olala tools and projects by the same author: **https://gitlab.com/kiki67100**

### License

MIT, like llama.cpp: see [LICENSE](LICENSE). Based on [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
and the Olala fork [OVHai-LLM/llama.cpp](https://github.com/OVHai-LLM/llama.cpp). The model weights are
not included and are covered by their own license.

---

<a id="français"></a>
## Français

### De quoi s'agit-il

Le fork Olala de llama.cpp ([OVHai-LLM/llama.cpp](https://github.com/OVHai-LLM/llama.cpp)) fait tourner le
modèle sur CPU, Apple Metal et NVIDIA CUDA. Avec le backend Vulkan, le modèle se chargeait mais ne
produisait que des `NaN` (sortie `????`) et faisait sans cesse des allers-retours entre CPU et GPU
(204 *graph splits*).

Cette branche (`vulkan-olala`) le fait tourner **entièrement sur le GPU via Vulkan**. Ça marche sur les
cartes AMD (et en principe sur tout GPU Vulkan 1.3), sans CUDA ni ROCm.

### Résultats (RX 6600, `q5_k_m`, `llama-bench -p 512 -n 128`)

| | CPU (Ryzen 5 5600, 6 threads) | Vulkan (RX 6600, `-ngl 99`) |
|---|---|---|
| Lecture du prompt (pp512) | 145 – 169 tok/s | **436 tok/s** |
| Génération (tg128) | 27 – 30 tok/s | **83 – 85 tok/s** |
| *Graph splits* | — | 2 (seul l'embedding reste sur CPU) |
| VRAM (contexte 4k) | — | ≈ 6,0 – 6,1 Go |

- **Aucun NaN.** Les tests Olala de `test-backend-ops` passent sur le GPU (détails plus bas).
- **Sorties comparées au CPU :** l'écart de logits entre Vulkan et le CPU est du même ordre que l'écart
  entre deux chemins de calcul CPU du fork. Ce modèle amplifie le bruit flottant : en greedy
  (`--temp 0`), le texte est tantôt identique au CPU, tantôt il diverge sur un token presque à égalité.
  Voir *Limites connues*.
- **Le `q8_0-safe2` fonctionne aussi** sur la carte de 8 Go : 48,6 tok/s en génération (une seule réponse
  courte mesurée, pas de bench complet), même token en tête que le CPU sur 28/28 et 101/101 positions,
  aucun NaN. Avec 32k de contexte, `--fit on` en garde une partie sur le CPU.
- **Agents de code :** les 3 tâches de test opencode (lire un fichier, créer et exécuter un script, corriger
  un bug) passent sur le serveur GPU.

### Ce qui a été modifié

Sur un GPU non-Metal, le graphe du modèle (`src/models/olala.cpp`) emprunte le **chemin portable** du fork.
Ce chemin n'a besoin que de deux ops propres au modèle, plus des ops ggml standard. Le travail :

| Modification | Fichiers |
|---|---|
| Shader Vulkan de `GGML_OP_MAMBA3_MIMO` : un workgroup de 256 threads par (tête, séquence), état récurrent en f32 | `ggml/src/ggml-vulkan/vulkan-shaders/mamba3_mimo.comp` |
| Shader Vulkan de `GGML_OP_GEODESIC` (résiduel par rotation géodésique) | `ggml/src/ggml-vulkan/vulkan-shaders/geodesic.comp` |
| **Correctif de précision**, voir ci-dessous | `ggml/src/ggml-vulkan/ggml-vulkan.cpp` |
| Nouveaux cas de test (séquences longues, plusieurs séquences, activations très grandes) | `tests/test-backend-ops.cpp` |

**Le correctif de précision :**
- Le graphe Olala marque certaines multiplications de matrices quantifiées comme « précision élevée
  requise », car les activations montent jusqu'à environ 1e8.
- Vulkan ignorait ce marqueur. Il convertissait les activations en `q8_1` (échelles fp16) ou en `f16`,
  ce qui déborde et produit les NaN.
- Ces multiplications (`MUL_MAT` et `MUL_MAT_ID`) gardent désormais leurs activations en **fp32** sur les
  GPU sans matrices coopératives (pipelines avec mémoire partagée fp32).

Les chemins CPU, Metal et CUDA ne changent pas.

**Correctifs de llama-server** (ils concernent tous les backends, CPU compris) :
- **Identifiants d'appels d'outils uniques** (`common/chat.h`). Le template de chat Olala renumérote les
  appels `call_0`, `call_1`… à chaque tour. Le serveur génère maintenant toujours ses propres identifiants
  uniques ; sans ça, opencode v2 s'arrête sur `Duplicate tool input start: call_0`.
- **Plus de plantage quand la mémoire de l'hôte s'épuise** (`tools/server/server-context.cpp`,
  `server-task.cpp`).
  - Sur ce modèle hybride, chaque point de sauvegarde de contexte copie l'état Mamba (environ 60 Mo).
    Avec les valeurs par défaut (32 points, 8 Go de cache de prompts), la mémoire passait de 7 à 17 Go
    en quelques longues conversations.
  - Avant, une allocation ratée tuait alors le processus sur
    `GGML_ASSERT(batch.slot_batched || batch.size() == 0)`. Maintenant le point de sauvegarde est sauté
    et le serveur continue.
  - Options recommandées : `--ctx-checkpoints 8 --cache-ram 1024`.

### Prérequis

- Un GPU avec un pilote Vulkan 1.3 (testé : RX 6600, pilote AMD 26.10.1).
- 8 Go de VRAM suffisent pour le `q5_k_m` avec 32k de contexte.
- Build Windows : **Visual Studio 2022 Build Tools** (charge « Développement Desktop en C++ »),
  **CMake**, **Ninja**, **Vulkan SDK** (fournit `glslc`) :

  ```powershell
  winget install Kitware.CMake Ninja-build.Ninja KhronosGroup.VulkanSDK
  winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ```

- Build Linux : un compilateur C++17, CMake, le Vulkan SDK (ou `glslc` + `libvulkan-dev`).
- Le modèle au format GGUF, par exemple `Olala-v1.0-mini-7A1B-q5_k_m.gguf`. Pour la conversion et la
  quantification, voir [docs/olala.md](docs/olala.md).

> **WSL2 :** WSL ne voit pas les GPU AMD via Vulkan (au mieux la couche lente `dzn`). Compilez et
> lancez en natif sous Windows.

### Compilation

**Windows** : ouvrir *x64 Native Tools Command Prompt for VS 2022*, puis :

```bat
git clone -b vulkan-olala https://gitlab.com/kiki67100/olala-ovh-amd-vulkan.git llama.cpp-olala-vulkan
cd llama.cpp-olala-vulkan
cmake -B build-vk -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_OPENSSL=OFF
cmake --build build-vk
```

**Linux** :

```bash
cmake -B build-vk -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_USE_PREBUILT_UI=OFF
cmake --build build-vk -j
```

Les binaires sont dans `build-vk/bin/`. Ajouter `-DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=ON`
pour obtenir `test-backend-ops` et `olala-logits`.

### Lancement

Serveur compatible OpenAI (Windows ; sous Linux, retirer `.exe` et utiliser `\` en fin de ligne) :

```bat
build-vk\bin\llama-server.exe -m Olala-v1.0-mini-7A1B-q5_k_m.gguf -ngl 99 -fa on ^
  -ctk q8_0 -ctv q8_0 -c 32768 --ctx-checkpoints 8 --cache-ram 1024 --host 127.0.0.1 --port 8081
```

Utiliser ensuite `http://127.0.0.1:8081/v1` depuis n'importe quel client compatible OpenAI.

- **Pas d'interface web intégrée** : le build utilise `LLAMA_USE_PREBUILT_UI=OFF`, la page d'accueil du
  serveur renvoie donc 404. Utiliser la GUI de chat ci-dessous ou un client API.
- **Chat en terminal** : `build-vk\bin\llama-cli.exe -m <modèle> -ngl 99 -fa on -c 8192`
- **Benchmark** : `build-vk\bin\llama-bench.exe -m <modèle> -ngl 99 -fa 1 -p 512 -n 128`
- **Modèles plus gros que la VRAM** (par exemple `q8_0`, 6,9 Go sur une carte de 8 Go) : remplacer
  `-ngl 99` par `--fit on`. llama.cpp garde alors une partie des experts MoE sur le CPU (plus lent).

### GUI de chat (optionnelle)

`tools/olala-vulkan/gui/` contient une petite page de chat servie par un script Python qui n'utilise que la
bibliothèque standard. Elle lance `llama-server` et propose un choix du modèle, un réglage de l'effort de
réflexion, un rendu Markdown avec coloration du code, et des statistiques de tokens et de vitesse.

```bat
python tools\olala-vulkan\gui\app.py --open
```

Elle sert `http://localhost:7861` et lance `llama-server` sur le port 8081. Par défaut, elle attend
`C:\olala\llama.cpp-olala-vulkan\build-vk\bin\llama-server.exe` et les modèles dans `C:\olala\models\`.
Surcharger avec `OLALA_WIN_ROOT`, `OLALA_LLAMA_SERVER` ou `OLALA_MODELS_DIR`.
Sous Windows, `tools\olala-vulkan\gui\lancer.bat` fait la même chose en double-cliquant.

### Validation

Chaque op ajoutée est comparée au backend CPU (erreur quadratique moyenne normalisée, NMSE) :

```bat
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MAMBA3_MIMO
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o GEODESIC
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MUL_MAT -p "amax=1000000"
build-vk\bin\test-backend-ops.exe -b Vulkan0 -o MUL_MAT_ID -p "amax=(1000000|100000)\."
```

Résultats sur la RX 6600 :

| Tests | Réussis |
|---|---|
| `MAMBA3_MIMO` + `MAMBA3_MIMO_CACHE_FUSION` | 14/14 |
| `GEODESIC` | 4/4 |
| `MUL_MAT` avec activations très grandes | 12/12 |
| `MUL_MAT_ID` avec activations très grandes | 12/12 |

**De bout en bout :**
- `examples/olala-logits` écrit les logits de chaque token. Comparer une exécution CPU et une exécution
  Vulkan.
- `OLALA_PORTABLE=1` force le chemin portable sur le CPU, c'est-à-dire le même graphe que Vulkan.
  S'en servir pour mesurer le bruit de fond.

**Sans GPU (Linux/WSL) :** les tests de justesse tournent sur le pilote Vulkan logiciel de Mesa
(lavapipe) :

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json GGML_VK_VISIBLE_DEVICES=0 \
  build-vk/bin/test-backend-ops -b Vulkan0 -o MAMBA3_MIMO
```

### Outils Windows pilotés depuis WSL (config de l'auteur)

`tools/olala-vulkan/olala.sh` et `tools/olala-vulkan/vk-tools/` pilotent depuis un terminal WSL les builds,
les tests et la GUI en natif Windows :
- `olala`, `olala q8`, `olala stop` et `olala status` pour le chat ;
- `win-build.sh`, `win-test.sh`, `win-bench.sh` et `win-validate.sh` pour compiler, tester et mesurer.

Aucun chemin n'est écrit en dur. Tout vient de `tools/olala-vulkan/config.sh` :
- `OLALA_WIN_ROOT` (défaut `C:\olala`) : dossier de travail Windows (miroir + builds, `models\`, `gui-vulkan\`) ;
- `OLALA_PY_W` : Python Windows, trouvé automatiquement via `py.exe` ;
- `OLALA_RESULTS` : résultats des tests et benchs ;
- `OLALA_MODEL` : modèle utilisé par les tests et benchs.

Guide complet : [docs/olala-vulkan.md](docs/olala-vulkan.md).

### Limites connues

- **`MAMBA3_MIMO` traite les tokens un par un**, dans un seul workgroup par (tête, séquence). Les longs
  prompts ne sont donc pas optimaux ; la prochaine étape est une version par blocs, comme le noyau CUDA.
- **Pas encore mesuré :** le débit en contexte long (prompts de 4k à 12k) et la VRAM à 32k.
- **GPU avec matrices coopératives** (RDNA3+, NVIDIA récents, Intel Arc) : les pipelines fp32 n'y sont pas
  créés. Les multiplications « précision élevée » retombent alors sur le CPU : correct mais lent.
- **Ops propres au fork non portées :** `OLALA_MOE`, `OLALA_MMV`, `OLALA_TPA_*` et `OLALA_DIFF_GATE`.
  Le chemin portable ne s'en sert pas : ce ne seraient que des optimisations de vitesse.
- **Divergence non expliquée :** sur un prompt en français, la génération greedy diffère du CPU dès le
  premier token, alors que `olala-logits` donne le même token en tête. Pas encore étudié.
- **`q8_0`** sur une carte de 8 Go : fonctionne, mais plus lent que le `q5_k_m` (environ 49 contre 80 tok/s).

### Documentation

| Fichier | Contenu |
|---|---|
| [docs/olala.md](docs/olala.md) | architecture, conversion, quantification, usage |
| [docs/olala-setup.md](docs/olala-setup.md) | installation selon le matériel (CPU, Mac, NVIDIA) |
| [docs/olala-vulkan.md](docs/olala-vulkan.md) | portage Vulkan : build, validation, résultats |
| [docs/olala-metal-testing.md](docs/olala-metal-testing.md) | check-list de validation Metal |

### Autres projets

Les autres outils et projets Olala du même auteur : **https://gitlab.com/kiki67100**

### Licence

MIT, comme llama.cpp : voir [LICENSE](LICENSE). Basé sur [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
et sur le fork Olala [OVHai-LLM/llama.cpp](https://github.com/OVHai-LLM/llama.cpp). Les poids du modèle ne sont
pas inclus et relèvent de leur propre licence.
