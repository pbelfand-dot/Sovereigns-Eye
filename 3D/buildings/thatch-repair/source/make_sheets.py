"""Builds one contact sheet per Thatch & Repair asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views (from `build_thatch.py --review <cycles_dir>`;
the walls are left out, so a roof floats where it would sit). Bottom row:
the asset in the running game, from
`godot --path . res://tools/capture.tscn -- <seed> <dir> thatch`.
A strip at the top gives the numbers.
"""
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

# The commons sheet helpers (same file name, so load it by path).
_spec = importlib.util.spec_from_file_location("commons_sheets", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "props", "village-commons", "source", "make_sheets.py"))
_commons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_commons)
PANEL, fit, font, label = _commons.PANEL, _commons.fit, _commons.font, _commons.label

GAME = {
    "street_0": "a street of Cottages",
    "street_1": "the same street as Timber Houses",
    "street_2": "and as Townhouses (tiles)",
    "cottage": "a poor Cottage close to",
    "onfoot": "on foot at a Cottage's door",
    "farm": "a farmhouse",
    "village": "the village from above",
}
ROOF_TOP = [("front34", "Front 3/4 (Blender)"), ("top", "From above (Blender)"), ("close", "The ridge (Blender)")]
PATCH_TOP = [("front", "Front (Blender)"), ("side", "From the side (Blender)"), ("close", "Close detail (Blender)")]
SHUTTER_TOP = [("front", "Front (Blender)"), ("front34", "Front 3/4 (Blender)"), ("close", "Close detail (Blender)")]
ASSETS = {
    "SE_Thatch_4x6_Worn": (ROOF_TOP, ["street_0", "cottage", "onfoot"]),
    "SE_Thatch_4x6": (ROOF_TOP, ["street_1", "street_0", "street_2"]),
    "SE_Thatch_6x8": (ROOF_TOP, ["farm", "village", "street_1"]),
    "SE_Patch_Wattle": (PATCH_TOP, ["cottage", "onfoot", "street_0"]),
    "SE_Patch_Daub": (PATCH_TOP, ["cottage", "onfoot", "street_0"]),
    "SE_Patch_Boards": (PATCH_TOP, ["cottage", "onfoot", "street_0"]),
}
for _fit in ("Wide_Round", "Thin_Round", "Wide_Flat"):
    for _state in ("Open", "Closed"):
        ASSETS["SE_Shutters_Plank_%s_%s" % (_fit, _state)] = (SHUTTER_TOP, ["onfoot", "cottage", "street_0"])


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
        for i, (view, t) in enumerate(top):
            p = os.path.join(cycles, "%s_%s.png" % (name, view))
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, v in enumerate(views):
            p = os.path.join(game, "thatch_%s.png" % v)
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: " + GAME[v], f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
