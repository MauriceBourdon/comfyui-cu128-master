#!/usr/bin/env bash
# install_custom_nodes.sh — Install/update ComfyUI custom nodes from a manifest
#
# Manifest format (one entry per line, # = comment):
#   https://github.com/user/repo|branch    (branch optional, default: main)
#
# Usage (automatic via entrypoint):
#   install_custom_nodes.sh MANIFEST NODES_DIR
#
# Usage (manual):
#   install_custom_nodes.sh [--list|--update] [MANIFEST] [NODES_DIR]
set -euo pipefail
export PATH="/venv/bin:$PATH"

MODE="install"

# Parse optional mode flag when called manually (--list, --update)
while [[ "${1:-}" =~ ^-- ]]; do
  case "$1" in
    --list)   MODE="list";   shift ;;
    --update) MODE="update"; shift ;;
    --help)
      echo "Usage: $(basename "$0") [--list|--update] [MANIFEST] [NODES_DIR]"
      exit 0 ;;
    *) echo "[nodes] Unknown flag: $1"; exit 2 ;;
  esac
done

MANIFEST="${1:-${CUSTOM_NODES_MANIFEST:-/workspace/custom_nodes_manifest.txt}}"
NODES_DIR="${2:-${COMFY_DIR:-/workspace/ComfyUI}/custom_nodes}"
STAMPS_DIR="/workspace/.stamps/nodes"

mkdir -p "$NODES_DIR" "$STAMPS_DIR"

if [[ ! -f "$MANIFEST" ]]; then
  echo "[nodes] No manifest found: $MANIFEST — skipping."
  exit 0
fi

echo "[nodes] manifest=$MANIFEST"
echo "[nodes] nodes_dir=$NODES_DIR"
echo "[nodes] mode=$MODE"
echo ""

ok=0; skip=0; fail=0

while IFS= read -r raw; do
  # Strip inline comments and surrounding whitespace
  line=$(printf '%s' "$raw" | sed 's/#.*//' | xargs 2>/dev/null || true)
  [[ -z "$line" ]] && continue

  # Parse: git_url|branch (branch is optional)
  git_url="${line%%|*}"
  branch="${line##*|}"
  [[ "$git_url" == "$line" ]] && branch="main"   # no pipe ⇒ no branch specified

  name=$(basename "$git_url" .git)
  dest="$NODES_DIR/$name"
  stamp="$STAMPS_DIR/$name"

  case "$MODE" in

    list)
      if [[ -d "$dest/.git" ]]; then
        echo "  [OK]    $name   ($git_url @ $branch)"
      else
        echo "  [MISS]  $name   ($git_url @ $branch)"
      fi
      ;;

    update)
      if [[ -d "$dest/.git" ]]; then
        echo "[nodes] Updating $name ..."
        if git -C "$dest" pull --ff-only origin "$branch" 2>&1; then
          ok=$((ok + 1))
        else
          echo "[nodes] WARN: $name — pull failed (may need manual rebase)"
          fail=$((fail + 1))
        fi
      else
        echo "[nodes] Not installed, skipping: $name"
        skip=$((skip + 1))
      fi
      ;;

    install)
      # Skip if already installed (stamp file OR existing .git dir)
      if [[ -f "$stamp" ]] || [[ -d "$dest/.git" ]]; then
        echo "[nodes] Already installed: $name"
        skip=$((skip + 1))
        continue
      fi

      echo "[nodes] Installing $name ..."
      if git clone --depth=1 -b "$branch" "$git_url" "$dest" 2>&1; then
        # Install Python requirements if present
        if [[ -f "$dest/requirements.txt" ]]; then
          echo "[nodes]   pip install requirements for $name ..."
          pip install --quiet --no-cache-dir -r "$dest/requirements.txt" || true
        fi
        # Run install script if present
        if [[ -f "$dest/install.py" ]]; then
          echo "[nodes]   running install.py for $name ..."
          python "$dest/install.py" 2>&1 || true
        fi
        touch "$stamp"
        ok=$((ok + 1))
        echo "[nodes] OK: $name"
      else
        fail=$((fail + 1))
        echo "[nodes] FAIL: $name"
      fi
      ;;
  esac

done < "$MANIFEST"

if [[ "$MODE" != "list" ]]; then
  echo ""
  echo "[nodes] done — ok=$ok  skip=$skip  fail=$fail"
  [[ "$ok" -gt 0 ]] && echo "[nodes] ⚠  Restart ComfyUI to load new nodes."
fi
