"""Paints the Training Yard atlas (T_Training_BaseColor.png), 512 x 512.

    python3 paint_training.py [out.png]

Regions (image pixels, y down). "Wraps" means it repeats seamlessly in x.
  y   0-128  x   0-128  heater shield: quarterly red and gold      quintain, racks
             x 128-256  heater shield: blue, a white chevron       racks
             x 256-384  round shield: green, a yellow cross        racks
             x 384-512  round shield: red, much battered           racks
  y 128-256  turf: grass over earth, worn where it was cut (wraps)  archery butts
  y 256-384  trodden earth with sand (wraps)                        sparring ring, butts' feet
  y 384-512  x   0-128  white linen clout, pegged                   archery butts
             x 128-256  goose fletching, grey and white             arrows
             x 256-384  hemp rope, twisted (wraps in its cell)      ring ropes, bindings
             x 384-512  hacked oak end grain and cuts               pells
The straw and sacking come from the Farm & Field atlas; wood, iron and
stone from the village kit's trim sheets.

Hand-painted look in the village kit's palette. Painted at 2x and
downsampled. Deterministic (fixed seeds).
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2
W = H = 512 * S


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shade(c, rng, amt):
    """The same colour a little lighter or darker (no hue shift)."""
    k = rng.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v + k))) for v in c)


def wear(img, rng, count, size, color, alpha=0.5):
    """Scuffs and chips: small soft blobs of `color` over the paint."""
    over = Image.new("RGB", img.size, color)
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    w, h = img.size
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(size * 0.4, size) * S
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=int(255 * alpha))
    return Image.composite(over, img, mask.filter(ImageFilter.GaussianBlur(1.2 * S)))


def wood_ground(w, h, rng, base):
    """Planks under the paint, showing at the chipped edges."""
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    for _ in range(60):
        y = rng.uniform(0, h)
        d.line((0, y, w, y + rng.uniform(-3, 3) * S), fill=shade(lerp(base, (40, 26, 16), 0.3), rng, 8), width=S)
    return img


def heater(w, h, field, seed, charge):
    """A heater shield face filling the cell: field colour(s), a charge, a
    darker rim and wear (the model cuts the outline; the cell is its front)."""
    rng = random.Random(seed)
    img = wood_ground(w, h, rng, (122, 88, 56))
    d = ImageDraw.Draw(img)
    m = 7 * S
    if charge == "quarterly":
        a, b = field
        d.rectangle((m, m, w // 2, h // 2), fill=a)
        d.rectangle((w // 2, m, w - m, h // 2), fill=b)
        d.rectangle((m, h // 2, w // 2, h - m), fill=b)
        d.rectangle((w // 2, h // 2, w - m, h - m), fill=a)
    else:
        d.rectangle((m, m, w - m, h - m), fill=field[0])
    if charge == "chevron":
        t = 15 * S
        d.polygon([(m, h * 0.72), (w / 2, h * 0.30), (w - m, h * 0.72), (w - m, h * 0.72 + t), (w / 2, h * 0.30 + t), (m, h * 0.72 + t)], fill=field[1])
    elif charge == "cross":
        t = 12 * S
        d.rectangle((w / 2 - t, m, w / 2 + t, h - m), fill=field[1])
        d.rectangle((m, h / 2 - t, w - m, h / 2 + t), fill=field[1])
    elif charge == "boss":
        r = 15 * S
        d.ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), fill=(84, 80, 76), outline=(48, 44, 42), width=2 * S)
        d.ellipse((w / 2 - r * 0.45, h / 2 - r * 0.6, w / 2, h / 2 - r * 0.15), fill=(150, 146, 138))
    d.rectangle((0, 0, w - 1, h - 1), outline=(58, 42, 30), width=m)
    img = wear(img, rng, 26, 9, (110, 80, 52), 0.55)
    img = wear(img, rng, 10, 5, (46, 32, 22), 0.6)   # cuts from practice blows
    return img


def turf(w, h, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (92, 128, 52))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 18)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        c = lerp((70, 104, 40), (150, 178, 80), rng.random() ** 0.9)
        L = rng.uniform(4, 10) * S
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + rng.uniform(-2, 2) * S, y - L), fill=c, width=max(1, int(1.5 * S)))
    # Bare earth where arrows and feet have worn it.
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    for _ in range(14):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(10, 26) * S
        for ox in (-w, 0, w):
            md.ellipse((x + ox - r, y - r * 0.5, x + ox + r, y + r * 0.5), fill=200)
    earth = Image.new("RGB", (w, h), (112, 86, 58))
    return Image.composite(earth, img, mask.filter(ImageFilter.GaussianBlur(6 * S)))


def earth(w, h, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (150, 122, 88))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 7)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.6, 2.2) * S
        c = shade(lerp((120, 94, 64), (196, 170, 128), rng.random()), rng, 6)
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=c)
    # Scuffed footprints and drag marks.
    for _ in range(24):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        L = rng.uniform(20, 60) * S
        a = rng.uniform(0, math.tau)
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + math.cos(a) * L, y + math.sin(a) * L), fill=(118, 92, 64), width=int(rng.uniform(3, 7) * S))
    return img.filter(ImageFilter.GaussianBlur(0.7 * S))


def clout(w, h, seed):
    """A square of white linen pegged at its centre, creased and holed."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (232, 226, 210))
    d = ImageDraw.Draw(img)
    for i in range(0, w, 3 * S):
        d.line((i, 0, i, h), fill=(222, 214, 196), width=1)
    for _ in range(8):     # creases
        x = rng.uniform(0, w)
        d.line((x, 0, x + rng.uniform(-20, 20) * S, h), fill=(208, 200, 182), width=2 * S)
    for _ in range(9):     # arrow holes
        x, y = rng.uniform(w * 0.15, w * 0.85), rng.uniform(h * 0.15, h * 0.85)
        r = rng.uniform(1.5, 3) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=(70, 56, 40))
    r = 6 * S
    d.ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), fill=(110, 80, 52), outline=(70, 50, 32), width=S)
    return img


def fletching(w, h, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (180, 176, 168))
    d = ImageDraw.Draw(img)
    for i in range(w // (2 * S)):
        x = i * 2 * S
        c = shade((206, 202, 194) if (i // 10) % 2 == 0 else (128, 124, 120), rng, 10)
        d.line((x, 0, x - 10 * S, h), fill=c, width=2 * S)
    return img


def rope(w, h, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (170, 140, 92))
    d = ImageDraw.Draw(img)
    step = 10 * S
    for i in range(-2, w // step + 3):
        x = i * step
        d.polygon([(x, 0), (x + step * 0.6, 0), (x + step * 0.6 + h * 0.45, h), (x + h * 0.45, h)], fill=shade((196, 166, 112), rng, 8))
        d.line((x + h * 0.45, h, x, 0), fill=(116, 92, 58), width=2 * S)
    return img


def end_grain(w, h, seed):
    """Oak end grain ringed round the pith, and fresh cuts where blades bit."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (150, 112, 72))
    d = ImageDraw.Draw(img)
    cx, cy = w * 0.5, h * 0.5
    for r in range(4 * S, int(w * 0.7), 4 * S):
        d.ellipse((cx - r, cy - r * 0.95, cx + r, cy + r * 0.95), outline=shade((118, 84, 52), rng, 10), width=S)
    for _ in range(5):
        a = rng.uniform(0, math.tau)
        d.line((cx, cy, cx + math.cos(a) * w * 0.45, cy + math.sin(a) * h * 0.45), fill=(92, 64, 40), width=S)
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures", "T_Training_BaseColor.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    c = 128 * S
    atlas = Image.new("RGB", (W, H), (0, 0, 0))
    atlas.paste(heater(c, c, ((176, 40, 34), (222, 170, 48)), 1, "quarterly"), (0, 0))
    atlas.paste(heater(c, c, ((46, 78, 150), (236, 230, 214)), 2, "chevron"), (c, 0))
    atlas.paste(heater(c, c, ((58, 112, 58), (226, 190, 60)), 3, "cross"), (2 * c, 0))
    atlas.paste(heater(c, c, ((160, 46, 36),), 4, "boss"), (3 * c, 0))
    atlas.paste(turf(W, c, 5), (0, c))
    atlas.paste(earth(W, c, 6), (0, 2 * c))
    atlas.paste(clout(c, c, 7), (0, 3 * c))
    atlas.paste(fletching(c, c, 8), (c, 3 * c))
    atlas.paste(rope(c, c, 9), (2 * c, 3 * c))
    atlas.paste(end_grain(c, c, 10), (3 * c, 3 * c))
    atlas = atlas.resize((512, 512), Image.LANCZOS)
    atlas.save(out, optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
