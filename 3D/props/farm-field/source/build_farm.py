"""Builds the Farm & Field family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_farm.py [--review DIR] [--lineup DIR/name] [--export] [--only A,B]

Crops are instanced by the thousand (MultiMesh), so they are built to tight
budgets; fences are modular 2 m segments; haystacks, the log pile and the
scarecrow are one-offs. Materials: the farm atlas (MI_Farm, painted by
paint_farm.py) and the village kit's wood, stone and iron trim sheets.
Origin at the ground, front = -Y in Blender (+Z in Godot). Fence segments
and crop rows run along +X.
"""
import math
import os
import random
import sys

# Python salts string hashes per run, and the glTF export path iterates a set
# of strings, so triangles came out in a different order from run to run.
# Pin the seed (re-launching once) so the same source gives the same GLBs.
if os.environ.get("PYTHONHASHSEED") != "0":
    os.environ["PYTHONHASHSEED"] = "0"
    os.execv(sys.executable, [sys.executable] + sys.argv)

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "village-commons", "source")
sys.path.insert(0, COMMONS_SRC)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402

FAMILY = os.path.dirname(HERE)
FARM = "MI_Farm"
FARM_TEX = os.path.join(FAMILY, "textures", "T_Farm_BaseColor.png")
# Farm atlas regions (u0, v0, u1, v1) in Blender UV space (v up).
R = {
    "straw": (0.0, 0.752, 1.0, 0.996),
    "wheat": (0.004, 0.502, 0.496, 0.748),
    "barley": (0.504, 0.502, 0.996, 0.748),
    "cabbage": (0.004, 0.252, 0.496, 0.498),
    "turnip_leaf": (0.504, 0.252, 0.746, 0.498),
    "root": (0.754, 0.252, 0.996, 0.498),
    "flax": (0.004, 0.004, 0.496, 0.248),
    "burlap": (0.504, 0.004, 0.746, 0.248),
    "ears": (0.754, 0.004, 0.996, 0.246),
}
for k, v in R.items():
    L.RECTS["farm_" + k] = (FARM,) + v
L.BANDS["straw"] = (FARM, 0.752, 0.996)
OWN = {FARM: {"doubleSided": True, "dir": os.path.join(FAMILY, "textures"),
              "pbr": {"baseColorTexture": "T_Farm_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.9}}}


def rect_uv(bm, faces, rect, fn):
    """Sets UVs from fn(loop) -> (a, b) in 0..1 of a farm rect."""
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = R[rect]
    for f in faces:
        for l in f.loops:
            a, b = fn(l)
            l[uv].uv = (u0 + (u1 - u0) * min(max(a, 0.0), 1.0), v0 + (v1 - v0) * min(max(b, 0.0), 1.0))


# --- Crops ---------------------------------------------------------------------------------------

def ridge(region, length=2.0, width=0.68, height=0.4, xdiv=6, seed=0, top_bumps=0.1):
    """The dense stand of a grain row: a low, wide, tufted ridge along X.
    Rows sit 0.6 m apart in a field, so neighbours touch and only a thin
    furrow shows: the field reads as one crop. Texture v runs up the
    stalks, so the tops show the painted heads."""
    rng = random.Random(seed)
    prof = [(-0.5, 0.0), (-0.5, 0.3), (-0.44, 0.62), (-0.3, 0.86), (-0.1, 0.98), (0.1, 0.98), (0.3, 0.86), (0.44, 0.62), (0.5, 0.3), (0.5, 0.0)]
    bm = L.new_bm()
    slices = []
    for i in range(xdiv + 1):
        x = -length / 2 + length * i / xdiv
        t = i / xdiv
        # Tufts: two frequencies, matching at both ends so segments join.
        bump = 1.0 + top_bumps * (0.6 * math.sin(t * math.tau * 3 + seed) + 0.4 * math.sin(t * math.tau * 7 + seed * 2))
        ring = []
        for k, (py, pz) in enumerate(prof):
            w = 1.0 + (rng.uniform(-0.06, 0.06) if 0 < i < xdiv and 0 < k < len(prof) - 1 else 0.0)
            z = pz * height * (bump if pz > 0.5 else 1.0)
            ring.append(bm.verts.new((x, py * width * w, z)))
        slices.append(ring)
    for i in range(xdiv):
        for k in range(len(prof) - 1):
            bm.faces.new([slices[i][k], slices[i + 1][k], slices[i + 1][k + 1], slices[i][k + 1]])
    for ring, flip in ((slices[0], True), (slices[-1], False)):
        bm.faces.new(list(reversed(ring)) if flip else ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    top = height * (1 + top_bumps)
    # u wraps twice over the 2 m segment (the stalk bands tile in their half).
    ends = [f for f in bm.faces if abs(f.normal.x) > 0.9]
    sides = [f for f in bm.faces if f not in ends]
    rect_uv(bm, sides, region, lambda l: ((l.vert.co.x / length + 0.5) * 2.0 % 1.0001 if abs(l.vert.co.x) > 1e-4 else 0.0,
                                         l.vert.co.z / top * 0.8))
    # Row ends show the dark stalk bases, not an arch of stalks.
    rect_uv(bm, ends, region, lambda l: (0.5 + l.vert.co.y * 0.5, 0.05 + l.vert.co.z / top * 0.15))
    return bm


def blades(bm, region, length=2.0, width=0.66, height=0.5, count=48, tall=(0.14, 0.26), seed=0, lean=0.3,
           v_tip=0.97, v_base=0.72, ears=0, ear_droop=False, ear_len=0.13):
    """A bristle of thin, slightly bent stems along the row's top: the
    jagged skyline of a standing crop. `ears` of them carry a grain ear at
    the tip (nodding ears for barley)."""
    rng = random.Random(seed + 100)
    picks = set(rng.sample(range(count), min(ears, count)))
    for i in range(count):
        x = -length / 2 + length * (i + rng.random()) / count
        y = rng.uniform(-0.36, 0.36) * width
        base_z = height * (0.98 - 1.6 * (y / width) ** 2) * 0.9
        h = rng.uniform(*tall) * (1.25 if i in picks else 1.0)
        a = rng.uniform(0, math.tau)
        w = rng.uniform(0.008, 0.014)
        dx, dy = math.cos(a) * w, math.sin(a) * w
        lx, ly = rng.uniform(-lean, lean), rng.uniform(-lean, lean)
        mid = Vector((x + lx * h * 0.35, y + ly * h * 0.35, base_z + h * 0.55))
        tip = Vector((x + lx * h, y + ly * h, base_z + h))
        f = L.new_bm()
        p0, p1 = Vector((x - dx, y - dy, base_z - 0.04)), Vector((x + dx, y + dy, base_z - 0.04))
        m0, m1 = mid + Vector((-dx * 0.8, -dy * 0.8, 0)), mid + Vector((dx * 0.8, dy * 0.8, 0))
        vs = [f.verts.new(p) for p in (p0, p1, m1, m0, tip)]
        f.faces.new([vs[0], vs[1], vs[2], vs[3]])
        f.faces.new([vs[3], vs[2], vs[4]])
        uu = (i * 0.137) % 0.9 + 0.05
        rect_uv(f, f.faces, region, lambda l: (uu, v_base if l.vert.co.z < base_z else (v_tip if l.vert.co.z > base_z + h * 0.8 else (v_base + v_tip) * 0.5)))
        L.merge_bm(bm, f)
        if i in picks:
            d = (tip - mid).normalized()
            if ear_droop:
                d = Vector((d.x * 0.6 + rng.uniform(-0.2, 0.2), d.y * 0.6 + (0.7 if rng.random() < 0.5 else -0.7), -0.35))
            L.merge_bm(bm, ear(tip - d.normalized() * 0.01, d, length=ear_len * rng.uniform(0.9, 1.1), r=0.019))
            if ear_droop:
                e_tip = tip + d.normalized() * ear_len
                a2 = L.new_bm()
                vs2 = [a2.verts.new(p) for p in (e_tip + Vector((0, 0, 0.006)), e_tip - Vector((0, 0, 0.006)), e_tip + d.normalized() * 0.1 + Vector((0, 0, -0.03)))]
                a2.faces.new(vs2)
                rect_uv(a2, a2.faces, region, lambda l: (0.5, v_tip))
                L.merge_bm(bm, a2)
    return bm


def ear(base, direction, length=0.13, r=0.024, segs=4):
    bm = L.lathe([(0.0, 0.0), (r * 0.7, length * 0.12), (r, length * 0.45), (r * 0.7, length * 0.8), (0.0, length)], segs, rect="farm_ears")
    d = Vector(direction).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    L.transform(bm, Matrix.Translation(base) @ rot)
    return bm


def crop_wheat():
    bm = ridge("wheat", seed=1)
    blades(bm, "wheat", height=0.4, seed=1, count=34, tall=(0.12, 0.22), ears=7)
    return [L.to_object(bm, "wheat", FARM, smooth_angle=60, recalc=False)]


def crop_barley():
    """Barley: paler, lower, nodding heads with fine awns."""
    bm = ridge("barley", seed=2, height=0.36)
    blades(bm, "barley", height=0.36, seed=2, count=34, tall=(0.1, 0.2), ears=7, ear_droop=True, ear_len=0.12)
    return [L.to_object(bm, "barley", FARM, smooth_angle=60, recalc=False)]


def crop_flax():
    """Flax: slender stalks, a little taller, blue flowers on the surface."""
    rng = random.Random(3)
    bm = ridge("flax", seed=3, width=0.6, height=0.48, top_bumps=0.08)
    blades(bm, "flax", width=0.6, height=0.48, seed=3, tall=(0.12, 0.22), count=30, lean=0.2, v_tip=0.62, v_base=0.3)
    for i in range(9):
        x = -0.9 + i * 0.22 + rng.uniform(-0.05, 0.05)
        y = rng.uniform(-0.18, 0.18)
        c = Vector((x, y, 0.48 * (1.0 - 1.4 * (y / 0.33) ** 2 * 0.3) + rng.uniform(0.1, 0.2)))
        f = L.new_bm()
        ctr = f.verts.new(c + Vector((0, 0, 0.008)))
        ring = [f.verts.new(c + Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0))) for a in [k * math.tau / 5 for k in range(5)]]
        for k in range(5):
            f.faces.new([ctr, ring[k], ring[(k + 1) % 5]])
        rect_uv(f, f.faces, "flax", lambda l, x0=c.x: (0.2 + (l.vert.co.x - x0) * 0.5, 0.92))
        L.merge_bm(bm, f)
    return [L.to_object(bm, "flax", FARM, smooth_angle=60, recalc=False)]


def leaf_strip(base, direction, length, width, cup=0.04, segs=2, rect="cabbage", lift=0.0, tip=0.35, round_tip=0.0):
    """A cupped leaf from base along direction: a small grid, UV base at the
    bottom of its atlas region. `tip`: the tip's width (of `width`);
    `round_tip` pushes the midrib past the tip's corners (a rounded end)."""
    bm = L.new_bm()
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    rows = []
    for j in range(segs + 1):
        t = j / segs
        w = width * math.sin(math.pi * (0.25 + 0.75 * t)) if t < 1 else width * tip
        row = []
        for s in (-1.0, 0.0, 1.0):
            reach = length * (t + (round_tip * (1 - s * s) if t == 1 else 0.0))
            p = Vector(base) + d * reach + side * s * w * 0.5 + up * (cup * (1 - s * s) * -1 + lift * t * t)
            row.append(bm.verts.new(p))
        rows.append(row)
    for j in range(segs):
        for k in range(2):
            bm.faces.new([rows[j][k], rows[j][k + 1], rows[j + 1][k + 1], rows[j + 1][k]])
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = R[rect]
    for f in bm.faces:
        for l in f.loops:
            j = next(i for i, row in enumerate(rows) if l.vert in row)
            k = rows[j].index(l.vert)
            l[uv].uv = (u0 + (u1 - u0) * (0.25 + 0.25 * k), v0 + (v1 - v0) * (j / segs) * 0.95)
    bm.normal_update()
    return bm


def crop_cabbage():
    """A round, pale heart wrapped by four cupped inner leaves, and six broad,
    round-tipped outer leaves spreading low (pale at the base, darker at the
    edge), so a field reads as rows of cabbages, not rosettes."""
    rng = random.Random(4)
    bm = L.lathe([(0.0, 0.02), (0.085, 0.035), (0.13, 0.09), (0.125, 0.15), (0.085, 0.2), (0.0, 0.22)], 8, rect="farm_cabbage")
    # The heart takes the pale lower quarter of the leaf region.
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = R["cabbage"]
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = (u0 + (u1 - u0) * (0.3 + 0.4 * (l[uv].uv.x % 1.0)), v0 + (v1 - v0) * 0.22 * min(1.0, l.vert.co.z / 0.22))
    for k in range(4):
        a = k * math.tau / 4 + 0.4 + rng.uniform(-0.15, 0.15)
        d = Vector((math.cos(a), math.sin(a), 1.5))
        base = Vector((math.cos(a) * 0.07, math.sin(a) * 0.07, 0.02))
        L.merge_bm(bm, leaf_strip(base, d, rng.uniform(0.17, 0.2), 0.22, cup=0.06, lift=-0.05, tip=0.7, round_tip=0.08))
    for k in range(6):
        a = k * math.tau / 6 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(0.35, 0.55)))
        base = Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.03))
        L.merge_bm(bm, leaf_strip(base, d, rng.uniform(0.25, 0.3), 0.3, cup=0.06, segs=3, lift=-0.06, tip=0.75, round_tip=0.1))
    return [L.to_object(bm, "cabbage", FARM, smooth_angle=60, recalc=False)]


def crop_turnip():
    rng = random.Random(5)
    bm = L.lathe([(0.0, -0.02), (0.06, 0.0), (0.075, 0.045), (0.05, 0.085), (0.015, 0.1), (0.0, 0.1)], 6, rect="farm_root")
    # Root UVs: purple shoulders at the top, so flip the lathe's v.
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = R["root"]
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = (l[uv].uv.x, v0 + (v1 - v0) * min(1.0, max(0.0, (l.vert.co.z + 0.02) / 0.12)))
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0))
        L.merge_bm(bm, leaf_strip(Vector((0, 0, 0.09)), d, rng.uniform(0.24, 0.3), 0.1, cup=0.02, segs=3, rect="turnip_leaf", lift=-0.12))
    return [L.to_object(bm, "turnip", FARM, smooth_angle=55, recalc=False)]


# --- Fences and gates (2 m segments along +X; the post is at x = 0) ------------------------------

SEG = 2.0


def weave_panel(x0, x1, z0, z1, courses, xdiv, stakes, amp=0.024, seed=0, thick=0.012):
    """A woven hurdle: courses of rods bending in and out between stakes.
    Two faces `thick` either side of the weave (a hurdle has body), so each
    side is a front face with its own normals (see lift_normals); each
    course is a strip of pale wood grain."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS["wood_light"]
    for side in (-1.0, 1.0):
        rng = random.Random(seed)  # the same weave on both faces
        grid = []
        for c in range(courses + 1):
            z = z0 + (z1 - z0) * c / courses
            row = []
            for i in range(xdiv + 1):
                x = x0 + (x1 - x0) * i / xdiv
                phase = (x - x0) / ((x1 - x0) / (len(stakes) - 1)) * math.pi
                y = amp * math.sin(phase) * (1 if c % 2 else -1) + rng.uniform(-0.004, 0.004) + side * thick
                row.append(bm.verts.new((x, y, z + rng.uniform(-0.01, 0.01) * (0 < c < courses))))
            grid.append(row)
        for c in range(courses):
            uo = rng.uniform(0, 1)
            for i in range(xdiv):
                quad = [grid[c][i], grid[c][i + 1], grid[c + 1][i + 1], grid[c + 1][i]]
                f = bm.faces.new(quad if side < 0 else quad[::-1])  # -Y face, then +Y face
                for l in f.loops:
                    cc = c if l.vert in grid[c] else c + 1
                    ii = grid[cc].index(l.vert)
                    l[uv].uv = (uo + (x0 + (x1 - x0) * ii / xdiv) * 0.6, v0 + (v1 - v0) * (0.15 if cc == c else 0.85))
    bm.normal_update()
    return bm


LIFT = 0.8  # how far a hurdle's normals tilt up (added to the unit normal)


def lift_normals(obj):
    """Marks the faces whose normals tilt up, as round rods catch the sky and
    a high sun: a solid hurdle seen from its shaded side would otherwise go
    near black in game (Cycles hides this; Godot's sky ambient doesn't).
    The tilt is applied in build(), after the weighted-normals pass that
    would otherwise overwrite it."""
    attr = obj.data.attributes.new("lift", "BOOLEAN", "FACE")
    for i in range(len(obj.data.polygons)):
        attr.data[i].value = True
    return obj


def apply_lift(obj):
    """Tilts the normals of faces marked by lift_normals (see there)."""
    me = obj.data
    attr = me.attributes.get("lift")
    if attr is None:
        return
    normals = [Vector(n.vector) for n in me.corner_normals]
    for poly in me.polygons:
        if attr.data[poly.index].value:
            for li in poly.loop_indices:
                normals[li] = (normals[li] + Vector((0, 0, LIFT))).normalized()
    me.normals_split_custom_set(normals)
    me.attributes.remove(attr)


def stake(x, y, z_top, r=0.026, seed=0, tilt=0.03):
    rng = random.Random(seed)
    top = Vector((x + rng.uniform(-tilt, tilt), y + rng.uniform(-tilt, tilt), z_top + rng.uniform(-0.04, 0.04)))
    return L.log((x, y, -0.06), top, r, sides=5, band="wood_dark", taper=0.85, jitter=0.12, seed=seed, rings=1)


def fence_wattle():
    """Hamlet: a woven wattle hurdle between rough stakes."""
    xs = [0.06, 0.53, 1.0, 1.47, 1.94]
    parts = [lift_normals(L.to_object(weave_panel(0.02, SEG - 0.02, 0.06, 0.9, 7, 12, xs, seed=1), "weave", "MI_WoodTrim", smooth_angle=50, recalc=False))]
    for k, x in enumerate(xs):
        parts.append(L.to_object(stake(x, 0.0, 1.0, seed=10 + k), "stake", "MI_WoodTrim", smooth_angle=55))
    return parts


def rail(x0, x1, z, r=0.05, seed=0, sag=0.025):
    return L.log((x0, 0.0, z), (x1, 0.0, z - 0.01), r, sides=5, band="wood_light", taper=0.92, jitter=0.1, bend=0.0, seed=seed, rings=2)


def fence_rail():
    """Village: a split-rail fence, a square post and two sagging rails."""
    rng = random.Random(2)
    parts = [L.to_object(L.beam((0, 0, -0.08), (0.01, 0.0, 1.05), 0.13, 0.13, bevel=0.015, rng=rng), "post", "MI_WoodTrim", smooth_angle=40)]
    for k, z in enumerate((0.45, 0.82)):
        bm = rail(0.04, SEG + 0.04, z, seed=20 + k)
        # A little sag mid-span.
        for v in bm.verts:
            t = v.co.x / SEG
            v.co.z -= 0.03 * math.sin(math.pi * max(0.0, min(1.0, t)))
        parts.append(L.to_object(bm, "rail", "MI_WoodTrim", smooth_angle=55))
    return parts


def pale(x, h, w=0.085, t=0.026, seed=0):
    rng = random.Random(seed)
    h += rng.uniform(-0.03, 0.03)
    pts = [(0.0, 0.0), (w, 0.0), (w, h - 0.07), (w / 2, h), (0.0, h - 0.07)]
    bm = L.new_bm()
    vs = [bm.verts.new((x - w / 2 + px, -t / 2, pz)) for px, pz in pts]
    f = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)], vec=(0, t, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    _, v0, v1 = L.BANDS["wood_light"]
    uo = rng.uniform(0, 1)
    uv = bm.loops.layers.uv["UVMap"]
    for fc in bm.faces:
        for l in fc.loops:
            p = l.vert.co
            # Grain runs up the pale: height along u, width across the band.
            l[uv].uv = (uo + p.z * L.UV_PER_M, v0 + (v1 - v0) * (0.3 + (p.x - x + w / 2) / w * 0.4))
    return bm


def fence_paled():
    """Town: a paled fence, pointed pales on two rails, a capped post."""
    rng = random.Random(3)
    parts = [L.to_object(L.beam((0, 0, -0.08), (0, 0.0, 1.12), 0.13, 0.13, bevel=0.02, rng=rng), "post", "MI_WoodTrim", smooth_angle=40)]
    capm = L.lathe([(0.0, 0.0), (0.1, 0.0), (0.1, 0.03), (0.0, 0.11)], 4, band="wood_dark", phase=math.pi / 4)
    L.transform(capm, Matrix.Translation((0, 0, 1.12)))
    parts.append(L.to_object(capm, "cap", "MI_WoodTrim", smooth_angle=20))
    for z in (0.25, 0.8):
        parts.append(L.to_object(L.beam((0.06, -0.055, z), (SEG + 0.06, -0.055, z), 0.05, 0.08, bevel=0.01, rng=rng), "rail", "MI_WoodTrim", smooth_angle=40))
    bm = L.new_bm()
    for k in range(9):
        L.merge_bm(bm, pale(0.2 + k * 0.2, 1.0, seed=30 + k))
    L.transform(bm, Matrix.Translation((0, -0.095, 0.03)))
    parts.append(L.to_object(bm, "pales", "MI_WoodTrim", smooth_angle=30))
    return parts


def gate_wattle():
    """Hamlet gate: a hurdle on its own stake, swung half open and tied."""
    parts = [L.to_object(stake(0.06, 0.0, 1.05, seed=40, r=0.032), "stake", "MI_WoodTrim", smooth_angle=55)]
    xs = [0.12, 0.58, 1.04, 1.5]
    panel = weave_panel(0.1, 1.55, 0.1, 0.92, 6, 7, xs, seed=4)
    stakes = L.new_bm()
    for k, x in enumerate(xs):
        L.merge_bm(stakes, stake(x, 0.0, 0.98, seed=50 + k, r=0.022))
    for bm in (panel, stakes):
        L.transform(bm, Matrix.Rotation(-0.55, 4, "Z"))
        L.transform(bm, Matrix.Translation((0.06, 0, 0)))
    parts.append(lift_normals(L.to_object(panel, "hurdle", "MI_WoodTrim", smooth_angle=50, recalc=False)))
    parts.append(L.to_object(stakes, "hurdle_stakes", "MI_WoodTrim", smooth_angle=55, recalc=False))
    tie = L.helix((0, 0, 0), 0.05, 0.75, 0.88, 3, count_per_turn=8, axis="Z")
    parts.append(L.to_object(L.sweep([p + Vector((0.06, 0, 0)) for p in tie], 0.011, sides=5, band="wood_light", twist=40.0, ridges=2, ridge_depth=0.18), "tie", "MI_WoodTrim", smooth_angle=70, recalc=False))
    return parts


def gate_rail():
    """Village gate: a five-bar field gate with a brace, hung on its post, ajar."""
    rng = random.Random(5)
    parts = [L.to_object(L.beam((0, 0, -0.08), (0, 0.0, 1.2), 0.16, 0.16, bevel=0.02, rng=rng), "hangpost", "MI_WoodTrim", smooth_angle=40)]
    g = L.new_bm()
    width, h = 1.9, 1.0
    for z in (0.18, 0.38, 0.58, 0.78, 0.98):
        L.merge_bm(g, L.beam((0.08, 0, z), (width, 0, z), 0.05, 0.08, bevel=0.008, rng=rng))
    for x in (0.08, width - 0.03):
        L.merge_bm(g, L.beam((x, 0, 0.1), (x, 0, h + 0.04), 0.07, 0.08, bevel=0.01, rng=rng))
    L.merge_bm(g, L.beam((0.1, 0, 0.2), (width - 0.05, 0, h - 0.02), 0.045, 0.07, bevel=0.008, rng=rng))
    L.transform(g, Matrix.Rotation(-0.35, 4, "Z"))
    parts.append(L.to_object(g, "gate", "MI_WoodTrim", smooth_angle=40))
    hinges = L.new_bm()
    for z in (0.3, 0.88):
        L.merge_bm(hinges, L.sweep([(0.07, 0.0, z), (0.4, -0.14, z)], 0.014, sides=4, rect="iron_bar", square=True))
    parts.append(L.to_object(hinges, "hinges", "MI_MetalOrnaments", smooth_angle=40))
    return parts


def gate_paled():
    """Town gate: a framed paled gate on a capped post, closed, iron-hinged."""
    rng = random.Random(6)
    parts = [L.to_object(L.beam((0, 0, -0.08), (0, 0.0, 1.22), 0.15, 0.15, bevel=0.02, rng=rng), "hangpost", "MI_WoodTrim", smooth_angle=40)]
    capm = L.lathe([(0.0, 0.0), (0.11, 0.0), (0.11, 0.03), (0.0, 0.12)], 4, band="wood_dark", phase=math.pi / 4)
    L.transform(capm, Matrix.Translation((0, 0, 1.22)))
    parts.append(L.to_object(capm, "cap", "MI_WoodTrim", smooth_angle=20))
    for z in (0.22, 0.82):
        parts.append(L.to_object(L.beam((0.1, -0.05, z), (SEG - 0.04, -0.05, z), 0.05, 0.09, bevel=0.01, rng=rng), "ledger", "MI_WoodTrim", smooth_angle=40))
    parts.append(L.to_object(L.beam((0.12, -0.05, 0.26), (SEG - 0.08, -0.05, 0.78), 0.045, 0.08, bevel=0.008, rng=rng), "brace", "MI_WoodTrim", smooth_angle=40))
    bm = L.new_bm()
    for k in range(9):
        L.merge_bm(bm, pale(0.2 + k * 0.2, 1.06 - abs(k - 4) * -0.02, seed=60 + k))
    L.transform(bm, Matrix.Translation((0, -0.09, 0.04)))
    parts.append(L.to_object(bm, "pales", "MI_WoodTrim", smooth_angle=30))
    hinges = L.new_bm()
    for z in (0.22, 0.82):
        L.merge_bm(hinges, L.sweep([(0.06, -0.08, z), (0.5, -0.08, z)], 0.016, sides=4, rect="iron_strap", square=True))
    parts.append(L.to_object(hinges, "hinges", "MI_MetalOrnaments", smooth_angle=40))
    return parts


# --- Haystacks, log pile, scarecrow ----------------------------------------------------------------

def straw_lathe(profile, segs, jitter=0.03, seed=0):
    return L.lathe(profile, segs, band="straw", jitter=jitter, seed=seed)


def haycock():
    """A round haycock on a stake, roped over the top with stone weights."""
    rng = random.Random(7)
    prof = [(0.0, -0.02), (1.02, -0.02), (1.06, 0.14), (1.0, 0.5), (0.86, 1.0), (0.62, 1.48), (0.32, 1.82), (0.0, 1.94)]
    parts = [L.to_object(straw_lathe(prof, 14, jitter=0.045, seed=1), "hay", FARM, smooth_angle=60, recalc=False)]
    parts.append(L.to_object(L.log((0.03, 0.0, 1.2), (0.1, 0.06, 2.42), 0.045, sides=6, band="wood_dark", taper=0.7, jitter=0.1, seed=3, rings=2), "stake", "MI_WoodTrim", smooth_angle=55))
    # Two ropes over the top, each end weighted with a stone.
    for k in range(2):
        a = k * math.pi / 2 + 0.3
        pts = []
        for i in range(13):
            t = -1.0 + 2.0 * i / 12
            ang = t * 1.25
            r = 0.04 + 0.92 * abs(math.sin(ang))
            z = 1.97 * math.cos(ang * 0.98) ** 1.1 if abs(ang) < 1.5 else 0.2
            pts.append(Vector((math.cos(a) * r * (1 if t >= 0 else -1), math.sin(a) * r * (1 if t >= 0 else -1), z)))
        # Push the rope onto the hay surface.
        fixed = []
        for p in pts:
            d = Vector((p.x, p.y, 0))
            rr = d.length
            prof_r = 1.0 * math.sqrt(max(0.0, 1 - (p.z / 1.98) ** 2)) + 0.03
            if rr > 1e-4:
                d.normalize()
                fixed.append(Vector((d.x * prof_r, d.y * prof_r, p.z)))
            else:
                fixed.append(Vector((0, 0, 1.97)))
        parts.append(L.to_object(L.sweep(fixed, 0.017, sides=5, band="wood_light", twist=40.0, ridges=2, ridge_depth=0.18), "rope", "MI_WoodTrim", smooth_angle=70, recalc=False))
        for end in (fixed[0], fixed[-1]):
            parts.append(L.to_object(L.stone(end + Vector((0, 0, -0.12)), (0.16, 0.14, 0.13), seed=70 + k * 2 + (end is fixed[0]), rough=0.3, detail=1), "weight", "MI_RockTrim", smooth_angle=35))
    return parts


def hayrick():
    """A rectangular hayrick with a thatched ridge top, roped and pegged."""
    parts = []
    length, width, wall, top = 1.9, 1.25, 1.0, 1.85
    bm = L.new_bm()
    prof = [(-0.47, 0.0), (-0.55, 0.38), (-0.53, 0.78), (-0.44, 1.0), (-0.22, 1.42), (0.0, top / wall), (0.22, 1.42), (0.44, 1.0), (0.53, 0.78), (0.55, 0.38), (0.47, 0.0)]
    slices = []
    nx = 8
    rng = random.Random(8)
    for i in range(nx + 1):
        t = i / nx
        x = -length / 2 + length * t
        end = 1.0 - 0.32 * (abs(2 * t - 1) ** 2.2)
        slices.append([bm.verts.new((x, py * width * end * (1 + rng.uniform(-0.03, 0.03) * (0 < i < nx)), pz * wall * (1 if pz < 1.01 else end ** 0.3)))
                       for (py, pz) in prof])
    for i in range(nx):
        for k in range(len(prof) - 1):
            bm.faces.new([slices[i][k], slices[i + 1][k], slices[i + 1][k + 1], slices[i][k + 1]])
    for ring, flip in ((slices[0], True), (slices[-1], False)):
        bm.faces.new(list(reversed(ring)) if flip else ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS["straw"]
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            if abs(f.normal.x) > 0.8:
                l[uv].uv = (p.y * 0.5, v0 + (v1 - v0) * min(1.0, p.z / top))
            else:
                l[uv].uv = (p.x * 0.5 + (0.3 if p.y > 0 else 0.0), v0 + (v1 - v0) * min(1.0, (p.z + abs(p.y) * 0.4) / top))
    parts.append(L.to_object(bm, "rick", FARM, smooth_angle=40, recalc=False))
    # A ridge rope and pegged ropes down the sides.
    parts.append(L.to_object(L.sweep([(-length * 0.47, 0, top - 0.02), (0, 0, top + 0.02), (length * 0.47, 0, top - 0.02)], 0.02, sides=5, band="wood_light", twist=40.0, ridges=2, ridge_depth=0.18), "ridge_rope", "MI_WoodTrim", smooth_angle=70, recalc=False))
    for x in (-0.55, 0.0, 0.55):
        for sy in (-1, 1):
            pts = [(x, 0.0, top + 0.01), (x, sy * 0.36 * width, wall + 0.03), (x, sy * 0.53 * width, 0.45), (x, sy * 0.56 * width, 0.08)]
            parts.append(L.to_object(L.sweep(pts, 0.012, sides=4, band="wood_light"), "rope", "MI_WoodTrim", smooth_angle=70, recalc=False))
            parts.append(L.to_object(L.log((x, sy * 0.58 * width, -0.05), (x, sy * 0.62 * width, 0.16), 0.025, sides=4, band="wood_dark", taper=0.6, jitter=0.1, seed=int(x * 10) + sy, rings=1), "peg", "MI_WoodTrim", smooth_angle=50))
    return parts


def sheaf(base, lean_to, seed=0, size=1.65):
    rng = random.Random(seed)
    bm = straw_lathe([(0.0, 0.0), (0.085, 0.0), (0.07, 0.22), (0.05, 0.3), (0.075, 0.42), (0.06, 0.62), (0.0, 0.66)], 5, jitter=0.06, seed=seed)
    band = L.lathe([(0.055, 0.29), (0.056, 0.34)], 5, band="wood_light")
    L.merge_bm(bm, band)
    for k in range(3):
        a = k * math.tau / 3 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1.0))
        L.merge_bm(bm, ear(Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0.6)), d, length=0.11, r=0.02))
    L.transform(bm, Matrix.Scale(size, 4))
    d = (Vector(lean_to) - Vector(base))
    d.z = 0
    tilt = 0.22
    axis = Vector((-d.y, d.x, 0)).normalized() if d.length > 1e-4 else Vector((1, 0, 0))
    L.transform(bm, Matrix.Translation(base) @ Matrix.Rotation(tilt, 4, axis))
    return bm


def stooks():
    """Three stooks of sheaves stood together in the stubble to dry."""
    parts = []
    for s_i, (cx, cy) in enumerate(((-0.55, -0.4), (0.62, -0.2), (0.0, 0.6))):
        bm = L.new_bm()
        n = 5
        for k in range(n):
            a = k * math.tau / n + s_i
            base = Vector((cx + math.cos(a) * 0.24, cy + math.sin(a) * 0.24, 0.0))
            L.merge_bm(bm, sheaf(base, (cx, cy, 0), seed=s_i * 10 + k))
        parts.append(L.to_object(bm, "stook", FARM, smooth_angle=55, recalc=False))
    return parts


def log_pile():
    """Seasoning logs stacked between stakes, a chopping block with an axe,
    and split wood beside it."""
    rng = random.Random(9)
    parts = []
    r = 0.15
    rows = [(-0.36, 0.0, 0.15), (0.0, 0.0, 0.15), (0.36, 0.0, 0.15), (-0.18, 0.0, 0.42), (0.18, 0.0, 0.42), (0.0, 0.0, 0.69)]
    for k, (y, _, z) in enumerate(rows):
        L_ = rng.uniform(1.7, 1.95)
        x0 = -0.95 + rng.uniform(-0.08, 0.08)
        parts.append(L.to_object(L.log((x0, y, z), (x0 + L_, y + rng.uniform(-0.05, 0.05), z + rng.uniform(-0.02, 0.02)), r * rng.uniform(0.9, 1.1), sides=8, band="wood_dark", taper=0.9, jitter=0.07, seed=100 + k, rings=2), "log", "MI_WoodTrim", smooth_angle=55))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(L.to_object(L.log((sx * 0.62, sy * 0.58, -0.05), (sx * 0.64, sy * 0.6, 0.75), 0.04, sides=5, band="wood_dark", taper=0.8, jitter=0.1, seed=110 + sx + sy * 3, rings=1), "stake", "MI_WoodTrim", smooth_angle=55))
    # Chopping block, axe and split logs, in front.
    parts.append(L.to_object(L.log((1.25, -0.45, -0.02), (1.25, -0.45, 0.48), 0.24, sides=9, band="wood_dark", taper=0.95, jitter=0.05, seed=120, rings=1), "block", "MI_WoodTrim", smooth_angle=55))
    handle = L.log((1.22, -0.45, 0.46), (1.0, -0.62, 1.05), 0.022, sides=5, band="wood_light", taper=0.9, jitter=0.03, seed=121, rings=1)
    parts.append(L.to_object(handle, "axe_handle", "MI_WoodTrim", smooth_angle=50))
    head = L.box((0.18, 0.04, 0.13), "wood_dark", bevel=0.008, rng=rng)
    uvh = head.loops.layers.uv["UVMap"]
    _, u0, v0, u1, v1 = L.RECTS["iron_plate"]
    for f in head.faces:
        for l in f.loops:
            l[uvh].uv = (u0 + (u1 - u0) * (l.vert.co.x / 0.18 + 0.5), v0 + (v1 - v0) * (l.vert.co.z / 0.13 + 0.5))
    L.transform(head, Matrix.Translation((1.24, -0.45, 0.47)) @ Matrix.Rotation(-0.6, 4, "Z") @ Matrix.Rotation(0.25, 4, "Y"))
    parts.append(L.to_object(head, "axe_head", "MI_MetalOrnaments", smooth_angle=30))
    for k in range(4):
        a = rng.uniform(0, math.tau)
        c = Vector((0.95 + rng.uniform(-0.15, 0.25), -0.85 + rng.uniform(-0.1, 0.15), 0.07))
        w = L.box((0.42, 0.13, 0.11), "wood_light", bevel=0.01, end_rect="end_grain_pale", rng=rng)
        L.transform(w, Matrix.Translation(c) @ Matrix.Rotation(a, 4, "Z"))
        parts.append(L.to_object(w, "split", "MI_WoodTrim", smooth_angle=40))
    return parts


def scarecrow():
    """A scarecrow: pole and arms, a stuffed sacking head under a straw hat,
    a ragged sacking coat, straw at the cuffs and collar."""
    rng = random.Random(10)
    parts = []
    parts.append(L.to_object(L.log((0, 0, -0.1), (0.02, 0.0, 1.95), 0.045, sides=6, band="wood_dark", taper=0.85, jitter=0.08, seed=130, rings=2), "pole", "MI_WoodTrim", smooth_angle=55))
    parts.append(L.to_object(L.log((-0.72, 0.02, 1.48), (0.72, 0.0, 1.5), 0.035, sides=6, band="wood_dark", taper=0.9, jitter=0.08, seed=131, rings=2), "arms", "MI_WoodTrim", smooth_angle=55))
    head = L.lathe([(0.0, 0.0), (0.08, 0.01), (0.15, 0.08), (0.16, 0.17), (0.12, 0.27), (0.04, 0.31), (0.0, 0.31)], 8, rect="farm_burlap", jitter=0.05, seed=4)
    L.transform(head, Matrix.Translation((0.01, 0, 1.66)))
    parts.append(L.to_object(head, "head", FARM, smooth_angle=60))
    hat = straw_lathe([(0.0, 0.0), (0.34, 0.0), (0.35, 0.02), (0.16, 0.05), (0.15, 0.17), (0.08, 0.21), (0.0, 0.22)], 12, jitter=0.04, seed=5)
    L.transform(hat, Matrix.Translation((0.01, 0, 1.92)) @ Matrix.Rotation(0.18, 4, "X"))
    parts.append(L.to_object(hat, "hat", FARM, smooth_angle=50))
    # Coat: a body tube and two sleeves of sacking, ragged at the hem.
    body = L.lathe([(0.12, 0.72), (0.2, 0.78), (0.21, 1.2), (0.19, 1.5), (0.1, 1.6), (0.06, 1.64)], 9, rect="farm_burlap", jitter=0.06, seed=6)
    for v in body.verts:
        if v.co.z < 0.8:
            v.co.z += rng.uniform(-0.06, 0.06)
    parts.append(L.to_object(body, "coat", FARM, smooth_angle=50, recalc=False))
    for sx in (-1, 1):
        sl = L.sweep([(sx * 0.12, 0.0, 1.5), (sx * 0.4, 0.01, 1.5), (sx * 0.62, 0.0, 1.47)], 0.07, sides=6, rect="farm_burlap", radius_fn=lambda t: 1.0 + 0.25 * t)
        parts.append(L.to_object(sl, "sleeve", FARM, smooth_angle=50, recalc=False))
        tuft = L.new_bm()
        for k in range(6):
            a = k * math.tau / 6
            base = Vector((sx * 0.62, math.cos(a) * 0.05, 1.47 + math.sin(a) * 0.05))
            tip = base + Vector((sx * rng.uniform(0.1, 0.16), math.cos(a) * 0.07, math.sin(a) * 0.07 - 0.05))
            f = tuft.verts.new(base + Vector((0, 0, 0.02)))
            g = tuft.verts.new(base - Vector((0, 0, 0.02)))
            h = tuft.verts.new(tip)
            tuft.faces.new([f, g, h])
        rect_uv(tuft, tuft.faces, "straw", lambda l: (0.3, 0.6))
        parts.append(L.to_object(tuft, "straw", FARM, smooth_angle=60, recalc=False))
    # Button eyes and a stitched mouth on the sacking face (front = -Y).
    for sx in (-1, 1):
        e = L.lathe([(0.0, 0.0), (0.028, 0.0), (0.024, 0.014), (0.0, 0.018)], 6, rect="iron_plate")
        L.transform(e, Matrix.Translation((0.01 + sx * 0.06, -0.152, 1.84)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        parts.append(L.to_object(e, "eye", "MI_MetalOrnaments", smooth_angle=60))
    mouth = L.sweep([(-0.06, -0.15, 1.76), (0.0, -0.157, 1.745), (0.07, -0.148, 1.765)], 0.008, sides=4, band="wood_dark")
    parts.append(L.to_object(mouth, "mouth", "MI_WoodTrim", smooth_angle=60, recalc=False))
    return parts


# --- Review / export (shared with the commons) -------------------------------------------------

BUILDERS = {
    "SE_Crop_Wheat": crop_wheat,
    "SE_Crop_Barley": crop_barley,
    "SE_Crop_Flax": crop_flax,
    "SE_Crop_Cabbage": crop_cabbage,
    "SE_Crop_Turnip": crop_turnip,
    "SE_Fence_Wattle": fence_wattle,
    "SE_Fence_Rail": fence_rail,
    "SE_Fence_Paled": fence_paled,
    "SE_Gate_Wattle": gate_wattle,
    "SE_Gate_Rail": gate_rail,
    "SE_Gate_Paled": gate_paled,
    "SE_Haycock": haycock,
    "SE_Hayrick": hayrick,
    "SE_Stooks": stooks,
    "SE_LogPile": log_pile,
    "SE_Scarecrow": scarecrow,
}

# Simple collision proxies: ("box", sx, sy, sz, cx) or ("cyl", radius, height).
COLLIDERS = {
    "SE_Fence_Wattle": ("box", 2.0, 0.12, 0.95, 1.0), "SE_Fence_Rail": ("box", 2.0, 0.14, 1.0, 1.0),
    "SE_Fence_Paled": ("box", 2.0, 0.16, 1.1, 1.0), "SE_Gate_Wattle": ("box", 0.3, 0.3, 1.0, 0.06),
    "SE_Gate_Rail": ("box", 0.3, 0.3, 1.2, 0.0), "SE_Gate_Paled": ("box", 2.0, 0.16, 1.15, 1.0),
    "SE_Haycock": ("cyl", 1.06, 2.0), "SE_Hayrick": ("box", 1.9, 1.4, 1.85, 0.0), "SE_Stooks": ("cyl", 1.1, 1.1),
    "SE_LogPile": ("box", 2.6, 1.3, 0.85, 0.15), "SE_Scarecrow": ("cyl", 0.12, 1.9),
}


def setup():
    L.reset()
    L.custom_material(FARM, (1.0, 1.0, 1.0), roughness=0.9, image=FARM_TEX)


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        obj = L.join(fn(), name)
        uvs = obj.data.uv_layers
        uvs.active = uvs["UVMap"]
        uvs["UVMap"].active_render = True
        if "Sway" in uvs:
            uvs.remove(uvs["Sway"])
        L.weighted_normals(obj)
        apply_lift(obj)
        built.append(obj)
        print("%s: %d tris, %d materials" % (name, L.tri_count(obj), len(obj.data.materials)))
    return built


def crop_patches(objs, out, views=None):
    """Each crop as a small patch of field (rows or a grid) on soil, side
    by side, for judging them the way they are seen: in a mass."""
    import build_commons as BC
    sc = bpy.context.scene
    soil = L.custom_material("_soil", (0.36, 0.25, 0.15), roughness=1.0)
    x0 = 0.0
    for o in objs:
        grain = o.name in ("SE_Crop_Wheat", "SE_Crop_Barley", "SE_Crop_Flax")
        nx, ny = (2, 7) if grain else (4, 5)
        sx, sy = (2.0, 0.6) if grain else (0.85, 0.8)
        for i in range(nx):
            for j in range(ny):
                if i == 0 and j == 0:
                    inst = o
                else:
                    inst = o.copy()
                    sc.collection.objects.link(inst)
                r = random.Random(i * 31 + j * 7)
                inst.location = (x0 + i * sx + (0 if grain else r.uniform(-0.08, 0.08)), j * sy, 0.0)
                inst.rotation_euler = (0, 0, (math.pi if r.random() < 0.5 else 0.0) if grain else r.uniform(0, math.tau))
                k = r.uniform(0.85, 1.1)
                inst.scale = (1.0, 1.0, k) if grain else (k, k, k)
        bmp = L.new_bm()
        bmesh.ops.create_grid(bmp, x_segments=1, y_segments=1, size=0.5)
        L.transform(bmp, Matrix.Translation((x0 + (nx - 1) * sx / 2, (ny - 1) * sy / 2, 0.005)) @ Matrix.Diagonal((nx * sx + 0.4, ny * sy + 0.4, 1, 1)))
        g = L.to_object(bmp, "_soilpatch", FARM, smooth_angle=None, recalc=False)
        g.data.materials.clear()
        g.data.materials.append(soil)
        x0 += nx * sx + 1.0
    width = x0 - 1.0
    for name, yaw, pitch, dist, fov in views or [("patches_mid", -12, 34, 1.0, 40), ("patches_close", -20, 14, 0.42, 40)]:
        pass
    centre = Vector((width / 2 - 0.5, 1.6, 0.3))
    paths = []
    BC.review([], out, views=[("patch_setup", 0, 30, 1.0, 40)], res=(32, 32))  # creates lights, ground, mannequin
    man = bpy.data.objects.get("_mannequin")
    if man:
        man.location = (width + 0.2, 1.0, 0)
    cam_data = bpy.data.cameras.new("_pcam")
    cam = bpy.data.objects.new("_pcam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1400, 520
    for name, yaw, pitch, dist in (("mid", -10, 36, width * 0.95), ("close", -18, 16, width * 0.38)):
        y, p = math.radians(yaw), math.radians(pitch)
        target = centre if name == "mid" else Vector((width * 0.3, 0.9, 0.25))
        cam_data.angle = math.radians(40)
        cam.location = target + Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))) * dist
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = out + "_" + name + ".png"
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    return paths


def fence_runs(objs, out):
    """Each fence style as it stands in game: three segments, then its gate."""
    import build_commons as BC
    sc = bpy.context.scene
    by = {o.name: o for o in objs}
    y = 0.0
    for tier in ("Wattle", "Rail", "Paled"):
        seg, gate = by.get("SE_Fence_" + tier), by.get("SE_Gate_" + tier)
        if not seg or not gate:
            continue
        for i in range(3):
            inst = seg if i == 0 else seg.copy()
            if i:
                sc.collection.objects.link(inst)
            inst.location = (i * SEG, y, 0)
        gate.location = (3 * SEG, y, 0)
        end = seg.copy()
        sc.collection.objects.link(end)
        end.location = (4 * SEG, y, 0)
        y += 2.6
    BC.review([], out, views=[("setup", 0, 30, 1.0, 40)], res=(32, 32))
    man = bpy.data.objects.get("_mannequin")
    if man:
        man.location = (4.6, -0.8, 0)
    cam_data = bpy.data.cameras.new("_fcam")
    cam = bpy.data.objects.new("_fcam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1400, 600
    paths = []
    for name, yaw, pitch, dist, target in (("mid", -25, 30, 13.0, Vector((5.0, 2.6, 0.5))), ("close", -35, 12, 5.5, Vector((5.5, 0.0, 0.55)))):
        y_, p_ = math.radians(yaw), math.radians(pitch)
        cam_data.angle = math.radians(42)
        cam.location = target + Vector((math.sin(y_) * math.cos(p_), -math.cos(y_) * math.cos(p_), math.sin(p_))) * dist
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = out + "_" + name + ".png"
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    return paths


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
        o.location = ((i % 4) * 3.5, (i // 4) * 3.5, 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    setup()
    built = build(only)
    import build_commons as BC  # review/lineup/export helpers
    if "--export" in args:
        export(built)
        if not only:
            save_blend(built, os.path.join(HERE, "farm_field.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--patches" in args:
        out = args[args.index("--patches") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for p in crop_patches([o for o in built if o.name.startswith("SE_Crop")], out):
            print("  ", p)
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for obj in built:
            for o in built:
                o.hide_render = o is not obj
            h = max(obj.dimensions.z, 0.6)
            views = [("front34", -35, 18, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 38, 10.0, 50), ("close", -40, 12, 3.0, 42)]
            for p in BC.review([obj], os.path.join(out, obj.name), views=views, extent=3.4, center_z=h * 0.45):
                print("  ", p)
    if "--fences" in args:
        out = args[args.index("--fences") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for p in fence_runs(built, out):
            print("  ", p)
    if "--lineup" in args:
        out = args[args.index("--lineup") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tall = max(o.dimensions.z for o in built)
        for p in BC.lineup(built, out, spacing=max(1.2, max(o.dimensions.x for o in built) + 0.6), center_z=max(0.3, tall * 0.5)):
            print("  ", p)


if __name__ == "__main__":
    main()
    # bpy 4.2 can crash while tearing down after a glTF export (exit 139).
    # Everything is written by now, so leave without the teardown.
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
