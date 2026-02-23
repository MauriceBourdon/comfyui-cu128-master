#!/usr/bin/env bash
# 10-sageattention.sh — Compilation SageAttention au 1er boot (GPU réel présent)
#
# SAGEATTENTION_BUILD=once   → compile au 1er boot uniquement (défaut)
# SAGEATTENTION_BUILD=always → recompile à chaque boot (utile après update)
# SAGEATTENTION_BUILD=false  → désactive complètement
# SAGEATTENTION3=true        → compile SA3 (FP4) — Blackwell uniquement
set -euo pipefail
export PATH="/venv/bin:$PATH"
STAMPS_DIR="/workspace/.stamps"; mkdir -p "$STAMPS_DIR"
SA2_STAMP="$STAMPS_DIR/sageattention2-build"
SA3_STAMP="$STAMPS_DIR/sageattention3-build"

# ── Détection GPU ───────────────────────────────────────────────────────────────────────
ARCH=$(/venv/bin/python3 - <<'PYEOF' 2>/dev/null || echo "none"
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
GPU_NAME=$(/venv/bin/python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null || echo "inconnu")
if   [[ "$MAJOR" -ge 12 ]]; then GPU_CLASS="Blackwell"
elif [[ "$MAJOR" -eq 9  ]]; then GPU_CLASS="Hopper"
elif [[ "$ARCH"  == "8.9" ]]; then GPU_CLASS="Ada Lovelace"
elif [[ "$MAJOR" -eq 8  ]]; then GPU_CLASS="Ampere"
else GPU_CLASS="Inconnu"; fi

echo "[sage] GPU    : $GPU_NAME  (sm${ARCH//./} — ${GPU_CLASS})"

# ── Faut-il compiler SA2 ? ─────────────────────────────────────────────────────────────────
BUILD="${SAGEATTENTION_BUILD:-once}"
_do_build=false
case "$BUILD" in
  once)          [[ ! -f "$SA2_STAMP" ]] && _do_build=true ;;
  always|true)   _do_build=true ;;
  false|no|off)  echo "[sage] SAGEATTENTION_BUILD=false — skip."; _do_build=false ;;
esac

# Dossier de packages persistant (survit aux redémarrages du pod)
SA_PKG_DIR="/workspace/packages"
mkdir -p "$SA_PKG_DIR"

# Si le stamp existe mais le package a disparu (ex: workspace recréé), recompiler
if [[ -f "$SA2_STAMP" && ! -d "$SA_PKG_DIR/sageattention" ]]; then
  echo "[sage] Package absent malgré le stamp — recompilation forcée."
  rm -f "$SA2_STAMP"
  _do_build="true"
fi

if [[ "$_do_build" == "true" ]]; then
  echo "[sage] Compilation SA2 pour sm${ARCH//./} (${GPU_CLASS})..."
  # Installation dans /workspace/packages (persistant entre les boots)
  # --no-build-isolation : setup.py trouve torch dans le venv
  # --target            : installe dans /workspace/packages au lieu de /venv
  FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="$ARCH" \
    /venv/bin/pip install --no-cache-dir --no-build-isolation \
    --target "$SA_PKG_DIR" \
    "git+https://github.com/thu-ml/SageAttention.git"
  touch "$SA2_STAMP"
  echo "[sage] SA2 installé dans $SA_PKG_DIR ✔"
else
  echo "[sage] SA2 déjà compilé (stamp) — skip."
fi

# ── SA3 optionnel pour Blackwell ────────────────────────────────────────────────────────────────
if [[ "$GPU_CLASS" == "Blackwell" && "${SAGEATTENTION3:-false}" == "true" ]]; then
  if [[ ! -f "$SA3_STAMP" ]]; then
    echo "[sage] Blackwell + SAGEATTENTION3=true → compilation SA3 (FP4)..."
    FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="12.0" \
      /venv/bin/pip install --no-cache-dir --no-binary=:all: "sageattention>=3.0.0"
    touch "$SA3_STAMP"
    echo "[sage] SA3 installé ✔"
  else
    echo "[sage] SA3 déjà installé (stamp) — skip."
  fi
fi
