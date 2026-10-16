"""Builds one contact sheet per Farm & Field asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json] [patch_dir]

Top row: Blender Cycles views (front 3/4, rear 3/4, close detail) beside a
1.78 m mannequin. Bottom row: the asset in the running game (Godot, real
lighting), from `godot --path . res://tools/capture.tscn -- <seed> <dir> farm`:
the field from the map table, the gate at 3/4, the follow camera on foot,
each crop over the heir's shoulder, the haystacks, log pile and scarecrow.
Crops are judged in a mass: their top row ends with the crops as small
fields (`build_farm.py --patches <patch_dir>/crops`). A strip at the top
gives the numbers.
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

# Asset -> in-game shots (farm_<view>.png), "cycles:<view>" for a Blender view.
ASSETS = {
    "SE_Crop_Wheat": ["crop_wheat", "1_field", "cycles:gameplay"],
    "SE_Crop_Barley": ["crop_barley", "1_field", "cycles:gameplay"],
    "SE_Crop_Flax": ["crop_flax", "1_field", "cycles:gameplay"],
    "SE_Crop_Cabbage": ["crop_cabbage", "1_field", "cycles:gameplay"],
    "SE_Crop_Turnip": ["crop_turnip", "1_field", "cycles:gameplay"],
    "SE_Fence_Wattle": ["0_gate", "0_field", "0_gameplay"],
    "SE_Fence_Rail": ["1_gate", "1_field", "1_gameplay"],
    "SE_Fence_Paled": ["3_gate", "3_field", "3_gameplay"],
    "SE_Gate_Wattle": ["0_gate", "0_gameplay", "cycles:gameplay"],
    "SE_Gate_Rail": ["1_gate", "1_gameplay", "cycles:gameplay"],
    "SE_Gate_Paled": ["3_gate", "3_gameplay", "cycles:gameplay"],
    "SE_Haycock": ["se_haycock", "overview", "cycles:gameplay"],
    "SE_Hayrick": ["se_hayrick", "overview", "cycles:gameplay"],
    "SE_Stooks": ["se_stooks", "overview", "cycles:gameplay"],
    "SE_LogPile": ["se_logpile", "overview", "cycles:gameplay"],
    "SE_Scarecrow": ["scarecrow", "1_field", "cycles:gameplay"],
}
TIER_NAMES = {"0": "Hamlet", "1": "Village", "3": "Town"}


def title(view):
    if view.startswith("crop_"):
        return "In game: over the heir's shoulder"
    if view.startswith("se_") or view == "scarecrow":
        return "In game: in the village"
    if view == "overview":
        return "In game: the village (map table)"
    tier, kind = view.split("_", 1)
    return "In game: %s (%s)" % ({"gate": "the gate at 3/4", "field": "the field (map table)",
                                  "gameplay": "on foot, follow camera"}[kind], TIER_NAMES[tier])


def main():
    cycles, game, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stats = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
    patches = sys.argv[5] if len(sys.argv) > 5 else None
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
            st.get("collision", ""),
        ] if x))
        d.text((16, 18), head, fill=(240, 220, 170), font=f_big)
        top = [("front34", "Front 3/4 (Blender)"), ("rear34", "Rear 3/4 (Blender)"), ("close", "Close detail (Blender)")]
        if name.startswith("SE_Crop_") and patches:
            top = [("close", "Close detail (Blender)"), ("front34", "Front 3/4 (Blender)"), ("patch:mid", "The crops as small fields (Blender)")]
        for i, (v, t) in enumerate(top):
            p = os.path.join(cycles, "%s_%s.png" % (name, v))
            if v.startswith("patch:"):
                p = os.path.join(patches, "crops_%s.png" % v[6:])
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, v in enumerate(views):
            if v.startswith("cycles:"):
                p, t = os.path.join(cycles, "%s_%s.png" % (name, v[7:])), "Gameplay angle beside a 1.78 m figure (Blender)"
            else:
                p, t = os.path.join(game, "farm_%s.png" % v), title(v)
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), t, f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
