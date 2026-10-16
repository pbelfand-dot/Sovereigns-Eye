"""Builds one contact sheet per Market Square asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail; for kerbs, the pieces laid as an arc round a paved disc,
from `build_square.py --kerbs <cycles_dir>/arc`). Bottom row: the asset in
the running game (Godot, real lighting), from
`godot --path . res://tools/capture.tscn -- <seed> <dir> square`.
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

TIER_NAMES = ["Hamlet", "Village", "Market Town", "Town"]
# Asset -> (top row [(file, title)], bottom row [in-game view "square_<tier>_<view>"]).
ARC = [("arc_%s_close", "Laid round the square, close (Blender)"), ("arc_%s_mid", "Laid round the square (Blender)"),
       ("arc_%s_top", "From above (Blender)")]
ASSETS = {
    "SE_Kerb_Rubble": (ARC, ["0_kerb", "0_square", "0_trough"]),
    "SE_Kerb_Stone": (ARC, ["1_kerb", "1_square", "1_trough"]),
    "SE_Kerb_Step": (ARC, ["2_kerb", "3_kerb", "3_square"]),
    "SE_MarketCross": (None, ["2_cross", "2_cross_gameplay", "2_square"]),
    "SE_MarketCross_Town": (None, ["3_cross", "3_cross_gameplay", "3_square"]),
    "SE_Trough_Log": (None, ["0_trough", "1_trough", "1_square"]),
    "SE_Trough_Stone": (None, ["2_trough", "3_trough", "3_square"]),
}
VIEW_TITLES = {"square": "the square (map table)", "kerb": "on foot where a road comes in", "trough": "beside the well",
               "cross": "the cross at 3/4", "cross_gameplay": "on foot, follow camera"}


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
            st.get("collision", ""),
        ] if x))
        d.text((16, 18), head, fill=(240, 220, 170), font=f_big)
        row = [("%s_front34" % name, "Front 3/4 (Blender)"), ("%s_rear34" % name, "Rear 3/4 (Blender)"), ("%s_close" % name, "Close detail (Blender)")]
        if top:
            row = [(f % name, t) for f, t in top]
        for i, (stem, t) in enumerate(row[:3]):
            p = os.path.join(cycles, stem + ".png")
            if os.path.exists(p) and t:
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, v in enumerate(views):
            p = os.path.join(game, "square_%s.png" % v)
            if os.path.exists(p):
                tier, kind = v.split("_", 1)
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: %s (%s)" % (VIEW_TITLES[kind], TIER_NAMES[int(tier)]), f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
