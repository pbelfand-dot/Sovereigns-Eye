"""Builds the Status Wear family in Blender (bpy 4.2): headwear and aprons
that show at a glance what a villager does and where they stand.

    /root/bpy-venv/bin/python build_wear.py [--export] [--review DIR] [--lineup DIR/name] [--only A,B]

Every piece is skinned to the rig of the Quaternius Modular Character
Outfits (65 bones, "Regular" proportions), the rig the game dresses its
villagers on, so OutfitKit merges it with the outfit parts. Headwear is
fitted to the measured head and every hairstyle the game gives that gender
(head-relative: the Head bone sits 5 cm lower on the female rig, and the
hair files come from either), and is weighted to the Head bone; a veil's
drape blends into the neck and chest. Aprons are cast onto the outfit body
and legs: the bib follows the chest, the skirt hangs in front of both legs,
weighted to the pelvis and, towards the hem, the thighs.

Materials: MI_Wear (cloth, straw, felt, leather; the felt is dyed per
colorway, T_Wear_*_BaseColor.png) and MI_Wear_Metal (gold, gems, steel).
Origin at the ground, front = -Y in Blender (+Z in Godot), like the rig.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "..", "props", "village-commons", "source")

# Same source, same GLBs (see 3D/props/farm-field/README.md).
if os.environ.get("PYTHONHASHSEED") != "0":
    os.environ["PYTHONHASHSEED"] = "0"
    os.execv(sys.executable, [sys.executable] + sys.argv)

sys.path.insert(0, COMMONS_SRC)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

import random  # noqa: E402

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402
import build_commons as BC  # noqa: E402  (review, lineup)

FAMILY = os.path.dirname(HERE)
R3D = os.path.normpath(os.path.join(FAMILY, "..", ".."))
PACK = os.path.join(R3D, "characters", "quaternius-modular-outfits-fantasy-standard", "models", "parts")
BASE = os.path.join(R3D, "character-tests", "quaternius-universal-base-standard", "models")
WEAR = "MI_Wear"
METAL = "MI_Wear_Metal"
TEX = os.path.join(FAMILY, "textures", "T_Wear_BaseColor.png")
OWN = {
    WEAR: {"doubleSided": True, "dir": os.path.join(FAMILY, "textures"),
           "pbr": {"baseColorTexture": "T_Wear_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
    METAL: {"doubleSided": False, "dir": os.path.join(FAMILY, "textures"),
            "pbr": {"baseColorTexture": "T_Wear_BaseColor.png", "metallicFactor": 0.4, "roughnessFactor": 0.42}},
}
# Atlas regions in pixels (x0, y0, x1, y1) on the 512 x 1024 atlas (see
# paint_wear.py), turned into Blender UV rectangles (v up), inset a little.
ATLAS = (512, 1024)
PX = {
    "straw": (0, 0, 128, 128), "straw_band": (128, 0, 256, 128), "linen": (256, 0, 384, 128), "linen_cream": (384, 0, 512, 128),
    "felt": (0, 128, 256, 256), "felt_band": (256, 128, 384, 256), "hem": (384, 128, 512, 256),
    "gold": (0, 256, 128, 384), "gold_band": (128, 256, 256, 384), "ruby": (258, 264, 316, 376), "sapphire": (322, 264, 380, 376),
    "steel": (384, 256, 512, 384),
    "leather": (0, 384, 128, 512), "strap": (128, 384, 256, 512), "brass": (256, 384, 384, 512), "iron": (384, 384, 512, 512),
    "wool": (0, 512, 256, 640), "wool_shadow": (256, 512, 384, 640), "lining": (384, 512, 512, 640),
    "braid": (0, 640, 128, 768), "ermine": (128, 640, 256, 768), "cord": (256, 640, 384, 768), "embroidery": (384, 640, 512, 768),
}
A = {k: (x0 / ATLAS[0] + 0.004, 1.0 - y1 / ATLAS[1] + 0.002, x1 / ATLAS[0] - 0.004, 1.0 - y0 / ATLAS[1] - 0.002)
     for k, (x0, y0, x1, y1) in PX.items()}
GENDERS = {
    "M": {"rig": "Male_Peasant_Body.gltf", "body": ["Male_Peasant_Body", "Male_Peasant_Legs"],
          "head": "bodies/Superhero_Male_FullBody.glb", "hair": {"short": ["Hair_SimpleParted", "Hair_Buzzed"], "long": ["Hair_Long"]}},
    "F": {"rig": "Female_Peasant_Body.gltf", "body": ["Female_Peasant_Body", "Female_Peasant_Legs"],
          "head": "bodies/Superhero_Female_FullBody.glb", "hair": {"short": ["Hair_SimpleParted", "Hair_BuzzedFemale"], "long": ["Hair_Long"]}},
}
N = 24  # segments round a ring


# --- Measuring the rig, head and hair ----------------------------------------------------------

def _import(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def _points(obj, group=None, thr=0.3):
    """World positions of a mesh's vertices (only those weighted to `group`)."""
    vg = obj.vertex_groups.get(group) if group else None
    out = []
    for v in obj.data.vertices:
        if vg is None or any(g.group == vg.index and g.weight > thr for g in v.groups):
            out.append(obj.matrix_world @ v.co)
    return out


def measure(g):
    """The rig (kept for skinning), the Head bone's position, head and hair
    points relative to it, and a BVH of the outfit body and legs."""
    spec = GENDERS[g]
    objs = _import(os.path.join(PACK, spec["rig"]))
    rig = [o for o in objs if o.type == "ARMATURE"][0]
    rig.name = "Rig_" + g
    for o in objs:
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    head_at = rig.data.bones["Head"].head_local.copy()
    head, hair = [], []
    objs = _import(os.path.join(BASE, spec["head"]))
    arm = [o for o in objs if o.type == "ARMATURE"][0]
    origin = arm.data.bones["Head"].head_local.copy()
    for o in objs:
        if o.type == "MESH" and o.name not in ("Icosphere", "Eyes"):
            head += [p - origin for p in _points(o, "Head", 0.5)]
    for o in objs:
        bpy.data.objects.remove(o)
    hair_sets = {"short": [], "long": []}
    for fit, names in spec["hair"].items():
        for name in names:
            objs = _import(os.path.join(BASE, "hair", name + ".glb"))
            arm = [o for o in objs if o.type == "ARMATURE"][0]
            origin = arm.data.bones["Head"].head_local.copy()
            for o in objs:
                if o.type == "MESH" and o.name != "Icosphere":
                    hair_sets[fit] += [p - origin for p in _points(o)]
            for o in objs:
                bpy.data.objects.remove(o)
    verts, polys, weight_meshes = [], [], []
    for name in spec["body"]:
        for o in _import(os.path.join(PACK, name + ".gltf")):
            if o.type == "MESH" and o.name != "Icosphere":
                base = len(verts)
                verts += [o.matrix_world @ v.co for v in o.data.vertices]
                polys += [[base + i for i in p.vertices] for p in o.data.polygons]
                o.parent = None
                o.hide_render = True
                weight_meshes.append(o)
            else:
                bpy.data.objects.remove(o)
    av, ap = [], []
    for o in _import(os.path.join(PACK, ("Male" if g == "M" else "Female") + "_Peasant_Arms.gltf")):
        if o.type == "MESH" and o.name != "Icosphere":
            base = len(av)
            av += [o.matrix_world @ v.co for v in o.data.vertices]
            ap += [[base + i for i in p.vertices] for p in o.data.polygons]
        bpy.data.objects.remove(o)
    bones = rig.data.bones
    arm = {"shoulder": bones["upperarm_l"].head_local.copy(), "elbow": bones["lowerarm_l"].head_local.copy(),
           "wrist": bones["hand_l"].head_local.copy()}
    return {"rig": rig, "head_at": head_at, "head": head, "short": head + hair_sets["short"], "long": head + hair_sets["long"],
            "arms_bvh": BVHTree.FromPolygons(av, ap), "arm": arm, "pelvis": bones["pelvis"].head_local.copy(),
            "bvh": BVHTree.FromPolygons(verts, polys), "weight_meshes": weight_meshes, "gender": g}


def fit_ring(pts, z, margin, dz=0.012, n=N):
    """Radii of a ring at height z (head-relative) that clears every point in
    the band, one per direction (angle 0 = +X, counter-clockwise; front is
    -Y, angle -90 degrees)."""
    band = [p for p in pts if abs(p.z - z) < dz]
    rs = []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = Vector((math.cos(a), math.sin(a)))
        best = 0.0
        for p in band:
            q = Vector((p.x, p.y))
            if q.length < 1e-6:
                continue
            c = q.normalized().dot(d)
            if c > math.cos(1.6 * math.pi / n):
                best = max(best, q.length * c)
        rs.append(best)
    for i in range(n):  # directions with no point take their neighbours'
        if rs[i] == 0.0:
            rs[i] = max(rs[(i - 1) % n], rs[(i + 1) % n], 0.05)
    # Smooth round the ring (a running max, then a low-pass), never inside a point.
    mx = [max(rs[(i + k) % n] for k in (-1, 0, 1)) for i in range(n)]
    for _ in range(3):
        mx = [(mx[(i - 2) % n] + 2 * mx[(i - 1) % n] + 3 * mx[i] + 2 * mx[(i + 1) % n] + mx[(i + 2) % n]) / 9.0 for i in range(n)]
    return [max(a, b) + margin for a, b in zip(mx, rs)]


def ring_points(rs, z_fn, scale=1.0, n=N):
    return [Vector((math.cos(2 * math.pi * i / n) * rs[i] * scale, math.sin(2 * math.pi * i / n) * rs[i] * scale, z_fn(i)))
            for i in range(n)]


def tilt(z_front, z_back, n=N):
    """Height round a ring: lower at the front (-Y), higher at the back."""
    mid, half = (z_front + z_back) / 2, (z_back - z_front) / 2
    return lambda i: mid + half * math.sin(2 * math.pi * i / n)


# --- Building surfaces -------------------------------------------------------------------------

def loft(rings, region, closed=True, cap_top=False, flip=False):
    """Quads between successive rings (bottom to top), UVs wrapped round the
    region (u) and up it (v, by distance along the surface)."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    n = len(rings[0])
    cols = n + 1 if closed else n
    grid = []
    for ring in rings:
        row = [bm.verts.new(ring[i % n]) for i in range(cols)]
        grid.append(row)
    # Distance up the surface, for v.
    dist = [0.0]
    for j in range(1, len(rings)):
        dist.append(dist[-1] + sum((rings[j][i] - rings[j - 1][i]).length for i in range(n)) / n)
    total = max(dist[-1], 1e-6)
    u0, v0, u1, v1 = A[region]
    for j in range(len(rings) - 1):
        for i in range(cols - 1):
            vs = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            f = bm.faces.new(vs[::-1] if flip else vs)
            for l in f.loops:
                jj = 0 if l.vert in grid[j] else 1
                row = grid[j + jj]
                ii = row.index(l.vert)
                l[uv].uv = (u0 + (u1 - u0) * ii / (cols - 1), v0 + (v1 - v0) * dist[j + jj] / total)
    if cap_top:
        top = grid[-1][:n]
        c = sum((v.co for v in top), Vector()) / n
        cv = bm.verts.new(c + Vector((0, 0, 0.004)))
        for i in range(n):
            f = bm.faces.new([top[i], top[(i + 1) % n], cv][::-1] if flip else [top[i], top[(i + 1) % n], cv])
            for l in f.loops:
                p = l.vert.co - c
                l[uv].uv = (u0 + (u1 - u0) * (0.5 + p.x * 3.0), v0 + (v1 - v0) * (0.5 + p.y * 3.0))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    return bm


def region_uv(bm, region):
    """Planar UVs (X, Z of the part's bounds) into an atlas region."""
    uv = bm.loops.layers.uv["UVMap"]
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    u0, v0, u1, v1 = A[region]
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            s = (p.x - lo[0]) / max(hi[0] - lo[0], 1e-6)
            t = (p.z - lo[2]) / max(hi[2] - lo[2], 1e-6)
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    return bm


def gem(at, size, region):
    bm = L.new_bm()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size)
    for v in bm.verts:
        v.co.y *= 0.55
        v.co += at
    return region_uv(bm, region)


def band(rs, z_fn, height, thick, region, flare=0.0):
    """A closed band (outer and inner walls, top and bottom lips)."""
    outer = loft([ring_points(rs, z_fn), ring_points(rs, lambda i: z_fn(i) + height, 1.0 + flare)], region)
    rin = [r - thick for r in rs]
    inner = loft([ring_points(rin, z_fn), ring_points(rin, lambda i: z_fn(i) + height, 1.0 + flare)], region, flip=True)
    lips = loft([ring_points(rin, lambda i: z_fn(i) + height, 1.0 + flare), ring_points(rs, lambda i: z_fn(i) + height, 1.0 + flare)], region)
    bottom = loft([ring_points(rs, z_fn), ring_points(rin, z_fn)], region)
    for b in (inner, lips, bottom):
        L.merge_bm(outer, b)
    bmesh.ops.remove_doubles(outer, verts=outer.verts, dist=1e-5)
    return outer


def fitted_dome(pts, z0, z_mid, margin, z_top=None, region="felt", lift=0.0, slouch=Vector((0, 0, 0)), swell=0.0):
    """A crown over the head: rings fitted to `pts` from z0 up to z_mid, then
    an elliptic dome over the top (to `z_top`, by default just clear of the
    highest point). `swell` puffs the dome out; `slouch` leans its top."""
    rings = []
    for k in range(3):
        z = z0 + (z_mid - z0) * k / 2
        rings.append(ring_points(fit_ring(pts, z, margin, dz=0.015), lambda i, z=z: z + lift))
    base = fit_ring(pts, z_mid, margin, dz=0.015)
    if z_top is None:
        z_top = max(p.z for p in pts) + margin
    for t in (0.3, 0.55, 0.75, 0.9, 0.98):
        sc = math.sqrt(max(0.0, 1.0 - t * t)) * (1.0 + swell * math.sin(math.pi * t))
        z = z_mid + t * (z_top - z_mid)
        rings.append([p + slouch * (t * t) for p in ring_points(base, lambda i, z=z: z + lift, sc)])
    return loft(rings, region, cap_top=True)


# --- Headwear (head-relative: origin at the Head bone) -----------------------------------------

def circlet(m, pts):
    f = tilt(0.148, 0.175)
    rs = fit_ring(pts, 0.16, 0.004)
    gold = band(rs, f, 0.018, 0.004, "gold")
    front = Vector((0.0, -rs[N * 3 // 4] - 0.004, f(N * 3 // 4) + 0.007))
    return {METAL: [gold, gem(front, 0.008, "ruby")]}


def crown(m, pts):
    f = tilt(0.155, 0.178)
    rs = fit_ring(pts, 0.175, 0.008, dz=0.02)
    parts = [band(rs, f, 0.04, 0.005, "gold_band", flare=0.06)]
    pts = L.new_bm()
    for k in range(8):  # fleurons: a leaf of gold rising from the band
        i = k * N // 8
        a = 2 * math.pi * i / N
        r = rs[i] * 1.06
        base = Vector((math.cos(a) * r, math.sin(a) * r, f(i) + 0.04))
        side = Vector((-math.sin(a), math.cos(a), 0.0)) * 0.018
        out = Vector((math.cos(a), math.sin(a), 0.0)) * 0.004
        tip = base + Vector((math.cos(a) * 0.006, math.sin(a) * 0.006, 0.045))
        vs = [pts.verts.new(p) for p in (base - side, base + side, tip, base - side + out, base + side + out, tip + out)]
        pts.faces.new([vs[0], vs[1], vs[2]])
        pts.faces.new([vs[3], vs[5], vs[4]])
        pts.faces.new([vs[0], vs[3], vs[4], vs[1]])
        pts.faces.new([vs[1], vs[4], vs[5], vs[2]])
        pts.faces.new([vs[2], vs[5], vs[3], vs[0]])
    region_uv(pts, "gold")
    parts.append(pts)
    for k in range(4):
        i = k * N // 4 + N // 8
        a = 2 * math.pi * i / N
        r = rs[i] * 1.03 + 0.002
        parts.append(gem(Vector((math.cos(a) * r, math.sin(a) * r, f(i) + 0.02)), 0.008, "ruby" if k % 2 else "sapphire"))
    return {METAL: parts}


def helmet(m, pts=None):
    """A nasal helmet: a dome on an iron rim, a bar down the nose. Fitted to
    the head (it hides the hair)."""
    dome = fitted_dome(m["head"], 0.115, 0.17, 0.014, region="steel")
    dome_apex = max(v.co.z for v in dome.verts)
    for v in dome.verts:  # a slight point at the crown, the spangenhelm's shape
        t = max(0.0, (v.co.z - 0.17) / max(dome_apex - 0.17, 1e-6))
        v.co.z += 0.022 * t ** 3
    rim_rs = fit_ring(m["head"], 0.115, 0.018, dz=0.015)
    rim = band(rim_rs, lambda i: 0.105, 0.022, 0.006, "iron")
    # Nasal: a flat bar from the rim down past the brow, just off the face.
    face = fit_ring(m["head"], 0.075, 0.01, dz=0.02)[N * 3 // 4]
    top_y = -rim_rs[N * 3 // 4]
    nasal = L.new_bm()
    bmesh.ops.create_cube(nasal, size=1.0)
    for v in nasal.verts:
        t = v.co.z + 0.5  # 0 bottom, 1 top
        v.co = Vector((v.co.x * 0.02 * (1.0 - 0.3 * (1 - t)), -face + (top_y + face) * t + v.co.y * 0.006, 0.05 + t * 0.07))
    region_uv(nasal, "iron")
    return {METAL: [dome, rim, nasal]}


def straw_hat(m, pts):
    zf = tilt(0.15, 0.17)
    crown = fitted_dome(pts, 0.16, 0.19, 0.014, z_top=max(p.z for p in pts) + 0.035, region="straw", lift=0.0)
    rs0 = fit_ring(pts, 0.16, 0.014, dz=0.02)
    brim_out = [0.235] * N
    brim = loft([ring_points(rs0, lambda i: 0.16), ring_points(brim_out, lambda i: zf(i) - 0.004)], "straw")
    under = loft([ring_points(rs0, lambda i: 0.154), ring_points(brim_out, lambda i: zf(i) - 0.01)], "straw", flip=True)
    rim = loft([ring_points(brim_out, lambda i: zf(i) - 0.01), ring_points(brim_out, lambda i: zf(i) - 0.004)], "straw")
    bnd = band([r + 0.002 for r in rs0], lambda i: 0.16, 0.026, 0.003, "straw_band")
    return {WEAR: [crown, brim, under, rim, bnd]}


def cap(m, pts):
    """A felt cap: a rolled brim and a soft crown slouched to the back."""
    zf = tilt(0.145, 0.165)
    rs = fit_ring(pts, 0.16, 0.012, dz=0.02)
    roll = band(rs, zf, 0.03, 0.006, "felt_band", flare=0.03)
    crown = fitted_dome(pts, 0.17, 0.19, 0.016, z_top=max(p.z for p in pts) + 0.03, region="felt",
                        slouch=Vector((0.01, 0.035, -0.01)), swell=0.12)
    return {WEAR: [roll, crown]}


def baker_hat(m, pts):
    """A tall puffed linen cap."""
    rs = fit_ring(pts, 0.16, 0.012, dz=0.02)
    bnd = band(rs, lambda i: 0.15, 0.026, 0.005, "linen")
    crown = fitted_dome(pts, 0.172, 0.19, 0.014, z_top=max(p.z for p in pts) + 0.11, region="linen", swell=0.16)
    return {WEAR: [bnd, crown]}


def veil(m, pts=None):
    """A linen veil over the head, falling in soft folds to the shoulders, open
    at the face. Fitted to the head (it hides the hair); the drape is kept
    clear of the shoulders."""
    head = m["head"]
    top = fitted_dome(head, 0.12, 0.17, 0.011, region="linen")
    rings = []
    for z in (0.12, 0.08, 0.04, 0.0):
        rings.append(ring_points(fit_ring(head, z, 0.011, dz=0.025), lambda i, z=z: z))
    base = fit_ring(head, 0.0, 0.011, dz=0.035)
    for t, z in ((0.35, -0.06), (0.7, -0.11), (1.0, -0.16)):
        ring = []
        for i in range(N):
            a = 2 * math.pi * i / N
            r = base[i] * (1.0 + 0.75 * t) * (1.0 + 0.05 * t * math.sin(6 * a))  # soft folds
            ring.append(Vector((math.cos(a) * r, math.sin(a) * r, z - 0.02 * t * max(0.0, math.sin(a)))))  # longer at the back
        rings.append(ring)
    drape = loft(rings, "linen")
    L.merge_bm(top, drape)
    bmesh.ops.remove_doubles(top, verts=top.verts, dist=1e-4)
    kill = []
    for f in top.faces:  # open the face from the brow down
        cen = f.calc_center_median()
        ang = math.atan2(cen.y, cen.x)
        d = abs((ang + math.pi / 2 + math.pi) % (2 * math.pi) - math.pi)
        if d < 0.7 and cen.z < 0.15:
            kill.append(f)
    bmesh.ops.delete(top, geom=kill, context="FACES")
    region_uv(top, "linen")
    top.verts.ensure_lookup_table()
    clear_of_body(m, top, 0.014, origin=m["head_at"])
    return {WEAR: [top]}


def clear_of_body(m, bm, gap, origin=Vector((0, 0, 0))):
    """Pushes vertices that sink into the outfit body (or come within `gap`
    of it) back out along the surface normal."""
    for v in bm.verts:
        p = v.co + origin
        hit = m["bvh"].find_nearest(p)
        if hit[0] is None:
            continue
        loc, normal = hit[0], hit[1]
        d = (p - loc).dot(normal)
        if d < gap and (p - loc).length < 0.08:
            v.co = loc + normal * gap - origin


HEADWEAR = {"circlet": circlet, "crown": crown, "helmet": helmet, "straw_hat": straw_hat, "cap": cap, "baker_hat": baker_hat, "veil": veil}


# --- Aprons (built on the outfit body) ---------------------------------------------------------

def cast_front(m, x, z):
    hit = m["bvh"].ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)), 2.0)
    return hit[0].y if hit[0] is not None else None


def apron(m, g, bib, region):
    """A panel cast onto the front of the body and legs: from the chest (bib)
    or the waist down to the knee."""
    top = (1.33 if g == "M" else 1.28) if bib else (1.03 if g == "M" else 1.01)
    crotch, knee = 0.86, 0.56
    rows = 14 if bib else 9
    cols = 9
    half = 0.16 if g == "M" else 0.15
    grid = []
    for j in range(rows + 1):
        z = top + (knee - top) * j / rows
        w = half * (0.55 if bib and z > 1.12 else 1.0) * (1.0 + 0.12 * max(0.0, (crotch - z) / (crotch - knee)))
        xs = [-w + 2 * w * i / cols for i in range(cols + 1)]
        ys = []
        for x in xs:
            y = cast_front(m, x, z)
            ys.append(y if y is not None else 0.0)
        if z < crotch + 0.05:  # bridge the legs: in front of both
            ys = [min(ys[max(0, i - 3):i + 4]) for i in range(len(ys))]
        off = 0.02 + 0.02 * max(0.0, min(1.0, (crotch + 0.12 - z) / (crotch + 0.12 - knee)))  # the skirt stands off the legs
        row = [Vector((x, y - off, z)) for x, y in zip(xs, ys)]
        # The sides turn back a little, so the panel has an edge.
        row[0].y += 0.02
        row[-1].y += 0.02
        grid.append(row)
    # Smooth down the columns (the cast is noisy at the belt and the hem).
    for _ in range(2):
        for j in range(1, rows):
            for i in range(cols + 1):
                grid[j][i].y = min(grid[j][i].y, (grid[j - 1][i].y + grid[j][i].y + grid[j + 1][i].y) / 3.0)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    vs = [[bm.verts.new(p) for p in row] for row in grid]
    u0, v0, u1, v1 = A[region]
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new([vs[j][i], vs[j + 1][i], vs[j + 1][i + 1], vs[j][i + 1]])
            for l in f.loops:
                jj = next(r for r in range(rows + 1) if l.vert in vs[r])
                ii = vs[jj].index(l.vert)
                l[uv].uv = (u0 + (u1 - u0) * ii / cols, v1 - (v1 - v0) * jj / rows)
    parts = {WEAR: [bm]}
    # Ties: a strap round the waist, and round the neck for a bib.
    straps = L.new_bm()
    waist_z = 1.03 if g == "M" else 1.01
    pts = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        d = Vector((math.cos(a), math.sin(a), 0.0))
        hit = m["bvh"].ray_cast(Vector((0, 0.03, waist_z)) + d * 0.5, -d, 1.0)
        pts.append((hit[0] if hit[0] is not None else Vector((0, 0.03, waist_z)) + d * 0.16) + d * 0.012)
    s = L.sweep(pts, 0.008, sides=4, rect="iron_bar", closed=True)
    L.merge_bm(straps, s)
    if bib:
        tl, tr = grid[0][1], grid[0][-2]
        neck_back = Vector((0.0, 0.07 if g == "M" else 0.065, 1.49 if g == "M" else 1.45))
        for corner, sx in ((tl, -1), (tr, 1)):
            path = [corner + Vector((0, 0, -0.01)), corner.lerp(neck_back, 0.4) + Vector((sx * 0.05, -0.02, 0.06)),
                    neck_back + Vector((sx * 0.05, 0.0, 0.0)), neck_back]
            L.merge_bm(straps, L.sweep(path, 0.007, sides=4, rect="iron_bar"))
    region_uv(straps, "strap")
    parts[WEAR].append(straps)
    return parts


APRONS = {"apron_leather": (True, "leather"), "apron_linen": (False, "linen_cream")}


# --- Robes, gowns and coats (cast onto the outfit body; the trousers come off) -----------------

# Kinds of vertex, for skinning (a vertex attribute "wkind").
K_BODY, K_SKIRT, K_SLEEVE_L, K_SLEEVE_R = 1.0, 2.0, 3.0, 4.0
GARMENTS = {
    # hem height, flare at the hem, sleeves, belt, trim at hem and neck, neckline drop at the front, train
    "robe": {"genders": ["M", "F"], "hem": 0.13, "flare": 0.1, "sleeves": True, "belt": "cord", "trim": None, "neck": 0.02, "train": 0.0},
    "gown": {"genders": ["F"], "hem": 0.04, "flare": 0.2, "sleeves": True, "belt": "braid", "trim": "braid", "neck": 0.1, "train": 0.06},
    "coat": {"genders": ["M", "F"], "hem": 0.5, "flare": 0.07, "sleeves": False, "belt": "leather", "trim": "braid", "neck": 0.04, "train": 0.0},
}


def tag(bm, kind):
    layer = bm.verts.layers.float.get("wkind") or bm.verts.layers.float.new("wkind")
    for v in bm.verts:
        v[layer] = kind
    return bm


def hull_ring(m, z_fn, offset, axis_y=0.03, n=N, bvh=None):
    """A ring round the body (or legs) at heights z_fn(i): per direction the
    outermost surface, smoothed so it never dips into a gap (between the
    legs), pushed out by `offset`."""
    bvh = bvh or m["bvh"]
    rs = []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = Vector((math.cos(a), math.sin(a), 0.0))
        c = Vector((0.0, axis_y, z_fn(i)))
        hit = bvh.ray_cast(c + d * 0.7, -d, 0.7)
        rs.append((hit[0] - c).length if hit[0] is not None else 0.0)
    for i in range(n):
        if rs[i] == 0.0:
            rs[i] = max(rs[(i - 1) % n], rs[(i + 1) % n], 0.06)
    mx = [max(rs[(i + k) % n] for k in (-1, 0, 1)) for i in range(n)]
    for _ in range(2):
        mx = [(mx[(i - 1) % n] + 2 * mx[i] + mx[(i + 1) % n]) / 4.0 for i in range(n)]
    rs = [max(a, b) for a, b in zip(mx, rs)]
    return [Vector((math.cos(2 * math.pi * i / n) * (rs[i] + offset), axis_y + math.sin(2 * math.pi * i / n) * (rs[i] + offset), z_fn(i)))
            for i in range(n)]


def strip(ring_lo, ring_hi, region, kind):
    return tag(loft([ring_lo, ring_hi], region), kind)


def grow(ring, by, axis_y=0.03):
    out = []
    for p in ring:
        d = Vector((p.x, p.y - axis_y, 0.0))
        out.append(p + d.normalized() * by if d.length > 1e-6 else p.copy())
    return out


def garment(m, g, kind):
    spec = GARMENTS[kind]
    male = g == "M"
    neck_z = 1.47 if male else 1.425
    shoulder_z = 1.41 if male else 1.37
    waist_z = 1.05 if male else 1.0
    hip_z = 0.93 if male else 0.9
    front = lambda i: max(0.0, -math.sin(2 * math.pi * i / N)) ** 2  # 1 at the front, 0 at the sides and back
    # The bodice: neck to hips, fitted.
    levels = [lambda i: neck_z - spec["neck"] * front(i), lambda i: shoulder_z - spec["neck"] * 0.5 * front(i)]
    for z in (1.32 if male else 1.29, 1.2 if male else 1.16, waist_z, hip_z):
        levels.append(lambda i, z=z: z)
    body = [hull_ring(m, f, 0.012) for f in levels]
    body[0] = grow(body[0], -0.004)  # the neckline hugs the neck
    # The skirt: hips to the hem, flaring, a little longer at the back for a train.
    skirt = [body[-1]]
    hem = spec["hem"]
    steps = 5 if hem < 0.3 else 3
    for k in range(1, steps + 1):
        t = k / steps
        z = hip_z + (hem - hip_z) * t
        back = lambda i: max(0.0, math.sin(2 * math.pi * i / N))
        ring = hull_ring(m, lambda i, z=z: z - spec["train"] * t * back(i) ** 2, 0.016)
        # Never narrower than the ring above (an A-line from the hips, not a
        # skirt that pinches in at the knees), then flared.
        prev = skirt[-1]
        ring = [p if Vector((p.x, p.y - 0.03)).length >= Vector((q.x, q.y - 0.03)).length
                else Vector((q.x, q.y, p.z)) for p, q in zip(ring, prev)]
        skirt.append(grow(ring, spec["flare"] * t ** 1.15 - (spec["flare"] * ((k - 1) / steps) ** 1.15 if k > 1 else 0.0)))
    parts = {WEAR: []}
    parts[WEAR].append(tag(loft(body, "wool"), K_BODY))
    # A linen chemise fills the neckline (the outfit's own shirt comes off).
    yoke = grow(hull_ring(m, lambda i: neck_z + 0.012, 0.004), -0.006)
    parts[WEAR].append(tag(loft([body[0], yoke], "lining"), K_BODY))
    parts[WEAR].append(tag(loft(skirt, "wool"), K_SKIRT))
    # Belt at the waist.
    belt_ring = grow(hull_ring(m, lambda i: waist_z, 0.012), 0.008)
    belt_region = {"cord": "cord", "braid": "braid", "leather": "strap"}[spec["belt"]]
    belt = strip([p + Vector((0, 0, -0.016)) for p in belt_ring], [p + Vector((0, 0, 0.016)) for p in belt_ring], belt_region, K_BODY)
    parts[WEAR].append(belt)
    if spec["belt"] == "cord":  # the girdle's end hangs at the front
        knot = belt_ring[N * 3 // 4] + Vector((0.03, -0.006, 0.0))
        tail = L.sweep([knot, knot + Vector((0.01, -0.012, -0.18)), knot + Vector((0.02, -0.02, -0.34))], 0.008, sides=5, rect="iron_bar")
        parts[WEAR].append(tag(region_uv(tail, "cord"), K_SKIRT))
    if spec["belt"] == "leather":
        buckle = L.new_bm()
        bmesh.ops.create_cube(buckle, size=1.0)
        b0 = belt_ring[N * 3 // 4]
        for v in buckle.verts:
            v.co = Vector((v.co.x * 0.05, b0.y - 0.004 + v.co.y * 0.008, waist_z + v.co.z * 0.04))
        parts[METAL] = [tag(region_uv(buckle, "brass"), K_BODY)]
    # Trim: a band round the hem and the neckline.
    if spec["trim"]:
        lo = grow(skirt[-1], 0.003)
        parts[WEAR].append(strip(lo, [p + Vector((0, 0, 0.05)) for p in grow(skirt[-1], 0.002)], spec["trim"], K_SKIRT))
        nk = grow(body[0], 0.003)
        parts[WEAR].append(strip([p + Vector((0, 0, -0.03)) for p in grow(body[1], 0.003)], nk, "embroidery", K_BODY))
    # Sleeves: wide, falling open at the wrist (bell sleeves), round the pack's sleeves.
    if spec["sleeves"]:
        for side, kind_id in ((1, K_SLEEVE_L), (-1, K_SLEEVE_R)):
            parts[WEAR].append(sleeve(m, side, kind_id))
    return parts


def sleeve(m, side, kind_id):
    arm = m["arm"]
    x0, x1 = arm["shoulder"].x * 0.75, arm["wrist"].x - 0.02
    rings = []
    count = 7
    for k in range(count):
        t = k / (count - 1)
        x = x0 + (x1 - x0) * t
        c = arm["shoulder"].lerp(arm["wrist"], (x - arm["shoulder"].x) / (arm["wrist"].x - arm["shoulder"].x))
        c.x = x
        # Clear the pack's sleeve: cast across the arm from all round.
        best = 0.0
        for i in range(12):
            a = 2 * math.pi * i / 12
            d = Vector((0.0, math.cos(a), math.sin(a)))
            hit = m["arms_bvh"].ray_cast(c + d * 0.3, -d, 0.3)
            if hit[0] is not None:
                best = max(best, (hit[0] - c).length)
        r = max(best, 0.045) + 0.014 + 0.045 * t ** 2.2
        droop = 0.07 * t ** 2  # the cuff hangs low
        ring = []
        for i in range(N):
            a = 2 * math.pi * i / N
            sag = droop * max(0.0, -math.sin(a))  # the lower half falls further
            ring.append(Vector((x, c.y + math.cos(a) * r, c.z + math.sin(a) * r - sag)))
        rings.append(ring)
    bm = loft(rings, "wool")
    if side < 0:
        for v in bm.verts:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return tag(bm, kind_id)


# --- Skinning and export ----------------------------------------------------------------------

def garment_weights(m, kind, co, name=""):
    if kind in (K_SLEEVE_L, K_SLEEVE_R):
        sfx = "_l" if kind == K_SLEEVE_L else "_r"
        arm = m["arm"]
        t = (abs(co.x) - arm["shoulder"].x * 0.75) / (arm["wrist"].x - arm["shoulder"].x * 0.75)
        if t < 0.12:
            k = t / 0.12
            return {"upperarm" + sfx: 0.45 + 0.55 * k, "clavicle" + sfx: 0.35 * (1 - k), "spine_03": 0.2 * (1 - k)}
        e = min(1.0, max(0.0, (t - 0.42) / 0.2))
        return {"upperarm" + sfx: 1.0 - e, "lowerarm" + sfx: e}
    if co.z > 1.0:
        return nearest_weights(m, co)
    # The skirt follows the legs from the hip down, each side its own, the
    # front and back blending gently across the middle (a sharp blend would
    # split the hem in a stride).
    if name == "coat":  # a short skirt close to the legs: each half follows its leg, as an apron does
        s = min(1.0, (1.0 - co.z) / 0.22) ** 0.8 * 0.95
        side = min(1.0, max(0.0, 0.5 + co.x / 0.1))
    else:
        s = min(1.0, (1.0 - co.z) / 0.3) ** 0.8 * 0.72
        side = min(1.0, max(0.0, 0.5 + co.x / 0.26))
    return {"pelvis": 1.0 - s, "thigh_l": s * side, "thigh_r": s * (1.0 - side)}


def weights_for(m, name, co, kind=0.0):
    """Bone weights for a vertex (armature space)."""
    if name in GARMENTS:
        return garment_weights(m, kind, co, name)
    if name in HEADWEAR:
        if name == "veil":
            rel_z = co.z - m["head_at"].z
            if rel_z < 0.02:
                t = min(1.0, (0.02 - rel_z) / 0.19)
                return {"Head": 1.0 - t, "neck_01": t * 0.7, "spine_03": t * 0.3}
        return {"Head": 1.0}
    # Aprons: copy the nearest body weights above the crotch, blend the skirt.
    if co.z > 1.0:
        return nearest_weights(m, co)
    # From the hip down the skirt follows the legs, each side its own, so a
    # stride carries it instead of pushing through it.
    s = min(1.0, (1.0 - co.z) / 0.2) ** 0.8 * 0.95
    side = min(1.0, max(0.0, 0.5 + co.x / 0.07))
    return {"pelvis": 1.0 - s, "thigh_l": s * side, "thigh_r": s * (1.0 - side)}


def nearest_weights(m, co):
    best, best_d = None, 1e9
    for o in m["weight_meshes"]:
        for v in o.data.vertices:
            d = ((o.matrix_world @ v.co) - co).length_squared
            if d < best_d:
                best, best_d = (o, v), d
    o, v = best
    out = {}
    for gw in v.groups:
        if gw.weight > 0.01:
            out[o.vertex_groups[gw.group].name] = gw.weight
    return out or {"spine_01": 1.0}


def make_piece(m, g, name, mats, obj_name):
    objs = []
    for mat, bms in mats.items():
        for bm in bms:
            if name in HEADWEAR:
                L.transform(bm, Matrix.Translation(m["head_at"]))
            objs.append(L.to_object(bm, name, mat, smooth_angle=40, recalc=False))
    obj = L.join(objs, obj_name)
    groups = {}
    attr = obj.data.attributes.get("wkind")
    kinds = [d.value for d in attr.data] if attr is not None else None
    for v in obj.data.vertices:
        kind = kinds[v.index] if kinds else 0.0
        for bone, w in weights_for(m, name, v.co, kind).items():
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    if obj.data.attributes.get("wkind") is not None:
        obj.data.attributes.remove(obj.data.attributes["wkind"])
    obj.parent = m["rig"]
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = m["rig"]
    uvs = obj.data.uv_layers
    if "Sway" in uvs:
        uvs.remove(uvs["Sway"])
    print("%s: %d tris, %d materials" % (obj.name, L.tri_count(obj), len(obj.data.materials)))
    return obj


def setup():
    L.reset()
    L.custom_material(WEAR, (1.0, 1.0, 1.0), roughness=0.85, image=TEX)
    m = L.custom_material(METAL, (1.0, 1.0, 1.0), roughness=0.35, image=TEX)
    m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.4


# What each piece fits: hats sit on the hair, so they come in a fit for short
# and for long hair; the helmet and the veil hide the hair and fit the head.
ON_HAIR = ["circlet", "crown", "straw_hat", "cap", "baker_hat"]
HEAD_ONLY = {"helmet": ["M", "F"], "veil": ["F"]}


def piece_name(name, g, fit=None):
    words = "".join(w.capitalize() for w in name.split("_"))
    return "SE_%s_%s_%s" % (words, fit.capitalize(), g) if fit else "SE_%s_%s" % (words, g)


def build(only=None):
    built = []
    for g in GENDERS:
        m = measure(g)
        todo = []
        for name in ON_HAIR:
            for fit in ("short", "long"):
                todo.append((name, fit, piece_name(name, g, fit)))
        for name, genders in HEAD_ONLY.items():
            if g in genders:
                todo.append((name, None, piece_name(name, g)))
        for name in APRONS:
            todo.append((name, None, piece_name(name, g)))
        for name, spec in GARMENTS.items():
            if g in spec["genders"]:
                todo.append((name, None, piece_name(name, g)))
        for name, fit, obj_name in todo:
            if only and obj_name not in only:
                continue
            random.seed(obj_name)
            if name in HEADWEAR:
                mats = HEADWEAR[name](m, m[fit] if fit else None)
            elif name in GARMENTS:
                mats = garment(m, g, name)
            else:
                bib, region = APRONS[name]
                mats = apron(m, g, bib, region)
            built.append((make_piece(m, g, name, mats, obj_name), m["rig"]))
    return built


def export(built):
    models = os.path.join(FAMILY, "models")
    tmp = os.path.join(HERE, "_export_tmp")
    os.makedirs(models, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    for obj, rig in built:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(tmp, obj.name + ".gltf")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=False,
                                  export_image_format="NONE", export_yup=True, export_texcoords=True, export_normals=True,
                                  export_tangents=False, export_attributes=False, export_extras=False, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=True, export_def_bones=False,
                                  export_morph=False)
        glb = os.path.join(models, obj.name + ".glb")
        mats = gltf_pack.pack(path, glb, own=OWN)
        print("exported %s: %d tris, %s, %d bytes" % (obj.name, L.tri_count(obj), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def review_dummy(g):
    """A stand-in villager for the review renders: the outfit body, legs, arms
    and feet, the base body's head and a hairstyle, at rest."""
    out = {}
    spec = GENDERS[g]
    pre = "Male" if g == "M" else "Female"
    meshes = []
    for name in ("%s_Peasant_Body" % pre, "%s_Peasant_Legs" % pre, "%s_Peasant_Arms" % pre, "%s_Peasant_Feet" % pre):
        for o in _import(os.path.join(PACK, name + ".gltf")):
            if o.type == "MESH" and o.name != "Icosphere":
                o.parent = None
                meshes.append(o)
            else:
                bpy.data.objects.remove(o)
    for o in _import(os.path.join(BASE, spec["head"])):
        if o.type == "MESH" and o.name not in ("Icosphere",):
            o.parent = None
            if o.name not in ("Eyes", "Eyebrows"):
                keep = set()
                vg = [o.vertex_groups.get(b) for b in ("Head", "neck_01")]
                for v in o.data.vertices:
                    if any(gx.group in [x.index for x in vg if x] and gx.weight > 0.15 for gx in v.groups):
                        keep.add(v.index)
                bm = bmesh.new()
                bm.from_mesh(o.data)
                bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
                bm.to_mesh(o.data)
                bm.free()
            meshes.append(o)
        else:
            bpy.data.objects.remove(o)
    out["body"] = L.join(meshes, "_dummy_" + g)
    out["body"].modifiers.clear()
    for key, hair_name in (("hair_short", "Hair_SimpleParted"), ("hair_long", "Hair_Long")):
        hair = []
        for o in _import(os.path.join(BASE, "hair", hair_name + ".glb")):
            if o.type == "MESH" and o.name != "Icosphere":
                o.parent = None
                o.modifiers.clear()
                hair.append(o)
            else:
                bpy.data.objects.remove(o)
        out[key] = L.join(hair, "_%s_%s" % (key, g))
        # Hair files sit on either rig's head: move them onto this one.
        rig_head = 1.6 if g == "M" else 1.55
        src_head = 1.6 if hair_name == "Hair_SimpleParted" else 1.55
        out[key].location.z += rig_head - src_head
    return out


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    setup()
    built = build(only)
    if "--export" in args:
        export(built)
    objs = [o for o, _ in built]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        dummies = {g: review_dummy(g) for g in GENDERS}
        for obj in objs:
            g = obj.name[-1]
            name = obj.name
            for o in objs:
                o.hide_render = o is not obj
            for gg, parts in dummies.items():
                for key, o in parts.items():
                    o.hide_render = gg != g or (key.startswith("hair") and (any(k in name for k in ("Helmet", "Veil"))
                                                                            or key != ("hair_long" if "_Long_" in name else "hair_short")))
            head = any(k in name for k in ("Circlet", "Crown", "Helmet", "Hat", "Cap", "Veil"))
            whole = any(k in name for k in ("Robe", "Gown", "Coat"))
            cz = (1.72 if g == "M" else 1.67) if head else (0.95 if whole else 1.05)
            d = 5.0 if head else (22.0 if whole else 11.0)
            views = [("front34", -35, 10, d, 35), ("rear34", 150, 12, d, 35), ("side", 90, 4, d, 35)]
            for p in BC.review([obj], os.path.join(out, name), views=views, extent=0.6, center_z=cz):
                print("  ", p)
    if "--lineup" in args:
        out = args[args.index("--lineup") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for p in BC.lineup(objs, out, spacing=0.6, center_z=1.5):
            print("  ", p)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
