"""Builds the Home Yard family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_home.py [--review DIR] [--yards DIR/name] [--lineup DIR/name] [--export] [--only A,B]

The things around a home that show how its family lives: a bench by the
door, a kitchen garden, the chopping block, a water butt, a laundry line
and hens, from a poor cottage (a log bench, a dug bed) to a prosperous
townhouse (a painted bench with flower pots). Wood, stone and iron are
UV-mapped onto the village kit's trim sheets, garden plants and straw onto
the farm atlas (farm-field), cloth, blossoms, hens, pots, soil and paint
onto this family's small atlas (T_Home_BaseColor.png, paint_home.py).

Origin at the ground, front = -Y in Blender (+Z in Godot): a bench faces
-Y with its back to the house wall (+Y).
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
import build_commons as BC  # noqa: E402  (review, lineup, set_uv_rect, water_disc)
import build_farm as BF  # noqa: E402  (cabbage and turnip plants, the farm atlas)

FAMILY = os.path.dirname(HERE)
HOME = "MI_Home"
HOME_TEX = os.path.join(FAMILY, "textures", "T_Home_BaseColor.png")
WATER = "MI_Home_Water"
OWN = {
    HOME: {"doubleSided": True, "dir": os.path.join(FAMILY, "textures"),
           "pbr": {"baseColorTexture": "T_Home_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}},
    WATER: {"doubleSided": False, "pbr": {"baseColorFactor": [0.05, 0.09, 0.09, 1.0], "metallicFactor": 0, "roughnessFactor": 0.2}},
}
OWN.update(BF.OWN)  # MI_Farm
# Home atlas regions (u0, v0, u1, v1), Blender UV space (v up).
H = {
    "linen": (0.004, 0.754, 0.496, 0.996), "madder": (0.504, 0.754, 0.662, 0.996),
    "woad": (0.67, 0.754, 0.829, 0.996), "weld": (0.837, 0.754, 0.996, 0.996),
    "flower_red": (0.004, 0.504, 0.246, 0.746), "flower_yellow": (0.254, 0.504, 0.496, 0.746),
    "flower_white": (0.504, 0.504, 0.746, 0.746), "leaf": (0.754, 0.504, 0.996, 0.746),
    "hen_white": (0.004, 0.254, 0.246, 0.496), "hen_brown": (0.254, 0.254, 0.496, 0.496),
    "comb": (0.504, 0.254, 0.746, 0.496), "beak": (0.754, 0.254, 0.996, 0.496),
    "pot": (0.004, 0.004, 0.246, 0.246), "soil": (0.254, 0.004, 0.496, 0.246),
    "paint_green": (0.504, 0.004, 0.746, 0.246), "paint_blue": (0.754, 0.004, 0.996, 0.246),
}
IRON = L.RECTS["iron_plate"][1:]


# --- Helpers -------------------------------------------------------------------------------------

def region(bm, name):
    """Maps a part's UVs into a region of the home atlas."""
    BC.set_uv_rect(bm, H[name])
    return bm


def planar(bm, name, a=0, b=2):
    """Planar UVs (axes a, b of the part's bounds) into a home-atlas region."""
    uv = bm.loops.layers.uv["UVMap"]
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    u0, v0, u1, v1 = H[name]
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            s = (p[a] - lo[a]) / max(hi[a] - lo[a], 1e-6)
            t = (p[b] - lo[b]) / max(hi[b] - lo[b], 1e-6)
            l[uv].uv = (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)
    return bm


def block(x0, x1, y0, y1, z0, z1, band, bevel=0.012, rng=None, tilt=0.0):
    bm = L.box((x1 - x0, y1 - y0, z1 - z0), band, bevel=bevel, segments=1, rng=rng)
    if tilt and rng:
        L.transform(bm, Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "X") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "Y"))
    L.transform(bm, Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)))
    return bm


def board_uv(bm, band, rng):
    """Wood-band UVs for a wide, flat board (a wall course): the grain runs
    along each face, its height stays inside the band. (`L.box` wraps the
    band round the cross-section, which on a deep board runs off the band.)"""
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS[band]
    zmin = min(v.co.z for v in bm.verts)
    zmax = max(v.co.z for v in bm.verts)
    v_off = rng.uniform(0.0, max(0.0, (v1 - v0) - (zmax - zmin) * L.UV_PER_M))
    u_off = rng.uniform(0.0, 1.0)
    for f in bm.faces:
        n = f.normal
        for l in f.loops:
            p = l.vert.co
            if abs(n.z) > 0.8:
                l[uv].uv = (u_off + p.x * L.UV_PER_M, v0 + v_off + (p.y - min(v.co.y for v in f.verts)) * 0.15 * L.UV_PER_M)
                continue
            u = p.x if abs(n.y) >= abs(n.x) else p.y + 2.0
            l[uv].uv = (u_off + u * L.UV_PER_M, v0 + v_off + (p.z - zmin) * L.UV_PER_M)
    return bm


def stump(at, r, h, seed):
    bm = L.log((at[0], at[1], -0.04), (at[0], at[1], h), r, sides=9, band="wood_dark", taper=0.95, jitter=0.07, seed=seed)
    return L.to_object(bm, "stump", "MI_WoodTrim", smooth_angle=50)


def plant(fn, at, yaw, scale):
    """One of the farm's crop plants (a list of objects), placed."""
    objs = fn()
    for o in objs:
        o.location = at
        o.rotation_euler = (0, 0, yaw)
        o.scale = (scale, scale, scale)
    return objs


def herb(at, seed, height=0.28, blades=7, name="leaf"):
    """A clump of upright leaves (herbs, leeks)."""
    rng = random.Random(seed)
    bm = L.new_bm()
    for k in range(blades):
        a = k * math.tau / blades + rng.uniform(-0.3, 0.3)
        lean = rng.uniform(0.15, 0.4)
        h = height * rng.uniform(0.75, 1.1)
        w = 0.035
        side = Vector((-math.sin(a), math.cos(a), 0)) * w
        base = Vector((math.cos(a) * 0.02, math.sin(a) * 0.02, 0))
        tip = base + Vector((math.cos(a) * lean * h, math.sin(a) * lean * h, h))
        vs = [bm.verts.new(base - side), bm.verts.new(base + side), bm.verts.new(tip)]
        bm.faces.new(vs)
    planar(bm, name, 0, 2)
    L.transform(bm, Matrix.Translation(at))
    return bm


def blossom_clump(at, r, h, seed, flower="flower_red", count=11):
    """A bushy plant in flower over a pot (or a bed): a low mound of leaves
    spilling over the rim, and a dome of blossoms on it."""
    rng = random.Random(seed)
    leaves = L.new_bm()
    for k in range(12):
        a = k * math.tau / 12 + rng.uniform(-0.2, 0.2)
        out = r * rng.uniform(0.9, 1.25)
        lift = h * rng.uniform(0.25, 0.55)
        w = r * 0.32
        side = Vector((-math.sin(a), math.cos(a), 0)) * w
        base = Vector((math.cos(a) * r * 0.15, math.sin(a) * r * 0.15, h * 0.1))
        tip = Vector((math.cos(a) * out, math.sin(a) * out, lift))
        mid = base.lerp(tip, 0.5) + Vector((0, 0, h * 0.18))
        vs = [leaves.verts.new(p) for p in (base, mid - side, tip, mid + side)]
        leaves.faces.new(vs)
    planar(leaves, "leaf", 0, 1)
    flowers = L.new_bm()
    for k in range(count):
        a = k * 2.39996 + rng.uniform(-0.2, 0.2)  # golden angle: an even dome
        d = math.sqrt((k + 0.5) / count) * r * 0.95
        s = r * rng.uniform(0.32, 0.44)
        z = h * 0.42 + (1.0 - d / r) * h * 0.38
        L.merge_bm(flowers, L.stone((math.cos(a) * d, math.sin(a) * d, z), (s, s, s * 0.55), seed=seed * 13 + k, detail=1, rough=0.1))
    region(flowers, flower)
    for bm in (leaves, flowers):
        L.transform(bm, Matrix.Translation(at))
    return [L.to_object(leaves, "leaves", HOME, smooth_angle=60, recalc=False), L.to_object(flowers, "blossoms", HOME, smooth_angle=60, recalc=False)]


def pot(at, r, h, seed, flower):
    prof = [(0.0, 0.0), (r * 0.7, 0.0), (r * 0.72, 0.02), (r, h * 0.85), (r * 1.08, h * 0.87), (r * 1.08, h), (r * 0.95, h), (r * 0.9, h * 0.9), (0.0, h * 0.9)]
    body = L.lathe(prof, 10, band="rock_slate")
    region(body, "pot")
    L.transform(body, Matrix.Translation(at))
    soil = L.lathe([(r * 0.92, h * 0.9 - 0.005), (0.0, h * 0.9)], 10, band="rock_slate")
    region(soil, "soil")
    L.transform(soil, Matrix.Translation(at))
    parts = [L.to_object(body, "pot", HOME, smooth_angle=40, recalc=False), L.to_object(soil, "pot_soil", HOME, smooth_angle=40, recalc=False)]
    parts += blossom_clump((at[0], at[1], at[2] + h * 0.86), r * 1.0, h * 0.9, seed, flower)
    return parts


def hen(at, yaw, seed, colour="hen_white", pecking=False):
    """A low-poly hen: body, head, comb, beak, tail, legs."""
    parts = []
    m = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z")
    body = L.lathe([(0.0, -0.11), (0.06, -0.1), (0.1, -0.03), (0.1, 0.04), (0.07, 0.1), (0.0, 0.12)], 8, band="rock_slate")
    L.transform(body, Matrix.Translation((0, 0, 0.17)) @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Diagonal((1.0, 0.85, 1.0, 1)))
    region(body, colour)
    hz = 0.24 if not pecking else 0.12
    hx = 0.13 if not pecking else 0.17
    head = L.lathe([(0.0, -0.045), (0.04, -0.025), (0.045, 0.01), (0.03, 0.04), (0.0, 0.05)], 6, band="rock_slate")
    L.transform(head, Matrix.Translation((hx, 0, hz)))
    region(head, colour)
    neck = L.sweep([(0.07, 0, 0.2), (hx, 0, hz)], 0.035, sides=6, rect="iron_bar")
    region(neck, colour)
    tail = L.new_bm()
    vs = [tail.verts.new(p) for p in ((-0.08, -0.04, 0.2), (-0.08, 0.04, 0.2), (-0.17, 0.0, 0.33))]
    tail.faces.new(vs)
    region(tail, colour)
    feathers = L.new_bm()
    for bm in (body, head, neck, tail):
        L.merge_bm(feathers, bm)
    L.transform(feathers, m)
    parts.append(L.to_object(feathers, "hen", HOME, smooth_angle=60, recalc=False))
    comb = block(hx - 0.02, hx + 0.025, -0.008, 0.008, hz + 0.03, hz + 0.065, "rock_slate", bevel=0.005)
    region(comb, "comb")
    beak = L.sweep([(hx + 0.04, 0, hz - 0.005), (hx + 0.075, 0, hz - 0.015)], 0.012, sides=4, rect="iron_bar", radius_fn=lambda t: 1.0 - 0.9 * t)
    region(beak, "beak")
    legs = L.new_bm()
    for y in (-0.03, 0.03):
        L.merge_bm(legs, L.sweep([(0.0, y, 0.09), (0.01, y, 0.0)], 0.008, sides=4, rect="iron_bar"))
    region(legs, "beak")
    for bm in (comb, beak, legs):
        L.merge_bm(bm, L.new_bm())
        L.transform(bm, m)
    parts.append(L.to_object(comb, "comb", HOME, smooth_angle=30))
    parts.append(L.to_object(beak, "beak", HOME, smooth_angle=60, recalc=False))
    parts.append(L.to_object(legs, "legs", HOME, smooth_angle=60, recalc=False))
    return parts


def cloth(x0, width, top, height, colour, seed, cols=3, rows=2, wave=0.03):
    """A cloth hanging from the line: a gently waved grid, pegged at the top.
    `top(x)` is the height of the line at x, so the cloth follows its sag."""
    rng = random.Random(seed)
    bm = L.new_bm()
    grid = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            s, t = i / cols, j / rows
            y = math.sin(s * math.pi * 1.5 + seed) * wave * t + rng.uniform(-0.005, 0.005)
            x = x0 + width * s
            row.append(bm.verts.new((x, y, top(x) - 0.01 - height * t * (1.0 - 0.06 * math.sin(s * math.pi)))))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
    planar(bm, colour, 0, 2)
    bm.normal_update()
    return bm


# --- Benches -------------------------------------------------------------------------------------

def bench_log():
    """A poor cottage: a split log on two stumps against the wall."""
    rng = random.Random(201)
    parts = [stump((-0.5, 0.0), 0.13, 0.3, 202), stump((0.5, 0.0), 0.12, 0.3, 203)]
    seat = L.log((-0.72, 0.0, 0.0), (0.72, 0.0, 0.0), 0.16, sides=9, band="wood_dark", taper=0.92, jitter=0.06, seed=204)
    L.transform(seat, Matrix.Diagonal((1.0, 1.0, 0.55, 1)))
    L.transform(seat, Matrix.Translation((0, 0, 0.36)))
    parts.append(L.to_object(seat, "seat", "MI_WoodTrim", smooth_angle=50))
    return parts


def bench_plank(painted=None):
    """A plank bench with a back rail on splayed legs (`painted`: an atlas
    region for a townhouse's coat of paint)."""
    rng = random.Random(205 if not painted else 206)
    parts = []
    seat = block(-0.72, 0.72, -0.17, 0.17, 0.42, 0.47, "wood_light", bevel=0.012, rng=rng)
    back = block(-0.72, 0.72, 0.13, 0.17, 0.66, 0.8, "wood_light", bevel=0.01, rng=rng)
    frame = L.new_bm()
    for x in (-0.58, 0.58):
        for y0, y1 in ((-0.12, -0.15), (0.12, 0.15)):
            L.merge_bm(frame, L.beam((x, y1, 0.0), (x * 1.0, y0, 0.43), 0.05, 0.05, band="wood_dark", rng=rng))
        L.merge_bm(frame, L.beam((x, 0.15, 0.4), (x, 0.15, 0.8), 0.045, 0.045, band="wood_dark", rng=rng))
        L.merge_bm(frame, L.beam((x, -0.15, 0.2), (x, 0.15, 0.2), 0.035, 0.035, band="wood_dark", rng=rng))
    mat = "MI_WoodTrim"
    if painted:
        for bm in (seat, back, frame):
            region(bm, painted)
        mat = HOME
    parts.append(L.to_object(seat, "seat", mat, smooth_angle=30))
    parts.append(L.to_object(back, "back", mat, smooth_angle=30))
    parts.append(L.to_object(frame, "frame", mat, smooth_angle=30))
    return parts


def bench():
    return bench_plank()


def bench_painted():
    """A townhouse: the plank bench painted green, a cushion of madder cloth."""
    parts = bench_plank("paint_green")
    cushion = block(-0.3, 0.3, -0.14, 0.12, 0.47, 0.53, "wood_light", bevel=0.02)
    region(cushion, "madder")
    parts.append(L.to_object(cushion, "cushion", HOME, smooth_angle=50))
    return parts


# --- Gardens -------------------------------------------------------------------------------------

def soil_bed(x, y, z0, z1, rows=0):
    """A raked soil mound (a dug bed) with optional row furrows along X."""
    bm = L.new_bm()
    bmesh.ops.create_grid(bm, x_segments=6, y_segments=max(2, rows * 2), size=0.5)
    for v in bm.verts:
        v.co.x *= x
        v.co.y *= y
        edge = min(1 - abs(v.co.x) / (x * 0.5 + 1e-6), 1 - abs(v.co.y) / (y * 0.5 + 1e-6))
        furrow = 0.5 + 0.5 * math.cos((v.co.y / y + 0.5) * rows * math.tau) if rows else 1.0
        v.co.z = z0 + (z1 - z0) * min(1.0, edge * 4.0) * (0.75 + 0.25 * furrow)
    bm.normal_update()
    planar(bm, "soil", 0, 1)
    return bm


def garden_poor():
    """A poor cottage: a dug bed of cabbages and turnips edged with stones."""
    rng = random.Random(211)
    parts = [L.to_object(soil_bed(2.0, 1.2, -0.02, 0.1, rows=2), "bed", HOME, smooth_angle=40, recalc=False)]
    stones = L.new_bm()
    k = 0
    for x in (-1.02, 1.02):
        for y in (-0.4, 0.05, 0.45):
            L.merge_bm(stones, L.stone((x, y + rng.uniform(-0.05, 0.05), 0.04), (0.18, 0.22, 0.1), seed=220 + k, band="rock_slate", detail=1))
            k += 1
    parts.append(L.to_object(stones, "stones", "MI_RockTrim", smooth_angle=60, recalc=False))
    for i, x in enumerate((-0.6, 0.05, 0.65)):
        parts += plant(BF.crop_cabbage, (x, -0.25, 0.07), rng.uniform(0, math.tau), 0.8)
    for i, x in enumerate((-0.7, -0.25, 0.25, 0.7)):
        parts += plant(BF.crop_turnip, (x, 0.3, 0.07), rng.uniform(0, math.tau), 0.85)
    return parts


def garden():
    """An ordinary home and better: a plank-edged raised bed with cabbages,
    herbs and leeks, and a wigwam of bean canes climbing with leaves."""
    rng = random.Random(231)
    parts = []
    frame = L.new_bm()
    for y in (-0.62, 0.62):
        L.merge_bm(frame, block(-1.1, 1.1, y - 0.025, y + 0.025, -0.02, 0.22, "wood_light", bevel=0.008, rng=rng))
    for x in (-1.1, 1.1):
        b = block(-0.6, 0.6, -0.025, 0.025, -0.02, 0.22, "wood_light", bevel=0.008, rng=rng)
        L.transform(b, Matrix.Translation((x, 0, 0)) @ Matrix.Rotation(math.pi / 2, 4, "Z"))
        L.merge_bm(frame, b)
    for x in (-1.1, 1.1):
        for y in (-0.62, 0.62):
            L.merge_bm(frame, L.beam((x, y, -0.02), (x, y, 0.27), 0.06, 0.06, band="wood_dark", rng=rng))
    parts.append(L.to_object(frame, "frame", "MI_WoodTrim", smooth_angle=30))
    parts.append(L.to_object(soil_bed(2.15, 1.2, 0.1, 0.2, rows=3), "bed", HOME, smooth_angle=40, recalc=False))
    for x in (-0.8, -0.3, 0.2):
        parts += plant(BF.crop_cabbage, (x, -0.32, 0.18), rng.uniform(0, math.tau), 0.75)
    greens = L.new_bm()
    for k, x in enumerate((-0.85, -0.5, -0.15, 0.2)):
        L.merge_bm(greens, herb((x, 0.3, 0.18), 240 + k, height=0.3))
    parts.append(L.to_object(greens, "herbs", HOME, smooth_angle=60, recalc=False))
    # Bean canes: four poles tied at the top, leaves climbing them.
    canes = L.new_bm()
    top = Vector((0.72, 0.05, 1.45))
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        foot = Vector((0.72 + math.cos(a) * 0.32, 0.05 + math.sin(a) * 0.32, 0.12))
        L.merge_bm(canes, L.sweep([foot, top + Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0.08))], 0.012, sides=5, band="wood_light"))
    parts.append(L.to_object(canes, "canes", "MI_WoodTrim", smooth_angle=60, recalc=False))
    vines = L.new_bm()
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        foot = Vector((0.72 + math.cos(a) * 0.32, 0.05 + math.sin(a) * 0.32, 0.12))
        for j in range(4):
            t = 0.15 + j * 0.2
            p = foot.lerp(top, t)
            L.merge_bm(vines, herb(p, 260 + k * 7 + j, height=0.16, blades=4))
    parts.append(L.to_object(vines, "bean_leaves", HOME, smooth_angle=60, recalc=False))
    return parts


# --- Chores --------------------------------------------------------------------------------------

def chopping_block():
    """A stump with the axe left in it, split wood around and a stack of it."""
    rng = random.Random(251)
    parts = [stump((0.0, 0.0), 0.25, 0.42, 252)]
    handle = L.beam((0.0, 0.0, 0.0), (0.0, 0.0, 0.62), 0.032, 0.036, band="wood_light", rng=rng)
    L.transform(handle, Matrix.Translation((0.05, 0.02, 0.43)) @ Matrix.Rotation(math.radians(-38), 4, "Y"))
    parts.append(L.to_object(handle, "axe_handle", "MI_WoodTrim", smooth_angle=30))
    head = block(-0.06, 0.08, -0.018, 0.018, -0.05, 0.05, "wood_dark", bevel=0.006)
    BC.set_uv_rect(head, IRON)
    L.transform(head, Matrix.Translation((0.04, 0.02, 0.45)) @ Matrix.Rotation(math.radians(-38), 4, "Y"))
    parts.append(L.to_object(head, "axe_head", "MI_MetalOrnaments", smooth_angle=30))
    split = L.new_bm()
    for k in range(5):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.35, 0.6)
        piece = L.log((0, 0, 0), (0.34, 0, 0), 0.06, sides=4, band="wood_dark", taper=1.0, jitter=0.05, seed=260 + k, rings=1)
        L.transform(piece, Matrix.Translation((math.cos(a) * d, math.sin(a) * d, 0.05)) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z"))
        L.merge_bm(split, piece)
    for row in range(3):
        for k in range(4 - row):
            piece = L.log((0, 0, 0), (0, 0.4, 0), 0.06, sides=4, band="wood_dark", taper=1.0, jitter=0.04, seed=270 + row * 5 + k, rings=1)
            L.transform(piece, Matrix.Translation((-0.75 + k * 0.13 + row * 0.065, -0.2, 0.06 + row * 0.11)))
            L.merge_bm(split, piece)
    parts.append(L.to_object(split, "split_wood", "MI_WoodTrim", smooth_angle=50))
    return parts


def water_butt():
    """Rain water by the wall: a coopered butt on two flat stones, its lid
    pushed half aside, a dipper hung on the rim."""
    rng = random.Random(281)
    parts = []
    stones = L.new_bm()
    for x in (-0.2, 0.2):
        L.merge_bm(stones, L.stone((x, 0.0, 0.03), (0.3, 0.5, 0.1), seed=282 + (x > 0), band="rock_slate", detail=1))
    parts.append(L.to_object(stones, "stones", "MI_RockTrim", smooth_angle=60, recalc=False))
    prof = [(0.0, 0.06), (0.29, 0.06), (0.31, 0.09), (0.35, 0.45), (0.33, 0.86), (0.32, 0.9), (0.29, 0.9), (0.3, 0.84), (0.0, 0.84)]
    parts.append(L.to_object(L.lathe(prof, 14, band="wood_light", jitter=0.012, seed=283), "butt", "MI_WoodTrim", smooth_angle=12))
    hoops = L.new_bm()
    for z, r in ((0.16, 0.325), (0.45, 0.354), (0.78, 0.338)):
        pts = L.arc_points((0, 0, z), r, 0, math.tau, 17, axis="Z")[:-1]
        L.merge_bm(hoops, L.sweep(pts, 0.012, sides=4, rect="iron_plate", closed=True))
    parts.append(L.to_object(hoops, "hoops", "MI_MetalOrnaments", smooth_angle=60, recalc=False))
    parts.append(L.to_object(BC.water_disc(0.3, 0.82, 14), "water", WATER, smooth_angle=None, recalc=False))
    lid = L.lathe([(0.0, 0.0), (0.33, 0.0), (0.33, 0.035), (0.0, 0.035)], 14, band="wood_light")
    L.transform(lid, Matrix.Translation((0.14, 0.05, 0.9)) @ Matrix.Rotation(0.06, 4, "Y"))
    parts.append(L.to_object(lid, "lid", "MI_WoodTrim", smooth_angle=20))
    knob = block(0.06, 0.22, -0.02, 0.02, 0.935, 0.965, "wood_dark", bevel=0.006)
    L.transform(knob, Matrix.Translation((0.08, 0.05, 0)))
    parts.append(L.to_object(knob, "lid_handle", "MI_WoodTrim", smooth_angle=30))
    dipper = L.lathe([(0.0, 0.0), (0.06, 0.0), (0.07, 0.06), (0.06, 0.06), (0.0, 0.01)], 8, band="wood_light")
    L.transform(dipper, Matrix.Translation((-0.36, -0.08, 0.68)))
    parts.append(L.to_object(dipper, "dipper", "MI_WoodTrim", smooth_angle=40))
    hand = L.beam((-0.36, -0.08, 0.72), (-0.3, -0.06, 0.93), 0.02, 0.02, band="wood_light", rng=rng)
    parts.append(L.to_object(hand, "dipper_handle", "MI_WoodTrim", smooth_angle=30))
    return parts


def laundry_line():
    """Washing on the line between two forked poles: a linen sheet, a red
    shirt, a blue tunic, a yellow cloth and a small linen."""
    rng = random.Random(291)
    parts = []
    poles = L.new_bm()
    for x in (0.0, 2.6):
        L.merge_bm(poles, L.log((x, 0, -0.05), (x + rng.uniform(-0.04, 0.04), 0, 1.85), 0.045, sides=6, band="wood_dark", taper=0.85, jitter=0.1, seed=292 + int(x)))
        for s in (-1, 1):
            L.merge_bm(poles, L.log((x, 0, 1.78), (x + s * 0.12, 0, 1.98), 0.025, sides=5, band="wood_dark", taper=0.8, jitter=0.1, seed=295 + s))
    parts.append(L.to_object(poles, "poles", "MI_WoodTrim", smooth_angle=50))
    line = [(0.0 + 2.6 * i / 10, 0, 1.82 - 0.14 * math.sin(math.pi * i / 10)) for i in range(11)]
    parts.append(BC.rope(line, r=0.009))

    def at(x):
        return 1.82 - 0.14 * math.sin(math.pi * x / 2.6)
    washing = L.new_bm()
    for x0, w, h, colour in ((0.18, 0.78, 1.0, "linen"), (1.05, 0.46, 0.62, "madder"), (1.58, 0.42, 0.55, "woad"), (2.05, 0.36, 0.42, "weld")):
        L.merge_bm(washing, cloth(x0, w, at, h, colour, int(x0 * 10), cols=4 if w > 0.6 else 3))
    parts.append(L.to_object(washing, "washing", HOME, smooth_angle=40, recalc=False))
    pegs = L.new_bm()
    for x in (0.2, 0.94, 1.07, 1.49, 1.6, 1.98, 2.07, 2.39):
        L.merge_bm(pegs, block(x - 0.012, x + 0.012, -0.012, 0.012, at(x) - 0.06, at(x) + 0.01, "wood_light", bevel=0.004))
    parts.append(L.to_object(pegs, "pegs", "MI_WoodTrim", smooth_angle=30))
    for o in parts:  # centred on the line (in the mesh: the first part's origin is the model's)
        o.data.transform(Matrix.Translation((-1.3, 0, 0)))
    return parts


def chicken_coop():
    """A hen house on legs with a straw-thatched roof, a ramp to its door and
    three hens about."""
    rng = random.Random(301)
    parts = []
    house = L.new_bm()
    L.merge_bm(house, board_uv(block(-0.53, 0.53, -0.38, 0.38, 0.42, 1.05, "wood_dark", bevel=0.01, rng=rng), "wood_dark", rng))
    for k in range(6):  # wall boards, dark seams between them
        z = 0.42 + k * 0.105
        L.merge_bm(house, board_uv(block(-0.555, 0.555, -0.405, 0.405, z, z + 0.105, "wood_light", bevel=0.01, rng=rng), "wood_light", rng))
    for x in (-0.5, 0.5):
        for y in (-0.35, 0.35):
            L.merge_bm(house, L.beam((x, y, 0.0), (x, y, 0.46), 0.07, 0.07, band="wood_dark", rng=rng))
    parts.append(L.to_object(house, "house", "MI_WoodTrim", smooth_angle=30))
    door = block(-0.14, 0.14, -0.43, -0.405, 0.44, 0.72, "wood_dark", bevel=0.006, rng=rng)
    parts.append(L.to_object(door, "door", "MI_WoodTrim", smooth_angle=30))
    hinges = L.new_bm()
    for z in (0.5, 0.66):
        L.merge_bm(hinges, block(-0.15, 0.02, -0.438, -0.428, z, z + 0.025, "wood_dark", bevel=0.003))
    BC.set_uv_rect(hinges, IRON)
    parts.append(L.to_object(hinges, "hinges", "MI_MetalOrnaments", smooth_angle=30))
    # A straw roof: two thick slopes meeting at a ridge along X.
    roof = L.new_bm()
    for s in (-1, 1):
        slab = L.box((1.36, 0.6, 0.08), "wood_light", bevel=0.02)
        L.transform(slab, Matrix.Translation((0, s * 0.24, 1.2)) @ Matrix.Rotation(-s * math.radians(32), 4, "X"))
        L.merge_bm(roof, slab)
    _, v0, v1 = L.BANDS["straw"]
    uv = roof.loops.layers.uv["UVMap"]
    for f in roof.faces:
        for l in f.loops:
            p = l.vert.co
            l[uv].uv = ((p.x + 0.7) * 0.7, v0 + (v1 - v0) * min(1.0, max(0.0, (1.36 - p.z) / 0.4)))
    parts.append(L.to_object(roof, "roof", BF.FARM, smooth_angle=40, recalc=False))
    gables = L.new_bm()
    rise = 0.405 * math.tan(math.radians(32))
    for x in (-0.53, 0.53):
        g = L.new_bm()
        vs = [g.verts.new((x, y, z)) for y, z in ((-0.405, 1.05), (0.405, 1.05), (0.0, 1.05 + rise))]
        g.faces.new(vs if x > 0 else vs[::-1])
        g.normal_update()
        bmesh.ops.solidify(g, geom=list(g.faces), thickness=0.03)
        bmesh.ops.recalc_face_normals(g, faces=g.faces)
        uv = g.loops.layers.uv["UVMap"]
        _, v0, v1 = L.BANDS["wood_dark"]
        for f in g.faces:
            for l in f.loops:
                l[uv].uv = (l.vert.co.y * L.UV_PER_M + 0.3, v0 + 0.02 + (l.vert.co.z - 1.05) * L.UV_PER_M)
        L.merge_bm(gables, g)
    parts.append(L.to_object(gables, "gables", "MI_WoodTrim", smooth_angle=20, recalc=False))
    # The ramp runs from the door sill down to the ground in front, with cleats.
    ramp = L.beam((0, 0.02, 0.0), (0, -0.72, 0.0), 0.24, 0.03, band="wood_light", bevel=0.006, rng=rng)
    for k in range(4):
        L.merge_bm(ramp, L.beam((-0.11, -0.12 - k * 0.15, 0.025), (0.11, -0.12 - k * 0.15, 0.025), 0.03, 0.022, band="wood_dark", bevel=0.003, rng=rng))
    L.transform(ramp, Matrix.Translation((0, -0.41, 0.44)) @ Matrix.Rotation(math.radians(36), 4, "X"))
    parts.append(L.to_object(ramp, "ramp", "MI_WoodTrim", smooth_angle=30))
    parts += hen((0.55, -0.95, 0.0), math.radians(-60), 311, "hen_white", pecking=True)
    parts += hen((-0.45, -0.85, 0.0), math.radians(200), 312, "hen_brown")
    parts += hen((0.1, -1.3, 0.0), math.radians(100), 313, "hen_brown", pecking=True)
    return parts


def flower_pots():
    """A townhouse: three terracotta pots of red, yellow and white flowers."""
    parts = []
    parts += pot((0.0, 0.0, 0.0), 0.17, 0.3, 321, "flower_red")
    parts += pot((0.36, 0.06, 0.0), 0.13, 0.24, 322, "flower_yellow")
    parts += pot((-0.3, 0.1, 0.0), 0.11, 0.2, 323, "flower_white")
    return parts


BUILDERS = {
    "SE_Bench_Log": bench_log,
    "SE_Bench": bench,
    "SE_Bench_Painted": bench_painted,
    "SE_Garden_Poor": garden_poor,
    "SE_Garden": garden,
    "SE_ChoppingBlock": chopping_block,
    "SE_WaterButt": water_butt,
    "SE_LaundryLine": laundry_line,
    "SE_ChickenCoop": chicken_coop,
    "SE_FlowerPots": flower_pots,
}

# Collision proxies (these are walk-through dressing in game; kept for other uses).
COLLIDERS = {
    "SE_Bench_Log": ("box", 1.45, 0.35, 0.45, 0.0), "SE_Bench": ("box", 1.45, 0.35, 0.8, 0.0), "SE_Bench_Painted": ("box", 1.45, 0.35, 0.8, 0.0),
    "SE_ChoppingBlock": ("cyl", 0.3, 0.45), "SE_WaterButt": ("cyl", 0.36, 0.95), "SE_ChickenCoop": ("box", 1.2, 0.85, 1.4, 0.0),
}


def setup():
    L.reset()
    L.custom_material(HOME, (1.0, 1.0, 1.0), roughness=0.85, image=HOME_TEX)
    L.custom_material(BF.FARM, (1.0, 1.0, 1.0), roughness=0.9, image=BF.FARM_TEX)
    L.custom_material(WATER, (0.05, 0.09, 0.09), roughness=0.2)


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        objs = fn()
        for o in objs:  # apply placement (farm plants are placed by transform)
            if o.scale != Vector((1, 1, 1)) or o.rotation_euler.z != 0:
                with bpy.context.temp_override(object=o, active_object=o, selected_editable_objects=[o]):
                    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        obj = L.join(objs, name)
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
        o.location = ((i % 4) * 3.5, (i // 4) * 3.5, 0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)


# The yards as laid out in game round a 6 x 4 m cottage (data/props.json
# "dressing": cottage), by home tier. Blender frame: front (door side) -Y.
YARDS = {
    0: [("SE_Bench_Log", 1.65, -2.4, 0), ("SE_Garden_Poor", -1.5, 3.6, 180), ("SE_LaundryLine", 1.6, 3.3, 180), ("SE_ChoppingBlock", -3.9, -0.2, -90)],
    1: [("SE_Bench", 1.65, -2.4, 0), ("SE_Garden", -1.5, 3.6, 180), ("SE_LaundryLine", 1.6, 3.3, 180), ("SE_ChoppingBlock", -3.9, -0.2, -90),
        ("SE_WaterButt", -3.55, -1.4, -90), ("SE_ChickenCoop", 4.1, 0.6, 90)],
    2: [("SE_Bench_Painted", 1.65, -2.4, 0), ("SE_FlowerPots", 2.7, -2.45, 0), ("SE_Garden", -1.5, 3.6, 180), ("SE_LaundryLine", 1.6, 3.3, 180),
        ("SE_WaterButt", -3.55, -1.4, -90), ("SE_FlowerPots", -3.4, -0.5, 30)],
}


def yards(objs, out):
    """Each home tier's yard round a stand-in cottage, from the front and
    from above."""
    by = {o.name: o for o in objs}
    BC.review([], out, views=[("setup", 0, 30, 1.0, 40)], res=(32, 32))
    sc = bpy.context.scene
    wall_m = L.custom_material("_wall", (0.72, 0.68, 0.6), roughness=0.9)
    paths = []
    for o in objs:
        o.hide_render = True
    for tier, items in YARDS.items():
        group = []
        hb = L.new_bm()
        bmesh.ops.create_cube(hb, size=1.0)
        L.transform(hb, Matrix.Translation((0, 0, 1.5)) @ Matrix.Diagonal((6.0, 4.0, 3.0, 1)))
        house = L.to_object(hb, "_house", "MI_WoodTrim", smooth_angle=None)
        house.data.materials.clear()
        house.data.materials.append(wall_m)
        group.append(house)
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
            man.location = (0.4, -3.4, 0)
        cam_data = bpy.data.cameras.new("_ycam")
        cam = bpy.data.objects.new("_ycam", cam_data)
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam_data.lens = 28
        sc.render.resolution_x, sc.render.resolution_y = 1280, 800
        for view, eye, look in (("front34", (7.5, -9.5, 6.0), (0.0, -0.5, 0.8)), ("back34", (-7.5, 10.0, 6.5), (0.0, 1.5, 0.6)), ("top", (0.5, -3.0, 16.0), (0.0, 0.3, 0.0))):
            cam.location = eye
            cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = "%s_%d_%s.png" % (out, tier, view)
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
            save_blend(built, os.path.join(HERE, "home_yard.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for obj in built:
            for o in built:
                o.hide_render = o is not obj
            h = max(obj.dimensions.z, 0.6)
            ext = max(obj.dimensions.x, obj.dimensions.y, h, 1.4) * 1.1
            views = [("front34", -35, 18, 6.0, 40), ("rear34", 150, 20, 6.0, 40), ("gameplay", -20, 38, 10.0, 50), ("close", -40, 16, 3.4, 42)]
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
