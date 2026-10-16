"""Builds one contact sheet per Lord's Castle piece for review, and the family's
overview (_castles.jpg).

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail), from `build_castle.py --review <cycles_dir>`. Bottom
row: the demo castles in the running game (tools/castle_demo.gd), from
`godot --path . res://tools/capture.tscn -- <seed> <dir> castle`. A strip
at the top gives the numbers.
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

CASTLE = {"stone": "the stone castle", "timber": "the motte and bailey"}
VIEW = {"village": "over its walls to the village", "front": "from the front", "aerial": "from above",
        "rear": "from behind", "court": "the court and the keep", "gate": "at the gate", "gameplay": "on foot",
        "motte": "the motte and its bridge", "tower": "the tower on the motte"}
# Piece -> in-game views for the bottom row: "<castle>_<view>".
ASSETS = {
    "SE_Curtain_Wall": ["stone_front", "stone_aerial", "stone_gameplay"],
    "SE_Curtain_Stair": ["stone_court", "stone_rear", "stone_aerial"],
    "SE_Curtain_Corner": ["stone_rear", "stone_aerial", "stone_village"],
    "SE_Tower_Square": ["stone_aerial", "stone_rear", "stone_front"],
    "SE_Tower_Corner": ["stone_front", "stone_village", "stone_court"],
    "SE_Gatehouse": ["stone_gate", "stone_front", "stone_gameplay"],
    "SE_Keep": ["stone_court", "stone_village", "stone_rear"],
    "SE_Palisade": ["timber_aerial", "timber_front", "timber_gate"],
    "SE_Palisade_Corner": ["timber_aerial", "timber_village", "timber_front"],
    "SE_Palisade_Gate": ["timber_gate", "timber_gameplay", "timber_front"],
    "SE_Timber_Tower": ["timber_tower", "timber_motte", "timber_village"],
    "SE_Motte": ["timber_motte", "timber_village", "timber_aerial"],
    "SE_Motte_Bridge": ["timber_motte", "timber_tower", "timber_aerial"],
}
OVERVIEW = ["stone_village", "timber_village", "stone_aerial", "timber_aerial"]


def caption(view):
    castle, _, kind = view.partition("_")
    return "In game: %s, %s" % (CASTLE[castle], VIEW[kind])


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
            p = os.path.join(game, "castle_%s.png" % v)
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), caption(v), f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)
    # The overview: both castles over their walls to the village, and from above.
    sheet = Image.new("RGB", (PANEL[0] * 2, PANEL[1] * 2), (28, 22, 17))
    d = ImageDraw.Draw(sheet)
    for i, v in enumerate(OVERVIEW):
        p = os.path.join(game, "castle_%s.png" % v)
        if os.path.exists(p):
            at = ((i % 2) * PANEL[0], (i // 2) * PANEL[1])
            sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), at)
            label(d, (at[0] + 8, at[1] + 8), caption(v), f_small)
    path = os.path.join(out, "_castles.jpg")
    sheet.save(path, quality=88, optimize=True)
    print("wrote", path)


if __name__ == "__main__":
    main()
