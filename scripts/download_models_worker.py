#!/usr/bin/env python3
import argparse, os, sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from huggingface_hub import hf_hub_download

def download_one(repo, rel, dstdir, token):
    os.makedirs(dstdir, exist_ok=True)
    fp = hf_hub_download(repo_id=repo, filename=rel,
                         token=(token or None),
                         local_dir=dstdir)
    return fp

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--token", default=os.environ.get("HF_TOKEN",""))
    p.add_argument("--workers", type=int, default=1)
    args = p.parse_args()

    os.makedirs(args.out, exist_ok=True)

    tasks = []
    with open(args.manifest, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                repo, rel, sub = line.split("|", 2)
            except ValueError:
                print(f"skip: {line}")
                continue
            dstdir = os.path.join(args.out, sub)
            tasks.append((repo, rel, dstdir))

    ok, fail = 0, 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(download_one, repo, rel, dstdir, args.token): (repo, rel)
                   for repo, rel, dstdir in tasks}
        for future in as_completed(futures):
            repo, rel = futures[future]
            try:
                fp = future.result()
                ok += 1
                print(f"ok: {repo} {rel} -> {fp}")
            except Exception as e:
                fail += 1
                print(f"fail: {repo} {rel} -> {e}")

    print(f"done: ok={ok} fail={fail}")

if __name__ == "__main__":
    sys.exit(main())
