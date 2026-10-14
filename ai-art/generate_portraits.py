#!/usr/bin/env python3
"""Paint Sovereign's Eye character-card portraits with a local ComfyUI.

The game writes every villager's prompt to
    <Godot user dir>/portraits/<world seed>/prompts.json
whenever a village is created or loaded. This script sends each prompt to
ComfyUI (FLUX.2 [klein] 4B by default), and saves the result as
    <Godot user dir>/portraits/<world seed>/<character id>.png
which the game shows on that villager's card automatically.

Consistency: every villager uses the same model, sampler, steps, size and
style text, plus a fixed seed derived from the world seed and character id,
so re-running gives the same face and two villages never share portraits.

Only the Python standard library is used. Typical use:

    python generate_portraits.py                 # newest village, all villagers
    python generate_portraits.py --limit 5       # try a few first
    python generate_portraits.py --only 3,17     # specific character ids
    python generate_portraits.py --overwrite     # repaint existing portraits

Start ComfyUI first (it listens on http://127.0.0.1:8188 by default).
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import platform
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_WORKFLOW = HERE / "workflows" / "portrait_flux2_klein_4b_distilled_api.json"
GAME_DIR_NAME = "Sovereign's Eye"


def godot_user_dir() -> Path:
    """Where Godot keeps the game's user:// files on this computer."""
    system = platform.system()
    if system == "Windows":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Godot"
    elif system == "Darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "godot"
    return base / "app_userdata" / GAME_DIR_NAME


def newest_prompt_file() -> Path | None:
    root = godot_user_dir() / "portraits"
    files = sorted(root.glob("*/prompts.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


# --- ComfyUI API ---------------------------------------------------------------

class ComfyError(RuntimeError):
    pass


def _request(server: str, path: str, payload: dict | None = None, timeout: float = 30.0) -> bytes:
    url = server.rstrip("/") + path
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise ComfyError(f"ComfyUI rejected {path} ({e.code}): {body[:2000]}") from None
    except urllib.error.URLError as e:
        raise ComfyError(
            f"Can't reach ComfyUI at {server} ({e.reason}). Start ComfyUI first, or pass --server."
        ) from None


def check_server(server: str) -> None:
    _request(server, "/system_stats", timeout=10)


def queue_prompt(server: str, workflow: dict, client_id: str) -> str:
    out = json.loads(_request(server, "/prompt", {"prompt": workflow, "client_id": client_id}))
    if out.get("node_errors"):
        raise ComfyError("Workflow errors: " + json.dumps(out["node_errors"])[:2000])
    return out["prompt_id"]


def wait_for_images(server: str, prompt_id: str, timeout: float) -> list[dict]:
    start = time.time()
    while time.time() - start < timeout:
        history = json.loads(_request(server, f"/history/{prompt_id}"))
        entry = history.get(prompt_id)
        if entry:
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise ComfyError("Generation failed: " + json.dumps(status.get("messages", []))[:2000])
            images = [img for node in entry.get("outputs", {}).values() for img in node.get("images", [])]
            if images:
                return images
        time.sleep(0.5)
    raise ComfyError(f"Timed out after {timeout:.0f}s waiting for prompt {prompt_id}")


def download_image(server: str, image: dict) -> bytes:
    query = urllib.parse.urlencode({
        "filename": image["filename"],
        "subfolder": image.get("subfolder", ""),
        "type": image.get("type", "output"),
    })
    return _request(server, "/view?" + query, timeout=120)


# --- Workflow patching ------------------------------------------------------------

def _positive_and_negative_nodes(wf: dict) -> tuple[set[str], set[str]]:
    """CLIPTextEncode nodes feeding a sampler/guider's positive or negative input."""
    pos, neg = set(), set()
    for node in wf.values():
        inputs = node.get("inputs", {})
        for key, target in (("positive", pos), ("negative", neg)):
            link = inputs.get(key)
            if isinstance(link, list) and str(link[0]) in wf and wf[str(link[0])].get("class_type") == "CLIPTextEncode":
                target.add(str(link[0]))
    return pos, neg


def patch_workflow(template: dict, job: dict, args: argparse.Namespace) -> dict:
    """Puts one villager's prompt, seed and size into a copy of the workflow.

    Works with the bundled FLUX.2 workflow and with most workflows exported
    from ComfyUI via "Export (API)", by patching nodes by type."""
    wf = copy.deepcopy(template)
    pos, neg = _positive_and_negative_nodes(wf)
    text_nodes = [k for k, n in wf.items() if n.get("class_type") == "CLIPTextEncode"]
    if not pos and text_nodes:
        pos = {text_nodes[0]}
    seed = int(job["seed"]) % (2**53)
    width, height = int(job.get("width", 768)), int(job.get("height", 960))
    for key, node in wf.items():
        ct = node.get("class_type", "")
        inputs = node.setdefault("inputs", {})
        if key in pos:
            inputs["text"] = job["prompt"]
        elif key in neg:
            inputs["text"] = job.get("negative_prompt", "")
        if ct == "RandomNoise":
            inputs["noise_seed"] = seed
        if ct in ("KSampler", "KSamplerAdvanced"):
            inputs["seed" if ct == "KSampler" else "noise_seed"] = seed
        if ct in ("EmptyFlux2LatentImage", "EmptyLatentImage", "EmptySD3LatentImage", "Flux2Scheduler"):
            if "width" in inputs and not isinstance(inputs["width"], list):
                inputs["width"] = width
            if "height" in inputs and not isinstance(inputs["height"], list):
                inputs["height"] = height
        if ct == "Flux2Scheduler" and args.steps:
            inputs["steps"] = args.steps
        if ct == "UNETLoader" and args.unet:
            inputs["unet_name"] = args.unet
        if ct == "SaveImage":
            inputs["filename_prefix"] = f"sovereigns_eye/{job.get('character_id', 'portrait')}"
    return wf


# --- Main -------------------------------------------------------------------------

def output_path(job: dict, prompts_file: Path) -> Path:
    return prompts_file.parent / f"{job['character_id']}.png"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prompts", type=Path, help="prompts.json written by the game (default: newest village)")
    ap.add_argument("--server", default="http://127.0.0.1:8188", help="ComfyUI address")
    ap.add_argument("--workflow", type=Path, default=DEFAULT_WORKFLOW, help="ComfyUI workflow in API format")
    ap.add_argument("--only", help="comma-separated character ids")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many new portraits")
    ap.add_argument("--overwrite", action="store_true", help="repaint portraits that already exist")
    ap.add_argument("--steps", type=int, default=0, help="override sampling steps")
    ap.add_argument("--unet", help="override the diffusion model file name (e.g. an fp8 version)")
    ap.add_argument("--timeout", type=float, default=600.0, help="seconds to wait for each portrait")
    ap.add_argument("--dry-run", action="store_true", help="show what would be generated, don't call ComfyUI")
    args = ap.parse_args(argv)

    prompts_file = args.prompts or newest_prompt_file()
    if prompts_file is None or not prompts_file.exists():
        print(f"No prompts found. Start or load a village in the game first.\nLooked in: {godot_user_dir() / 'portraits'}")
        return 2
    data = json.loads(prompts_file.read_text(encoding="utf-8"))
    jobs = data.get("portraits", [])
    if args.only:
        wanted = {int(x) for x in args.only.split(",") if x.strip()}
        jobs = [j for j in jobs if int(j["character_id"]) in wanted]
    existing = sum(1 for j in jobs if output_path(j, prompts_file).exists())
    todo = [j for j in jobs if args.overwrite or not output_path(j, prompts_file).exists()]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{data.get('village', '?')} (seed {data.get('seed_text', '?')}): {len(todo)} portrait(s) to paint, "
          f"{existing} of {len(jobs)} already exist.  Output: {prompts_file.parent}")
    if args.dry_run:
        for j in todo:
            print(f"  #{j['character_id']} {j['name']} seed={j['seed']}\n    {j['prompt'][:160]}...")
        return 0
    if not todo:
        return 0

    template = json.loads(args.workflow.read_text(encoding="utf-8"))
    try:
        check_server(args.server)
    except ComfyError as e:
        print(e)
        return 3
    client_id = str(uuid.uuid4())
    done = 0
    for i, job in enumerate(todo, 1):
        started = time.time()
        try:
            prompt_id = queue_prompt(args.server, patch_workflow(template, job, args), client_id)
            images = wait_for_images(args.server, prompt_id, args.timeout)
            png = download_image(args.server, images[0])
        except ComfyError as e:
            print(f"  #{job['character_id']} {job['name']}: {e}")
            if "value_not_in_list" in str(e) or "not in list" in str(e):
                print("  -> A model file is missing in ComfyUI. See ai-art/README.md (Models).")
            return 4
        out = output_path(job, prompts_file)
        out.write_bytes(png)
        done += 1
        print(f"  [{i}/{len(todo)}] #{job['character_id']} {job['name']}  ({time.time() - started:.1f}s) -> {out.name}")
    print(f"Done: {done} portrait(s). Open a villager's card in the game to see them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
