"""Paints the charter banner cloth atlas (T_Commons_Banner_BaseColor.png).

    python3 paint_banner.py [out.png]

1024 x 1024, three banner faces side by side (341 px wide, rows 0-800):
  column 0  Village      - a golden wheat sheaf
  column 1  Market Town  - golden balance scales
  column 2  Town         - a crowned three-towered castle
Rows 800-1024 hold gold fringe, cord and gilding for tassels and finials.
Crimson and gold are the charter colours; the cloth gets a soft weave,
painted folds and an embroidered border so it reads as fabric, not paint.
Painted at 2x and downsampled for clean edges.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2  # supersampling
W, H = 1024 * S, 1024 * S
COL = W // 3
FACE_H = 800 * S

CRIMSON = (143, 36, 51)
CRIMSON_DARK = (98, 22, 34)
CRIMSON_LIGHT = (176, 58, 70)
GOLD = (222, 176, 74)
GOLD_DARK = (150, 104, 38)
GOLD_LIGHT = (246, 214, 128)


def noise_layer(size, scale, seed, amp):
    rng = random.Random(seed)
    small = Image.new("L", (max(1, size[0] // scale), max(1, size[1] // scale)))
    small.putdata([128 + int(rng.uniform(-amp, amp)) for _ in range(small.size[0] * small.size[1])])
    return small.resize(size, Image.BICUBIC)


def cloth(size, seed):
    """Crimson cloth: base colour, weave, painted vertical folds."""
    w, h = size
    img = Image.new("RGB", size, CRIMSON)
    px = img.load()
    rng = random.Random(seed)
    folds = [(rng.uniform(0, w), rng.uniform(w * 0.05, w * 0.12), rng.uniform(-1, 1)) for _ in range(5)]
    for y in range(0, h):
        t = y / h
        for x in range(0, w):
            f = 0.0
            for cx, width, sgn in folds:
                f += sgn * math.exp(-((x - cx) / width) ** 2) * (0.3 + 0.7 * t)
            # Darker under the sleeve and toward the hem, lighter mid-cloth.
            shade = 1.0 + 0.10 * f - 0.18 * math.exp(-y / (h * 0.06)) - 0.1 * t * t
            r, g, b = CRIMSON
            px[x, y] = (int(r * shade), int(g * shade), int(b * shade))
    weave = noise_layer(size, 3 * S, seed + 1, 14)
    warp = noise_layer((w, 1), 2 * S, seed + 2, 22).resize(size)
    tex = ImageChops.add(weave, warp, scale=2.0, offset=0)
    img = ImageChops.multiply(img, Image.merge("RGB", [tex.point(lambda v: min(255, v + 127))] * 3))
    return img


def border(draw, box, width):
    x0, y0, x1, y1 = box
    draw.rectangle(box, outline=GOLD_DARK, width=width + 2 * S)
    draw.rectangle((x0 + S, y0 + S, x1 - S, y1 - S), outline=GOLD, width=width)
    # Stitches along the inner edge.
    inner = (x0 + width + 6 * S, y0 + width + 6 * S, x1 - width - 6 * S, y1 - width - 6 * S)
    step = 14 * S
    ix0, iy0, ix1, iy1 = inner
    for x in range(int(ix0), int(ix1), step):
        draw.line((x, iy0, x + step // 2, iy0), fill=GOLD, width=2 * S)
        draw.line((x, iy1, x + step // 2, iy1), fill=GOLD, width=2 * S)
    for y in range(int(iy0), int(iy1), step):
        draw.line((ix0, y, ix0, y + step // 2), fill=GOLD, width=2 * S)
        draw.line((ix1, y, ix1, y + step // 2), fill=GOLD, width=2 * S)


def outlined(draw, shape_fn):
    """Draws a charge twice: a dark outline pass, then the gold fill."""
    shape_fn(draw, GOLD_DARK, 5 * S)
    shape_fn(draw, GOLD, 0)


def wheat(draw, cx, cy, s):
    """A sheaf: five slender ears fanning up from a band, stalks flaring below."""
    def leaf(c, ang, length, width, grow):
        dx, dy = math.cos(ang), math.sin(ang)
        px, py = -dy, dx
        half = length / 2 + grow / 2
        wd = width / 2 + grow / 2
        return [(c[0] + dx * half, c[1] + dy * half), (c[0] + px * wd, c[1] + py * wd),
                (c[0] - dx * half * 0.8, c[1] - dy * half * 0.8), (c[0] - px * wd, c[1] - py * wd)]

    def shape(d, color, grow):
        g = grow
        for k in range(-4, 5):
            d.line((cx + k * 4 * s, cy + 50 * s, cx + k * 19 * s, cy + 205 * s), fill=color, width=int(8 * s) + g)
        for k in (-2, -1, 0, 1, 2):
            a = math.radians(-90 + k * 15)
            bx, by = cx + k * 7 * s, cy + 30 * s
            dx, dy = math.cos(a), math.sin(a)
            d.line((bx, by, bx + dx * 120 * s, by + dy * 120 * s), fill=color, width=int(6 * s) + g)
            for j in range(6):
                t = (112 + j * 19) * s
                gx, gy = bx + dx * t, by + dy * t
                for side in (-1, 1):
                    ga = a + side * 0.55
                    c = (gx + math.cos(ga) * 9 * s, gy + math.sin(ga) * 9 * s)
                    d.polygon(leaf(c, ga - side * 0.25, (24 - j) * s, 12 * s, g), fill=color)
                    # Awns: fine whiskers off each grain.
                    tip = (c[0] + math.cos(ga - side * 0.1) * 30 * s, c[1] + math.sin(ga - side * 0.1) * 30 * s)
                    d.line((c[0], c[1], tip[0], tip[1]), fill=color, width=int(2 * s) + g)
            top = (bx + dx * 232 * s, by + dy * 232 * s)
            d.polygon(leaf(top, a, 26 * s, 13 * s, g), fill=color)
        d.rounded_rectangle((cx - 36 * s - g / 2, cy + 26 * s - g / 2, cx + 36 * s + g / 2, cy + 58 * s + g / 2), radius=9 * s, fill=color)
        if g == 0:
            for k in (-1, 1):
                d.line((cx - 34 * s, cy + 42 * s + k * 8 * s, cx + 34 * s, cy + 42 * s + k * 8 * s), fill=GOLD_DARK, width=int(2 * s))
    outlined(draw, shape)


def scales(draw, cx, cy, s):
    def shape(d, color, grow):
        g = grow
        d.rectangle((cx - 7 * s - g / 2, cy - 130 * s, cx + 7 * s + g / 2, cy + 150 * s), fill=color)          # post
        d.polygon([(cx - 60 * s - g, cy + 170 * s + g / 2), (cx + 60 * s + g, cy + 170 * s + g / 2), (cx + 20 * s, cy + 140 * s), (cx - 20 * s, cy + 140 * s)], fill=color)  # foot
        d.ellipse((cx - 18 * s - g / 2, cy - 160 * s - g / 2, cx + 18 * s + g / 2, cy - 124 * s + g / 2), fill=color)  # knob
        d.line((cx - 120 * s, cy - 100 * s, cx + 120 * s, cy - 100 * s), fill=color, width=int(12 * s) + g)    # beam
        for sx in (-1, 1):
            px = cx + sx * 112 * s
            d.line((px, cy - 100 * s, px - 50 * s, cy + 20 * s), fill=color, width=int(4 * s) + g)
            d.line((px, cy - 100 * s, px + 50 * s, cy + 20 * s), fill=color, width=int(4 * s) + g)
            d.chord((px - 62 * s - g, cy - 10 * s - g, px + 62 * s + g, cy + 50 * s + g), 0, 180, fill=color)
    outlined(draw, shape)


def castle(draw, cx, cy, s):
    def shape(d, color, grow):
        g = grow / 2
        # Three towers with crenellations.
        for tx, tw, top in ((-90, 56, -60), (0, 74, -110), (90, 56, -60)):
            x0, x1 = cx + (tx - tw / 2) * s - g, cx + (tx + tw / 2) * s + g
            d.rectangle((x0, cy + top * s - g, x1, cy + 150 * s + g), fill=color)
            n = 3
            mw = (x1 - x0) / (2 * n - 1)
            for k in range(n):
                d.rectangle((x0 + 2 * k * mw, cy + (top - 22) * s - g, x0 + (2 * k + 1) * mw, cy + top * s), fill=color)
        d.rectangle((cx - 120 * s - g, cy + 20 * s - g, cx + 120 * s + g, cy + 150 * s + g), fill=color)  # curtain wall
        if grow == 0:
            # Gate and windows cut back to crimson.
            d.chord((cx - 26 * s, cy + 60 * s, cx + 26 * s, cy + 120 * s), 180, 360, fill=CRIMSON_DARK)
            d.rectangle((cx - 26 * s, cy + 90 * s, cx + 26 * s, cy + 150 * s), fill=CRIMSON_DARK)
            for wx in (-90, 90):
                d.rectangle((cx + (wx - 7) * s, cy - 20 * s, cx + (wx + 7) * s, cy + 10 * s), fill=CRIMSON_DARK)
            d.rectangle((cx - 8 * s, cy - 70 * s, cx + 8 * s, cy - 35 * s), fill=CRIMSON_DARK)
        # The crown above.
        base_y = cy - 175 * s
        pts = [(cx - 70 * s, base_y + 30 * s), (cx - 78 * s, base_y - 30 * s), (cx - 38 * s, base_y + 2 * s),
               (cx, base_y - 48 * s), (cx + 38 * s, base_y + 2 * s), (cx + 78 * s, base_y - 30 * s), (cx + 70 * s, base_y + 30 * s)]
        if grow:
            pts = [(x + (grow * 0.4 if x > cx else -grow * 0.4), y + (grow * 0.4 if y > base_y else -grow * 0.4)) for x, y in pts]
        d.polygon(pts, fill=color)
        for x, y in ((cx - 78 * s, base_y - 30 * s), (cx, base_y - 48 * s), (cx + 78 * s, base_y - 30 * s)):
            r = 11 * s + g
            d.ellipse((x - r, y - r, x + r, y + r), fill=color)
    outlined(draw, shape)


def gold_strip(img, box, seed, kind):
    """Gold fringe threads, cord twist or plain gilding."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=GOLD)
    rng = random.Random(seed)
    if kind == "fringe":
        for x in range(x0, x1, 4 * S):
            c = GOLD_DARK if rng.random() < 0.5 else GOLD_LIGHT
            d.line((x, y0, x + rng.randint(-S, S), y1), fill=c, width=S)
    elif kind == "cord":
        for x in range(x0 - (y1 - y0), x1, 10 * S):
            d.line((x, y1, x + (y1 - y0), y0), fill=GOLD_DARK, width=3 * S)
            d.line((x + 4 * S, y1, x + 4 * S + (y1 - y0), y0), fill=GOLD_LIGHT, width=2 * S)
    else:
        for y in range(y0, y1, S):
            t = (y - y0) / max(1, y1 - y0)
            k = 0.75 + 0.45 * math.sin(t * math.pi * 3) ** 2
            d.line((x0, y, x1, y), fill=tuple(min(255, int(c * k)) for c in GOLD))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "T_Commons_Banner_BaseColor.png")
    img = Image.new("RGB", (W, H), GOLD)
    charges = (wheat, scales, castle)
    for i, charge in enumerate(charges):
        face = cloth((COL, FACE_H), seed=10 + i)
        d = ImageDraw.Draw(face)
        # Sleeve band across the top where the cloth wraps the crossbar.
        d.rectangle((0, 0, COL, 46 * S), fill=CRIMSON_DARK)
        d.line((0, 46 * S, COL, 46 * S), fill=GOLD_DARK, width=3 * S)
        border(d, (14 * S, 60 * S, COL - 14 * S, FACE_H - 14 * S), 10 * S + i * 3 * S)
        cx, cy = COL // 2, int(FACE_H * 0.47)
        charge(d, cx, cy, S * (1.0 if i != 2 else 0.95))
        # A soft fold shadow pass on top of the charge so it sits in the cloth.
        shade = Image.new("L", face.size, 255)
        sd = ImageDraw.Draw(shade)
        rng = random.Random(40 + i)
        for _ in range(3):
            x = rng.uniform(0.15, 0.85) * COL
            sd.rectangle((x, 0, x + rng.uniform(10, 26) * S, FACE_H), fill=222)
        shade = shade.filter(ImageFilter.GaussianBlur(14 * S))
        face = ImageChops.multiply(face, Image.merge("RGB", [shade] * 3))
        img.paste(face, (i * COL, 0))
    gold_strip(img, (0, FACE_H, W, FACE_H + 70 * S), 1, "fringe")
    gold_strip(img, (0, FACE_H + 70 * S, W, FACE_H + 130 * S), 2, "cord")
    gold_strip(img, (0, FACE_H + 130 * S, W, H), 3, "gild")
    img = img.resize((W // S, H // S), Image.LANCZOS)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out, optimize=True)
    print("wrote", os.path.abspath(out), img.size)


if __name__ == "__main__":
    main()
