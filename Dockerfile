FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash git git-lfs curl ca-certificates ffmpeg openssl \
    python3 python3-venv python3-pip \
    tini libgl1 libglib2.0-0 jq rsync aria2 iproute2 \
    build-essential ninja-build python3-dev \
 && git lfs install \
 && rm -rf /var/lib/apt/lists/*

# Python venv + PyTorch cu128 + torchvision + torchaudio
RUN python3 -m venv /venv \
 && /venv/bin/pip install -U pip setuptools wheel packaging \
 && /venv/bin/pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu128 \
    torch torchvision torchaudio \
 && /venv/bin/pip install --no-cache-dir \
    jupyterlab==4.2.5 \
    "huggingface-hub[hf_transfer]==0.28.1" \
    hf_transfer \
    safetensors==0.4.5 \
    pyyaml tqdm

# SageAttention 2.2.0 — compilé pour Ampere/Ada/Hopper/Blackwell
# Triton est déjà installé par PyTorch comme dépendance — pas besoin de le réinstaller.
# FORCE_CUDA=1    → force la compilation même sans GPU présent (CI/CD)
# Image devel     → fournit NVCC + headers CUDA nécessaires à la compilation
# Placé AVANT ComfyUI pour ne PAS être invalidé quand COMFYUI_CACHEBUST change.
RUN /venv/bin/pip install --no-cache-dir ninja \
 && FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0;12.0" \
    /venv/bin/pip install --no-cache-dir --no-binary=:all: "sageattention==2.2.0"

# ── ComfyUI (layer invalidable indépendamment) ─────────────────────────────────
# Passer --build-arg COMFYUI_CACHEBUST=$(date +%Y%m%d) en CI pour forcer un
# clone frais SANS reconstruire SageAttention (layer précédent reste en cache).
ARG COMFYUI_CACHEBUST=1

# ComfyUI + requirements
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && /venv/bin/pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt

# ComfyUI-Manager est intégré nativement depuis déc. 2025 — activé via --enable-manager
# Plus besoin de git clone séparé.

# Scripts + manifests + helper binaries
COPY scripts/entrypoint.sh             /entrypoint.sh
COPY scripts/download_models_async.sh  /scripts/download_models_async.sh
COPY scripts/download_models_worker.py /scripts/download_models_worker.py
COPY scripts/install_custom_nodes.sh   /scripts/install_custom_nodes.sh
COPY bin/start-comfyui                 /usr/local/bin/start-comfyui
COPY bin/start-jupyter                 /usr/local/bin/start-jupyter
COPY bin/pull-models                   /usr/local/bin/pull-models
COPY bin/comfy-status                  /usr/local/bin/comfy-status
COPY bin/comfy-save                    /usr/local/bin/comfy-save
COPY bin/comfy-reset                   /usr/local/bin/comfy-reset
COPY bin/comfy-update                  /usr/local/bin/comfy-update
COPY bin/comfy-replay                  /usr/local/bin/comfy-replay
COPY bin/comfy-notes                   /usr/local/bin/comfy-notes
COPY manifests/                        /manifests/

RUN chmod +x \
    /entrypoint.sh \
    /scripts/download_models_async.sh \
    /scripts/install_custom_nodes.sh \
    /usr/local/bin/start-comfyui \
    /usr/local/bin/start-jupyter \
    /usr/local/bin/pull-models \
    /usr/local/bin/comfy-status \
    /usr/local/bin/comfy-save \
    /usr/local/bin/comfy-reset \
    /usr/local/bin/comfy-update \
    /usr/local/bin/comfy-replay \
    /usr/local/bin/comfy-notes

# Environment defaults
ENV ENABLE_JUPYTER=true \
    JUPYTER_PORT=8888 \
    JUPYTER_TOKEN="" \
    COMFY_AUTOSTART=true \
    COMFY_PORT=8188 \
    COMFY_ARGS="--listen 0.0.0.0 --port 8188 --use-sage-attention --enable-manager" \
    COMFY_ARGS_EXTRA="" \
    COMFY_AUTOUPDATE=false \
    DATA_DIR=/workspace \
    COMFY_DIR=/opt/ComfyUI \
    MODELS_DIR=/workspace/models \
    MODELS_MANIFEST=/workspace/models_manifest.txt \
    CUSTOM_NODES_MANIFEST=/workspace/custom_nodes_manifest.txt \
    DL_WORKERS=4 \
    PIP_CACHE_DIR=/workspace/.pip-cache \
    PIP_NO_CACHE_DIR=0 \
    HF_HUB_ENABLE_HF_TRANSFER=1

EXPOSE 8188 8888
WORKDIR /opt/ComfyUI
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fs http://localhost:8188/system_stats || exit 1
ENTRYPOINT ["/usr/bin/tini","-s","--","bash","/entrypoint.sh"]
