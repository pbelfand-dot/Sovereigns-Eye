"""Builds the Carts & Transport family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_carts.py [--review DIR] [--export] [--only A,B]

A carrying cart of the 1180s and the horse that draws it:
  - SE_Cart_Horse: a plank-sided cart on two spoked wheels (felloes shod
    with iron strakes), a single pair of shafts, and a small bay cart horse
    in them, in a padded collar with hames, traces to the shafts, a cart
    saddle with its back band and tugs, a belly band and a bridle. Rigid
    parts in a node tree the game animates (see NODE CONTRACT below);
  - SE_Cart_Load: a trader's load for the bed, roped down: sacks, bolts of
    cloth, a small cask, a bundle of iron bars;
  - SE_Cart: the same cart unhitched, its shafts tipped down to the ground.

NODE CONTRACT (SE_Cart_Horse; Blender +X forward = Godot +X, Blender +Z up
= Godot +Y, Blender +Y = Godot -Z = the cart's left). Every node has an
identity rotation at rest, so it turns about its own axes:
  root (the scene, on the ground at the axle's centre)
    Cart          the body, shafts, axle; origin at the root
    Wheel_L/_R    origin at the hub; spins about Blender Y (Godot Z)
    Horse         origin on the ground under the body's centre
      Leg_FL/FR/HL/HR      origin at the shoulder or hip; swing about Y
        Leg_*_Lower        origin at the knee or hock; bend about Y
      Neck                 origin at the withers
        Head               origin at the poll
      Tail                 origin at the dock
    Load_Anchor   an empty at the centre of the bed floor's top

Wood and iron are the village kit's trim sheets; the horse, its harness,
the sacks, cloth, rope and the cask's staves are this family's atlas
(T_Carts_BaseColor.png, paint_carts.py).
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "village-commons", "source")

# Same source, same GLBs: see build_farm.py.
if os.environ.get("PYTHONHASHSEED") != "0":
    os.environ["PYTHONHASHSEED"] = "0"
    os.execv(sys.executable, [sys.executable] + sys.argv)

sys.path.insert(0, COMMONS_SRC)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402
import build_commons as BC  # noqa: E402  (review renders)

FAMILY = os.path.dirname(HERE)
CT = "MI_Carts"
CT_TEX = os.path.join(FAMILY, "textures", "T_Carts_BaseColor.png")
OWN = {CT: {"doubleSided": False, "dir": os.path.join(FAMILY, "textures"),
            "pbr": {"baseColorTexture": "T_Carts_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}}}
WOOD, IRON = "MI_WoodTrim", "MI_MetalOrnaments"


def _cell(x0, y0, x1, y1, inset=1.5):
    """Image pixels (y down) of the 512 atlas -> Blender UV rect (v up)."""
    return ((x0 + inset) / 512, 1 - (y1 - inset) / 512, (x1 - inset) / 512, 1 - (y0 + inset) / 512)


for _k, (_y0, _y1) in {"coat": (0, 64), "points": (64, 128), "hair": (128, 192), "leather": (192, 224),
                       "rope": (224, 256), "collar": (256, 320), "sack": (320, 384)}.items():
    L.BANDS["ct_" + _k] = (CT, 1 - _y1 / 512 + 0.003, 1 - _y0 / 512 - 0.003)
for _k, _r in {"cloth_blue": (0, 384, 128, 426), "cloth_red": (0, 426, 128, 468), "cloth_green": (0, 468, 128, 510),
               "end_blue": (128, 384, 192, 448), "end_red": (192, 384, 256, 448), "end_green": (128, 448, 192, 512),
               "cask_head": (192, 448, 256, 512), "staves": (256, 384, 384, 512), "felt": (384, 384, 448, 448),
               "eye": (448, 384, 512, 448), "sack_neck": (384, 448, 448, 512), "dark_leather": (448, 448, 512, 512)}.items():
    L.RECTS["ct_" + _k] = (CT,) + _cell(*_r)

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

# --- The cart's main dimensions (Blender, metres) --------------------------------------------------
R_WHEEL = 0.60          # the strakes' radius = the hub's height (the game reads it as the rolling radius)
TRACK = 0.74            # each wheel's middle plane from the cart's centre line
HX = 2.60               # the horse's body centre ahead of the axle
FLOOR = 0.80            # the bed floor's top
BED_X0, BED_X1 = -0.90, 1.10   # the bed inside, tail to head
BED_Y = 0.57            # half the bed's inside width
SIDE_TOP = 1.18         # the sides' top (the top rail sits on it)
ANCHOR = Vector(((BED_X0 + BED_X1) / 2, 0.0, FLOOR))
# A shaft's centre line, +Y side: along the bed's side as its frame, then
# rising and closing in to the horse's sides at the tugs and the collar.
SHAFT = [(-0.95, 0.55, 0.71), (0.15, 0.55, 0.71), (1.15, 0.55, 0.71), (1.60, 0.51, 0.765), (2.05, 0.462, 0.845),
         (2.50, 0.418, 0.925), (2.95, 0.392, 0.98), (3.35, 0.378, 1.008), (3.54, 0.374, 1.03)]
SHAFT_R = 0.05


def shaft_pt(x, side=1):
    """The shaft's centre at x (world), on side +1 (left, +Y) or -1."""
    pts = [Vector(p) for p in SHAFT]
    for i in range(1, len(pts)):
        if x <= pts[i].x or i == len(pts) - 1:
            a, b = pts[i - 1], pts[i]
            p = a.lerp(b, (x - a.x) / (b.x - a.x))
            return Vector((p.x, side * p.y, p.z))


# --- Helpers ----------------------------------------------------------------------------------------

def obj(bm, name, mat, smooth=None, recalc=True):
    return L.to_object(bm, name, mat, smooth_angle=smooth, recalc=recalc)


def sp(v, e):
    """Signed power: superellipse sections (e < 1 squarer, e > 1 rounder)."""
    return math.copysign(abs(v) ** e, v)


def lerp_rows(rows, key):
    """Linear interpolation of rows (k, a, b, ...) at key k (clamped)."""
    if key <= rows[0][0]:
        return rows[0][1:]
    for i in range(1, len(rows)):
        if key <= rows[i][0] or i == len(rows) - 1:
            a, b = rows[i - 1], rows[i]
            f = min(1.0, (key - a[0]) / (b[0] - a[0]))
            return tuple(a[j] + (b[j] - a[j]) * f for j in range(1, len(a)))


def band_v(band, f):
    """Fraction f (0 bottom .. 1 top) of a band -> Blender v."""
    _, v0, v1 = L.BANDS[band]
    return v0 + (v1 - v0) * max(0.0, min(1.0, f))


def rect_uv(rect, a, b):
    _, u0, v0, u1, v1 = L.RECTS[rect]
    return (u0 + (u1 - u0) * a, v0 + (v1 - v0) * b)


def skin(rings, uvs, mat, name, smooth=70, cap0=None, cap1=None, weld=True):
    """A surface lofted through rings of points (each ring n points, all
    rings the same n, joined round as a tube). uvs[k] holds n + 1 (u, v),
    the last for the seam. cap0/cap1 close the first/last ring: "flat" (an
    n-gon) or (point, (u, v)) (a fan). Closed, so normals point outward."""
    bm = L.new_bm()
    uvl = bm.loops.layers.uv["UVMap"]
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for k in range(len(rings) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            f = bm.faces.new((vs[k][j], vs[k][j2], vs[k + 1][j2], vs[k + 1][j]))
            for lp, uv in zip(f.loops, (uvs[k][j], uvs[k][j + 1], uvs[k + 1][j + 1], uvs[k + 1][j])):
                lp[uvl].uv = uv
    for idx, cap in ((0, cap0), (len(rings) - 1, cap1)):
        if cap is None:
            continue
        ring, ruv = vs[idx], uvs[idx]
        if cap == "flat":
            f = bm.faces.new(ring)
            for lp in f.loops:
                lp[uvl].uv = ruv[ring.index(lp.vert)]
        else:
            pt, puv = cap
            c = bm.verts.new(pt)
            for j in range(n):
                f = bm.faces.new((ring[j], ring[(j + 1) % n], c))
                for lp, uv in zip(f.loops, (ruv[j], ruv[j + 1], puv)):
                    lp[uvl].uv = uv
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return obj(bm, name, mat, smooth=smooth)


def tube_rings(pts, prof, n, phase=0.0):
    """Rings round a path: prof[i] = (d, w, off): d half across in the
    path's plane (its "fore" side, square to the path in the XZ plane), w
    half across in Y, the ring's centre moved fore by off."""
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        fore = Vector((-t.z, 0.0, t.x)).normalized()
        d, w, off = prof[i]
        rings.append([p + fore * (off + d * math.cos(phase + 2 * math.pi * j / n)) + Y * (w * math.sin(phase + 2 * math.pi * j / n))
                      for j in range(n)])
    return rings


def strap(pts, normals, width, thick, name="strap", band="ct_leather", closed=False, smooth=40, u_scale=0.5):
    """A flat strap (leather) along pts, lying with its face out along
    normals: a thin closed box swept along, its face mapped across the band."""
    pts = [Vector(p) for p in pts]
    if closed:
        pts = pts + [pts[0]]
        normals = list(normals) + [normals[0]]
    rings, uvs, acc = [], [], 0.0
    _, v0, v1 = L.BANDS[band]
    for i, p in enumerate(pts):
        if closed and (i == 0 or i == len(pts) - 1):
            t = (pts[1] - pts[-2]).normalized()
        else:
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nn = Vector(normals[i]).normalized()
        nn = (nn - t * nn.dot(t)).normalized()
        side = t.cross(nn).normalized() * width / 2
        if i:
            acc += (p - pts[i - 1]).length
        rings.append([p - side, p + side, p + side + nn * thick, p - side + nn * thick])
        u = acc * u_scale
        uvs.append([(u, v0), (u, v1), (u, v1), (u, v0), (u, v0)])
    return skin(rings, uvs, CT, name, smooth=smooth, cap0=None if closed else "flat", cap1=None if closed else "flat")


def sweep(pts, r, band, sides=6, name="sweep", mat=None, closed=False, smooth=50, radius_fn=None, rect=None, square=False):
    bm = L.sweep(pts, r, sides=sides, band=band, rect=rect, closed=closed, radius_fn=radius_fn, square=square)
    return obj(bm, name, mat or L.BANDS.get(band, L.RECTS.get(rect, (WOOD,)))[0], smooth=smooth)


def plank(p0, p1, w, h, rng, band="wood_dark", name="plank", up=Z, bevel=0.0):
    return obj(L.beam(p0, p1, w, h, band=band, bevel=bevel, rng=rng, up=up), name, WOOD)


def iron_bar(p0, p1, r, name="iron", sides=4):
    return sweep([p0, p1], r, None, sides=sides, rect="iron_bar", name=name, mat=IRON, smooth=None, square=True)


# --- The cart ---------------------------------------------------------------------------------------

def wheel(side):
    """One wheel, built about its hub at (0, side * TRACK, R_WHEEL): a
    turned nave, eight spokes, six felloes, and six iron strakes nailed
    over the felloes' joints, one of them at the bottom."""
    parts = []
    c = Vector((0.0, side * TRACK, R_WHEEL))
    # The nave, turned, along the axle.
    prof = [(0.068, -0.15), (0.092, -0.115), (0.112, -0.035), (0.112, 0.035), (0.092, 0.115), (0.068, 0.15)]
    bm = L.lathe(prof, 10, band="wood_dark", scale=0.6)
    L.cap(bm, -0.15, "end_grain", top=False)
    L.cap(bm, 0.15, "end_grain", top=True)
    L.transform(bm, Matrix.Translation(c) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    parts.append(obj(bm, "nave", WOOD, smooth=40))
    # Spokes.
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        d = Vector((math.cos(a), 0, math.sin(a)))
        parts.append(obj(L.log(c + d * 0.085, c + d * 0.53, 0.025, sides=6, band="wood_dark", taper=0.78, jitter=0.0, seed=k + 3, rings=1),
                         "spoke", WOOD, smooth=50))
    # The felloes: one ring of 24 sections (4 to a felloe).
    m, r_in, r_out, hw = 24, 0.50, 0.585, 0.04
    _, v0, v1 = L.BANDS["wood_dark"]
    rings, uvs = [], []
    for i in range(m + 1):
        a = math.radians(-90 + 360 * i / m)
        rad = Vector((math.cos(a), 0, math.sin(a)))
        cs = [(r_out, -hw), (r_out, hw), (r_in, hw), (r_in, -hw)]
        rings.append([c + rad * rr + Y * yy for rr, yy in cs])
        u = 0.3 + r_out * (2 * math.pi * i / m) * 0.5
        uvs.append([(u, v0 + 0.02 + 0.5 * x) for x in (0.0, 0.08, 0.12, 0.2, 0.24)])
    parts.append(skin(rings, uvs, WOOD, "felloes", smooth=40))
    # Strakes: iron plates over the joints, a little wider than the felloe.
    for k in range(6):
        a0 = math.radians(-90 + 60 * k)
        rings, uvs = [], []
        segs = 3
        r_out = R_WHEEL / math.cos(math.radians(22 / segs))
        for i in range(segs + 1):
            a = a0 + math.radians(-22 + 44 * i / segs)
            rad = Vector((math.cos(a), 0, math.sin(a)))
            cs = [(r_out, -0.044), (r_out, 0.044), (0.582, 0.044), (0.582, -0.044)]
            rings.append([c + rad * rr + Y * yy for rr, yy in cs])
            uvs.append([rect_uv("iron_strap", x, 0.1 + 0.8 * i / segs) for x in (0.0, 0.8, 1.0, 0.2, 0.0)])
        parts.append(skin(rings, uvs, IRON, "strake", smooth=None, cap0="flat", cap1="flat"))
    return parts


def cart_body(rng):
    """The body, frame, shafts and axle: plank sides on stakes, a floor of
    boards across the frame, a head and a tail board, the shafts running
    on from the frame, the axle-tree under it and its arms through the
    naves, held by linchpins; iron trace hooks on the shafts."""
    parts = []
    for s in (1, -1):
        path = [Vector((x, s * y, z)) for x, y, z in SHAFT]
        n = len(path)
        parts.append(sweep(path, SHAFT_R, "wood_dark", sides=6, name="shaft", smooth=40,
                           radius_fn=lambda f: 1.0 - 0.3 * max(0.0, (f - 0.35) / 0.65)))
    # Cross bars closing the frame, before and behind the bed.
    for x in (BED_X1 + 0.16, BED_X0 - 0.045):
        a, b = shaft_pt(x, 1), shaft_pt(x, -1)
        parts.append(plank(a, b, 0.08, 0.09, rng, name="bar"))
    # The axle-tree under the frame, its arms through the naves, linchpins.
    parts.append(plank((0, -0.62, R_WHEEL), (0, 0.62, R_WHEEL), 0.11, 0.115, rng, name="axle_tree"))
    for s in (1, -1):
        parts.append(obj(L.log((0, s * 0.56, R_WHEEL), (0, s * 0.94, R_WHEEL), 0.04, sides=6, band="wood_dark", taper=0.9,
                               jitter=0.0, seed=21, rings=1), "arm", WOOD, smooth=50))
        parts.append(iron_bar((0, s * 0.915, R_WHEEL - 0.065), (0, s * 0.915, R_WHEEL + 0.07), 0.011, name="linchpin"))
    # The floor: boards across, on the frame.
    nb = 7
    bw = (BED_X1 - BED_X0) / nb
    for i in range(nb):
        x = BED_X0 + bw * (i + 0.5)
        parts.append(plank((x, -BED_Y, FLOOR - 0.02), (x, BED_Y, FLOOR - 0.02), bw - 0.008, 0.04, rng, band="wood_light", name="floor"))
    # The sides: two planks each on stakes, a rail on top.
    for s in (1, -1):
        y = s * (BED_Y + 0.015)
        for z0, z1 in ((FLOOR - 0.04, 0.975), (0.98, SIDE_TOP)):
            parts.append(plank((BED_X0 - 0.03, y, (z0 + z1) / 2), (BED_X1 + 0.03, y, (z0 + z1) / 2), 0.03, z1 - z0, rng,
                               band="wood_dark", name="side"))
        for x in (-0.84, -0.30, 0.40, 1.04):
            parts.append(plank((x, s * (BED_Y + 0.055), 0.66), (x, s * (BED_Y + 0.055), SIDE_TOP + 0.07), 0.05, 0.06, rng,
                               name="stake", up=X))
        parts.append(plank((BED_X0 - 0.05, s * (BED_Y + 0.025), SIDE_TOP + 0.02), (BED_X1 + 0.05, s * (BED_Y + 0.025), SIDE_TOP + 0.02),
                           0.07, 0.045, rng, name="rail"))
    # Head and tail boards (the tail board lower, to drop out).
    for x, top in ((BED_X1 + 0.015, 1.14), (BED_X0 - 0.015, 1.10)):
        mid = (FLOOR - 0.04 + top) / 2
        for z0, z1 in ((FLOOR - 0.04, mid - 0.003), (mid + 0.003, top)):
            parts.append(plank((x, -(BED_Y + 0.03), (z0 + z1) / 2), (x, BED_Y + 0.03, (z0 + z1) / 2), 0.03, z1 - z0, rng,
                               band="wood_dark", name="end_board"))
    # Iron trace hooks on the shafts, where the traces end.
    for s in (1, -1):
        p = shaft_pt(HX - 0.55, s)
        parts.append(sweep([p + Vector((0.05, -s * 0.01, 0.03)), p + Vector((0.0, -s * 0.02, 0.075)), p + Vector((-0.05, -s * 0.03, 0.07))],
                           0.011, None, sides=4, rect="iron_bar", name="hook", mat=IRON, smooth=None))
    return parts


# --- The horse --------------------------------------------------------------------------------------
# Horse-local (origin on the ground under the body's centre, +X ahead): a
# small cart horse of 13.3-14 hands, 1.41 m at the withers.

BODY_E = 0.85
# x, top, bottom, half width
BODY = [
    (-0.845, 1.17, 1.06, 0.07),
    (-0.80, 1.285, 0.975, 0.16),
    (-0.72, 1.345, 0.905, 0.225),
    (-0.60, 1.378, 0.862, 0.255),
    (-0.46, 1.386, 0.832, 0.268),
    (-0.32, 1.37, 0.80, 0.274),
    (-0.16, 1.348, 0.772, 0.284),
    (0.00, 1.338, 0.752, 0.29),
    (0.16, 1.352, 0.752, 0.29),
    (0.30, 1.386, 0.766, 0.276),
    (0.42, 1.408, 0.792, 0.25),
    (0.54, 1.392, 0.83, 0.226),
    (0.66, 1.31, 0.878, 0.205),
    (0.75, 1.17, 0.928, 0.172),
    (0.805, 1.06, 0.975, 0.10),
]


def body_pt(x, th, off=0.0):
    """A point on the barrel at x, angle th round it (-pi/2 belly, 0 the
    left side, pi/2 the spine, pi the right side), and its outward normal;
    `off` out along the normal."""
    top, bot, w = lerp_rows(BODY, x)
    zc, h = (top + bot) / 2, (top - bot) / 2
    c, s = math.cos(th), math.sin(th)
    p = Vector((x, w * sp(c, BODY_E), zc + h * sp(s, BODY_E)))
    n = Vector((0.0, c / w, s / h)).normalized()
    return p + n * off, n


def coat_f(th):
    """Where a point round the barrel falls across the coat band: 0 at the
    belly's middle line, 1 at the spine, the same both sides."""
    th = th % (2 * math.pi)
    if th > 1.5 * math.pi:
        th -= 2 * math.pi
    return (th + math.pi / 2) / math.pi if th <= math.pi / 2 else (1.5 * math.pi - th) / math.pi


def horse_body():
    n = 14
    rings, uvs = [], []
    for x, top, bot, w in BODY:
        ring, uv = [], []
        for j in range(n + 1):
            th = -math.pi / 2 + 2 * math.pi * j / n
            if j < n:
                ring.append(body_pt(x, th)[0])
            uv.append((0.1 + x * 0.45, band_v("ct_coat", coat_f(th))))
        rings.append(ring)
        uvs.append(uv)
    x0, x1 = BODY[0][0], BODY[-1][0]
    c0 = ((BODY[0][1] + BODY[0][2]) / 2)
    c1 = ((BODY[-1][1] + BODY[-1][2]) / 2)
    return skin(rings, uvs, CT, "barrel", smooth=80,
                cap0=(Vector((x0 - 0.025, 0, c0)), (0.1 + x0 * 0.45, band_v("ct_coat", 0.5))),
                cap1=(Vector((x1 + 0.02, 0, c1)), (0.1 + x1 * 0.45, band_v("ct_coat", 0.5))))


# The legs. Each segment: a path down the leg, a section at each point
# (half depth fore-and-aft, half width, moved fore by), the map from height
# to the coat (bay above, black from the knee or hock down, the hoof).
LEG_N = 8
FORE_UPPER = [((0.50, 1.10), (0.10, 0.07, -0.005)), ((0.50, 1.00), (0.125, 0.08, -0.012)), ((0.50, 0.86), (0.112, 0.074, -0.022)),
              ((0.505, 0.72), (0.08, 0.06, -0.006)), ((0.51, 0.56), (0.056, 0.048, 0.0)),
              ((0.51, 0.44), (0.05, 0.05, 0.0))]
FORE_LOWER = [((0.51, 0.44), (0.054, 0.054, 0.0)), ((0.51, 0.385), (0.048, 0.04, 0.0)), ((0.51, 0.27), (0.042, 0.031, -0.002)),
              ((0.506, 0.195), (0.046, 0.035, -0.004)), ((0.50, 0.15), (0.056, 0.044, -0.008)), ((0.52, 0.108), (0.043, 0.038, 0.0)),
              ((0.545, 0.075), (0.053, 0.05, 0.0)), ((0.56, 0.0), (0.066, 0.061, 0.0))]
HIND_UPPER = [((-0.49, 1.14), (0.12, 0.085, 0.0)), ((-0.50, 1.02), (0.15, 0.10, -0.025)), ((-0.505, 0.88), (0.152, 0.092, -0.045)),
              ((-0.535, 0.76), (0.135, 0.074, -0.025)), ((-0.575, 0.62), (0.084, 0.055, -0.008)),
              ((-0.60, 0.50), (0.06, 0.06, 0.0))]
HIND_LOWER = [((-0.60, 0.50), (0.064, 0.064, 0.0)), ((-0.60, 0.44), (0.06, 0.042, -0.012)), ((-0.60, 0.32), (0.046, 0.033, -0.003)),
              ((-0.602, 0.21), (0.048, 0.036, -0.004)), ((-0.605, 0.16), (0.056, 0.044, -0.008)), ((-0.585, 0.105), (0.043, 0.038, 0.0)),
              ((-0.565, 0.072), (0.051, 0.048, 0.0)), ((-0.55, 0.0), (0.063, 0.058, 0.0))]
LEGS = {  # name: (y, upper, lower, the knee or hock's height)
    "Leg_FL": (0.15, FORE_UPPER, FORE_LOWER, 0.44),
    "Leg_FR": (-0.15, FORE_UPPER, FORE_LOWER, 0.44),
    "Leg_HL": (0.16, HIND_UPPER, HIND_LOWER, 0.50),
    "Leg_HR": (-0.16, HIND_UPPER, HIND_LOWER, 0.50),
}


def points_f(z, joint):
    """Height on a leg -> fraction up the points band: the hoof's horn,
    the coronet, black to the joint, shading to bay above it."""
    stops = [(0.0, 0.0), (0.074, 0.10), (0.09, 0.118), (joint, 0.55), (joint + 0.13, 0.70), (1.25, 0.98)]
    return lerp_rows(stops, z)[0]


def limb(name, spec, y, joint, top=None, bottom=None):
    """One leg segment: a tube down the path. top/bottom close its ends:
    ("dome", r) a half sphere about the end point (a joint), ("fan",) a
    point just past the end (inside the body), ("flat",) the hoof's sole."""
    pts = [Vector((x, y, z)) for (x, z), _ in spec]
    prof = [p for _, p in spec]
    n = LEG_N
    rings = tube_rings(pts, prof, n)
    # The hoof: its rings level, its sole on the ground.
    if bottom and bottom[0] == "flat":
        for k in (-1, -2):
            (x, z), (d, w, off) = spec[k]
            rings[k] = [Vector((x + d * math.cos(2 * math.pi * j / n), y + w * math.sin(2 * math.pi * j / n), z)) for j in range(n)]
    caps = [None, None]
    for end, how in ((0, top), (1, bottom)):
        if not how:
            continue
        i = 0 if end == 0 else len(pts) - 1
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        out = -t if end == 0 else t
        if how[0] == "dome":
            r = how[1]
            fore = Vector((-t.z, 0.0, t.x)).normalized()
            extra = []
            for phi in (math.radians(52),):
                cen = pts[i] + out * r * math.sin(phi)
                extra.append([cen + (fore * math.cos(2 * math.pi * j / n) + Y * math.sin(2 * math.pi * j / n)) * r * math.cos(phi)
                              for j in range(n)])
            if end == 0:
                rings = extra + rings
            else:
                rings = rings + extra
            caps[end] = pts[i] + out * r
        elif how[0] == "fan":
            caps[end] = pts[i] + out * 0.03
        elif how[0] == "flat":
            caps[end] = "flat"
    uvs = [[((j / n) * 0.25, band_v("ct_points", points_f(r[j % n].z, joint))) for j in range(n + 1)] for r in rings]
    cap_args = []
    for c in caps:
        if c is None or c == "flat":
            cap_args.append(c)
        else:
            cap_args.append((c, (0.125, band_v("ct_points", points_f(c.z, joint)))))
    return skin(rings, uvs, CT, name, smooth=75, cap0=cap_args[0], cap1=cap_args[1])


# The neck: from the shoulders up to the poll. Each row: the crest (top
# line), the throat (under line), half width.
NECK_E = 0.9
NECK = [
    ((0.34, 1.37), (0.60, 0.95), 0.20),
    ((0.47, 1.43), (0.74, 1.005), 0.18),
    ((0.60, 1.49), (0.835, 1.10), 0.16),
    ((0.72, 1.555), (0.885, 1.215), 0.142),
    ((0.82, 1.615), (0.915, 1.33), 0.125),
    ((0.91, 1.67), (0.94, 1.43), 0.11),
    ((0.98, 1.712), (0.96, 1.515), 0.10),
]
WITHERS = Vector((0.42, 0.0, 1.408))
POLL = Vector((1.02, 0.0, 1.70))


def neck_row(s):
    """The neck's row at s (0 base .. 1 poll): crest, throat, half width."""
    k = s * (len(NECK) - 1)
    i = min(int(k), len(NECK) - 2)
    f = k - i
    (ta, ua, wa), (tb, ub, wb) = NECK[i], NECK[i + 1]
    t = Vector((ta[0] + (tb[0] - ta[0]) * f, 0, ta[1] + (tb[1] - ta[1]) * f))
    u = Vector((ua[0] + (ub[0] - ua[0]) * f, 0, ua[1] + (ub[1] - ua[1]) * f))
    return t, u, wa + (wb - wa) * f


def neck_pt(s, ang, off=0.0):
    """A point on the neck: ang -pi/2 the throat, 0 the left side, pi/2
    the crest, pi the right side; and the outward normal."""
    t, u, w = neck_row(s)
    c, m = (t + u) / 2, (t - u) / 2
    h = m.length
    mu = m.normalized()
    cs, sn = math.cos(ang), math.sin(ang)
    p = c + mu * (h * sp(sn, NECK_E)) + Y * (w * sp(cs, NECK_E))
    nrm = (Y * (cs / w) + mu * (sn / h)).normalized()
    return p + nrm * off, nrm


def horse_neck():
    n = 12
    ss = [0.0, 0.14, 0.3, 0.48, 0.66, 0.84, 1.0]
    rings, uvs = [], []
    for s in ss:
        ring, uv = [], []
        for j in range(n + 1):
            ang = -math.pi / 2 + 2 * math.pi * j / n
            if j < n:
                ring.append(neck_pt(s, ang)[0])
            uv.append((0.3 + s * 0.4, band_v("ct_coat", coat_f(ang))))
        rings.append(ring)
        uvs.append(uv)
    t0, u0, _ = neck_row(0.0)
    t1, u1, _ = neck_row(1.0)
    return skin(rings, uvs, CT, "neck", smooth=80,
                cap0=((t0 + u0) / 2, (0.3, band_v("ct_coat", 0.5))),
                cap1=((t1 + u1) / 2 + Vector((0.06, 0, -0.04)), (0.7, band_v("ct_coat", 0.5))))


def horse_mane():
    """The mane along the crest, falling to the right (off) side."""
    ss = [0.05, 0.16, 0.28, 0.4, 0.52, 0.64, 0.76, 0.88, 0.97]
    # (angle round the neck, out from it, across the hair band)
    cs = [(math.pi / 2 - 0.26, -0.012, 0.92), (math.pi / 2 - 0.06, 0.026, 1.0), (math.pi / 2 + 0.24, 0.03, 0.72),
          (math.pi / 2 + 0.64, 0.012, 0.02), (math.pi / 2 + 0.58, -0.014, 0.0)]
    rings, uvs = [], []
    for s in ss:
        k = 1.0 - 0.45 * max(0.0, (s - 0.75) / 0.25) - 0.4 * max(0.0, (0.2 - s) / 0.2)   # thinner at the poll and the withers
        ring, uv = [], []
        for ang, off, f in cs:
            a = math.pi / 2 + (ang - math.pi / 2) * k
            ring.append(neck_pt(s, a, off * k)[0])
            uv.append((s * 0.6, band_v("ct_hair", f)))
        uv.append((s * 0.6, band_v("ct_hair", cs[0][2])))
        rings.append(ring)
        uvs.append(uv)
    return skin(rings, uvs, CT, "mane", smooth=60, cap0="flat", cap1="flat")


# The head, from the poll down its face to the muzzle. Rows: distance
# down the face, the face's offset, the jaw's offset (square to it), half width.
HEAD_A = Vector((0.36, 0.0, -0.44)).normalized()      # down the face
HEAD_N = Vector((-HEAD_A.z, 0.0, HEAD_A.x))           # out of the face (ahead and up)
HEAD_E = 0.85
HEAD = [
    (-0.02, 0.005, -0.06, 0.045),
    (0.03, 0.05, -0.125, 0.082),
    (0.09, 0.07, -0.18, 0.098),
    (0.16, 0.074, -0.205, 0.10),
    (0.24, 0.07, -0.195, 0.09),
    (0.32, 0.064, -0.14, 0.075),
    (0.40, 0.058, -0.10, 0.066),
    (0.47, 0.056, -0.088, 0.066),
    (0.53, 0.056, -0.084, 0.07),
    (0.575, 0.045, -0.072, 0.066),
    (0.605, 0.018, -0.05, 0.048),
]


def head_pt(t, ang, off=0.0):
    """A point on the head: ang pi/2 the face, -pi/2 under the jaw, 0 the
    left cheek; and the outward normal."""
    ft, jt, w = lerp_rows(HEAD, t)
    c, h = (ft + jt) / 2, (ft - jt) / 2
    cs, sn = math.cos(ang), math.sin(ang)
    p = POLL + HEAD_A * t + HEAD_N * (c + h * sp(sn, HEAD_E)) + Y * (w * sp(cs, HEAD_E))
    nrm = (HEAD_N * (sn / h) + Y * (cs / w)).normalized()
    return p + nrm * off, nrm


def head_f(t):
    """Down the head into the points band: bay at the poll, dark at the muzzle."""
    return lerp_rows([(0.0, 0.82), (0.35, 0.76), (0.5, 0.68), (0.62, 0.6)], t)[0]


def horse_head():
    n = 10
    rings, uvs = [], []
    for t, _, _, _ in HEAD:
        ring, uv = [], []
        for j in range(n + 1):
            ang = -math.pi / 2 + 2 * math.pi * j / n
            if j < n:
                ring.append(head_pt(t, ang)[0])
            uv.append((j / n * 0.25, band_v("ct_points", head_f(t))))
        rings.append(ring)
        uvs.append(uv)
    t0, t1 = HEAD[0][0], HEAD[-1][0]
    back = POLL + HEAD_A * (t0 - 0.02) + HEAD_N * (-0.03)
    nose = POLL + HEAD_A * (t1 + 0.012) + HEAD_N * (-0.015)
    return skin(rings, uvs, CT, "head", smooth=75,
                cap0=(back, (0.1, band_v("ct_points", head_f(0.0)))), cap1=(nose, (0.1, band_v("ct_points", head_f(0.62)))))


def horse_ear(side):
    """An ear: a leaf-shaped cone standing up from behind the forehead,
    its opening forward, dark at the tip."""
    base, _ = head_pt(0.035, math.pi / 2 - 0.62 * side, -0.012)
    d = Vector((0.1, side * 0.24, 1.0)).normalized()
    fore = (X - d * X.dot(d)).normalized()
    lat = d.cross(fore).normalized()
    n = 5
    prof = [(0.0, 0.024, 0.034), (0.05, 0.022, 0.032), (0.095, 0.012, 0.018)]
    rings, uvs = [], []
    for k, (a, rf, rl) in enumerate(prof):
        rings.append([base + d * a + fore * (rf * math.cos(2 * math.pi * j / n)) + lat * (rl * math.sin(2 * math.pi * j / n)) for j in range(n)])
        uvs.append([(j / n * 0.1, band_v("ct_points", 0.78 - 0.1 * k)) for j in range(n + 1)])
    tip = base + d * 0.13 + fore * 0.006
    return skin(rings, uvs, CT, "ear", smooth=60, cap0="flat", cap1=(tip, (0.05, band_v("ct_points", 0.5))))


def horse_eye(side):
    """A dark eye set into the head, a glint in it."""
    t, ang = 0.165, 0.30
    a = ang if side > 0 else math.pi - ang
    c, nrm = head_pt(t, a, -0.004)
    along = (HEAD_A - nrm * HEAD_A.dot(nrm)).normalized()
    up = nrm.cross(along).normalized() * side
    n = 6
    rings, uvs = [], []
    for k, (rad, out) in enumerate(((1.0, 0.0),)):
        ring, uv = [], []
        for j in range(n + 1):
            a2 = 2 * math.pi * j / n
            if j < n:
                ring.append(c + nrm * out + along * (0.024 * rad * math.cos(a2)) + up * (0.016 * rad * math.sin(a2)))
            uv.append(rect_uv("ct_eye", 0.5 + 0.5 * rad * math.cos(a2) * 0.9, 0.5 + 0.5 * rad * math.sin(a2) * 0.9 * side))
        rings.append(ring)
        uvs.append(uv)
    return skin(rings, uvs, CT, "eye", smooth=80, cap0="flat", cap1=(c + nrm * 0.015, rect_uv("ct_eye", 0.5, 0.5)))


def horse_forelock():
    """A forelock between the ears, lying down the forehead."""
    rings, uvs = [], []
    for k, t in enumerate((0.0, 0.07, 0.14)):
        ring, uv = [], []
        for j, (ang, off, f) in enumerate(((math.pi / 2 + 0.3 - 0.06 * k, -0.005, 0.9), (math.pi / 2, 0.018 - 0.005 * k, 1.0),
                                           (math.pi / 2 - 0.3 + 0.06 * k, -0.005, 0.9))):
            ring.append(head_pt(t, ang, off)[0] + HEAD_N * 0.0)
            uv.append((j * 0.03, band_v("ct_hair", 1.0 - t * 4)))
        uv.append((0.09, band_v("ct_hair", 1.0 - t * 4)))
        rings.append(ring)
        uvs.append(uv)
    tip, _ = head_pt(0.17, math.pi / 2, 0.004)
    return skin(rings, uvs, CT, "forelock", smooth=60, cap0="flat", cap1=(tip, (0.03, band_v("ct_hair", 0.1))))


TAIL_DOCK = Vector((-0.80, 0.0, 1.28))
TAIL = [((-0.80, 1.29), (0.045, 0.045, 0.0)), ((-0.865, 1.245), (0.052, 0.05, 0.0)), ((-0.91, 1.14), (0.066, 0.058, 0.0)),
        ((-0.93, 0.98), (0.082, 0.066, 0.0)), ((-0.93, 0.80), (0.08, 0.062, 0.0)), ((-0.912, 0.64), (0.064, 0.05, 0.0)),
        ((-0.89, 0.52), (0.035, 0.03, 0.0))]


def horse_tail():
    pts = [Vector((x, 0.0, z)) for (x, z), _ in TAIL]
    prof = [p for _, p in TAIL]
    n = 8
    rings = tube_rings(pts, prof, n)
    uvs = [[(j / n * 0.3, band_v("ct_hair", 1.0 - k / (len(rings) - 1))) for j in range(n + 1)] for k in range(len(rings))]
    return skin(rings, uvs, CT, "tail", smooth=70, cap0=(pts[0] + Vector((0.03, 0, 0.02)), (0.15, band_v("ct_hair", 1.0))),
                cap1=(pts[-1] + Vector((0.005, 0, -0.04)), (0.15, band_v("ct_hair", 0.0))))


# --- The harness ------------------------------------------------------------------------------------

COLLAR_S = 0.27


def collar_frame():
    """The collar's centre, its long axis (up the neck's section, back
    toward the withers), its normal (on up the neck), inner half sizes."""
    t, u, w = neck_row(COLLAR_S)
    c = (t + u) / 2
    m = (t - u).normalized()
    k = Vector((m.z, 0.0, -m.x))
    if k.x < 0:
        k = -k
    return c, m, k, (t - u).length / 2 + 0.028, w + 0.026


def collar_pt(phi, out=0.0, fwd=0.0):
    """A point round the collar's roll centre line: phi 90 deg the top, 0
    the left side, -90 the breast."""
    c, m, k, a, b = collar_frame()
    r = collar_r(phi)
    return c + k * fwd + m * ((a + r + out) * math.sin(phi)) + Y * ((b + r + out) * math.cos(phi))


def collar_r(phi):
    return 0.05 + 0.022 * math.cos(phi) ** 2


def harness(rng):
    """The collar, hames and traces, the cart saddle with its back band,
    tugs and belly band. Horse-local."""
    parts = []
    # The collar: a stuffed leather roll round the neck against the shoulders.
    m_pts = 12
    pts = [collar_pt(2 * math.pi * i / m_pts + math.pi / 2) for i in range(m_pts)]
    radii = [collar_r(2 * math.pi * i / m_pts + math.pi / 2) for i in range(m_pts)]
    parts.append(sweep(pts, 0.06, "ct_collar", sides=6, name="collar", mat=CT, closed=True, smooth=70,
                       radius_fn=lambda f: radii[min(m_pts - 1, int(round(f * (m_pts - 1))))] / 0.06))
    # The hames: a bent timber down each side of the collar's front.
    hook = {}
    for s in (1, -1):
        hp = []
        for i in range(6):
            phi = math.radians(78 - 158 * i / 5)
            ph = phi if s > 0 else math.pi - phi
            hp.append(collar_pt(ph, out=0.0, fwd=0.062))
        parts.append(sweep(hp, 0.024, "wood_light", sides=4, name="hame", smooth=40))
        ph = math.radians(-12) if s > 0 else math.pi + math.radians(12)
        h0 = collar_pt(ph, out=0.01, fwd=0.062)
        h1 = h0 + Y * s * 0.04 + Vector((-0.02, 0, 0))
        parts.append(iron_bar(h0, h1, 0.012, name="hame_hook"))
        hook[s] = h1
        # A strap ties the hames together over the top.
    tie = [collar_pt(math.radians(a), out=0.01, fwd=0.062) for a in (78, 90, 102)]
    parts.append(strap(tie, [Vector((0, 0, 1))] * 3, 0.03, 0.012, name="hame_strap"))
    # Traces: rope from the hame hooks back to the hooks on the shafts.
    for s in (1, -1):
        end = shaft_pt(HX - 0.55, s) - Vector((HX, 0, 0)) + Vector((-0.04, -s * 0.03, 0.07))
        a = hook[s]
        tp = []
        for i in range(5):
            f = i / 4
            p = a.lerp(end, f)
            p.z -= 0.05 * math.sin(math.pi * f)
            top, bot, w = lerp_rows(BODY, p.x)
            p.y = s * max(abs(p.y), w + 0.045) if -0.84 < p.x < 0.8 else p.y
            tp.append(p)
        parts.append(sweep(tp, 0.016, "ct_rope", sides=4, name="trace", mat=CT, smooth=50))
    # The cart saddle: a felt pad over the back, a wooden tree on it with
    # the back band over it, down each side to the tugs round the shafts.
    xs = [0.10, 0.19, 0.28, 0.37]
    ths = [math.pi / 2 + (k - 2) * 0.26 * math.pi / 2 for k in range(5)]
    bm = L.new_bm()
    uvl = bm.loops.layers.uv["UVMap"]
    grid = [[bm.verts.new(body_pt(x, th, 0.032)[0]) for th in ths] for x in xs]
    low = [[bm.verts.new(body_pt(x, th, -0.01)[0]) for th in ths] for x in xs]

    def face(vs, uvs, want):
        f = bm.faces.new(vs)
        for lp, uv in zip(f.loops, uvs):
            lp[uvl].uv = uv
        f.normal_update()
        if f.normal.dot(want) < 0:
            f.normal_flip()

    def puv(i, j):
        return rect_uv("ct_felt", 0.06 + 0.88 * j / (len(ths) - 1), 0.06 + 0.88 * i / (len(xs) - 1))

    for i in range(len(xs) - 1):
        for j in range(len(ths) - 1):
            want = body_pt((xs[i] + xs[i + 1]) / 2, (ths[j] + ths[j + 1]) / 2)[1]
            face([grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]], [puv(i, j), puv(i, j + 1), puv(i + 1, j + 1), puv(i + 1, j)], want)
    edge = rect_uv("ct_felt", 0.02, 0.5)
    for i in (0, len(xs) - 1):
        for j in range(len(ths) - 1):
            want = X * (1 if i else -1)
            face([grid[i][j], grid[i][j + 1], low[i][j + 1], low[i][j]], [edge] * 4, want)
    for j in (0, len(ths) - 1):
        for i in range(len(xs) - 1):
            want = body_pt(xs[i], ths[j])[1]
            face([grid[i][j], grid[i + 1][j], low[i + 1][j], low[i][j]], [edge] * 4, want)
    bm.normal_update()
    parts.append(obj(bm, "pad", CT, smooth=50, recalc=False))
    xb = 0.235
    tree = [body_pt(xb, math.pi / 2 + a, 0.075)[0] for a in (-0.55, -0.28, 0.0, 0.28, 0.55)]
    parts.append(sweep(tree, 0.035, "wood_dark", sides=4, name="saddle_tree", smooth=40))
    tug_x = xb
    tugs = {s: shaft_pt(HX + tug_x, s) - Vector((HX, 0, 0)) for s in (1, -1)}
    bb, bn = [], []
    for s in (1, -1):
        side = [tugs[s] + Vector((0, 0, 0.075)), tugs[s] + Vector((0, -s * 0.03, 0.2))]
        for a in (0.16, 0.38):
            th = a * math.pi if s > 0 else math.pi - a * math.pi
            side.append(body_pt(xb, th, 0.02 + 0.08 * a)[0])
        normals = [Y * s, Y * s] + [body_pt(xb, (a * math.pi if s > 0 else math.pi - a * math.pi))[1] for a in (0.16, 0.38)]
        if s < 0:
            side.reverse()
            normals.reverse()
        if s > 0:
            bb += side
            bn += normals
        else:
            bb += [body_pt(xb, math.pi / 2, 0.11)[0]] + side
            bn += [Z] + normals
    parts.append(strap(bb, bn, 0.06, 0.012, name="back_band"))
    # Tugs: leather loops round the shafts.
    for s in (1, -1):
        loop = [tugs[s] + (Y * math.cos(a) + Z * math.sin(a)) * (SHAFT_R * 0.9 + 0.024) for a in [2 * math.pi * k / 5 + math.pi / 2 for k in range(5)]]
        parts.append(sweep(loop, 0.013, "ct_leather", sides=3, name="tug", mat=CT, closed=True, smooth=60))
    # The belly band, tug to tug under the barrel.
    belly, bnorm = [], []
    for s in (1, -1):
        side = [tugs[s] + Vector((0, 0, -0.07)), body_pt(xb + 0.01, -0.12 * math.pi if s > 0 else math.pi + 0.12 * math.pi, 0.016)[0],
                body_pt(xb + 0.01, -0.32 * math.pi if s > 0 else math.pi + 0.32 * math.pi, 0.016)[0]]
        nrm = [Y * s, body_pt(xb + 0.01, -0.12 * math.pi if s > 0 else math.pi + 0.12 * math.pi)[1],
               body_pt(xb + 0.01, -0.32 * math.pi if s > 0 else math.pi + 0.32 * math.pi)[1]]
        if s > 0:
            belly += side
            bnorm += nrm
        else:
            belly += [body_pt(xb + 0.01, -math.pi / 2, 0.016)[0]] + list(reversed(side))
            bnorm += [-Z] + list(reversed(nrm))
    parts.append(strap(belly, bnorm, 0.065, 0.01, name="belly_band"))
    return parts


def bridle():
    """A headstall over the poll and down the cheeks to the bit, a
    noseband round the face, bit rings at the corners of the mouth."""
    parts = []
    off = 0.006
    for s in (1, -1):
        def a(x):
            return x if s > 0 else math.pi - x
        path = [(0.0, math.pi / 2), (0.03, 0.95), (0.10, 0.05), (0.22, -0.45), (0.37, -0.58), (0.5, -0.42)]
        pts = [head_pt(t, a(g), off)[0] for t, g in path]
        nrm = [head_pt(t, a(g))[1] for t, g in path]
        parts.append(strap(pts, nrm, 0.024, 0.008, name="cheekpiece"))
        c, nn = head_pt(0.505, a(-0.42), 0.012)
        ring = [c + (HEAD_A * math.cos(k * math.pi / 2 + 0.4) + HEAD_N * math.sin(k * math.pi / 2 + 0.4)) * 0.024 for k in range(4)]
        parts.append(sweep(ring, 0.006, None, sides=3, rect="iron_bar", name="bit_ring", mat=IRON, closed=True, smooth=None))
    nose = [head_pt(0.40, -math.pi / 2 + 2 * math.pi * k / 8, off) for k in range(8)]
    parts.append(strap([p for p, _ in nose], [n for _, n in nose], 0.026, 0.008, name="noseband", closed=True))
    brow = [head_pt(0.05, math.pi / 2 + g, off) for g in (-0.7, 0.0, 0.7)]
    parts.append(strap([p for p, _ in brow], [n for _, n in brow], 0.02, 0.008, name="browband"))
    return parts


# --- The node tree ----------------------------------------------------------------------------------

class Node:
    """A part the game moves: its objects (world space, joined at the end),
    its pivot (world space) and its children."""

    def __init__(self, name, pivot, parent=None):
        self.name, self.pivot, self.parent = name, Vector(pivot), parent
        self.parts, self.children = [], []
        if parent:
            parent.children.append(self)

    def add(self, *objs):
        self.parts += [o for o in objs if o is not None]

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def realize(roots):
    """Joins each node's parts into one object named for the node, its
    origin at the pivot, parented with an identity rotation; returns the
    objects, top-level first."""
    made = []

    def make(n, parent_obj):
        if n.parts:
            for o in n.parts:
                if o.matrix_world != Matrix.Identity(4):
                    o.data.transform(o.matrix_world)
                    o.matrix_world = Matrix.Identity(4)
            o = L.join(n.parts, n.name) if len(n.parts) > 1 else n.parts[0]
            o.name = o.data.name = n.name
            o.data.transform(Matrix.Translation(-n.pivot))
            uvs = o.data.uv_layers
            uvs.active = uvs["UVMap"]
            uvs["UVMap"].active_render = True
            if "Sway" in uvs:
                uvs.remove(uvs["Sway"])
        else:
            o = bpy.data.objects.new(n.name, None)
            bpy.context.scene.collection.objects.link(o)
            o.empty_display_type = "PLAIN_AXES"
            o.empty_display_size = 0.15
        o.location = n.pivot - (n.parent.pivot if n.parent else Vector())
        if parent_obj:
            o.parent = parent_obj
        made.append(o)
        for c in n.children:
            make(c, o)

    for r in roots:
        make(r, None)
    return made


def cart_horse():
    rng = random.Random(5)
    roots = []
    cart = Node("Cart", (0, 0, 0))
    cart.add(*cart_body(rng))
    roots.append(cart)
    for name, s in (("Wheel_L", 1), ("Wheel_R", -1)):
        w = Node(name, (0, s * TRACK, R_WHEEL))
        w.add(*wheel(s))
        roots.append(w)
    off = Vector((HX, 0, 0))
    horse = Node("Horse", off)
    horse.add(horse_body(), *harness(rng))
    for name, (y, upper, lower, joint) in LEGS.items():
        (ux, uz), _ = upper[1]
        leg = Node(name, off + Vector((ux, y, uz)), horse)
        leg.add(limb(name.lower(), upper, y, joint, top=("fan",), bottom=("dome", upper[-1][1][0])))
        (lx, lz), (lr, _, _) = lower[0]
        low = Node(name + "_Lower", off + Vector((lx, y, lz)), leg)
        low.add(limb(name.lower() + "_lower", lower, y, joint, top=("dome", lr), bottom=("flat",)))
    neck = Node("Neck", off + WITHERS, horse)
    neck.add(horse_neck(), horse_mane())
    head = Node("Head", off + POLL, neck)
    head.add(horse_head(), horse_ear(1), horse_ear(-1), horse_eye(1), horse_eye(-1), horse_forelock(), *bridle())
    tail = Node("Tail", off + TAIL_DOCK, horse)
    tail.add(horse_tail())
    roots.append(horse)
    roots.append(Node("Load_Anchor", ANCHOR))
    # The horse was built about its own origin: move it into the shafts.
    for r in (horse,):
        for n in r.walk():
            for o in n.parts:
                o.data.transform(Matrix.Translation(off))
    return realize(roots)


def cart_unhitched():
    """The cart out of the shafts: the body tipped forward about the axle
    until the shafts' ends rest on the ground, the wheels as they stand."""
    rng = random.Random(5)
    body = cart_body(rng)
    wheels = wheel(1) + wheel(-1)
    pts = [v.co.copy() for o in body for v in o.data.vertices]

    def low(phi):
        c, s = math.cos(phi), math.sin(phi)
        return min(R_WHEEL - p.x * s + (p.z - R_WHEEL) * c for p in pts)

    lo, hi = 0.0, 0.6
    for _ in range(40):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if low(mid) > 0 else (lo, mid)
    tip = Matrix.Translation((0, 0, R_WHEEL)) @ Matrix.Rotation(hi, 4, "Y") @ Matrix.Translation((0, 0, -R_WHEEL))
    for o in body:
        o.data.transform(tip)
    print("SE_Cart: tipped %.1f degrees" % math.degrees(hi))
    return [L.join(body + wheels, "SE_Cart")]


# --- The load ---------------------------------------------------------------------------------------
# In the load's own frame: its origin at the bed floor's top centre (where
# Load_Anchor is), +X ahead. Inside, the bed is 2.00 m long (x +-1.00),
# 1.14 m wide (y +-0.57), its sides 0.38 m high.

def sack(at, size, yaw=0.0, seed=0, upright=False):
    """A filled sack: a lumpy cushion of sacking (lx long, the neck at its
    +x end, gathered and tied), lying, or stood on end with the neck up."""
    from mathutils import noise
    lx, ly, lz = size
    nu, nv = 8, 6
    rot = Matrix.Rotation(yaw, 4, "Z") @ (Matrix.Rotation(-math.pi / 2, 4, "Y") if upright else Matrix.Identity(4))

    def P(lat, lon):
        cl = math.cos(lat)
        p = Vector((lx / 2 * sp(cl, 0.55) * sp(math.cos(lon), 0.7), ly / 2 * sp(cl, 0.55) * sp(math.sin(lon), 0.7), lz / 2 * sp(math.sin(lat), 0.7)))
        return p * (1.0 + 0.07 * noise.noise(p * 4.0 + Vector((seed, seed * 0.7, 0.3))))

    rings, uvs = [], []
    for i in range(1, nv):
        lat = -math.pi / 2 + math.pi * i / nv
        rings.append([P(lat, 2 * math.pi * j / nu) for j in range(nu)])
        uvs.append([(j / nu * (lx + ly) * 0.7, band_v("ct_sack", i / nv)) for j in range(nu + 1)])
    bot, top = Vector((0, 0, -lz / 2 * 0.92)), Vector((0, 0, lz / 2 * 0.95))
    e = max(rings[len(rings) // 2], key=lambda p: p.x)
    tuft = [[e + Vector((dx, math.cos(a) * r, math.sin(a) * r)) for a in [2 * math.pi * q / 5 for q in range(5)]]
            for dx, r in ((-0.02, 0.05), (0.04, 0.03), (0.08, 0.05))]
    tip = e + Vector((0.1, 0, 0))
    lowest = min((rot @ p).z for p in sum(rings, []) + [bot])
    k = Matrix.Translation(Vector(at) - Vector((0, 0, lowest))) @ rot
    rings = [[k @ p for p in r] for r in rings]
    parts = [skin(rings, uvs, CT, "sack", smooth=70, cap0=(k @ bot, (0.2, band_v("ct_sack", 0.0))), cap1=(k @ top, (0.2, band_v("ct_sack", 1.0))))]
    tuv = [[rect_uv("ct_sack_neck", q / 5, 0.15 + 0.35 * m) for q in range(6)] for m in range(3)]
    parts.append(skin([[k @ p for p in r] for r in tuft], tuv, CT, "sack_neck", smooth=60, cap0="flat",
                      cap1=(k @ tip, rect_uv("ct_sack_neck", 0.5, 0.95))))
    return parts


def bolt(at, length, r, h, colour):
    """A bolt of woven cloth rolled up, lying across the bed (along y)."""
    n = 10
    rings, uvs = [], []
    for k, y in enumerate((-length / 2, length / 2)):
        rings.append([Vector(at) + Vector((r * math.cos(2 * math.pi * j / n), y, h * math.sin(2 * math.pi * j / n))) for j in range(n)])
        uvs.append([rect_uv("ct_cloth_" + colour, k, j / n) for j in range(n + 1)])
    o = skin(rings, uvs, CT, "bolt", smooth=50, cap0="flat", cap1="flat")
    # The ends: the rolled cloth's spiral.
    uvl = o.data.uv_layers["UVMap"].data
    for poly in o.data.polygons:
        if len(poly.vertices) == n:
            for li in poly.loop_indices:
                p = o.data.vertices[o.data.loops[li].vertex_index].co - Vector(at)
                uvl[li].uv = rect_uv("ct_end_" + colour, 0.5 + 0.5 * p.x / r, 0.5 + 0.5 * p.z / h)
    return o


def cask(at, r=0.205, hgt=0.54):
    """A small cask on end: oak staves, four iron hoops."""
    prof = [(r * 0.84, 0.0), (r * 0.96, hgt * 0.24), (r, hgt * 0.5), (r * 0.96, hgt * 0.76), (r * 0.84, hgt)]
    bm = L.lathe(prof, 10, rect="ct_staves")
    L.cap(bm, 0.0, "ct_cask_head", top=False)
    L.cap(bm, hgt, "ct_cask_head", top=True)
    L.transform(bm, Matrix.Translation(at))
    parts = [obj(bm, "cask", CT, smooth=40)]
    for z0, z1 in ((0.025, 0.065), (0.17, 0.2), (hgt - 0.2, hgt - 0.17), (hgt - 0.065, hgt - 0.025)):
        rr = [lerp_rows([(z, rad) for rad, z in prof], z)[0] + 0.006 for z in (z0, z1)]
        hb = L.lathe([(rr[0], z0), (rr[1], z1)], 10, rect="iron_strap")
        L.transform(hb, Matrix.Translation(at))
        parts.append(obj(hb, "hoop", IRON, smooth=40, recalc=False))
    return parts


def iron_bundle(x0, x1, y, rng):
    """A bundle of wrought-iron bars, corded at two places."""
    parts = []
    t = 0.026
    lift = 0.016   # the bars rest on the cords
    rows = [(4, lift + t / 2), (3, lift + t * 1.5), (1, lift + t * 2.5)]
    for count, z in rows:
        for k in range(count):
            yy = y + (k - (count - 1) / 2) * (t + 0.003) + rng.uniform(-0.002, 0.002)
            parts.append(iron_bar((x0 + rng.uniform(0, 0.02), yy, z), (x1 - rng.uniform(0, 0.02), yy, z), t / 2 * 1.2, name="bar"))
    for x in (x0 + 0.12, x1 - 0.12):
        w, hgt = 2 * (t + 0.003) + 0.02, 3 * t + 0.012
        loop = [Vector((x, y + w * math.cos(a), lift + hgt / 2 - 0.008 + hgt / 2 * math.sin(a))) for a in [2 * math.pi * q / 6 for q in range(6)]]
        parts.append(sweep(loop, 0.008, "ct_rope", sides=3, name="cord", mat=CT, closed=True, smooth=50))
    return parts


def cart_load():
    """A trader's load: three sacks at the tail and one stood up at the
    head, three bolts of cloth across the middle, a small cask, a bundle of
    iron bars, roped down across the top to the sides' rails."""
    rng = random.Random(17)
    parts = []
    parts += sack((-0.62, 0.27, 0.0), (0.70, 0.46, 0.30), yaw=0.03, seed=1)
    parts += sack((-0.62, -0.27, 0.0), (0.70, 0.46, 0.30), yaw=-0.05, seed=2)
    parts += sack((-0.60, 0.0, 0.215), (0.78, 0.42, 0.28), yaw=math.pi / 2 + 0.08, seed=3)
    parts += sack((0.60, 0.03, 0.0), (0.46, 0.36, 0.34), yaw=0.4, seed=4, upright=True)
    r, h = 0.105, 0.088
    parts.append(bolt((-0.02, 0.0, h), 0.92, r, h, "blue"))
    parts.append(bolt((-0.02 + 2 * r + 0.004, 0.0, h), 0.92, r, h, "red"))
    parts.append(bolt((-0.02 + r + 0.002, 0.0, h + 2 * h * 0.86), 0.9, r, h, "green"))
    parts += cask((0.72, -0.31, 0.0))
    parts += iron_bundle(0.33, 0.95, 0.33, rng)
    # Ropes over the top from one side's rail to the other.
    for x, prof in ((-0.60, [(0.40, 0.0), (0.45, 0.22), (0.49, 0.36), (0.50, 0.5), (0.49, 0.64), (0.45, 0.78), (0.40, 1.0)]),
                    (0.085, [(0.40, 0.0), (0.315, 0.11), (0.322, 0.3), (0.326, 0.5), (0.322, 0.7), (0.315, 0.89), (0.40, 1.0)])):
        pts = [Vector((x + 0.03 * (f - 0.5), BED_Y - 0.012 - (2 * BED_Y - 0.024) * f, z)) for z, f in prof]
        parts.append(sweep(pts, 0.014, "ct_rope", sides=5, name="rope", mat=CT, smooth=50))
    return [L.join(parts, "SE_Cart_Load")]


BUILDERS = {
    "SE_Cart_Horse": cart_horse,
    "SE_Cart_Load": cart_load,
    "SE_Cart": cart_unhitched,
}


# --- Build, export, review -------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(CT, (1.0, 1.0, 1.0), roughness=0.85, image=CT_TEX)


def tree_of(o):
    out = [o]
    for c in sorted(o.children, key=lambda c: c.name):
        out += tree_of(c)
    return out


def build(only=None):
    """{model name: [its objects, top-level first]}"""
    built = {}
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)  # same source, same GLBs
        objs = fn()
        if not isinstance(objs, list):
            objs = [objs]
        built[name] = objs
    bpy.context.view_layer.update()
    return built


def tris(objs):
    return sum(L.tri_count(o) for o in objs if o.type == "MESH")


def godot(v):
    """Blender (x, y, z) -> Godot (x, y, z)."""
    return (v.x, v.z, -v.y)


def report(name, objs):
    lo = Vector((min((o.matrix_world @ Vector(c))[i] for o in objs if o.type == "MESH" for c in o.bound_box) for i in range(3)))
    hi = Vector((max((o.matrix_world @ Vector(c))[i] for o in objs if o.type == "MESH" for c in o.bound_box) for i in range(3)))
    d = hi - lo
    print("%s: %d tris, %.2f x %.2f x %.2f m" % (name, tris(objs), d.x, d.y, d.z))
    if len(objs) > 1:
        for o in objs:
            path = o.name
            p = o.parent
            while p:
                path = p.name + "/" + path
                p = p.parent
            wp = o.matrix_world.translation
            print("   %-28s %5d tris  pivot (Godot) %+.3f %+.3f %+.3f" % (path, L.tri_count(o) if o.type == "MESH" else 0, *godot(wp)))
        horse = [o for o in objs if o.name == "Horse"]
        if horse:
            print("   the horse and its harness: %d tris" % tris(tree_of(horse[0])))


def export(built):
    models = os.path.join(FAMILY, "models")
    tmp = os.path.join(HERE, "_export_tmp")
    os.makedirs(models, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    for name, objs in built.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        path = os.path.join(tmp, name + ".gltf")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=True,
                                  export_image_format="NONE", export_yup=True, export_texcoords=True, export_normals=True,
                                  export_tangents=False, export_attributes=False, export_extras=False, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=False, export_morph=False)
        glb = os.path.join(models, name + ".glb")
        mats = gltf_pack.pack(path, glb, own=OWN)
        print("exported %s: %d tris, %s, %d bytes" % (name, tris(objs), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def tops(objs):
    return [o for o in objs if o.parent is None]


def save_blend(built, path):
    """Every model side by side in one editable file (then back in place)."""
    moved = []
    for i, (name, objs) in enumerate(built.items()):
        for o in tops(objs):
            moved.append((o, o.location.copy()))
            o.location = o.location + Vector((0, -4.0 * i, 0))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)
    for o, loc in moved:
        o.location = loc
    bpy.context.view_layer.update()


# Test poses for the joints: each leg segment turned 35 degrees about its
# pivot's Y (Blender; negative brings a hoof forward), the neck and head
# nodded, the tail swung aside about X, as the game turns them.
J = math.radians(35)
POSES = {
    "rest": {},
    "a": {"Leg_FL": (0, -J), "Leg_FL_Lower": (0, J), "Leg_FR": (0, J), "Leg_HL": (0, J), "Leg_HL_Lower": (0, -J),
          "Leg_HR": (0, -J), "Neck": (0, 0.1), "Head": (0, -0.25), "Tail": (0.3, 0)},
    "b": {"Leg_FL": (0, J), "Leg_FR": (0, -J), "Leg_FR_Lower": (0, J), "Leg_HL": (0, -J), "Leg_HR": (0, J),
          "Leg_HR_Lower": (0, -J), "Neck": (0, -0.1), "Head": (0, 0.25), "Tail": (-0.3, 0)},
}


def poses(built, out):
    """Renders the horse in its test poses (side on, and low from ahead
    and behind, to look into the joints)."""
    objs = built["SE_Cart_Horse"]
    by = {o.name: o for o in objs}
    for name, oo in built.items():
        for o in oo:
            o.hide_render = name != "SE_Cart_Horse"
    moved = [(o, o.location.copy()) for o in tops(objs)]
    for o, loc in moved:
        o.location = loc - Vector((HX, 0, 0))
    for tag, pose in POSES.items():
        for o in objs:
            o.rotation_euler = (0, 0, 0)
        for n, (rx, ry) in pose.items():
            by[n].rotation_euler = (rx, ry, 0)
        views = [("side", 180, 6, 3.4, 40), ("low_front", -50, 3, 2.4, 45), ("low_rear", 130, 3, 2.4, 45)]
        for p in BC.review(objs, os.path.join(out, "pose_" + tag), views=views, extent=3.4, center_z=0.8):
            print("  ", p)
    for o in objs:
        o.rotation_euler = (0, 0, 0)
    for o, loc in moved:
        o.location = loc


def extent(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def show_only(built, names):
    for name, objs in built.items():
        for o in objs:
            o.hide_render = name not in names


def review(built, out):
    """Cycles views of each model beside a 1.78 m figure; and the load in
    the cart (at Load_Anchor) with the horse."""
    views = [("front34", -35, 16, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 40, 10.0, 50), ("close", -30, 14, 3.4, 42)]
    for name, objs in built.items():
        show_only(built, [name])
        lo, hi = extent(objs)
        d = hi - lo
        moved = [(o, o.location.copy()) for o in tops(objs)]
        for o, loc in moved:
            o.location = loc - Vector(((lo.x + hi.x) / 2, 0, 0))
        h = max(d.z, 0.6)
        ext = max(d.x, d.y, h, 1.4) * 1.1
        for p in BC.review(objs, os.path.join(out, name), views=views, extent=ext, center_z=h * 0.45):
            print("  ", p)
        for o, loc in moved:
            o.location = loc
    if "SE_Cart_Load" in built and "SE_Cart_Horse" in built:
        load, rig = built["SE_Cart_Load"][0], built["SE_Cart_Horse"]
        show_only(built, ["SE_Cart_Load", "SE_Cart_Horse"])
        anchor = [o for o in rig if o.name == "Load_Anchor"][0]
        shift = Vector((anchor.matrix_world.translation.x + 0.9, 0, 0))
        moved = [(o, o.location.copy()) for o in tops(rig) + [load]]
        for o in tops(rig):
            o.location = o.location - shift
        load.location = anchor.matrix_world.translation - shift
        laden = [("laden", -35, 18, 6.0, 40), ("laden_rear", 160, 24, 6.0, 40), ("laden_top", -25, 52, 9.0, 45)]
        for p in BC.review(rig + [load], os.path.join(out, "SE_Cart_Load"), views=laden, extent=4.2, center_z=0.8):
            print("  ", p)
        for o, loc in moved:
            o.location = loc
    show_only(built, list(built))


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    setup()
    built = build(only)
    for name, objs in built.items():
        report(name, objs)
    if "--export" in args:
        export(built)
        if not only:
            save_blend(built, os.path.join(HERE, "carts_transport.blend"))
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        review(built, out)
    if "--poses" in args and "SE_Cart_Horse" in built:
        out = args[args.index("--poses") + 1]
        os.makedirs(out, exist_ok=True)
        poses(built, out)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
