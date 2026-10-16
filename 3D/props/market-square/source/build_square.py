"""Builds the Market Square family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_square.py [--review DIR] [--kerbs DIR/name] [--lineup DIR/name] [--export] [--only A,B]

The edge of the square and what stands on it, growing with the charter:
kerb pieces (1.5 m, laid round the rim: rubble edging, a dressed kerb, a
two-step stone edge), the market cross a Market Town's charter brings (and
a Town's grander lantern cross), and the trough beside the well (a hollowed
log, then a carved stone trough). Everything is UV-mapped onto the village
kit's trim sheets; the troughs have their own water, and the Town cross's
gilding is the commons' banner gold.

Origin at the ground, front = -Y in Blender (+Z in Godot). A kerb piece runs
along +X from x = 0 to 1.5 m with the square's edge on y = 0 and the kerb
reaching out to -Y (away from the square).
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
import build_commons as BC  # noqa: E402  (ring_sector, review, lineup, mannequin)

FAMILY = os.path.dirname(HERE)
WATER = "MI_Square_Water"
# Trough water: open to the sky, so darker and less glossy than the well's
# (which sits down a shaft); otherwise it reads as a pale blue board.
OWN = {WATER: {"doubleSided": False, "pbr": {"baseColorFactor": [0.045, 0.1, 0.105, 1.0], "metallicFactor": 0, "roughnessFactor": 0.32}}}
SEG = 1.5          # kerb piece length (m)
PAVING_TOP = 0.15  # the square's paving surface in game (m above the grass)


# --- Small parts ---------------------------------------------------------------------------------

def block(x0, x1, y0, y1, z0, z1, band, bevel=0.02, rng=None, tilt=0.0):
    """A dressed stone block between the given bounds (bevelled), optionally
    tipped a little, as laid by hand."""
    size = (x1 - x0, y1 - y0, z1 - z0)
    bm = L.box(size, band, bevel=bevel, segments=1, rng=rng)
    if tilt and rng:
        L.transform(bm, Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "X") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "Y"))
    L.transform(bm, Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)))
    return bm


def water_rect(x0, x1, y0, y1, z):
    bm = L.new_bm()
    vs = [bm.verts.new(p) for p in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv["UVMap"]
    for l in f.loops:
        l[uv].uv = ((l.vert.co.x - x0) / max(x1 - x0, 1e-3), (l.vert.co.y - y0) / max(y1 - y0, 1e-3))
    bm.normal_update()
    return bm


def octagon_course(r_in, r_out, z0, z1, band, seed, bevel=0.015):
    """One course of an octagonal stepped base: eight dressed blocks, a flat
    side to the front (-Y)."""
    bm = L.new_bm()
    for k in range(8):
        a0 = -math.pi / 2 - math.pi / 8 + k * math.pi / 4
        L.merge_bm(bm, BC.ring_sector(r_in, r_out, z0, z1, a0 + 0.004, a0 + math.pi / 4 - 0.004, 1, band, bevel=bevel, seed=seed + k))
    return bm


# --- Kerbs (1.5 m pieces along +X; the square on +Y, the kerb reaching out to -Y) ---------------

def kerb_rubble():
    """Hamlet: field stones half sunk along the square's edge, a hand apart."""
    rng = random.Random(11)
    bm = L.new_bm()
    k = 0
    x = 0.02
    while x < SEG - 0.2:
        sx = rng.uniform(0.44, 0.6)
        sy = rng.uniform(0.34, 0.46)
        sz = rng.uniform(0.3, 0.38)
        c = (x + sx * 0.5, -0.24 + rng.uniform(-0.04, 0.04), sz * 0.5 - 0.12)
        L.merge_bm(bm, L.stone(c, (sx, sy, sz), seed=40 + k, band="rock_slate", detail=2, rough=0.24))
        x += sx * 0.9 + rng.uniform(0.02, 0.08)
        k += 1
    return [L.to_object(bm, "stones", "MI_RockTrim", smooth_angle=60, recalc=False)]


def kerb_stone():
    """Village: two dressed kerb stones, their tops a hand above the paving."""
    rng = random.Random(12)
    bm = L.new_bm()
    for i in range(2):
        x0 = i * SEG / 2 + 0.01
        top = PAVING_TOP + 0.06 + rng.uniform(-0.008, 0.008)
        L.merge_bm(bm, block(x0, x0 + SEG / 2 - 0.02, -0.32, -0.01, -0.12, top, "rock_ashlar", bevel=0.025, rng=rng, tilt=0.008))
    return [L.to_object(bm, "kerb", "MI_RockTrim", smooth_angle=35, recalc=False)]


def kerb_step():
    """Market Town and Town: the square's edge as two shallow steps, a slate
    coping flush with the paving, then a dressed step down to the grass;
    joints staggered between the courses."""
    rng = random.Random(13)
    bm = L.new_bm()
    for i in range(2):
        x0 = i * SEG / 2 + 0.01
        L.merge_bm(bm, block(x0, x0 + SEG / 2 - 0.02, -0.36, 0.0, -0.1, PAVING_TOP + 0.025, "rock_slate", bevel=0.025, rng=rng, tilt=0.004))
    for i in range(3):
        xa = max(0.01, i * SEG / 2 - SEG / 4 + 0.01)
        xb = min(SEG - 0.01, (i + 1) * SEG / 2 - SEG / 4 - 0.01)
        L.merge_bm(bm, block(xa, xb, -0.74, -0.37, -0.12, 0.085, "rock_ashlar", bevel=0.02, rng=rng, tilt=0.006))
    return [L.to_object(bm, "steps", "MI_RockTrim", smooth_angle=35, recalc=False)]


# --- Market crosses ------------------------------------------------------------------------------

def stepped_base(courses, seed):
    """Octagonal steps: [(r_out, height)], bottom first; each course rests on
    the one below and covers its middle."""
    parts = []
    z = -0.05
    for i, (r_out, h) in enumerate(courses):
        r_in = courses[i + 1][0] - 0.2 if i + 1 < len(courses) else 0.25
        band = "rock_slate" if i % 2 == 0 else "rock_ashlar"
        parts.append(L.to_object(octagon_course(max(r_in, 0.2), r_out, z, z + h, band, seed + i * 10), "step%d" % i, "MI_RockTrim", smooth_angle=30, recalc=False))
        z += h
    return parts, z


def notice(at_y, z, rng):
    """The charter posted on the socket: a board with an iron strap and nails."""
    parts = []
    board = L.box((0.34, 0.025, 0.44), "wood_light", bevel=0.006, rng=rng)
    L.transform(board, Matrix.Rotation(0.03, 4, "Y"))
    L.transform(board, Matrix.Translation((0.0, at_y - 0.014, z)))
    parts.append(L.to_object(board, "notice", "MI_WoodTrim", smooth_angle=30))
    strap = L.box((0.38, 0.012, 0.035), "wood_dark", bevel=0.003)
    rect = L.RECTS["iron_strap"]
    uv = strap.loops.layers.uv["UVMap"]
    for f in strap.faces:
        for l in f.loops:
            l[uv].uv = (rect[1] + (rect[3] - rect[1]) * (l.vert.co.x / 0.38 + 0.5), rect[2] + (rect[4] - rect[2]) * (l.vert.co.z / 0.035 + 0.5))
    L.transform(strap, Matrix.Translation((0.0, at_y - 0.03, z + 0.17)))
    parts.append(L.to_object(strap, "strap", "MI_MetalOrnaments", smooth_angle=30))
    for sx in (-0.14, 0.14):
        nail = L.lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.008), (0.0, 0.012)], 6, rect="iron_bar")
        L.transform(nail, Matrix.Translation((sx, at_y - 0.028, z - 0.18)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        parts.append(L.to_object(nail, "nail", "MI_MetalOrnaments", smooth_angle=50, recalc=False))
    return parts


def market_cross():
    """Market Town: the cross that marks the market right. Three octagonal
    steps, a square socket with a broached top and the charter posted on it,
    a tapering octagonal shaft with an iron band, and a stone cross."""
    rng = random.Random(31)
    parts, z = stepped_base([(1.5, 0.27), (1.13, 0.26), (0.8, 0.25)], seed=100)
    # Socket: square, broached (chamfered) up to the shaft.
    sock = L.lathe([(0.44, z - 0.02), (0.44, z + 0.42), (0.3, z + 0.55), (0.0, z + 0.55)], 4, band="rock_ashlar", phase=math.pi / 4)
    parts.append(L.to_object(sock, "socket", "MI_RockTrim", smooth_angle=30, recalc=False))
    parts += notice(-0.31, z + 0.24, rng)
    z_sh = z + 0.53
    shaft = L.lathe([(0.17, z_sh), (0.165, z_sh + 0.1), (0.125, z_sh + 2.45), (0.12, z_sh + 2.5)], 8, band="rock_ashlar", phase=math.pi / 8)
    parts.append(L.to_object(shaft, "shaft", "MI_RockTrim", smooth_angle=30, recalc=False))
    band_ = L.lathe([(0.16, z_sh + 1.0), (0.165, z_sh + 1.03), (0.165, z_sh + 1.1), (0.16, z_sh + 1.13)], 8, rect="iron_bar", phase=math.pi / 8)
    parts.append(L.to_object(band_, "iron", "MI_MetalOrnaments", smooth_angle=30, recalc=False))
    z_cap = z_sh + 2.48
    cap = L.lathe([(0.12, z_cap), (0.2, z_cap + 0.08), (0.2, z_cap + 0.15), (0.13, z_cap + 0.18), (0.0, z_cap + 0.18)], 8, band="rock_slate", phase=math.pi / 8)
    parts.append(L.to_object(cap, "capital", "MI_RockTrim", smooth_angle=30, recalc=False))
    # The cross: a tall upright and the arms, flared a little at the ends.
    zc = z_cap + 0.18
    up = block(-0.065, 0.065, -0.065, 0.065, zc - 0.02, zc + 0.78, "rock_ashlar", bevel=0.015, rng=rng)
    parts.append(L.to_object(up, "upright", "MI_RockTrim", smooth_angle=30))
    arm = block(-0.3, 0.3, -0.06, 0.06, zc + 0.43, zc + 0.55, "rock_ashlar", bevel=0.015, rng=rng)
    parts.append(L.to_object(arm, "arms", "MI_RockTrim", smooth_angle=30))
    for sx in (-1, 1):
        tip = block(sx * 0.3 - 0.03, sx * 0.3 + 0.03, -0.075, 0.075, zc + 0.41, zc + 0.57, "rock_slate", bevel=0.012, rng=rng)
        parts.append(L.to_object(tip, "tip", "MI_RockTrim", smooth_angle=30))
    top = block(-0.075, 0.075, -0.075, 0.075, zc + 0.76, zc + 0.82, "rock_slate", bevel=0.012, rng=rng)
    parts.append(L.to_object(top, "tip", "MI_RockTrim", smooth_angle=30))
    return parts


def gablet(face_angle, cx, half, z0, h, rng):
    """A small stone gable on one face of the lantern head."""
    bm = L.new_bm()
    pts = [(-half, z0), (half, z0), (0.0, z0 + h)]
    front = [bm.verts.new((x, -cx, z)) for x, z in pts]
    back = [bm.verts.new((x, -cx + 0.06, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new([front[i], back[i], back[j], front[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    L.uv_box_band(bm, list(bm.faces), "rock_slate", u_off=rng.uniform(0, 1))
    L.transform(bm, Matrix.Rotation(face_angle, 4, "Z"))
    return bm


def market_cross_town():
    """Town: a lantern cross. Four octagonal steps, a moulded octagonal
    socket with iron shields, a tall shaft with two iron bands, and a
    lantern head: a square block with a gablet on every face, corner
    pinnacles, a stone spirelet and a gilt cross."""
    rng = random.Random(37)
    parts, z = stepped_base([(1.6, 0.23), (1.3, 0.22), (1.0, 0.22), (0.72, 0.22)], seed=200)
    sock = L.lathe([(0.5, z - 0.02), (0.5, z + 0.07), (0.43, z + 0.13), (0.43, z + 0.6), (0.5, z + 0.66), (0.5, z + 0.73), (0.3, z + 0.82), (0.0, z + 0.82)], 8, band="rock_ashlar", phase=math.pi / 8)
    parts.append(L.to_object(sock, "socket", "MI_RockTrim", smooth_angle=30, recalc=False))
    # Iron shields on the four main faces of the socket.
    rect = L.RECTS["iron_plate"]
    for k in range(4):
        sh = L.new_bm()
        outline = [(-0.1, 0.1), (0.1, 0.1), (0.1, -0.02), (0.0, -0.12), (-0.1, -0.02)]
        vs = [sh.verts.new((x, 0.0, zz)) for x, zz in outline]
        sh.faces.new(vs)
        sh.normal_update()  # solidify offsets along vertex normals: they must exist
        bmesh.ops.solidify(sh, geom=sh.faces[:], thickness=0.012)
        uv = sh.loops.layers.uv["UVMap"]
        for f in sh.faces:
            for l in f.loops:
                l[uv].uv = (rect[1] + (rect[3] - rect[1]) * (l.vert.co.x / 0.2 + 0.5), rect[2] + (rect[4] - rect[2]) * (l.vert.co.z / 0.22 + 0.55))
        apothem = 0.43 * math.cos(math.pi / 8)
        L.transform(sh, Matrix.Rotation(k * math.pi / 2, 4, "Z") @ Matrix.Translation((0.0, -apothem - 0.004, z + 0.38)))
        parts.append(L.to_object(sh, "shield", "MI_MetalOrnaments", smooth_angle=30))
    z_sh = z + 0.8
    shaft = L.lathe([(0.18, z_sh), (0.175, z_sh + 0.1), (0.13, z_sh + 2.9), (0.125, z_sh + 2.95)], 8, band="rock_ashlar", phase=math.pi / 8)
    parts.append(L.to_object(shaft, "shaft", "MI_RockTrim", smooth_angle=30, recalc=False))
    for zz in (z_sh + 0.9, z_sh + 2.0):
        r = 0.18 - 0.05 * (zz - z_sh) / 2.9 + 0.005
        b = L.lathe([(r, zz), (r + 0.006, zz + 0.03), (r + 0.006, zz + 0.09), (r, zz + 0.12)], 8, rect="iron_bar", phase=math.pi / 8)
        parts.append(L.to_object(b, "iron", "MI_MetalOrnaments", smooth_angle=30, recalc=False))
    # Lantern head.
    zh = z_sh + 2.93
    cap = L.lathe([(0.13, zh), (0.26, zh + 0.1), (0.26, zh + 0.16), (0.0, zh + 0.16)], 8, band="rock_slate", phase=math.pi / 8)
    parts.append(L.to_object(cap, "capital", "MI_RockTrim", smooth_angle=30, recalc=False))
    zb = zh + 0.16
    head = block(-0.2, 0.2, -0.2, 0.2, zb, zb + 0.46, "rock_ashlar", bevel=0.012, rng=rng)
    parts.append(L.to_object(head, "lantern", "MI_RockTrim", smooth_angle=30))
    for k in range(4):
        # A dark niche on each face, and its gablet above.
        niche = block(-0.09, 0.09, -0.212, -0.19, zb + 0.08, zb + 0.36, "rock_cobble", bevel=0.004, rng=rng)
        L.transform(niche, Matrix.Rotation(k * math.pi / 2, 4, "Z"))
        parts.append(L.to_object(niche, "niche", "MI_RockTrim", smooth_angle=30))
        parts.append(L.to_object(gablet(k * math.pi / 2, 0.2, 0.21, zb + 0.44, 0.24, rng), "gablet", "MI_RockTrim", smooth_angle=30, recalc=False))
    for sx in (-1, 1):
        for sy in (-1, 1):
            pin = L.lathe([(0.045, zb + 0.4), (0.045, zb + 0.52), (0.0, zb + 0.68)], 4, band="rock_slate", phase=math.pi / 4)
            L.transform(pin, Matrix.Translation((sx * 0.19, sy * 0.19, 0)))
            parts.append(L.to_object(pin, "pinnacle", "MI_RockTrim", smooth_angle=30, recalc=False))
    spire = L.lathe([(0.2, zb + 0.44), (0.17, zb + 0.5), (0.0, zb + 0.95)], 4, band="rock_slate", phase=math.pi / 4)
    parts.append(L.to_object(spire, "spirelet", "MI_RockTrim", smooth_angle=20, recalc=False))
    # Gilt cross on the spirelet.
    zt = zb + 0.92
    gilt = L.new_bm()
    L.merge_bm(gilt, L.box((0.035, 0.035, 0.34), "wood_dark", bevel=0.006))
    L.transform(gilt, Matrix.Translation((0, 0, zt + 0.17)))
    arm = L.box((0.2, 0.03, 0.03), "wood_dark", bevel=0.006)
    L.transform(arm, Matrix.Translation((0, 0, zt + 0.24)))
    L.merge_bm(gilt, arm)
    BC.gilt(gilt)
    parts.append(L.to_object(gilt, "gilt_cross", BC.BANNER, smooth_angle=30, recalc=False))  # the banners' gilding
    return parts


# --- Troughs (long axis along X) -----------------------------------------------------------------

def channel(length, R, r, z_rim, arc=8, xsegs=6, rng=None, band="wood_dark", inner_band="wood_light"):
    """A hollowed half-log along X: the outer bark below, a flat rim and the
    worn wood inside, with the ends closed."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    slices = []
    for i in range(xsegs + 1):
        x = -length / 2 + length * i / xsegs
        wob = (rng.uniform(-0.01, 0.01) if rng else 0.0)
        ring = []
        for k in range(arc + 1):  # outer: left rim -> bottom -> right rim
            a = math.pi + math.pi * k / arc
            ring.append(bm.verts.new((x, math.cos(a) * (R + wob), z_rim + math.sin(a) * (R + wob))))
        for k in range(arc + 1):  # inner: right rim -> bottom -> left rim
            a = 2 * math.pi - math.pi * k / arc
            ring.append(bm.verts.new((x, math.cos(a) * r, z_rim + math.sin(a) * r)))
        slices.append(ring)
    n = len(slices[0])
    _, ov0, ov1 = L.BANDS[band]
    _, iv0, iv1 = L.BANDS[inner_band]
    for i in range(xsegs):
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new([slices[i][k], slices[i + 1][k], slices[i + 1][k2], slices[i][k2]])
            inner = k > arc
            v0, v1 = (iv0, iv1) if inner else (ov0, ov1)
            for l in f.loops:
                kk = slices[i].index(l.vert) if l.vert in slices[i] else slices[i + 1].index(l.vert)
                t = (kk if kk <= arc else kk - arc - 1) / arc
                l[uv].uv = ((l.vert.co.x + length / 2) * L.UV_PER_M, v0 + (v1 - v0) * (0.1 + 0.8 * t))
    er = L.RECTS["end_grain"]
    for ring in (slices[0], slices[-1]):
        for k in range(arc):
            f = bm.faces.new([ring[k], ring[k + 1], ring[n - 2 - k], ring[n - 1 - k]])
            for l in f.loops:
                p = l.vert.co
                l[uv].uv = (er[1] + (er[3] - er[1]) * (p.y / (2 * R) + 0.5), er[2] + (er[4] - er[2]) * ((p.z - z_rim) / (2 * R) + 1.0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    return bm


def trough_log():
    """Hamlet and Village: a hollowed half-log on two chocks, full of water."""
    rng = random.Random(51)
    parts = []
    z_rim = 0.44
    parts.append(L.to_object(channel(1.9, 0.27, 0.2, z_rim, rng=rng), "log", "MI_WoodTrim", smooth_angle=50, recalc=False))
    for sx in (-0.62, 0.62):
        chock = block(sx - 0.1, sx + 0.1, -0.24, 0.24, 0.0, 0.2, "wood_dark", bevel=0.015, rng=rng, tilt=0.03)
        parts.append(L.to_object(chock, "chock", "MI_WoodTrim", smooth_angle=40))
    wl = z_rim - 0.09
    hw = math.sqrt(0.2 ** 2 - 0.09 ** 2)
    parts.append(L.to_object(water_rect(-0.93, 0.93, -hw, hw, wl), "water", WATER, smooth_angle=None, recalc=False))
    return parts


def trough_stone():
    """Market Town and Town: a carved stone trough on a plinth, its rim
    moulded, an iron ring for tethering at one end, full of water."""
    rng = random.Random(53)
    parts = []
    bm = L.new_bm()
    L.merge_bm(bm, block(-0.98, 0.98, -0.4, 0.4, -0.04, 0.1, "rock_slate", bevel=0.02, rng=rng))           # plinth
    L.merge_bm(bm, block(-0.92, 0.92, -0.34, 0.34, 0.1, 0.2, "rock_ashlar", bevel=0.012, rng=rng))          # floor
    for sy in (-1, 1):
        L.merge_bm(bm, block(-0.92, 0.92, sy * 0.34 - (0.11 if sy > 0 else 0.0), sy * 0.34 + (0.0 if sy > 0 else 0.11), 0.1, 0.66, "rock_ashlar", bevel=0.02, rng=rng))
    for sx in (-1, 1):
        L.merge_bm(bm, block(sx * 0.92 - (0.12 if sx > 0 else 0.0), sx * 0.92 + (0.0 if sx > 0 else 0.12), -0.23, 0.23, 0.1, 0.66, "rock_ashlar", bevel=0.02, rng=rng))
    parts.append(L.to_object(bm, "trough", "MI_RockTrim", smooth_angle=35, recalc=False))
    rim = L.new_bm()
    for sy in (-1, 1):
        L.merge_bm(rim, block(-0.95, 0.95, sy * 0.345 - 0.065, sy * 0.345 + 0.065, 0.64, 0.7, "rock_slate", bevel=0.015, rng=rng))
    for sx in (-1, 1):
        L.merge_bm(rim, block(sx * 0.885 - 0.065, sx * 0.885 + 0.065, -0.28, 0.28, 0.64, 0.7, "rock_slate", bevel=0.015, rng=rng))
    parts.append(L.to_object(rim, "rim", "MI_RockTrim", smooth_angle=35, recalc=False))
    ring = L.sweep(L.arc_points(Vector((1.0, 0.0, 0.48)), 0.06, 0, math.tau, 12, axis="X"), 0.011, sides=6, rect="iron_bar", closed=True)
    parts.append(L.to_object(ring, "ring", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    staple = L.box((0.03, 0.04, 0.05), "wood_dark", bevel=0.004)
    L.transform(staple, Matrix.Translation((0.995, 0.0, 0.545)))
    parts.append(L.to_object(staple, "staple", "MI_MetalOrnaments", smooth_angle=30))
    parts.append(L.to_object(water_rect(-0.8, 0.8, -0.23, 0.23, 0.52), "water", WATER, smooth_angle=None, recalc=False))
    return parts


BUILDERS = {
    "SE_Kerb_Rubble": kerb_rubble,
    "SE_Kerb_Stone": kerb_stone,
    "SE_Kerb_Step": kerb_step,
    "SE_MarketCross": market_cross,
    "SE_MarketCross_Town": market_cross_town,
    "SE_Trough_Log": trough_log,
    "SE_Trough_Stone": trough_stone,
}

# Simple collision proxies: ("box", sx, sy, sz, cx) or ("cyl", radius, height).
# Kerbs have none: people step over them.
COLLIDERS = {
    "SE_MarketCross": ("cyl", 1.5, 1.3), "SE_MarketCross_Town": ("cyl", 1.6, 1.7),
    "SE_Trough_Log": ("box", 1.95, 0.6, 0.6, 0.0), "SE_Trough_Stone": ("box", 1.98, 0.82, 0.72, 0.0),
}


def setup():
    L.reset()
    L.custom_material(WATER, (0.045, 0.1, 0.105), roughness=0.32)
    L.custom_material(BC.BANNER, (1.0, 1.0, 1.0), roughness=0.85, image=BC.BANNER_TEX)


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)  # helpers called without an rng of their own draw from here: same source, same GLBs
        obj = L.join(fn(), name)
        uvs = obj.data.uv_layers
        uvs.active = uvs["UVMap"]
        uvs["UVMap"].active_render = True
        if "Sway" in uvs:
            uvs.remove(uvs["Sway"])
        L.weighted_normals(obj)
        built.append(obj)
        print("%s: %d tris, %d materials" % (name, L.tri_count(obj), len(obj.data.materials)))
    return built


def collider(name):
    spec = COLLIDERS.get(name)
    if not spec:
        return None
    bm = L.new_bm()
    if spec[0] == "box":
        _, sx, sy, sz, cx = spec
        bmesh.ops.create_cube(bm, size=1.0)
        L.transform(bm, Matrix.Translation((cx, 0, sz / 2)) @ Matrix.Diagonal((sx, sy, sz, 1)))
    else:
        _, r, h = spec
        bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=h)
        L.transform(bm, Matrix.Translation((0, 0, h / 2)))
    o = L.to_object(bm, name + "-convcolonly", "MI_WoodTrim", smooth_angle=None)
    o.data.materials.clear()
    while o.data.uv_layers:
        o.data.uv_layers.remove(o.data.uv_layers[0])
    return o


def export(objs):
    models = os.path.join(FAMILY, "models")
    tmp = os.path.join(HERE, "_export_tmp")
    os.makedirs(models, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    for obj in objs:
        col = collider(obj.name)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        if col:
            col.select_set(True)
        loc = obj.location.copy()
        obj.location = (0, 0, 0)
        path = os.path.join(tmp, obj.name + ".gltf")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=True,
                                  export_image_format="NONE", export_yup=True, export_texcoords=True, export_normals=True,
                                  export_tangents=False, export_attributes=False, export_extras=False, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=False, export_morph=False)
        glb = os.path.join(models, obj.name + ".glb")
        mats = gltf_pack.pack(path, glb, own=OWN)
        obj.location = loc
        if col:
            bpy.data.objects.remove(col)
        print("exported %s: %d tris, %s, %d bytes" % (obj.name, L.tri_count(obj), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def save_blend(objs, path):
    for o in [o for o in bpy.data.objects if o.name.startswith("_")]:
        bpy.data.objects.remove(o)
    for i, o in enumerate(objs):
        o.hide_render = False
        o.location = ((i % 4) * 4.0, (i // 4) * 4.0, 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)


def kerb_arcs(objs, out, radius=13.5):
    """Each kerb tier as it lies in game: an arc of pieces round the edge of
    a paved disc, with the heir's mannequin for scale."""
    kerbs = [o for o in objs if o.name.startswith("SE_Kerb")]
    BC.review([], out, views=[("setup", 0, 30, 1.0, 40)], res=(32, 32))  # lights, ground, mannequin
    sc = bpy.context.scene
    n = round(math.tau * radius / SEG)
    step = math.tau / n
    chord = 2 * radius * math.sin(step / 2)
    pave = L.custom_material("_paving", (0.55, 0.5, 0.44), roughness=0.9)
    paths = []
    for o in objs:
        o.hide_render = True
    for idx, k in enumerate(kerbs):
        group = []
        disc = L.new_bm()
        bmesh.ops.create_circle(disc, cap_ends=True, radius=radius, segments=96)
        L.transform(disc, Matrix.Translation((0, 0, PAVING_TOP)))
        d = L.to_object(disc, "_disc", "MI_RockTrim", smooth_angle=None)
        d.data.materials.clear()
        d.data.materials.append(pave)
        group.append(d)
        for i in range(-5, 6):
            a0 = -math.pi / 2 + i * step
            p0 = Vector((math.cos(a0), math.sin(a0), 0)) * radius
            tang = Vector((-math.sin(a0 + step / 2), math.cos(a0 + step / 2), 0))
            c = k.copy()
            sc.collection.objects.link(c)
            c.hide_render = False
            # Local +X along the edge, local -Y outward.
            out_dir = Vector((math.cos(a0 + step / 2), math.sin(a0 + step / 2), 0))
            m = Matrix(((tang.x, -out_dir.x, 0, p0.x), (tang.y, -out_dir.y, 0, p0.y), (0, 0, 1, 0), (0, 0, 0, 1)))
            m = m @ Matrix.Diagonal((chord / SEG, 1, 1, 1))
            c.matrix_world = m
            group.append(c)
        man = bpy.data.objects.get("_mannequin")
        if man:
            man.location = (1.0, -radius - 1.2, 0)
        cam_data = bpy.data.cameras.new("_kcam")
        cam = bpy.data.objects.new("_kcam", cam_data)
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam_data.lens = 40
        sc.render.resolution_x, sc.render.resolution_y = 1280, 640
        for name, eye, look in (("mid", (5.5, -radius - 7.5, 4.2), (0, -radius + 0.5, 0.2)), ("close", (2.2, -radius - 2.6, 1.3), (0.3, -radius + 0.3, 0.1)),
                                ("top", (0.0, -radius - 0.4, 7.5), (0.0, -radius - 0.3, 0.0))):
            cam.location = eye
            cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = "%s_%s_%s.png" % (out, k.name, name)
            bpy.ops.render.render(write_still=True)
            paths.append(sc.render.filepath)
        for g in group:
            bpy.data.objects.remove(g)
        bpy.data.objects.remove(cam)
    return paths


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    setup()
    built = build(only)
    if "--export" in args:
        export(built)
        if not only:
            save_blend(built, os.path.join(HERE, "market_square.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for obj in built:
            if obj.name.startswith("SE_Kerb"):
                continue
            for o in built:
                o.hide_render = o is not obj
            h = max(obj.dimensions.z, 0.6)
            base = os.path.join(out, obj.name)
            if h > 3.0:
                # The crosses: framed on their height, and a close look at the
                # socket with its notice (Market Town) or the lantern head (Town).
                ext = h * 1.15
                far = [("front34", -35, 14, 6.0, 40), ("rear34", 150, 16, 6.0, 40), ("gameplay", -20, 38, 10.0, 50)]
                shots = BC.review([obj], base, views=far, extent=ext, center_z=h * 0.48)
                detail_z = 1.4 if obj.name == "SE_MarketCross" else (h - 0.75) / 1.45
                shots += BC.review([obj], base, views=[("close", -30, 12, 3.4, 42)], extent=3.4, center_z=detail_z)
            else:
                ext = max(obj.dimensions.x, obj.dimensions.y, 2.0) * 1.15
                views = [("front34", -35, 18, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 38, 10.0, 50), ("close", -40, 12, 3.0, 42)]
                shots = BC.review([obj], base, views=views, extent=ext, center_z=h * 0.45)
            for p in shots:
                print("  ", p)
    if "--kerbs" in args:
        out = args[args.index("--kerbs") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for p in kerb_arcs(built, out):
            print("  ", p)
    if "--lineup" in args:
        out = args[args.index("--lineup") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tall = max(o.dimensions.z for o in built)
        for p in BC.lineup(built, out, spacing=max(2.4, max(o.dimensions.x for o in built) + 0.6), center_z=max(0.3, tall * 0.5)):
            print("  ", p)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
