#!/usr/bin/env python3
import argparse, os, sys
from huggingface_hub import hf_hub_download

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--token", default=os.environ.get("HF_TOKEN",""))
    args = p.parse_args()

    os.makedirs(args.out, exist_ok=True)
    ok, fail = 0, 0
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
            os.makedirs(dstdir, exist_ok=True)
            try:
                fp = hf_hub_download(repo_id=repo, filename=rel,
                                     token=(args.token or None),
                                     local_dir=dstdir)
                ok += 1
                print(f"ok: {repo} {rel} -> {fp}")
            except Exception as e:
                fail += 1
                print(f"fail: {repo} {rel} -> {e}")
    print(f"done: ok={ok} fail={fail}")

if __name__ == "__main__":
    sys.exit(main())
