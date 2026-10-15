"""Builds one contact sheet per Village Commons asset for review.

    python3 make_sheets.py <cycles_dir> <game_dir> <out_dir> [stats.json]

Top row: Blender Cycles turntable views (front 3/4, rear 3/4, close detail).
Bottom row: the asset in the running game (Godot, real lighting): the real
gameplay camera or a close in-game view, 3/4 beside the heir for scale, and
the square from the map table. A strip at the top gives the numbers.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# Asset -> (charter tier whose in-game shots show it, in-game views)
ASSETS = {
    "SE_Well_Hamlet": (0, ["gameplay", "front34", "square"]),
    "SE_Well_Village": (1, ["gameplay", "front34", "rear34"]),
    "SE_Well_Town": (2, ["gameplay", "front34", "close"]),
    "SE_Banner_Village": (1, ["banner", "gameplay", "cycles:gameplay"]),
    "SE_Banner_MarketTown": (2, ["banner", "gameplay", "cycles:gameplay"]),
    "SE_Banner_Town": (3, ["banner", "square", "cycles:gameplay"]),
    "SE_Signpost_Rough": (0, ["signpost", "square", "cycles:gameplay"]),
    "SE_Signpost_Village": (1, ["signpost", "square", "cycles:gameplay"]),
    "SE_Signpost_Town": (3, ["signpost", "square", "cycles:gameplay"]),
}
TIER_NAMES = ["Hamlet", "Village", "Market Town", "Town"]
PANEL = (640, 400)


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def fit(img, size):
    w, h = img.size
    s = max(size[0] / w, size[1] / h)
    img = img.resize((int(w * s + 0.5), int(h * s + 0.5)), Image.LANCZOS)
    x = (img.size[0] - size[0]) // 2
    y = (img.size[1] - size[1]) // 2
    return img.crop((x, y, x + size[0], y + size[1]))


def label(draw, xy, text, f):
    x, y = xy
    tw = draw.textlength(text, font=f)
    draw.rectangle((x, y, x + tw + 14, y + f.size + 10), fill=(20, 16, 12))
    draw.text((x + 7, y + 4), text, fill=(236, 214, 160), font=f)


def main():
    cycles, game, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stats = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else {}
    os.makedirs(out, exist_ok=True)
    f_small, f_big = font(18), font(26)
    for name, (tier, views) in ASSETS.items():
        sheet = Image.new("RGB", (PANEL[0] * 3, 64 + PANEL[1] * 2), (28, 22, 17))
        d = ImageDraw.Draw(sheet)
        st = stats.get(name, {})
        head = "%s   %s" % (name, " | ".join(x for x in [
            "%d tris" % st["tris"] if "tris" in st else "",
            "%d materials" % st["materials"] if "materials" in st else "",
            st.get("size", ""),
            "LODs %s" % st["lods"] if "lods" in st else "",
            st.get("collision", ""),
        ] if x))
        d.text((16, 18), head, fill=(240, 220, 170), font=f_big)
        top = [("front34", "Front 3/4 (Blender)"), ("rear34", "Rear 3/4 (Blender)"), ("close", "Close detail (Blender)")]
        for i, (v, title) in enumerate(top):
            p = os.path.join(cycles, "%s_%s.png" % (name, v))
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64))
                label(d, (i * PANEL[0] + 8, 72), title, f_small)
        for i, v in enumerate(views):
            if v.startswith("cycles:"):
                p = os.path.join(cycles, "%s_%s.png" % (name, v[7:]))
                if os.path.exists(p):
                    sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                    label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "Gameplay angle beside a 1.78 m figure (Blender)", f_small)
                continue
            p = os.path.join(game, "commons_%d_%s.png" % (tier, v))
            if os.path.exists(p):
                sheet.paste(fit(Image.open(p).convert("RGB"), PANEL), (i * PANEL[0], 64 + PANEL[1]))
                title = {"gameplay": "In game: gameplay camera", "front34": "In game: 3/4 beside the heir",
                         "rear34": "In game: from behind", "close": "In game: close", "square": "In game: the square (map table)",
                         "banner": "In game: on the square", "signpost": "In game: at the road's end"}[v]
                label(d, (i * PANEL[0] + 8, 72 + PANEL[1]), "%s (%s)" % (title, TIER_NAMES[tier]), f_small)
        path = os.path.join(out, name + ".jpg")
        sheet.save(path, quality=88, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
