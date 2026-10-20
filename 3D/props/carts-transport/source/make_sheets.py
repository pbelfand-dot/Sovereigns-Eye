"""Builds one contact sheet per Carts & Transport model for review, and the
family's overview (_carts.jpg).

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [asset_check.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close), from `build_carts.py --review <cycles_dir>`. Bottom row: the
models in Godot. From the running game, the cart on the village road and
in the square (`godot --path . res://tools/capture.tscn -- 12345 <game_dir>
carts`, which draws them with CartView). From `source/godot_review.gd
-- <game_dir>`, the legs turned 35 degrees as the game turns them, the
joints from below, the load and the cart unhitched. The header's numbers
come from tools/asset_check.gd's JSON report.
"""
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

# The commons sheet helpers (same file name, so load it by path).
_spec = importlib.util.spec_from_file_location("commons_sheets", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "village-commons", "source", "make_sheets.py"))
_commons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_commons)
PANEL, fit, font, label = _commons.PANEL, _commons.fit, _commons.font, _commons.label

# (folder, file, zoom on the centre, caption)
SHOTS = {
    "road": ("game", "carts_1_road.png", 2.0, "In game: setting out along the road (CartView)"),
    "square": ("game", "carts_0_square.png", 2.0, "In game: loaded in the square, the carter at its head"),
    "leaving": ("game", "carts_2_leaving.png", 1.6, "In game: from the strategy camera, 36 m"),
    "walk": ("game", "godot_walk.png", 1.0, "Godot: legs turned 35 degrees, as the game turns them"),
    "walk_b": ("game", "godot_walk_b.png", 1.0, "Godot: the other stride"),
    "joints": ("game", "godot_joints_front.png", 1.0, "Godot: into the joints from below"),
    "laden": ("game", "godot_laden.png", 1.0, "Godot: the load at Load_Anchor"),
    "strategy": ("game", "godot_strategy.png", 2.2, "Godot: laden on a track, and unhitched, 30 m off"),
    "unhitched": ("game", "godot_unhitched.png", 1.0, "Godot: unhitched, its shafts on the ground"),
    "laden_cycles": ("cycles", "SE_Cart_Load_laden.png", 1.0, "In the cart with the horse (Blender)"),
    "laden_top": ("cycles", "SE_Cart_Load_laden_top.png", 1.3, "From above, in the cart (Blender)"),
    "cart_gameplay": ("cycles", "SE_Cart_gameplay.png", 1.4, "Gameplay angle beside a 1.78 m figure (Blender)"),
}
ASSETS = {
    "SE_Cart_Horse": ["road", "walk", "joints"],
    "SE_Cart_Load": ["laden_cycles", "laden", "square"],
    "SE_Cart": ["unhitched", "strategy", "cart_gameplay"],
}
OVERVIEW = ["road", "walk", "square", "unhitched"]


def shot(dirs, key):
    where, name, zoom, title = SHOTS[key]
    p = os.path.join(dirs[where], name)
    if not os.path.exists(p):
        return None, title
    img = Image.open(p).convert("RGB")
    if zoom > 1.0:
        w, h = img.size
        cw, ch = int(w / zoom), int(h / zoom)
        img = img.crop(((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2))
    return fit(img, PANEL), title


def stats_from(path):
    """asset_check.gd's JSON report -> {model: header numbers}."""
    if not path:
        return {}
    out = {}
    for m in json.load(open(path)).get("models", []):
        lods = m["lods"]
        out[os.path.splitext(m["file"])[0]] = {
            "tris": m["tris"], "materials": len(m["materials"]), "size": m["size"].replace(" x ", " × "),
            "lods": str(lods) if len(lods) <= 3 else "on %d of %d parts" % (sum(1 for n in lods if n), len(lods)),
        }
    return out


def main():
    cycles, game, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stats = stats_from(sys.argv[4] if len(sys.argv) > 4 else None)
    dirs = {"cycles": cycles, "game": game}
    os.makedirs(out, exist_ok=True)
    f_small, f_big = font(18), font(26)
    for name, views in ASSETS.items():
        sheet = Image.new("RGB", (PANEL[0] * 3, 64 + PANEL[1] * 2), (28, 22, 17))
        d = ImageDraw.Draw(sheet)
        st = stats.get(name, {})
        head = "%s   %s" % (name, " | ".join(x for x in [
            "%d tris" % st["tris"] if "tris" in st else "",
            "%d material%s" % (st["materials"], "" if st["materials"] == 1 else "s") if "materials" in st else "",
            st.get("size", ""),
            "LODs %s" % st["lods"] if "lods" in st else "",
        ] if x))
        d.text((16, 18), head, fill=(240, 220, 170), font=f_big)
        for i, (view, t) in enumerate([("front34", "Front 3/4 (Blender)"), ("rear34", "Rear 3/4 (Blender)"), ("close", "Close detail (Blender)")]):
            p = os.path.join(cycles, "%s_%s.png" % (name, view))
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, key in enumerate(views):
            img, title = shot(dirs, key)
            if img:
                sheet.paste(img, (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), title, f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)
    sheet = Image.new("RGB", (PANEL[0] * 2, PANEL[1] * 2), (28, 22, 17))
    d = ImageDraw.Draw(sheet)
    for i, key in enumerate(OVERVIEW):
        img, title = shot(dirs, key)
        if img:
            at = ((i % 2) * PANEL[0], (i // 2) * PANEL[1])
            sheet.paste(img, at)
            label(d, (at[0] + 8, at[1] + 8), title, f_small)
    path = os.path.join(out, "_carts.jpg")
    sheet.save(path, quality=88, optimize=True)
    print("wrote", path)


if __name__ == "__main__":
    main()
