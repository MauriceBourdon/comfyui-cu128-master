#!/usr/bin/env bash
# 10-sageattention.sh — Détection GPU + gestion SageAttention au runtime
#
# L'image embarque déjà SA2 compilé pour Ampere/Ada/Hopper/Blackwell.
# Ce script ne fait rien par défaut.
#
# Variables d'env optionnelles (RunPod Pod Settings):
#   SAGEATTENTION_BUILD=true   → recompile SA2 pour l'arch EXACTE du GPU présent
#   SAGEATTENTION3=true        → compile SA3 (FP4) — Blackwell uniquement
set -euo pipefail
export PATH="/venv/bin:$PATH"
STAMPS_DIR="/workspace/.stamps"; mkdir -p "$STAMPS_DIR"

# ── Détection compute capability ────────────────────────────────────────────────────────────────
ARCH=$(python3 - <<'PYEOF' 2>/dev/null || echo "none"
import torch, sys
if not torch.cuda.is_available():
    print("none"); sys.exit()
c = torch.cuda.get_device_capability(0)
print(f"{c[0]}.{c[1]}")
PYEOF
)

if [[ "$ARCH" == "none" ]]; then
  echo "[sage] Aucun GPU CUDA détecté — skip."
  exit 0
fi

MAJOR="${ARCH%%.*}"
GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null || echo "inconnu")

# Classe GPU
if   [[ "$MAJOR" -ge 12 ]]; then GPU_CLASS="Blackwell"
elif [[ "$MAJOR" -eq 9  ]]; then GPU_CLASS="Hopper"
elif [[ "$ARCH"  == "8.9" ]]; then GPU_CLASS="Ada Lovelace"
elif [[ "$MAJOR" -eq 8  ]]; then GPU_CLASS="Ampere"
else GPU_CLASS="Inconnu"; fi

echo "[sage] GPU    : $GPU_NAME"
echo "[sage] arch   : sm${ARCH//./}  (${GPU_CLASS})"
echo "[sage] SA2 baked-in compilé pour : 8.0 / 8.6 / 8.9 / 9.0 / 12.0"

# ── Option 1 : SA3 pour Blackwell (FP4, perf optimale) ─────────────────────────────────
if [[ "$GPU_CLASS" == "Blackwell" && "${SAGEATTENTION3:-false}" == "true" ]]; then
  SA3_STAMP="$STAMPS_DIR/sageattention3-build"
  if [[ ! -f "$SA3_STAMP" ]]; then
    echo "[sage] Blackwell + SAGEATTENTION3=true → compilation SA3 (FP4)..."
    TORCH_CUDA_ARCH_LIST="12.0" \
      pip install --quiet --no-cache-dir --no-binary=:all: "sageattention>=3.0.0"
    touch "$SA3_STAMP"
    echo "[sage] SA3 installé — redémarre ComfyUI pour en bénéficier."
  else
    echo "[sage] SA3 déjà installé (stamp)."
  fi

# ── Option 2 : rebuild SA2 pour l'arch EXACTE du GPU ───────────────────────────────────
elif [[ "${SAGEATTENTION_BUILD:-false}" == "true" ]]; then
  REBUILD_STAMP="$STAMPS_DIR/sageattention-build"
  if [[ ! -f "$REBUILD_STAMP" ]]; then
    echo "[sage] SAGEATTENTION_BUILD=true → recompilation SA2 pour sm${ARCH//./}..."
    TORCH_CUDA_ARCH_LIST="$ARCH" \
      pip install --quiet --no-cache-dir --no-binary=:all: "sageattention==2.2.0"
    touch "$REBUILD_STAMP"
    echo "[sage] Rebuild SA2 terminé."
  else
    echo "[sage] SA2 rebuild déjà effectué (stamp)."
  fi

# ── Défaut : SA2 baked-in (aucune action) ──────────────────────────────────────────────────
else
  echo "[sage] SA2 baked-in utilisé (sm${ARCH//./}, ${GPU_CLASS}) — aucune action."
  if [[ "$GPU_CLASS" == "Blackwell" ]]; then
    echo "[sage] ℹï¸  Pour les performances FP4 optimales sur Blackwell :"
    echo "[sage]      Set SAGEATTENTION3=true dans les variables d'env RunPod"
  fi
fi
