#!/usr/bin/env bash
# 20-custom-nodes-requirements.sh
# Réinstalle les requirements de tous les custom nodes à chaque boot.
# Nécessaire car le venv (/venv) est dans l'image et repart à zéro,
# mais les custom nodes persistent dans /workspace.
set -euo pipefail
export PATH="/venv/bin:$PATH"

NODES_DIR="${COMFY_DIR:-/workspace/ComfyUI}/custom_nodes"

if [[ ! -d "$NODES_DIR" ]]; then
  echo "[req] Aucun dossier custom_nodes trouvé — skip."
  exit 0
fi

echo "[req] Réinstallation des requirements custom nodes..."
ok=0; skip=0

for dir in "$NODES_DIR"/*/; do
  [[ -f "$dir/requirements.txt" ]] || { skip=$((skip+1)); continue; }
  name=$(basename "$dir")
  echo "[req]   pip install $name"
  pip install --quiet --no-cache-dir -r "$dir/requirements.txt" || \
    echo "[req]   WARN: échec pour $name (non bloquant)"
  ok=$((ok+1))
done

echo "[req] done — ok=$ok skip=$skip"
