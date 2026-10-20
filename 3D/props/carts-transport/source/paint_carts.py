"""Paints the Carts & Transport atlas (T_Carts_BaseColor.png), 512 x 512 RGB.

    python3 paint_carts.py [out.png]

Regions (image pixels, y down). "Wraps" means it repeats seamlessly in x.
  y   0- 64  a bay horse's coat: the belly a little dark at the bottom of
             the band, warm red-brown sides with a sheen, the spine darker
             at the top (wraps)                                            body, neck
  y  64-128  the bay's points, bottom to top: hoof horn, the coronet, black
             hair, black shading into bay, bay (wraps)                     legs (by height), the head
                                                                           (dark muzzle), ears
  y 128-192  black horse hair, the strands along v (wraps)                 mane, forelock, tail
  y 192-224  harness leather: a strap, stitched along both edges (wraps)   straps, bridle, back and belly bands
  y 224-256  hemp rope, the strands laid along u (wraps)                   traces, lashings, ties
  y 256-320  the collar: a leather roll stuffed with straw, stitched
             across every hand's breadth, a seam along it (wraps)          the collar
  y 320-384  sacking: coarse undyed hessian (wraps)                        sacks
  y 384-512  x   0-128  woven cloth, three dyes in stripes 42 px tall:
                        woad blue, madder red, Lincoln green; u along the bolt     bolts of cloth (sides)
             x 128-256  four 64 px squares: the rolled ends of the bolts
                        (blue, red, green) and a cask head                 bolt ends, cask heads
             x 256-384  oak staves, the grain up v                          the cask
             x 384-512  four 64 px squares: red felt with a dark border,
                        an eye, a sack's gathered neck, dark leather        saddle pad, eyes, sack necks,
                                                                           the saddle's seat
Wood and iron otherwise come from the village kit's sheets.

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

BAY = (122, 66, 36)
BAY_LIGHT = (156, 92, 52)
BAY_DARK = (84, 44, 26)
BLACK = (26, 22, 20)
HORN = (58, 52, 46)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
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


def gradient(w, h, stops):
    """A vertical gradient: stops [(t, colour)], t 0 at the top, 1 at the bottom."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        for k in range(len(stops) - 1):
            if stops[k][0] <= t <= stops[k + 1][0]:
                a, b = stops[k], stops[k + 1]
                c = lerp(a[1], b[1], (t - a[0]) / max(1e-6, b[0] - a[0]))
                break
        else:
            c = stops[-1][1]
        for x in range(w):
            px[x, y] = c
    return img


def hair_streaks(img, rng, count, length, colours, width=1, vertical=False, y0=0, y1=None):
    """Fine strokes along u (a coat lying flat) or along v (long hair)."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    y1 = h if y1 is None else y1
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(y0, y1)
        ln = rng.uniform(length * 0.5, length) * S
        c = rng.choice(colours)
        for ox in (-w, 0, w):
            if vertical:
                d.line((x + ox, y, x + ox + rng.uniform(-2, 2) * S, y + ln), fill=c, width=width * S)
            else:
                d.line((x + ox, y, x + ox + ln, y + rng.uniform(-1, 1) * S), fill=c, width=width * S)
    return img


def coat(w, h, seed):
    """The bay's body coat, across the band from the spine (top) to the
    belly (bottom): darker along the back, a warm sheen on the sides."""
    rng = random.Random(seed)
    img = gradient(w, h, [(0.0, BAY_DARK), (0.22, BAY), (0.5, BAY_LIGHT), (0.78, BAY), (1.0, (96, 52, 30))])
    img = blobs(img, rng, 30, 14, BAY_LIGHT, 0.18, squash=0.4, blur=3)
    img = blobs(img, rng, 24, 12, BAY_DARK, 0.15, squash=0.4, blur=3)
    img = hair_streaks(img, rng, int(w / S * 3), 18, [lerp(BAY, BAY_DARK, 0.4), lerp(BAY, BAY_LIGHT, 0.5), BAY])
    return img.filter(ImageFilter.GaussianBlur(0.8 * S))


def points(w, h, seed):
    """The legs from the hoof (bottom) up: horn with growth lines, the
    coronet's hair edge, black, black shading into bay, bay."""
    rng = random.Random(seed)
    # t from the top of the band (bay) down to the hoof.
    img = gradient(w, h, [(0.0, BAY_LIGHT), (0.28, BAY), (0.36, lerp(BAY, BLACK, 0.55)), (0.45, BLACK),
                          (0.875, BLACK), (0.89, (40, 34, 30)), (0.9, HORN), (1.0, (44, 40, 36))])
    hair_streaks(img, rng, int(w / S * 1.4), 6, [(40, 34, 30), (18, 15, 14), (34, 28, 25)], vertical=True, y0=h * 0.44, y1=h * 0.86)
    hair_streaks(img, rng, int(w / S * 1.2), 5, [lerp(BAY, BAY_LIGHT, 0.5), lerp(BAY, BAY_DARK, 0.35)], vertical=True, y0=0, y1=h * 0.26)
    d = ImageDraw.Draw(img)
    for _ in range(int(w / S / 3)):   # the hoof's growth lines run down it
        x = rng.uniform(0, w)
        c = shade((70, 62, 54), rng, 10)
        for ox in (-w, 0, w):
            d.line((x + ox, h * 0.905, x + ox, h), fill=c, width=S)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def black_hair(w, h, seed):
    """Long black hair: strands down v, a little light catching them."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (22, 19, 17))
    hair_streaks(img, rng, int(w / S * 5), h / S, [(12, 10, 9), (44, 38, 34), (58, 50, 44), (30, 26, 23)], vertical=True, y0=-h * 0.5, y1=h)
    img = img.filter(ImageFilter.GaussianBlur(0.5 * S))
    hair_streaks(img, rng, int(w / S * 0.6), h / S * 0.8, [(76, 66, 58)], vertical=True, y0=-h * 0.3, y1=h)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def leather(w, h, seed, base=(92, 56, 32)):
    """A harness strap: dark at the edges, stitched along both."""
    rng = random.Random(seed)
    img = gradient(w, h, [(0.0, lerp(base, (0, 0, 0), 0.45)), (0.12, base), (0.5, lerp(base, (255, 230, 200), 0.12)),
                          (0.88, base), (1.0, lerp(base, (0, 0, 0), 0.45))])
    img = blobs(img, rng, 40, 6, lerp(base, (0, 0, 0), 0.3), 0.3, squash=0.5)
    d = ImageDraw.Draw(img)
    step = 6 * S
    for row in (0.22, 0.78):   # stitching
        y = h * row
        for i in range(int(w / step)):
            x = i * step
            d.line((x, y, x + step * 0.55, y), fill=lerp(base, (230, 210, 170), 0.45), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def rope(w, h, seed):
    """Laid hemp: three strands, their lay slanting across."""
    rng = random.Random(seed)
    base = (170, 144, 100)
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    pitch = 12 * S
    for i in range(-4, int(w / pitch) + 6):
        x = i * pitch
        c = shade(base, rng, 10)
        d.polygon([(x, 0), (x + pitch * 0.85, 0), (x + pitch * 0.85 - h * 0.7, h), (x - h * 0.7, h)], fill=c)
        d.line((x, 0, x - h * 0.7, h), fill=(104, 84, 54), width=int(1.5 * S))
        d.line((x + pitch * 0.3, 0, x + pitch * 0.3 - h * 0.7, h), fill=lerp(base, (230, 214, 176), 0.4), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def collar(w, h, seed):
    """The collar's roll: leather over straw, stitched across every hand's
    breadth (lumpy between), a seam along it at the middle."""
    rng = random.Random(seed)
    base = (118, 74, 40)
    img = gradient(w, h, [(0.0, lerp(base, (0, 0, 0), 0.35)), (0.3, base), (0.5, lerp(base, (255, 225, 180), 0.12)),
                          (0.7, base), (1.0, lerp(base, (0, 0, 0), 0.35))])
    d = ImageDraw.Draw(img)
    pitch = 22 * S
    for i in range(int(w / pitch)):
        x = i * pitch
        d.line((x, 0, x, h), fill=lerp(base, (0, 0, 0), 0.5), width=2 * S)
        d.line((x + 2 * S, 0, x + 2 * S, h), fill=lerp(base, (255, 230, 190), 0.2), width=S)
    d.line((0, h / 2, w, h / 2), fill=lerp(base, (0, 0, 0), 0.45), width=S)
    img = blobs(img, rng, 50, 8, lerp(base, (255, 230, 190), 0.18), 0.35, squash=0.8)
    img = blobs(img, rng, 30, 6, lerp(base, (0, 0, 0), 0.3), 0.3)
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def sacking(w, h, seed):
    """Coarse undyed hessian: a loose weave, a few stains."""
    rng = random.Random(seed)
    base = (178, 154, 112)
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    for x in range(0, w, 3 * S):
        d.line((x, 0, x, h), fill=shade((150, 128, 90), rng, 8), width=S)
    for y in range(0, h, 3 * S):
        d.line((0, y, w, y), fill=shade((196, 174, 132), rng, 8), width=S)
    img = blobs(img, rng, 18, 12, (140, 118, 82), 0.35)
    img = blobs(img, rng, 10, 8, (200, 182, 142), 0.3)
    return img.filter(ImageFilter.GaussianBlur(0.35 * S))


DYES = [(56, 80, 122), (150, 50, 38), (74, 102, 58)]   # woad, madder, Lincoln green (woad over weld)


def cloth(w, h, seed):
    """Three stripes of woven cloth (each one bolt's outside): the weave,
    a selvedge line along it, soft folds."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    sh = h // 3
    for k, c in enumerate(DYES):
        y0 = k * sh
        d.rectangle((0, y0, w, y0 + sh), fill=c)
        for y in range(y0, y0 + sh, 2 * S):
            d.line((0, y, w, y), fill=shade(lerp(c, (0, 0, 0), 0.12), rng, 6), width=S)
        for x in range(0, w, 2 * S):
            d.line((x, y0, x, y0 + sh), fill=shade(lerp(c, (255, 255, 255), 0.06), rng, 6), width=S)
        # The cloth's edge where the last turn ends, and a selvedge stripe.
        d.line((0, y0 + sh * 0.62, w, y0 + sh * 0.62), fill=lerp(c, (0, 0, 0), 0.5), width=2 * S)
        d.line((0, y0 + sh * 0.68, w, y0 + sh * 0.68), fill=lerp(c, (240, 220, 180), 0.35), width=S)
        for _ in range(3):   # a soft fold
            x = rng.uniform(0, w)
            d.line((x, y0, x + rng.uniform(-6, 6) * S, y0 + sh), fill=lerp(c, (0, 0, 0), 0.18), width=3 * S)
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def bolt_end(size, colour, seed):
    """The end of a rolled bolt: the cloth's turns in a spiral."""
    rng = random.Random(seed)
    img = Image.new("RGB", (size, size), lerp(colour, (0, 0, 0), 0.35))
    d = ImageDraw.Draw(img)
    c = size / 2
    r = size * 0.49
    k = 0
    while r > size * 0.06:
        col = shade(lerp(colour, (255, 255, 255), 0.05 if k % 2 else 0.0), rng, 8)
        d.ellipse((c - r, c - r, c + r, c + r), fill=col, outline=lerp(colour, (0, 0, 0), 0.55), width=S)
        r -= rng.uniform(3.0, 4.5) * S
        k += 1
    d.ellipse((c - size * 0.06, c - size * 0.06, c + size * 0.06, c + size * 0.06), fill=(60, 48, 34))
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def cask_head(size, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (size, size), (78, 60, 42))
    d = ImageDraw.Draw(img)
    n = 4
    for i in range(n):
        x0 = i * size / n
        d.rectangle((x0, 0, x0 + size / n, size), fill=shade((150, 116, 78), rng, 10))
        d.line((x0, 0, x0, size), fill=(70, 54, 38), width=S)
        for _ in range(6):
            x = x0 + rng.uniform(2, size / n - 2)
            d.line((x, 0, x + rng.uniform(-2, 2), size), fill=shade((128, 98, 66), rng, 8), width=S)
    # The chime: a dark ring at the edge.
    d.ellipse((S, S, size - S, size - S), outline=(64, 50, 36), width=3 * S)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def staves(w, h, seed):
    """Oak staves side by side, the grain up v, dark joints."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (138, 104, 68))
    d = ImageDraw.Draw(img)
    n = 8
    for i in range(n):
        x0 = i * w / n
        c = shade((146, 110, 72), rng, 12)
        d.rectangle((x0, 0, x0 + w / n, h), fill=c)
        for _ in range(8):
            x = x0 + rng.uniform(2 * S, w / n - 2 * S)
            d.line((x, 0, x + rng.uniform(-3, 3) * S, h), fill=shade(lerp(c, (60, 40, 24), 0.3), rng, 8), width=S)
        d.line((x0, 0, x0, h), fill=(62, 46, 30), width=int(1.5 * S))
    img = blobs(img, rng, 12, 8, (110, 84, 56), 0.3, wrap=False)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def felt(size, seed):
    """The saddle pad: red woollen felt, a dark bound edge."""
    rng = random.Random(seed)
    base = (138, 46, 34)
    img = Image.new("RGB", (size, size), base)
    img = blobs(img, rng, 20, 6, lerp(base, (0, 0, 0), 0.2), 0.35, wrap=False)
    img = blobs(img, rng, 14, 5, lerp(base, (255, 210, 180), 0.12), 0.3, wrap=False)
    d = ImageDraw.Draw(img)
    b = 5 * S
    d.rectangle((0, 0, size - 1, size - 1), outline=(46, 30, 22), width=b)
    d.rectangle((b, b, size - 1 - b, size - 1 - b), outline=(196, 160, 96), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.4 * S))


def eye(size):
    """A horse's eye: dark brown, a pale glint high and forward."""
    img = Image.new("RGB", (size, size), BAY_DARK)
    d = ImageDraw.Draw(img)
    m = size * 0.08
    d.ellipse((m, m, size - m, size - m), fill=(18, 12, 10))
    d.ellipse((size * 0.3, size * 0.3, size * 0.7, size * 0.7), fill=(44, 26, 18))
    d.ellipse((size * 0.58, size * 0.2, size * 0.74, size * 0.36), fill=(210, 206, 196))
    return img.filter(ImageFilter.GaussianBlur(0.6 * S))


def sack_neck(size, seed):
    """A sack's gathered neck: hessian bunched into folds, a cord round it."""
    rng = random.Random(seed)
    img = sacking(size, size, seed)
    d = ImageDraw.Draw(img)
    for i in range(9):
        x = (i + 0.5) * size / 9
        d.line((x, 0, x + rng.uniform(-3, 3) * S, size), fill=(120, 100, 70), width=2 * S)
    d.rectangle((0, size * 0.42, size, size * 0.56), fill=(150, 126, 86))
    d.line((0, size * 0.42, size, size * 0.42), fill=(96, 78, 52), width=S)
    d.line((0, size * 0.56, size, size * 0.56), fill=(96, 78, 52), width=S)
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures", "T_Carts_BaseColor.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    band, half, cell, q = 64 * S, 32 * S, 128 * S, 64 * S
    atlas = Image.new("RGB", (W, H), (0, 0, 0))
    atlas.paste(coat(W, band, 1), (0, 0))
    atlas.paste(points(W, band, 2), (0, band))
    atlas.paste(black_hair(W, band, 3), (0, 2 * band))
    atlas.paste(leather(W, half, 4), (0, 3 * band))
    atlas.paste(rope(W, half, 5), (0, 3 * band + half))
    atlas.paste(collar(W, band, 6), (0, 4 * band))
    atlas.paste(sacking(W, band, 7), (0, 5 * band))
    y = 6 * band
    atlas.paste(cloth(cell, cell, 8), (0, y))
    for k, c in enumerate(DYES):
        atlas.paste(bolt_end(q, c, 9 + k), (cell + (k % 2) * q, y + (k // 2) * q))
    atlas.paste(cask_head(q, 12), (cell + q, y + q))
    atlas.paste(staves(cell, cell, 13), (2 * cell, y))
    atlas.paste(felt(q, 14), (3 * cell, y))
    atlas.paste(eye(q), (3 * cell + q, y))
    atlas.paste(sack_neck(q, 15), (3 * cell, y + q))
    atlas.paste(leather(q, q, 16, base=(70, 44, 28)), (3 * cell + q, y + q))
    atlas = atlas.resize((512, 512), Image.LANCZOS)
    atlas.save(out, optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
