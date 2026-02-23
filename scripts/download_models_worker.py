#!/usr/bin/env python3
"""Download models from manifest with parallel workers.

Manifest format (one entry per line, # = comment):
  repo|path_in_repo|subdir_under_models  → HuggingFace download
  https://...|filename|subdir            → Direct URL (aria2c if available, else curl)

Env vars:
  HF_TOKEN     HuggingFace token for gated/private models
  DL_WORKERS   number of parallel workers (default: 6)
"""
import argparse, os, sys, shutil, subprocess, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from huggingface_hub import hf_hub_download


def _retry(fn, attempts=3, base_delay=5):
    """Réessaie fn jusqu'à `attempts` fois avec backoff exponentiel."""
    for i in range(attempts):
        try:
            return fn()
        except Exception as e:
            if i < attempts - 1:
                wait = base_delay * (2 ** i)  # 5s, 10s, 20s
                print(f"[retry {i+1}/{attempts}] {e} — nouvel essai dans {wait}s...")
                time.sleep(wait)
            else:
                raise

DEFAULT_WORKERS = int(os.environ.get("DL_WORKERS", "6"))


def dl_hf(repo, rel, dstdir, token):
    return hf_hub_download(
        repo_id=repo,
        filename=rel,
        token=(token or None),
        local_dir=dstdir,
    )


def dl_url(url, filename, dstdir):
    dest = os.path.join(dstdir, filename)
    if os.path.exists(dest):
        return dest  # already present, skip
    if shutil.which("aria2c"):
        subprocess.run(
            [
                "aria2c", "-x8", "-s8", "-k1M",
                "--file-allocation=none",
                "--console-log-level=warn",
                "-d", dstdir, "-o", filename, url,
            ],
            check=True,
        )
    else:
        subprocess.run(
            ["curl", "-fL", "--retry", "3", "-o", dest, url],
            check=True,
        )
    return dest


def process_line(line, out_root, token):
    parts = line.split("|", 2)
    if len(parts) != 3:
        raise ValueError(f"bad format (expected a|b|c): {line!r}")
    a, b, sub = (p.strip() for p in parts)
    dstdir = os.path.join(out_root, sub)
    os.makedirs(dstdir, exist_ok=True)
    if a.startswith("http://") or a.startswith("https://"):
        fp = _retry(lambda: dl_url(a, b, dstdir))
    else:
        fp = _retry(lambda: dl_hf(a, b, dstdir, token))
    return fp


def main():
    p = argparse.ArgumentParser(description="Download models from manifest")
    p.add_argument("--manifest", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--token", default=os.environ.get("HF_TOKEN", ""))
    p.add_argument(
        "--workers", type=int, default=DEFAULT_WORKERS,
        help=f"parallel workers (default: {DEFAULT_WORKERS}, env: DL_WORKERS)",
    )
    args = p.parse_args()

    os.makedirs(args.out, exist_ok=True)

    lines = []
    with open(args.manifest, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line and not line.startswith("#"):
                lines.append(line)

    if not lines:
        print("[dl] manifest is empty, nothing to download.")
        return 0

    print(f"[dl] {len(lines)} entries, {args.workers} workers")
    ok, fail = 0, 0

    with ThreadPoolExecutor(max_workers=args.workers) as exe:
        futures = {
            exe.submit(process_line, line, args.out, args.token): line
            for line in lines
        }
        for fut in as_completed(futures):
            line = futures[fut]
            try:
                fp = fut.result()
                ok += 1
                print(f"[ok]   {line} → {fp}")
            except Exception as e:
                fail += 1
                print(f"[fail] {line} → {e}")

    print(f"[dl] done: ok={ok} fail={fail}")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
