#!/bin/bash
set -eu
MF="${1:-/workspace/models_manifest.txt}"
ROOT="${2:-/workspace/models}"
export PATH="/venv/bin:$PATH"
exec python /scripts/download_models_worker.py \
  --manifest "$MF" \
  --out "$ROOT" \
  --workers "${DL_WORKERS:-4}"
