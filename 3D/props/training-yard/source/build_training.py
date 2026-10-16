"""Builds the Training Yard family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_training.py [--review DIR] [--export] [--only A,B]

Where a village's men muster and a town's guard trains, behind the
barracks: practice posts (pells) hacked by blades, straw dummies on a
crossbar, a quintain with a shield on one end of its arm and a sandbag on
the other, turf archery butts with a white linen clout pegged on their
face and arrows stuck round it, racks of staves and of weapons, and a
sparring ring of stakes and rope or of posts and rails.

Wood, iron and stone are UV-mapped onto the village kit's trim sheets,
straw and sacking onto the Farm & Field atlas, the painted shields, turf,
trodden earth, the clout, fletching and rope onto this family's small
atlas (T_Training_BaseColor.png, paint_training.py).

Origin at the ground; front = -Y in Blender (+Z in Godot): a dummy faces
-Y, so a soldier drilling at it stands on -Y.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "village-commons", "source")
FARM_SRC = os.path.join(HERE, "..", "..", "farm-field", "source")

# Same source, same GLBs: see build_farm.py.
if os.environ.get("PYTHONHASHSEED") != "0":
    os.environ["PYTHONHASHSEED"] = "0"
    os.execv(sys.executable, [sys.executable] + sys.argv)

sys.path.insert(0, COMMONS_SRC)
sys.path.insert(0, FARM_SRC)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402
import build_commons as BC  # noqa: E402  (review renders)
import build_farm as BF  # noqa: E402  (the farm atlas: straw, sacking)

FAMILY = os.path.dirname(HERE)
TRAIN = "MI_Training"
TRAIN_TEX = os.path.join(FAMILY, "textures", "T_Training_BaseColor.png")
OWN = {
    TRAIN: {"doubleSided": True, "dir": os.path.join(FAMILY, "textures"),
            "pbr": {"baseColorTexture": "T_Training_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
}
OWN.update(BF.OWN)  # MI_Farm


def _cell(x0, y0, x1, y1):
    """Image pixels (y down) of the 512 atlas -> Blender UV rect (v up)."""
    return (x0 / 512, 1 - y1 / 512, x1 / 512, 1 - y0 / 512)


T = {
    "shield_quarterly": _cell(4, 4, 124, 124), "shield_chevron": _cell(132, 4, 252, 124),
    "shield_cross": _cell(260, 4, 380, 124), "shield_battered": _cell(388, 4, 508, 124),
    "clout": _cell(4, 388, 124, 508), "fletching": _cell(132, 388, 252, 508),
    "rope": _cell(260, 388, 380, 508), "end_grain": _cell(388, 388, 508, 508),
}
for _k, _v in T.items():
    L.RECTS["tr_" + _k] = (TRAIN,) + _v
L.BANDS["turf"] = (TRAIN, 1 - 256 / 512 + 0.004, 1 - 128 / 512 - 0.004)
L.BANDS["earth"] = (TRAIN, 1 - 384 / 512 + 0.004, 1 - 256 / 512 - 0.004)


# --- Helpers ---------------------------------------------------------------------------------------

def obj(bm, name, mat, smooth=50, recalc=True):
    return L.to_object(bm, name, mat, smooth_angle=smooth, recalc=recalc)


def rect_planar(bm, rect, a=0, b=1, lo=None, hi=None):
    """Planar UVs over axes a, b of the part's bounds into a rect (u0, v0, u1, v1)."""
    uv = bm.loops.layers.uv["UVMap"]
    lo = lo or [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = hi or [max(v.co[i] for v in bm.verts) for i in range(3)]
    u0, v0, u1, v1 = rect
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            s = (p[a] - lo[a]) / max(hi[a] - lo[a], 1e-6)
            t = (p[b] - lo[b]) / max(hi[b] - lo[b], 1e-6)
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    return bm


def ground_patch(rx, ry, seed, band="earth", segs=20, rough=0.14, z=0.012, center=(0, 0)):
    """Trodden ground: a flat ragged disc just above the grass (planar UV in a band)."""
    rng = random.Random(seed)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    c = bm.verts.new((center[0], center[1], z))
    ring = []
    for i in range(segs):
        a = math.tau * i / segs
        k = 1.0 + rng.uniform(-rough, rough)
        ring.append(bm.verts.new((center[0] + math.cos(a) * rx * k, center[1] + math.sin(a) * ry * k, z - 0.004)))
    _, v0, v1 = L.BANDS[band]
    for i in range(segs):
        f = bm.faces.new([c, ring[i], ring[(i + 1) % segs]])
        for l in f.loops:
            p = l.vert.co
            dy = (p.y - center[1]) / (max(rx, ry) * (1 + rough))
            l[uv].uv = (p.x * L.UV_PER_M * 0.6 + 0.3, v0 + (v1 - v0) * (0.5 + 0.48 * max(-1.0, min(1.0, dy))))
    return bm


def rope_ring(center_z, r, thick=0.018, sides=5, segs=12, x=0.0, y=0.0):
    pts = [(x + math.cos(math.tau * i / segs) * r, y + math.sin(math.tau * i / segs) * r, center_z) for i in range(segs)]
    return L.sweep(pts, thick, sides=sides, rect="tr_rope", closed=True)


def heater_outline(w, h, n=6):
    """A heater shield's outline in its own XZ plane (CCW seen from -Y),
    top edge straight, sides curving to a point."""
    pts = [(-w / 2, h / 2), (w / 2, h / 2)]
    for i in range(1, n + 1):
        t = i / n
        x = w / 2 * math.cos(t * math.pi / 2) ** 0.8
        z = h / 2 - h * (0.35 + 0.65 * math.sin(t * math.pi / 2))
        pts.append((x, z))
    for i in range(n - 1, 0, -1):
        x, z = pts[1 + i]
        pts.append((-x, z))
    return pts


def round_outline(r, n=14):
    return [(math.cos(math.tau * i / n) * r, math.sin(math.tau * i / n) * r) for i in range(n)]


def shield(outline, rect, thick=0.03, boss=False):
    """A flat shield cut to `outline` (XZ, facing -Y), its face painted from
    the atlas, the back and rim plain wood."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    front = [bm.verts.new((x, -thick / 2, z)) for x, z in outline]
    back = [bm.verts.new((x, thick / 2, z)) for x, z in outline]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    n = len(outline)
    for i in range(n):
        faces.append(bm.faces.new([front[(i + 1) % n], front[i], back[i], back[(i + 1) % n]]))
    xs = [p[0] for p in outline]
    zs = [p[1] for p in outline]
    u0, v0, u1, v1 = T[rect]
    eu0, ev0, eu1, ev1 = T["end_grain"]   # the back and rim: plain oak
    for k, f in enumerate(faces):
        for l in f.loops:
            p = l.vert.co
            s = (p.x - min(xs)) / (max(xs) - min(xs))
            t = (p.z - min(zs)) / (max(zs) - min(zs))
            if k == 0:
                l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
            else:
                l[uv].uv = (eu0 + (eu1 - eu0) * s, ev0 + (ev1 - ev0) * t)
    parts = [obj(bm, "shield", TRAIN, smooth=None, recalc=False)]
    if boss:
        b = L.lathe([(0.0, 0.0), (0.07, 0.0), (0.06, 0.03), (0.03, 0.05), (0.0, 0.055)], 10, rect="iron_plate")
        L.transform(b, Matrix.Translation((0, -thick / 2, 0)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        parts.append(obj(b, "boss", "MI_MetalOrnaments", smooth=60))
    return parts


def waster(at, lean_to, rng, length=0.92):
    """A wooden practice sword: blade, crossguard, grip and pommel, from its
    pommel `at` toward `lean_to`."""
    a, b = Vector(at), Vector(lean_to)
    d = (b - a).normalized()
    parts = []
    grip_end = a + d * 0.2
    parts.append(L.beam(a, grip_end, 0.035, 0.03, band="wood_dark", rng=rng))
    guard_c = grip_end
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    parts.append(L.beam(guard_c - side * 0.11, guard_c + side * 0.11, 0.04, 0.03, band="wood_dark", rng=rng))
    tip = grip_end + d * (length - 0.2)
    parts.append(L.beam(grip_end, tip, 0.055, 0.022, band="wood_light", rng=rng))
    pommel = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.035, 0.025), (0.0, 0.05)], 6, band="wood_dark")
    L.transform(pommel, Matrix.Translation(a - d * 0.03))
    parts.append(pommel)
    return [obj(p, "waster", "MI_WoodTrim", smooth=None) for p in parts]


def arrow(tail, head, rng):
    """An arrow from its nock `tail` to `head` (buried): ash shaft, grey goose fletching."""
    a, b = Vector(tail), Vector(head)
    d = (b - a).normalized()
    parts = [obj(L.sweep([a, b], 0.0055, sides=4, band="wood_light"), "shaft", "MI_WoodTrim", smooth=None, recalc=False)]
    fl = L.new_bm()
    uv = fl.loops.layers.uv["UVMap"]
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    u0, v0, u1, v1 = T["fletching"]
    for axis in (side, up):
        p0 = a + d * 0.02
        p1 = a + d * 0.17
        q = [p0, p1, p1 + axis * 0.035, p0 + axis * 0.045]
        vs = [fl.verts.new(v) for v in q]
        f = fl.faces.new(vs)
        for l, (s, t) in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
        q2 = [p0, p1, p1 - axis * 0.035, p0 - axis * 0.045]
        vs = [fl.verts.new(v) for v in q2]
        f = fl.faces.new(list(reversed(vs)))
        for l, (s, t) in zip(f.loops, [(0, 1), (1, 1), (1, 0), (0, 0)]):
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    parts.append(obj(fl, "fletching", TRAIN, smooth=None, recalc=False))
    return parts


def straw_tufts(at, out, rng, n=6, r=0.05):
    tuft = L.new_bm()
    for k in range(n):
        a = k * math.tau / n
        o = Vector(out).normalized()
        side = o.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(o).normalized()
        base = Vector(at) + (side * math.cos(a) + up * math.sin(a)) * r
        tip = base + o * rng.uniform(0.09, 0.15) + (side * math.cos(a) + up * math.sin(a)) * 0.06 - Vector((0, 0, 0.04))
        f = tuft.verts.new(base + Vector((0, 0, 0.02)))
        g = tuft.verts.new(base - Vector((0, 0, 0.02)))
        h = tuft.verts.new(tip)
        tuft.faces.new([f, g, h])
    BF.rect_uv(tuft, tuft.faces, "straw", lambda l: (0.3, 0.6))
    return obj(tuft, "straw", BF.FARM, smooth=60, recalc=False)


# --- Models ----------------------------------------------------------------------------------------

def pell():
    """A practice post (pell): a knotted oak trunk about a man's height,
    hacked where the blades bite, a rope round it, the ground trodden bare."""
    rng = random.Random("pell")
    parts = [obj(L.log((0, 0, -0.15), (0.02, 0.01, 1.74), 0.12, sides=9, band="wood_dark", taper=0.86, jitter=0.16, seed=11,
                       end_rect="end_grain_pale", rings=6), "trunk", "MI_WoodTrim", smooth=50)]
    for z, a in ((0.62, 0.4), (1.3, 2.6)):   # branch stubs, sawn off
        p0 = Vector((math.cos(a) * 0.09, math.sin(a) * 0.09, z))
        p1 = p0 + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0.07))
        parts.append(obj(L.log(p0, p1, 0.045, sides=6, band="wood_dark", taper=0.8, jitter=0.1, seed=int(z * 100), end_rect="end_grain_pale", rings=2),
                         "stub", "MI_WoodTrim", smooth=50))
    # Fresh cuts on the front (-Y), where the blades bite: pale wood showing.
    u0, v0, u1, v1 = T["end_grain"]
    cuts = L.new_bm()
    uv = cuts.loops.layers.uv["UVMap"]
    for i in range(7):
        z = rng.uniform(0.85, 1.55)
        a = math.radians(rng.uniform(-150, -30))
        r = 0.112 - 0.012 * (z - 0.8)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        tang = Vector((-math.sin(a), math.cos(a), 0))
        tilt = rng.uniform(-0.5, 0.5)
        half = 0.045
        p0 = Vector((cx, cy, z)) - tang * half + Vector((0, 0, -tilt * half))
        p1 = Vector((cx, cy, z)) + tang * half + Vector((0, 0, tilt * half))
        n = Vector((math.cos(a), math.sin(a), 0)) * 0.004
        q = [p0 + n, p1 + n, p1 + n + Vector((0, 0, 0.012)), p0 + n + Vector((0, 0, 0.012))]
        f = cuts.faces.new([cuts.verts.new(v) for v in q])
        for l, (s, t) in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            l[uv].uv = (u0 + (u1 - u0) * (0.2 + 0.6 * s), v0 + (v1 - v0) * (0.45 + 0.1 * t))
    parts.append(obj(cuts, "cuts", TRAIN, smooth=None, recalc=False))
    parts.append(obj(rope_ring(1.62, 0.108, segs=10), "rope", TRAIN, smooth=60, recalc=False))
    parts.append(obj(rope_ring(1.58, 0.11, segs=10), "rope", TRAIN, smooth=60, recalc=False))
    parts.append(obj(ground_patch(0.75, 0.9, 3, center=(0, -0.2)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def dummy_straw():
    """A straw dummy: a post and crossbar, a body of straw bound with rope, a
    sacking head under a dented pot of a helmet, a battered shield on its arm."""
    rng = random.Random("dummy")
    parts = [obj(L.log((0, 0, -0.1), (0.0, 0.01, 1.92), 0.06, sides=6, band="wood_dark", taper=0.9, jitter=0.08, seed=21, rings=3),
                 "post", "MI_WoodTrim", smooth=55)]
    parts.append(obj(L.log((-0.6, 0.0, 1.42), (0.6, 0.01, 1.44), 0.04, sides=6, band="wood_dark", taper=0.92, jitter=0.08, seed=22, rings=2),
                     "arms", "MI_WoodTrim", smooth=55))
    body = BF.straw_lathe([(0.05, 0.84), (0.17, 0.88), (0.22, 1.02), (0.23, 1.2), (0.21, 1.4), (0.15, 1.52), (0.07, 1.58)], 10, jitter=0.05, seed=4)
    parts.append(obj(body, "body", BF.FARM, smooth=55))
    for z, r in ((0.95, 0.205), (1.2, 0.235), (1.44, 0.2)):
        parts.append(obj(rope_ring(z, r, segs=12), "rope", TRAIN, smooth=60, recalc=False))
    head = L.lathe([(0.0, 0.0), (0.07, 0.01), (0.13, 0.07), (0.14, 0.15), (0.11, 0.24), (0.04, 0.28), (0.0, 0.28)], 9, rect="farm_burlap", jitter=0.05, seed=5)
    L.transform(head, Matrix.Translation((0.0, 0, 1.56)))
    parts.append(obj(head, "head", BF.FARM, smooth=60))
    helm = L.lathe([(0.15, 0.0), (0.158, 0.02), (0.15, 0.08), (0.12, 0.14), (0.06, 0.18), (0.0, 0.19)], 12, rect="iron_plate")
    for v in helm.verts:   # dented
        if v.co.x > 0.05 and v.co.y < 0:
            v.co.x *= 0.93
    L.transform(helm, Matrix.Translation((0.01, 0.0, 1.73)) @ Matrix.Rotation(0.22, 4, "Y") @ Matrix.Rotation(-0.1, 4, "X"))
    parts.append(obj(helm, "helm", "MI_MetalOrnaments", smooth=50))
    for sx in (-1, 1):
        parts.append(straw_tufts((sx * 0.6, 0.0, 1.43), (sx, 0, 0), rng))
    parts.append(straw_tufts((0.0, 0.0, 0.85), (0, 0, -1), rng, n=7, r=0.12))
    # A battered round shield strapped to its left arm, facing out (-Y).
    sh = shield(round_outline(0.27), "shield_battered", boss=True)
    for o in sh:
        o.matrix_world = Matrix.Translation((-0.52, -0.08, 1.33)) @ Matrix.Rotation(0.15, 4, "Y")
    parts.extend(sh)
    parts.append(obj(ground_patch(0.7, 0.85, 7, center=(0, -0.25)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def quintain():
    """A quintain: a braced post with an arm turning on an iron pin at its
    head, a painted shield at one end and a sandbag on a rope at the other.
    Strike the shield and the bag comes round."""
    rng = random.Random("quintain")
    parts = [obj(L.beam((0, 0, -0.1), (0, 0, 2.28), 0.18, 0.18, band="wood_dark", rng=rng), "post", "MI_WoodTrim", smooth=None)]
    for a in range(4):   # braces at the foot
        ang = a * math.pi / 2 + math.pi / 4
        d = Vector((math.cos(ang), math.sin(ang), 0))
        parts.append(obj(L.beam(d * 0.78 + Vector((0, 0, 0.02)), d * 0.08 + Vector((0, 0, 0.72)), 0.09, 0.08, band="wood_dark", rng=rng),
                         "brace", "MI_WoodTrim", smooth=None))
        parts.append(obj(L.beam(d * 0.78 + Vector((0, 0, 0.0)), d * 0.62 + Vector((0, 0, 0.0)), 0.12, 0.06, band="wood_dark", rng=rng),
                         "foot", "MI_WoodTrim", smooth=None))
    collar = L.lathe([(0.11, 0.0), (0.125, 0.02), (0.125, 0.08), (0.11, 0.1)], 8, rect="iron_plate")
    L.transform(collar, Matrix.Translation((0, 0, 2.14)))
    parts.append(obj(collar, "collar", "MI_MetalOrnaments", smooth=40))
    pin = L.lathe([(0.03, 0.0), (0.03, 0.14), (0.05, 0.15), (0.05, 0.19), (0.0, 0.2)], 8, rect="iron_plate")
    L.transform(pin, Matrix.Translation((0, 0, 2.27)))
    parts.append(obj(pin, "pin", "MI_MetalOrnaments", smooth=40))
    # The arm, turned a little off square: shield end toward -Y (the rider).
    yaw = math.radians(-18)
    d = Vector((math.sin(yaw), -math.cos(yaw), 0))
    z = 2.34
    shield_end = d * 0.95 + Vector((0, 0, z))
    bag_end = -d * 1.45 + Vector((0, 0, z))
    parts.append(obj(L.beam(bag_end, shield_end, 0.1, 0.12, band="wood_dark", rng=rng), "arm", "MI_WoodTrim", smooth=None))
    sh = shield(heater_outline(0.56, 0.7), "shield_quarterly")
    face = Matrix.Translation(shield_end + d * 0.03 - Vector((0, 0, 0.28))) @ Matrix.Rotation(yaw, 4, "Z")
    for o in sh:
        o.matrix_world = face
    parts.extend(sh)
    # The sandbag swings from the far end on a short rope.
    top = bag_end + Vector((0, 0, -0.06))
    parts.append(obj(L.sweep([top, top + Vector((0.02, 0, -0.42))], 0.016, sides=5, rect="tr_rope"), "rope", TRAIN, smooth=60, recalc=False))
    bag = L.lathe([(0.0, 0.0), (0.12, 0.03), (0.2, 0.14), (0.21, 0.26), (0.15, 0.38), (0.06, 0.44), (0.03, 0.5), (0.0, 0.5)], 9,
                  rect="farm_burlap", jitter=0.06, seed=9)
    L.transform(bag, Matrix.Translation(top + Vector((0.02, 0, -0.9))))
    parts.append(obj(bag, "sandbag", BF.FARM, smooth=55))
    parts.append(obj(rope_ring(top.z - 0.44, 0.045, thick=0.015, segs=8, x=top.x + 0.02, y=top.y), "tie", TRAIN, smooth=60, recalc=False))
    # A worn track round it, where the riders come.
    parts.append(obj(ground_patch(1.5, 1.7, 13, center=(0, -0.3)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def mound(length, depth, height, nx=14, ny=8, seed=0):
    """A turf bank: a loaf of earth, rounded on top so the rain runs off,
    its front (-Y) steeper where the arrows go in."""
    rng = random.Random(seed)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    grid = []
    for j in range(ny + 1):
        row = []
        t = j / ny                     # 0 front foot .. 1 back foot
        for i in range(nx + 1):
            s = i / nx                 # 0 left .. 1 right
            x = (s - 0.5) * length
            y = (t - 0.5) * depth
            ex = 1.0 - abs(2 * s - 1) ** 2.6
            ey = math.sin(math.pi * t) ** (0.7 if t < 0.5 else 1.1)
            zz = height * ex ** 0.45 * ey
            if 0 < i < nx and 0 < j < ny:
                zz += rng.uniform(-0.025, 0.025)
            row.append(bm.verts.new((x, y, max(0.0, zz))))
        grid.append(row)
    _, v0, v1 = L.BANDS["turf"]
    for j in range(ny):
        for i in range(nx):
            q = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            f = bm.faces.new(q)
            for l in f.loops:
                p = l.vert.co
                l[uv].uv = (p.x * L.UV_PER_M * 0.8 + 0.2, v0 + (v1 - v0) * (0.05 + 0.9 * (p.y / depth + 0.5)))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return bm


def archery_butt():
    """A turf butt: an earth bank clad in turf, a square of white linen (the
    clout) pegged to its face, arrows in and round it, the ground in front
    worn where the archers fetch them."""
    rng = random.Random("butt")
    parts = [obj(mound(2.6, 1.5, 1.45, seed=3), "mound", TRAIN, smooth=60, recalc=False)]

    def surface(x, z):
        """The front face's point (and outward normal) at x across, z up."""
        best = None
        for k in range(60):
            y = -0.75 + k * 0.012
            s = x / 2.6 + 0.5
            t = y / 1.5 + 0.5
            ex = 1.0 - abs(2 * s - 1) ** 2.6
            ey = math.sin(math.pi * t) ** 0.7
            zz = 1.45 * ex ** 0.45 * ey
            if zz >= z:
                best = Vector((x, y, z))
                break
        return best or Vector((x, 0, z))

    c = surface(0.0, 0.92)
    n = Vector((0, -1, 0.55)).normalized()
    # The clout: a square of linen, a peg through its middle.
    w = 0.34
    side = Vector((1, 0, 0))
    up = n.cross(side).normalized() * -1
    cl = L.new_bm()
    uv = cl.loops.layers.uv["UVMap"]
    o = c + n * 0.012
    q = [o - side * w / 2 - up * w / 2, o + side * w / 2 - up * w / 2, o + side * w / 2 + up * w / 2, o - side * w / 2 + up * w / 2]
    f = cl.faces.new([cl.verts.new(v) for v in q])
    u0, v0, u1, v1 = T["clout"]
    for l, (s, t) in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    parts.append(obj(cl, "clout", TRAIN, smooth=None, recalc=False))
    parts.append(obj(L.log(c + n * 0.02, c + n * 0.09, 0.012, sides=5, band="wood_light", taper=0.9, jitter=0.05, seed=31, rings=1),
                     "peg", "MI_WoodTrim", smooth=None))
    # Arrows in the turf round the clout (a few strays low and wide).
    for k in range(9):
        x = rng.uniform(-0.55, 0.55) if k < 6 else rng.uniform(-1.0, 1.0)
        zt = rng.uniform(0.62, 1.2) if k < 6 else rng.uniform(0.3, 0.75)
        p = surface(x, zt)
        dirn = Vector((rng.uniform(-0.15, 0.15), 1.0, rng.uniform(-0.25, -0.05))).normalized()
        head = p + dirn * 0.18
        tail = p - dirn * 0.58
        parts.extend(arrow(tail, head, rng))
    parts.append(obj(ground_patch(1.35, 0.8, 17, center=(0, -1.2)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def rack_staves():
    """A rough rack for a village's muster: two crossed trestles and a pole,
    quarterstaves leaning on it and two wooden wasters."""
    rng = random.Random("staves")
    parts = []
    for sx in (-0.75, 0.75):
        for sy in (-1, 1):
            parts.append(obj(L.log((sx, sy * 0.32, 0.0), (sx, -sy * 0.06, 1.12), 0.035, sides=6, band="wood_dark", taper=0.92, jitter=0.1,
                                   seed=int(40 + sx * 10 + sy), rings=2), "leg", "MI_WoodTrim", smooth=55))
    parts.append(obj(L.log((-0.95, 0.0, 1.02), (0.95, 0.0, 1.04), 0.04, sides=6, band="wood_dark", taper=0.95, jitter=0.08, seed=45, rings=2),
                     "pole", "MI_WoodTrim", smooth=55))
    for k in range(5):
        x = -0.55 + k * 0.27 + rng.uniform(-0.04, 0.04)
        foot = Vector((x + rng.uniform(-0.05, 0.05), -0.5, 0.0))
        top = Vector((x, 0.05, 1.04)) + (Vector((x, 0.05, 1.04)) - foot).normalized() * 0.7
        parts.append(obj(L.log(foot, top, 0.022, sides=6, band="wood_light", taper=0.95, jitter=0.03, seed=50 + k, rings=1),
                         "staff", "MI_WoodTrim", smooth=55))
    parts.extend(waster((0.62, -0.42, 0.03), (0.7, 0.04, 1.05), rng))
    parts.extend(waster((-0.86, -0.38, 0.04), (-0.8, 0.05, 1.06), rng))
    parts.append(obj(ground_patch(1.15, 0.7, 23, center=(0, -0.25)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def rack_weapons():
    """A town guard's rack: two posts and two rails, spears standing in the
    top rail, wasters leaning below and shields hung on pegs."""
    rng = random.Random("weapons")
    parts = []
    for sx in (-0.9, 0.9):
        parts.append(obj(L.beam((sx, 0, -0.05), (sx, 0, 1.62), 0.09, 0.09, band="wood_dark", rng=rng), "post", "MI_WoodTrim", smooth=None))
        parts.append(obj(L.beam((sx, -0.28, 0.03), (sx, 0.28, 0.03), 0.09, 0.07, band="wood_dark", rng=rng), "foot", "MI_WoodTrim", smooth=None))
    for z in (0.38, 1.3):
        parts.append(obj(L.beam((-1.0, -0.06, z), (1.0, -0.06, z), 0.07, 0.09, band="wood_dark", rng=rng), "rail", "MI_WoodTrim", smooth=None))
    for k in range(5):
        x = -0.7 + k * 0.35
        foot = Vector((x, -0.06, 0.08))
        top = Vector((x + rng.uniform(-0.03, 0.03), -0.04, 2.25))
        parts.append(obj(L.log(foot, top, 0.019, sides=6, band="wood_light", taper=0.96, jitter=0.02, seed=60 + k, rings=1),
                         "spear", "MI_WoodTrim", smooth=55))
        head = L.lathe([(0.0, 0.0), (0.024, 0.0), (0.024, 0.05), (0.035, 0.08), (0.0, 0.26)], 4, rect="iron_plate")
        L.transform(head, Matrix.Translation(top))
        parts.append(obj(head, "spearhead", "MI_MetalOrnaments", smooth=None))
    parts.extend(waster((-0.55, -0.32, 0.04), (-0.62, -0.12, 0.95), rng))
    parts.extend(waster((0.45, -0.33, 0.04), (0.4, -0.12, 0.95), rng))
    for (x, z, rect, shape) in ((-0.45, 1.0, "shield_chevron", "heater"), (0.42, 0.98, "shield_cross", "round")):
        outline = heater_outline(0.48, 0.6) if shape == "heater" else round_outline(0.26)
        sh = shield(outline, rect, boss=shape == "round")
        for o in sh:
            o.matrix_world = Matrix.Translation((x, -0.16, z)) @ Matrix.Rotation(-0.12, 4, "X")
        parts.extend(sh)
        parts.append(obj(L.log((x, -0.09, z + 0.3), (x, -0.2, z + 0.32), 0.012, sides=5, band="wood_light", taper=1.0, jitter=0.0, seed=70, rings=1),
                         "peg", "MI_WoodTrim", smooth=None))
    parts.append(obj(ground_patch(1.25, 0.7, 29, center=(0, -0.2)), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def ring_rope():
    """A sparring ring: six stakes, rope sagging between them (one side open
    to step in), the ground inside trodden to bare earth."""
    rng = random.Random("ring_rope")
    parts = []
    r = 2.6
    stakes = []
    for k in range(6):
        a = math.pi / 2 + k * math.tau / 6
        p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        stakes.append(p)
        parts.append(obj(L.log(p - Vector((0, 0, 0.1)), p + Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 1.08)), 0.05, sides=6,
                               band="wood_dark", taper=0.9, jitter=0.1, seed=80 + k, rings=2), "stake", "MI_WoodTrim", smooth=55))
    for k in range(6):
        if k == 2:   # the gap in front (-Y side)
            continue
        a, b = stakes[k], stakes[(k + 1) % 6]
        pts = []
        for i in range(9):
            t = i / 8
            p = a.lerp(b, t)
            p.z = 0.98 - 0.16 * math.sin(math.pi * t)
            pts.append(p)
        parts.append(obj(L.sweep(pts, 0.016, sides=5, rect="tr_rope"), "rope", TRAIN, smooth=60, recalc=False))
    parts.append(obj(ground_patch(2.9, 2.9, 37, segs=26, rough=0.1), "ground", TRAIN, smooth=None, recalc=False))
    return parts


def ring_rail():
    """A town's ring: eight posts and two rails round a sanded floor, a gap to
    step in."""
    rng = random.Random("ring_rail")
    parts = []
    r = 2.8
    posts = []
    for k in range(8):
        a = math.pi / 8 + k * math.tau / 8
        p = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        posts.append(p)
        parts.append(obj(L.beam(p - Vector((0, 0, 0.08)), p + Vector((0, 0, 1.12)), 0.11, 0.11, band="wood_dark", rng=rng), "post", "MI_WoodTrim", smooth=None))
    for k in range(8):
        if k == 5:   # the gap (front, -Y)
            continue
        a, b = posts[k], posts[(k + 1) % 8]
        for z in (0.55, 1.0):
            parts.append(obj(L.beam(a + Vector((0, 0, z)), b + Vector((0, 0, z)), 0.07, 0.09, band="wood_light", rng=rng), "rail", "MI_WoodTrim", smooth=None))
    parts.append(obj(ground_patch(3.05, 3.05, 41, segs=28, rough=0.06), "ground", TRAIN, smooth=None, recalc=False))
    return parts


BUILDERS = {
    "SE_Pell": pell,
    "SE_Dummy_Straw": dummy_straw,
    "SE_Quintain": quintain,
    "SE_ArcheryButt": archery_butt,
    "SE_Rack_Staves": rack_staves,
    "SE_Rack_Weapons": rack_weapons,
    "SE_Ring_Rope": ring_rope,
    "SE_Ring_Rail": ring_rail,
}


# --- Build, export, review -------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(TRAIN, (1.0, 1.0, 1.0), roughness=0.85, image=TRAIN_TEX)
    L.custom_material(BF.FARM, (1.0, 1.0, 1.0), roughness=0.9, image=BF.FARM_TEX)


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
        o.location = ((i % 4) * 7.0, (i // 4) * 7.0, 0)
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
            save_blend(built, os.path.join(HERE, "training_yard.blend"))
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
