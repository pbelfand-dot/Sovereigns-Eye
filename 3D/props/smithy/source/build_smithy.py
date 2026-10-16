"""Builds the Smithy family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_smithy.py [--review DIR] [--yards DIR/name] [--lineup DIR/name] [--export] [--only A,B]

The smith's yard, set against the smithy's side wall so the building reads
as a smithy before the UI says so: a forge in two tiers (a village hearth
of field stone under a timber hood; a town forge of dressed stone with a
tall chimney and double bellows), an anvil on its stump, the slack tub,
charcoal (a heap, then a bin), a tool rack and, in a town, a grindstone.
Wood, stone and iron are UV-mapped onto the village kit's trim sheets;
leather, charcoal, glowing embers and the sooty tub water are the family's
own flat materials (no new textures).

Origin at the ground, front = -Y in Blender (+Z in Godot). A forge's back
(the wall side) is +Y; its bellows are on +X.
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
import build_commons as BC  # noqa: E402  (review, lineup, bucket, set_uv_rect)

FAMILY = os.path.dirname(HERE)
LEATHER = "MI_Smithy_Leather"
COAL = "MI_Smithy_Coal"
EMBERS = "MI_Smithy_Embers"
WATER = "MI_Smithy_Water"
OWN = {
    LEATHER: {"doubleSided": False, "pbr": {"baseColorFactor": [0.25, 0.13, 0.07, 1.0], "metallicFactor": 0, "roughnessFactor": 0.62}},
    COAL: {"doubleSided": False, "pbr": {"baseColorFactor": [0.05, 0.045, 0.045, 1.0], "metallicFactor": 0, "roughnessFactor": 0.95}},
    EMBERS: {"doubleSided": False, "emissiveFactor": [1.0, 0.36, 0.06], "emissiveStrength": 2.5,
             "pbr": {"baseColorFactor": [0.55, 0.12, 0.03, 1.0], "metallicFactor": 0, "roughnessFactor": 0.9}},
    WATER: {"doubleSided": False, "pbr": {"baseColorFactor": [0.035, 0.05, 0.05, 1.0], "metallicFactor": 0, "roughnessFactor": 0.25}},
}
IRON = L.RECTS["iron_plate"][1:]
IRON_BAR = L.RECTS["iron_bar"][1:]


# --- Small parts ---------------------------------------------------------------------------------

def block(x0, x1, y0, y1, z0, z1, band, bevel=0.02, rng=None, tilt=0.0):
    """A block between the given bounds (bevelled), its long side along X."""
    size = (x1 - x0, y1 - y0, z1 - z0)
    bm = L.box(size, band, bevel=bevel, segments=1, rng=rng)
    if tilt and rng:
        L.transform(bm, Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "X") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "Y"))
    L.transform(bm, Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)))
    return bm


def iron(bm, region=IRON):
    """Maps a part's UVs onto the dark iron of the metal trim sheet."""
    BC.set_uv_rect(bm, region)
    return bm


def iron_box(x0, x1, y0, y1, z0, z1, bevel=0.006):
    bm = L.box((x1 - x0, y1 - y0, z1 - z0), "wood_dark", bevel=bevel)
    L.transform(bm, Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)))
    return iron(bm)


def mound(r, h, z, segs=10, rings=3, seed=0, jitter=0.12):
    """A low irregular dome (a coal bed, a charcoal heap)."""
    rng = random.Random(seed)
    prof = [(0.0, z + h)]
    for k in range(1, rings + 1):
        t = k / rings
        prof.append((r * math.sin(t * math.pi / 2), z + h * math.cos(t * math.pi / 2)))
    prof.reverse()
    bm = L.lathe(prof, segs, band="rock_slate", jitter=jitter, seed=seed)
    for v in bm.verts:
        if v.co.z > z + 0.01:
            v.co.z += rng.uniform(-0.25, 0.25) * h * 0.3
    bm.normal_update()
    return bm


def lumps(center, spread, count, size, seed, z=0.0):
    """Scattered charcoal lumps."""
    rng = random.Random(seed)
    bm = L.new_bm()
    for k in range(count):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.uniform(0, 1)) * spread
        s = size * rng.uniform(0.7, 1.3)
        L.merge_bm(bm, L.stone((center[0] + math.cos(a) * d, center[1] + math.sin(a) * d, z + s * 0.25), (s, s * 0.8, s * 0.6),
                               seed=seed * 31 + k, band="rock_slate", detail=1, rough=0.3))
    return bm


def facet(pts, thick=0.05, band="wood_dark", scale=L.UV_PER_M):
    """A thick flat plate through 3-4 points (hood sides), banded along its bottom edge."""
    bm = L.new_bm()
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    bm.normal_update()
    n = f.normal.copy()
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=thick)
    bm.normal_update()
    a = (Vector(pts[1]) - Vector(pts[0])).normalized()
    b = n.cross(a).normalized()
    _, v0, v1 = L.BANDS[band]
    uv = bm.loops.layers.uv["UVMap"]
    o = Vector(pts[0])
    for fc in bm.faces:
        for l in fc.loops:
            p = l.vert.co - o
            l[uv].uv = (p.dot(a) * scale, v0 + min(v1 - v0, abs(p.dot(b)) * scale))
    return bm


def hood(x_bot, y_front, y_back, z_bot, x_top, y_top_front, z_top, thick, band):
    """A forge hood: front and two sides sloping in from the fire to the
    chimney; its back is the chimney breast."""
    bm = L.new_bm()
    fl, fr = (-x_bot, y_front, z_bot), (x_bot, y_front, z_bot)
    bl, br = (-x_bot, y_back, z_bot), (x_bot, y_back, z_bot)
    tfl, tfr = (-x_top, y_top_front, z_top), (x_top, y_top_front, z_top)
    tbl, tbr = (-x_top, y_back, z_top), (x_top, y_back, z_top)
    L.merge_bm(bm, facet([fl, fr, tfr, tfl], thick, band))
    L.merge_bm(bm, facet([fr, br, tbr, tfr], thick, band))
    L.merge_bm(bm, facet([bl, fl, tfl, tbl], thick, band))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bellows(at, length, width, z0, z1, yaw=0.0, seed=0, handle=True):
    """Leather bellows: two pear-shaped boards with pleated leather between,
    an iron nozzle at the narrow end (pointing to -X before `yaw`) and, when
    worked by hand, a handle strapped flat on the top board and running out
    past its round end."""
    rng = random.Random(seed)
    parts = []

    def outline(z, scale=1.0):
        pts = []
        for k in range(12):
            t = k / 12 * math.tau
            # A pear: narrow towards -X (the nozzle), round at +X.
            x = math.cos(t) * length * 0.5
            w = width * 0.5 * (0.35 + 0.65 * (x / length + 0.5) ** 0.8) * scale
            pts.append(Vector((x, math.sin(t) * w, z)))
        return pts
    boards = L.new_bm()
    leather = L.new_bm()
    zm = (z0 + z1) / 2
    for z in (z0, z1):
        b = L.new_bm()
        vs = [b.verts.new(p) for p in outline(z)]
        b.faces.new(vs)
        b.normal_update()  # solidify offsets along vertex normals: they must exist
        bmesh.ops.solidify(b, geom=list(b.faces), thickness=0.03)
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        L.uv_box_band(b, list(b.faces), "wood_light", u_off=rng.uniform(0, 1))
        L.merge_bm(boards, b)
    rings = [outline(z0 + 0.02), outline(zm - 0.02, 1.08), outline(zm + 0.02, 0.96), outline(z1 - 0.02)]
    grid = [[leather.verts.new(p) for p in ring] for ring in rings]
    for j in range(len(grid) - 1):
        for k in range(12):
            k2 = (k + 1) % 12
            leather.faces.new([grid[j][k], grid[j][k2], grid[j + 1][k2], grid[j + 1][k]])
    bmesh.ops.recalc_face_normals(leather, faces=leather.faces)
    nozzle = L.sweep([(-length * 0.5 + 0.02, 0, zm), (-length * 0.5 - 0.16, 0, zm - 0.02)], 0.03, sides=6, rect="iron_bar",
                     radius_fn=lambda t: 1.0 - 0.45 * t)
    m = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z")
    for bm in (boards, leather, nozzle):
        L.transform(bm, m)
    parts.append(L.to_object(boards, "bellows_boards", "MI_WoodTrim", smooth_angle=30))
    parts.append(L.to_object(leather, "bellows_leather", LEATHER, smooth_angle=50, recalc=False))
    if handle:
        # Resting on the board (its top face is z1), held by two iron straps.
        grip = L.beam((length * 0.08, 0, z1 + 0.025), (length * 0.74, 0, z1 + 0.025), 0.05, 0.05, band="wood_dark", rng=rng)
        L.transform(grip, m)
        parts.append(L.to_object(grip, "bellows_handle", "MI_WoodTrim", smooth_angle=30))
        for x in (0.18, 0.38):
            strap = iron_box(length * x - 0.018, length * x + 0.018, -0.034, 0.034, z1 - 0.004, z1 + 0.056)
            L.transform(strap, m)
            L.merge_bm(nozzle, strap)
    parts.append(L.to_object(nozzle, "nozzle", "MI_MetalOrnaments", smooth_angle=50, recalc=False))
    return parts


def fire(cx, cy, z, r, seed):
    """A coal bed with a glowing heart in the firepot."""
    coals = mound(r, 0.07, z, segs=10, rings=2, seed=seed)
    hot = mound(r * 0.55, 0.06, z + 0.03, segs=8, rings=2, seed=seed + 1, jitter=0.2)
    L.merge_bm(hot, lumps((0, 0), r * 0.5, 4, 0.05, seed + 2, z=z + 0.05))
    for bm in (coals, hot):
        L.transform(bm, Matrix.Translation((cx, cy, 0)))
    return [L.to_object(coals, "coals", COAL, smooth_angle=50, recalc=False),
            L.to_object(hot, "embers", EMBERS, smooth_angle=50, recalc=False)]


def stump(r, h, seed):
    return L.to_object(L.log((0, 0, -0.04), (0, 0, h), r, sides=10, band="wood_dark", taper=0.94, jitter=0.06, seed=seed), "stump", "MI_WoodTrim", smooth_angle=50)


def hammer(at, yaw, tilt=0.0, length=0.36, seed=0):
    rng = random.Random(seed)
    m = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "Y")
    handle = L.beam((0, 0, 0), (length, 0, 0), 0.028, 0.032, band="wood_light", rng=rng)
    head = iron_box(length - 0.02, length + 0.03, -0.065, 0.065, -0.022, 0.026)
    for bm in (handle, head):
        L.transform(bm, m)
    return [L.to_object(handle, "hammer_handle", "MI_WoodTrim", smooth_angle=30), L.to_object(head, "hammer_head", "MI_MetalOrnaments", smooth_angle=30)]


def tongs(at, yaw, length=0.55, lean=0.0, spread=0.03):
    """Smith's tongs: two long iron reins, slightly open at the jaws."""
    bm = L.new_bm()
    for s in (-1, 1):
        pts = [(0, s * spread * 0.4, 0), (length * 0.75, s * spread * 0.5, 0), (length * 0.85, s * spread * 0.15, 0), (length, s * spread, 0)]
        L.merge_bm(bm, L.sweep(pts, 0.009, sides=5, rect="iron_bar"))
    L.transform(bm, Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(lean, 4, "Y"))
    return L.to_object(bm, "tongs", "MI_MetalOrnaments", smooth_angle=60, recalc=False)


def shovel(at, yaw, lean, length=1.05):
    m = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(lean, 4, "Y")
    handle = L.log((0, 0, 0.12), (0, 0, length), 0.018, sides=6, band="wood_light", taper=1.0, jitter=0.0, seed=3, rings=1)
    grip = L.beam((-0.07, 0, length), (0.07, 0, length), 0.03, 0.03, band="wood_light")
    blade = L.new_bm()
    pts = [(-0.11, 0.0, 0.0), (0.11, 0.0, 0.0), (0.12, 0.0, 0.2), (0.0, 0.0, 0.24), (-0.12, 0.0, 0.2)]
    vs = [blade.verts.new(p) for p in pts]
    blade.faces.new(vs)
    blade.normal_update()
    bmesh.ops.solidify(blade, geom=list(blade.faces), thickness=0.012)
    bmesh.ops.recalc_face_normals(blade, faces=blade.faces)
    L.uv_box_band(blade, list(blade.faces), "wood_dark")
    iron(blade)
    for bm in (handle, grip, blade):
        L.transform(bm, m)
    return [L.to_object(handle, "shovel", "MI_WoodTrim", smooth_angle=50), L.to_object(grip, "grip", "MI_WoodTrim", smooth_angle=30),
            L.to_object(blade, "blade", "MI_MetalOrnaments", smooth_angle=30)]


# --- Forges --------------------------------------------------------------------------------------

def forge_village():
    """Hamlet and Village: a waist-high hearth of field stone with the fire
    in a firepot, a breast and a timber-framed hood narrowing to a short
    stone flue, and leather bellows on a trestle at its side."""
    rng = random.Random(61)
    parts = []
    hearth = block(-0.7, 0.7, -0.5, 0.55, -0.05, 0.76, "rock_cobble", bevel=0.03, rng=rng)
    parts.append(L.to_object(hearth, "hearth", "MI_RockTrim", smooth_angle=35, recalc=False))
    rim = L.new_bm()
    for k in range(9):
        x = -0.62 + k * 0.155 + rng.uniform(-0.02, 0.02)
        L.merge_bm(rim, L.stone((x, -0.44, 0.78), (0.17, 0.15, 0.09), seed=70 + k, band="rock_slate", detail=1))
    for sx in (-1, 1):
        for k in range(3):
            L.merge_bm(rim, L.stone((sx * 0.62, -0.25 + k * 0.17, 0.78), (0.15, 0.16, 0.09), seed=80 + k + (sx > 0) * 5, band="rock_slate", detail=1))
    parts.append(L.to_object(rim, "rim", "MI_RockTrim", smooth_angle=60, recalc=False))
    parts += fire(0.0, -0.05, 0.75, 0.36, 90)
    # Chimney breast behind the fire, the hood over it, the flue above.
    parts.append(L.to_object(block(-0.7, 0.7, 0.3, 0.62, 0.74, 1.8, "rock_cobble", bevel=0.025, rng=rng), "breast", "MI_RockTrim", smooth_angle=35, recalc=False))
    parts.append(L.to_object(hood(0.72, -0.52, 0.31, 1.72, 0.3, 0.12, 2.42, 0.05, "wood_dark"), "hood", "MI_WoodTrim", smooth_angle=20, recalc=False))
    parts.append(L.to_object(L.beam((-0.78, -0.56, 1.69), (0.78, -0.56, 1.69), 0.1, 0.12, band="wood_dark", rng=rng), "lintel", "MI_WoodTrim", smooth_angle=30))
    for sx in (-1, 1):
        parts.append(L.to_object(L.beam((sx * 0.74, -0.56, 1.72), (sx * 0.3, 0.12, 2.42), 0.06, 0.06, band="wood_dark", rng=rng), "hip", "MI_WoodTrim", smooth_angle=30))
    parts.append(L.to_object(block(-0.3, 0.3, 0.1, 0.62, 2.36, 3.3, "rock_cobble", bevel=0.02, rng=rng), "flue", "MI_RockTrim", smooth_angle=35, recalc=False))
    parts.append(L.to_object(block(-0.36, 0.36, 0.04, 0.68, 3.28, 3.36, "rock_slate", bevel=0.015, rng=rng), "flue_cap", "MI_RockTrim", smooth_angle=35, recalc=False))
    # Bellows on a trestle at the side, blowing into the hearth.
    for x in (0.95, 1.45):
        parts.append(L.to_object(L.beam((x, -0.22, 0.0), (x, -0.22, 0.56), 0.07, 0.07, band="wood_dark", rng=rng), "leg", "MI_WoodTrim", smooth_angle=30))
        parts.append(L.to_object(L.beam((x, 0.22, 0.0), (x, 0.22, 0.56), 0.07, 0.07, band="wood_dark", rng=rng), "leg", "MI_WoodTrim", smooth_angle=30))
        parts.append(L.to_object(L.beam((x, -0.28, 0.58), (x, 0.28, 0.58), 0.08, 0.06, band="wood_dark", rng=rng), "trestle", "MI_WoodTrim", smooth_angle=30))
    parts += bellows((1.22, 0.0, 0.0), 0.95, 0.62, 0.62, 0.86, seed=95)
    # The tongs and a poker leaning on the hearth.
    parts.append(tongs((-0.74, -0.52, 0.02), math.radians(95), length=0.72, lean=-1.2))
    poker = L.sweep([(-0.55, -0.56, 0.0), (-0.5, -0.6, 0.85), (-0.42, -0.6, 0.9)], 0.01, sides=5, rect="iron_bar")
    parts.append(L.to_object(poker, "poker", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    return parts


def forge_town():
    """Market Town and Town: a dressed-stone hearth on a slate plinth with a
    coped rim and an iron tool rail, a stone hood banded in iron rising into
    a tall chimney with a moulded cap, and great double bellows worked by a
    lever with a stone counterweight."""
    rng = random.Random(63)
    parts = []
    parts.append(L.to_object(block(-0.98, 0.98, -0.62, 0.66, -0.05, 0.12, "rock_slate", bevel=0.02, rng=rng), "plinth", "MI_RockTrim", smooth_angle=35, recalc=False))
    parts.append(L.to_object(block(-0.9, 0.9, -0.55, 0.6, 0.1, 0.74, "rock_ashlar", bevel=0.02, rng=rng), "hearth", "MI_RockTrim", smooth_angle=35, recalc=False))
    cope = L.new_bm()
    L.merge_bm(cope, block(-0.95, 0.95, -0.6, -0.38, 0.72, 0.82, "rock_slate", bevel=0.015, rng=rng))
    for sx in (-1, 1):
        L.merge_bm(cope, block(sx * 0.95 - (0.22 if sx > 0 else 0.0), sx * 0.95 + (0.0 if sx > 0 else 0.22), -0.38, 0.3, 0.72, 0.82, "rock_slate", bevel=0.015, rng=rng))
    parts.append(L.to_object(cope, "coping", "MI_RockTrim", smooth_angle=35, recalc=False))
    parts += fire(0.0, -0.04, 0.74, 0.42, 92)
    rail = L.sweep([(-0.85, -0.66, 0.7), (-0.85, -0.7, 0.66), (0.85, -0.7, 0.66), (0.85, -0.66, 0.7)], 0.012, sides=5, rect="iron_bar")
    parts.append(L.to_object(rail, "rail", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    parts.append(tongs((-0.4, -0.71, 0.66), math.radians(-90), length=0.6, lean=math.radians(85)))
    parts.append(tongs((-0.15, -0.71, 0.66), math.radians(-90), length=0.52, lean=math.radians(85), spread=0.02))
    # Breast, stone hood with an iron band, tall chimney.
    parts.append(L.to_object(block(-0.92, 0.92, 0.32, 0.66, 0.8, 1.9, "rock_ashlar", bevel=0.02, rng=rng), "breast", "MI_RockTrim", smooth_angle=35, recalc=False))
    parts.append(L.to_object(hood(0.95, -0.62, 0.33, 1.84, 0.36, 0.08, 2.72, 0.08, "rock_ashlar"), "hood", "MI_RockTrim", smooth_angle=20, recalc=False))
    band_ = L.sweep([(-0.97, 0.33, 1.86), (-0.97, -0.64, 1.86), (0.97, -0.64, 1.86), (0.97, 0.33, 1.86)], 0.022, sides=4, rect="iron_strap", square=True)
    parts.append(L.to_object(band_, "hood_band", "MI_MetalOrnaments", smooth_angle=30, recalc=False))
    parts.append(L.to_object(block(-0.36, 0.36, 0.06, 0.68, 2.66, 4.3, "rock_ashlar", bevel=0.02, rng=rng), "chimney", "MI_RockTrim", smooth_angle=35, recalc=False))
    cap = L.lathe([(0.44, 4.28), (0.5, 4.33), (0.5, 4.4), (0.4, 4.46), (0.0, 4.46)], 4, band="rock_slate", phase=math.pi / 4)
    L.transform(cap, Matrix.Translation((0, 0.37, 0)))
    parts.append(L.to_object(cap, "chimney_cap", "MI_RockTrim", smooth_angle=20, recalc=False))
    # Double bellows on a frame, a lever with a counterweight above.
    for x in (1.2, 1.9):
        for y in (-0.3, 0.3):
            parts.append(L.to_object(L.beam((x, y, 0.0), (x, y, 0.5), 0.08, 0.08, band="wood_dark", rng=rng), "leg", "MI_WoodTrim", smooth_angle=30))
        parts.append(L.to_object(L.beam((x, -0.36, 0.52), (x, 0.36, 0.52), 0.1, 0.07, band="wood_dark", rng=rng), "frame", "MI_WoodTrim", smooth_angle=30))
    parts += bellows((1.55, 0.0, 0.0), 1.15, 0.72, 0.56, 0.78, seed=96, handle=False)
    parts += bellows((1.55, 0.0, 0.25), 1.15, 0.72, 0.56, 0.74, seed=97, handle=False)[:2]
    post = L.beam((2.15, 0.32, 0.0), (2.15, 0.32, 1.85), 0.12, 0.12, band="wood_dark", rng=rng)
    parts.append(L.to_object(post, "lever_post", "MI_WoodTrim", smooth_angle=30))
    lever = L.beam((0.95, 0.32, 1.62), (2.4, 0.32, 1.9), 0.07, 0.08, band="wood_dark", rng=rng)
    parts.append(L.to_object(lever, "lever", "MI_WoodTrim", smooth_angle=30))
    weight = L.stone((2.42, 0.32, 1.72), (0.24, 0.22, 0.2), seed=98, band="rock_slate")
    parts.append(L.to_object(weight, "counterweight", "MI_RockTrim", smooth_angle=60, recalc=False))
    chain = L.sweep([(1.45, 0.32, 1.68), (1.45, 0.1, 1.3), (1.5, 0.0, 1.03)], 0.009, sides=4, rect="iron_bar")
    L.merge_bm(chain, iron_box(1.46, 1.54, -0.025, 0.025, 0.985, 1.03))  # the eye it hooks, on the top board (z 0.99)
    parts.append(L.to_object(chain, "chain", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    return parts


# --- Yard pieces ---------------------------------------------------------------------------------

def anvil():
    """A horned anvil on an oak stump, a hammer resting on its face, a
    glowing bar waiting, and tongs leaning on the stump."""
    parts = [stump(0.27, 0.52, 71)]
    a = L.new_bm()
    L.merge_bm(a, iron_box(-0.2, 0.2, -0.13, 0.13, 0.5, 0.56))      # feet
    L.merge_bm(a, iron_box(-0.12, 0.12, -0.08, 0.08, 0.56, 0.67))   # waist
    L.merge_bm(a, iron_box(-0.23, 0.28, -0.085, 0.085, 0.67, 0.79))  # body and heel
    parts.append(L.to_object(a, "anvil", "MI_MetalOrnaments", smooth_angle=30))
    horn = L.sweep([(-0.22, 0, 0.745), (-0.36, 0, 0.75), (-0.47, 0, 0.73), (-0.53, 0, 0.7)], 0.07, sides=8, rect="iron_plate",
                   radius_fn=lambda t: 1.0 - 0.9 * t)
    parts.append(L.to_object(horn, "horn", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    hot = L.box((0.3, 0.035, 0.03), "wood_dark", bevel=0.006)
    L.transform(hot, Matrix.Translation((0.02, -0.02, 0.805)) @ Matrix.Rotation(0.25, 4, "Z"))
    parts.append(L.to_object(hot, "hot_bar", EMBERS, smooth_angle=30))
    parts += hammer((0.1, 0.06, 0.81), math.radians(160), length=0.34, seed=72)
    parts.append(tongs((0.22, -0.26, 0.0), math.radians(-60), length=0.62, lean=-1.3))
    return parts


def slack_tub():
    """The quench tub: half a barrel of sooty water with two iron hoops,
    tongs left in it."""
    parts = []
    prof = [(0.0, 0.0), (0.33, 0.0), (0.35, 0.03), (0.39, 0.56), (0.395, 0.58), (0.36, 0.58), (0.33, 0.06), (0.0, 0.06)]
    parts.append(L.to_object(L.lathe(prof, 16, band="wood_light", jitter=0.012, seed=73), "tub", "MI_WoodTrim", smooth_angle=12))
    hoops = L.new_bm()
    for z, r in ((0.1, 0.36), (0.47, 0.392)):
        pts = L.arc_points((0, 0, z), r, 0, math.tau, 19, axis="Z")[:-1]
        L.merge_bm(hoops, L.sweep(pts, 0.014, sides=4, rect="iron_strap", closed=True))
    parts.append(L.to_object(hoops, "hoops", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    parts.append(L.to_object(BC.water_disc(0.37, 0.48, 16), "water", WATER, smooth_angle=None, recalc=False))
    parts.append(tongs((-0.12, 0.0, 0.4), math.radians(20), length=0.62, lean=-1.1))
    return parts


def coal_heap():
    """Hamlet and Village: charcoal heaped on the ground, a shovel in it."""
    parts = []
    heap = mound(0.62, 0.36, -0.02, segs=12, rings=3, seed=74, jitter=0.16)
    L.merge_bm(heap, lumps((0.0, 0.0), 0.75, 9, 0.11, 75))
    parts.append(L.to_object(heap, "charcoal", COAL, smooth_angle=50, recalc=False))
    parts += shovel((0.18, -0.1, 0.18), math.radians(30), math.radians(-25))
    return parts


def coal_bin():
    """Market Town and Town: a plank bin heaped with charcoal, a shovel in it."""
    rng = random.Random(76)
    parts = []
    bm = L.new_bm()
    for y in (-0.36, 0.36):
        L.merge_bm(bm, block(-0.55, 0.55, y - 0.03, y + 0.03, 0.0, 0.52, "wood_light", bevel=0.01, rng=rng))
    for x in (-0.55, 0.55):
        b = block(-0.36, 0.36, -0.03, 0.03, 0.0, 0.52, "wood_light", bevel=0.01, rng=rng)
        L.transform(b, Matrix.Translation((x, 0, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z"))
        L.merge_bm(bm, b)
    parts.append(L.to_object(bm, "bin", "MI_WoodTrim", smooth_angle=30))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(L.to_object(L.beam((sx * 0.58, sy * 0.39, 0.0), (sx * 0.58, sy * 0.39, 0.6), 0.07, 0.07, band="wood_dark", rng=rng), "corner", "MI_WoodTrim", smooth_angle=30))
    fill = mound(0.48, 0.18, 0.44, segs=10, rings=2, seed=77, jitter=0.1)
    L.transform(fill, Matrix.Diagonal((1.05, 0.72, 1.0, 1)))
    L.merge_bm(fill, lumps((0.0, 0.0), 0.4, 5, 0.1, 78, z=0.5))
    parts.append(L.to_object(fill, "charcoal", COAL, smooth_angle=50, recalc=False))
    parts += shovel((0.25, 0.0, 0.5), math.radians(80), math.radians(-35), length=0.9)
    return parts


def tool_rack():
    """A rack against the wall: two posts and two rails, hammers, tongs, a
    file and a string of horseshoes hanging from it."""
    rng = random.Random(79)
    parts = []
    for x in (-0.55, 0.55):
        parts.append(L.to_object(L.beam((x, 0.0, -0.05), (x, 0.0, 1.55), 0.09, 0.09, band="wood_dark", rng=rng), "post", "MI_WoodTrim", smooth_angle=30))
    for z in (1.4, 0.75):
        parts.append(L.to_object(L.beam((-0.62, -0.06, z), (0.62, -0.06, z), 0.05, 0.08, band="wood_dark", rng=rng), "rail", "MI_WoodTrim", smooth_angle=30))
    # Hanging tools (handles down from the top rail).
    for i, x in enumerate((-0.42, -0.24)):
        h = hammer((x, -0.12, 1.4), 0.0, tilt=math.radians(90), length=0.34 + i * 0.05, seed=80 + i)
        parts += h
    for x in (-0.02, 0.14):
        parts.append(tongs((x, -0.12, 1.42), 0.0, length=0.6, lean=math.radians(90), spread=0.025))
    file_ = iron_box(0.29, 0.31, -0.13, -0.11, 1.0, 1.4, bevel=0.003)
    parts.append(L.to_object(file_, "file", "MI_MetalOrnaments", smooth_angle=30))
    shoes = L.new_bm()
    for k in range(3):
        pts = L.arc_points((0.45, -0.12, 1.28 - k * 0.13), 0.055, math.radians(-20), math.radians(200), 9, axis="Y")
        L.merge_bm(shoes, L.sweep(pts, 0.011, sides=4, rect="iron_bar"))
    L.merge_bm(shoes, L.sweep([(0.45, -0.1, 1.4), (0.45, -0.12, 1.06)], 0.006, sides=4, rect="iron_bar"))
    parts.append(L.to_object(shoes, "horseshoes", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    return parts


def grindstone():
    """Market Town and Town: a grinding wheel on a timber frame with a crank,
    a water trough under the stone."""
    rng = random.Random(81)
    parts = []
    for y in (-0.22, 0.22):
        parts.append(L.to_object(L.beam((-0.55, y, 0.42), (0.55, y, 0.42), 0.07, 0.08, band="wood_dark", rng=rng), "rail", "MI_WoodTrim", smooth_angle=30))
        for x in (-0.48, 0.48):
            parts.append(L.to_object(L.beam((x, y, -0.02), (x * 1.08, y * 1.15, 0.46), 0.07, 0.07, band="wood_dark", rng=rng), "leg", "MI_WoodTrim", smooth_angle=30))
    wheel = L.lathe([(0.0, -0.06), (0.36, -0.06), (0.38, -0.03), (0.38, 0.03), (0.36, 0.06), (0.0, 0.06)], 16, band="rock_slate")
    L.transform(wheel, Matrix.Translation((0.0, 0.0, 0.72)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    parts.append(L.to_object(wheel, "wheel", "MI_RockTrim", smooth_angle=40, recalc=False))
    axle = L.sweep([(0.0, -0.32, 0.72), (0.0, 0.3, 0.72)], 0.025, sides=6, rect="iron_bar")
    crank = L.sweep([(0.0, -0.3, 0.72), (0.0, -0.32, 0.72), (0.18, -0.34, 0.6), (0.18, -0.46, 0.6)], 0.016, sides=5, rect="iron_bar")
    L.merge_bm(axle, crank)
    parts.append(L.to_object(axle, "axle", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    for y in (-0.22, 0.22):
        parts.append(L.to_object(block(-0.06, 0.06, y - 0.04, y + 0.04, 0.46, 0.72, "wood_dark", bevel=0.01, rng=rng), "bearing", "MI_WoodTrim", smooth_angle=30))
    trough = L.new_bm()
    L.merge_bm(trough, block(-0.32, 0.32, -0.15, 0.15, 0.2, 0.24, "wood_light", bevel=0.008, rng=rng))
    for y in (-0.15, 0.15):
        L.merge_bm(trough, block(-0.32, 0.32, y - 0.02, y + 0.02, 0.2, 0.38, "wood_light", bevel=0.008, rng=rng))
    parts.append(L.to_object(trough, "trough", "MI_WoodTrim", smooth_angle=30))
    for x in (-0.3, 0.3):
        parts.append(L.to_object(L.beam((x, 0, 0.0), (x, 0, 0.21), 0.05, 0.05, band="wood_dark", rng=rng), "trough_leg", "MI_WoodTrim", smooth_angle=30))
    parts.append(L.to_object(BC.water_disc(0.12, 0.33, 8), "water", WATER, smooth_angle=None, recalc=False))
    return parts


BUILDERS = {
    "SE_Forge_Village": forge_village,
    "SE_Forge_Town": forge_town,
    "SE_Anvil": anvil,
    "SE_SlackTub": slack_tub,
    "SE_CoalHeap": coal_heap,
    "SE_CoalBin": coal_bin,
    "SE_ToolRack": tool_rack,
    "SE_Grindstone": grindstone,
}

# Simple collision proxies: ("box", sx, sy, sz, cx) or ("cyl", radius, height).
# In game the whole yard is one walking obstacle (data/controls.json "forge").
COLLIDERS = {
    "SE_Forge_Village": ("box", 2.1, 1.2, 1.8, 0.35), "SE_Forge_Town": ("box", 3.0, 1.35, 2.0, 0.55),
    "SE_Anvil": ("cyl", 0.3, 0.8), "SE_SlackTub": ("cyl", 0.4, 0.6), "SE_CoalHeap": ("cyl", 0.7, 0.4),
    "SE_CoalBin": ("box", 1.2, 0.8, 0.6, 0.0), "SE_ToolRack": ("box", 1.3, 0.25, 1.55, 0.0), "SE_Grindstone": ("box", 1.2, 0.6, 1.1, 0.0),
}


def setup():
    L.reset()
    L.custom_material(LEATHER, (0.25, 0.13, 0.07), roughness=0.62)
    L.custom_material(COAL, (0.05, 0.045, 0.045), roughness=0.95)
    L.custom_material(WATER, (0.035, 0.05, 0.05), roughness=0.25)
    m = L.custom_material(EMBERS, (0.55, 0.12, 0.03), roughness=0.9)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.36, 0.06, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 2.5


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


# The forge yards as laid out in game (data/props.json "sets": forge_yard_*),
# local frame: +Y here is the wall (Godot -Z), the yard faces -Y.
YARDS = {
    "village": [("SE_Forge_Village", 0.25, 0.55, 0), ("SE_Anvil", 0.55, -0.75, 20), ("SE_SlackTub", 1.5, -0.75, 0),
                ("SE_CoalHeap", -1.25, -0.35, 0), ("SE_ToolRack", -1.05, 1.0, 0)],
    "town": [("SE_Forge_Town", -0.5, 0.55, 0), ("SE_Anvil", -0.15, -0.8, 15), ("SE_SlackTub", 0.85, -0.9, 0),
             ("SE_CoalBin", -1.9, -0.25, 90), ("SE_ToolRack", -1.75, 1.05, 0), ("SE_Grindstone", 1.8, -0.88, 0)],
}


def yards(objs, out):
    """Each forge yard as it stands in game, against a wall, with the
    mannequin for scale."""
    by = {o.name: o for o in objs}
    BC.review([], out, views=[("setup", 0, 30, 1.0, 40)], res=(32, 32))  # lights, ground, mannequin
    sc = bpy.context.scene
    wall_m = L.custom_material("_wall", (0.72, 0.68, 0.6), roughness=0.9)
    paths = []
    for o in objs:
        o.hide_render = True
    for name, items in YARDS.items():
        group = []
        wb = L.new_bm()
        bmesh.ops.create_cube(wb, size=1.0)
        L.transform(wb, Matrix.Translation((0, 1.35 + 0.15, 1.6)) @ Matrix.Diagonal((6.0, 0.3, 3.2, 1)))
        w = L.to_object(wb, "_wallblock", "MI_WoodTrim", smooth_angle=None)
        w.data.materials.clear()
        w.data.materials.append(wall_m)
        group.append(w)
        for model, x, y, yaw in items:
            if model not in by:
                continue
            c = by[model].copy()
            sc.collection.objects.link(c)
            c.hide_render = False
            c.location = (x, y, 0)
            c.rotation_euler = (0, 0, math.radians(yaw))
            group.append(c)
        man = bpy.data.objects.get("_mannequin")
        if man:
            man.location = (0.9, -2.0, 0)
        cam_data = bpy.data.cameras.new("_ycam")
        cam = bpy.data.objects.new("_ycam", cam_data)
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam_data.lens = 32
        sc.render.resolution_x, sc.render.resolution_y = 1280, 800
        for view, eye, look in (("front34", (4.2, -6.2, 3.6), (0.0, 0.0, 1.0)), ("top", (1.2, -6.5, 9.0), (0.0, -0.1, 0.4))):
            cam.location = eye
            cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = "%s_%s_%s.png" % (out, name, view)
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
            save_blend(built, os.path.join(HERE, "smithy.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for obj in built:
            for o in built:
                o.hide_render = o is not obj
            h = max(obj.dimensions.z, 0.6)
            ext = max(obj.dimensions.x, obj.dimensions.y, h, 1.6) * 1.1
            views = [("front34", -35, 18, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 38, 10.0, 50), ("close", -40, 14, 3.4, 42)]
            for p in BC.review([obj], os.path.join(out, obj.name), views=views, extent=ext, center_z=h * 0.45):
                print("  ", p)
    if "--yards" in args:
        out = args[args.index("--yards") + 1]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        for p in yards(built, out):
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
