"""Paints the Status Wear atlas (T_Wear_BaseColor*.png), 512 x 1024, one per
colorway: the felt (caps) and the wool (robes, gowns, coats) are dyed per
colorway, everything else is shared.

    python3 paint_wear.py [out_dir]

Regions (image pixels, y down), 128 px cells:
  y   0-128  x   0-128  straw weave              straw hat crown and brim
             x 128-256  dark straw band           the hat band
             x 256-384  bleached linen            veil, baker's cap
             x 384-512  cream linen               linen apron
  y 128-256  x   0-256  dyed felt (per colorway)  cap
             x 256-384  felt band, darker         the cap's rolled brim
             x 384-512  linen hem, stitched       apron and veil edges
  y 256-384  x   0-128  gold                      circlet and crown
             x 128-256  engraved gold band        crown band
             x 256-320  ruby                      gems
             x 320-384  sapphire                  gems
             x 384-512  steel                     helmet
  y 384-512  x   0-128  oiled leather             smith's apron
             x 128-256  dark leather straps       apron straps, helmet rim
             x 256-384  brass                     buckles, rivets
             x 384-512  iron dark                 helmet nasal and band
  y 512-640  x   0-256  dyed wool (per colorway)  robes, gowns, coats
             x 256-384  dyed wool in shadow        lining, folds
             x 384-512  undyed linen lining        sleeves' insides
  y 640-768  x   0-128  gold braid                gown and coat trim
             x 128-256  ermine                    a royal's trim
             x 256-384  hemp cord                 a robe's girdle
             x 384-512  embroidered band (dyed)   necklines
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2
W = 512 * S
H = 1024 * S
U = 128 * S
# Colorways: name, felt colour, swatch (the clothing colour it suits best).
COLORWAYS = [
    ("russet", (138, 64, 40), "#8a4028"),
    ("woad", (62, 86, 124), "#3e567c"),
    ("green", (66, 92, 52), "#425c34"),
    ("black", (44, 38, 36), "#2c2624"),
    ("crimson", (138, 31, 47), "#8a1f2f"),
    ("purple", (91, 42, 134), "#5b2a86"),
    ("royal", (31, 63, 122), "#1f3f7a"),
    ("cream", (226, 216, 196), "#e8e0d0"),
    ("brown", (96, 76, 58), "#5a4a3a"),
    ("grey", (78, 78, 80), "#4a4a4a"),
]


def jitter(c, rng, amt):
    return tuple(max(0, min(255, int(v + rng.uniform(-amt, amt)))) for v in c)


def shade(c, rng, amt):
    k = rng.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v + k))) for v in c)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def straw(w, h, base, seed, band=False):
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    step = 6 * S
    for y in range(0, h, step):
        for x in range(0, w, step):
            over = ((x // step) + (y // step)) % 2 == 0
            c = shade(lerp(base, (255, 240, 180) if over else (120, 90, 40), 0.18), rng, 10)
            if over:
                d.rectangle((x, y + 1, x + step, y + step - 2), fill=c)
            else:
                d.rectangle((x + 1, y, x + step - 2, y + step), fill=c)
    if band:
        for y in range(0, h, 10 * S):
            d.line((0, y, w, y), fill=lerp(base, (0, 0, 0), 0.3), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.7 * S))


def cloth(w, h, base, seed, weave=0.05, hem=False):
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for y in range(0, h, 3 * S):
        d.line((0, y, w, y), fill=lerp(base, (0, 0, 0), weave), width=1)
    for x in range(0, w, 3 * S):
        d.line((x, 0, x, h), fill=lerp(base, (255, 255, 255), weave * 0.8), width=1)
    for _ in range(30):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(10, 26) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=shade(base, rng, 5))
    img = img.filter(ImageFilter.GaussianBlur(1.0 * S))
    if hem:
        d = ImageDraw.Draw(img)
        for y in range(8 * S, h, 16 * S):
            for x in range(0, w, 6 * S):
                d.line((x, y, x + 3 * S, y), fill=lerp(base, (60, 50, 40), 0.45), width=S)
    return img


def felt(w, h, base, seed, band=False):
    img = Image.new("RGB", (w, h), lerp(base, (0, 0, 0), 0.25) if band else base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(500):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1, 3) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=shade(lerp(base, (0, 0, 0), 0.25) if band else base, rng, 9))
    if band:
        for y in range(0, h, 16 * S):
            d.line((0, y, w, y), fill=lerp(base, (0, 0, 0), 0.45), width=2 * S)
    return img.filter(ImageFilter.GaussianBlur(0.9 * S))


def metal(w, h, base, seed, engraved=False, hi=(255, 255, 255)):
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for y in range(h):
        t = 0.5 + 0.5 * math.sin(y / h * math.pi * 3.0)
        d.line((0, y, w, y), fill=lerp(base, hi, 0.22 * t))
    for _ in range(40):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        d.line((x, y, x + rng.uniform(8, 30) * S, y + rng.uniform(-2, 2) * S), fill=lerp(base, (0, 0, 0), 0.15), width=1)
    if engraved:
        for x in range(0, w, 16 * S):
            d.ellipse((x + 3 * S, h * 0.3, x + 13 * S, h * 0.7), outline=lerp(base, (70, 40, 10), 0.5), width=2 * S)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def gem(w, h, base):
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    d.ellipse((w * 0.15, h * 0.15, w * 0.55, h * 0.45), fill=lerp(base, (255, 255, 255), 0.55))
    return img.filter(ImageFilter.GaussianBlur(3 * S))


def leather(w, h, base, seed, dark=False):
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(160):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(4, 16) * S
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=jitter(base, rng, 10))
    for _ in range(18):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        d.line((x, y, x + rng.uniform(-30, 30) * S, y + rng.uniform(-10, 10) * S), fill=lerp(base, (0, 0, 0), 0.3), width=S)
    if dark:
        for x in (6 * S, w - 6 * S):
            for y in range(0, h, 8 * S):
                d.line((x, y, x, y + 4 * S), fill=lerp(base, (230, 210, 170), 0.5), width=S)
    return img.filter(ImageFilter.GaussianBlur(1.0 * S))


def wool(w, h, base, seed, shadow=False):
    """Fulled wool: a soft twill with faint vertical drape lines."""
    c = lerp(base, (0, 0, 0), 0.28) if shadow else base
    img = Image.new("RGB", (w, h), c)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for y in range(0, h, 4 * S):
        d.line((0, y, w, y + 4 * S), fill=lerp(c, (0, 0, 0), 0.07), width=1)
    for _ in range(14):
        x = rng.uniform(0, w)
        d.line((x, 0, x + rng.uniform(-6, 6) * S, h), fill=lerp(c, (0, 0, 0), 0.12), width=int(3 * S))
        d.line((x + 4 * S, 0, x + 4 * S, h), fill=lerp(c, (255, 255, 255), 0.06), width=int(2 * S))
    for _ in range(300):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1, 2.5) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=shade(c, rng, 7))
    return img.filter(ImageFilter.GaussianBlur(1.0 * S))


def braid(w, h, seed):
    base = (214, 168, 64)
    img = Image.new("RGB", (w, h), lerp(base, (0, 0, 0), 0.25))
    d = ImageDraw.Draw(img)
    step = 10 * S
    for x in range(-step, w + step, step):
        for y in range(0, h, step):
            d.polygon([(x, y), (x + step // 2, y + step // 2), (x, y + step), (x - step // 2, y + step // 2)], fill=base,
                      outline=lerp(base, (90, 60, 10), 0.6))
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def ermine(w, h, seed):
    img = Image.new("RGB", (w, h), (238, 236, 230))
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(400):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1, 3) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=shade((238, 236, 230), rng, 10))
    for _ in range(14):  # the black tails
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        d.polygon([(x, y), (x + 3 * S, y + 9 * S), (x - 3 * S, y + 9 * S)], fill=(30, 28, 28))
    return img.filter(ImageFilter.GaussianBlur(0.7 * S))


def cord(w, h, seed):
    base = (176, 150, 104)
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    for x in range(-h, w, 7 * S):
        d.line((x, h, x + h, 0), fill=lerp(base, (60, 40, 20), 0.35), width=2 * S)
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def embroidered(w, h, base, seed):
    img = Image.new("RGB", (w, h), lerp(base, (0, 0, 0), 0.2))
    d = ImageDraw.Draw(img)
    gold = (220, 176, 70)
    for y in (6 * S, h - 8 * S):
        d.line((0, y, w, y), fill=gold, width=2 * S)
    for x in range(8 * S, w, 18 * S):
        cy = h // 2
        d.ellipse((x - 4 * S, cy - 4 * S, x + 4 * S, cy + 4 * S), outline=gold, width=2 * S)
        d.line((x + 4 * S, cy, x + 14 * S, cy), fill=gold, width=S)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
    os.makedirs(out, exist_ok=True)
    shared = Image.new("RGB", (W, H))
    shared.paste(straw(U, U, (214, 182, 104), 1), (0, 0))
    shared.paste(straw(U, U, (150, 110, 58), 2, band=True), (U, 0))
    shared.paste(cloth(U, U, (238, 234, 222), 3), (2 * U, 0))
    shared.paste(cloth(U, U, (222, 208, 176), 4), (3 * U, 0))
    shared.paste(cloth(U, U, (230, 222, 200), 5, hem=True), (3 * U, U))
    shared.paste(metal(U, U, (236, 186, 62), 6, hi=(255, 242, 170)), (0, 2 * U))
    shared.paste(metal(U, U, (224, 172, 56), 7, engraved=True, hi=(255, 236, 160)), (U, 2 * U))
    shared.paste(gem(U // 2, U, (168, 24, 34)), (2 * U, 2 * U))
    shared.paste(gem(U // 2, U, (34, 64, 168)), (2 * U + U // 2, 2 * U))
    shared.paste(metal(U, U, (176, 178, 180), 8), (3 * U, 2 * U))
    shared.paste(leather(U, U, (112, 70, 40), 9), (0, 3 * U))
    shared.paste(leather(U, U, (66, 42, 26), 10, dark=True), (U, 3 * U))
    shared.paste(metal(U, U, (176, 140, 70), 11, hi=(240, 210, 130)), (2 * U, 3 * U))
    shared.paste(metal(U, U, (74, 74, 78), 12), (3 * U, 3 * U))
    shared.paste(cloth(U, U, (222, 212, 188), 13), (3 * U, 4 * U))
    shared.paste(braid(U, U, 14), (0, 5 * U))
    shared.paste(ermine(U, U, 15), (U, 5 * U))
    shared.paste(cord(U, U, 16), (2 * U, 5 * U))
    for i, (name, colour, _swatch) in enumerate(COLORWAYS):
        a = shared.copy()
        a.paste(felt(2 * U, U, colour, 20 + i), (0, U))
        a.paste(felt(U, U, colour, 30 + i, band=True), (2 * U, U))
        a.paste(wool(2 * U, U, colour, 40 + i), (0, 4 * U))
        a.paste(wool(U, U, colour, 50 + i, shadow=True), (2 * U, 4 * U))
        a.paste(embroidered(U, U, colour, 60 + i), (3 * U, 5 * U))
        a = a.resize((512, 1024), Image.LANCZOS)
        path = os.path.join(out, "T_Wear_BaseColor.png" if i == 0 else "T_Wear_%d_BaseColor.png" % (i + 1))
        a.save(path, optimize=True)
        print("wrote", os.path.abspath(path))


if __name__ == "__main__":
    main()
