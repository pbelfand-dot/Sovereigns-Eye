"""Builds one contact sheet per kind of Status Wear for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <walk_dir> <out_dir> [stats.json]

Top row: Blender Cycles views on a stand-in villager (the outfit body, the
base head and a hairstyle), from `build_wear.py --review <cycles_dir>`.
Bottom row: the piece on villagers in the running game, from
`godot --path . res://tools/prefab_gallery.tscn -- <game_dir> wear` (and
WEAR_MODE=walk into <walk_dir>). A strip at the top gives the numbers.
"""
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

_spec = importlib.util.spec_from_file_location("commons_sheets", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "props", "village-commons", "source", "make_sheets.py"))
_commons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_commons)
PANEL, fit, font, label = _commons.PANEL, _commons.fit, _commons.font, _commons.label

# The gallery's villagers (tools/prefab_gallery.gd _wear): index -> who.
WHO = {0: "a farmer", 1: "a farmer", 2: "a miller", 3: "a merchant", 4: "a baker", 5: "a baker (bun let down)", 6: "a lord",
       7: "a lady", 8: "a king", 9: "a queen", 10: "a soldier", 11: "a guard captain", 12: "a dowager", 13: "a blacksmith",
       14: "a carpenter", 15: "an innkeeper", 16: "a housekeeper", 17: "an elder lord (a cap for a veil)"}
# Kind -> (title, pieces for the numbers, top row [(stem, caption)], bottom row [(kind, index, caption)]).
KINDS = {
    "Circlet": ("SE_Circlet", [("SE_Circlet_Short_M_front34", "Short hair, man (Blender)"), ("SE_Circlet_Long_F_front34", "Long hair, woman (Blender)"),
                               ("SE_Circlet_Long_F_side", "Side (Blender)")], [("head", 6), ("head", 7), ("body", 7)]),
    "Crown": ("SE_Crown", [("SE_Crown_Short_M_front34", "Short hair, man (Blender)"), ("SE_Crown_Long_F_front34", "Long hair, woman (Blender)"),
                           ("SE_Crown_Long_F_rear34", "Rear 3/4 (Blender)")], [("head", 8), ("head", 9), ("body", 9)]),
    "Helmet": ("SE_Helmet", [("SE_Helmet_M_front34", "Man (Blender)"), ("SE_Helmet_F_front34", "Woman (Blender)"),
                             ("SE_Helmet_M_side", "Side: the nasal (Blender)")], [("head", 10), ("head", 11), ("body", 10)]),
    "StrawHat": ("SE_StrawHat", [("SE_StrawHat_Short_M_front34", "Short hair, man (Blender)"), ("SE_StrawHat_Long_F_front34", "Long hair, woman (Blender)"),
                                 ("SE_StrawHat_Short_M_side", "Side (Blender)")], [("head", 0), ("head", 1), ("body", 0)]),
    "Cap": ("SE_Cap", [("SE_Cap_Short_M_front34", "Short hair, man (Blender)"), ("SE_Cap_Long_F_front34", "Long hair, woman (Blender)"),
                       ("SE_Cap_Short_M_rear34", "Rear 3/4 (Blender)")], [("head", 2), ("head", 3), ("head", 17)]),
    "BakerHat": ("SE_BakerHat", [("SE_BakerHat_Short_M_front34", "Short hair, man (Blender)"), ("SE_BakerHat_Long_F_front34", "Long hair, woman (Blender)"),
                                 ("SE_BakerHat_Short_M_side", "Side (Blender)")], [("head", 4), ("head", 5), ("body", 4)]),
    "Veil": ("SE_Veil", [("SE_Veil_F_front34", "Front 3/4 (Blender)"), ("SE_Veil_F_rear34", "Rear 3/4 (Blender)"),
                         ("SE_Veil_F_side", "Side (Blender)")], [("head", 12), ("head", 16), ("body", 12)]),
    "ApronLeather": ("SE_ApronLeather", [("SE_ApronLeather_M_front34", "Man (Blender)"), ("SE_ApronLeather_F_front34", "Woman (Blender)"),
                                         ("SE_ApronLeather_M_side", "Side (Blender)")], [("body", 13), ("body", 14), ("walk", 13)]),
    "ApronLinen": ("SE_ApronLinen", [("SE_ApronLinen_M_front34", "Man (Blender)"), ("SE_ApronLinen_F_front34", "Woman (Blender)"),
                                     ("SE_ApronLinen_F_side", "Side (Blender)")], [("body", 4), ("body", 16), ("walk", 15)]),
}


def main():
    cycles, game, walk, out = sys.argv[1:5]
    stats = json.load(open(sys.argv[5])) if len(sys.argv) > 5 else {}
    os.makedirs(out, exist_ok=True)
    f_small, f_big = font(18), font(26)
    for kind, (prefix, top, bottom) in KINDS.items():
        sheet = Image.new("RGB", (PANEL[0] * 3, 64 + PANEL[1] * 2), (28, 22, 17))
        d = ImageDraw.Draw(sheet)
        pieces = sorted(k for k in stats if k.startswith(prefix + "_"))
        tris = sorted({stats[k]["tris"] for k in pieces})
        head = "%s   %d pieces | %s tris each | %s" % (kind, len(pieces), "/".join(str(t) for t in tris),
                                                       ", ".join(sorted({m for k in pieces for m in stats[k]["materials"]})))
        d.text((16, 18), head, fill=(240, 220, 170), font=f_big)
        for i, (stem, t) in enumerate(top):
            p = os.path.join(cycles, stem + ".png")
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), t, f_small)
        for i, (view, idx) in enumerate(bottom):
            src = walk if view == "walk" else game
            p = os.path.join(src, "wear_%s_%02d.png" % ("head" if view == "head" else "body", idx))
            if os.path.exists(p):
                im = Image.open(p).convert("RGB")
                if view != "head":
                    w, h = im.size
                    im = im.crop((int(w * 0.25), 0, int(w * 0.75), int(h * 0.98)))
                sheet.paste(fit(im, PANEL), (i * PANEL[0], 64 + PANEL[1]))
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "In game: %s%s" % (WHO[idx], ", walking" if view == "walk" else ""), f_small)
        path = os.path.join(out, kind + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
