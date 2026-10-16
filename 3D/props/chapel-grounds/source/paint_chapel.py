"""Paints the Chapel & Churchyard atlas (T_Chapel_BaseColor.png), 512 x 512.

    python3 paint_chapel.py [out.png]

Regions (image pixels, y down). "Wraps" means it repeats seamlessly in x.
  y   0-128  churchyard turf: short grazed grass, daisies (wraps)    grave mounds
  y 128-256  x   0-256  fresh-dug earth: clods, stones, spade cuts    fresh grave
             x 256-384  yew bark: red-brown, fluted                   the yew's trunk
             x 384-512  hemp rope, twisted                            the bell rope
  y 256-384  x   0-128  cross slab: a cross on a stepped base         grave slab
             x 128-256  knight's slab: a cross with a sword beside    knight's slab
             x 256-384  limestone, lichened                           crosses, slab sides
             x 384-512  bell bronze, streaked with verdigris          the bell
  y 384-512  yew foliage: dark needle sprays (wraps)                  the yew's crown
Wood, iron, tiles and rubble stone come from the village kit's trim sheets.

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


def blobs(img, rng, count, size, color, alpha=0.5, wrap=True, squash=0.7, blur=1.2):
    """Soft blobs of `color` over the image (lichen, stains, wear)."""
    over = Image.new("RGB", img.size, color)
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    w, h = img.size
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(size * 0.4, size) * S
        for ox in ((-w, 0, w) if wrap else (0,)):
            d.ellipse((x + ox - r, y - r * squash, x + ox + r, y + r * squash), fill=int(255 * alpha))
    return Image.composite(over, img, mask.filter(ImageFilter.GaussianBlur(blur * S)))


def turf(w, h, seed):
    """Short grazed churchyard grass, a little darker and finer than the
    meadow, with daisies."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (62, 98, 38))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 9)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        c = lerp((44, 76, 30), (116, 150, 62), rng.random() ** 1.3)
        L = rng.uniform(2, 6) * S
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + rng.uniform(-1.5, 1.5) * S, y - L), fill=c, width=max(1, int(1.2 * S)))
    for _ in range(40):  # daisies
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1.2, 2.0) * S
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=(236, 234, 222))
            d.ellipse((x + ox - r * 0.4, y - r * 0.4, x + ox + r * 0.4, y + r * 0.4), fill=(226, 190, 60))
    return img


def fresh_earth(w, h, seed):
    """Fresh-dug earth: dark loam, clods with lit tops, a few stones and
    the flat cuts of a spade."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (96, 70, 46))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 10)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.8, 2.4) * S
        c = shade(lerp((70, 50, 32), (128, 98, 66), rng.random()), rng, 5)
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=c)
    for _ in range(70):  # clods: dark underside, lit top
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(3, 7) * S
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r * 0.7, x + ox + r, y + r * 0.7), fill=(64, 44, 28))
            d.ellipse((x + ox - r * 0.8, y - r * 0.75, x + ox + r * 0.7, y + r * 0.2), fill=shade((122, 92, 62), rng, 8))
    for _ in range(18):  # stones
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(1.5, 3.5) * S
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r * 0.8, x + ox + r, y + r * 0.8), fill=shade((150, 142, 128), rng, 12))
    for _ in range(6):  # spade cuts: flat, smoother bands
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        L = rng.uniform(14, 26) * S
        for ox in (-w, 0, w):
            d.rectangle((x + ox, y, x + ox + L, y + 4 * S), fill=(104, 78, 52))
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


LIMESTONE = (176, 168, 150)


def limestone(w, h, seed, wrap=True):
    """Pale weathered limestone: grain, pits, lichen in grey-green and
    orange, darker where the rain runs."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), LIMESTONE)
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 6)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.5, 1.6) * S
        c = shade(lerp((150, 142, 126), (198, 190, 172), rng.random()), rng, 4)
        for ox in ((-w, 0, w) if wrap else (0,)):
            d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=c)
    img = blobs(img, rng, 22, 9, (140, 134, 118), 0.45, wrap)       # weathering
    img = blobs(img, rng, 16, 6, (150, 160, 128), 0.55, wrap)       # grey-green lichen
    img = blobs(img, rng, 7, 4, (196, 150, 70), 0.6, wrap, blur=0.8)  # orange lichen
    return img


def carve(img, shapes, depth=(98, 92, 80), lip=(214, 206, 188)):
    """Incised lines: a pale lip on the lit (upper-left) side, then the
    dark cut. `shapes` are (kind, coords, width) in the cell's pixels."""
    d = ImageDraw.Draw(img)
    for dx, dy, c in ((-S, -S, lip), (S // 2, S // 2, (120, 112, 98)), (0, 0, depth)):
        for kind, xy, wid in shapes:
            pts = [(x + dx, y + dy) for x, y in xy]
            if kind == "line":
                d.line(pts, fill=c, width=wid, joint="curve")
            elif kind == "ring":
                (x0, y0), (x1, y1) = pts
                d.ellipse((x0, y0, x1, y1), outline=c, width=wid)
            elif kind == "poly":
                d.polygon(pts, outline=c, width=wid)
    return img


def cross_slab(w, h, seed, sword=False):
    """A coffin-lid grave cover seen from above, head at the top of the
    cell: a cross with a ringed head on a stepped base (a calvary), as on
    12th- and 13th-century slabs; a knight's has a sword beside the shaft."""
    img = limestone(w, h, seed, wrap=False)
    cx = w * (0.42 if sword else 0.5)
    t = 5 * S
    head_y, r = h * 0.2, w * 0.15
    shapes = [
        ("ring", [(cx - r, head_y - r), (cx + r, head_y + r)], t),
        ("line", [(cx, head_y - r * 1.25), (cx, h * 0.84)], t),            # shaft
        ("line", [(cx - r * 1.25, head_y), (cx + r * 1.25, head_y)], t),   # arms
    ]
    for k, (hw, y) in enumerate([(0.10, 0.84), (0.16, 0.89), (0.22, 0.94)]):  # the stepped base
        shapes.append(("poly", [(cx - w * hw, h * y), (cx + w * hw, h * y), (cx + w * hw, h * (y + 0.05)), (cx - w * hw, h * (y + 0.05))], t))
    for a in (0.25, 0.75):  # leaves on the arms of the head (fleury ends)
        ang = math.tau * a
        shapes.append(("line", [(cx + math.cos(ang) * r * 0.5, head_y + math.sin(ang) * r * 0.5), (cx + math.cos(ang) * r * 0.9, head_y + math.sin(ang) * r * 0.9)], 2 * S))
    if sword:
        sx = w * 0.74
        shapes += [
            ("poly", [(sx - 4 * S, h * 0.31), (sx + 4 * S, h * 0.31), (sx, h * 0.82)], 4 * S),   # blade
            ("line", [(sx - w * 0.09, h * 0.30), (sx + w * 0.09, h * 0.30)], 5 * S),          # cross guard
            ("line", [(sx, h * 0.21), (sx, h * 0.30)], 5 * S),                               # grip
            ("ring", [(sx - 4 * S, h * 0.15), (sx + 4 * S, h * 0.15 + 8 * S)], 4 * S),       # pommel
        ]
    img = carve(img, shapes)
    rng = random.Random(seed + 100)
    img = blobs(img, rng, 6, 7, (150, 160, 128), 0.4, False)  # lichen over the carving too
    return img


def bronze(w, h, seed):
    """Bell metal: warm bronze, darkened, with verdigris running down."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (156, 116, 62))
    d = ImageDraw.Draw(img)
    for y in range(0, h, S):  # turned bands from the casting
        c = shade((156, 116, 62), rng, 10)
        d.line((0, y, w, y), fill=c, width=S)
    streaks = Image.new("RGB", (w, h), (98, 124, 100))
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    for _ in range(14):  # verdigris run down from the crown
        x = rng.uniform(0, w)
        y0 = rng.uniform(0, h * 0.4)
        md.line((x, y0, x + rng.uniform(-3, 3) * S, y0 + rng.uniform(20, 50) * S), fill=int(rng.uniform(70, 130)), width=int(rng.uniform(3, 7) * S))
    img = Image.composite(streaks, img, mask.filter(ImageFilter.GaussianBlur(3 * S)))
    img = img.filter(ImageFilter.GaussianBlur(0.8 * S))
    return blobs(img, rng, 10, 8, (176, 136, 76), 0.35, False)  # rubbed bright


def yew_foliage(w, h, seed):
    """Dense dark needle sprays, lighter at the sprays' tips (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (36, 62, 34))
    d = ImageDraw.Draw(img)
    for _ in range(900):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.uniform(-0.6, 0.6) - math.pi / 2
        L = rng.uniform(8, 18) * S
        c = lerp((30, 54, 30), (80, 112, 58), rng.random() ** 1.4)
        for ox in (-w, 0, w):
            x1, y1 = x + ox + math.cos(a) * L, y + math.sin(a) * L
            d.line((x + ox, y, x1, y1), fill=c, width=S)
            for k in range(1, 6):  # needles both sides of the spray
                px, py = x + ox + math.cos(a) * L * k / 6, y + math.sin(a) * L * k / 6
                for side in (-1, 1):
                    na = a + side * 1.2
                    d.line((px, py, px + math.cos(na) * 3 * S, py + math.sin(na) * 3 * S), fill=c, width=max(1, S // 2 + 1))
    return img


def yew_bark(w, h, seed):
    """Red-brown bark in long fluted strips, flaking (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (118, 66, 46))
    d = ImageDraw.Draw(img)
    x = 0
    while x < w:
        sw = rng.uniform(6, 14) * S
        c = shade(lerp((92, 50, 36), (150, 92, 64), rng.random()), rng, 6)
        d.rectangle((x, 0, x + sw, h), fill=c)
        d.line((x, 0, x, h), fill=(64, 34, 24), width=S)
        x += sw
    img = blobs(img, rng, 60, 3, (160, 100, 70), 0.5, True, squash=3.0, blur=0.8)  # flakes, long
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def rope(w, h, seed):
    """Hemp rope, its strands twisting across the cell (u along the rope)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (160, 132, 88))
    d = ImageDraw.Draw(img)
    step = 10 * S
    for i in range(-2, w // step + 3):
        x = i * step
        d.polygon([(x, 0), (x + step * 0.6, 0), (x + step * 0.6 + h * 0.45, h), (x + h * 0.45, h)], fill=shade((186, 156, 106), rng, 8))
        d.line((x + h * 0.45, h, x, 0), fill=(108, 86, 54), width=2 * S)
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures", "T_Chapel_BaseColor.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    c = 128 * S
    atlas = Image.new("RGB", (W, H), (0, 0, 0))
    atlas.paste(turf(W, c, 1), (0, 0))
    atlas.paste(fresh_earth(2 * c, c, 2), (0, c))
    atlas.paste(yew_bark(c, c, 8), (2 * c, c))
    atlas.paste(rope(c, c, 9), (3 * c, c))
    atlas.paste(cross_slab(c, c, 3), (0, 2 * c))
    atlas.paste(cross_slab(c, c, 4, sword=True), (c, 2 * c))
    atlas.paste(limestone(c, c, 5), (2 * c, 2 * c))
    atlas.paste(bronze(c, c, 6), (3 * c, 2 * c))
    atlas.paste(yew_foliage(W, c, 7), (0, 3 * c))
    atlas = atlas.resize((512, 512), Image.LANCZOS)
    atlas.save(out, optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
