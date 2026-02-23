# Runpod ComfyUI — CUDA 12.8 | SageAttention | Custom Nodes | Manifest Models

Image Docker RunPod tout-en-un pour ComfyUI, optimisée GPU avec CUDA 12.8.

## Fonctionnalités

- **CUDA 12.8** + **PyTorch cu128** + `torchvision` + `torchaudio` préinstallés
- **ComfyUI** + **ComfyUI-Manager** embarqués dans l'image
- **SageAttention & Triton** compilés au build (pas au runtime), activés par défaut via `--use-sage-attention`
- **`hf_transfer`** activé par défaut (`HF_HUB_ENABLE_HF_TRANSFER=1`) pour des téléchargements HuggingFace ultra-rapides
- **JupyterLab** (port 8888) avec token auto-généré si non défini (sécurité)
- **Persist mode** : ComfyUI copié dans `/workspace/ComfyUI` au premier boot (custom_nodes survivent aux redémarrages)
- **Symlinks** propres vers `/workspace/{ComfyUI,workflows,input,output}`
- **Manifest modèles** éditable à chaud (`/workspace/models_manifest.txt`) — HuggingFace + URLs directes
- **Manifest custom nodes** éditable à chaud (`/workspace/custom_nodes_manifest.txt`) — install auto au démarrage
- **HEALTHCHECK** Docker intégré (vérifie `/system_stats`)
- **CI/CD** GitHub Actions → push automatique sur Docker Hub au merge sur `main`

---

## Variables d'environnement (RunPod)

```bash
# Services
ENABLE_JUPYTER=true
JUPYTER_PORT=8888
JUPYTER_TOKEN=          # auto-généré si vide (noté dans les logs au boot)

# ComfyUI
COMFY_AUTOSTART=true
COMFY_PORT=8188
COMFY_ARGS=--listen 0.0.0.0 --port 8188 --use-sage-attention
COMFY_ARGS_EXTRA=       # flags additionnels sans écraser les défauts (ex: --lowvram)

# Chemins
DATA_DIR=/workspace
COMFY_DIR=/opt/ComfyUI
MODELS_DIR=/workspace/models
MODELS_MANIFEST=/workspace/models_manifest.txt
CUSTOM_NODES_MANIFEST=/workspace/custom_nodes_manifest.txt

# Téléchargements
DL_WORKERS=4            # workers parallèles pour le téléchargement des modèles
HF_TOKEN=               # token HuggingFace pour les modèles privés/gatés
HF_HUB_ENABLE_HF_TRANSFER=1

# Cache pip
PIP_CACHE_DIR=/workspace/.pip-cache
PIP_NO_CACHE_DIR=0

# Persist
COMFY_PERSIST=true      # false = mode image (plus rapide, mais sans persistance)
```

---

## Quick Start

1. **Lance le pod** → JupyterLab et ComfyUI démarrent automatiquement (SageAttention actif)
2. **Note le `JUPYTER_TOKEN`** affiché dans les logs au boot (ou fixe-le en variable d'env)
3. **Édite les manifests** dans `/workspace/` :
   - `models_manifest.txt` pour les modèles
   - `custom_nodes_manifest.txt` pour les custom nodes
4. **`pull-models --sync`** pour forcer le téléchargement des modèles immédiatement
5. **Rafraîchis l'UI ComfyUI** après installation de nouveaux nodes

---

## Commandes disponibles dans le pod

### Modèles

```bash
# Télécharger les modèles du manifest (async par défaut)
pull-models
pull-models --sync                    # attend la fin
pull-models --workers 8               # plus de parallélisme
pull-models --status                  # voir les 120 dernières lignes de log
pull-models --manifest /path/to/other.txt
```

### Custom Nodes

```bash
# Installer les nodes du manifest (fait automatiquement au boot)
bash /scripts/install_custom_nodes.sh

# Lister l'état des nodes définis dans le manifest
bash /scripts/install_custom_nodes.sh --list

# Mettre à jour tous les nodes installés
bash /scripts/install_custom_nodes.sh --update
```

### ComfyUI

```bash
comfy-status          # état global : processus, ports, modèles, nodes, logs
comfy-save            # snapshot git de /workspace/ComfyUI (commit WIP)
comfy-update          # mise à jour depuis upstream comfyanonymous/ComfyUI
comfy-reset           # réinitialise ComfyUI depuis le seed image (avec backup)
comfy-replay          # rej rejoue /workspace/post_start.sh manuellement
comfy-notes "cmd"     # ajoute une commande dans post_start.sh (exécuté au boot)
```

---

## Format des manifests

### `models_manifest.txt`

```
# Format: repo_hf|chemin_dans_repo|sous_dossier_models
Kijai/WanVideo_comfy|umt5-xxl-enc-bf16.safetensors|clip

# Format URL directe (aria2c si disponible, sinon curl)
https://example.com/model.safetensors|model.safetensors|checkpoints
```

### `custom_nodes_manifest.txt`

```
# Format: git_url|branch  (branch optionnel, défaut: main)
https://github.com/kijai/ComfyUI-KJNodes|main
https://github.com/cubiq/ComfyUI_IPAdapter_plus
```

---

## `comfy-notes` — Post-start hooks

`comfy-notes` permet d'ajouter des commandes dans `/workspace/post_start.sh` qui s'exécutent à chaque boot :

```bash
# Exemple : installer un package une seule fois (idempotent via once())
comfy-notes 'once insightface pip install insightface onnxruntime'

# Exemple : créer un symlink
comfy-notes 'safe_link /workspace/models/custom /opt/custom'
```

Le fichier généré contient les helpers `once()` (avec stamps) et `safe_link()` prêts à l'emploi.

---

## CI/CD — GitHub Actions

Chaque push sur `main` déclenche un build `linux/amd64` et un push vers :
`docker.io/mauricebourdondock/comfyui-cu128`

Tags générés automatiquement : `latest`, `runpod-amd64`, `v{run_number}`, `{sha:7}`

Secrets GitHub requis : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

---

## Structure du projet

```
├── Dockerfile
├── .github/workflows/docker-build.yml
├── scripts/
│   ├── entrypoint.sh              # bootstrap complet du pod
│   ├── download_models_async.sh   # lanceur async du worker Python
│   ├── download_models_worker.py  # téléchargement parallèle (HF + URL)
│   └── install_custom_nodes.sh    # installation des custom nodes
├── bin/
│   ├── start-comfyui              # lance ComfyUI (COMFY_ARGS + COMFY_ARGS_EXTRA)
│   ├── start-jupyter              # lance JupyterLab
│   ├── pull-models                # gestion téléchargements modèles
│   ├── comfy-status               # tableau de bord (processus, ports, modèles)
│   ├── comfy-save                 # snapshot git du workspace
│   ├── comfy-reset                # réinitialisation depuis l'image seed
│   ├── comfy-update               # mise à jour depuis upstream
│   ├── comfy-replay               # rejoue post_start.sh
│   └── comfy-notes                # édition de post_start.sh
└── manifests/
    ├── models_manifest.txt        # modèles HF / URL à télécharger
    ├── custom_nodes_manifest.txt  # custom nodes git à installer
    └── post_start.d/
        └── 10-sageattention.sh    # rebuild optionnel de SageAttention
```
