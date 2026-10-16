"""Builds the Lord's Castle family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_castle.py [--review DIR] [--export] [--only A,B]

Pieces for a lord's castle as it might stand in the 1180s, in two tiers:
  - timber (motte and bailey): a palisade of pointed stakes with a fighting
    platform, a timber gate tower, the motte (an earth mound), the timber
    tower on its top and the flying bridge up its flank;
  - stone: curtain wall, a plain corner, a wall with a stair to its wall
    walk, square mural towers (in line and at a corner), a gatehouse with a
    portcullis, and a great tower (keep) with a forebuilding, after Henry
    II's towers of the 1170s-80s (pilaster buttresses, corner turrets,
    round-headed windows, a first-floor entrance up a stone stair).

They join on a 4 m grid along the wall line (+X), the outside to -Y:
  curtain wall 4 m, stair 8 m, corner 2.4 m (the wall's thickness),
  towers 6 m, gatehouse 8 m; palisade and timber gate 4 m. The wall walk
  is at 6 m; a tower's doors open onto it.

The walls are in the village kit's rubble stone (MI_UnevenBrick, the
stone of the village's houses and chapel tower), dressed corners,
courses and copings in its ashlar (MI_RockTrim), timber and iron on its
trim sheets; shingles, turf, earth, the dark of loops and windows, lead,
the gate and planks on this family's atlas (T_Castle_BaseColor.png,
paint_castle.py).

Origin at the ground in the middle of the piece; front (outside) = -Y in
Blender (+Z in Godot). The motte and its bridge share an origin.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "..", "props", "village-commons", "source")

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
from mathutils.bvhtree import BVHTree  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402
import build_commons as BC  # noqa: E402  (review renders)

FAMILY = os.path.dirname(HERE)
CA = "MI_Castle"
CA_TEX = os.path.join(FAMILY, "textures", "T_Castle_BaseColor.png")
STONE = "MI_UnevenBrick"
OWN = {
    CA: {"doubleSided": False, "dir": os.path.join(FAMILY, "textures"),
         "pbr": {"baseColorTexture": "T_Castle_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
    STONE: {"doubleSided": False, "dir": gltf_pack.VILLAGE, "normalTexture": "T_UnevenBrick_Normal.png",
            "pbr": {"baseColorTexture": "T_UnevenBrick_BaseColor.png", "metallicFactor": 0, "metallicRoughnessTexture": "T_UnevenBrick_Roughness.png"}},
}
L.MATERIALS[STONE] = ("T_UnevenBrick_BaseColor.png", "T_UnevenBrick_Normal.png")


def _cell(x0, y0, x1, y1):
    """Image pixels (y down) of the 512 atlas -> Blender UV rect (v up)."""
    return (x0 / 512, 1 - y1 / 512, x1 / 512, 1 - y0 / 512)


T = {"void": _cell(4, 388, 124, 508), "lead": _cell(132, 388, 252, 508),
     "gate": _cell(260, 388, 380, 508), "planks": _cell(388, 388, 508, 508)}
for _k, _v in T.items():
    L.RECTS["ca_" + _k] = (CA,) + _v
L.BANDS["ca_shingles"] = (CA, 1 - 128 / 512 + 0.004, 1 - 0.004)
L.BANDS["ca_turf"] = (CA, 1 - 256 / 512 + 0.004, 1 - 128 / 512 - 0.004)
L.BANDS["ca_earth"] = (CA, 1 - 384 / 512 + 0.004, 1 - 256 / 512 - 0.004)

# The kit grid.
WALL_H = 6.0       # wall walk
WALL_T = 2.4       # curtain thickness
PARAPET_T = 0.6
BREAST = 1.0       # breastwork height above a walk or roof
MERLON = 0.9
CAP = 0.1
TOWER = 6.0
TOWER_H = 10.0
GATE_W = 8.0
GATE_H = 11.0
UV = 0.5           # the kit's stone tiles every 2 m


# --- Helpers ---------------------------------------------------------------------------------------

def obj(bm, name, mat, smooth=None, recalc=True):
    return L.to_object(bm, name, mat, smooth_angle=smooth, recalc=recalc)


def prism(outline, z0, z1):
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


def box(x0, x1, y0, y1, z0, z1):
    return prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1)


def uv_stone(bm, faces=None, off=(0.0, 0.0)):
    """The kit's rubble stone, tiled at its own scale: courses run level on
    upright faces; tops and bottoms are seen from above."""
    uv = bm.loops.layers.uv["UVMap"]
    for f in (faces or bm.faces):
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = l.vert.co
            if ax == 2:
                l[uv].uv = (p.x * UV + off[0], p.y * UV + off[1])
            else:
                a = p.y if ax == 0 else p.x
                l[uv].uv = (a * UV + off[0], p.z * UV + off[1])
    return bm


def uv_ashlar(bm, band="rock_ashlar"):
    """Dressed stone from the kit's band, tall faces turned so the blocks
    run along their length (quoins, jambs)."""
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS[band]
    hgt = v1 - v0
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        span_a, span_b = hi[a] - lo[a], hi[b] - lo[b]
        long_b = span_b > span_a and span_b * UV > hgt
        for l in f.loops:
            p = l.vert.co
            if long_b:   # tall: u along it, v across, within the band
                l[uv].uv = (p[b] * UV, v0 + min(hgt, (p[a] - lo[a]) * UV))
            else:
                l[uv].uv = (p[a] * UV, v0 + min(hgt, (p[b] - lo[b]) * UV))
    return bm


def rect_uv(bm, rect, a=0, b=2):
    """Planar UVs over axes a, b of the part's bounds into an atlas rect."""
    uv = bm.loops.layers.uv["UVMap"]
    _, u0, v0, u1, v1 = L.RECTS[rect]
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            s = (p[a] - lo[a]) / max(hi[a] - lo[a], 1e-6)
            t = (p[b] - lo[b]) / max(hi[b] - lo[b], 1e-6)
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    return bm


def boards(origin, du, dv, lu, lv, thick=0.06, tile=(2.0, 1.5), rect="ca_planks", back=True):
    """Planking over the rectangle origin + s*du + t*dv (s to lu, t to lv;
    du, dv unit vectors), facing du x dv: the grain along du, the atlas
    cell repeated every `tile` m so the boards keep their width however
    big the surface. With `back` it is a slab `thick` deep, seen from both
    sides (decks, floors); without, a skin seen from the front only."""
    o, du, dv = Vector(origin), Vector(du).normalized(), Vector(dv).normalized()
    nrm = du.cross(dv)
    _, u0, v0, u1, v1 = L.RECTS[rect]
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    layers = [(o, False)] + ([(o - nrm * thick, True)] if back else [])
    for base, flip in layers:
        for i in range(int(math.ceil(lu / tile[0] - 1e-6))):
            for j in range(int(math.ceil(lv / tile[1] - 1e-6))):
                s0, s1 = i * tile[0], min(lu, (i + 1) * tile[0])
                t0, t1 = j * tile[1], min(lv, (j + 1) * tile[1])
                q = [(s0, t0), (s1, t0), (s1, t1), (s0, t1)]
                if flip:
                    q.reverse()
                f = bm.faces.new([bm.verts.new(base + du * a + dv * b) for a, b in q])
                for l, (a, b) in zip(f.loops, q):
                    l[uv].uv = (u0 + (u1 - u0) * (a - s0) / tile[0], v0 + (v1 - v0) * (b - t0) / tile[1])
    if back:   # the edges, a sliver of plank end
        c = [o, o + du * lu, o + du * lu + dv * lv, o + dv * lv]
        for k in range(4):
            a, b = c[k], c[(k + 1) % 4]
            f = bm.faces.new([bm.verts.new(p) for p in (b, a, a - nrm * thick, b - nrm * thick)])
            for l, (x, y) in zip(f.loops, ((0, 0), (1, 0), (1, 0.05), (0, 0.05))):
                l[uv].uv = (u0 + (u1 - u0) * x, v0 + (v1 - v0) * y)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    return bm


def planks(parts, *args, name="planks", **kw):
    parts.append(obj(boards(*args, **kw), name, CA, recalc=False))


def stone(bm, name="stone"):
    return obj(uv_stone(bm), name, STONE)


def ashlar(bm, name="ashlar"):
    return obj(uv_ashlar(bm), name, "MI_RockTrim")


def frame(at, yaw):
    """Matrix placing a part built facing -Y at `at`, turned by yaw (rad)."""
    return Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z")


def arch_outline(w, h, segs=8):
    """A round-headed opening's outline in its own XZ plane (x across, z up,
    CCW seen from -Y): straight jambs, a semicircular head."""
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0)]
    for i in range(segs + 1):
        a = math.pi * i / segs
        pts.append((r * math.cos(a), h - r + r * math.sin(a)))
    return pts


def plate(outline, rect=None, mat=CA, depth=0.0):
    """A flat shape in the XZ plane, facing -Y, pushed out by `depth`."""
    bm = L.new_bm()
    vs = [bm.verts.new((x, -depth, z)) for x, z in outline]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    if rect:
        rect_uv(bm, rect, 0, 2)
    return bm


def opening(parts, at, yaw, w, h, kind="window", surround=0.16, margin=0.25):
    """A window, a doorway or an arrow loop on a wall face: the dark of the
    opening and a dressed-stone surround standing a little proud of the
    face. `at` is the bottom middle of the opening on the face; the face
    looks along -Y turned by yaw."""
    m = frame(at, yaw)
    if kind == "loop":
        # A tall narrow slit in a dressed panel, widened at the ends (cross-slit).
        sur = plate([(-0.22, -margin), (0.22, -margin), (0.22, h + margin), (-0.22, h + margin)], depth=0.05)
        uv_ashlar(sur)
        L.transform(sur, m)
        parts.append(obj(sur, "loop_frame", "MI_RockTrim"))
        slit = plate([(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h), (-w / 2, h)], "ca_void", depth=0.08)
        L.transform(slit, m)
        parts.append(obj(slit, "loop", CA))
        return
    sur = plate(arch_outline(w + 2 * surround, h + surround), depth=0.05)
    uv_ashlar(sur)
    L.transform(sur, m)
    parts.append(obj(sur, kind + "_frame", "MI_RockTrim"))
    hole = plate(arch_outline(w, h), "ca_gate" if kind == "door" else "ca_void", depth=0.08)
    L.transform(hole, m @ Matrix.Translation((0, 0, surround * 0.5)))
    parts.append(obj(hole, kind, CA))


def merlons(parts, x0, x1, y0, y1, z, count, corners=False):
    """A run of merlons along X between x0 and x1 standing on z, each with
    a coping; `count` merlons spaced evenly with half a crenel at each end
    (so runs side by side keep the rhythm), or, round a roof (`corners`),
    with a merlon at each end: the run's first wraps round the corner at
    x0 as an L, and its last is the next run's first."""
    run, t = x1 - x0, y1 - y0
    for k in range(count):
        if corners and count > 1:
            if k == count - 1:
                continue
            c = x0 + 0.45 + (run - 0.9) * k / (count - 1)
            mw = 0.9 if k == 0 else 1.1
        else:
            c = x0 + run * (k + 0.5) / count
            mw = min(1.2, run / count * 0.6)
        if corners and k == 0:
            corner_merlon(parts, x0, y0, 0.9, t, z)
            continue
        parts.append(stone(box(c - mw / 2, c + mw / 2, y0, y1, z, z + MERLON), "merlon"))
        parts.append(ashlar(box(c - mw / 2 - 0.03, c + mw / 2 + 0.03, y0 - 0.03, y1 + 0.03, z + MERLON, z + MERLON + CAP), "coping"))


def corner_merlon(parts, x0, y0, arm, t, z):
    """A merlon wrapping a parapet's corner at (x0, y0): an L with arms
    `arm` long along +X and +Y, as thick as the parapet (t), coped."""
    def ell(e):
        return [(x0 - e, y0 - e), (x0 + arm + e, y0 - e), (x0 + arm + e, y0 + t + e), (x0 + t + e, y0 + t + e),
                (x0 + t + e, y0 + arm + e), (x0 - e, y0 + arm + e)]
    parts.append(stone(prism(ell(0.0), z, z + MERLON), "merlon"))
    parts.append(ashlar(prism(ell(0.03), z + MERLON, z + MERLON + CAP), "coping"))


def parapet_ring(parts, half_x, half_y, z, merlons_per_side, thick=PARAPET_T):
    """A crenellated parapet round a rectangular roof: breastwork, a merlon
    at each corner and `merlons_per_side` between, copings."""
    for side in range(4):
        # Build along X on the -Y side, then turn.
        hx = half_x if side % 2 == 0 else half_y
        hy = half_y if side % 2 == 0 else half_x
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        p = []
        p.append(stone(box(-hx, hx - thick, -hy, -hy + thick, z, z + BREAST), "breast"))
        merlons(p, -hx, hx, -hy, -hy + thick, z + BREAST, merlons_per_side + 2, corners=True)
        for o in p:
            o.data.transform(rot)
        parts += p


def plinth(parts, half_x, half_y, height=1.2, batter=0.35, sides=(0, 1, 2, 3)):
    """A battered (sloping) base round a rectangular footprint."""
    for side in sides:
        hx = half_x if side % 2 == 0 else half_y
        hy = half_y if side % 2 == 0 else half_x
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        bm = L.new_bm()
        a = [bm.verts.new(v) for v in [(-hx - batter, -hy - batter, -0.3), (hx + batter, -hy - batter, -0.3),
                                       (hx, -hy, height), (-hx, -hy, height)]]
        bm.faces.new(a)
        L.transform(bm, rot)
        bm.normal_update()
        parts.append(obj(uv_stone(bm), "plinth", STONE))


def stair(parts, x0, x1, y0, y1, z1, steps):
    """A straight flight of stone steps rising toward +X from the ground at
    x0 to z1 at x1, between y0 and y1: one solid of rubble (a sawtooth
    seen from the side) with a dressed tread on each step, its nosing a
    little proud of the riser."""
    run, rise = (x1 - x0) / steps, z1 / steps
    # The side, as columns one step wide: column k from the ground to its
    # tread, its left edge passing the corner of the tread below.
    B = [(x0 + k * run, -0.3) for k in range(steps + 1)]
    T = [(x0 + k * run, (k + 1) * rise) for k in range(steps)]          # a tread's back corner
    N = [(x0 + (k + 1) * run, (k + 1) * rise) for k in range(steps)]    # its nosing corner
    tris = [(B[0], B[1], N[0]), (B[0], N[0], T[0])]
    for k in range(1, steps):
        tris += [(B[k], B[k + 1], N[k]), (B[k], N[k], N[k - 1]), (N[k - 1], N[k], T[k])]
    # The outline round the side: along the ground, up the back, down the steps.
    prof = list(B)
    for k in reversed(range(steps)):
        prof += [N[k], T[k]]
    bm = L.new_bm()
    va = {p: bm.verts.new((p[0], y0, p[1])) for p in prof}
    vb = {p: bm.verts.new((p[0], y1, p[1])) for p in prof}
    for t in tris:
        bm.faces.new([va[p] for p in t])
        bm.faces.new([vb[p] for p in reversed(t)])
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([va[prof[j]], va[prof[i]], vb[prof[i]], vb[prof[j]]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    parts.append(obj(uv_stone(bm), "stair", STONE, recalc=False))
    for i in range(steps):
        x, z = x0 + i * run, (i + 1) * rise
        parts.append(ashlar(box(x - 0.04, x + run, y0 - 0.03, y1 + 0.03, z - 0.05, z + 0.03), "tread"))


def course(parts, half_x, half_y, z, h=0.22, out=0.06):
    """A dressed string course round a rectangular body."""
    parts.append(ashlar(box(-half_x - out, half_x + out, -half_y - out, half_y + out, z, z + h), "course"))


def quoins(parts, half_x, half_y, z0, z1, w=0.5, out=0.05, corners=((-1, -1), (-1, 1), (1, -1), (1, 1))):
    """Dressed corner stones up a rectangular body's corners."""
    for sx, sy in corners:
        x, y = sx * half_x, sy * half_y
        parts.append(ashlar(box(min(x, x - sx * w) - (out if sx < 0 else 0), max(x, x - sx * w) + (out if sx > 0 else 0),
                                min(y, y - sy * w) - (out if sy < 0 else 0), max(y, y - sy * w) + (out if sy > 0 else 0), z0, z1), "quoin"))


def roof_slab(bm_list, a, b, c, band="ca_shingles", thick=0.08, mat=CA, rect=None):
    """A roof plane a-b (eave) to c (ridge side from a): shingles running
    along the eave, the slope squeezed into the band."""
    a, b, c = Vector(a), Vector(b), Vector(c)
    d = b + (c - a)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    nrm = (b - a).cross(c - a).normalized()
    top = [bm.verts.new(p) for p in (a, b, d, c)]
    bot = [bm.verts.new(p - nrm * thick) for p in (a, b, d, c)]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([top[j], top[i], bot[i], bot[j]])
    along = (b - a).normalized()
    slope = (c - a)
    for f in bm.faces:
        for l in f.loops:
            q = l.vert.co - a
            if rect:
                _, u0, v0, u1, v1 = L.RECTS[rect]
                l[uv].uv = (u0 + (u1 - u0) * max(0, min(1, q.dot(along) / (b - a).length)), v0 + (v1 - v0) * max(0, min(1, q.dot(slope) / slope.length_squared)))
            else:
                _, v0, v1 = L.BANDS[band]
                l[uv].uv = (q.dot(along) * 0.6, v0 + (v1 - v0) * max(0.0, min(1.0, q.dot(slope) / slope.length_squared)))
    bm.normal_update()
    bm_list.append(obj(bm, "roof", mat))


def pyramid_roof(parts, half, eave_z, apex_z, band="ca_shingles", rng=None):
    """A four-sided shingled roof over a square of half-width `half`: each
    side in courses of the band, repeated up the slope so the shingles
    keep their size, shingled underneath too where the eaves are seen
    from below, and a board over each hip."""
    apex = Vector((0, 0, apex_z))
    _, v0, v1 = L.BANDS[band]
    slope = math.hypot(half, apex_z - eave_z)
    strips = max(1, int(round(slope / 3.0)))
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        a = rot @ Vector((-half, -half, eave_z))
        b = rot @ Vector((half, -half, eave_z))
        along = (b - a).normalized()
        nrm = (b - a).cross(apex - a).normalized()
        bm = L.new_bm()
        uv = bm.loops.layers.uv["UVMap"]
        for k in range(strips):
            t0, t1 = k / strips, (k + 1) / strips
            ring = [a.lerp(apex, t0), b.lerp(apex, t0), b.lerp(apex, t1), a.lerp(apex, t1)]
            vv = [v0, v0, v1, v1]
            if k == strips - 1:
                ring, vv = ring[:3], vv[:3]
            for off, flip in ((0.0, False), (-0.06, True)):
                pts = [p + nrm * off for p in ring]
                order = list(range(len(pts)))
                if flip:
                    order.reverse()
                f = bm.faces.new([bm.verts.new(pts[i]) for i in order])
                for l, i in zip(f.loops, order):
                    l[uv].uv = ((ring[i] - a).dot(along) * 0.6, vv[i])
        bm.normal_update()
        parts.append(obj(bm, "roof", CA, recalc=False))
        hip = L.beam(a + Vector((0, 0, 0.02)), apex + Vector((0, 0, 0.05)), 0.16, 0.08, rng=rng, band="wood_dark",
                     up=nrm.lerp(Vector((0, 0, 1)), 0.5))
        parts.append(obj(hip, "hip", "MI_WoodTrim"))


# --- Stone ------------------------------------------------------------------------------------------

def curtain_run(parts, x0, x1, walk=WALL_H):
    """A length of curtain wall along X: the battered foot, the body up to
    the wall walk, the outer parapet with its merlons (one per 2 m), the
    dressed sills in the crenels, a loop in each merlon."""
    h = WALL_T / 2
    parts.append(stone(box(x0, x1, -h, h, -0.3, walk), "wall"))
    bm = L.new_bm()
    q = [bm.verts.new(v) for v in [(x0, -h - 0.35, -0.3), (x1, -h - 0.35, -0.3), (x1, -h, 1.2), (x0, -h, 1.2)]]
    bm.faces.new(q)
    bm.normal_update()
    parts.append(obj(uv_stone(bm), "batter", STONE))
    parts.append(stone(box(x0, x1, -h, -h + PARAPET_T, walk, walk + BREAST), "breast"))
    n = int(round((x1 - x0) / 2.0))
    merlons(parts, x0, x1, -h, -h + PARAPET_T, walk + BREAST, n)
    parts.append(ashlar(box(x0, x1, -h - 0.02, -h + PARAPET_T + 0.02, walk + BREAST - 0.02, walk + BREAST + 0.06), "sill"))
    for k in range(n):
        c = x0 + (x1 - x0) * (k + 0.5) / n
        opening(parts, Vector((c, -h, walk + BREAST + 0.2)), 0.0, 0.07, 0.42, "loop", margin=0.12)


def curtain_wall():
    """4 m of curtain wall."""
    parts = []
    curtain_run(parts, -2.0, 2.0)
    return parts


def curtain_stair():
    """8 m of curtain wall with a straight stone stair up its inner face to
    the wall walk."""
    parts = []
    curtain_run(parts, -4.0, 4.0)
    h = WALL_T / 2
    stair(parts, -3.7, 3.5, h, h + 1.2, WALL_H, 20)
    return parts


def curtain_corner():
    """A plain angle where two curtains meet: 3 m along each wall from the
    corner's middle, the same as a corner tower's, so the two swap on the
    grid. The outside to -Y and -X, walls joining on +X and +Y; a corner
    merlon wrapping the angle, then a merlon on each arm keeping the walls'
    rhythm, a loop in it."""
    parts = []
    h = WALL_T / 2
    e = TOWER / 2   # each arm's end, where the next wall begins
    parts.append(stone(prism([(-h, -h), (e, -h), (e, h), (h, h), (h, e), (-h, e)], -0.3, WALL_H), "wall"))
    # The battered foot round the outer corner, its ends square to run on
    # into the walls' own (so the two never lie in one plane).
    b = 0.35
    for quad in ([(-h - b, -h - b, -0.3), (e, -h - b, -0.3), (e, -h, 1.2), (-h, -h, 1.2)],
                 [(-h - b, e, -0.3), (-h - b, -h - b, -0.3), (-h, -h, 1.2), (-h, e, 1.2)]):
        bm = L.new_bm()
        bm.faces.new([bm.verts.new(v) for v in quad])
        bm.normal_update()
        parts.append(obj(uv_stone(bm), "batter", STONE, recalc=False))
    z = WALL_H + BREAST
    parts.append(stone(box(-h, e, -h, -h + PARAPET_T, WALL_H, z), "breast"))
    parts.append(stone(box(-h, -h + PARAPET_T, -h + PARAPET_T, e, WALL_H, z), "breast"))
    parts.append(ashlar(box(-h - 0.02, e, -h - 0.02, -h + PARAPET_T + 0.02, z - 0.02, z + 0.06), "sill"))
    parts.append(ashlar(box(-h - 0.02, -h + PARAPET_T + 0.02, -h + PARAPET_T + 0.02, e, z - 0.02, z + 0.06), "sill"))
    # The wall beyond starts with half a crenel (0.4) before its first
    # merlon; so this arm ends merlon (1.2), crenel (0.8), and the corner's.
    corner_merlon(parts, -h, -h, e - 0.4 - 1.2 - 0.8 + h, PARAPET_T, z)
    for arm in range(2):
        p = []
        merlons(p, e - 0.4 - 1.2 - 0.4, e, -h, -h + PARAPET_T, z, 1)
        opening(p, Vector((e - 1.0, -h, z + 0.2)), 0.0, 0.07, 0.42, "loop", margin=0.12)
        if arm:   # the -X face: +X arm mirrored across the diagonal
            for o in p:
                o.data.transform(Matrix(((0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))))
                o.data.flip_normals()
        parts += p
    quoins(parts, h, h, 1.2, z - 0.02, corners=((-1, -1),))
    return parts


def tower(corner=False):
    """A square mural tower straddling the wall line: battered foot, quoins,
    a string course at the wall walk, loops on its outer faces, doorways
    onto the wall walks either side (in line: +X and -X; at a corner: +X
    and +Y), a door at the foot from the bailey, a lead roof behind a
    crenellated parapet."""
    parts = []
    s = TOWER / 2
    parts.append(stone(box(-s, s, -s, s, -0.3, TOWER_H), "tower"))
    plinth(parts, s, s)
    quoins(parts, s, s, 1.2, TOWER_H)
    course(parts, s, s, WALL_H - 0.25)
    course(parts, s, s, TOWER_H - 0.22)
    parapet_ring(parts, s, s, TOWER_H, 1)
    roof = box(-s + PARAPET_T, s - PARAPET_T, -s + PARAPET_T, s - PARAPET_T, TOWER_H - 0.05, TOWER_H + 0.02)
    rect_uv(roof, "ca_lead", 0, 1)
    parts.append(obj(roof, "leads", CA))
    # Doorways onto the wall walks, just inside the parapet's line.
    doors = [(math.pi / 2, Vector((s, 0.3, WALL_H))), (-math.pi / 2, Vector((-s, 0.3, WALL_H)))]
    if corner:
        doors = [(math.pi / 2, Vector((s, 0.3, WALL_H))), (math.pi, Vector((-0.3, s, WALL_H)))]
    for yaw, at in doors:
        opening(parts, at, yaw, 1.0, 2.0, "doorway")
    # Loops on the outer faces: the front, and the parts of the sides that stand out of the wall.
    opening(parts, Vector((0, -s, 2.2)), 0.0, 0.1, 1.5, "loop")
    opening(parts, Vector((0, -s, 7.2)), 0.0, 0.1, 1.5, "loop")
    if corner:
        opening(parts, Vector((-s, 0, 2.2)), -math.pi / 2, 0.1, 1.5, "loop")
        opening(parts, Vector((-s, 0, 7.2)), -math.pi / 2, 0.1, 1.5, "loop")
        opening(parts, Vector((s, -2.1, 3.0)), math.pi / 2, 0.1, 1.4, "loop")
        opening(parts, Vector((-2.1, s, 3.0)), math.pi, 0.1, 1.4, "loop")
        opening(parts, Vector((s - 0.0, 2.1, 0.0)), math.pi / 2, 1.1, 2.1, "door")
    else:
        for sx in (-1, 1):
            opening(parts, Vector((sx * s, -2.1, 3.0)), sx * math.pi / 2, 0.1, 1.4, "loop")
            opening(parts, Vector((sx * s, -2.1, 8.0)), sx * math.pi / 2, 0.1, 1.2, "loop")
        opening(parts, Vector((0.0, s, 0.0)), math.pi, 1.1, 2.1, "door")
        opening(parts, Vector((0.0, s, 7.4)), math.pi, 0.7, 1.3, "window")
    return parts


def tower_square():
    return tower(False)


def tower_corner():
    return tower(True)


def gatehouse():
    """A gate tower astride the wall: a round-arched passage through it
    with a portcullis (half raised) and a pair of oak gates standing open
    inward; loops over the gate, a window to the bailey, doorways onto the
    wall walks, a lead roof behind a crenellated parapet."""
    parts = []
    s = GATE_W / 2
    pw, ph = 3.2, 4.4
    r = pw / 2
    # The body: a block with the passage cut up into it. Each face (front
    # and back) is laid as explicit pieces: a pier either side, and above
    # the arch a strip per arch segment up to the top, so every edge is
    # shared and nothing overlaps.
    arch = [(r * math.cos(math.pi - math.pi * i / 12), ph - r + r * math.sin(math.pi - math.pi * i / 12)) for i in range(13)]
    tops = [(x, GATE_H) for x, _ in arch]
    # The outline, round the face: under the left pier, up the passage and over the arch, down, the right pier, the top back to the left.
    ring = [(-s, -0.3), (-r, -0.3)] + arch + [(r, -0.3), (s, -0.3), (s, GATE_H)] + list(reversed(tops)) + [(-s, GATE_H)]
    idx = {p: i for i, p in enumerate(ring)}
    pieces = [[(-s, -0.3), (-r, -0.3), arch[0]], [(-s, -0.3), arch[0], tops[0]], [(-s, -0.3), tops[0], (-s, GATE_H)],
              [(r, -0.3), (s, -0.3), arch[12]], [arch[12], (s, -0.3), (s, GATE_H)], [arch[12], (s, GATE_H), tops[12]]]
    pieces += [[arch[i], arch[i + 1], tops[i + 1], tops[i]] for i in range(12)]
    bm = L.new_bm()
    front = [bm.verts.new((x, -s, z)) for x, z in ring]
    back = [bm.verts.new((x, s, z)) for x, z in ring]
    for pc in pieces:
        bm.faces.new([front[idx[p]] for p in pc])
        bm.faces.new([back[idx[p]] for p in reversed(pc)])
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[i], front[j], back[j], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    parts.append(obj(uv_stone(bm), "gatehouse", STONE, recalc=False))
    plinth(parts, s, s, 1.2, 0.35, sides=(1, 3))
    for x0, x1 in ((-s - 0.35, -r), (r, s + 0.35)):   # the front and back feet either side of the passage
        for sy in (-1, 1):
            bm = L.new_bm()
            y = sy * s
            q = [bm.verts.new(v) for v in [(x0, y + sy * 0.35, -0.3), (x1, y + sy * 0.35, -0.3), (x1, y, 1.2), (x0, y, 1.2)]]
            bm.faces.new(q)
            bm.normal_update()
            parts.append(obj(uv_stone(bm), "plinth", STONE))
    quoins(parts, s, s, 1.2, GATE_H)
    course(parts, s, s, WALL_H - 0.25)
    course(parts, s, s, GATE_H - 0.22)
    parapet_ring(parts, s, s, GATE_H, 2)
    roof = box(-s + PARAPET_T, s - PARAPET_T, -s + PARAPET_T, s - PARAPET_T, GATE_H - 0.05, GATE_H + 0.02)
    rect_uv(roof, "ca_lead", 0, 1)
    parts.append(obj(roof, "leads", CA))
    # Dressed voussoirs round the arch, front and back.
    for sy in (-1, 1):
        ring = [(r * math.cos(a), sy * (s + 0.03), ph - r + r * math.sin(a)) for a in [math.pi * i / 12 for i in range(13)]]
        bm = L.sweep(ring, 0.28, sides=4, band="rock_ashlar", square=True)
        parts.append(obj(bm, "voussoirs", "MI_RockTrim"))
    # The portcullis, half raised, near the front; its grooves in the jambs.
    py = -s + 0.9
    bars = []
    for i in range(7):
        x = -r + 0.25 + i * (pw - 0.5) / 6
        bars.append(L.beam((x, py, 2.4), (x, py, ph + 0.8), 0.12, 0.12, band="wood_dark", up=Vector((1, 0, 0))))
        tip = L.new_bm()
        bmesh.ops.create_cone(tip, cap_ends=True, segments=4, radius1=0.07, radius2=0.0, depth=0.3)
        L.transform(tip, Matrix.Translation((x, py, 2.25)) @ Matrix.Rotation(math.pi, 4, "X"))
        L.uv_box_band(tip, list(tip.faces), "wood_dark")
        parts.append(obj(tip, "spike", "MI_MetalOrnaments"))
    for z in (2.7, 3.5, 4.3):
        bars.append(L.beam((-r + 0.1, py - 0.08, z), (r - 0.1, py - 0.08, z), 0.1, 0.1, band="wood_dark"))
    for bm in bars:
        parts.append(obj(bm, "portcullis", "MI_WoodTrim"))
    for sx in (-1, 1):
        parts.append(ashlar(box(sx * r - 0.12, sx * r + 0.12, py - 0.12, py + 0.12, -0.05, ph - 0.1), "groove"))
    # The gates, hung behind the portcullis and swung back against the passage walls.
    for sx in (-1, 1):
        leaf = plate([(0, 0), (r - 0.05, 0), (r - 0.05, 3.6), (0, 3.6)], "ca_gate", depth=0.0)
        hinge = Vector((sx * (r - 0.05), py + 0.7, 0.05))
        if sx < 0:
            m = Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(82), 4, "Z")
        else:
            m = Matrix.Translation(hinge) @ Matrix.Rotation(math.pi - math.radians(82), 4, "Z")
        L.transform(leaf, m)
        parts.append(obj(leaf, "gate", CA))
        back = plate([(0, 0), (r - 0.05, 0), (r - 0.05, 3.6), (0, 3.6)], "ca_gate", depth=0.0)
        for v in back.verts:
            v.co.y -= 0.12
        for f in back.faces:
            f.normal_flip()
        L.transform(back, m)
        parts.append(obj(back, "gate", CA))
    # Loops over the gate, a window to the bailey, doorways onto the wall walks.
    for x in (-2.7, 2.7):
        opening(parts, Vector((x, -s, 6.4)), 0.0, 0.1, 1.6, "loop")
    opening(parts, Vector((0, -s, 7.6)), 0.0, 0.1, 1.4, "loop")
    opening(parts, Vector((0, s, 7.0)), math.pi, 0.9, 1.6, "window")
    for sx in (-1, 1):
        opening(parts, Vector((sx * s, 0.3, WALL_H)), sx * math.pi / 2, 1.0, 2.0, "doorway")
        opening(parts, Vector((sx * s, -2.6, 8.4)), sx * math.pi / 2, 0.1, 1.2, "loop")
    return parts


def keep():
    """A great tower in the manner of Henry II's: square, on a battered
    plinth, a pilaster buttress up the middle of each face, turrets at the
    corners rising above the parapet, round-headed windows growing larger
    floor by floor (slits at the bottom), twin lead roofs behind the
    parapet, and a forebuilding over the stone stair to the first-floor
    entrance."""
    parts = []
    s = 7.0
    top = 18.0
    parts.append(stone(box(-s, s, -s, s, -0.3, top), "keep"))
    plinth(parts, s, s, 1.8, 0.6)
    course(parts, s, s, 5.6)
    course(parts, s, s, 11.6)
    course(parts, s, s, top - 0.22)
    # Corner turrets.
    t = 1.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (s - t + 0.3), sy * (s - t + 0.3)
            parts.append(stone(box(cx - t, cx + t, cy - t, cy + t, 1.7, top + 3.0), "turret"))
            quoins(parts, t, t, 1.8, top + 3.0)
            for o in parts[-4:]:
                o.data.transform(Matrix.Translation((cx, cy, 0)))
            p = []
            parapet_ring(p, t, t, top + 3.0, 0, thick=0.4)
            for o in p:
                o.data.transform(Matrix.Translation((cx, cy, 0)))
            parts += p
            lead = box(cx - t + 0.4, cx + t - 0.4, cy - t + 0.4, cy + t - 0.4, top + 2.95, top + 3.02)
            rect_uv(lead, "ca_lead", 0, 1)
            parts.append(obj(lead, "leads", CA))
    # Pilaster buttresses up the middle of each face.
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        b = uv_ashlar(box(-0.9, 0.9, -s - 0.35, -s + 0.01, 1.7, top))
        L.transform(b, rot)
        parts.append(obj(b, "pilaster", "MI_RockTrim"))
    # The parapet between the turrets, and its merlons.
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        p = []
        x0, x1 = -s + 2 * t - 0.3, s - 2 * t + 0.3
        p.append(stone(box(x0, x1, -s, -s + PARAPET_T, top, top + BREAST), "breast"))
        merlons(p, x0, x1, -s, -s + PARAPET_T, top + BREAST, 4)
        for o in p:
            o.data.transform(rot)
        parts += p
    # Twin lead roofs, ridges running along X, a gutter between them.
    for sy in (-1, 1):
        y_out, y_in = sy * (s - PARAPET_T), 0.0
        mid = (y_out + y_in) / 2
        for y0, y1 in ((y_out, mid), (y_in, mid)):
            roof_slab(parts, (-s + 0.6, y0, top - 0.1), (s - 0.6, y0, top - 0.1), (-s + 0.6, y1, top + 1.6), rect="ca_lead", mat=CA)
    # Windows: slits at the bottom, small windows at the entrance floor, the hall's larger pairs above.
    for side in range(4):
        rot_yaw = side * math.pi / 2
        rot = Matrix.Rotation(rot_yaw, 4, "Z")
        for x in (-3.4, 3.4):
            at = rot @ Vector((x, -s, 2.6))
            opening(parts, at, rot_yaw, 0.1, 1.6, "loop")
            if not (side == 0 and x > 0):   # the forebuilding covers the front's right hand
                opening(parts, rot @ Vector((x, -s, 7.2)), rot_yaw, 0.7, 1.5, "window")
            for dx in (-0.6, 0.6):
                opening(parts, rot @ Vector((x + dx, -s, 13.0)), rot_yaw, 0.6, 2.0, "window")
    # The forebuilding on the front's right, over the head of the stair.
    fx0, fx1, fy0, fy1, fh = 1.0, 6.8, -s - 4.6, -s, 10.5
    parts.append(stone(box(fx0, fx1, fy0, fy1 + 0.2, -0.3, fh), "forebuilding"))
    p = []
    plinth(p, (fx1 - fx0) / 2, (fy1 - fy0) / 2, 1.2, 0.3, sides=(0, 1, 3))
    quoins(p, (fx1 - fx0) / 2, (fy1 - fy0) / 2, 1.2, fh)
    parapet_ring(p, (fx1 - fx0) / 2, (fy1 - fy0) / 2, fh, 1, thick=0.45)
    cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2
    for o in p:
        o.data.transform(Matrix.Translation((cx, cy, 0)))
    parts += p
    lead = box(fx0 + 0.45, fx1 - 0.45, fy0 + 0.45, fy1 - 0.45, fh - 0.05, fh + 0.02)
    rect_uv(lead, "ca_lead", 0, 1)
    parts.append(obj(lead, "leads", CA))
    opening(parts, Vector((cx, fy0, 6.6)), 0.0, 0.9, 1.8, "window")
    opening(parts, Vector((cx, fy0, 2.4)), 0.0, 0.1, 1.5, "loop")
    # The stair up the front to the forebuilding's door at the first floor.
    y0, y1 = -s - 2.0, -s
    stair(parts, fx0 - 7.4, fx0, y0, y1, 5.4, 18)
    opening(parts, Vector((fx0, (y0 + y1) / 2 + 0.1, 5.4)), -math.pi / 2, 1.1, 2.2, "door")
    return parts


# --- Timber -----------------------------------------------------------------------------------------

def stake(x, y, h, r, seed):
    """A split-log stake, pointed, its foot sunk in the bank."""
    rng = random.Random(seed)
    prof = [(r, -0.4), (r * 0.96, h - 0.38), (0.0, h)]
    bm = L.lathe(prof, 6, band="wood_dark", jitter=0.06, seed=seed, phase=rng.uniform(0, 1))
    L.transform(bm, Matrix.Translation((x, y, 0)))
    return bm


def palisade_run(parts, x0, x1, rng, platform=True):
    """Stakes along X from x0 to x1, two rails behind them, and a fighting
    platform on brackets behind, at a height to look over the points."""
    n = int(round((x1 - x0) / 0.25))
    for i in range(n):
        x = x0 + (i + 0.5) * (x1 - x0) / n
        parts.append(obj(stake(x, 0.0, rng.uniform(4.15, 4.6), rng.uniform(0.115, 0.135), 100 + i), "stake", "MI_WoodTrim", smooth=40))
    for z in (1.0, 3.0):
        parts.append(obj(L.log((x0, 0.2, z), (x1, 0.2, z), 0.08, sides=6, band="wood_dark", seed=int(z * 10)), "rail", "MI_WoodTrim", smooth=40))
    if platform:
        planks(parts, (x0, 0.3, 3.05), (1, 0, 0), (0, 1, 0), x1 - x0, 0.95, 0.1, (2.0, 1.0), name="deck")
        k = int(round((x1 - x0) / 2.0))
        for i in range(k):
            x = x0 + (x1 - x0) * (i + 0.5) / k
            parts.append(obj(L.beam((x, 1.15, -0.3), (x, 1.15, 2.95), 0.14, 0.14, rng=rng, up=Vector((1, 0, 0))), "post", "MI_WoodTrim"))
            parts.append(obj(L.beam((x, 0.25, 2.9), (x, 1.2, 2.9), 0.12, 0.1, rng=rng), "bearer", "MI_WoodTrim"))
            parts.append(obj(L.beam((x, 1.1, 1.6), (x, 0.3, 2.85), 0.09, 0.09, rng=rng, up=Vector((1, 0, 0))), "brace", "MI_WoodTrim"))


def palisade():
    """4 m of palisade: pointed stakes, rails, a fighting platform behind."""
    rng = random.Random(21)
    parts = []
    palisade_run(parts, -2.0, 2.0, rng)
    return parts


def palisade_corner():
    """Where the palisade turns a corner: a stout corner post, the stakes
    running 2 m from it along +X and along +Y (joining palisade lengths
    there), their rails, and the fighting platform turning the corner
    behind them on a post of its own. The outside to -Y and -X."""
    rng = random.Random(25)
    parts = []
    swap = Matrix(((0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))   # the +X arm onto +Y, inside staying inside
    for arm in range(2):
        p = []
        for i in range(8):
            x = 0.25 * (i + 0.5)
            if i > 0:
                p.append(obj(stake(x, 0.0, rng.uniform(4.15, 4.6), rng.uniform(0.115, 0.135), 140 + 10 * arm + i), "stake", "MI_WoodTrim", smooth=40))
        for z in (1.0, 3.0):
            p.append(obj(L.log((0.0, 0.2, z), (2.0, 0.2, z), 0.08, sides=6, band="wood_dark", seed=int(z * 10) + arm), "rail", "MI_WoodTrim", smooth=40))
        if arm:
            for o in p:
                o.data.transform(swap)
                o.data.flip_normals()
        parts += p
    parts.append(obj(stake(0.0, 0.0, 4.8, 0.2, 170), "corner_post", "MI_WoodTrim", smooth=40))
    planks(parts, (0.3, 0.3, 3.05), (1, 0, 0), (0, 1, 0), 1.7, 0.95, 0.1, (2.0, 1.0), name="deck")
    planks(parts, (1.25, 1.25, 3.05), (0, 1, 0), (-1, 0, 0), 0.75, 0.95, 0.1, (2.0, 1.0), name="deck")
    parts.append(obj(L.beam((1.15, 1.15, -0.3), (1.15, 1.15, 2.95), 0.16, 0.16, rng=rng, up=Vector((1, 0, 0))), "post", "MI_WoodTrim"))
    for a, b in (((0.25, 1.15, 2.9), (1.25, 1.15, 2.9)), ((1.15, 0.25, 2.86), (1.15, 1.25, 2.86))):
        parts.append(obj(L.beam(a, b, 0.12, 0.1, rng=rng), "bearer", "MI_WoodTrim"))
    parts.append(obj(L.beam((1.1, 1.1, 1.6), (0.35, 0.35, 2.82), 0.09, 0.09, rng=rng, up=Vector((1, -1, 0))), "brace", "MI_WoodTrim"))
    return parts


def palisade_gate():
    """A timber gate tower over the palisade's gateway: four posts, a
    fighting floor with a plank breastwork and loops, a shingled roof, a
    pair of gates of planks standing open inward."""
    rng = random.Random(23)
    parts = []
    hx, hy = 1.85, 1.4
    floor_z, top_z = 4.4, 5.7
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(obj(L.beam((sx * hx, sy * hy, -0.4), (sx * hx, sy * hy, 6.4), 0.3, 0.3, rng=rng, up=Vector((1, 0, 0))), "post", "MI_WoodTrim"))
    for z in (floor_z - 0.15, 6.3):
        for sy in (-1, 1):
            parts.append(obj(L.beam((-hx - 0.25, sy * hy, z), (hx + 0.25, sy * hy, z), 0.22, 0.22, rng=rng), "beam", "MI_WoodTrim"))
        for sx in (-1, 1):
            parts.append(obj(L.beam((sx * hx, -hy - 0.25, z), (sx * hx, hy + 0.25, z), 0.2, 0.2, rng=rng), "beam", "MI_WoodTrim"))
    # Its sides boarded up to the floor, so the gates close the gap in the palisade.
    for sx in (-1, 1):   # facing out (+-X): runs along +-Y
        planks(parts, (sx * hx, -sx * hy, 0.0), (0, sx, 0), (0, 0, 1), 2 * hy, floor_z - 0.25, 0.08, (hy, 1.5), name="side")
    # The gateway's lintel and braces.
    parts.append(obj(L.beam((-hx, -hy - 0.12, 3.7), (hx, -hy - 0.12, 3.7), 0.24, 0.24, rng=rng), "lintel", "MI_WoodTrim"))
    for sx in (-1, 1):
        parts.append(obj(L.beam((sx * hx, -hy - 0.14, 2.6), (sx * (hx - 0.9), -hy - 0.14, 3.62), 0.14, 0.14, rng=rng, up=Vector((0, 1, 0))), "brace", "MI_WoodTrim"))
    # Floor and plank breastwork with loops.
    planks(parts, (-hx - 0.3, -hy - 0.3, floor_z + 0.12), (1, 0, 0), (0, 1, 0), 2 * hx + 0.6, 2 * hy + 0.6, 0.12, (2.15, 1.2), name="floor")
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        hw = hx + 0.3 if side % 2 == 0 else hy + 0.3
        hd = hy + 0.3 if side % 2 == 0 else hx + 0.3
        wall = boards((-hw, -hd, floor_z + 0.1), (1, 0, 0), (0, 0, 1), 2 * hw - 0.08, top_z - floor_z - 0.1, 0.08, (hw - 0.04, 1.6))
        L.transform(wall, rot)
        parts.append(obj(wall, "breastwork", CA, recalc=False))
        slit = plate([(-0.06, 0), (0.06, 0), (0.06, 0.6), (-0.06, 0.6)], "ca_void", depth=0.02)
        L.transform(slit, rot @ Matrix.Translation((0, -hd, floor_z + 0.5)))
        parts.append(obj(slit, "loop", CA))
    pyramid_roof(parts, hx + 0.75, top_z + 0.55, top_z + 2.3, rng=rng)   # on the posts, open under its eaves
    # The gates, of planks on ledges, open inward.
    for sx in (-1, 1):
        leaf = plate([(0, 0), (1.6, 0), (1.6, 3.5), (0, 3.5)], "ca_gate", depth=0.0)
        if sx < 0:
            m = Matrix.Translation((-1.65, -hy + 0.2, 0.05)) @ Matrix.Rotation(math.radians(80), 4, "Z")
        else:
            m = Matrix.Translation((1.65, -hy + 0.2, 0.05)) @ Matrix.Rotation(math.pi - math.radians(80), 4, "Z")
        L.transform(leaf, m)
        parts.append(obj(leaf, "gate", CA))
        back = plate([(0, 0), (1.6, 0), (1.6, 3.5), (0, 3.5)], "ca_gate", depth=0.0)
        for v in back.verts:
            v.co.y -= 0.1
        for f in back.faces:
            f.normal_flip()
        L.transform(back, m)
        parts.append(obj(back, "gate", CA))
    return parts


def timber_tower():
    """The tower on the motte: a braced frame of posts and rails clad in
    planks, a door at its foot, an overhanging fighting gallery (a hoard)
    with loops, a steep shingled roof."""
    rng = random.Random(29)
    parts = []
    s = 3.0
    wall_top, hoard_top = 8.6, 10.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(obj(L.beam((sx * s, sy * s, -0.3), (sx * s, sy * s, hoard_top), 0.34, 0.34, rng=rng, up=Vector((1, 0, 0))), "post", "MI_WoodTrim"))
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 4, "Z")
        cl = boards((-s, -s - 0.02, -0.3), (1, 0, 0), (0, 0, 1), 2 * s, wall_top + 0.3, back=False, tile=(3.0, 1.6))
        L.transform(cl, rot)
        parts.append(obj(cl, "cladding", CA, recalc=False))
        for z in (0.15, 3.2, 6.0, wall_top):
            b = L.beam((-s, -s - 0.12, z), (s, -s - 0.12, z), 0.2, 0.2, rng=rng)
            L.transform(b, rot)
            parts.append(obj(b, "rail", "MI_WoodTrim"))
        for z0, z1 in ((0.2, 3.1), (3.3, 5.9)):
            if side == 1 and z0 < 1.0:
                continue   # the door's face: its jambs instead
            for d in (-1, 1):
                b = L.beam((d * (s - 0.2), -s - 0.16, z0), (-d * 0.4, -s - 0.16, z1), 0.13, 0.13, rng=rng, up=Vector((0, 1, 0)))
                L.transform(b, rot)
                parts.append(obj(b, "brace", "MI_WoodTrim"))
        # The hoard: joists out, a floor, a plank breastwork with loops.
        for x in (-s + 0.6, 0.0, s - 0.6):
            j = L.beam((x, -s + 0.2, wall_top + 0.05), (x, -s - 0.85, wall_top + 0.05), 0.16, 0.18, rng=rng)
            L.transform(j, rot)
            parts.append(obj(j, "joist", "MI_WoodTrim"))
        hw = s + 0.85
        hb = boards((-hw, -hw, wall_top + 0.15), (1, 0, 0), (0, 0, 1), 2 * hw - 0.08, hoard_top - wall_top - 0.15, 0.08, (hw * 2 / 3, 1.7))
        L.transform(hb, rot)
        parts.append(obj(hb, "hoard", CA, recalc=False))
        for x in (-1.6, 0.0, 1.6):
            slit = plate([(-0.06, 0), (0.06, 0), (0.06, 0.7), (-0.06, 0.7)], "ca_void", depth=0.02)
            L.transform(slit, rot @ Matrix.Translation((x, -s - 0.85, wall_top + 0.5)))
            parts.append(obj(slit, "loop", CA))
    planks(parts, (-s - 0.85, -s - 0.85, wall_top + 0.2), (1, 0, 0), (0, 1, 0), 2 * s + 1.7, 2 * s + 1.7, 0.1, ((2 * s + 1.7) / 3, 1.6), name="hoard_floor")
    pyramid_roof(parts, s + 1.3, hoard_top + 0.1, hoard_top + 4.6, rng=rng)
    # The door, at the head of the bridge: an oak leaf between jambs, under a lintel.
    door = plate([(-0.55, 0), (0.55, 0), (0.55, 2.05), (-0.55, 2.05)], "ca_gate", depth=0.05)
    L.transform(door, Matrix.Translation((s, 0, 0.26)) @ Matrix.Rotation(math.pi / 2, 4, "Z"))
    parts.append(obj(door, "door", CA))
    for y in (-0.7, 0.7):
        parts.append(obj(L.beam((s + 0.1, y, 0.25), (s + 0.1, y, 3.1), 0.16, 0.16, rng=rng, up=Vector((1, 0, 0))), "jamb", "MI_WoodTrim"))
    parts.append(obj(L.beam((s + 0.12, -0.85, 2.4), (s + 0.12, 0.85, 2.4), 0.2, 0.18, rng=rng), "lintel", "MI_WoodTrim"))
    return parts


MOTTE = [(14.0, -0.5), (13.5, 0.0), (12.2, 1.3), (10.6, 3.0), (9.0, 4.8), (7.4, 6.4), (6.6, 6.95), (5.6, 7.15), (0.0, 7.2)]


def motte_turf():
    """The mound's surface: the profile turned, then made uneven."""
    bm = L.lathe(MOTTE, 40, band="ca_turf", r_ref=8.0, scale=0.25)
    for v in bm.verts:   # an uneven mound, not a turned one
        r = math.hypot(v.co.x, v.co.y)
        if 1.0 < r < 13.8:
            k = noise.noise(Vector((v.co.x * 0.18, v.co.y * 0.18, 3.0))) * 0.35
            v.co.z += k * min(1.0, (13.8 - r) / 2.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    return bm


def motte_ground():
    """Height of the motte's surface (or the ground off it) at x, y: a
    function that looks it up on the turf itself."""
    bm = motte_turf()
    tree = BVHTree.FromBMesh(bm)
    bm.free()

    def z(x, y):
        hit = tree.ray_cast(Vector((x, y, 50.0)), Vector((0, 0, -1)))[0]
        return max(0.0, hit.z) if hit else 0.0
    return z


def motte():
    """The motte: a steep earth mound under rough turf, its top flattened
    for the tower, a path trodden up its flank under the bridge."""
    parts = [obj(motte_turf(), "motte", CA, smooth=60)]
    ground = motte_ground()
    # The worn path up the +X flank, where the bridge's trestles stand,
    # laid on the turf a hand's breadth proud of it.
    path = L.new_bm()
    uv = path.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS["ca_earth"]
    rows = []
    for k in range(17):
        r = 13.6 - k * (8.0 / 16)
        rows.append([path.verts.new((r, y, ground(r, y) + (0.06 if abs(y) < 1.0 else 0.03))) for y in (-1.3, -0.65, 0.0, 0.65, 1.3)])
    for k in range(16):
        for i in range(4):
            f = path.faces.new([rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]])
            for l in f.loops:
                p = l.vert.co
                l[uv].uv = (p.x * 0.3, v0 + (v1 - v0) * (0.1 + 0.8 * (p.y / 2.6 + 0.5)))
    path.normal_update()
    for f in path.faces:
        if f.normal.z < 0:
            f.normal_flip()
    parts.append(obj(path, "path", CA, smooth=60, recalc=False))
    return parts


def motte_bridge():
    """The flying bridge from the bailey up to the motte's top, as in the
    Bayeux Tapestry: a plank deck on stringers, carried on trestles that
    stand on the flank, a rail each side. Shares the motte's origin."""
    rng = random.Random(31)
    parts = []
    ground = motte_ground()
    hw = 0.85
    # The deck runs from a sill on the ground at x_low up to a sill on the
    # motte's top at x_high, a little proud of the turf at each end.
    x_low, x_high = 19.8, 5.8
    z_low = 0.45
    z_high = max(ground(x_high, y) for y in (-hw, 0.0, hw)) + 0.42
    def deck_z(x):
        return z_low + (x_low - x) / (x_low - x_high) * (z_high - z_low)
    # Stringers and deck.
    for y in (-hw + 0.1, hw - 0.1):
        parts.append(obj(L.beam((x_low, y, deck_z(x_low) - 0.2), (x_high, y, deck_z(x_high) - 0.2), 0.16, 0.24, rng=rng), "stringer", "MI_WoodTrim"))
    lo, hi = Vector((x_low, -hw, deck_z(x_low))), Vector((x_high, -hw, deck_z(x_high)))
    planks(parts, lo, (0, 1, 0), hi - lo, 2 * hw, (hi - lo).length, 0.08, (2 * hw, 1.5), name="deck")
    # Trestles on the ground and the flank, their feet sunk in it.
    for x in (16.2, 12.6, 9.2):
        top = deck_z(x) - 0.3
        foot = min(ground(x, y) for y in (-hw - 0.4, hw + 0.4))
        for y in (-hw - 0.15, hw + 0.15):
            parts.append(obj(L.beam((x, y * 1.15, foot - 0.3), (x, y, top), 0.2, 0.2, rng=rng, up=Vector((1, 0, 0))), "leg", "MI_WoodTrim"))
        parts.append(obj(L.beam((x, -hw - 0.35, top), (x, hw + 0.35, top), 0.22, 0.22, rng=rng), "cap", "MI_WoodTrim"))
        if top - foot > 1.6:
            parts.append(obj(L.beam((x, -hw - 0.25, foot + 0.3), (x, hw + 0.25, top - 0.4), 0.12, 0.12, rng=rng, up=Vector((1, 0, 0))), "brace", "MI_WoodTrim"))
    # The sills the deck's ends bear on.
    for x, z in ((x_low - 0.2, 0.0), (x_high + 0.25, min(ground(x_high + 0.25, y) for y in (-hw - 0.2, hw + 0.2)))):
        parts.append(obj(L.beam((x, -hw - 0.2, z + 0.02), (x, hw + 0.2, z + 0.02), 0.3, 0.3, rng=rng), "sill", "MI_WoodTrim"))
    # Rails.
    for y in (-hw, hw):
        for x in (x_low, 16.2, 12.6, 9.2, x_high):
            parts.append(obj(L.beam((x, y, deck_z(x)), (x, y, deck_z(x) + 1.05), 0.1, 0.1, rng=rng, up=Vector((1, 0, 0))), "rail_post", "MI_WoodTrim"))
        parts.append(obj(L.beam((x_low, y, deck_z(x_low) + 1.0), (x_high, y, deck_z(x_high) + 1.0), 0.09, 0.09, rng=rng), "rail", "MI_WoodTrim"))
    return parts


BUILDERS = {
    "SE_Curtain_Wall": curtain_wall,
    "SE_Curtain_Stair": curtain_stair,
    "SE_Curtain_Corner": curtain_corner,
    "SE_Tower_Square": tower_square,
    "SE_Tower_Corner": tower_corner,
    "SE_Gatehouse": gatehouse,
    "SE_Keep": keep,
    "SE_Palisade": palisade,
    "SE_Palisade_Corner": palisade_corner,
    "SE_Palisade_Gate": palisade_gate,
    "SE_Timber_Tower": timber_tower,
    "SE_Motte": motte,
    "SE_Motte_Bridge": motte_bridge,
}


# Shown beside a piece in its review renders.
CONTEXT = {"SE_Motte_Bridge": ("SE_Motte",)}


# --- Build, export, review -------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(CA, (1.0, 1.0, 1.0), roughness=0.85, image=CA_TEX)


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
        o.location = ((i % 4) * 32.0, (i // 4) * 32.0, 0)
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
            save_blend(built, os.path.join(HERE, "lords_castle.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for o in built:
            for other in built:   # the bridge is seen on its motte
                other.hide_render = other is not o and other.name not in CONTEXT.get(o.name, ())
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
