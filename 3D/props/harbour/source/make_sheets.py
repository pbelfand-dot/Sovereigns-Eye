"""Builds one contact sheet per Harbour & Ships piece for review, and the
family's overview (_harbour.jpg).

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles views beside a 1.78 m mannequin (front 3/4, rear
3/4, close detail), from `build_harbour.py --review <cycles_dir>` (each
piece lifted to stand its lowest point on the ground, so what is under the
water shows). Bottom row: the demo harbour in the running game
(tools/harbour_demo.gd), from
`godot --path . res://tools/capture.tscn -- <seed> <dir> harbour`.
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

VIEW = {"overview": "the harbour from the sea", "quay": "the stone quay and the cog", "stern": "the cog's stern rudder",
        "hoist": "wool going aboard", "timber": "the timber quay", "jetty": "the jetty from the beach",
        "shore": "the shore: slipway, nets, a boat turned over", "steps": "the water stairs", "sail": "a keel coming in under sail"}
# Piece -> in-game views for the bottom row.
ASSETS = {
    "SE_Quay_Timber": ["timber", "hoist", "overview"],
    "SE_Quay_Stone": ["quay", "steps", "overview"],
    "SE_Quay_Steps": ["steps", "quay", "overview"],
    "SE_Jetty": ["jetty", "overview", "sail"],
    "SE_Jetty_End": ["jetty", "overview", "shore"],
    "SE_Slipway": ["shore", "jetty", "overview"],
    "SE_Mooring_Post": ["steps", "quay", "timber"],
    "SE_Hoist": ["hoist", "quay", "timber"],
    "SE_Boat_Rowing": ["steps", "jetty", "quay"],
    "SE_Boat_Fishing": ["timber", "hoist", "overview"],
    "SE_Ship_Keel": ["sail", "overview", "jetty"],
    "SE_Ship_Cog": ["quay", "stern", "hoist"],
    "SE_Net_Rack": ["shore", "overview", "jetty"],
    "SE_Boat_Ashore": ["shore", "overview", "jetty"],
}
OVERVIEW = ["overview", "quay", "sail", "shore"]


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
            p = os.path.join(game, "harbour_%s.png" % v)
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: " + VIEW[v], f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)
    sheet = Image.new("RGB", (PANEL[0] * 2, PANEL[1] * 2), (28, 22, 17))
    d = ImageDraw.Draw(sheet)
    for i, v in enumerate(OVERVIEW):
        p = os.path.join(game, "harbour_%s.png" % v)
        if os.path.exists(p):
            at = ((i % 2) * PANEL[0], (i // 2) * PANEL[1])
            sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), at)
            label(d, (at[0] + 8, at[1] + 8), "In game: " + VIEW[v], f_small)
    path = os.path.join(out, "_harbour.jpg")
    sheet.save(path, quality=88, optimize=True)
    print("wrote", path)


if __name__ == "__main__":
    main()
