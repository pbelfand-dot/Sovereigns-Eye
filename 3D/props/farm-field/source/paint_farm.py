"""Paints the Farm & Field atlas (T_Farm_BaseColor.png), 1024 x 1024.

    python3 paint_farm.py [out.png]

Regions (image pixels, y down). "Tiles" means it repeats seamlessly in x.
  y   0-256  x    0-1024  straw / hay strands (tiles)        haystacks, stooks, scarecrow
  y 256-512  x    0-512   wheat stalks (tiles in its 512)     wheat rows
             x  512-1024  barley stalks (tiles in its 512)    barley rows
  y 512-768  x    0-512   cabbage leaf, veins from the base   cabbage leaves and head
             x  512-768   turnip leaf with a midrib           turnip tops
             x  768-1024  turnip root, purple to white        turnip roots
  y 768-1024 x    0-512   flax stalks with blue flowers       flax rows
             x  512-768   burlap weave                         scarecrow head, sacks
             x  768-1024  grain ear kernels                    wheat and barley ears

Hand-painted look in the Quaternius palette: warm, soft strokes, no photo
noise. Painted at 2x and downsampled.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2
W = H = 1024 * S


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def jitter(c, rng, amt):
    return tuple(max(0, min(255, int(v + rng.uniform(-amt, amt)))) for v in c)


def strands(img, box, base, dark, light, seed, count, length, width, angle=0.0, tile=True, taper=True):
    """Soft strands (straw, stalks) in a box; wraps around in x so it tiles."""
    x0, y0, x1, y1 = box
    rng = random.Random(seed)
    d = ImageDraw.Draw(img)
    d.rectangle(box, fill=base)
    w = x1 - x0
    for _ in range(count):
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0 - length * 0.3, y1)
        a = math.radians(90 + angle + rng.uniform(-9, 9))
        L = length * rng.uniform(0.6, 1.2)
        c = lerp(dark, light, rng.random() ** 0.8)
        wd = max(1, int(width * rng.uniform(0.6, 1.3)))
        for off in ((0,) if not tile else (-w, 0, w)):
            xa, ya = x + off, y
            xb, yb = x + off + math.cos(a) * L, y + math.sin(a) * L
            d.line((xa, ya, xb, yb), fill=c, width=wd)
            if taper:
                d.line((xa, ya, xa + math.cos(a) * L * 0.3, ya + math.sin(a) * L * 0.3), fill=lerp(c, light, 0.4), width=max(1, wd // 2))
    # Keep the strands inside their box (the wrap draws past the edges).
    return img


def region(size, fill):
    return Image.new("RGB", size, fill)


def straw(w, h, seed):
    img = region((w, h), (196, 158, 74))
    strands(img, (0, 0, w, h), (196, 158, 74), (150, 108, 44), (240, 206, 120), seed, 2600, 70 * S, 3 * S, angle=0)
    # Bundled shadows: soft darker vertical bands so it reads as heaped hay.
    shade = Image.new("L", (w, h), 255)
    sd = ImageDraw.Draw(shade)
    rng = random.Random(seed + 9)
    for _ in range(9):
        x = rng.uniform(0, w)
        bw = rng.uniform(18, 40) * S
        for off in (-w, 0, w):
            sd.rectangle((x + off, 0, x + off + bw, h), fill=200)
    shade = shade.filter(ImageFilter.GaussianBlur(10 * S))
    img = Image.composite(img, Image.new("RGB", (w, h), (0, 0, 0)), shade.point(lambda v: v))
    return img


def stalks(w, h, seed, body, dark, light, heads=None, head_color=None):
    img = region((w, h), body)
    # Ground shadow at the base (bottom), light toward the tops.
    grad = Image.new("RGB", (w, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / h
        gd.line((0, y, w, y), fill=lerp(lerp(light, body, 0.35), lerp(dark, body, 0.2), t ** 1.4))
    img = grad
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(700):
        x = rng.uniform(0, w)
        top = rng.uniform(-0.1, 0.35) * h
        c = lerp(dark, light, rng.random())
        wd = max(1, int(rng.uniform(1.5, 3.2) * S))
        lean = rng.uniform(-10, 10) * S
        for off in (-w, 0, w):
            d.line((x + off, h, x + off + lean, top), fill=c, width=wd)
    if heads:
        for _ in range(heads):
            x = rng.uniform(0, w)
            y = rng.uniform(0.02, 0.25) * h
            r = rng.uniform(5, 9) * S
            c = jitter(head_color, rng, 6)
            for off in (-w, 0, w):
                d.ellipse((x + off - r * 0.55, y - r * 1.5, x + off + r * 0.55, y + r * 1.5), fill=c, outline=lerp(c, dark, 0.5), width=S)
    return img


def leaf(w, h, seed, base, vein, edge, radial=True, pale=None):
    """`pale`: the colour at the leaf's base (the bottom of the region),
    fading to `base` at the tip (a cabbage's pale heart, darker outer leaves)."""
    img = region((w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)

    def at(y):
        return lerp(base, pale, (y / h) ** 1.4) if pale else base
    if pale:
        for y in range(h):
            d.line((0, y, w, y), fill=at(y))
    # Mottling.
    for _ in range(260):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(8, 26) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=jitter(at(y), rng, 12))
    img = img.filter(ImageFilter.GaussianBlur(5 * S))
    d = ImageDraw.Draw(img)
    if radial:
        # Veins fan up from the bottom centre (a leaf's base).
        cx, cy = w / 2, h
        soft = lerp(vein, base, 0.45)
        for k in range(9):
            a = math.radians(-90 + (k - 4) * 17)
            L = h * rng.uniform(0.8, 1.05)
            x1, y1 = cx + math.cos(a) * L, cy + math.sin(a) * L
            d.line((cx, cy, x1, y1), fill=soft, width=int(4 * S))
            for j in range(1, 4):
                t = j / 4
                px, py = cx + (x1 - cx) * t, cy + (y1 - cy) * t
                for sgn in (-1, 1):
                    b = a + sgn * 0.55
                    d.line((px, py, px + math.cos(b) * 30 * S, py + math.sin(b) * 30 * S), fill=lerp(soft, base, 0.5), width=int(2 * S))
    else:
        d.line((w / 2, h, w / 2, 0), fill=vein, width=int(7 * S))
        for j in range(1, 9):
            y = h - j * h / 9
            for sgn in (-1, 1):
                d.line((w / 2, y, w / 2 + sgn * w * 0.42, y - h * 0.08), fill=lerp(vein, base, 0.35), width=int(3 * S))
    # Paler rim.
    d.rectangle((0, 0, w - 1, h - 1), outline=edge, width=int(6 * S))
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def root(w, h):
    img = region((w, h), (230, 224, 210))
    d = ImageDraw.Draw(img)
    top, mid, bot = (128, 52, 112), (196, 120, 170), (236, 230, 214)
    for y in range(h):
        t = y / h
        c = lerp(top, mid, t / 0.45) if t < 0.45 else lerp(mid, bot, (t - 0.45) / 0.55)
        d.line((0, y, w, y), fill=c)
    rng = random.Random(7)
    for _ in range(40):
        y = rng.uniform(0.3, 1.0) * h
        x = rng.uniform(0, w)
        d.line((x, y, x + rng.uniform(10, 30) * S, y), fill=lerp(bot, (170, 150, 130), 0.4), width=S)
    return img.filter(ImageFilter.GaussianBlur(1.5 * S))


def flax(w, h, seed):
    img = stalks(w, h, seed, (92, 132, 82), (54, 92, 52), (150, 186, 110))
    d = ImageDraw.Draw(img)
    rng = random.Random(seed + 3)
    for _ in range(170):
        x = rng.uniform(0, w)
        y = rng.uniform(0.02, 0.3) * h
        r = rng.uniform(5, 9) * S
        c = jitter((96, 132, 214), rng, 18)
        for off in (-w, 0, w):
            for k in range(5):
                a = k * math.tau / 5
                px, py = x + off + math.cos(a) * r * 0.6, y + math.sin(a) * r * 0.6
                d.ellipse((px - r * 0.5, py - r * 0.5, px + r * 0.5, py + r * 0.5), fill=c)
            d.ellipse((x + off - r * 0.25, y - r * 0.25, x + off + r * 0.25, y + r * 0.25), fill=(236, 214, 120))
    return img


def burlap(w, h):
    img = region((w, h), (170, 136, 92))
    d = ImageDraw.Draw(img)
    rng = random.Random(5)
    step = 6 * S
    for x in range(0, w, step):
        d.line((x, 0, x, h), fill=jitter((140, 108, 70), rng, 14), width=2 * S)
    for y in range(0, h, step):
        d.line((0, y, w, y), fill=jitter((196, 164, 116), rng, 14), width=2 * S)
    stains = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(stains)
    for _ in range(14):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(20, 60) * S
        sd.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=70)
    stains = stains.filter(ImageFilter.GaussianBlur(14 * S))
    img = Image.composite(Image.new("RGB", (w, h), (110, 82, 50)), img, stains)
    return img.filter(ImageFilter.GaussianBlur(0.9 * S))


def ears(w, h):
    img = region((w, h), (222, 188, 104))
    d = ImageDraw.Draw(img)
    rng = random.Random(11)
    rows, cols = 10, 8
    for r in range(rows):
        for c in range(cols):
            cx = (c + 0.5 + (0.5 if r % 2 else 0)) * w / cols
            cy = (r + 0.5) * h / rows
            rx, ry = w / cols * 0.42, h / rows * 0.48
            col = jitter((238, 210, 128), rng, 5)
            d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=col, outline=(196, 156, 78), width=S)
            d.line((cx, cy - ry * 0.5, cx, cy + ry * 0.5), fill=(206, 168, 90), width=S)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "T_Farm_BaseColor.png")
    atlas = Image.new("RGB", (W, H))
    u = 256 * S
    atlas.paste(straw(W, u, 1), (0, 0))
    atlas.paste(stalks(2 * u, u, 2, (206, 168, 78), (150, 112, 46), (240, 210, 128), heads=120, head_color=(232, 196, 104)), (0, u))
    atlas.paste(stalks(2 * u, u, 3, (190, 182, 112), (128, 126, 70), (226, 220, 156), heads=90, head_color=(214, 204, 140)), (2 * u, u))
    atlas.paste(leaf(2 * u, u, 4, (96, 138, 58), (206, 224, 160), (138, 172, 84), pale=(196, 210, 132)), (0, 2 * u))
    atlas.paste(leaf(u, u, 5, (84, 146, 64), (170, 210, 120), (120, 176, 90), radial=False), (2 * u, 2 * u))
    atlas.paste(root(u, u), (3 * u, 2 * u))
    atlas.paste(flax(2 * u, u, 6), (0, 3 * u))
    atlas.paste(burlap(u, u), (2 * u, 3 * u))
    atlas.paste(ears(u, u), (3 * u, 3 * u))
    atlas = atlas.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    atlas.save(out, optimize=True)
    print("wrote", os.path.abspath(out))


if __name__ == "__main__":
    main()
