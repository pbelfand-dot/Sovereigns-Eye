"""Builds one contact sheet per Training Yard asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail), from `build_training.py --review <cycles_dir>`. Bottom
row: the yard in the running game at the charters that use the asset,
from `godot --path . res://tools/capture.tscn -- <seed> <dir> training`.
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

CHARTER = {"0": "Hamlet", "1": "Village", "2": "Market Town", "3": "Town"}
VIEW = {"yard": "the yard", "gameplay": "on foot"}
# Asset -> in-game views "training_<charter>_<view>" for the bottom row.
ASSETS = {
    "SE_Pell": ["0_yard", "0_gameplay", "1_gameplay"],
    "SE_Dummy_Straw": ["1_gameplay", "2_gameplay", "3_gameplay"],
    "SE_Quintain": ["3_gameplay", "3_yard", "2_yard"],
    "SE_ArcheryButt": ["0_gameplay", "2_gameplay", "1_yard"],
    "SE_Rack_Staves": ["0_gameplay", "1_yard", "0_yard"],
    "SE_Rack_Weapons": ["2_gameplay", "3_yard", "2_yard"],
    "SE_Ring_Rope": ["2_gameplay", "2_yard", "1_yard"],
    "SE_Ring_Rail": ["3_gameplay", "3_yard", "2_yard"],
}


def main():
    cycles, game, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stats = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
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
        for i, v in enumerate(views):
            p = os.path.join(game, "training_%s.png" % v)
            if os.path.exists(p):
                charter, _, kind = v.partition("_")
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: %s (%s)" % (VIEW[kind], CHARTER[charter]), f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
