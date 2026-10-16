"""Paints the Harbour & Ships atlas (T_Harbour_BaseColor.png), 512 x 512 RGBA.

    python3 paint_harbour.py [out.png]

Regions (image pixels, y down). "Wraps" means it repeats seamlessly in x.
  y   0- 64  a tarred clinker strake: one plank, grain along it, the
             clench nails along its lower edge, the lap's shadow (wraps)   hulls below the sheer
  y  64-128  the same strake in weathered oak, not tarred (wraps)          upper strakes, inside hulls
  y 128-192  sailcloth, undyed wool, the cloths seamed vertically (wraps)  sails, wool bales
  y 192-256  sailcloth striped red and undyed (wraps)                      the trading ship's sail
  y 256-320  the quay's trodden earth with shingle (wraps)                 quay tops, the shore
  y 320-384  the tide line: weed and barnacles, thick at the bottom,
             thinning upward to a ragged edge; nothing above it (alpha 0)
             (wraps)                                                       quay faces, piles (MI_Harbour_Cut)
  y 384-512  x   0-128  grey deck planks, along u                          decks, jetty
             x 128-256  a knotted fishing net, see-through between the
                        twine (alpha 0)                                    nets (MI_Harbour_Cut)
             x 256-384  a coil of rope seen from above                     rope coils
             x 384-512  a furled sail: canvas folds bound with gaskets     sails stowed on their yards
Wood, iron and dressed stone otherwise come from the village kit's
sheets. Alpha is 255 everywhere but between the net's twine and above
the weed.

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


def blobs(img, rng, count, size, color, alpha=0.5, wrap=True, squash=0.7, blur=1.2, ymask=None):
    over = Image.new("RGB", img.size, color)
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    w, h = img.size
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        if ymask:
            y = ymask(rng, h)
        r = rng.uniform(size * 0.4, size) * S
        for ox in ((-w, 0, w) if wrap else (0,)):
            d.ellipse((x + ox - r, y - r * squash, x + ox + r, y + r * squash), fill=int(255 * alpha))
    return Image.composite(over, img, mask.filter(ImageFilter.GaussianBlur(blur * S)))


def strake(w, h, seed, base, grain, tar):
    """One clinker plank: grain along it, the plank's lower edge lapped
    over the one below (a dark line and its shadow), a row of clench nails
    just above it (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    for _ in range(int(w / S / 2)):
        y = rng.uniform(h * 0.15, h * 0.85)
        x = rng.uniform(0, w)
        ln = rng.uniform(30, 120) * S
        c = shade(grain, rng, 10)
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + ln, y + rng.uniform(-2, 2) * S), fill=c, width=S)
    # Butt joints: where one plank meets the next along the strake.
    for x in (w * 0.31, w * 0.83):
        d.line((x, 0, x, h), fill=shade(base, rng, 4) if not tar else (20, 16, 13), width=S)
    # The lap at the bottom: the edge, then its shadow on the plank below.
    d.rectangle((0, h - 6 * S, w, h), fill=lerp(base, (0, 0, 0), 0.55))
    d.rectangle((0, h - 7 * S, w, h - 6 * S), fill=lerp(base, (255, 255, 255), 0.18))
    # Clench nails: iron roves along the lap.
    step = 12 * S
    for i in range(int(w / step)):
        x = (i + 0.5) * step
        y = h - 11 * S
        c = (70, 66, 62) if tar else (96, 88, 78)
        d.ellipse((x - 1.6 * S, y - 1.6 * S, x + 1.6 * S, y + 1.6 * S), fill=c)
    # Highlights where the tar has worn or the oak has silvered.
    if tar:
        img = blobs(img, rng, 14, 9, (74, 62, 50), 0.35, squash=0.3)
    else:
        img = blobs(img, rng, 12, 10, (170, 160, 142), 0.25, squash=0.3)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def sailcloth(w, h, seed, stripes):
    """Woven wool, the cloths seamed vertically; striped red and undyed
    cloth by cloth when `stripes` (wraps in x)."""
    rng = random.Random(seed)
    cream, red = (214, 200, 168), (164, 58, 42)
    img = Image.new("RGB", (w, h), cream)
    d = ImageDraw.Draw(img)
    cloth = 32 * S
    for i in range(int(w / cloth)):
        c = red if stripes and i % 2 else cream
        c = shade(c, rng, 6)
        d.rectangle((i * cloth, 0, (i + 1) * cloth, h), fill=c)
        d.line((i * cloth, 0, i * cloth, h), fill=lerp(c, (60, 40, 30), 0.45), width=S)
    img = blobs(img, rng, 26, 10, (150, 136, 110), 0.18)   # weather stains
    noise = Image.effect_noise((w, h), 18).convert("L")
    img = Image.composite(img, Image.new("RGB", (w, h), (120, 106, 86)), noise.point(lambda v: 255 - v // 6))
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def earth(w, h, seed):
    """Trodden quayside earth and shingle (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (124, 104, 78))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / (S * S) / 7)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.6, 2.2) * S
        c = shade(lerp((96, 84, 66), (176, 164, 140), rng.random()), rng, 5)
        for ox in (-w, 0, w):
            d.ellipse((x + ox - r, y - r * 0.8, x + ox + r, y + r * 0.8), fill=c)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def tideline(w, h, seed):
    """Wet timber or stone at the water: dark weed and barnacles at the
    bottom thinning upward to a clean wet sheen at the top (wraps in x)."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (88, 86, 76))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)   # 0 top, 1 bottom
        c = lerp((108, 104, 92), (46, 54, 34), t ** 1.4)
        for x in range(w):
            px[x, y] = c
    img = blobs(img, rng, 70, 7, (58, 78, 36), 0.6, ymask=lambda r, hh: hh * (1 - r.random() ** 2.2))   # weed
    img = blobs(img, rng, 40, 4, (176, 172, 158), 0.55, squash=1.0, blur=0.5,
                ymask=lambda r, hh: hh * (0.35 + 0.6 * r.random()))   # barnacles
    d = ImageDraw.Draw(img)
    for _ in range(26):   # weed fronds hanging
        x = rng.uniform(0, w)
        y0 = rng.uniform(h * 0.45, h * 0.8)
        for ox in (-w, 0, w):
            d.line((x + ox, y0, x + ox + rng.uniform(-3, 3) * S, h), fill=(40, 62, 30), width=2 * S)
    img = img.filter(ImageFilter.GaussianBlur(0.5 * S)).convert("RGBA")
    # Above the weed, nothing: a ragged line a quarter to a third of the way
    # down, alpha 0 over it, so the weed's top edge is the weed's own.
    a = Image.new("L", (w, h), 255)
    ad = ImageDraw.Draw(a)
    for x in range(w):
        t = 0.29 + 0.05 * math.sin(x / w * math.tau * 3) + 0.03 * math.sin(x / w * math.tau * 11 + 1.3) + rng.uniform(-0.025, 0.025)
        ad.line((x, 0, x, int(h * t)), fill=0)
    img.putalpha(a)
    return img


def deck(w, h, seed):
    """Grey weathered deck planks, grain along u."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (128, 120, 106))
    d = ImageDraw.Draw(img)
    ph = h / 5
    for i in range(5):
        c = shade((132, 122, 106), rng, 10)
        d.rectangle((0, i * ph + S, w, (i + 1) * ph - S), fill=c)
        for _ in range(10):
            y = i * ph + rng.uniform(2, ph - 2)
            x = rng.uniform(0, w)
            d.line((x, y, x + rng.uniform(20, 60) * S, y), fill=shade(c, rng, 14), width=S)
        d.line((0, i * ph, w, i * ph), fill=(70, 64, 56), width=S)
        for x in (rng.uniform(4, 30) * S, rng.uniform(70, 120) * S):   # treenails
            d.ellipse((x - 1.5 * S, i * ph + ph / 2 - 1.5 * S, x + 1.5 * S, i * ph + ph / 2 + 1.5 * S), fill=(84, 74, 60))
    return img


def net(w, h, seed):
    """Knotted twine in a diamond mesh; alpha 0 between the twine."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = 16 * S
    twine = (112, 92, 64, 255)
    for k in range(-h // m - 2, w // m + 3):
        for sgn in (1, -1):
            pts = []
            for y in range(0, h + m, m // 2):
                x = k * m + sgn * y
                pts.append((x + rng.uniform(-1, 1) * S, y))
            d.line(pts, fill=twine, width=int(1.6 * S))
    for k in range(-1, w // m + 2):   # knots at the crossings
        for j in range(-1, h // m + 2):
            for off in (0, m / 2):
                x, y = k * m + off, j * m + off
                d.ellipse((x - 2 * S, y - 2 * S, x + 2 * S, y + 2 * S), fill=(96, 78, 54, 255))
    return img


def rope_coil(w, h, seed):
    """A coil of hemp rope from above: a spiral of laid strands."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (124, 106, 74))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    r = w * 0.48
    k = 0
    while r > w * 0.08:
        c = shade((166, 142, 98), rng, 8)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(84, 70, 46), width=int(2 * S), fill=c)
        for a in range(0, 360, 14):   # the lay of the strands
            ang = math.radians(a + k * 7)
            x0, y0 = cx + math.cos(ang) * (r - 3 * S), cy + math.sin(ang) * (r - 3 * S)
            x1, y1 = cx + math.cos(ang + 0.12) * (r - 6 * S), cy + math.sin(ang + 0.12) * (r - 6 * S)
            d.line((x0, y0, x1, y1), fill=(118, 98, 64), width=S)
        r -= 7 * S
        k += 1
    d.ellipse((cx - w * 0.08, cy - w * 0.08, cx + w * 0.08, cy + w * 0.08), fill=(60, 50, 36))
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def furled(w, h, seed):
    """A sail furled on its yard: canvas folds along it, bound every so
    often with a gasket of rope."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (196, 182, 150))
    d = ImageDraw.Draw(img)
    y = 0.0
    while y < h:
        fh = rng.uniform(6, 12) * S
        c = shade((200, 186, 154), rng, 10)
        d.rectangle((0, y, w, y + fh), fill=c)
        d.line((0, y + fh - S, w, y + fh - S), fill=(130, 116, 92), width=S)
        y += fh
    for x in (w * 0.2, w * 0.5, w * 0.8):   # gaskets
        d.rectangle((x - 3 * S, 0, x + 3 * S, h), fill=(124, 100, 66))
        d.line((x - 3 * S, 0, x - 3 * S, h), fill=(80, 64, 44), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures", "T_Harbour_BaseColor.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    band, cell = 64 * S, 128 * S
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    atlas.paste(strake(W, band, 1, (44, 36, 30), (30, 24, 20), True), (0, 0))
    atlas.paste(strake(W, band, 2, (138, 112, 82), (110, 88, 64), False), (0, band))
    atlas.paste(sailcloth(W, band, 3, False), (0, 2 * band))
    atlas.paste(sailcloth(W, band, 4, True), (0, 3 * band))
    atlas.paste(earth(W, band, 5), (0, 4 * band))
    atlas.paste(tideline(W, band, 6), (0, 5 * band))
    atlas.paste(deck(cell, cell, 7), (0, 3 * cell))
    atlas.paste(net(cell, cell, 8), (cell, 3 * cell))
    atlas.paste(rope_coil(cell, cell, 9), (2 * cell, 3 * cell))
    # Turned a quarter: on a bundle, u runs round it and v along it.
    atlas.paste(furled(cell, cell, 10).transpose(Image.Transpose.ROTATE_90), (3 * cell, 3 * cell))
    atlas = atlas.resize((512, 512), Image.LANCZOS)
    # Downsampling softens the net's alpha; keep it hard so the cut is clean.
    r, g, b, a = atlas.split()
    a = a.point(lambda v: 255 if v >= 96 else 0)
    Image.merge("RGBA", (r, g, b, a)).save(out, optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
