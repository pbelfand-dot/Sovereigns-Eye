"""Paints the Lord's Castle atlas (T_Castle_BaseColor.png), 512 x 512.

    python3 paint_castle.py [out.png]

Regions (image pixels, y down). "Wraps" means it repeats seamlessly in x.
  y   0-128  oak shingles, split and lapped, weathered grey-brown (wraps)   timber roofs
  y 128-256  rough turf over a mound, tussocky (wraps)                      the motte
  y 256-384  trodden earth with stones, the path up the motte (wraps)       paths, ditch
  y 384-512  x   0-128  the dark of a deep opening, lit at its edges         loops, windows, doors
             x 128-256  lead sheets with rolled seams, white with age       the keep's roof
             x 256-384  an oak gate leaf: planks, iron straps and studs      gates
             x 384-512  weathered grey planks                                bridge deck, hoarding
Stone, wood and iron otherwise come from the village kit's sheets: the
walls in its rubble stone (MI_UnevenBrick, as on the village's stone
houses and the chapel tower), dressed corners and copings in its ashlar.

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
    k = rng.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v + k))) for v in c)


def blobs(img, rng, count, size, color, alpha=0.5, wrap=True, squash=0.7, blur=1.2):
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


def shingles(w, h, seed):
    """Courses of split oak shingles, each lapping the one below and set
    half a shingle over from it; butts ragged, some darker or paler, a
    little moss (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (70, 58, 46))
    d = ImageDraw.Draw(img)
    rows = 7
    rh = h / rows
    for r in range(rows):
        y0 = r * rh
        x = -(r % 2) * 6 * S - rng.uniform(0, 4) * S
        while x < w:
            sw = rng.uniform(9, 14) * S
            c = shade(lerp((98, 82, 64), (156, 138, 112), rng.random()), rng, 6)
            bottom = y0 + rh - rng.uniform(0, 3) * S
            for ox in (-w, 0, w):
                d.polygon([(x + ox, y0), (x + ox + sw - 1, y0), (x + ox + sw - 1, bottom + rng.uniform(-1, 1) * S), (x + ox, bottom)], fill=c)
                d.line((x + ox + sw * 0.45, y0 + 3 * S, x + ox + sw * 0.45 + rng.uniform(-1, 1) * S, bottom - 3 * S), fill=shade(c, rng, 16), width=S)
            x += sw
        # The shadow cast by the butts of the course above.
        d.rectangle((0, y0, w, y0 + 2 * S), fill=(44, 36, 28))
        d.rectangle((0, y0 + 2 * S, w, y0 + 4 * S), fill=(72, 60, 46))
    img = blobs(img, rng, 18, 7, (96, 112, 66), 0.4)   # moss
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def turf(w, h, seed):
    """Rough grass over a mound: tussocks, darker hollows (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (70, 104, 44))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 8)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        c = lerp((48, 80, 32), (128, 158, 70), rng.random() ** 1.2)
        L = rng.uniform(3, 9) * S
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + rng.uniform(-2.5, 2.5) * S, y - L), fill=c, width=max(1, int(1.3 * S)))
    img = blobs(img, rng, 26, 14, (52, 78, 36), 0.35)       # hollows
    return blobs(img, rng, 10, 9, (150, 150, 90), 0.25)     # dry tufts


def earth(w, h, seed):
    """Trodden earth with stones and ruts (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (128, 100, 70))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 7)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.6, 2.0) * S
        c = shade(lerp((100, 78, 54), (170, 142, 104), rng.random()), rng, 5)
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r, x + ox + r, y + r), fill=c)
    for _ in range(30):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(2, 5) * S
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r * 0.7, x + ox + r, y + r * 0.7), fill=shade((150, 146, 134), rng, 14))
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def void(w, h, seed):
    """The dark inside a deep opening: near-black in the middle, the stone
    of the reveals catching a little light toward the edges."""
    img = Image.new("RGB", (w, h), (14, 11, 9))
    px = img.load()
    for y in range(h):
        for x in range(w):
            e = min(x, w - 1 - x, y, h - 1 - y) / (w * 0.5)
            k = max(0.0, 1.0 - e * 3.0)
            px[x, y] = lerp((14, 11, 9), (58, 50, 42), k ** 2)
    return img


def lead(w, h, seed):
    """Lead roofing: grey-blue sheets between rolled seams, streaked white
    where it has weathered."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (118, 124, 130))
    d = ImageDraw.Draw(img)
    step = 21 * S
    for i in range(w // step + 1):
        x = i * step
        d.rectangle((x, 0, x + step - 3 * S, h), fill=shade((118, 124, 130), rng, 8))
        d.line((x + step - 2 * S, 0, x + step - 2 * S, h), fill=(150, 156, 160), width=2 * S)
        d.line((x + step - 0.5 * S, 0, x + step - 0.5 * S, h), fill=(78, 82, 88), width=S)
    return blobs(img, rng, 20, 8, (186, 190, 188), 0.3, False, squash=2.5)


def gate(w, h, seed):
    """An oak gate leaf: vertical planks, two iron straps, studs."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (92, 64, 42))
    d = ImageDraw.Draw(img)
    pw = w / 6
    for i in range(6):
        c = shade((106, 74, 48), rng, 10)
        d.rectangle((i * pw + S, 0, (i + 1) * pw - S, h), fill=c)
        for _ in range(5):
            y = rng.uniform(0, h)
            d.line((i * pw + 3 * S, y, (i + 1) * pw - 3 * S, y + rng.uniform(-3, 3) * S), fill=shade(c, rng, 16), width=S)
    for y in (h * 0.22, h * 0.74):
        d.rectangle((0, y, w, y + 9 * S), fill=(48, 44, 42))
        d.line((0, y + S, w, y + S), fill=(86, 80, 74), width=S)
        for i in range(12):
            x = (i + 0.5) * w / 12
            d.ellipse((x - 2 * S, y + 2.5 * S, x + 2 * S, y + 6.5 * S), fill=(120, 112, 100))
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def planks(w, h, seed):
    """Weathered grey planks, grain running across (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (126, 118, 104))
    d = ImageDraw.Draw(img)
    ph = h / 5
    for i in range(5):
        c = shade((126, 118, 104), rng, 10)
        d.rectangle((0, i * ph + S, w, (i + 1) * ph - S), fill=c)
        for _ in range(10):
            y = i * ph + rng.uniform(2, ph - 2)
            x = rng.uniform(0, w)
            d.line((x, y, x + rng.uniform(20, 60) * S, y), fill=shade(c, rng, 14), width=S)
        d.line((0, i * ph, w, i * ph), fill=(70, 64, 56), width=S)
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures", "T_Castle_BaseColor.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    c = 128 * S
    atlas = Image.new("RGB", (W, H), (0, 0, 0))
    atlas.paste(shingles(W, c, 1), (0, 0))
    atlas.paste(turf(W, c, 2), (0, c))
    atlas.paste(earth(W, c, 3), (0, 2 * c))
    atlas.paste(void(c, c, 4), (0, 3 * c))
    atlas.paste(lead(c, c, 5), (c, 3 * c))
    atlas.paste(gate(c, c, 6), (2 * c, 3 * c))
    atlas.paste(planks(c, c, 7), (3 * c, 3 * c))
    atlas = atlas.resize((512, 512), Image.LANCZOS)
    atlas.save(out, optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
