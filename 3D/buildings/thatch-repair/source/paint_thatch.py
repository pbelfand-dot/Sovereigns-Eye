"""Paints the Thatch & Repair textures.

    python3 paint_thatch.py [textures_dir]

T_Thatch_BaseColor.png      1024 x 1024, tiles both ways: fresh golden thatch
                            laid in courses, 1.6 m of roof per tile
T_ThatchWorn_BaseColor.png  the same straw weathered grey-brown, with moss
                            on the butt ends and rain streaks
T_Thatch_Normal.png         the courses' relief (shared by both): each
                            course swells toward its butt end and drops
                            under the next; strands run down the slope
T_ThatchKit_BaseColor.png   1024 x 1024 atlas (image pixels, y down; "wraps"
                            means it repeats seamlessly in x):
  y   0-128   ridge, block-cut: liggers and crossed spars (wraps)
  y 128-256   ridge, worn: wrapped straw gone grey, moss (wraps)
  y 256-320   eave butt ends, fresh (wraps)
  y 320-384   eave butt ends, worn (wraps)
  y 384-448   underside: straw between rafters (wraps)
  y 448-512   weathered board, grain along x (wraps)
  y 512-544   batten, darker wood (wraps)
  y 544-576   iron strap with nail heads (wraps)
  y 576-1024  x   0-448  wattle: hazel rods woven between stakes
              x 448-896  daub: clay smeared over a crack, straw in it
              x 896-1024 broken limewash edge over clay

Hand-painted look in the village kit's palette: soft strokes, warm lights,
bright moss. Painted at 2x and downsampled. Deterministic (fixed seeds).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2
N = 1024 * S
COURSES = 5          # per tile: 1.6 m / 5 = 0.32 m a course


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def jitter(c, rng, amt):
    """The same colour a little lighter or darker (no hue shift)."""
    d = rng.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v + d))) for v in c)


# --- Thatch body ----------------------------------------------------------------------------------

def course_edges(rng):
    """Lower edge of each course, y (pixels, down) per column x: a gentle
    wave plus tufts that bulge down, all periodic in x so the tile wraps."""
    x = np.arange(N, dtype=np.float64)
    pitch = N / COURSES
    edges = []
    for k in range(COURSES):
        e = np.full(N, (k + 1) * pitch)
        for f, a in ((3, 0.03), (5, 0.022), (11, 0.012), (23, 0.01)):
            e += pitch * a * np.sin(2 * math.pi * f * x / N + rng.uniform(0, 6.28))
        tufts = rng.randint(22, 28)
        p = N / tufts
        phase = rng.uniform(0, p)
        t = ((x + phase) % p) / p * 2.0 - 1.0
        depth = np.array([rng.uniform(0.02, 0.07) for _ in range(tufts)])
        idx = (((x + phase) // p).astype(int)) % tufts
        e += pitch * depth[idx] * (1.0 - t * t)
        # Ragged straw tips: every few pixels a strand ends a little lower or higher.
        tips = np.zeros(N)
        i = 0
        while i < N:
            w = rng.randint(3, 9) * S
            a = rng.uniform(-0.01, 0.045) * pitch
            tt = np.linspace(-1.0, 1.0, w)
            tips[i:i + w] = (a * (1.0 - np.abs(tt)))[:max(0, min(w, N - i))]
            i += w
        k = np.ones(3 * S) / (3 * S)
        tips = np.convolve(np.concatenate([tips[-6 * S:], tips, tips[:6 * S]]), k, mode="same")[6 * S:-6 * S]
        e += tips
        edges.append(e)
    return edges, pitch


def course_field(edges, pitch):
    """For every pixel: which course it is in and s, 0 just under the
    course above, 1 at its own butt edge. Courses wrap: the last one's
    tufts hang past the tile's foot into the top rows, and so on."""
    y = np.arange(N, dtype=np.float64)[:, None]
    course = np.zeros((N, N), dtype=np.int32)
    s = np.zeros((N, N))
    E = list(edges)
    ext = [E[-2] - N, E[-1] - N] + E + [E[0] + N]
    owner = [COURSES - 1, 0] + list(range(1, COURSES)) + [0]
    for j in range(len(ext) - 1):
        top = ext[j][None, :]
        bot = ext[j + 1][None, :]
        inside = (y >= top) & (y < bot)
        course[inside] = owner[j]
        s = np.where(inside, (y - top) / np.maximum(bot - top, 1.0), s)
    return course, np.clip(s, 0.0, 1.0)


def strands_layer(edges, pitch, rng, count):
    """Long strands down each course (bright = lighter straw), on a grey
    layer that wraps in x and y."""
    img = Image.new("L", (N, N), 128)
    d = ImageDraw.Draw(img)
    for k in range(COURSES):
        top_y = (k * pitch) - pitch * 0.35
        for _ in range(count):
            x = rng.uniform(0, N)
            ix = int(x) % N
            bot = edges[k][ix] + rng.uniform(-6, 2) * S
            y0 = top_y + rng.uniform(-pitch * 0.2, pitch * 0.7)
            if y0 > bot - 8 * S:
                y0 = bot - rng.uniform(20, 60) * S
            ang = math.radians(rng.uniform(-5, 5))
            L = bot - y0
            x1 = x + math.tan(ang) * L
            v = int(max(0, min(255, rng.gauss(128, 46))))
            w = max(1, int(rng.uniform(1.6, 3.6) * S))
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    d.line((x + ox, y0 + oy, x1 + ox, bot + oy), fill=v, width=w)
    return np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * S)), dtype=np.float64) / 255.0


def thatch_body(seed=7):
    rng = random.Random(seed)
    edges, pitch = course_edges(rng)
    course, s = course_field(edges, pitch)
    st = strands_layer(edges, pitch, rng, 1500)
    # Relief: the course swells toward its butt edge; strands ridge it.
    height = 0.78 * (s ** 0.75) + 0.22 * st
    return {"edges": edges, "pitch": pitch, "course": course, "s": s, "st": st, "height": height}


def wrap_blur(a, r):
    """Gaussian blur that wraps round the tile."""
    img = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8))
    big = Image.new("L", (N * 3, N * 3))
    for i in range(3):
        for j in range(3):
            big.paste(img, (i * N, j * N))
    big = big.filter(ImageFilter.GaussianBlur(r))
    return np.asarray(big.crop((N, N, 2 * N, 2 * N)), dtype=np.float64) / 255.0


def blobs(rng, count, rmin, rmax, bias_to=None):
    """Soft irregular blobs (moss, stains) on a wrapping mask."""
    img = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        if bias_to is not None:
            k = rng.randrange(COURSES)
            x = rng.uniform(0, N)
            y = bias_to[k][int(x) % N] - rng.uniform(0, 0.35) * (N / COURSES)
        else:
            x, y = rng.uniform(0, N), rng.uniform(0, N)
        r = rng.uniform(rmin, rmax) * S
        pts = []
        for i in range(11):
            a = i / 11 * math.tau
            rr = r * rng.uniform(0.55, 1.15)
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr * 0.7))
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                d.polygon([(px + ox, py + oy) for px, py in pts], fill=255)
    return img


def paint_body(body, palette, worn, seed):
    rng = random.Random(seed)
    s, st = body["s"], body["st"]
    dark, mid, light, butt = (np.array(c, dtype=np.float64) for c in palette)
    # Darker under the course above, lighter toward the butt ends.
    t = (s ** 0.8)[..., None]
    col = dark * (1 - t) + mid * t
    col = col + (light - mid) * np.clip((st[..., None] - 0.5) * 1.6, -1.0, 1.0)
    shade = np.clip(0.62 + 0.38 * (s / 0.2), 0.62, 1.0)[..., None]
    col *= shade
    edge = np.clip((s - 0.9) / 0.1, 0.0, 1.0)[..., None] * 0.55
    col = col * (1 - edge) + butt * edge
    if worn:
        # Rain streaks down the slope and soft dark rot.
        streak = Image.new("L", (N, N), 0)
        sd = ImageDraw.Draw(streak)
        for _ in range(90):
            x = rng.uniform(0, N)
            y = rng.uniform(0, N)
            L = rng.uniform(80, 340) * S
            w = rng.uniform(4, 14) * S
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    sd.line((x + ox, y + oy, x + ox + rng.uniform(-6, 6), y + L + oy), fill=int(rng.uniform(60, 140)), width=int(w))
        streak = wrap_blur(np.asarray(streak, dtype=np.float64) / 255.0, 5 * S)[..., None]
        col *= 1.0 - 0.32 * streak
        rot = wrap_blur(np.asarray(blobs(rng, 14, 50, 110), dtype=np.float64) / 255.0, 22 * S)[..., None]
        col = col * (1 - 0.35 * rot) + np.array((62, 58, 44)) * 0.35 * rot
        # Moss on the butt ends, where the wet lingers.
        moss = wrap_blur(np.asarray(blobs(rng, 22, 18, 52, bias_to=body["edges"]), dtype=np.float64) / 255.0, 6 * S)
        grain = wrap_blur(np.asarray(blobs(rng, 160, 4, 12), dtype=np.float64) / 255.0, 2 * S)
        moss = np.clip((moss - 0.2) * 2.0, 0, 1) * (0.55 + 0.45 * grain) * (0.35 + 0.65 * np.clip(s * 1.3 - 0.2, 0, 1))
        m_dark, m_light = np.array((58, 104, 30), dtype=np.float64), np.array((132, 184, 52), dtype=np.float64)
        mt = np.clip(st * 1.4 - 0.2, 0, 1)[..., None]
        mcol = m_dark * (1 - mt) + m_light * mt
        col = col * (1 - moss[..., None]) + mcol * moss[..., None]
        lichen = wrap_blur(np.asarray(blobs(rng, 40, 3, 7), dtype=np.float64) / 255.0, 1.2 * S)[..., None]
        col = col * (1 - 0.6 * lichen) + np.array((196, 192, 150)) * 0.6 * lichen
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB")
    return img.resize((1024, 1024), Image.LANCZOS)


def normal_map(height, strength=5.0):
    h = wrap_blur(height, 0.8 * S)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5   # rows go down the image
    k = strength * S
    n = np.stack([-dx * k * 8, dy * k * 8, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    img = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
    a = np.asarray(img, dtype=np.float64) / 255.0 * 2 - 1
    a /= np.linalg.norm(a, axis=-1, keepdims=True)
    return Image.fromarray(((a * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")


# --- Kit atlas ------------------------------------------------------------------------------------

AW = 1024 * S


def straw_strip(w, h, seed, base, dark, light, count, vertical=True, length=(30, 70)):
    """Straw strokes in a w x h strip that wraps in x."""
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(-10 * S, h)
        L = rng.uniform(*length) * S
        a = math.radians((90 if vertical else 0) + rng.uniform(-8, 8))
        c = lerp(dark, light, rng.random() ** 0.9)
        wd = max(1, int(rng.uniform(1.4, 3.0) * S))
        for ox in (-w, 0, w):
            d.line((x + ox, y, x + ox + math.cos(a) * L, y + math.sin(a) * L), fill=c, width=wd)
    return img


def rod(d, p0, p1, w, color, rng):
    """A hazel rod: body, a light top line and a dark underside."""
    hi = lerp(color, (235, 210, 160), 0.45)
    lo = lerp(color, (20, 14, 8), 0.5)
    (x0, y0), (x1, y1) = p0, p1
    d.line((x0, y0 + w * 0.35, x1, y1 + w * 0.35), fill=lo, width=int(w))
    d.line((x0, y0, x1, y1), fill=color, width=int(w))
    d.line((x0, y0 - w * 0.28, x1, y1 - w * 0.28), fill=hi, width=max(1, int(w * 0.3)))


def ridge_fresh(h):
    img = straw_strip(AW, h, 31, (214, 172, 92), (160, 118, 56), (242, 210, 134), 2600, length=(14, 34))
    d = ImageDraw.Draw(img)
    rng = random.Random(32)
    hazel = (118, 84, 50)
    w = 4.2 * S
    # Two liggers each side of the apex, crossed spars between them (mirrored).
    for side in (1, -1):
        ya = h * 0.5 + side * h * 0.17
        yb = h * 0.5 + side * h * 0.36
        step = 26 * S
        for i in range(-1, AW // step + 2):
            xa = i * step
            for ox in (0,):
                rod(d, (xa + ox, ya), (xa + step + ox, yb), w * 0.75, jitter(hazel, rng, 10), rng)
                rod(d, (xa + step + ox, ya), (xa + ox, yb), w * 0.75, jitter(hazel, rng, 10), rng)
        for y in (ya, yb):
            rod(d, (-4 * S, y), (AW + 4 * S, y), w, hazel, rng)
    # Shade toward the cut edges.
    shade = Image.new("L", (AW, h), 0)
    sd = ImageDraw.Draw(shade)
    for y in range(h):
        t = abs(y - h * 0.5) / (h * 0.5)
        sd.line((0, y, AW, y), fill=int(255 * max(0.0, t - 0.82) / 0.18 * 0.45))
    return Image.composite(Image.new("RGB", (AW, h), (120, 86, 40)), img, shade)


def ridge_worn(h):
    img = straw_strip(AW, h, 41, (120, 104, 78), (78, 68, 50), (160, 146, 112), 2600, length=(14, 34))
    rng = random.Random(42)
    d = ImageDraw.Draw(img)
    rod(d, (-4 * S, h * 0.5), (AW + 4 * S, h * 0.5 + 2 * S), 3.4 * S, (82, 64, 44), rng)
    for _ in range(46):
        x, y = rng.uniform(0, AW), rng.uniform(0, h)
        r = rng.uniform(6, 16) * S
        c = jitter((96, 150, 44), rng, 18)
        for ox in (-AW, 0, AW):
            d.ellipse((x + ox - r, y - r * 0.6, x + ox + r, y + r * 0.6), fill=c)
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def butts(h, seed, base, dots, gap, moss=False):
    """The cut face of the eave: short straw ends packed close, seen at a
    slant, the tips catching the light at the foot."""
    img = Image.new("RGB", (AW, h), gap)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(int(AW / S * 5.5)):
        x = rng.uniform(0, AW)
        y0 = rng.uniform(-h * 0.2, h * 0.55)
        y1 = y0 + rng.uniform(0.35, 0.8) * h
        c = lerp(base, dots, rng.random() ** 0.7)
        wd = max(1, int(rng.uniform(1.6, 3.2) * S))
        lean = rng.uniform(-3, 3) * S
        for ox in (-AW, 0, AW):
            d.line((x + ox, y0, x + ox + lean, y1), fill=c, width=wd)
            d.line((x + ox + lean * 0.9, y1 - 2 * S, x + ox + lean, y1), fill=lerp(c, (250, 236, 190), 0.4), width=wd)
    if moss:
        for _ in range(22):
            x = rng.uniform(0, AW)
            r = rng.uniform(8, 20) * S
            c = jitter((76, 118, 38), rng, 14)
            for ox in (-AW, 0, AW):
                d.ellipse((x + ox - r, -r * 0.6, x + ox + r, r * 0.55), fill=c)
    return img.filter(ImageFilter.GaussianBlur(0.5 * S))


def underside(h):
    img = straw_strip(AW, h, 51, (96, 74, 44), (62, 46, 28), (136, 108, 66), 1400, vertical=True, length=(16, 40))
    d = ImageDraw.Draw(img)
    pitch = AW / 22          # a rafter every ~0.45 m at the eave's mapping
    for i in range(22):
        x = i * pitch
        d.rectangle((x, 0, x + 18 * S, h), fill=(64, 44, 28))
        d.line((x + 3 * S, 0, x + 3 * S, h), fill=(92, 66, 42), width=2 * S)
    return img


def board(h):
    img = Image.new("RGB", (AW, h), (128, 120, 106))
    d = ImageDraw.Draw(img)
    rng = random.Random(61)
    for _ in range(340):
        y = rng.uniform(0, h)
        x = rng.uniform(0, AW)
        L = rng.uniform(80, 400) * S
        c = lerp((84, 78, 68), (168, 160, 142), rng.random())
        for ox in (-AW, 0, AW):
            d.line((x + ox, y, x + ox + L, y + rng.uniform(-3, 3) * S), fill=c, width=max(1, int(rng.uniform(1, 2.4) * S)))
    for _ in range(9):          # knots and split ends
        x, y = rng.uniform(0, AW), rng.uniform(h * 0.2, h * 0.8)
        r = rng.uniform(4, 8) * S
        for ox in (-AW, 0, AW):
            d.ellipse((x + ox - r * 1.6, y - r, x + ox + r * 1.6, y + r), outline=(70, 62, 52), width=2 * S, fill=(104, 94, 80))
    d.line((0, 1 * S, AW, 1 * S), fill=(176, 168, 150), width=2 * S)
    d.line((0, h - 2 * S, AW, h - 2 * S), fill=(66, 60, 52), width=3 * S)
    return img


def batten(h):
    img = Image.new("RGB", (AW, h), (96, 82, 64))
    d = ImageDraw.Draw(img)
    rng = random.Random(71)
    for _ in range(160):
        y = rng.uniform(0, h)
        x = rng.uniform(0, AW)
        c = lerp((62, 52, 40), (132, 116, 92), rng.random())
        for ox in (-AW, 0, AW):
            d.line((x + ox, y, x + ox + rng.uniform(60, 260) * S, y), fill=c, width=S)
    return img


def iron(h):
    img = Image.new("RGB", (AW, h), (58, 52, 50))
    d = ImageDraw.Draw(img)
    rng = random.Random(81)
    for _ in range(70):
        x, y = rng.uniform(0, AW), rng.uniform(0, h)
        r = rng.uniform(2, 6) * S
        for ox in (-AW, 0, AW):
            d.ellipse((x + ox - r * 2, y - r, x + ox + r * 2, y + r), fill=jitter((92, 64, 46), rng, 10))
    step = 64 * S
    for i in range(AW // step):
        x = i * step + step * 0.5
        r = 4.5 * S
        d.ellipse((x - r, h / 2 - r, x + r, h / 2 + r), fill=(38, 34, 32))
        d.ellipse((x - r * 0.5, h / 2 - r * 0.6, x + r * 0.2, h / 2 - r * 0.1), fill=(110, 104, 98))
    d.line((0, 1 * S, AW, 1 * S), fill=(96, 90, 86), width=S)
    return img


def wattle(w, h):
    """Hazel withies woven between upright stakes, clay crumbs in the gaps."""
    img = Image.new("RGB", (w, h), (58, 42, 30))
    d = ImageDraw.Draw(img)
    rng = random.Random(91)
    stakes = 5
    sp = w / stakes
    rows = 15
    rh = h / rows
    for r in range(rows):
        y = (r + 0.5) * rh
        c = jitter((128, 98, 66), rng, 10)
        for i in range(stakes):
            # Over one stake, under the next: in front it is lit, behind in shadow.
            x0, x1 = i * sp, (i + 1) * sp
            over = (i + r) % 2 == 0
            body = c if over else lerp(c, (30, 20, 12), 0.45)
            for j in range(7):      # round: dark below, light on top
                t = j / 6
                cc = lerp(lerp(body, (24, 16, 10), 0.5), lerp(body, (226, 200, 150), 0.4), t)
                yy = y + rh * 0.36 - t * rh * 0.66
                d.line((x0 - 2 * S, yy, x1 + 2 * S, yy), fill=cc, width=max(1, int(rh * 0.13)))
    for i in range(stakes + 1):
        x = i * sp
        d.rectangle((x - sp * 0.07, 0, x + sp * 0.07, h), fill=(84, 62, 42))
        d.line((x - sp * 0.035, 0, x - sp * 0.035, h), fill=(124, 96, 64), width=2 * S)
        d.line((x + sp * 0.06, 0, x + sp * 0.06, h), fill=(48, 34, 22), width=2 * S)
    for _ in range(120):        # clay still clinging
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(3, 10) * S
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=jitter((132, 104, 72), rng, 12))
    return img


def daub(w, h):
    img = Image.new("RGB", (w, h), (146, 116, 80))
    d = ImageDraw.Draw(img)
    rng = random.Random(101)
    for _ in range(90):         # trowel strokes
        x, y = rng.uniform(-40, w), rng.uniform(0, h)
        L = rng.uniform(60, 180) * S
        a = math.radians(rng.uniform(-25, 25))
        c = lerp((118, 90, 60), (178, 148, 106), rng.random())
        d.line((x, y, x + math.cos(a) * L, y + math.sin(a) * L), fill=c, width=int(rng.uniform(10, 26) * S))
    img = img.filter(ImageFilter.GaussianBlur(3 * S))
    d = ImageDraw.Draw(img)
    for _ in range(260):        # chopped straw in the clay
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        L = rng.uniform(6, 18) * S
        a = rng.uniform(0, math.tau)
        d.line((x, y, x + math.cos(a) * L, y + math.sin(a) * L), fill=jitter((206, 178, 110), rng, 14), width=max(1, int(1.4 * S)))
    for _ in range(5):          # drying cracks
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        pts = [(x, y)]
        for _ in range(6):
            x += rng.uniform(-18, 18) * S
            y += rng.uniform(8, 24) * S
            pts.append((x, y))
        d.line(pts, fill=(84, 62, 40), width=2 * S)
    return img


def broken_edge(w, h):
    """Limewash over clay, as the plaster breaks round a hole: cream on top,
    the clay showing where it has flaked."""
    img = Image.new("RGB", (w, h), (212, 198, 170))
    d = ImageDraw.Draw(img)
    rng = random.Random(111)
    for _ in range(70):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(6, 20) * S
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=jitter((150, 118, 82), rng, 12))
    for _ in range(120):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(2, 5) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=jitter((228, 218, 194), rng, 8))
    return img.filter(ImageFilter.GaussianBlur(1.2 * S))


def kit_atlas():
    atlas = Image.new("RGB", (AW, AW), (0, 0, 0))
    y = 0
    for img, hh in ((ridge_fresh(128 * S), 128), (ridge_worn(128 * S), 128),
                    (butts(64 * S, 121, (146, 108, 52), (232, 196, 118), (84, 60, 28)), 64),
                    (butts(64 * S, 131, (100, 88, 66), (160, 148, 116), (52, 44, 32), moss=True), 64),
                    (underside(64 * S), 64), (board(64 * S), 64), (batten(32 * S), 32), (iron(32 * S), 32)):
        atlas.paste(img, (0, y * S))
        y += hh
    atlas.paste(wattle(448 * S, 448 * S), (0, 576 * S))
    atlas.paste(daub(448 * S, 448 * S), (448 * S, 576 * S))
    atlas.paste(broken_edge(128 * S, 448 * S), (896 * S, 576 * S))
    return atlas.resize((1024, 1024), Image.LANCZOS)


FRESH = ((150, 106, 46), (200, 154, 72), (236, 198, 118), (240, 214, 150))
WORN = ((70, 62, 46), (122, 106, 80), (160, 146, 114), (170, 160, 130))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "textures")
    os.makedirs(out, exist_ok=True)
    body = thatch_body()
    paint_body(body, FRESH, False, 201).save(os.path.join(out, "T_Thatch_BaseColor.png"), optimize=True)
    paint_body(body, WORN, True, 202).save(os.path.join(out, "T_ThatchWorn_BaseColor.png"), optimize=True)
    normal_map(body["height"]).save(os.path.join(out, "T_Thatch_Normal.png"), optimize=True)
    kit_atlas().save(os.path.join(out, "T_ThatchKit_BaseColor.png"), optimize=True)
    print("painted", out)


if __name__ == "__main__":
    main()
