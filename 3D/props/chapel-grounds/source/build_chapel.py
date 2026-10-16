"""Builds the Chapel & Churchyard family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_chapel.py [--review DIR] [--export] [--only A,B]

The chapel's bell and crosses, and the churchyard behind it:
  - kit pieces for the chapel itself: an oak bell frame with its bell in the
    tower's top stage (the openings left open), an iron cross on the tower's
    spire and a stone cross on the east gable;
  - the churchyard: grave mounds in grazed turf, a fresh grave, oak grave
    crosses, stone cross-slab grave covers (one a knight's, with a sword), a
    wheel-head churchyard cross on its steps, a yew, a drystone wall, a coped
    wall with ashlar piers, and a lychgate.
Most medieval graves were unmarked mounds or had a wooden cross that has
long since rotted; the better-off had a stone slab carved with a cross.
Upright headstones only came in after 1600, so there are none here.

Wood, iron, rubble, ashlar and roof tiles are UV-mapped onto the village
kit's trim sheets; turf, fresh earth, the carved slabs, limestone, bell
bronze, yew bark and foliage and the bell rope onto this family's atlas
(T_Chapel_BaseColor.png, paint_chapel.py).

Origin at the ground (a kit piece: at its seat on the building); front =
-Y in Blender (+Z in Godot). A grave's head (west, where its cross
stands) is +Y; its feet (east) are -Y.
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
from mathutils import Matrix, Vector, noise  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402
import build_commons as BC  # noqa: E402  (review renders)

FAMILY = os.path.dirname(HERE)
CH = "MI_Chapel"
CH_TEX = os.path.join(FAMILY, "textures", "T_Chapel_BaseColor.png")
OWN = {
    CH: {"doubleSided": False, "dir": os.path.join(FAMILY, "textures"),
         "pbr": {"baseColorTexture": "T_Chapel_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
}


def _cell(x0, y0, x1, y1):
    """Image pixels (y down) of the 512 atlas -> Blender UV rect (v up)."""
    return (x0 / 512, 1 - y1 / 512, x1 / 512, 1 - y0 / 512)


T = {
    "earth": _cell(4, 132, 252, 252), "bark": _cell(260, 132, 380, 252), "rope": _cell(388, 132, 508, 252),
    "slab": _cell(2, 258, 126, 382), "slab_knight": _cell(130, 258, 254, 382),
    "limestone": _cell(262, 262, 378, 378), "bronze": _cell(390, 262, 506, 378),
}
for _k, _v in T.items():
    L.RECTS["ch_" + _k] = (CH,) + _v
L.BANDS["ch_turf"] = (CH, 1 - 128 / 512 + 0.004, 1 - 0.004)
L.BANDS["ch_yew"] = (CH, 0.004, 128 / 512 - 0.004)


# --- Helpers ---------------------------------------------------------------------------------------

def obj(bm, name, mat, smooth=50, recalc=True):
    return L.to_object(bm, name, mat, smooth_angle=smooth, recalc=recalc)


def uv_box_rect(bm, rect, faces=None, k=None):
    """Box projection into an atlas rect, the same scale on every face
    (metres -> the rect's width; the whole part fits inside it)."""
    uv = bm.loops.layers.uv["UVMap"]
    _, u0, v0, u1, v1 = L.RECTS[rect]
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    k = k or 1.0 / max(1.0, max(hi[i] - lo[i] for i in range(3)))
    for f in (faces or bm.faces):
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for l in f.loops:
            p = l.vert.co
            l[uv].uv = (u0 + (u1 - u0) * min(1.0, (p[a] - lo[a]) * k), v0 + (v1 - v0) * min(1.0, (p[b] - lo[b]) * k))
    return bm


def prism(outline, z0, z1):
    """Extrudes a CCW (x, y) outline from z0 to z1 (a closed solid)."""
    bm = L.new_bm()
    lo = [bm.verts.new((x, y, z0)) for x, y in outline]
    hi = [bm.verts.new((x, y, z1)) for x, y in outline]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
    bm.normal_update()
    return bm


def block(cx, cy, z0, sx, sy, sz):
    """An axis-aligned box from z0 up, centred on (cx, cy)."""
    return prism([(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2), (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)], z0, z0 + sz)


def chamfered(sx, sy, c):
    """A rectangle outline with its corners cut off by c (CCW)."""
    x, y = sx / 2, sy / 2
    return [(-x + c, -y), (x - c, -y), (x, -y + c), (x, y - c), (x - c, y), (-x + c, y), (-x, y - c), (-x, -y + c)]


def taper_top(bm, z_from, k):
    """Scales verts above z_from in x and y by k (a shaft narrowing upward)."""
    zs = [v.co.z for v in bm.verts]
    z1 = max(zs)
    for v in bm.verts:
        if v.co.z > z_from:
            t = (v.co.z - z_from) / max(z1 - z_from, 1e-6)
            s = 1.0 + (k - 1.0) * t
            v.co.x *= s
            v.co.y *= s
    return bm


def ashlar(bm, band="rock_ashlar"):
    L.uv_box_band(bm, list(bm.faces), band, scale=L.UV_PER_M * 0.9, u_off=random.random())
    return bm


def lumpy(bm, amount, scale, seed):
    """Pushes verts in and out along their normals (noise), for clods and foliage."""
    bm.normal_update()
    for v in bm.verts:
        d = noise.noise(v.co * scale + Vector((seed * 1.7, seed * 0.3, seed * 0.9)))
        v.co += v.normal * d * amount
    return bm


def grave_mound_bm(length, width, height, band=None, rect=None, nx=6, ny=12, seed=0, rough=0.012, rim_earth=False):
    """A grave mound: a loaf, highest along its middle, rounded off at both
    ends; its edge sinks just below the ground. UV: turf band (u along the
    grave) or planar into a rect."""
    rng = random.Random(seed)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    grid = []
    for j in range(ny + 1):
        t = j / ny
        row = []
        for i in range(nx + 1):
            s = i / nx
            x = (s - 0.5) * width * (1.0 - 0.18 * abs(2 * t - 1) ** 3)   # ends narrow a little
            y = (t - 0.5) * length
            hx = max(0.0, 1.0 - (2 * s - 1) ** 2) ** 0.55
            hy = max(0.0, 1.0 - abs(2 * t - 1) ** 3.2) ** 0.6
            z = height * hx * hy - 0.03
            if 0 < i < nx and 0 < j < ny:
                z += rng.uniform(-rough, rough)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
            # A turfed grave's rim is the cut edge of the sods: bare earth.
            rim = band and rim_earth and (i in (0, nx - 1) or j in (0, ny - 1))
            for l in f.loops:
                p = l.vert.co
                if band and not rim:
                    _, v0, v1 = L.BANDS[band]
                    l[uv].uv = (p.y * L.UV_PER_M * 1.2 + seed * 0.37, v0 + (v1 - v0) * (0.05 + 0.9 * (p.x / width + 0.5)))
                else:
                    _, u0, v0, u1, v1 = L.RECTS[rect or "ch_earth"]
                    l[uv].uv = (u0 + (u1 - u0) * (p.y / length + 0.5), v0 + (v1 - v0) * (p.x / width + 0.5))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return bm


def clod(center, size, seed, rect="ch_earth"):
    bm = L.new_bm()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5)
    L.transform(bm, Matrix.Diagonal((size[0], size[1], size[2], 1)))
    lumpy(bm, 0.25 * max(size), 3.0, seed)
    L.transform(bm, Matrix.Rotation(seed * 1.3, 4, "Z"))
    L.transform(bm, Matrix.Translation(center))
    bm.normal_update()
    _, u0, v0, u1, v1 = L.RECTS[rect]
    uv = bm.loops.layers.uv["UVMap"]
    rng = random.Random(seed)
    ou, ov = rng.uniform(0.1, 0.8), rng.uniform(0.1, 0.8)
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co - Vector(center)
            l[uv].uv = (u0 + (u1 - u0) * (ou + p.x * 0.3 + p.z * 0.2), v0 + (v1 - v0) * (ov + p.y * 0.3 + p.z * 0.2))
    return bm


def coffin_slab(head_w, foot_w, length, thick, rect, coped=0.025, sunk=0.05):
    """A grave cover shaped like a coffin lid (wider at the head, +Y), its
    top faintly ridged along the middle and chamfered round the edge; the
    carved face is the top, the sides are plain limestone."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    y0, y1 = -length / 2, length / 2
    ch = 0.03
    zb, zt = -sunk, thick - sunk

    def w_at(y, inset=0.0):
        t = (y - y0) / length
        return (foot_w + (head_w - foot_w) * t) / 2 - inset

    rows = []
    for k, y in enumerate([y0, y0 + ch, 0.0, y1 - ch, y1]):
        edge = k in (0, 4)
        inset = ch if edge else 0.0
        z_edge = zt - ch
        row = [
            bm.verts.new((-w_at(y), y, zb)), bm.verts.new((-w_at(y), y, z_edge)),
            bm.verts.new((-w_at(y, ch), y, zt if not edge else zt - ch * 0.4)),
            bm.verts.new((0.0, y, (zt + coped) if not edge else zt)),
            bm.verts.new((w_at(y, ch), y, zt if not edge else zt - ch * 0.4)),
            bm.verts.new((w_at(y), y, z_edge)), bm.verts.new((w_at(y), y, zb)),
        ]
        if edge:   # the chamfer round the ends: pull the top in along y
            sgn = 1 if k == 4 else -1
            for v in row[2:5]:
                v.co.y -= sgn * ch * 0.8
        rows.append(row)
    for k in range(4):
        a, b = rows[k], rows[k + 1]
        for i in range(6):
            bm.faces.new([a[i], b[i], b[i + 1], a[i + 1]])
    for row, rev in ((rows[0], False), (rows[-1], True)):
        bm.faces.new(list(reversed(row)) if not rev else row)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)   # outward first: the top is told by its normal
    bm.normal_update()
    _, u0, v0, u1, v1 = L.RECTS[rect]
    for f in bm.faces:
        top = f.normal.z > 0.6
        for l in f.loops:
            p = l.vert.co
            if top:
                l[uv].uv = (u0 + (u1 - u0) * (p.x / (2 * w_at(p.y) + 1e-6) + 0.5), v0 + (v1 - v0) * ((p.y - y0) / length))
            else:
                _, lu0, lv0, lu1, lv1 = L.RECTS["ch_limestone"]
                a = p.y if abs(f.normal.x) > abs(f.normal.y) else p.x
                l[uv].uv = (lu0 + (lu1 - lu0) * (a / 2.2 + 0.5), lv0 + (lv1 - lv0) * ((p.z - zb) / 0.6 + 0.2))
    return bm


# --- The chapel's own pieces -------------------------------------------------------------------------

TOWER_IN = 1.686   # half the tower's inside (4 m tower, kit walls 0.314 m thick inward)


BELL_PROFILE = [(0.0, 1.99), (0.12, 1.99), (0.19, 1.96), (0.225, 1.88), (0.245, 1.7), (0.29, 1.52), (0.37, 1.39),
                (0.4, 1.32), (0.395, 1.29), (0.35, 1.3), (0.0, 1.33)]   # crown, shoulder, waist, sound bow, lip


def bell_pit(cx, cy, k, inward, rng):
    """One bell in its own oak frame: two A-trestles, the headstock across
    them on iron gudgeons, the bell (scaled by k) hung from it with its
    clapper, and a lever on the headstock with the rope hanging from it
    toward the middle of the tower (`inward`: +1 or -1 in y)."""
    parts = []
    for x in (cx - 0.52, cx + 0.52):
        parts.append(obj(L.beam((x, cy - 0.62, 0.08), (x, cy + 0.62, 0.08), 0.16, 0.15, rng=rng, up=Vector((0, 0, 1))), "sole", "MI_WoodTrim"))
        for sy in (-1, 1):   # raking legs meeting under the gudgeon
            parts.append(obj(L.beam((x, cy + sy * 0.56, 0.14), (x, cy + sy * 0.06, 1.98), 0.14, 0.14, rng=rng, up=Vector((1, 0, 0))), "leg", "MI_WoodTrim"))
        parts.append(obj(L.beam((x, cy - 0.34, 0.95), (x, cy + 0.34, 0.95), 0.1, 0.12, rng=rng, up=Vector((0, 0, 1))), "tie", "MI_WoodTrim"))
        parts.append(obj(L.beam((x, cy - 0.14, 2.03), (x, cy + 0.14, 2.03), 0.17, 0.12, rng=rng, up=Vector((0, 0, 1))), "bearing", "MI_WoodTrim"))
    parts.append(obj(L.beam((cx - 0.62, cy, 2.18), (cx + 0.62, cy, 2.18), 0.22, 0.2, rng=rng), "headstock", "MI_WoodTrim"))
    for x in (cx - 0.5, cx + 0.5):
        parts.append(obj(L.sweep([(x, cy, 2.08), (x, cy, 2.29)], 0.026, sides=6, rect="iron_strap"), "strap", "MI_MetalOrnaments"))
    prof = [(r * k, 2.06 - (2.06 - z) * k) for r, z in BELL_PROFILE]
    bell = L.lathe(prof, 18, rect="ch_bronze")
    L.transform(bell, Matrix.Translation((cx, cy, 0)))
    parts.append(obj(bell, "bell", CH, smooth=60))
    top = 2.06 - (2.06 - 1.99) * k
    lip = 2.06 - (2.06 - 1.33) * k
    parts.append(obj(L.sweep([(cx, cy, top - 0.03), (cx, cy, lip + 0.1)], 0.02, sides=6, rect="iron_bar"), "clapper", "MI_MetalOrnaments"))
    ball = L.new_bm()
    bmesh.ops.create_icosphere(ball, subdivisions=1, radius=0.055)
    L.transform(ball, Matrix.Translation((cx, cy, lip + 0.08)))
    L.uv_box_band(ball, list(ball.faces), "wood_dark")
    parts.append(obj(ball, "clapper_ball", "MI_MetalOrnaments"))
    end = (cx + 0.2, cy + inward * 0.78, 2.5)
    parts.append(obj(L.beam((cx + 0.2, cy, 2.2), end, 0.08, 0.09, rng=rng, up=Vector((1, 0, 0))), "lever", "MI_WoodTrim"))
    parts.append(obj(L.sweep([(end[0], end[1], end[2] - 0.04), (end[0] + 0.01, end[1], 1.2), (end[0] + 0.02, end[1] - inward * 0.01, -0.05)], 0.016, sides=5, rect="ch_rope"), "rope", CH))
    return parts


def belfry():
    """The tower's top stage: a plank floor and two bells, each in its own
    oak frame in opposite corners, so one hangs behind an opening on every
    side of the tower (its walls are the kit's arched windows left open)."""
    rng = random.Random(3)
    parts = []
    n = 9
    pw = 2 * TOWER_IN / n
    for i in range(n):
        x = -TOWER_IN + pw * (i + 0.5)
        parts.append(obj(L.beam((x, -TOWER_IN, -0.04), (x, TOWER_IN, -0.04), pw - 0.01, 0.07, band="wood_light", rng=rng), "floor", "MI_WoodTrim"))
    parts += bell_pit(1.04, -1.04, 1.1, 1, rng)      # the tenor, front right
    parts += bell_pit(-1.04, 1.04, 0.95, -1, rng)    # the treble, back left
    return parts


def cross_tower():
    """A wrought-iron cross on the spire's iron rod: a collar, a square
    shaft, a ring round the crossing, arms ending in balls."""
    parts = []
    # A collar over the spire's own iron rod, then the shaft.
    parts.append(obj(L.sweep([(0, 0, -0.12), (0, 0, 0.06)], 0.07, sides=8, rect="iron_bar"), "collar", "MI_MetalOrnaments", smooth=50))
    parts.append(obj(L.sweep([(0, 0, 0.0), (0, 0, 1.24)], 0.05, sides=4, rect="iron_bar", square=True), "shaft", "MI_MetalOrnaments", smooth=None))
    parts.append(obj(L.sweep([(-0.36, 0, 0.86), (0.36, 0, 0.86)], 0.045, sides=4, rect="iron_bar", square=True), "arms", "MI_MetalOrnaments", smooth=None))
    for p in ((-0.39, 0, 0.86), (0.39, 0, 0.86), (0, 0, 1.28)):
        b = L.new_bm()
        bmesh.ops.create_icosphere(b, subdivisions=1, radius=0.065)
        L.transform(b, Matrix.Translation(p))
        L.uv_box_band(b, list(b.faces), "wood_dark")
        parts.append(obj(b, "tip", "MI_MetalOrnaments", smooth=80))
    ring = [(math.cos(a) * 0.21, 0, 0.86 + math.sin(a) * 0.21) for a in [i * math.tau / 16 for i in range(16)]]
    parts.append(obj(L.sweep(ring, 0.026, sides=4, rect="iron_bar", closed=True), "ring", "MI_MetalOrnaments"))
    return parts


def wheel_cross(span, arm, thick, ring_r, ring_t, z_bottom, z_center, top_up, rect="ch_limestone"):
    """A stone cross with a ring joining its arms, its lower limb rising
    from z_bottom (the top of whatever carries it). Limbs square in
    section, the ring a squared hoop; no faces overlap."""
    parts = []
    bms = []
    bms.append(block(0, 0, z_bottom, arm, thick, z_center - arm / 2 - z_bottom))             # lower limb
    bms.append(block(0, 0, z_center - arm / 2, span, thick, arm))                            # arms
    bms.append(block(0, 0, z_center + arm / 2, arm, thick, top_up - arm / 2))                # top limb
    ring_pts = [(math.cos(a) * ring_r, 0, z_center + math.sin(a) * ring_r) for a in [i * math.tau / 16 for i in range(16)]]
    ring = L.sweep(ring_pts, ring_t, sides=4, closed=True, rect=rect, square=True)
    L.transform(ring, Matrix.Translation((0, 0, 0)))
    for b in bms:
        uv_box_rect(b, rect)
        parts.append(obj(b, "cross", CH, smooth=None))
    uv_box_rect(ring, rect, k=0.9)
    parts.append(obj(ring, "ring", CH, smooth=40))
    return parts


def cross_gable():
    """A stone ringed cross on the east gable: a saddle stone notched over
    the ridge, a short neck, the cross."""
    parts = []
    saddle = prism([(-0.17, -0.2), (0.17, -0.2), (0.17, 0.2), (-0.17, 0.2)], -0.12, 0.2)
    for v in saddle.verts:   # notch: the underside rides the ridge tiles
        if v.co.z < 0:
            v.co.z = -0.12 + abs(v.co.x) * 0.4
    uv_box_rect(saddle, "ch_limestone")
    parts.append(obj(saddle, "saddle", CH, smooth=None))
    neck = block(0, 0, 0.2, 0.14, 0.12, 0.28)
    uv_box_rect(neck, "ch_limestone")
    parts.append(obj(neck, "neck", CH, smooth=None))
    parts += wheel_cross(0.62, 0.13, 0.11, 0.2, 0.035, 0.48, 0.74, 0.24)
    return parts


# --- The churchyard ---------------------------------------------------------------------------------

def grave_mound():
    """A grave grassed over: a low loaf of turf."""
    return [obj(grave_mound_bm(1.95, 0.84, 0.25, band="ch_turf", seed=1, nx=8, ny=14, rim_earth=True), "mound", CH, smooth=60, recalc=False)]


def grave_fresh():
    """A new grave: a heap of dug earth, clods tumbling off it."""
    rng = random.Random(5)
    parts = [obj(grave_mound_bm(2.0, 0.92, 0.3, rect="ch_earth", seed=2, rough=0.03, nx=7, ny=12), "heap", CH, smooth=40, recalc=False)]
    for i in range(7):
        side = -1 if i % 2 else 1
        x = side * rng.uniform(0.32, 0.5)
        y = rng.uniform(-0.85, 0.85)
        s = rng.uniform(0.09, 0.15)
        z = max(0.0, 0.3 * (1 - (abs(x) / 0.46) ** 2)) - 0.02
        parts.append(obj(clod((x, y, z), (s * 1.3, s, s * 0.8), 10 + i), "clod", CH, smooth=30))
    return parts


def grave_cross():
    """An oak grave cross, a little weathered and leaning."""
    rng = random.Random(7)
    up = L.beam((0, 0, -0.2), (0, 0, 1.0), 0.075, 0.06, band="wood_dark", rng=rng, up=Vector((1, 0, 0)))
    arm = L.beam((-0.25, -0.005, 0.72), (0.25, -0.005, 0.72), 0.066, 0.06, band="wood_dark", rng=rng)
    cap = L.beam((0, 0.0, 1.0), (0, 0.0, 1.04), 0.11, 0.09, band="wood_dark", rng=rng, up=Vector((1, 0, 0)))
    parts = [obj(up, "upright", "MI_WoodTrim"), obj(arm, "arm", "MI_WoodTrim"), obj(cap, "cap", "MI_WoodTrim")]
    lean = Matrix.Rotation(math.radians(3.5), 4, "X") @ Matrix.Rotation(math.radians(-2.0), 4, "Y")
    for p in parts:
        p.data.transform(lean)
    return parts


def grave_slab():
    """A coffin-lid cover with a ringed cross on a stepped base."""
    return [obj(coffin_slab(0.66, 0.48, 1.9, 0.16, "ch_slab"), "slab", CH, smooth=None)]


def grave_slab_knight():
    """A knight's slab: the same ringed cross, his sword beside it."""
    return [obj(coffin_slab(0.74, 0.52, 2.0, 0.18, "ch_slab_knight"), "slab", CH, smooth=None)]


def churchyard_cross():
    """A wheel-head churchyard cross: two square steps, a socket stone with
    its corners broached, a square shaft with chamfered arrises narrowing
    upward, a ringed head."""
    parts = []
    for z0, s, h in ((0.0, 1.7, 0.24), (0.24, 1.18, 0.24)):
        st = block(0, 0, z0 - (0.06 if z0 == 0 else 0.0), s, s, h + (0.06 if z0 == 0 else 0.0))
        ashlar(st)
        parts.append(obj(st, "step", "MI_RockTrim", smooth=None))
    sock = prism(chamfered(0.66, 0.66, 0.0), 0.48, 0.86)
    top = [v for v in sock.verts if v.co.z > 0.8]
    for v in top:   # broach: the top is cut to an octagon
        v.co.x *= 0.88
        v.co.y *= 0.88
    uv_box_rect(sock, "ch_limestone")
    parts.append(obj(sock, "socket", CH, smooth=None))
    shaft = prism(chamfered(0.26, 0.26, 0.045), 0.86, 3.08)
    taper_top(shaft, 0.86, 0.78)
    uv_box_rect(shaft, "ch_limestone")
    parts.append(obj(shaft, "shaft", CH, smooth=None))
    parts += wheel_cross(0.8, 0.19, 0.16, 0.27, 0.045, 3.08, 3.26, 0.26)
    return parts


def yew():
    """A churchyard yew: a short, massive, fluted red-brown trunk and a dark,
    dense crown of many lumpy masses, broad and low, its lowest boughs
    sweeping down almost to the ground."""
    parts = []
    prof = [(0.72, -0.1), (0.6, 0.12), (0.5, 0.45), (0.46, 0.9), (0.4, 1.4), (0.0, 1.8)]
    trunk = L.lathe(prof, 12, rect="ch_bark")
    for v in trunk.verts:   # fluting: ridges and hollows running up the trunk
        a = math.atan2(v.co.y, v.co.x)
        k = 1.0 + 0.16 * math.sin(5 * a + v.co.z * 0.7) + 0.06 * math.sin(11 * a)
        v.co.x *= k
        v.co.y *= k
    parts.append(obj(trunk, "trunk", CH, smooth=70))
    rng = random.Random(11)
    # A broad dome: one big middle mass, a ring of low boughs round it and a
    # few on top, each squashed a little underneath.
    masses = [((0.0, 0.0, 2.5), (1.75, 1.75, 1.6))]
    for i in range(6):
        a = i * math.tau / 6 + 0.3
        r = rng.uniform(1.35, 1.6)
        masses.append(((math.cos(a) * r, math.sin(a) * r, rng.uniform(1.3, 1.6)), (rng.uniform(0.95, 1.1), rng.uniform(0.9, 1.05), rng.uniform(0.8, 0.92))))
    for i in range(2):
        a = i * math.pi + 1.1
        masses.append(((math.cos(a) * 0.75, math.sin(a) * 0.75, 3.55 + rng.uniform(-0.1, 0.2)), (1.0, 0.95, 0.85)))
    _, v0, v1 = L.BANDS["ch_yew"]
    for k, (c, s_) in enumerate(masses):
        bm = L.new_bm()
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
        L.transform(bm, Matrix.Diagonal((s_[0], s_[1], s_[2], 1)))
        lumpy(bm, 0.18, 1.8, 20 + k)
        for v in bm.verts:   # flatter underneath, the way boughs hang
            if v.co.z < -0.35 * s_[2]:
                v.co.z = -0.35 * s_[2] + (v.co.z + 0.35 * s_[2]) * 0.5
        L.transform(bm, Matrix.Translation(c))
        bm.normal_update()
        uv = bm.loops.layers.uv["UVMap"]
        zlo, zhi = c[2] - s_[2], c[2] + s_[2]
        ou = rng.uniform(0, 1)
        for f in bm.faces:
            n = f.normal
            for l in f.loops:
                p = l.vert.co
                if abs(n.z) > 0.7:
                    u, t = p.x * 0.35, (p.y - c[1]) / (2 * s_[1]) + 0.5
                else:
                    u = (p.x if abs(n.y) > abs(n.x) else p.y) * 0.35
                    t = (p.z - zlo) / (zhi - zlo)
                l[uv].uv = (ou + u, v0 + (v1 - v0) * max(0.0, min(1.0, t)))
        parts.append(obj(bm, "crown", CH, smooth=80))
    return parts


def wall_rubble():
    """2 m of drystone churchyard wall: a battered rubble body with a row of
    rough coping stones set on edge along its top."""
    rng = random.Random(13)
    body = prism([(-1.0, -0.3), (1.0, -0.3), (1.0, 0.3), (-1.0, 0.3)], -0.05, 0.78)
    for v in body.verts:   # battered: narrower at the top
        if v.co.z > 0.5:
            v.co.y *= 0.72
    L.uv_box_band(body, list(body.faces), "rock_cobble", scale=L.UV_PER_M * 0.8, u_off=0.3)
    parts = [obj(body, "body", "MI_RockTrim", smooth=None)]
    x = -1.0
    i = 0
    while x < 0.98:
        w = min(rng.uniform(0.17, 0.26), 1.0 - x)
        h = rng.uniform(0.15, 0.22)
        st = block(x + w / 2, rng.uniform(-0.02, 0.02), 0.76, w - 0.015, rng.uniform(0.34, 0.42), h)
        for v in st.verts:   # rough tops
            if v.co.z > 0.8:
                v.co.z += rng.uniform(-0.04, 0.02)
        L.uv_box_band(st, list(st.faces), "rock_cobble", scale=L.UV_PER_M * 0.8, u_off=rng.uniform(0, 1))
        parts.append(obj(st, "coping", "MI_RockTrim", smooth=None))
        x += w
        i += 1
    return parts


def wall_coped():
    """2 m of mortared churchyard wall: a plinth, a squared body and a
    saddleback coping that sheds the rain both ways."""
    plinth = block(0, 0, -0.05, 2.0, 0.54, 0.27)
    body = block(0, 0, 0.22, 2.0, 0.44, 0.74)
    cope = prism([(-1.0, -0.27), (1.0, -0.27), (1.0, 0.27), (-1.0, 0.27)], 0.96, 1.04)
    ridge = prism([(-1.0, -0.27), (1.0, -0.27), (1.0, 0.27), (-1.0, 0.27)], 1.04, 1.04 + 0.12)
    for v in ridge.verts:   # the saddleback: top edges pulled to a ridge
        if v.co.z > 1.1:
            v.co.y *= 0.08
    parts = []
    for bm, band, name in ((plinth, "rock_ashlar", "plinth"), (body, "rock_ashlar", "body"), (cope, "rock_slate", "cope"), (ridge, "rock_slate", "ridge")):
        L.uv_box_band(bm, list(bm.faces), band, scale=L.UV_PER_M * 0.9, u_off=0.2)
        parts.append(obj(bm, name, "MI_RockTrim", smooth=None))
    return parts


def wall_pier():
    """An ashlar pier where a churchyard wall turns or ends: a plinth, the
    shaft and a pyramid cap with a ball on it."""
    parts = []
    for bm, band in ((block(0, 0, -0.05, 0.7, 0.7, 0.3), "rock_ashlar"), (block(0, 0, 0.25, 0.6, 0.6, 1.02), "rock_ashlar")):
        L.uv_box_band(bm, list(bm.faces), band, scale=L.UV_PER_M * 0.9, u_off=0.6)
        parts.append(obj(bm, "pier", "MI_RockTrim", smooth=None))
    cap = prism([(-0.36, -0.36), (0.36, -0.36), (0.36, 0.36), (-0.36, 0.36)], 1.27, 1.37)
    top = prism([(-0.36, -0.36), (0.36, -0.36), (0.36, 0.36), (-0.36, 0.36)], 1.37, 1.6)
    for v in top.verts:
        if v.co.z > 1.5:
            v.co.x *= 0.15
            v.co.y *= 0.15
    for bm in (cap, top):
        uv_box_rect(bm, "ch_limestone")
        parts.append(obj(bm, "cap", CH, smooth=None))
    ball = L.new_bm()
    bmesh.ops.create_icosphere(ball, subdivisions=1, radius=0.09)
    L.transform(ball, Matrix.Translation((0, 0, 1.64)))
    uv_box_rect(ball, "ch_limestone")
    parts.append(obj(ball, "ball", CH, smooth=80))
    return parts


def lychgate():
    """A lychgate: a tiled roof on four oak posts over the churchyard's
    gateway, where a bier waited out of the rain for the priest. Paved
    underfoot, arch-braced, a pair of boarded gates on its outer side
    standing open. Passage along Y; the outside is -Y."""
    rng = random.Random(17)
    parts = []
    px, py = 0.95, 1.0
    flag = block(0, 0, -0.04, 2.1, 2.3, 0.07)
    L.uv_box_band(flag, list(flag.faces), "rock_slate", scale=L.UV_PER_M * 0.9)
    parts.append(obj(flag, "flags", "MI_RockTrim", smooth=None))
    for x in (-px, px):
        for y in (-py, py):
            pad = block(x, y, -0.05, 0.3, 0.3, 0.2)
            ashlar(pad)
            parts.append(obj(pad, "pad", "MI_RockTrim", smooth=None))
            parts.append(obj(L.beam((x, y, 0.15), (x, y, 2.2), 0.17, 0.17, rng=rng, up=Vector((1, 0, 0))), "post", "MI_WoodTrim"))
        # Tie beam across the passage on each side, arch braces up to it.
        parts.append(obj(L.beam((x, -py - 0.12, 2.29), (x, py + 0.12, 2.29), 0.17, 0.18, rng=rng), "tie", "MI_WoodTrim"))
        for y in (-py, py):
            parts.append(obj(L.beam((x, y, 1.6), (x, y * 0.45, 2.22), 0.1, 0.1, rng=rng, up=Vector((1, 0, 0))), "brace", "MI_WoodTrim"))
    # Wall plates along X carrying the rafters, their ends past the posts.
    for y in (-py, py):
        parts.append(obj(L.beam((-1.32, y, 2.36), (1.32, y, 2.36), 0.15, 0.13, rng=rng), "plate", "MI_WoodTrim"))
    # Roof: ridge along X, the slopes coming down over the way in and out.
    ridge_z, eave_z, eave_y, rx = 3.42, 2.24, py + 0.48, 1.45
    for sgn in (-1, 1):
        parts.append(obj(L.tile_slab((-rx, sgn * eave_y, eave_z), (rx, sgn * eave_y, eave_z), (-rx, 0.0, ridge_z + 0.02))
                         if sgn < 0 else
                         L.tile_slab((rx, sgn * eave_y, eave_z), (-rx, sgn * eave_y, eave_z), (rx, 0.0, ridge_z + 0.02)), "roof", "MI_RoundTiles", smooth=None))
    parts.append(obj(L.sweep([(-rx - 0.02, 0, ridge_z + 0.04), (rx + 0.02, 0, ridge_z + 0.04)], 0.09, sides=8, rect="end_grain"), "ridge", "MI_RoundTiles", smooth=50))
    rd = parts[-1].data
    for poly in rd.polygons:
        pass
    # Gable trusses: a collar and king post on each tie, barge boards.
    slope = (ridge_z - eave_z) / eave_y
    for x in (-1.25, 1.25):
        parts.append(obj(L.beam((x, 0, 2.36), (x, 0, ridge_z - 0.05), 0.12, 0.12, rng=rng, up=Vector((1, 0, 0))), "king", "MI_WoodTrim"))
        for sgn in (-1, 1):
            parts.append(obj(L.beam((x, sgn * 0.62, 2.36), (x, sgn * 0.12, ridge_z - 0.3), 0.09, 0.1, rng=rng, up=Vector((1, 0, 0))), "strut", "MI_WoodTrim"))
    # Barge boards just outside the tiles' gable edges, tucked under them.
    for x in (-rx - 0.035, rx + 0.035):
        for sgn in (-1, 1):
            y0 = sgn * (eave_y + 0.02)
            parts.append(obj(L.beam((x, y0, eave_z - 0.1), (x, 0, ridge_z - 0.06), 0.05, 0.2, rng=rng, up=Vector((0, -sgn, slope)).normalized()), "barge", "MI_WoodTrim"))
    # The gates, hung on the outer posts and standing open inward.
    for sx in (-1, 1):
        hinge = Vector((sx * (px - 0.1), -py, 0.0))
        ang = -sx * math.radians(68)
        rot = Matrix.Translation(hinge) @ Matrix.Rotation(ang, 4, "Z")
        leaf = []
        w = 0.82
        for k in range(5):
            x0 = -sx * (0.04 + k * w / 5)
            leaf.append(L.beam((x0 - sx * w / 10, 0, 0.12), (x0 - sx * w / 10, 0, 1.12 - 0.03 * k), w / 5 - 0.012, 0.035, band="wood_light", rng=rng, up=Vector((0, 1, 0))))
        for z in (0.3, 0.95):
            leaf.append(L.beam((-sx * 0.02, 0.04, z), (-sx * (w - 0.02), 0.04, z), 0.1, 0.045, band="wood_dark", rng=rng))
        leaf.append(L.beam((-sx * 0.04, 0.045, 0.32), (-sx * (w - 0.06), 0.045, 0.93), 0.09, 0.04, band="wood_dark", rng=rng))
        for bm in leaf:
            L.transform(bm, rot)
            parts.append(obj(bm, "gate", "MI_WoodTrim"))
    return parts


BUILDERS = {
    "SE_Belfry": belfry,
    "SE_Cross_Tower": cross_tower,
    "SE_Cross_Gable": cross_gable,
    "SE_Grave_Mound": grave_mound,
    "SE_Grave_Fresh": grave_fresh,
    "SE_Grave_Cross": grave_cross,
    "SE_Grave_Slab": grave_slab,
    "SE_Grave_Slab_Knight": grave_slab_knight,
    "SE_Churchyard_Cross": churchyard_cross,
    "SE_Yew": yew,
    "SE_Wall_Rubble": wall_rubble,
    "SE_Wall_Coped": wall_coped,
    "SE_Wall_Pier": wall_pier,
    "SE_Lychgate": lychgate,
}


# --- Build, export, review -------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(CH, (1.0, 1.0, 1.0), roughness=0.85, image=CH_TEX)


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)  # same source, same GLBs
        objs = fn()
        for o in objs:   # bake placements made with matrix_world
            if o.matrix_world != Matrix.Identity(4):
                o.data.transform(o.matrix_world)
                o.matrix_world = Matrix.Identity(4)
        obj_ = L.join(objs, name)
        uvs = obj_.data.uv_layers
        uvs.active = uvs["UVMap"]
        uvs["UVMap"].active_render = True
        if "Sway" in uvs:
            uvs.remove(uvs["Sway"])
        built.append(obj_)
    return built


def export(objs):
    models = os.path.join(FAMILY, "models")
    tmp = os.path.join(HERE, "_export_tmp")
    os.makedirs(models, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    for o in objs:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        loc = o.location.copy()
        o.location = (0, 0, 0)
        path = os.path.join(tmp, o.name + ".gltf")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=True,
                                  export_image_format="NONE", export_yup=True, export_texcoords=True, export_normals=True,
                                  export_tangents=False, export_attributes=False, export_extras=False, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=False, export_morph=False)
        glb = os.path.join(models, o.name + ".glb")
        mats = gltf_pack.pack(path, glb, own=OWN)
        o.location = loc
        print("exported %s: %d tris, %s, %d bytes" % (o.name, L.tri_count(o), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def save_blend(objs, path):
    for o in [o for o in bpy.data.objects if o.name.startswith("_")]:
        bpy.data.objects.remove(o)
    for i, o in enumerate(objs):
        o.hide_render = False
        o.location = ((i % 5) * 7.0, (i // 5) * 7.0, 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    setup()
    built = build(only)
    for o in built:
        print("%s: %d tris, %.2f x %.2f x %.2f m" % (o.name, L.tri_count(o), *o.dimensions))
    if "--export" in args:
        export(built)
        if not only:
            save_blend(built, os.path.join(HERE, "chapel_grounds.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for o in built:
            for other in built:
                other.hide_render = other is not o
                other.location = (0, 0, 0)
            h = max(o.dimensions.z, 0.6)
            ext = max(o.dimensions.x, o.dimensions.y, h, 1.4) * 1.1
            views = [("front34", -35, 16, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 40, 10.0, 50), ("close", -30, 14, 3.4, 42)]
            for p in BC.review([o], os.path.join(out, o.name), views=views, extent=ext, center_z=h * 0.45):
                print("  ", p)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
