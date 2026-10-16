"""Builds the Village Commons family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_commons.py [--review out_dir] [--export] [--only NAME,...]

Assets (origin at the ground center, front = -Y in Blender = +Z in Godot):
  SE_Well_Hamlet, SE_Well_Village, SE_Well_Town
  SE_Banner_Village, SE_Banner_MarketTown, SE_Banner_Town
  SE_Signpost_Rough, SE_Signpost_Village, SE_Signpost_Town
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import commons_lib as L  # noqa: E402
import gltf_pack  # noqa: E402

WATER = "MI_Commons_Water"
BANNER = "MI_Commons_Banner"
BANNER_TEX = os.path.join(L.FAMILY, "textures", "T_Commons_Banner_BaseColor.png")
# Regions of the banner atlas (u0, v0, u1, v1), Blender UV space.
BANNER_FACE = [(i / 3 + 0.002, 0.2207, (i + 1) / 3 - 0.002, 0.999) for i in range(3)]
SLEEVE_V = (0.957, 0.997)
FRINGE = (0.0, 0.152, 1.0, 0.217)
CORD = (0.0, 0.095, 1.0, 0.148)
GILD = (0.0, 0.004, 1.0, 0.088)


# --- Shared parts ------------------------------------------------------------------------------

def ring_sector(r0, r1, z0, z1, a0, a1, segs, band, bevel=0.012, seed=0):
    """A curved block of a ring (capstones, plinth courses)."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    grid = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        grid.append([bm.verts.new((r * c, r * s, z)) for r, z in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
    for i in range(segs):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new([grid[i][k], grid[i + 1][k], grid[i + 1][k2], grid[i][k2]])
    bm.faces.new(list(reversed(grid[0])))
    bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel:
        L.bevel_edges(bm, bevel, 1)
    bm.normal_update()
    _, v0, v1 = L.BANDS[band]
    rng = random.Random(seed)
    uo = rng.uniform(0, 1)
    vo = rng.uniform(0, max(0.0, (v1 - v0) - (r1 - r0 + z1 - z0) * L.UV_PER_M))
    rm = (r0 + r1) * 0.5
    for f in bm.faces:
        n = f.normal
        for l in f.loops:
            p = l.vert.co
            a = math.atan2(p.y, p.x)
            if a < a0 - 0.5:
                a += math.tau
            r = math.hypot(p.x, p.y)
            if abs(n.z) > 0.6:
                l[uv].uv = (uo + a * rm * L.UV_PER_M, v0 + vo + (r - r0) * L.UV_PER_M)
            else:
                l[uv].uv = (uo + a * rm * L.UV_PER_M, v0 + vo + (p.z - z0 + (r - r0)) * L.UV_PER_M)
    return bm


def tube_wall(r_bottom, r_top, z0, z1, segs, band, inward=False, v_off=0.0, phase=0.0):
    prof = [(r_bottom, z0), (r_top, z1)]
    if inward:
        prof = [(r_top, z1), (r_bottom, z0)]
    return L.lathe(prof, segs, band=band, v_off=v_off, phase=phase)


def water_disc(r, z, segs):
    bm = L.new_bm()
    verts = [bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)]
    f = bm.faces.new(verts)
    uv = bm.loops.layers.uv["UVMap"]
    for l in f.loops:
        l[uv].uv = (l.vert.co.x * 0.5 + 0.5, l.vert.co.y * 0.5 + 0.5)
    return bm


def bucket(at, seed=0, tilt=0.0, yaw=0.0, handle_up=True, scale=1.0):
    """A coopered bucket: staves, two iron hoops, an iron bail."""
    rng = random.Random(seed)
    objs = []
    prof = [(0.0, 0.0), (0.140, 0.0), (0.150, 0.02), (0.172, 0.29), (0.176, 0.305), (0.158, 0.305), (0.135, 0.05), (0.0, 0.05)]
    body = L.lathe(prof, 14, band="wood_light", jitter=0.015, seed=seed)
    hoops = L.new_bm()
    for z, r in ((0.06, 0.153), (0.235, 0.172)):
        pts = L.arc_points((0, 0, z), r, 0, math.tau, 17, axis="Z")[:-1]
        L.merge_bm(hoops, L.sweep(pts, 0.011, sides=4, rect="iron_strap", closed=True))
    h = 0.20 if handle_up else 0.05
    bail_pts = []
    for i in range(13):
        t = i / 12
        a = math.pi * t
        x = -0.178 * math.cos(a)
        z = 0.27 + math.sin(a) * h + (0.0 if handle_up else 0.0)
        bail_pts.append(Vector((x, 0.0, z)))
    L.merge_bm(hoops, L.sweep(bail_pts, 0.0075, sides=5, rect="iron_bar"))
    m = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "Y") @ Matrix.Scale(scale, 4)
    L.transform(body, m)
    L.transform(hoops, m)
    objs.append(L.to_object(body, "bucket", "MI_WoodTrim", smooth_angle=12))
    objs.append(L.to_object(hoops, "bucket_iron", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    return objs


def rope_coil(x0, x1, z, r_axle, turns, seed=0):
    """Rope wound along an axle running on X."""
    pts = L.helix((0, 0, 0), r_axle + 0.017, x0, x1, turns, count_per_turn=10, axis="X")
    for p in pts:
        p.z += z
    bm = L.sweep(pts, 0.017, sides=5, band="wood_light", twist=40.0, ridges=2, ridge_depth=0.18)
    return L.to_object(bm, "rope_coil", "MI_WoodTrim", smooth_angle=70, recalc=False)


def rope(points, r=0.016):
    bm = L.sweep(points, r, sides=5, band="wood_light", twist=40.0, ridges=2, ridge_depth=0.18)
    return L.to_object(bm, "rope", "MI_WoodTrim", smooth_angle=70, recalc=False)


def crank(at_x, z, side=1.0, arm=0.30, phase=-0.9):
    """An iron crank on the axle end with a turned wooden grip."""
    c, s = math.cos(phase), math.sin(phase)
    p0 = Vector((at_x, 0, z))
    p1 = p0 + Vector((0, c * arm * 0.1, 0))
    p2 = Vector((at_x + 0.03 * side, c * arm, z + s * arm))
    p3 = p2 + Vector((0.16 * side, 0, 0))
    bm = L.sweep([p0 + Vector((-0.04 * side, 0, 0)), p0 + Vector((0.02 * side, 0, 0)), p2, p2 + Vector((0.03 * side, 0, 0))],
                 0.023, sides=6, rect="iron_bar", square=True)
    grip = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.037, 0.04), (0.037, 0.15), (0.03, 0.18), (0.0, 0.18)], 8, band="wood_dark")
    L.transform(grip, Matrix.Translation(p2 + Vector((0.025 * side, 0, 0))) @ Matrix.Rotation(math.radians(90 * side), 4, "Y"))
    return [L.to_object(bm, "crank", "MI_MetalOrnaments", smooth_angle=40), L.to_object(grip, "crank_grip", "MI_WoodTrim", smooth_angle=60)]


def mannequin():
    """A 1.78 m stand-in for scale checks in review renders (not exported)."""
    bm = L.lathe([(0.0, 0.0), (0.13, 0.02), (0.15, 0.9), (0.2, 1.3), (0.17, 1.45), (0.08, 1.5), (0.11, 1.6), (0.1, 1.74), (0.0, 1.78)], 12)
    o = L.to_object(bm, "_mannequin", "MI_WoodTrim")
    o.data.materials.clear()
    o.data.materials.append(L.custom_material("_grey", (0.55, 0.55, 0.6)))
    return o


# --- Wells -------------------------------------------------------------------------------------

def well_village():
    rng = random.Random(7)
    parts = []
    # Dressed-stone ring with a slight batter, and the shaft inside.
    parts.append(L.to_object(tube_wall(1.0, 0.97, 0.0, 0.74, 24, "rock_ashlar"), "ring_out", "MI_RockTrim", smooth_angle=60, recalc=False))
    parts.append(L.to_object(tube_wall(0.66, 0.66, 0.05, 0.74, 20, "rock_ashlar", inward=True, v_off=0.05), "ring_in", "MI_RockTrim", smooth_angle=60, recalc=False))
    parts.append(L.to_object(water_disc(0.67, 0.34, 20), "water", WATER, smooth_angle=None, recalc=False))
    # A footing course of bigger stones grounds it.
    for i in range(10):
        a0 = i * math.tau / 10 + 0.02
        parts.append(L.to_object(ring_sector(0.9, 1.07, -0.04, 0.13, a0, a0 + math.tau / 10 - 0.04, 2, "rock_slate", 0.03, seed=20 + i), "foot%d" % i, "MI_RockTrim", smooth_angle=40))
    # Eight slate capstones, a hair apart.
    for i in range(8):
        a0 = i * math.tau / 8 + 0.012
        a1 = (i + 1) * math.tau / 8 - 0.012
        parts.append(L.to_object(ring_sector(0.62, 1.06, 0.72, 0.83, a0, a1, 3, "rock_slate", 0.014, seed=i), "cap%d" % i, "MI_RockTrim", smooth_angle=40))
    # The frame: two posts to the ridge beam, knee braces, the ridge.
    top = 2.92
    for sx in (-1.0, 1.0):
        parts.append(L.to_object(L.beam((sx * 0.86, 0, 0.83), (sx * 0.86, 0, top), 0.16, 0.16, rng=rng), "post", "MI_WoodTrim"))
        parts.append(L.to_object(L.beam((sx * 0.86, 0, 2.30), (sx * 0.40, 0, top - 0.06), 0.1, 0.1, rng=rng), "brace", "MI_WoodTrim"))
    parts.append(L.to_object(L.beam((-1.22, 0, top + 0.06), (1.22, 0, top + 0.06), 0.14, 0.16, rng=rng), "ridge_beam", "MI_WoodTrim"))
    # Gable roof on X: tiles, bargeboards, a ridge cap.
    eave_z, eave_y, ridge_z, half = 2.38, 1.12, 3.06, 1.24
    for sy in (-1.0, 1.0):
        if sy < 0:
            slab = L.tile_slab((-half, sy * eave_y, eave_z), (half, sy * eave_y, eave_z), (-half, 0.0, ridge_z))
        else:
            slab = L.tile_slab((half, sy * eave_y, eave_z), (-half, sy * eave_y, eave_z), (half, 0.0, ridge_z))
        parts.append(L.to_object(slab, "roof", "MI_RoundTiles", smooth_angle=30))
        for sx in (-1.0, 1.0):
            parts.append(L.to_object(L.beam((sx * (half + 0.03), sy * (eave_y + 0.05), eave_z - 0.06), (sx * (half + 0.03), 0.0, ridge_z + 0.02), 0.05, 0.16, rng=rng), "barge", "MI_WoodTrim"))
    parts.append(ridge_cap(-half - 0.06, half + 0.06, ridge_z - 0.01, 0.095))
    # Windlass: a turned axle, the rope coil, the crank, the bucket on its rope.
    axle_z = 1.58
    parts.append(L.to_object(L.log((-1.04, 0, axle_z), (1.04, 0, axle_z), 0.07, sides=10, band="wood_dark", taper=1.0, jitter=0.03, seed=3), "axle", "MI_WoodTrim", smooth_angle=60))
    parts.append(rope_coil(-0.32, 0.30, axle_z, 0.07, 9))
    parts += crank(1.04, axle_z, 1.0)
    parts.append(rope([(0.05, 0.0, axle_z - 0.09), (0.05, 0.0, 1.28)]))
    parts += bucket(Vector((0.05, 0.0, 0.98)), seed=1, yaw=math.radians(90))
    parts += bucket(Vector((-0.58, -0.62, 0.83)), seed=2, yaw=math.radians(30), handle_up=False)
    return parts


def well_hamlet():
    """A poor hamlet's well: rubble ring, rough forked posts, a log windlass,
    a patched plank lid. Low, wide, a bit crooked."""
    rng = random.Random(11)
    parts = []
    parts.append(L.to_object(L.lathe([(0.95, 0.0), (0.92, 0.3), (0.88, 0.6)], 16, band="rock_cobble", jitter=0.035, seed=4),
                             "ring_out", "MI_RockTrim", smooth_angle=45, recalc=False))
    parts.append(L.to_object(L.lathe([(0.6, 0.6), (0.6, 0.05)], 14, band="rock_cobble", jitter=0.03, seed=5),
                             "ring_in", "MI_RockTrim", smooth_angle=45, recalc=False))
    parts.append(L.to_object(water_disc(0.61, 0.24, 14), "water", WATER, smooth_angle=None, recalc=False))
    # Capping rubble: rounded fieldstones around the rim, one gap patched by the lid.
    n = 13
    for i in range(n):
        if i in (9,):
            continue
        a = i * math.tau / n + rng.uniform(-0.08, 0.08)
        r = 0.76 + rng.uniform(-0.03, 0.03)
        size = (rng.uniform(0.34, 0.52), rng.uniform(0.28, 0.4), rng.uniform(0.13, 0.19))
        st = L.stone((0, 0, 0), size, seed=30 + i, rough=0.3, detail=1, band="rock_slate")
        L.transform(st, Matrix.Rotation(rng.uniform(-0.12, 0.12), 4, "X"))
        L.transform(st, Matrix.Rotation(a + math.pi / 2, 4, "Z"))
        L.transform(st, Matrix.Translation((r * math.cos(a), r * math.sin(a), 0.62 + size[2] * 0.25)))
        parts.append(L.to_object(st, "rubble", "MI_RockTrim", smooth_angle=35))
    # Loose stones at the foot.
    for i, (a, r) in enumerate(((0.6, 1.0), (2.2, 1.02), (4.1, 0.98))):
        st = L.stone((r * math.cos(a), r * math.sin(a), 0.07), (0.28, 0.22, 0.16), seed=50 + i)
        parts.append(L.to_object(st, "loose", "MI_RockTrim", smooth_angle=60))
    # Forked posts of rough timber, leaning in a touch.
    axle_z = 1.82
    for sx, seed in ((-1.0, 61), (1.0, 62)):
        parts.append(L.to_object(L.log((sx * 1.0, 0.02 * sx, -0.05), (sx * 0.9, 0.0, axle_z + 0.02), 0.09, sides=8, band="wood_dark", taper=0.8, jitter=0.1, bend=0.04, seed=seed), "post", "MI_WoodTrim", smooth_angle=55))
        parts.append(L.to_object(L.log((sx * 0.9, 0.0, axle_z - 0.22), (sx * 0.98, 0.04, axle_z + 0.16), 0.055, sides=7, band="wood_dark", taper=0.7, jitter=0.1, seed=seed + 10), "fork", "MI_WoodTrim", smooth_angle=55))
    parts.append(L.to_object(L.log((-1.12, 0, axle_z + 0.06), (1.1, 0, axle_z + 0.06), 0.065, sides=9, band="wood_dark", taper=0.92, jitter=0.07, bend=0.015, seed=3), "axle", "MI_WoodTrim", smooth_angle=55))
    parts.append(rope_coil(-0.26, 0.2, axle_z + 0.06, 0.065, 6))
    # Two pegs through the axle end make the handle.
    for k in range(2):
        a = math.radians(30 + 90 * k)
        d = Vector((0, math.cos(a), math.sin(a))) * 0.3
        c = Vector((1.02, 0, axle_z + 0.06))
        parts.append(L.to_object(L.log(c - d, c + d, 0.026, sides=6, band="wood_light", taper=0.9, jitter=0.08, seed=70 + k), "peg", "MI_WoodTrim", smooth_angle=55))
    # The lid: three rough planks over part of the shaft, one broken short.
    for k, (y, length) in enumerate(((-0.2, 1.35), (-0.4, 1.3), (-0.6, 0.85))):
        b = L.box((length, 0.19, 0.045), "wood_light", bevel=0.01, rng=rng)
        L.transform(b, Matrix.Rotation(rng.uniform(-0.05, 0.05), 4, "Z"))
        L.transform(b, Matrix.Translation((0.05 + (0.22 if k == 2 else 0.0), y, 0.79 + k * 0.004)))
        parts.append(L.to_object(b, "lid", "MI_WoodTrim", smooth_angle=40))
    cross = L.box((0.62, 0.1, 0.04), "wood_dark", bevel=0.008, rng=rng)
    L.transform(cross, Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((0, 0, 0)))
    L.transform(cross, Matrix.Translation((-0.38, -0.4, 0.835)))
    parts.append(L.to_object(cross, "lid_cross", "MI_WoodTrim", smooth_angle=40))
    # The bucket waits on the lid, its rope slack from the coil.
    parts += bucket(Vector((0.32, -0.38, 0.81)), seed=3, yaw=math.radians(-20), handle_up=False, scale=0.95)
    parts.append(rope([(0.05, -0.05, axle_z - 0.02), (0.12, -0.22, 1.3), (0.2, -0.33, 1.08), (0.3, -0.38, 1.02)]))
    return parts


def well_town():
    """A prosperous town well: an octagonal carved wellhead on a plinth,
    four chamfered posts with knee braces, a flared hipped roof with a
    weathervane, and a winch wheel."""
    rng = random.Random(23)
    parts = []
    ph = math.pi / 8
    oct_ = 8
    parts.append(L.to_object(L.lathe([(1.18, -0.05), (1.18, 0.12), (1.12, 0.17)], oct_, band="rock_slate", phase=ph), "plinth", "MI_RockTrim", smooth_angle=30, recalc=False))
    parts.append(L.to_object(L.lathe([(1.06, 0.15), (1.04, 0.84)], oct_, band="rock_ashlar", phase=ph), "head", "MI_RockTrim", smooth_angle=30, recalc=False))
    parts.append(L.to_object(L.lathe([(1.06, 0.82), (1.15, 0.86), (1.16, 0.95), (1.1, 0.99), (0.7, 0.99), (0.68, 0.95)], oct_, band="rock_slate", phase=ph), "cap", "MI_RockTrim", smooth_angle=30, recalc=False))
    parts.append(L.to_object(L.lathe([(0.68, 0.95), (0.68, 0.1)], 20, band="rock_ashlar"), "shaft", "MI_RockTrim", smooth_angle=60, recalc=False))
    parts.append(L.to_object(water_disc(0.69, 0.44, 20), "water", WATER, smooth_angle=None, recalc=False))
    # Posts at the corners, chamfered, on carved stone bases.
    post_top = 2.56
    corners = [(sx * 0.74, sy * 0.74) for sx in (-1, 1) for sy in (-1, 1)]
    for (x, y) in corners:
        parts.append(L.to_object(L.box((0.24, 0.24, 0.1), "rock_slate", bevel=0.025, rng=rng), "shoe", "MI_RockTrim", smooth_angle=40))
        parts[-1].location = (x, y, 1.04)
        parts.append(L.to_object(L.beam((x, y, 0.99), (x, y, post_top), 0.17, 0.17, bevel=0.03, segments=2, rng=rng), "post", "MI_WoodTrim", smooth_angle=40))
        parts.append(L.to_object(L.box((0.24, 0.24, 0.09), "wood_dark", bevel=0.02, rng=rng), "capital", "MI_WoodTrim", smooth_angle=40))
        parts[-1].location = (x, y, post_top - 0.05)
    # Top frame with crossed ends and knee braces.
    fz = post_top + 0.07
    for sy in (-1, 1):
        parts.append(L.to_object(L.beam((-0.94, sy * 0.74, fz), (0.94, sy * 0.74, fz), 0.13, 0.15, bevel=0.02, rng=rng), "frame", "MI_WoodTrim", smooth_angle=40))
    for sx in (-1, 1):
        parts.append(L.to_object(L.beam((sx * 0.74, -0.94, fz + 0.13), (sx * 0.74, 0.94, fz + 0.13), 0.13, 0.13, bevel=0.02, rng=rng), "frame", "MI_WoodTrim", smooth_angle=40))
    for (x, y) in corners:
        parts.append(L.to_object(L.beam((x, y, 2.12), (x * 0.45, y, fz - 0.06), 0.08, 0.08, bevel=0.012, rng=rng), "brace", "MI_WoodTrim"))
        parts.append(L.to_object(L.beam((x, y, 2.12), (x, y * 0.45, fz + 0.06), 0.08, 0.08, bevel=0.012, rng=rng), "brace", "MI_WoodTrim"))
    # Flared hipped roof: a shallow skirt, then a steep cap to the finial.
    # Shallow skirt (about 25 degrees), then a steep cap (about 55) to a tall spire.
    ez, e = fz + 0.12, 1.36
    bz, b = ez + 0.2, 0.94
    az = bz + 0.94 * math.tan(math.radians(55))
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 4, "Z")
        p1 = rot @ Vector((-e, -e, ez))
        p2 = rot @ Vector((e, -e, ez))
        q1 = rot @ Vector((-b, -b, bz))
        q2 = rot @ Vector((b, -b, bz))
        apex = Vector((0, 0, az))
        parts.append(L.to_object(roof_facet([p1, p2, q2, q1]), "skirt", "MI_RoundTiles", smooth_angle=20, recalc=False))
        parts.append(L.to_object(roof_facet([q1, q2, apex]), "cap", "MI_RoundTiles", smooth_angle=20, recalc=False))
        # Hip boards along the corner lines.
        parts.append(L.to_object(L.beam(p1 + Vector((0, 0, 0.02)), q1 + Vector((0, 0, 0.05)), 0.07, 0.07, bevel=0.012, rng=rng), "hip", "MI_WoodTrim"))
        parts.append(L.to_object(L.beam(q1 + Vector((0, 0, 0.05)), apex + Vector((0, 0, 0.02)), 0.07, 0.07, bevel=0.012, rng=rng), "hip", "MI_WoodTrim"))
        # A fascia board along the eave.
        parts.append(L.to_object(L.beam(p1 + Vector((0, -0.02, -0.05)), p2 + Vector((0, -0.02, -0.05)), 0.04, 0.1, bevel=0.01, rng=rng), "fascia", "MI_WoodTrim"))
    # Finial and weathervane.
    fin = L.lathe([(0.0, 0.0), (0.09, 0.0), (0.1, 0.06), (0.06, 0.1), (0.075, 0.18), (0.03, 0.26), (0.02, 0.62), (0.0, 0.66)], 8, rect="iron_bar")
    L.transform(fin, Matrix.Translation((0, 0, az - 0.05)))
    parts.append(L.to_object(fin, "finial", "MI_MetalOrnaments", smooth_angle=50, recalc=False))
    vane = L.new_bm()
    pts = [(0.0, 0.0), (0.42, 0.0), (0.34, 0.09), (0.42, 0.18), (0.0, 0.18)]
    vv = [vane.verts.new((x, 0.0, z)) for x, z in pts]
    vane.faces.new(vv)
    vane.normal_update()  # solidify offsets along vertex normals: they must exist
    bmesh.ops.solidify(vane, geom=vane.faces[:], thickness=0.018)
    L.uv_planar_band(vane, list(vane.faces), "wood_dark", Vector((1, 0, 0)), Vector((0, 0, 1)), scale=1.0)
    for f in vane.faces:
        for l in f.loops:
            l[vane.loops.layers.uv["UVMap"]].uv = (0.85 + l.vert.co.x * 0.3, 0.06 + l.vert.co.z * 0.6)
    L.transform(vane, Matrix.Translation((0.02, 0.0, az + 0.36)) @ Matrix.Rotation(0.6, 4, "Z"))
    parts.append(L.to_object(vane, "vane", "MI_MetalOrnaments", smooth_angle=30))
    # Winch: side rails, the axle, a spoked wheel, the rope and a bucket.
    axle_z = 1.78
    for sx in (-1, 1):
        parts.append(L.to_object(L.beam((sx * 0.74, -0.84, axle_z - 0.12), (sx * 0.74, 0.84, axle_z - 0.12), 0.1, 0.12, bevel=0.015, rng=rng), "rail", "MI_WoodTrim"))
    parts.append(L.to_object(L.log((-0.86, 0, axle_z), (1.0, 0, axle_z), 0.07, sides=12, band="wood_dark", taper=1.0, jitter=0.015, seed=8), "axle", "MI_WoodTrim", smooth_angle=60))
    parts.append(rope_coil(-0.3, 0.32, axle_z, 0.07, 10))
    parts += wheel(Vector((0.98, 0, axle_z)), 0.44)
    parts.append(rope([(0.0, 0.0, axle_z - 0.09), (0.0, 0.0, 1.43)]))
    parts += bucket(Vector((0.0, 0.0, 1.13)), seed=6, yaw=math.radians(90))
    parts += bucket(Vector((-0.62, 0.66, 0.99)), seed=7, yaw=math.radians(-35), handle_up=False)
    return parts


def roof_facet(pts, thickness=0.07, scale=L.UV_PER_M * 1.15):
    """A thick roof facet (tri or quad) with tiles running down the slope."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    P = [Vector(p) for p in pts]
    nrm = (P[1] - P[0]).cross(P[-1] - P[0]).normalized()
    if nrm.z < 0:
        P = list(reversed(P))
        nrm = -nrm
    top = [bm.verts.new(p) for p in P]
    bot = [bm.verts.new(p - nrm * thickness) for p in P]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(P)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([top[j], top[i], bot[i], bot[j]])
    # Down-slope direction: the facet's steepest descent.
    down = Vector((nrm.x, nrm.y, 0)).normalized()
    up = (Vector((0, 0, 1)) - nrm * nrm.z).normalized()
    along = up.cross(nrm).normalized()
    o = Vector((0, 0, 0))
    for f in bm.faces:
        for l in f.loops:
            q = l.vert.co - o
            l[uv].uv = (q.dot(along) * scale, q.dot(up) * scale)
    bm.normal_update()
    return bm


def wheel(center, r):
    """A spoked winch wheel turning on X: rim, hub, six spokes, iron tyre."""
    rng = random.Random(5)
    parts = []
    rim = L.sweep(L.arc_points((0, 0, 0), r, 0, math.tau, 25, axis="X")[:-1], 0.04, sides=6, band="wood_dark", closed=True)
    tyre = L.sweep(L.arc_points((0, 0, 0), r + 0.035, 0, math.tau, 25, axis="X")[:-1], 0.014, sides=4, rect="iron_strap", closed=True)
    hub = L.lathe([(0.0, -0.09), (0.09, -0.09), (0.11, -0.04), (0.11, 0.04), (0.09, 0.09), (0.0, 0.09)], 10, band="wood_dark")
    L.transform(hub, Matrix.Rotation(math.pi / 2, 4, "Y"))
    m = Matrix.Translation(center)
    for bm in (rim, tyre, hub):
        L.transform(bm, m)
    parts.append(L.to_object(rim, "wheel_rim", "MI_WoodTrim", smooth_angle=60, recalc=False))
    parts.append(L.to_object(tyre, "wheel_tyre", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    parts.append(L.to_object(hub, "wheel_hub", "MI_WoodTrim", smooth_angle=50))
    for k in range(6):
        a = k * math.tau / 6 + 0.3
        d = Vector((0, math.cos(a), math.sin(a)))
        parts.append(L.to_object(L.beam(center + d * 0.08, center + d * (r - 0.02), 0.045, 0.045, bevel=0.01, rng=rng), "spoke", "MI_WoodTrim"))
    return parts


def ridge_cap(x0, x1, z, r, segs=10):
    """A run of half-round ridge tiles along X."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    cols = []
    xs = [x0, x1]
    for x in xs:
        cols.append([bm.verts.new((x, r * math.cos(a) * 1.0, z + r * math.sin(a) * 0.85)) for a in [math.pi * i / segs for i in range(segs + 1)]])
    for i in range(segs):
        f = bm.faces.new([cols[0][i], cols[1][i], cols[1][i + 1], cols[0][i + 1]])
        for l in f.loops:
            p = l.vert.co
            k = cols[0].index(l.vert) if l.vert in cols[0] else cols[1].index(l.vert)
            l[uv].uv = (p.x * 0.6, k / segs * math.pi * r * 0.6)
    for col, flip in ((cols[0], True), (cols[1], False)):
        f = bm.faces.new(list(reversed(col)) if flip else col)
        for l in f.loops:
            l[uv].uv = (l.vert.co.y * 0.6, (l.vert.co.z - z) * 0.6)
    bm.normal_update()
    return L.to_object(bm, "ridge_cap", "MI_RoundTiles", smooth_angle=50, recalc=False)


# --- Banners -------------------------------------------------------------------------------------

def set_uv_rect(bm, region, along_len=None):
    """Maps a lathe/sweep's existing 0..1-ish UVs into a region of the banner atlas."""
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = region
    us = [l[uv].uv.x for f in bm.faces for l in f.loops]
    vs = [l[uv].uv.y for f in bm.faces for l in f.loops]
    umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
    for f in bm.faces:
        for l in f.loops:
            a = (l[uv].uv.x - umin) / max(umax - umin, 1e-6)
            b = (l[uv].uv.y - vmin) / max(vmax - vmin, 1e-6)
            l[uv].uv = (u0 + (u1 - u0) * a, v0 + (v1 - v0) * b)


def gilt(bm):
    set_uv_rect(bm, GILD)
    return bm


def banner_cloth(width, height, column, shape, top_z, y=0.07, amp=0.05, seed=0):
    rng = random.Random(seed)
    ph = rng.uniform(0, math.tau)

    def wave(u, d):
        return amp * (0.35 + d) * math.sin(u * math.tau * 1.25 + ph + d * 2.2) + 0.02 * d * d

    bm = L.cloth(width, height, 10, 14, shape, wave, region=BANNER_FACE[column])
    L.set_sway(bm, lambda p: (-p.z / height) ** 1.2 if p.z < 0 else 0.0)
    L.transform(bm, Matrix.Translation((0, y, top_z)))
    return L.to_object(bm, "cloth", BANNER, smooth_angle=80, recalc=False)


def hem(width, height, shape, top_z, y, depth=0.09, amp=0.05, seed=0, column=0):
    """Gold fringe hanging from the cloth's lower edge."""
    rng = random.Random(seed)
    ph = rng.uniform(0, math.tau)
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    n = 16
    top, bot = [], []
    for i in range(n + 1):
        u = i / n
        d = shape(u)
        x = (u - 0.5) * width
        z = top_z - d * height
        yy = y + amp * (0.35 + d) * math.sin(u * math.tau * 1.25 + ph + d * 2.2) + 0.02 * d * d
        top.append(bm.verts.new((x, yy, z + 0.004)))
        bot.append(bm.verts.new((x, yy + 0.01, z - depth)))
    u0, v0, u1, v1 = FRINGE
    for i in range(n):
        f = bm.faces.new([top[i], top[i + 1], bot[i + 1], bot[i]])
        for l in f.loops:
            k = top.index(l.vert) if l.vert in top else bot.index(l.vert)
            l[uv].uv = (u0 + (u1 - u0) * k / n * 0.6, v1 if l.vert in top else v0)
    bm.normal_update()
    L.set_sway(bm, lambda p: min(1.0, (top_z - p.z) / height) ** 1.2)
    return L.to_object(bm, "fringe", BANNER, smooth_angle=80, recalc=False)


def sleeve(x0, x1, z, r, y=0.0):
    """The cloth rolled around the crossbar."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    segs = 10
    cols = [[bm.verts.new((x, y + r * math.cos(a), z + r * math.sin(a))) for a in [math.tau * i / segs for i in range(segs)]] for x in (x0, x1)]
    for i in range(segs):
        j = (i + 1) % segs
        f = bm.faces.new([cols[0][i], cols[0][j], cols[1][j], cols[1][i]])
        for l in f.loops:
            k = cols[0].index(l.vert) if l.vert in cols[0] else cols[1].index(l.vert)
            if k == 0 and i == segs - 1:
                k = segs
            l[uv].uv = (0.05 + (0.28 if l.vert in cols[1] else 0.0), SLEEVE_V[0] + (SLEEVE_V[1] - SLEEVE_V[0]) * k / segs)
    bm.normal_update()
    return L.to_object(bm, "sleeve", BANNER, smooth_angle=80, recalc=False)


def tassel(top, length=0.42, seed=0):
    """A gold cord ending in a tassel."""
    parts = []
    cord = L.sweep([top, top + Vector((0.01, 0.0, -length * 0.55)), top + Vector((0.0, 0.0, -length))], 0.008, sides=5, rect="iron_bar")
    set_uv_rect(cord, CORD)
    L.set_sway(cord, lambda p: (top.z - p.z) / length * 0.5)
    parts.append(L.to_object(cord, "cord", BANNER, smooth_angle=70, recalc=False))
    t = L.lathe([(0.0, 0.0), (0.035, 0.0), (0.04, 0.03), (0.022, 0.1), (0.028, 0.12), (0.015, 0.15), (0.0, 0.16)], 8, band="wood_light")
    set_uv_rect(t, FRINGE)
    L.set_sway(t, lambda p: 0.5)
    L.transform(t, Matrix.Translation(top + Vector((0, 0, -length - 0.14))))
    parts.append(L.to_object(t, "tassel", BANNER, smooth_angle=70))
    return parts


def banner_village():
    """Village: a plain pole with stone wedges, a lashed side arm held by a
    guy rope, a swallowtail banner with the wheat sheaf."""
    parts = []
    top = 4.1
    parts.append(L.to_object(L.lathe([(0.0, -0.1), (0.058, -0.1), (0.055, 0.1), (0.046, 0.5), (0.04, top), (0.0, top + 0.02)], 10, band="wood_dark", jitter=0.02, seed=1), "pole", "MI_WoodTrim", smooth_angle=60))
    for i, a in enumerate((0.3, 2.4, 4.3)):
        parts.append(L.to_object(L.stone((0.12 * math.cos(a), 0.12 * math.sin(a), 0.03), (0.17, 0.13, 0.11), seed=80 + i, rough=0.3, detail=1), "wedge", "MI_RockTrim", smooth_angle=35))
    fin = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.036, 0.05), (0.018, 0.08), (0.05, 0.13), (0.0, 0.36)], 6, rect="iron_bar")
    L.transform(fin, Matrix.Translation((0, 0, top - 0.02)))
    parts.append(L.to_object(fin, "finial", "MI_MetalOrnaments", smooth_angle=30))
    w, h = 0.8, 1.72
    bar_z = 3.78
    x0 = 0.1
    arm_end = x0 + w + 0.12
    parts.append(L.to_object(L.log((-0.08, 0.0, bar_z), (arm_end, 0.0, bar_z), 0.026, sides=7, band="wood_light", taper=0.85, jitter=0.08, seed=4), "arm", "MI_WoodTrim", smooth_angle=55))
    lash = L.helix((0, 0, 0), 0.05, -0.07, 0.07, 4, count_per_turn=8, axis="Z")
    parts.append(rope([p + Vector((0, 0, bar_z)) for p in lash], r=0.011))
    parts.append(rope([(0.0, 0.0, top - 0.12), (arm_end - 0.04, 0.0, bar_z + 0.02)], r=0.009))

    def shape(u):
        return 0.78 + 0.22 * abs(2 * u - 1)  # swallowtail

    cloth = banner_cloth(w, h, 0, shape, bar_z - 0.03, y=0.0, seed=1)
    cloth.location.x = x0 + w / 2
    parts.append(cloth)
    parts.append(sleeve(x0, x0 + w, bar_z, 0.034))
    return parts


def turned_pole(z0, top, r=0.048, collars=(0.35, 0.55), seed=0, band="wood_light"):
    prof = [(0.0, z0), (r * 1.35, z0)]
    for c in collars:
        prof += [(r * 1.05, c - 0.04), (r * 1.4, c), (r * 1.05, c + 0.04)]
    prof += [(r, top - 0.25), (r * 1.3, top - 0.2), (r * 0.95, top - 0.14), (r * 0.9, top), (0.0, top + 0.01)]
    return L.to_object(L.lathe(prof, 10, band=band, seed=seed), "pole", "MI_WoodTrim", smooth_angle=50)


def gilt_knob(at, r=0.05, axis="X"):
    k = L.lathe([(0.0, 0.0), (r * 0.5, 0.0), (r, r * 0.6), (r * 0.9, r * 1.2), (r * 0.3, r * 1.6), (0.0, r * 1.7)], 8, band="wood_light")
    gilt(k)
    rot = Matrix.Rotation(math.pi / 2 * (1 if axis == "X" else 0), 4, "Y") if axis == "X" else Matrix()
    return k, rot


def crossbar_turned(half, z, r=0.028):
    parts = []
    bar = L.lathe([(0.0, -half), (r, -half), (r, half), (0.0, half)], 8, band="wood_dark")
    L.transform(bar, Matrix.Translation((0, 0, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    parts.append(L.to_object(bar, "crossbar", "MI_WoodTrim", smooth_angle=50))
    for sx in (-1, 1):
        k = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.055, 0.035), (0.05, 0.075), (0.02, 0.1), (0.0, 0.105)], 8, band="wood_light")
        gilt(k)
        L.transform(k, Matrix.Translation((sx * half, 0, z)) @ Matrix.Rotation(sx * math.pi / 2, 4, "Y"))
        parts.append(L.to_object(k, "knob", BANNER, smooth_angle=50))
    return parts


def side_arm(x_end, z, r=0.03, brace_drop=0.6, knob=True):
    """A turned side arm with a gilt knob and an iron brace under it."""
    parts = []
    bar = L.lathe([(0.0, 0.0), (r, 0.0), (r, x_end), (0.0, x_end)], 8, band="wood_dark")
    L.transform(bar, Matrix.Translation((0, 0, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    parts.append(L.to_object(bar, "arm", "MI_WoodTrim", smooth_angle=50))
    if knob:
        k = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.055, 0.035), (0.05, 0.075), (0.02, 0.1), (0.0, 0.105)], 8, band="wood_light")
        gilt(k)
        L.transform(k, Matrix.Translation((x_end, 0, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        parts.append(L.to_object(k, "knob", BANNER, smooth_angle=50))
    brace = L.sweep([(0.05, 0.0, z - brace_drop), (0.18, 0.0, z - brace_drop * 0.55), (0.34, 0.0, z - 0.2), (0.48, 0.0, z - 0.03)], 0.014, sides=4, rect="iron_bar", square=True)
    parts.append(L.to_object(brace, "brace", "MI_MetalOrnaments", smooth_angle=40))
    ring = L.sweep(L.arc_points((0, 0, z - 0.03), 0.06, 0, math.tau, 13, axis="Z")[:-1], 0.012, sides=4, rect="iron_strap", closed=True)
    parts.append(L.to_object(ring, "collar", "MI_MetalOrnaments", smooth_angle=40, recalc=False))
    return parts


def banner_market():
    """Market Town: an octagonal stone foot, a turned pole with a gilt
    finial, a braced side arm, a pointed banner (balance scales) with
    fringe and tassels."""
    parts = []
    parts.append(L.to_object(L.lathe([(0.27, -0.05), (0.27, 0.22), (0.22, 0.3), (0.08, 0.31)], 8, band="rock_slate", phase=math.pi / 8), "foot", "MI_RockTrim", smooth_angle=30, recalc=False))
    top = 4.55
    parts.append(turned_pole(0.28, top, seed=2))
    fin = L.lathe([(0.0, 0.0), (0.035, 0.0), (0.05, 0.04), (0.075, 0.11), (0.05, 0.18), (0.022, 0.21), (0.016, 0.4), (0.0, 0.46)], 10, band="wood_light")
    gilt(fin)
    L.transform(fin, Matrix.Translation((0, 0, top)))
    parts.append(L.to_object(fin, "finial", BANNER, smooth_angle=50))
    w, h = 0.94, 2.0
    bar_z = 4.18
    x0 = 0.12
    parts += side_arm(x0 + w + 0.12, bar_z)

    def shape(u):
        return 0.86 + 0.14 * (1 - abs(2 * u - 1))  # a point at the bottom

    cloth = banner_cloth(w, h, 1, shape, bar_z - 0.03, y=0.0, seed=2)
    fr = hem(w, h, shape, bar_z - 0.03, 0.0, seed=2)
    for o in (cloth, fr):
        o.location.x = x0 + w / 2
    parts += [cloth, fr]
    parts.append(sleeve(x0, x0 + w, bar_z, 0.04))
    parts += tassel(Vector((x0 + w + 0.05, 0.0, bar_z - 0.03)), length=0.42)
    return parts


def banner_town():
    """Town: a stepped stone plinth, a tall turned pole crowned in gilt, a
    braced side arm, a long banner (crowned castle) with fringe and tassels."""
    rng = random.Random(9)
    parts = []
    parts.append(L.to_object(L.box((0.62, 0.62, 0.2), "rock_slate", bevel=0.03, rng=rng), "plinth", "MI_RockTrim", smooth_angle=40))
    parts[-1].location = (0, 0, 0.08)
    parts.append(L.to_object(L.box((0.44, 0.44, 0.34), "rock_ashlar", bevel=0.025, rng=rng), "plinth2", "MI_RockTrim", smooth_angle=40))
    parts[-1].location = (0, 0, 0.35)
    parts.append(L.to_object(L.box((0.5, 0.5, 0.06), "rock_slate", bevel=0.02, rng=rng), "plinth_cap", "MI_RockTrim", smooth_angle=40))
    parts[-1].location = (0, 0, 0.54)
    top = 5.3
    parts.append(turned_pole(0.56, top, r=0.055, collars=(0.7, 0.95, 3.0), seed=3))
    crown_z = top
    band = L.lathe([(0.0, 0.0), (0.09, 0.0), (0.1, 0.03), (0.1, 0.09), (0.085, 0.1), (0.0, 0.1)], 12, band="wood_light")
    gilt(band)
    L.transform(band, Matrix.Translation((0, 0, crown_z)))
    parts.append(L.to_object(band, "crown", BANNER, smooth_angle=40))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        spike = L.lathe([(0.0, 0.0), (0.03, 0.0), (0.0, 0.14)], 6, band="wood_light")
        gilt(spike)
        tilt = Matrix.Rotation(0.2, 4, Vector((-math.sin(a), math.cos(a), 0)))
        L.transform(spike, Matrix.Translation((0.08 * math.cos(a), 0.08 * math.sin(a), crown_z + 0.09)) @ tilt)
        parts.append(L.to_object(spike, "crown_pt", BANNER, smooth_angle=40))
    orb = L.lathe([(0.0, 0.0), (0.04, 0.01), (0.055, 0.05), (0.04, 0.095), (0.012, 0.11), (0.012, 0.16), (0.0, 0.17)], 10, band="wood_light")
    gilt(orb)
    L.transform(orb, Matrix.Translation((0, 0, crown_z + 0.1)))
    parts.append(L.to_object(orb, "orb", BANNER, smooth_angle=50))
    w, h = 1.04, 2.3
    bar_z = 4.9
    x0 = 0.13
    parts += side_arm(x0 + w + 0.14, bar_z, r=0.034, brace_drop=0.75)

    def shape(u):
        return 0.9 + 0.1 * (1 - abs(2 * u - 1))

    cloth = banner_cloth(w, h, 2, shape, bar_z - 0.035, y=0.0, amp=0.06, seed=3)
    fr = hem(w, h, shape, bar_z - 0.035, 0.0, amp=0.06, seed=3)
    for o in (cloth, fr):
        o.location.x = x0 + w / 2
    parts += [cloth, fr]
    parts.append(sleeve(x0, x0 + w, bar_z, 0.045))
    parts += tassel(Vector((x0 + w + 0.06, 0.0, bar_z - 0.04)), length=0.5)
    parts += tassel(Vector((x0 + 0.02, 0.0, bar_z - 0.04)), length=0.3)
    return parts


# --- Signposts -----------------------------------------------------------------------------------

def arrow_board(length, height, thick, point, band="wood_light", rng=None, tail_notch=False):
    """A sign board with an arrow point at +X (in the XZ plane)."""
    rng = rng or random
    pts = [(0.0, -height / 2), (length - point, -height / 2), (length, 0.0), (length - point, height / 2), (0.0, height / 2)]
    if tail_notch:
        pts.append((point * 0.6, 0.0))
    bm = L.new_bm()
    vs = [bm.verts.new((x, -thick / 2, z)) for x, z in pts]
    f = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, thick, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    L.bevel_edges(bm, 0.008, 1)
    bm.normal_update()
    _, v0, v1 = L.BANDS[band]
    vo = rng.uniform(0, (v1 - v0) - height * L.UV_PER_M * 1.2)
    uo = rng.uniform(0, 1)
    uv = bm.loops.layers.uv["UVMap"]
    for face in bm.faces:
        for l in face.loops:
            p = l.vert.co
            c = p.z + height / 2 + (abs(p.y) if abs(face.normal.y) < 0.5 else 0.0)
            l[uv].uv = (uo + p.x * L.UV_PER_M, v0 + vo + c * L.UV_PER_M)
    return bm


def board_on_post(post_r, z, direction, length, height=0.17, thick=0.04, rng=None, tilt=0.0, notch=False, batten=False):
    """An arrow board nailed to the post's side, pointing `direction` (radians)."""
    bm = arrow_board(length, height, thick, 0.13, rng=rng, tail_notch=notch)
    if batten:
        bat = L.box((length - 0.22, 0.05, 0.03), "wood_dark", bevel=0.008, rng=rng)
        L.transform(bat, Matrix.Translation(((length - 0.22) / 2, thick / 2 + 0.012, height / 2 - 0.005)))
        L.merge_bm(bm, bat)
    L.transform(bm, Matrix.Translation((-0.08, 0, 0)))
    L.transform(bm, Matrix.Rotation(tilt, 4, "Y"))
    L.transform(bm, Matrix.Translation((0, post_r + thick / 2 + 0.003, z)))
    L.transform(bm, Matrix.Rotation(direction, 4, "Z"))
    return L.to_object(bm, "board", "MI_WoodTrim", smooth_angle=35)


def signpost_rough():
    """Hamlet: a crooked post with two rough boards, one lashed back on."""
    rng = random.Random(31)
    parts = []
    parts.append(L.to_object(L.log((0.0, 0.0, -0.1), (0.03, 0.04, 2.05), 0.065, sides=7, band="wood_dark", taper=0.75, jitter=0.12, bend=0.04, seed=12), "post", "MI_WoodTrim", smooth_angle=55))
    for i, a in enumerate((0.8, 3.0, 5.0)):
        parts.append(L.to_object(L.stone((0.11 * math.cos(a), 0.11 * math.sin(a), 0.03), (0.15, 0.12, 0.1), seed=90 + i, rough=0.3, detail=1), "wedge", "MI_RockTrim", smooth_angle=35))
    parts.append(board_on_post(0.06, 1.72, 0.25, 0.78, height=0.18, rng=rng, tilt=0.07))
    parts.append(board_on_post(0.06, 1.38, math.pi - 0.6, 0.66, height=0.16, rng=rng, tilt=-0.1, notch=True))
    lash = L.helix((0, 0, 0), 0.075, 1.3, 1.46, 3, count_per_turn=8, axis="Z")
    parts.append(rope(lash, r=0.012))
    return parts


def signpost_village():
    """Village: a squared post with a pyramid cap and three arrow boards."""
    rng = random.Random(32)
    parts = []
    parts.append(L.to_object(L.beam((0, 0, -0.1), (0, 0, 2.25), 0.12, 0.12, bevel=0.018, rng=rng), "post", "MI_WoodTrim", smooth_angle=40))
    capm = L.lathe([(0.0, 0.0), (0.11, 0.0), (0.11, 0.04), (0.0, 0.16)], 4, band="wood_dark", phase=math.pi / 4)
    L.transform(capm, Matrix.Translation((0, 0, 2.23)))
    parts.append(L.to_object(capm, "cap", "MI_WoodTrim", smooth_angle=20))
    parts.append(board_on_post(0.06, 1.95, 0.15, 0.92, rng=rng))
    parts.append(board_on_post(0.06, 1.7, 2.3, 0.84, rng=rng))
    parts.append(board_on_post(0.06, 1.46, -0.55, 0.78, rng=rng))
    # A footing of packed stones.
    for i, a in enumerate((0.2, 1.8, 3.4, 4.9)):
        parts.append(L.to_object(L.stone((0.13 * math.cos(a), 0.13 * math.sin(a), 0.03), (0.16, 0.13, 0.1), seed=95 + i, rough=0.3, detail=1), "foot", "MI_RockTrim", smooth_angle=35))
    return parts


def signpost_town():
    """Town: a dressed stone footing, a turned post with iron collar and
    finial, three framed boards."""
    rng = random.Random(33)
    parts = []
    parts.append(L.to_object(L.box((0.4, 0.4, 0.36), "rock_ashlar", bevel=0.03, rng=rng), "footing", "MI_RockTrim", smooth_angle=40))
    parts[-1].location = (0, 0, 0.15)
    parts.append(L.to_object(L.box((0.46, 0.46, 0.07), "rock_slate", bevel=0.02, rng=rng), "footing_cap", "MI_RockTrim", smooth_angle=40))
    parts[-1].location = (0, 0, 0.36)
    prof = [(0.0, 0.38), (0.085, 0.38), (0.085, 0.46), (0.06, 0.5), (0.055, 2.15), (0.075, 2.2), (0.075, 2.28), (0.05, 2.32), (0.0, 2.33)]
    parts.append(L.to_object(L.lathe(prof, 8, band="wood_dark", phase=math.pi / 8), "post", "MI_WoodTrim", smooth_angle=30))
    collar = L.lathe([(0.064, 0.0), (0.066, 0.06)], 8, rect="iron_strap", phase=math.pi / 8)
    L.transform(collar, Matrix.Translation((0, 0, 1.08)))
    parts.append(L.to_object(collar, "collar", "MI_MetalOrnaments", smooth_angle=30, recalc=False))
    fin = L.lathe([(0.0, 0.0), (0.04, 0.0), (0.05, 0.05), (0.025, 0.09), (0.04, 0.12), (0.0, 0.32)], 8, rect="iron_bar")
    L.transform(fin, Matrix.Translation((0, 0, 2.32)))
    parts.append(L.to_object(fin, "finial", "MI_MetalOrnaments", smooth_angle=30))
    for z, direction, length in ((2.0, 0.1, 0.98), (1.76, 2.4, 0.9), (1.52, -0.6, 0.86)):
        parts.append(board_on_post(0.058, z, direction, length, height=0.18, thick=0.045, rng=rng, batten=True))
    return parts


# --- Review renders ------------------------------------------------------------------------------

def review(objs, out_path, views=None, res=(640, 480), extent=3.4, center_z=1.4):
    """Renders a quick Cycles contact strip: front 3/4, rear 3/4, gameplay
    angle, close-up; with a 1.78 m mannequin for scale."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w") if not sc.world else sc.world
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.72, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9
    if not bpy.data.objects.get("_sun"):
        sun = bpy.data.lights.new("_sun", "SUN")
        sun.energy = 3.2
        sun.color = (1.0, 0.95, 0.86)
        so = bpy.data.objects.new("_sun", sun)
        sc.collection.objects.link(so)
        so.rotation_euler = (math.radians(50), 0, math.radians(35))
        g = L.new_bm()
        bmesh.ops.create_grid(g, x_segments=1, y_segments=1, size=12)
        go = L.to_object(g, "_ground", "MI_WoodTrim", smooth_angle=None, recalc=False)
        go.data.materials.clear()
        go.data.materials.append(L.custom_material("_grass", (0.36, 0.5, 0.26)))
        man = mannequin()
        man.location = (1.7, -1.1, 0)
    cam_data = bpy.data.cameras.new("_cam")
    cam = bpy.data.objects.new("_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    views = views or [("front34", -35, 18, 7.5, 40), ("rear34", 150, 22, 7.5, 40), ("gameplay", -20, 38, 11.0, 50), ("close", -50, 12, 3.2, 45)]
    paths = []
    for name, yaw, pitch, dist, fov in views:
        cam_data.angle = math.radians(fov)
        y, p = math.radians(yaw), math.radians(pitch)
        target = Vector((0, 0, center_z if name != "close" else (center_z * 1.45 if center_z > 2.0 else center_z * 0.7)))
        if name == "close" and center_z > 2.0:
            target.x = 0.6  # the cloth hangs off the arm
        d = dist * extent / 3.4
        cam.location = target + Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))) * d
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        path = out_path + "_" + name + ".png"
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    bpy.data.objects.remove(cam)
    return paths


BUILDERS = {
    "SE_Well_Hamlet": well_hamlet,
    "SE_Well_Village": well_village,
    "SE_Well_Town": well_town,
    "SE_Banner_Village": banner_village,
    "SE_Banner_MarketTown": banner_market,
    "SE_Banner_Town": banner_town,
    "SE_Signpost_Rough": signpost_rough,
    "SE_Signpost_Village": signpost_village,
    "SE_Signpost_Town": signpost_town,
}


def lineup(objs, out_path, spacing=3.4, center_z=1.3):
    """All assets side by side (with the mannequin) from two angles."""
    n = len(objs)
    for i, o in enumerate(objs):
        o.hide_render = False
        o.location.x = (i - (n - 1) / 2) * spacing
    ext = max(3.4, n * spacing * 0.8)
    paths = review(objs, out_path, views=[("lineup_front", -18, 16, 8.0, 45), ("lineup_top", -15, 42, 10.0, 45)], res=(1280, 560), extent=ext, center_z=center_z)
    man = bpy.data.objects.get("_mannequin")
    return paths


# Simple convex collision proxies (radius, height) for Godot's -convcolonly import hint.
COLLIDERS = {
    "SE_Well_Hamlet": (1.0, 0.9), "SE_Well_Village": (1.08, 0.9), "SE_Well_Town": (1.18, 1.0),
    "SE_Banner_Village": (0.18, 2.0), "SE_Banner_MarketTown": (0.28, 2.0), "SE_Banner_Town": (0.36, 2.0),
    "SE_Signpost_Rough": (0.16, 2.0), "SE_Signpost_Village": (0.18, 2.0), "SE_Signpost_Town": (0.26, 2.0),
}


def collider(name):
    r, h = COLLIDERS[name]
    bm = L.new_bm()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=h)
    L.transform(bm, Matrix.Translation((0, 0, h / 2)))
    o = L.to_object(bm, name + "-convcolonly", "MI_WoodTrim", smooth_angle=None)
    o.data.materials.clear()
    while o.data.uv_layers:
        o.data.uv_layers.remove(o.data.uv_layers[0])
    return o


def export(objs, models_dir, tmp_dir):
    os.makedirs(models_dir, exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)
    report = []
    for obj in objs:
        col = collider(obj.name)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        col.select_set(True)
        loc = obj.location.copy()
        obj.location = (0, 0, 0)
        tmp = os.path.join(tmp_dir, obj.name + ".gltf")
        bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLTF_SEPARATE", use_selection=True, export_apply=True,
                                  export_image_format="NONE", export_yup=True, export_texcoords=True, export_normals=True,
                                  export_tangents=False, export_attributes=False, export_extras=False, export_cameras=False,
                                  export_lights=False, export_animations=False, export_skins=False, export_morph=False)
        glb = os.path.join(models_dir, obj.name + ".glb")
        mats = gltf_pack.pack(tmp, glb)
        obj.location = loc
        bpy.data.objects.remove(col)
        report.append((obj.name, L.tri_count(obj), mats, os.path.getsize(glb)))
        print("exported %s: %d tris, %s, %d bytes" % (obj.name, L.tri_count(obj), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)
    return report


def save_blend(objs, path):
    """Lays the assets out in a row and saves the editable source."""
    for o in [o for o in bpy.data.objects if o.name.startswith("_")]:
        bpy.data.objects.remove(o)
    for i, o in enumerate(objs):
        o.hide_render = False
        o.location = ((i % 3) * 4.0, (i // 3) * 4.0, 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)


def main():
    args = sys.argv[1:]
    out = None
    if "--review" in args:
        out = args[args.index("--review") + 1]
    lineup_out = None
    if "--lineup" in args:
        lineup_out = args[args.index("--lineup") + 1]
    only = None
    if "--only" in args:
        only = args[args.index("--only") + 1].split(",")
    L.reset()
    L.custom_material(WATER, (0.09, 0.2, 0.22), roughness=0.08)
    L.custom_material(BANNER, (1.0, 1.0, 1.0), roughness=0.85, image=BANNER_TEX)
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        parts = fn()
        obj = L.join(parts, name)
        uvs = obj.data.uv_layers
        uvs.active = uvs["UVMap"]
        uvs["UVMap"].active_render = True
        if not name.startswith("SE_Banner") and "Sway" in uvs:
            uvs.remove(uvs["Sway"])
        L.weighted_normals(obj)
        built.append(obj)
        print("%s: %d tris, %d materials" % (name, L.tri_count(obj), len(obj.data.materials)))
    if out:
        os.makedirs(out, exist_ok=True)
        for obj in built:
            for o in built:
                o.hide_render = o is not obj
            h = obj.dimensions.z
            # Frame by height: wells sit low and wide, banners are tall.
            if h > 4.0:
                views = [("front34", -30, 12, 9.0, 40), ("rear34", 155, 14, 9.0, 40), ("gameplay", -20, 38, 13.0, 50), ("close", -25, 8, 3.4, 42)]
                for p in review([obj], os.path.join(out, obj.name), views=views, extent=3.4, center_z=h * 0.52):
                    print("  ", p)
                continue
            if h < 3.0 and obj.name.startswith("SE_Signpost"):
                views = [("front34", -35, 14, 5.0, 40), ("rear34", 150, 16, 5.0, 40), ("gameplay", -20, 38, 9.0, 50), ("close", -40, 10, 2.6, 42)]
                for p in review([obj], os.path.join(out, obj.name), views=views, extent=3.4, center_z=1.25):
                    print("  ", p)
                continue
            for p in review([obj], os.path.join(out, obj.name)):
                print("  ", p)
    if "--export" in args:
        export(built, os.path.join(L.FAMILY, "models"), os.path.join(L.FAMILY, "source", "_export_tmp"))
        if not only:
            save_blend(built, os.path.join(L.FAMILY, "source", "village_commons.blend"))
    if lineup_out:
        os.makedirs(os.path.dirname(lineup_out), exist_ok=True)
        tall = max(o.dimensions.z for o in built)
        for p in lineup(built, lineup_out, spacing=3.4 if tall > 3 else 2.2, center_z=min(1.3, tall * 0.5)):
            print("  ", p)


if __name__ == "__main__":
    main()
    # bpy 4.2 can crash while tearing down after a glTF export (exit 139).
    # Everything is written by now, so leave without the teardown.
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
