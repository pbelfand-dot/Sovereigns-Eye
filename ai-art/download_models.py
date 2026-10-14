#!/usr/bin/env python3
"""Download the FLUX.2 [klein] 4B files into a ComfyUI install, after asking.

    python download_models.py --comfyui "C:/path/to/ComfyUI"

Nothing is downloaded until you type "yes" (or pass --yes). Downloads resume
if interrupted. Files already present are skipped.

Files (from Comfy-Org's official FLUX.2 [klein] template):
    models/diffusion_models/flux-2-klein-4b.safetensors   7.22 GB  (distilled, 4 steps)
    models/text_encoders/qwen_3_4b.safetensors            7.49 GB
    models/vae/flux2-vae.safetensors                      0.32 GB
                                                   total ~15.0 GB
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

FILES = [
    ("diffusion_models", "flux-2-klein-4b.safetensors", 7.22,
     "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors"),
    ("text_encoders", "qwen_3_4b.safetensors", 7.49,
     "https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"),
    ("vae", "flux2-vae.safetensors", 0.32,
     "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"),
]


def download(url: str, dest: Path) -> None:
    part = dest.with_suffix(dest.suffix + ".part")
    have = part.stat().st_size if part.exists() else 0
    req = urllib.request.Request(url, headers={"Range": f"bytes={have}-"} if have else {})
    with urllib.request.urlopen(req) as resp:
        total = int(resp.headers.get("Content-Length", 0)) + have
        mode = "ab" if have and resp.status == 206 else "wb"
        if mode == "wb":
            have = 0
        with open(part, mode) as f:
            while True:
                chunk = resp.read(8 * 1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
                have += len(chunk)
                if total:
                    print(f"\r    {have / 1e9:6.2f} / {total / 1e9:.2f} GB", end="", flush=True)
    print()
    part.rename(dest)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--comfyui", type=Path, required=True, help="ComfyUI folder (the one containing 'models')")
    ap.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    args = ap.parse_args()
    models = args.comfyui / "models"
    if not models.is_dir():
        print(f"{models} not found. Point --comfyui at your ComfyUI folder.")
        return 2
    todo = [(sub, name, gb, url) for sub, name, gb, url in FILES if not (models / sub / name).exists()]
    if not todo:
        print("All model files are already installed.")
        return 0
    print("These files will be downloaded:")
    for sub, name, gb, _ in todo:
        print(f"  {gb:5.2f} GB  models/{sub}/{name}")
    print(f"  total {sum(f[2] for f in todo):.2f} GB")
    if not args.yes and input('Type "yes" to download: ').strip().lower() != "yes":
        print("Cancelled; nothing downloaded.")
        return 1
    for sub, name, _, url in todo:
        (models / sub).mkdir(parents=True, exist_ok=True)
        print(f"  {name}")
        download(url, models / sub / name)
    print("Done. Restart ComfyUI so it sees the new models.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
