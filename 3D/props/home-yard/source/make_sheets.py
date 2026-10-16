"""Builds one contact sheet per Home Yard asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail), from `build_home.py --review <cycles_dir> --yards
<cycles_dir>/yard`. Bottom row: the asset in the running game, from
`godot --path . res://tools/capture.tscn -- <seed> <dir> home`.
A strip at the top gives the numbers.
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

LEVEL = {"0": "Cottage", "1": "Timber House", "2": "Townhouse", "farm": "Farmhouse"}
VIEW_TITLES = {"front": "the front at 3/4", "back": "the back at 3/4", "gameplay": "on foot, follow camera", "": "the farmhouse's yard"}
# Asset -> (top row override or None, bottom row in-game views "home_<view>").
ASSETS = {
    "SE_Bench_Log": ([("yard_0_front34", "The Cottage's yard (Blender)"), ("SE_Bench_Log_front34", "Front 3/4 (Blender)"),
                      ("SE_Bench_Log_close", "Close detail (Blender)")], ["0_gameplay", "0_front", "1_gameplay"]),
    "SE_Bench": (None, ["1_gameplay", "1_front", "farm"]),
    "SE_Bench_Painted": ([("yard_2_front34", "The Townhouse's yard (Blender)"), ("SE_Bench_Painted_front34", "Front 3/4 (Blender)"),
                          ("SE_Bench_Painted_close", "Close detail (Blender)")], ["2_gameplay", "2_front", "1_gameplay"]),
    "SE_Garden_Poor": ([("yard_0_back34", "The Cottage's yard from behind (Blender)"), ("SE_Garden_Poor_front34", "Front 3/4 (Blender)"),
                        ("SE_Garden_Poor_close", "Close detail (Blender)")], ["0_back", "0_front", "1_back"]),
    "SE_Garden": ([("yard_1_back34", "The Timber House's yard from behind (Blender)"), ("SE_Garden_front34", "Front 3/4 (Blender)"),
                   ("SE_Garden_close", "Close detail (Blender)")], ["1_back", "2_back", "farm"]),
    "SE_ChoppingBlock": (None, ["0_back", "1_back", "farm"]),
    "SE_WaterButt": (None, ["1_back", "2_back", "farm"]),
    "SE_LaundryLine": (None, ["0_back", "1_back", "2_back"]),
    "SE_ChickenCoop": ([("yard_1_front34", "The Timber House's yard (Blender)"), ("SE_ChickenCoop_front34", "Front 3/4 (Blender)"),
                        ("SE_ChickenCoop_close", "Close detail (Blender)")], ["1_front", "1_back", "farm"]),
    "SE_FlowerPots": (None, ["2_gameplay", "2_front", "2_back"]),
}


def main():
    cycles, game, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stats = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
    os.makedirs(out, exist_ok=True)
    f_small, f_big = font(18), font(26)
    for name, (top, views) in ASSETS.items():
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
        row = top or [("%s_front34" % name, "Front 3/4 (Blender)"), ("%s_rear34" % name, "Rear 3/4 (Blender)"), ("%s_close" % name, "Close detail (Blender)")]
        for i, (stem, t) in enumerate(row[:3]):
            p = os.path.join(cycles, stem + ".png")
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, v in enumerate(views):
            p = os.path.join(game, "home_%s.png" % v)
            if os.path.exists(p):
                level, _, kind = v.partition("_")
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: %s (%s)" % (VIEW_TITLES[kind], LEVEL[level]), f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
