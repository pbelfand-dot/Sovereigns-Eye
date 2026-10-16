"""Builds one contact sheet per Chapel & Churchyard asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail), from `build_chapel.py --review <cycles_dir>`. Bottom
row: the chapel and its churchyard in the running game at the charters
that use the asset, from
`godot --path . res://tools/capture.tscn -- <seed> <dir> chapel`.
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
VIEW = {"yard": "the churchyard", "gameplay": "on foot", "side": "beside the chapel", "front": "from the square"}
CLOSE = {"belfry": "In game: the belfry from the square", "tower": "In game: the belfry close up",
         "spire": "In game: the spire's cross", "gable": "In game: the east gable"}
# Asset -> in-game views for the bottom row: "<charter>_<view>" or "close_<view>".
ASSETS = {
    "SE_Belfry": ["close_belfry", "close_tower", "3_front"],
    "SE_Cross_Tower": ["close_spire", "close_belfry", "0_front"],
    "SE_Cross_Gable": ["close_gable", "2_side", "3_side"],
    "SE_Grave_Mound": ["0_gameplay", "1_yard", "0_yard"],
    "SE_Grave_Fresh": ["0_gameplay", "1_gameplay", "0_yard"],
    "SE_Grave_Cross": ["0_gameplay", "1_gameplay", "0_yard"],
    "SE_Grave_Slab": ["2_gameplay", "3_yard", "2_yard"],
    "SE_Grave_Slab_Knight": ["3_yard", "3_gameplay", "3_side"],
    "SE_Churchyard_Cross": ["1_yard", "2_gameplay", "3_yard"],
    "SE_Yew": ["1_yard", "2_yard", "3_gameplay"],
    "SE_Wall_Rubble": ["2_yard", "2_gameplay", "2_side"],
    "SE_Wall_Coped": ["3_yard", "3_gameplay", "3_side"],
    "SE_Wall_Pier": ["2_gameplay", "3_gameplay", "3_yard"],
    "SE_Lychgate": ["3_yard", "3_gameplay", "3_side"],
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
            p = os.path.join(game, "chapel_%s.png" % v)
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                head, _, kind = v.partition("_")
                text = CLOSE[kind] if head == "close" else "In game: %s (%s)" % (VIEW[kind], CHARTER[head])
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), text, f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
