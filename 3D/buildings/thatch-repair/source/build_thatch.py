"""Builds the Thatch & Repair family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_thatch.py [--review DIR] [--export] [--only A,B]

What a poor home is roofed and mended with, and what it is roofed with
once the family does better:

- Thatched roofs to sit on the village kit's walls in place of its tiled
  roofs: a weathered one for a cottage (grey straw, moss, a sagging ridge
  and a patch of new straw), a neat one for a Timber House and a farmhouse
  (golden straw, a block-cut ridge with liggers and crossed spars). Hipped
  all round with rounded hips, so no gable is needed; thick rounded eaves.
- Patches for a poor home's walls: wattle showing where the daub has
  fallen away, a smear of new daub, boards nailed over a hole.
- Plank shutters for its windows (the kit's three window shapes), open
  with one leaf hanging from a lost hinge, or shut with a board gone.

Roofs: origin at the top of the walls (the kit's roof convention), span
along X, ridge along Y; `VillageKit` places them as it places
Roof_RoundTiles_<span>x<length>. Shutters: the kit's wall-module frame
(origin at the foot of the wall's centre line, front -Y in Blender = +Z in
Godot). Patches: origin at their back, on the wall face, front -Y.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMONS_SRC = os.path.join(HERE, "..", "..", "..", "props", "village-commons", "source")

# Same source, same GLBs: see farm-field's build_farm.py.
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
TEX = os.path.join(FAMILY, "textures")
THATCH, WORN, KIT = "MI_Thatch", "MI_Thatch_Worn", "MI_ThatchKit"
OWN = {
    THATCH: {"doubleSided": False, "dir": TEX, "normalTexture": "T_Thatch_Normal.png",
             "pbr": {"baseColorTexture": "T_Thatch_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.92}},
    WORN: {"doubleSided": False, "dir": TEX, "normalTexture": "T_Thatch_Normal.png",
           "pbr": {"baseColorTexture": "T_ThatchWorn_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.95}},
    KIT: {"doubleSided": True, "dir": TEX,
          "pbr": {"baseColorTexture": "T_ThatchKit_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.88}},
}

# Atlas bands of T_ThatchKit (Blender UV, v up): (v0, v1), u wraps.
def _band(y0, y1):
    return (1.0 - y1 / 1024.0, 1.0 - y0 / 1024.0)


BAND = {
    "ridge": _band(0, 128), "ridge_worn": _band(128, 256),
    "butts": _band(256, 320), "butts_worn": _band(320, 384),
    "under": _band(384, 448), "board": _band(448, 512),
    "batten": _band(512, 544), "iron": _band(544, 576),
}
CELL = {  # (u0, v0, u1, v1)
    "wattle": (0.0, 0.0, 448 / 1024, 448 / 1024),
    "daub": (448 / 1024, 0.0, 896 / 1024, 448 / 1024),
    "edge": (896 / 1024, 0.0, 1.0, 448 / 1024),
}
TILE = 1.6          # metres of roof per body-texture tile
BUTT_M = 6.4        # metres of eave per wrap of the butt bands
UNDER_M = 14.4
RIDGE_M = 8.8
BOARD_M = 3.5


# --- Thatched roofs ---------------------------------------------------------------------------------

class Roof:
    """A hipped thatched roof over a span x length rectangle of walls.

    Every point of the roof lies on a contour ring: the walls' rectangle
    moved in by `d` (negative = out past the walls), its corners rounded.
    Rings are lofted from the underside, round the eave and up to the
    ridge, so the hips come out rounded and the courses of straw (which
    follow the rings) run level all round."""

    def __init__(self, span, length, pitch, worn, seed, step=0.24):
        self.S, self.Lg = span, length
        self.t = pitch
        self.worn = worn
        self.o = 0.45                       # eave overhang (plan)
        self.u0 = 0.15                      # underside height at the wall line
        self.thv = 0.26 * math.sqrt(1 + pitch * pitch)   # thatch thickness, vertical
        self.r0 = 0.85                      # hip rounding (plan radius across the slope)
        self.k = 1.7                        # hip ends this much steeper: a longer ridge
        self.rng = random.Random(seed)
        self.nseed = Vector((self.rng.uniform(0, 50), self.rng.uniform(0, 50), 0))
        self.counts = None
        self.step = step                    # ring spacing up the slope (plan)

    # Contours ---------------------------------------------------------------------------------------
    def dims(self, d):
        hx = max(0.0, self.S / 2 - d)
        hy = max(0.0, self.Lg / 2 - d / self.k)
        r = min(self.r0, hx)
        return hx, hy, r

    def ring(self, d, n_long, n_end, n_c):
        """Points CCW from above, starting at the x+ side's foot (y = -(hy - r)).
        Each point: (x, y, meta) with meta = (segment, value), value the
        coordinate along a side or the angle into a corner."""
        hx, hy, r = self.dims(d)
        ry = r / self.k
        cx, cy = hx - r, hy - ry
        pts = []
        sides = [  # (segment, start, direction along, count)
            (0, n_long), (2, n_end), (4, n_long), (6, n_end)]
        centers = [(cx, cy, 0.0), (-cx, cy, 0.5 * math.pi), (-cx, -cy, math.pi), (cx, -cy, 1.5 * math.pi)]
        for k, (seg, n) in enumerate(sides):
            for i in range(n):
                f = i / n
                if seg == 0:
                    x, y, val = hx, -cy + 2 * cy * f, -cy + 2 * cy * f
                elif seg == 2:
                    x, y, val = cx - 2 * cx * f, hy, cx - 2 * cx * f
                elif seg == 4:
                    x, y, val = -hx, cy - 2 * cy * f, cy - 2 * cy * f
                else:
                    x, y, val = -cx + 2 * cx * f, -hy, -cx + 2 * cx * f
                pts.append((x, y, (seg, val, r, cx, cy, ry)))
            ccx, ccy, a0 = centers[k]
            for i in range(n_c):
                phi = 0.5 * math.pi * i / n_c
                a = a0 + phi
                pts.append((ccx + r * math.cos(a), ccy + ry * math.sin(a), (seg + 1, phi, r, cx, cy, ry)))
        return pts

    @staticmethod
    def zone_u(zone, meta):
        """u (metres) of a ring point as seen from one side's zone: the
        side's own coordinate, carried on round the corners on either hand."""
        seg, val, r, cx, cy, ry = meta
        half = 0.5 * math.pi
        if seg % 2 == 0:
            # A side point: its own coordinate in its own zone's direction.
            return {0: val, 2: -val, 4: -val, 6: val}[seg] if seg == zone else None
        corner = (seg - 1) // 2               # 0..3, between zone 2c and 2c+2
        prev_zone, next_zone = 2 * corner, (2 * corner + 2) % 8
        start = cy if corner % 2 == 0 else cx
        end = cx if corner % 2 == 0 else cy
        # Elliptic corner: it leaves a side running along y at speed ry, one along x at r.
        r_prev, r_next = (ry, r) if corner % 2 == 0 else (r, ry)
        if zone == prev_zone:
            return start + r_prev * val
        if zone == next_zone:
            return -end - r_next * (half - val)
        return None

    @staticmethod
    def side_u(zone, x, y):
        return {0: y, 2: -x, 4: -y, 6: x}[zone]

    # Heights ----------------------------------------------------------------------------------------
    def under(self, d):
        return self.u0 + self.t * d

    def top(self, d):
        span = self.S / 2 + self.o
        bulge = 0.05 * math.sin(math.pi * min(1.0, max(0.0, (d + self.o) / span)))
        return self.under(d) + self.thv + bulge

    def wobble(self, x, y, d):
        """Weathering: a ridge sagging between its ends, slumps and lumps."""
        if not self.worn:
            return 0.0
        p = Vector((x * 0.55, y * 0.55, 0)) + self.nseed
        z = 0.055 * noise.noise(p) + 0.02 * noise.noise(p * 3.1)
        ridge_half = max(0.6, self.Lg / 2 - self.S / (2 * self.k) + 0.6)
        up = max(0.0, min(1.0, (d + self.o) / (self.S / 2 + self.o)))
        z -= 0.16 * max(0.0, 1.0 - (y / ridge_half) ** 2) * up ** 1.5
        return z

    def eave_jitter(self, x, y):
        if not self.worn:
            return 0.0
        return 0.06 * noise.noise(Vector((x * 1.7, y * 1.7, 3.0)) + self.nseed)

    # Building ---------------------------------------------------------------------------------------
    def levels(self):
        """(d, kind, height fn) from the underside round the eave to the ridge."""
        o, thv = self.o, self.thv
        out = [(0.35, "under", lambda d: self.under(d)),
               (-o + 0.05, "under", lambda d: self.under(d)),
               (-o, "face", lambda d: self.under(-o) + 0.04),
               (-o - 0.035, "face", lambda d: self.under(-o) + thv * 0.5),
               (-o - 0.005, "face", lambda d: self.under(-o) + thv * 0.92),
               (-o + 0.09, "top", lambda d: self.top(d) - 0.02)]
        top_steps = int(math.ceil((self.S / 2 + o - 0.25) / self.step))
        for i in range(top_steps + 1):
            d = -o + 0.25 + (self.S / 2 - 0.02 - (-o + 0.25)) * (i / top_steps) ** 0.92
            out.append((d, "top", self.top))
        out.append((self.S / 2, "top", self.top))
        return out

    def body(self, n_long, n_end, n_c):
        """The thatch: one sheet from the underside to the ridge."""
        self.counts = (n_long, n_end, n_c)
        lv = self.levels()
        bm = L.new_bm()
        uv = bm.loops.layers.uv["UVMap"]
        rings = []
        for d, kind, h in lv:
            ring = []
            for x, y, meta in self.ring(d, n_long, n_end, n_c):
                z = h(d)
                if kind == "top":
                    z += self.wobble(x, y, d)
                if kind != "top" or d < -self.o + 0.2:
                    # A ragged eave: the cut wanders in and out.
                    j = self.eave_jitter(x, y)
                    nx, ny = self._outward(meta, x, y)
                    x, y = x + nx * j, y + ny * j
                    if kind == "face":
                        z += j * 0.6
                ring.append((bm.verts.new((x, y, z)), meta))
            rings.append(ring)
        # v along the slope: arc length over the profile at the x+ side's middle.
        prof = [(d, h(d)) for d, _, h in lv]
        s_acc = [0.0]
        for i in range(1, len(prof)):
            (d0, z0), (d1, z1) = prof[i - 1], prof[i]
            s_acc.append(s_acc[-1] + math.hypot(d1 - d0, z1 - z0))
        top0 = next(i for i, l in enumerate(lv) if l[1] == "top")
        n = len(rings[0])
        mats = {"under": 1, "face": 2, "top": 0}
        for i in range(len(rings) - 1):
            kind = lv[i + 1][1] if lv[i][1] != "under" or lv[i + 1][1] == "under" else "under"
            if lv[i][1] == "face" and lv[i + 1][1] == "top":
                kind = "top"
            if lv[i][1] == "under" and lv[i + 1][1] == "face":
                kind = "under"
            for j in range(n):
                a, b = rings[i][j], rings[i][(j + 1) % n]
                c, e = rings[i + 1][(j + 1) % n], rings[i + 1][j]
                quad = [a, b, c, e]
                try:
                    f = bm.faces.new([q[0] for q in quad])
                except ValueError:
                    continue
                f.material_index = mats[kind]
                zone = self._zone(a[1], b[1], n_c)
                for loop, (v, meta), ri in zip(f.loops, quad, (i, i, i + 1, i + 1)):
                    u = self.zone_u(zone, meta)
                    if u is None:
                        u = self.side_u(zone, v.co.x, v.co.y)
                    if kind == "top":
                        loop[uv].uv = (u / TILE, (s_acc[ri] - s_acc[top0]) / TILE)
                    elif kind == "face":
                        f0 = top0 - 3      # first face ring
                        t = (s_acc[ri] - s_acc[f0]) / max(1e-6, s_acc[top0 - 1] - s_acc[f0])
                        v0, v1 = BAND["butts_worn" if self.worn else "butts"]
                        loop[uv].uv = (u / BUTT_M, v0 + (v1 - v0) * min(1.0, max(0.0, t)))
                    else:
                        v0, v1 = BAND["under"]
                        t = s_acc[ri] / max(1e-6, s_acc[2])
                        loop[uv].uv = (u / UNDER_M, v0 + (v1 - v0) * min(1.0, t))
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.004)
        bmesh.ops.dissolve_degenerate(bm, dist=0.004, edges=bm.edges)
        return bm

    @staticmethod
    def _zone(ma, mb, n_c):
        """Which side's u a face between two ring points takes: its side's,
        or in a corner, the nearer side's (the seam runs down the hip)."""
        seg = ma[0]
        if seg % 2 == 0:
            return seg
        corner = (seg - 1) // 2
        phi = ma[1] + 0.25 * math.pi / n_c
        return 2 * corner if phi < math.pi / 4 else (2 * corner + 2) % 8

    @staticmethod
    def _outward(meta, x, y):
        seg = meta[0]
        if seg % 2 == 0:
            return {0: (1, 0), 2: (0, 1), 4: (-1, 0), 6: (0, -1)}[seg]
        corner = (seg - 1) // 2
        a = 0.5 * math.pi * corner + meta[1]
        return math.cos(a), math.sin(a)

    # The ridge --------------------------------------------------------------------------------------
    def ridge(self, block_cut):
        """A ridge of straw wrapped over the top, round the hip ends. A
        block-cut ridge stands proud with its lower edge cut in points and
        scallops; a worn one is thin and ragged."""
        S, Lg = self.S, self.Lg
        wd = 0.42 if block_cut else 0.34           # plan depth of the ridge from the apex
        h_r = 0.13 if block_cut else 0.07
        k = self.k
        straight = Lg - S / k                      # the ridge line
        period = 0.5
        per_side = max(2, round(straight / period)) if straight > 0.1 else 0
        ppp = 6                                    # points per period
        bm = L.new_bm()
        uv = bm.loops.layers.uv["UVMap"]
        band = BAND["ridge" if block_cut else "ridge_worn"]

        def edge_depth(f):
            """How far the cut edge drops below its line, f in [0, 1) of a period."""
            if not block_cut:
                return 0.0
            if f < 0.5:
                return 0.17 * (1.0 - abs(4.0 * f - 1.0))           # a point
            g = 4.0 * (f - 0.5) - 1.0
            return 0.12 * math.sqrt(max(0.0, 1.0 - g * g))         # a scallop

        # Parameterize the ridge's outline: two straight runs and two half-round ends.
        def outline(d):
            hx = max(0.0, S / 2 - d)
            half = straight / 2
            pts = []
            end_periods = max(2, round(math.pi * wd * (1 + 1 / k) / 2 / period))
            # x+ run, -y to +y
            for i in range(per_side * ppp):
                f = i / (per_side * ppp)
                pts.append((hx, -half + straight * f, ("run", -half + straight * f, i / ppp)))
            rr = hx * (1 + 1 / k) / 2            # mean radius of the half-ellipse end
            for i in range(end_periods * ppp):
                a = math.pi * i / (end_periods * ppp)
                pts.append((hx * math.cos(a), half + hx / k * math.sin(a), ("end", a * rr + half, i / ppp + per_side)))
            for i in range(per_side * ppp):
                f = i / (per_side * ppp)
                pts.append((-hx, half - straight * f, ("run", half + math.pi * rr + straight * f, i / ppp)))
            for i in range(end_periods * ppp):
                a = math.pi + math.pi * i / (end_periods * ppp)
                pts.append((hx * math.cos(a), -half + hx / k * math.sin(a), ("end", half + math.pi * rr + straight + (a - math.pi) * rr, i / ppp)))
            return pts

        d_c = S / 2 - wd
        steps = [(0.0, "foot"), (0.0, "lip"), (0.12, "cap"), (0.45, "cap"), (0.8, "cap"), (1.0, "cap")]
        rings = []
        for f_up, kind in steps:
            ring = []
            base = outline(d_c)
            for k, (bx, by, meta) in enumerate(base):
                drop = edge_depth(meta[2] % 1.0)
                d_edge = d_c - drop
                d = d_edge + (S / 2 - d_edge) * f_up
                # The point at this level, same parameter round the outline.
                hx = max(0.0, S / 2 - d)
                if meta[0] == "run":
                    x = hx if bx > 0 else -hx
                    y = by
                else:
                    cy0 = straight / 2 if by > 0 else -straight / 2
                    a = math.atan2((by - cy0) * k, bx)
                    x = hx * math.cos(a)
                    y = cy0 + hx / k * math.sin(a)
                z = self.top(d) + self.wobble(x, y, d)
                if kind == "foot":
                    z += 0.004
                else:
                    lift = h_r * (0.85 + 0.15 * math.sin(math.pi * min(1.0, f_up * 1.6)))
                    if not block_cut:
                        lift *= 0.8 + 0.4 * noise.noise(Vector((x * 2.0, y * 2.0, 7.0)) + self.nseed)
                    z += lift
                    if kind == "cap" and f_up >= 1.0:
                        z += 0.05
                ring.append((bm.verts.new((x, y, z)), meta, f_up if kind != "foot" else -0.05))
            rings.append(ring)
        n = len(rings[0])
        for i in range(len(rings) - 1):
            for j in range(n):
                quad = [rings[i][j], rings[i][(j + 1) % n], rings[i + 1][(j + 1) % n], rings[i + 1][j]]
                try:
                    f = bm.faces.new([q[0] for q in quad])
                except ValueError:
                    continue
                u_ref = quad[0][1][1]
                for loop, (v, meta, fu) in zip(f.loops, quad):
                    u = meta[1]
                    if abs(u - u_ref) > 3.0:          # the outline's wrap point
                        u += math.copysign(2 * (straight + math.pi * wd * (1 + 1 / k) / 2), u_ref - u)
                    vv = band[0] + (band[1] - band[0]) * 0.5 * max(0.0, min(1.0, 0.04 + fu * 0.96))
                    loop[uv].uv = (u / RIDGE_M, vv)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.004)
        bmesh.ops.dissolve_degenerate(bm, dist=0.004, edges=bm.edges)
        return bm

    def patch(self, side_zone, a_c, d_c, ra, rd):
        """New straw let into an old roof: a slightly proud panel of
        golden thatch, its outline ragged, its edges feathered down into
        the old straw, its courses in line with the roof's."""
        bm = L.new_bm()
        uv = bm.loops.layers.uv["UVMap"]
        rng = random.Random("patch")
        lv = self.levels()
        top0 = next(i for i, l in enumerate(lv) if l[1] == "top")
        d_ref, z_ref = lv[top0][0], self.top(lv[top0][0]) - 0.02

        def s_of(d):
            """Slope arc length from the roof's first top ring (as body() does)."""
            s, prev = 0.0, (d_ref, z_ref)
            for q in range(1, 41):
                dd = d_ref + (d - d_ref) * q / 40
                pt = (dd, self.top(dd))
                s += math.hypot(pt[0] - prev[0], pt[1] - prev[1])
                prev = pt
            return s

        n_ang = 28
        # A rounded oblong laid along the courses, as a thatcher works: a
        # little ragged, wider than it is tall.
        shape = []
        for i in range(n_ang):
            ang = 2 * math.pi * i / n_ang
            c, sn = abs(math.cos(ang)), abs(math.sin(ang))
            superellipse = (c ** 3.2 + sn ** 3.2) ** (-1 / 3.2)
            shape.append(superellipse * (1.0 + rng.uniform(-0.07, 0.05)))
        ox = 1 if side_zone == 0 else -1

        def point(fr, i):
            ang = 2 * math.pi * i / n_ang
            k = shape[i % n_ang] if fr > 0 else 1.0
            a = a_c + math.cos(ang) * ra * fr * k
            d = d_c + math.sin(ang) * rd * fr * k
            hx, hy, r = self.dims(d)
            x, y = (hx, a) if side_zone == 0 else (-hx, -a)
            lift = 0.006 + 0.028 * max(0.0, 1.0 - fr ** 3)
            z = self.top(d) + self.wobble(x, y, d) + lift
            v = bm.verts.new((x + ox * lift * 0.55, y, z))
            return (v, a, d)

        center = point(0.0, 0)
        rings = [[point(fr, i) for i in range(n_ang)] for fr in (0.3, 0.6, 0.85, 1.0)]
        faces = []
        for i in range(n_ang):
            j = (i + 1) % n_ang
            faces.append([center, rings[0][i], rings[0][j]])
            for q in range(len(rings) - 1):
                faces.append([rings[q][i], rings[q + 1][i], rings[q + 1][j], rings[q][j]])
        for quad in faces:
            if side_zone == 0:
                quad = list(reversed(quad))
            f = bm.faces.new([q[0] for q in quad])
            for loop, (v, a, d) in zip(f.loops, quad):
                loop[uv].uv = (a / TILE, s_of(d) / TILE)
        return bm


def roof_object(name, span, length, pitch, worn):
    roof = Roof(span, length, pitch, worn, seed=name, step=0.24 if span <= 4 else 0.29)
    n_long = max(8, round((length + 0.9 - 1.7) / 0.5))
    n_end = max(5, round((span + 0.9 - 1.7) / 0.55))
    bm = roof.body(n_long, n_end, 6)
    body = L.to_object(bm, name, WORN if worn else THATCH, smooth_angle=52, recalc=False)
    body.data.materials.append(bpy.data.materials[KIT])   # underside
    body.data.materials.append(bpy.data.materials[KIT])   # eave
    parts = [body]
    ridge = L.to_object(roof.ridge(block_cut=not worn), name + "_ridge", KIT, smooth_angle=60, recalc=False)
    parts.append(ridge)
    if worn:
        # New straw let into the front slope, toward one end.
        p = roof.patch(4, 0.35, 0.8, 0.62, 0.3)
        parts.append(L.to_object(p, name + "_patch", THATCH, smooth_angle=60, recalc=False))
    return parts


def thatch_4x6_worn():
    return roof_object("SE_Thatch_4x6_Worn", 4, 6, 1.35, True)


def thatch_4x6():
    return roof_object("SE_Thatch_4x6", 4, 6, 1.35, False)


def thatch_6x8():
    return roof_object("SE_Thatch_6x8", 6, 8, 1.22, False)


# --- Shared bits for boards ---------------------------------------------------------------------------

def prism(outline_xz, y_front, y_back, band, rng, along="z"):
    """A flat piece cut to an outline in the XZ plane (CCW seen from -Y),
    with thickness between y_front and y_back; wood grain along `along`."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    front = [bm.verts.new((x, y_front, z)) for x, z in outline_xz]
    back = [bm.verts.new((x, y_back, z)) for x, z in outline_xz]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    n = len(outline_xz)
    for i in range(n):
        faces.append(bm.faces.new([front[(i + 1) % n], front[i], back[i], back[(i + 1) % n]]))
    v0, v1 = BAND[band]
    xs = [p[0] for p in outline_xz]
    zs = [p[1] for p in outline_xz]
    lo_x, hi_x, lo_z, hi_z = min(xs), max(xs), min(zs), max(zs)
    u_off = rng.uniform(0, 1)
    scale = BOARD_M if band != "iron" else 1.6
    for f in faces:
        for l in f.loops:
            p = l.vert.co
            if along == "z":
                a, c = p.z, (p.x - lo_x) / max(1e-6, hi_x - lo_x)
            else:
                a, c = p.x, (p.z - lo_z) / max(1e-6, hi_z - lo_z)
            l[uv].uv = (u_off + a / scale, v0 + (v1 - v0) * (0.06 + 0.88 * c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def nail(x, z, y, s=0.016):
    return prism([(x - s, z - s), (x + s, z - s), (x + s, z + s), (x - s, z + s)], y - 0.008, y + 0.002, "iron", random.Random(0), along="x")


# --- Shutters --------------------------------------------------------------------------------------

# The kit's window shapes (WindowShutters_* closed outlines): half width,
# sill, shoulder (where an arch begins) and top.
FITS = {
    "Wide_Round": (0.67, 1.095, 2.16, 2.738),
    "Thin_Round": (0.43, 1.095, 2.18, 2.608),
    "Wide_Flat": (0.67, 1.095, 2.518, 2.518),
}


def top_at(fit, x):
    hw, sill, shoulder, top = FITS[fit]
    if top <= shoulder + 1e-6:
        return top
    t = min(1.0, abs(x) / hw)
    return shoulder + (top - shoulder) * math.sqrt(max(0.0, 1.0 - t * t))


def leaf(fit, side, rng, missing=None, broken=None, broken_cut=0.0):
    """One leaf of plank shutter, closed, hinged at x = side * hw: boards
    edge to edge (a gap between), two battens and a brace on the front,
    iron straps from the hinge. Returns a list of bmeshes."""
    hw, sill, _, _ = FITS[fit]
    boards = 3 if hw > 0.5 else 2
    w = hw / boards
    y_front, y_back = -0.196, -0.158
    parts = []
    for b in range(boards):
        if b == missing:
            continue
        x0 = side * (b * w) if side > 0 else -(b + 1) * w
        x1 = x0 + w
        x0 += 0.005
        x1 -= 0.005
        bottom = sill + rng.uniform(-0.01, 0.015)
        if b == broken:   # snapped off: a jagged top
            top_pts = [(x1, top_at(fit, x1) - broken_cut), ((x0 + x1) / 2, top_at(fit, x1) - broken_cut * 0.62), (x0, top_at(fit, x0) - broken_cut * 0.85)]
        else:
            top_pts = [(x, top_at(fit, x) - 0.01) for x in (x1, (x0 + x1) / 2, x0)]
        outline = [(x0, bottom), (x1, bottom)] + top_pts
        parts.append(prism(outline, y_front, y_back, "board", rng))
    # Battens and the brace (on the front), the straps over them.
    x_in, x_out = (0.0, hw) if side > 0 else (-hw, 0.0)
    xa, xb = x_in + 0.03, x_out - 0.03
    z_lo = sill + 0.2
    z_hi = min(top_at(fit, xa), top_at(fit, xb)) - 0.32
    yb0, yb1 = y_front - 0.03, y_front
    for z in (z_lo, z_hi):
        parts.append(prism([(xa, z - 0.05), (xb, z - 0.05), (xb, z + 0.05), (xa, z + 0.05)], yb0, yb1, "batten", rng, along="x"))
    # Brace rising from the hinge side's foot (it holds the leaf from sagging).
    hinge_x = xb if side > 0 else xa
    free_x = xa if side > 0 else xb
    p0 = Vector((hinge_x, z_lo + 0.05))
    p1 = Vector((free_x, z_hi - 0.05))
    dv = (p1 - p0).normalized()
    nv = Vector((-dv.y, dv.x)) * 0.04
    quad = [p0 - nv, p1 - nv, p1 + nv, p0 + nv]
    parts.append(prism([(q.x, q.y) for q in quad], yb0 + 0.004, yb1, "batten", rng, along="x"))
    for z in (z_lo, z_hi):
        x_end = hinge_x - side * hw * 0.62
        xs = sorted((hinge_x + side * 0.03, x_end))
        parts.append(prism([(xs[0], z - 0.022), (xs[1], z - 0.022), (xs[1], z + 0.022), (xs[0], z + 0.022)], yb0 - 0.008, yb0, "iron", rng, along="x"))
        for nx in (hinge_x - side * 0.08, x_end + side * 0.06):
            parts.append(nail(nx, z, yb0 - 0.008, 0.011))
    return parts


def merged(bms):
    out = L.new_bm()
    for b in bms:
        L.merge_bm(out, b)
        b.free()
    return out


def swing(bms, fit, side, angle_deg, droop=0.0, roll_deg=0.0):
    """Swing a closed leaf open round its hinge (x = side * hw, y = -0.177),
    then let it hang (roll about the hinge's top) if a hinge has gone."""
    hw, sill, _, _ = FITS[fit]
    bm = merged(bms)
    hinge = Vector((side * hw, -0.177, 0.0))
    m = (Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(side * angle_deg), 4, "Z") @ Matrix.Translation(-hinge))
    L.transform(bm, m)
    if roll_deg:
        # Hanging from its lower hinge: the leaf turns in its own plane, the free edge drops.
        along = (m.to_3x3() @ Vector((-side, 0, 0))).normalized()
        axis = along.cross(Vector((0, 0, 1))).normalized()
        pivot = Vector((side * hw, -0.177, sill + 0.2))
        rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(roll_deg), 4, axis) @ Matrix.Translation(-pivot)
        free_before = pivot + along * hw
        if (rot @ free_before).z > free_before.z:
            rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-roll_deg), 4, axis) @ Matrix.Translation(-pivot)
        L.transform(bm, rot)
    if droop:
        L.transform(bm, Matrix.Translation((0, 0, -droop)))
    return bm


def shutters(fit, state):
    rng = random.Random("%s_%s" % (fit, state))
    parts = []
    if state == "Closed":
        hw = FITS[fit][0]
        boards = 3 if hw > 0.5 else 2
        left = leaf(fit, -1, rng, missing=0 if boards == 3 else None, broken=0 if boards == 2 else None, broken_cut=0.46)
        right = leaf(fit, 1, rng)
        bm = merged(left + right)
    else:
        a = swing(leaf(fit, -1, rng), fit, -1, 142)
        # The right leaf has lost its top hinge: it hangs open, tipped.
        b = swing(leaf(fit, 1, rng), fit, 1, 136, droop=0.035, roll_deg=7.0)
        bm = merged([a, b])
    return L.to_object(bm, "tmp", KIT, smooth_angle=None, recalc=False)


def make_shutter(fit, state):
    def fn():
        return [shutters(fit, state)]
    return fn


# --- Wall patches ----------------------------------------------------------------------------------

def blob(rx, rz, rng, n=18, rough=0.18):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1.0 + rng.uniform(-rough, rough)
        pts.append((math.cos(a) * rx * k, math.sin(a) * rz * k))
    return pts


def planar_cell(bm, cell, lo, hi):
    uv = bm.loops.layers.uv["UVMap"]
    u0, v0, u1, v1 = cell
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co
            s = (p.x - lo[0]) / (hi[0] - lo[0])
            t = (p.z - lo[1]) / (hi[1] - lo[1])
            l[uv].uv = (u0 + (u1 - u0) * min(1, max(0, s)), v0 + (v1 - v0) * min(1, max(0, t)))


def fan(outline, center, y_out, y_rim, y_c=None):
    """A flat disc (fan from its centre) at depth y_out, the centre at y_c."""
    bm = L.new_bm()
    c = bm.verts.new((center[0], y_c if y_c is not None else y_out, center[1]))
    ring = [bm.verts.new((x, y_rim, z)) for x, z in outline]
    n = len(ring)
    for i in range(n):
        bm.faces.new([c, ring[i], ring[(i + 1) % n]])
    return bm


def wattle_hole(rx, rz, rng):
    """Daub fallen off: the wattle behind, a broken rim of limewashed
    plaster standing round it."""
    hole = blob(rx, rz, rng, n=20, rough=0.16)
    inner = fan(hole, (0.0, 0.0), -0.006, -0.006)
    planar_cell(inner, CELL["wattle"], (-0.45, -0.45), (0.45, 0.45))
    # The rim: from the hole's edge (raised: the plaster's thickness) out to the wall.
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    n = len(hole)
    lip_in = [bm.verts.new((x, -0.006, z)) for x, z in hole]
    lip_top = [bm.verts.new((x * 1.02, -0.032, z * 1.02)) for x, z in hole]
    out = []
    for x, z in hole:
        k = 1.0 + rng.uniform(0.035, 0.085) / max(0.2, math.hypot(x, z))
        out.append(bm.verts.new((x * k, -0.004, z * k)))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new([lip_in[j], lip_in[i], lip_top[i], lip_top[j]]))
        faces.append(bm.faces.new([lip_top[j], lip_top[i], out[i], out[j]]))
    u0, v0, u1, v1 = CELL["edge"]
    for f in faces:
        for l in f.loops:
            p = l.vert.co
            ang = (math.atan2(p.z, p.x) / (2 * math.pi)) % 1.0
            l[uv].uv = (u0 + (u1 - u0) * (0.1 + 0.8 * min(1.0, -p.y / 0.035)), v0 + (v1 - v0) * ang)
    for f in faces:   # the broken edge faces the hole, its top faces out
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.y > 0.6 or (abs(f.normal.y) <= 0.6 and f.normal.x * c.x + f.normal.z * c.z > 0):
            f.normal_flip()
    return [inner, bm]


def daub_smear(rx, rz, rng):
    outline = blob(rx, rz, rng, n=22, rough=0.22)
    bm = L.new_bm()
    c = bm.verts.new((0, -0.024, 0))
    mid = [bm.verts.new((x * 0.55, -0.018 + rng.uniform(-0.003, 0.003), z * 0.55)) for x, z in outline]
    ring = [bm.verts.new((x, -0.003, z)) for x, z in outline]
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([c, mid[i], mid[j]])
        bm.faces.new([mid[i], ring[i], ring[j], mid[j]])
    planar_cell(bm, CELL["daub"], (-0.45, -0.45), (0.45, 0.45))
    return bm


def patch_wattle():
    rng = random.Random("SE_Patch_Wattle")
    bms = wattle_hole(0.40, 0.29, rng)
    return [L.to_object(merged(bms), "tmp", KIT, smooth_angle=50, recalc=False)]


def patch_daub():
    rng = random.Random("SE_Patch_Daub")
    return [L.to_object(daub_smear(0.36, 0.27, rng), "tmp", KIT, smooth_angle=60, recalc=False)]


def patch_boards():
    """Boards nailed across a hole: the wattle shows between them."""
    rng = random.Random("SE_Patch_Boards")
    bms = wattle_hole(0.30, 0.24, rng)
    zs = (-0.17, 0.0, 0.18)
    for i, z in enumerate(zs):
        w = rng.uniform(0.13, 0.16)
        half = rng.uniform(0.36, 0.46)
        tilt = math.radians(rng.uniform(-6, 6))
        dx = rng.uniform(-0.05, 0.05)
        corners = [(-half, -w / 2), (half, -w / 2), (half, w / 2), (-half, w / 2)]
        pts = [(dx + x * math.cos(tilt) - y * math.sin(tilt), z + x * math.sin(tilt) + y * math.cos(tilt)) for x, y in corners]
        y_back = -0.034 - 0.004 * i
        bms.append(prism(pts, y_back - 0.026, y_back, "board", rng, along="x"))
        for sx in (-1, 1):
            px = dx + sx * (half - 0.06) * math.cos(tilt)
            pz = z + sx * (half - 0.06) * math.sin(tilt)
            bms.append(nail(px, pz, y_back - 0.026, 0.012))
    return [L.to_object(merged(bms), "tmp", KIT, smooth_angle=None, recalc=False)]


BUILDERS = {
    "SE_Thatch_4x6_Worn": thatch_4x6_worn,
    "SE_Thatch_4x6": thatch_4x6,
    "SE_Thatch_6x8": thatch_6x8,
    "SE_Patch_Wattle": patch_wattle,
    "SE_Patch_Daub": patch_daub,
    "SE_Patch_Boards": patch_boards,
}
for _fit in FITS:
    for _state in ("Open", "Closed"):
        BUILDERS["SE_Shutters_Plank_%s_%s" % (_fit, _state)] = make_shutter(_fit, _state)


# --- Build, export, review --------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(THATCH, (1.0, 1.0, 1.0), roughness=0.92, image=os.path.join(TEX, "T_Thatch_BaseColor.png"))
    L.custom_material(WORN, (1.0, 1.0, 1.0), roughness=0.95, image=os.path.join(TEX, "T_ThatchWorn_BaseColor.png"))
    L.custom_material(KIT, (1.0, 1.0, 1.0), roughness=0.88, image=os.path.join(TEX, "T_ThatchKit_BaseColor.png"))
    for name in (THATCH, WORN):
        m = bpy.data.materials[name]
        nt = m.node_tree
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = bpy.data.images.load(os.path.join(TEX, "T_Thatch_Normal.png"), check_existing=True)
        ntex.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], nt.nodes["Principled BSDF"].inputs["Normal"])


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)  # same source, same GLBs
        objs = fn()
        obj = L.join(objs, name)
        uvs = obj.data.uv_layers
        uvs.active = uvs["UVMap"]
        uvs["UVMap"].active_render = True
        if "Sway" in uvs:
            uvs.remove(uvs["Sway"])
        built.append(obj)
    return built


def export(objs):
    models = os.path.join(FAMILY, "models")
    tmp = os.path.join(HERE, "_export_tmp")
    os.makedirs(models, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    for obj in objs:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
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
        print("exported %s: %d tris, %s, %d bytes" % (obj.name, L.tri_count(obj), mats, os.path.getsize(glb)))
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def save_blend(objs, path):
    for o in [o for o in bpy.data.objects if o.name.startswith("_")]:
        bpy.data.objects.remove(o)
    for i, o in enumerate(objs):
        o.hide_render = False
        o.location = ((i % 4) * 9.0, (i // 4) * 9.0, 0)
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
            save_blend(built, os.path.join(HERE, "thatch_repair.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for obj in built:
            for o in built:
                o.hide_render = o is not obj
                o.location = (0, 0, 0)
            roof = obj.name.startswith("SE_Thatch")
            h = max(obj.dimensions.z, 0.6)
            ext = max(obj.dimensions.x, obj.dimensions.y, h, 1.4) * 1.1
            if roof:
                obj.location = (0, 0, 3.0)
                views = [("front34", -35, 22, 6.0, 40), ("top", -20, 62, 7.5, 45), ("eave", -60, 6, 3.0, 45), ("close", -40, 30, 2.6, 42)]
                c = 3.0 + h * 0.4
            else:
                obj.location = (0, 0, 0 if obj.name.startswith("SE_Shutters") else 1.6)
                views = [("front", 0, 4, 6.0, 40), ("front34", -40, 12, 6.0, 40), ("side", -80, 10, 6.0, 40), ("close", -25, 8, 3.2, 42)]
                c = 1.8 if obj.name.startswith("SE_Shutters") else 1.6
            for p in BC.review([obj], os.path.join(out, obj.name), views=views, extent=ext, center_z=c):
                print("  ", p)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
