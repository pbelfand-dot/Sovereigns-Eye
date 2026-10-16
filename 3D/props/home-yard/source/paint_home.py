"""Paints the Home Yard atlas (T_Home_BaseColor.png), 512 x 512.

    python3 paint_home.py [out.png]

Regions (image pixels, y down), 128 px rows:
  y   0-128  x   0-256  linen (bleached, a fine weave)      laundry
             x 256-341  madder red cloth                     laundry
             x 341-426  woad blue cloth                      laundry
             x 426-512  weld yellow cloth                    laundry
  y 128-256  x   0-128  red blossoms on leaves               flower pots
             x 128-256  yellow blossoms                      flower pots
             x 256-384  white blossoms                       flower pots
             x 384-512  herb leaves                          pots, garden herbs
  y 256-384  x   0-128  white hen feathers                   hens
             x 128-256  brown hen feathers                   hens
             x 256-384  comb red                             hens
             x 384-512  beak and leg ochre                   hens
  y 384-512  x   0-128  terracotta                           pots
             x 128-256  dug soil                             garden beds
             x 256-384  green-painted wood                   a townhouse's bench
             x 384-512  blue-painted wood                    a townhouse's planters
Every region is a soft, hand-painted tone with a little texture; the
models map whole faces into them.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2           # paint at 2x, then downsample
W = H = 512 * S


def jitter(c, rng, amt):
    return tuple(max(0, min(255, int(v + rng.uniform(-amt, amt)))) for v in c)


def shade(c, rng, amt):
    """The same colour a little lighter or darker (no hue shift)."""
    k = rng.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v + k))) for v in c)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def region(w, h, base):
    return Image.new("RGB", (w, h), base)


def cloth(w, h, base, seed, weave=True):
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    if weave:
        for y in range(0, h, 3 * S):
            d.line((0, y, w, y), fill=lerp(base, (0, 0, 0), 0.06), width=1)
        for x in range(0, w, 3 * S):
            d.line((x, 0, x, h), fill=lerp(base, (255, 255, 255), 0.05), width=1)
    for _ in range(40):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(10, 30) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=shade(base, rng, 5))
    img = img.filter(ImageFilter.GaussianBlur(1.2 * S))
    d = ImageDraw.Draw(img)
    # A darker hem along the bottom and top.
    d.rectangle((0, h - 5 * S, w, h), fill=lerp(base, (0, 0, 0), 0.18))
    d.rectangle((0, 0, w, 3 * S), fill=lerp(base, (0, 0, 0), 0.1))
    return img


def blossoms(w, h, petal, centre, seed, leaf=(76, 122, 58)):
    img = region(w, h, leaf)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(60):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(6, 14) * S
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=jitter(leaf, rng, 14))
    for _ in range(26):
        x, y = rng.uniform(8 * S, w - 8 * S), rng.uniform(8 * S, h - 8 * S)
        r = rng.uniform(6, 10) * S
        for k in range(5):
            a = k * math.tau / 5 + rng.uniform(-0.2, 0.2)
            px, py = x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.7
            d.ellipse((px - r * 0.55, py - r * 0.55, px + r * 0.55, py + r * 0.55), fill=jitter(petal, rng, 12))
        d.ellipse((x - r * 0.3, y - r * 0.3, x + r * 0.3, y + r * 0.3), fill=centre)
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def leaves(w, h, seed):
    base = (84, 132, 62)
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(90):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.uniform(0, math.pi)
        L = rng.uniform(10, 22) * S
        dx, dy = math.cos(a) * L, math.sin(a) * L
        d.line((x - dx, y - dy, x + dx, y + dy), fill=jitter(lerp(base, (150, 190, 100), rng.uniform(0, 0.5)), rng, 8), width=int(6 * S))
    return img.filter(ImageFilter.GaussianBlur(1.0 * S))


def feathers(w, h, base, dark, seed):
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for row in range(0, h, 8 * S):
        for col in range(-8 * S, w, 12 * S):
            x = col + (6 * S if (row // (8 * S)) % 2 else 0)
            d.arc((x, row - 6 * S, x + 14 * S, row + 10 * S), 20, 160, fill=jitter(dark, rng, 10), width=int(2 * S))
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def flat(w, h, base, seed, amt=8):
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(80):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(6, 18) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=jitter(base, rng, amt))
    return img.filter(ImageFilter.GaussianBlur(2 * S))


def terracotta(w, h):
    base = (178, 94, 58)
    img = flat(w, h, base, 31, 10)
    d = ImageDraw.Draw(img)
    for y in (int(h * 0.18), int(h * 0.22)):
        d.line((0, y, w, y), fill=lerp(base, (60, 30, 20), 0.35), width=int(2 * S))
    return img


def soil(w, h):
    base = (88, 64, 42)
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(33)
    for _ in range(400):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1.5, 5) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=jitter(lerp(base, (40, 28, 18) if rng.random() < 0.5 else (130, 100, 70), 0.4), rng, 6))
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def painted_wood(w, h, base, seed):
    img = region(w, h, base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for y in range(0, h, 2 * S):
        if rng.random() < 0.35:
            d.line((0, y, w, y + rng.uniform(-3, 3) * S), fill=jitter(lerp(base, (0, 0, 0), 0.12), rng, 6), width=1)
    # Paint worn through to the wood here and there.
    for _ in range(7):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        rw, rh = rng.uniform(4, 12) * S, rng.uniform(1.5, 3) * S
        d.ellipse((x - rw, y - rh, x + rw, y + rh), fill=lerp(base, (112, 84, 56), 0.6))
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "T_Home_BaseColor.png")
    a = Image.new("RGB", (W, H))
    u = 128 * S
    a.paste(cloth(2 * u, u, (232, 224, 204), 1), (0, 0))
    a.paste(cloth(int(u * 2 / 3), u, (176, 74, 60), 2), (2 * u, 0))
    a.paste(cloth(int(u * 2 / 3), u, (86, 110, 152), 3), (2 * u + int(u * 2 / 3), 0))
    a.paste(cloth(W - (2 * u + int(u * 4 / 3)), u, (214, 182, 92), 4), (2 * u + int(u * 4 / 3), 0))
    a.paste(blossoms(u, u, (206, 52, 48), (240, 200, 90), 11), (0, u))
    a.paste(blossoms(u, u, (236, 190, 52), (180, 110, 40), 12), (u, u))
    a.paste(blossoms(u, u, (240, 238, 228), (232, 196, 70), 13), (2 * u, u))
    a.paste(leaves(u, u, 14), (3 * u, u))
    a.paste(feathers(u, u, (238, 232, 218), (190, 182, 168), 21), (0, 2 * u))
    a.paste(feathers(u, u, (156, 98, 54), (110, 64, 34), 22), (u, 2 * u))
    a.paste(flat(u, u, (200, 44, 40), 23), (2 * u, 2 * u))
    a.paste(flat(u, u, (224, 170, 62), 24), (3 * u, 2 * u))
    a.paste(terracotta(u, u), (0, 3 * u))
    a.paste(soil(u, u), (u, 3 * u))
    a.paste(painted_wood(u, u, (88, 122, 94), 41), (2 * u, 3 * u))
    a.paste(painted_wood(u, u, (76, 100, 136), 42), (3 * u, 3 * u))
    a = a.resize((512, 512), Image.LANCZOS)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    a.save(out, optimize=True)
    print("wrote", os.path.abspath(out))


if __name__ == "__main__":
    main()
