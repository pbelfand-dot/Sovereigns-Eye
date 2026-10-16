"""Builds the Harbour & Ships family in Blender (bpy 4.2).

    /root/bpy-venv/bin/python build_harbour.py [--review DIR] [--export] [--only A,B]

A small harbour as it might be in the 1180s, and the craft that use it:
  - the waterfront: a timber revetment quay (posts and planking, braced in
    front), a stone quay and one with water stairs, a jetty on pile bents
    and its head, a log slipway, mooring posts and a hoist (a post and jib
    with a windlass: treadwheel cranes come later, in the 1240s);
  - the craft: a rowing boat, a fishing boat, a trading ship in the
    Scandinavian clinker tradition (a "keel") under sail, steered by a side
    rudder, and a cog: flat-bottomed, high-sided, with straight raked posts,
    beams through its sides and the new stern rudder;
  - the shore: nets drying on a rack, a boat turned over on trestles.

The waterfront joins along +X, the sea to -Y (Blender), on a 4 m grid. Its
origin is at the water line on the face; the quay top is 1.4 m above it,
the bed 2 m below. Craft have their origin at the water line amidships,
the bow to +X. Shore pieces stand on the ground at their origin.

Wood and iron are the village kit's trim sheets, dressed stone its ashlar,
the stone quay its rubble (MI_UnevenBrick); planking, sailcloth, the quay's
earth, the tide line, deck planks, nets, rope and furled sails are this
family's atlas (T_Harbour_BaseColor.png, paint_harbour.py). Nets and the
weed at the tide line are cut out of it (MI_Harbour_Cut, alpha mask);
sails are thin and two-sided (MI_Harbour_Sail).
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
HA, CUT, SAIL = "MI_Harbour", "MI_Harbour_Cut", "MI_Harbour_Sail"
HA_TEX = os.path.join(FAMILY, "textures", "T_Harbour_BaseColor.png")
STONE = "MI_UnevenBrick"
_ATLAS = {"dir": os.path.join(FAMILY, "textures"),
          "pbr": {"baseColorTexture": "T_Harbour_BaseColor.png", "metallicFactor": 0, "roughnessFactor": 0.85}}
OWN = {
    HA: dict(_ATLAS, doubleSided=False),
    SAIL: dict(_ATLAS, doubleSided=True),
    CUT: dict(_ATLAS, doubleSided=True, alphaMode="MASK", alphaCutoff=0.5),
    STONE: {"doubleSided": False, "dir": gltf_pack.VILLAGE, "normalTexture": "T_UnevenBrick_Normal.png",
            "pbr": {"baseColorTexture": "T_UnevenBrick_BaseColor.png", "metallicFactor": 0, "metallicRoughnessTexture": "T_UnevenBrick_Roughness.png"}},
}
L.MATERIALS[STONE] = ("T_UnevenBrick_BaseColor.png", "T_UnevenBrick_Normal.png")


def _cell(x0, y0, x1, y1):
    """Image pixels (y down) of the 512 atlas -> Blender UV rect (v up)."""
    return (x0 / 512, 1 - y1 / 512, x1 / 512, 1 - y0 / 512)


for _k, _v in {"deck": _cell(4, 388, 124, 508), "net": _cell(130, 386, 254, 510),
               "rope": _cell(260, 388, 380, 508), "furled": _cell(388, 388, 508, 508)}.items():
    L.RECTS["ha_" + _k] = (HA,) + _v
for _k, (_y0, _y1) in {"tar": (0, 64), "oak": (64, 128), "sail": (128, 192), "stripe": (192, 256),
                       "earth": (256, 320), "tide": (320, 384)}.items():
    L.BANDS["ha_" + _k] = (HA, 1 - _y1 / 512 + 0.003, 1 - _y0 / 512 - 0.003)

# The waterfront.
QUAY = 1.4        # quay top above the water
JETTY = 1.2       # the jetty's deck (its top) above the water
BED = -2.0        # the bed at the waterfront's face
UV = 0.5          # the kit's stone tiles every 2 m


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


def slab(outline_xz, y0, y1):
    """A flat piece cut to an outline in the XZ plane (convex, anticlockwise
    seen from -Y), y0 to y1 thick."""
    bm = L.new_bm()
    fr = [bm.verts.new((x, y0, z)) for x, z in outline_xz]
    bk = [bm.verts.new((x, y1, z)) for x, z in outline_xz]
    bm.faces.new(fr)
    bm.faces.new(list(reversed(bk)))
    n = len(outline_xz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([fr[j], fr[i], bk[i], bk[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    return bm


def uv_stone(bm):
    """The kit's rubble stone at its own scale: courses level on upright faces."""
    uv = bm.loops.layers.uv["UVMap"]
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        for l in f.loops:
            p = l.vert.co
            if ax == 2:
                l[uv].uv = (p.x * UV, p.y * UV)
            else:
                l[uv].uv = ((p.y if ax == 0 else p.x) * UV, p.z * UV)
    return bm


def ashlar(bm, name="ashlar"):
    L.uv_box_band(bm, list(bm.faces), "rock_ashlar")
    return obj(bm, name, "MI_RockTrim")


def wood(p0, p1, w, h, rng, up=Vector((0, 0, 1)), name="timber", band="wood_dark"):
    return obj(L.beam(p0, p1, w, h, rng=rng, up=up, band=band), name, "MI_WoodTrim")


def pole(p0, p1, r, seed, name="pole"):
    return obj(L.log(p0, p1, r, sides=7, band="wood_dark", seed=seed, jitter=0.06), name, "MI_WoodTrim", smooth=40)


def boards(origin, du, dv, lu, lv, thick=0.06, tile=(2.0, 1.5), rect="ha_deck", back=True):
    """Planking over the rectangle origin + s*du + t*dv (s to lu, t to lv),
    facing du x dv, the grain along du, the atlas cell repeated every
    `tile` m so the boards keep their width; with `back` a slab `thick`
    deep seen from both sides (decks), else a skin seen from the front."""
    o, du, dv = Vector(origin), Vector(du).normalized(), Vector(dv).normalized()
    nrm = du.cross(dv)
    _, u0, v0, u1, v1 = L.RECTS[rect]
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    for base, flip in [(o, False)] + ([(o - nrm * thick, True)] if back else []):
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
    if back:
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
    parts.append(obj(boards(*args, **kw), name, HA, recalc=False))


def band_strip(parts, pts_lo, pts_hi, band, u_scale=0.5, name="strip", mat=HA):
    """A strip of quads between two matching point rows, mapped into a band
    (v from the low row to the high), facing whichever way the rows wind."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS[band]
    acc = 0.0
    us = [0.0]
    for i in range(1, len(pts_lo)):
        acc += (Vector(pts_lo[i]) - Vector(pts_lo[i - 1])).length
        us.append(acc)
    for i in range(len(pts_lo) - 1):
        q = [(pts_lo[i], us[i], v0), (pts_lo[i + 1], us[i + 1], v0), (pts_hi[i + 1], us[i + 1], v1), (pts_hi[i], us[i], v1)]
        f = bm.faces.new([bm.verts.new(p) for p, _, _ in q])
        for l, (_, u, v) in zip(f.loops, q):
            l[uv].uv = (u * u_scale, v)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    parts.append(obj(bm, name, mat, recalc=False))


def tide_sleeve(parts, x, y, r, z0=-0.8, z1=0.6, seg=8):
    """Weed and barnacles round a pile at the water: a sleeve a little
    proud of it, mapped into the tide band (weed below, clean above)."""
    lo = [(x + math.cos(a) * r, y + math.sin(a) * r, z0) for a in [2 * math.pi * i / seg for i in range(seg + 1)]]
    hi = [(p[0], p[1], z1) for p in lo]
    band_strip(parts, lo, hi, "ha_tide", u_scale=0.5, name="tide", mat=CUT)


def rope(parts, pts, r=0.022, name="rope"):
    bm = L.sweep(pts, r, sides=5, band="wood_light")
    parts.append(obj(bm, name, "MI_WoodTrim"))


# --- Hulls ----------------------------------------------------------------------------------------

# Half-sections, keel (0, 0) to sheer (1, 1): y out from the middle line, z up.
SECTIONS = {
    # The Scandinavian tradition: a sharp floor rising from the keel, a
    # firm turn of the bilge, the sides flaring a little to the sheer.
    "round": [(0.0, 0.0), (0.30, 0.07), (0.56, 0.19), (0.76, 0.36), (0.90, 0.57), (0.98, 0.79), (1.02, 1.0)],
    # The cog: a flat, flush-planked bottom, a hard turn, sides near upright.
    "flat": [(0.0, 0.0), (0.55, 0.0), (0.74, 0.03), (0.86, 0.11), (0.94, 0.30), (0.98, 0.62), (1.0, 1.0)],
}


def _section(shape, t):
    """The point at fraction t of the way round a half-section (by length)."""
    pts = [Vector(p) for p in SECTIONS[shape]]
    seg = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
    total = sum(seg)
    d = t * total
    for i, l in enumerate(seg):
        if d <= l or i == len(seg) - 1:
            return pts[i].lerp(pts[i + 1], min(1.0, d / l))
        d -= l
    return pts[-1]


class Hull:
    """A clinker hull from its main dimensions. P(s, t, side): s along it
    (-1 stern .. +1 stem), t round the section (0 keel .. 1 sheer), side +1
    port (+Y) or -1 starboard. The water line is z = 0."""

    def __init__(self, length, beam, depth, draft, strakes, shape="round", sheer=0.6, rocker=0.15,
                 end0=0.86, end_pow=2.0, full=2.0, full_pow=0.55, stations=22, tar_below=None):
        self.half = length / 2
        self.beam, self.depth, self.draft = beam, depth, draft
        self.n, self.shape, self.sheer, self.rocker = strakes, shape, sheer, rocker
        self.end0, self.end_pow, self.full, self.full_pow = end0, end_pow, full, full_pow
        self.N = stations
        self.tar_below = strakes if tar_below is None else tar_below
        self.thick = 0.035

    def X(self, t):
        """How far from amidships the hull ends for the strake edge at t: set
        by how high the edge is, so a cog's posts are straight lines (its
        flat bottom's edges all end at the post's foot) and a Scandinavian
        stem curves up."""
        return self.half * (self.end0 + (1 - self.end0) * _section(self.shape, t).y ** self.end_pow)

    def b(self, s):
        return self.beam / 2 * max(0.0, 1 - abs(s) ** self.full) ** self.full_pow

    def keel_z(self, s):
        return self.rocker * abs(s) ** 4 - self.draft

    def sheer_z(self, s):
        return self.depth + self.sheer * abs(s) ** 2.5 - self.draft

    def P(self, s, t, side=1):
        q = _section(self.shape, t)
        k, h = self.keel_z(s), self.sheer_z(s)
        return Vector((s * self.X(t), side * self.b(s) * q.x, k + (h - k) * q.y))

    def normal(self, s, t, side=1):
        """Outward normal (y, z plane) of the planking at (s, t)."""
        e = 0.01
        a, c = self.P(s, max(0.0, t - e), side), self.P(s, min(1.0, t + e), side)
        d = c - a
        n = Vector((0, side * d.z, -side * d.y))   # the section's tangent turned outward
        if n.length < 1e-6:
            return Vector((0, side, 0))
        return n.normalized()

    def inner(self, s, t, side=1):
        return self.P(s, t, side) - self.normal(s, t, side) * self.thick

    def half_width(self, s, t):
        return abs(self.inner(s, t).y)

    def edges(self):
        """Strake edges round the section: the garboard and the top strake
        a little narrower than the rest."""
        w = [0.8] + [1.0] * (self.n - 2) + [0.9]
        tot = sum(w)
        out, acc = [0.0], 0.0
        for x in w:
            acc += x
            out.append(acc / tot)
        return out

    def ss(self):
        return [-1 + 2 * i / (self.N - 1) for i in range(self.N)]


def _face(bm, pts, uvs, want, uvl):
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    for l, u in zip(f.loops, uvs):
        l[uvl].uv = u
    f.normal_update()
    if f.normal.dot(want) < 0:
        f.normal_flip()
    return f


def hull_parts(h, parts, lap=0.022):
    """The planking: each strake a strip lapped over the one below (its
    lower edge stood out by `lap`, the lap's edge closing it), the inside
    of the planking, the gunwale; tarred below `tar_below` strakes, oak
    above; the keel and the stem and stern posts."""
    ss, ts = h.ss(), h.edges()
    for side in (1, -1):
        outer = L.new_bm()
        uvo = outer.loops.layers.uv["UVMap"]
        oak_out = L.new_bm()
        uvk = oak_out.loops.layers.uv["UVMap"]
        inner = L.new_bm()
        uvi = inner.loops.layers.uv["UVMap"]
        for k in range(h.n):
            t0, t1 = ts[k], ts[k + 1]
            bm, uvl = (outer, uvo) if k < h.tar_below else (oak_out, uvk)
            _, v0, v1 = L.BANDS["ha_tar" if k < h.tar_below else "ha_oak"]
            for i in range(h.N - 1):
                sa, sb = ss[i], ss[i + 1]
                fade = lambda s: min(1.0, (1 - abs(s)) * 6)   # no lap where the strakes run into the posts
                lo_a = h.P(sa, t0, side) + (h.normal(sa, t0, side) * lap * fade(sa) if k else Vector())
                lo_b = h.P(sb, t0, side) + (h.normal(sb, t0, side) * lap * fade(sb) if k else Vector())
                hi_a, hi_b = h.P(sa, t1, side), h.P(sb, t1, side)
                want = h.normal((sa + sb) / 2, (t0 + t1) / 2, side)
                ua, ub = lo_a.x * 0.42, lo_b.x * 0.42
                _face(bm, [lo_a, lo_b, hi_b, hi_a], [(ua, v0), (ub, v0), (ub, v1), (ua, v1)], want, uvl)
                if k:
                    # The lap's own edge, from the strake below up to this one.
                    pa, pb = h.P(sa, t0, side), h.P(sb, t0, side)
                    down = Vector((0, 0, -1)) + want
                    _face(bm, [pa, pb, lo_b, lo_a], [(ua, v0), (ub, v0), (ub, v0 + 0.01), (ua, v0 + 0.01)], down, uvl)
                # Inside, one plain surface; oak.
                _, w0, w1 = L.BANDS["ha_oak"]
                ia, ib = h.inner(sa, t0, side), h.inner(sb, t0, side)
                ja, jb = h.inner(sa, t1, side), h.inner(sb, t1, side)
                _face(inner, [ia, ib, jb, ja], [(ua, w0), (ub, w0), (ub, w1), (ua, w1)], -want, uvi)
        # The gunwale: the top edge of the planking, inside to out.
        g0 = L.BANDS["ha_oak"][1]
        for i in range(h.N - 1):
            sa, sb = ss[i], ss[i + 1]
            a, b = h.P(sa, 1.0, side), h.P(sb, 1.0, side)
            c, d = h.inner(sb, 1.0, side), h.inner(sa, 1.0, side)
            _face(oak_out if h.tar_below < h.n else outer, [a, b, c, d], [(a.x * 0.42, g0), (b.x * 0.42, g0), (b.x * 0.42, g0 + 0.05), (a.x * 0.42, g0 + 0.05)],
                  Vector((0, 0, 1)), uvk if h.tar_below < h.n else uvo)
        for bm, name in ((outer, "planking"), (oak_out, "planking_oak"), (inner, "inside")):
            if len(bm.faces):
                bm.normal_update()
                parts.append(obj(bm, name, HA, recalc=False))
            else:
                bm.free()
    # The keel along the bottom, the stem and stern posts up the ends.
    rng = random.Random(int(h.half * 100))
    keel = [h.P(s, 0.0) - Vector((0, 0, 0.06)) for s in ss]
    parts.append(obj(L.sweep(keel, 0.07, sides=4, band="wood_dark", square=True), "keel", "MI_WoodTrim"))
    return rng


def posts(h, parts, rise_fore=0.0, rise_aft=0.0, curl=0.0, w=0.09):
    """The stem and sternpost: up the hull's ends and on above the sheer by
    `rise` (curling back inboard by `curl`, the Scandinavian way)."""
    for sgn, rise in ((1, rise_fore), (-1, rise_aft)):
        pts = [h.P(sgn, t / 8) for t in range(9)]
        top = pts[-1]
        d = (pts[-1] - pts[-2]).normalized()
        for k in range(1, 5):
            f = k / 4
            p = top + d * rise * f
            p.x -= sgn * curl * f ** 2
            pts.append(p)
        parts.append(obj(L.sweep(pts, w, sides=4, band="wood_dark", square=True), "post", "MI_WoodTrim"))


def deck(h, parts, s0, s1, t, tile=1.5, name="deck", hatch=None):
    """Planking across the hull at height t between s0 and s1, the boards
    fore and aft; `hatch` (s0, s1, half-width) is left open (dark below)."""
    X = h.X(t)
    x0, x1 = s0 * X, s1 * X
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    _, u0, v0, u1, v1 = L.RECTS["ha_deck"]
    nx = max(1, int(math.ceil((x1 - x0) / tile)))
    wmax = max(h.half_width(s, t) for s in [s0 + (s1 - s0) * k / 10 for k in range(11)])
    ny = max(1, int(math.ceil(2 * wmax / tile)))
    for i in range(nx):
        xa, xb = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
        sa, sb = xa / X, xb / X
        wa, wb = h.half_width(sa, t) - 0.01, h.half_width(sb, t) - 0.01
        za, zb = h.P(sa, t).z, h.P(sb, t).z
        for j in range(ny):
            ya, yb = -wmax + 2 * wmax * j / ny, -wmax + 2 * wmax * (j + 1) / ny
            if hatch and hatch[0] * X <= (xa + xb) / 2 <= hatch[1] * X and abs((ya + yb) / 2) < hatch[2]:
                continue
            corners = [(xa, ya, za, wa), (xb, ya, zb, wb), (xb, yb, zb, wb), (xa, yb, za, wa)]
            pts = [Vector((x, max(-w, min(w, y)), z)) for x, y, z, w in corners]
            if abs(pts[3].y - pts[0].y) < 0.02 and abs(pts[2].y - pts[1].y) < 0.02:
                continue
            f = bm.faces.new([bm.verts.new(p) for p in pts])
            for l, (x, y, _, _) in zip(f.loops, corners):
                l[uv].uv = (u0 + (u1 - u0) * (x - xa) / (xb - xa), v0 + (v1 - v0) * (y - ya) / (yb - ya))
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
    bm.normal_update()
    parts.append(obj(bm, name, HA, recalc=False))
    if hatch:
        X0, X1 = hatch[0] * X, hatch[1] * X
        z = h.P((hatch[0] + hatch[1]) / 2, t).z
        dark = L.new_bm()
        uvd = dark.loops.layers.uv["UVMap"]
        _, du0, dv0, du1, dv1 = L.RECTS["ha_rope"]
        f = dark.faces.new([dark.verts.new(p) for p in [(X0, -hatch[2], z - 0.5), (X1, -hatch[2], z - 0.5), (X1, hatch[2], z - 0.5), (X0, hatch[2], z - 0.5)]])
        for l in f.loops:
            l[uvd].uv = (du0 + (du1 - du0) * 0.5, dv0 + (dv1 - dv0) * 0.5)   # the coil's dark heart
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        parts.append(obj(dark, "hold", HA, recalc=False))
        rng = random.Random(7)
        cz, hw = z + 0.07, hatch[2]
        for y in (-hw, hw):
            parts.append(wood((X0 - 0.09, y, cz), (X1 + 0.09, y, cz), 0.18, 0.16, rng, name="coaming"))
        for x in (X0, X1):
            parts.append(wood((x, -hw + 0.09, cz), (x, hw - 0.09, cz), 0.18, 0.16, rng, name="coaming"))


def thwart(h, parts, s, t, rng, w=0.26, th=0.06):
    hw = h.half_width(s, t)
    z = h.P(s, t).z
    x = s * h.X(t)
    parts.append(wood((x, -hw, z), (x, hw, z), w, th, rng, name="thwart"))


def mast(parts, x, foot_z, top_z, r, seed):
    parts.append(obj(L.log((x, 0, foot_z), (x, 0, top_z), r, sides=8, band="wood_light", taper=0.7, jitter=0.02, seed=seed),
                     "mast", "MI_WoodTrim", smooth=50))


def yard(parts, x, z, length, r, seed, y=0.0):
    parts.append(obj(L.log((x, y - length / 2, z), (x, y + length / 2, z), r, sides=7, band="wood_light", taper=0.75, jitter=0.02, seed=seed),
                     "yard", "MI_WoodTrim", smooth=50))


def furled_sail(parts, x, z, length, r=0.22):
    """A sail stowed along its yard: a bundle of canvas bound with gaskets."""
    pts = [(x + 0.05, -length / 2 + 0.3 + (length - 0.6) * k / 8, z - r * 0.9 - 0.04 * math.sin(math.pi * k / 8)) for k in range(9)]
    bm = L.sweep(pts, r, sides=8, rect="ha_furled", radius_fn=lambda f: 0.55 + 0.45 * math.sin(math.pi * f))
    parts.append(obj(bm, "furled", HA, smooth=60))


def square_sail(parts, x, z_top, width, height, belly, band="ha_stripe", cols=10, rows=8):
    """A square sail set from its yard, filled by a wind from astern: its
    belly forward (+X), its foot drawn aft at the corners to the sheets."""
    bm = L.new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = L.BANDS[band]
    grid = []
    for j in range(rows + 1):
        v = j / rows
        row = []
        for i in range(cols + 1):
            u = i / cols
            y = (u - 0.5) * width * (1 + 0.08 * v)
            zz = z_top - v * height
            bulge = belly * math.sin(math.pi * u) * math.sin(math.pi * (0.12 + 0.8 * v))
            corner = -0.6 * v ** 3 * (1 - math.sin(math.pi * u))
            row.append(bm.verts.new((x + bulge + corner, y, zz)))
        grid.append(row)
    cloth_u = 1 / (16 * 0.8)   # one 32 px cloth of the band is 0.8 m of sail
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
            for l, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                l[uv].uv = ((a / cols - 0.5) * width * cloth_u, v1 - (v1 - v0) * b / rows)
    bm.normal_update()
    clews = [grid[rows][0].co.copy(), grid[rows][cols].co.copy()]
    parts.append(obj(bm, "sail", SAIL, smooth=60, recalc=False))
    return clews


def stays(parts, top, ends):
    for e in ends:
        rope(parts, [top, e], r=0.018, name="stay")


def bale(parts, at, size, rng, yaw=0.0):
    """A woollen bale in canvas, roped."""
    bm = L.box(size, "ha_sail", bevel=0.05, segments=2)
    L.uv_box_band(bm, list(bm.faces), "ha_sail", scale=0.35)
    L.transform(bm, Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation((0, 0, size[2] / 2)))
    parts.append(obj(bm, "bale", HA, smooth=50))
    for d in (-0.25, 0.25):
        c = Vector(at) + Matrix.Rotation(yaw, 4, "Z") @ Vector((d * size[0], 0, 0))
        hw, hh = size[1] / 2 + 0.01, size[2] + 0.01
        rope(parts, [c + Matrix.Rotation(yaw, 4, "Z") @ Vector((0, -hw, 0.02)), c + Matrix.Rotation(yaw, 4, "Z") @ Vector((0, -hw, hh)),
                     c + Matrix.Rotation(yaw, 4, "Z") @ Vector((0, hw, hh)), c + Matrix.Rotation(yaw, 4, "Z") @ Vector((0, hw, 0.02))], r=0.015, name="lashing")


def cask(parts, at, r=0.32, hgt=0.85, lying=False):
    prof = [(r * 0.86, 0.0), (r, hgt * 0.25), (r * 1.04, hgt * 0.5), (r, hgt * 0.75), (r * 0.86, hgt)]
    bm = L.lathe(prof, 10, band="ha_oak", scale=0.6)
    L.cap(bm, 0.0, "ha_deck", top=False)
    L.cap(bm, hgt, "ha_deck", top=True)
    m = Matrix.Translation(at)
    if lying:
        m = m @ Matrix.Translation((0, 0, r)) @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Translation((0, 0, -hgt / 2))
    L.transform(bm, m)
    parts.append(obj(bm, "cask", HA, smooth=40))


def oar(parts, a, b, blade=0.5, w=0.13, seed=0):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    loom_end = b - d * blade
    parts.append(obj(L.log(a, loom_end, 0.035, sides=6, band="wood_light", taper=0.9, jitter=0.01, seed=seed), "oar", "MI_WoodTrim", smooth=50))
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    parts.append(wood(loom_end, b, w, 0.025, random.Random(seed), up=up, name="blade", band="wood_light"))


# --- Craft ----------------------------------------------------------------------------------------

def rowing_hull():
    return Hull(4.6, 1.45, 0.62, 0.22, 4, sheer=0.32, rocker=0.08, end0=0.84, end_pow=2.4, stations=14, tar_below=3)


def boat_rowing():
    """A small clinker rowing boat, about 4.6 m: four strakes a side, two
    thwarts, tholes on the gunwale, a pair of oars stowed."""
    h = rowing_hull()
    parts = []
    rng = hull_parts(h, parts, lap=0.016)
    posts(h, parts, 0.12, 0.08, 0.02, w=0.06)
    for s in (0.18, -0.38):
        thwart(h, parts, s, 0.72, rng, w=0.22, th=0.045)
    for s in (0.05, -0.55):
        for side in (1, -1):
            p = h.P(s, 1.0, side)
            parts.append(wood(p - Vector((0, 0, 0.02)), p + Vector((0, 0, 0.16)), 0.035, 0.035, rng, up=Vector((1, 0, 0)), name="thole"))
    for side, seed in ((1, 3), (-1, 4)):
        y = side * 0.32
        oar(parts, (-1.65, y, h.P(0.18, 0.72).z + 0.06), (2.0, y * 0.9, h.P(0.18, 0.72).z + 0.08), blade=0.6, w=0.12, seed=seed)
    return parts


def boat_fishing():
    """A clinker fishing boat, about 7.5 m: six strakes a side, three
    thwarts, a mast with its sail furled on the yard, a steering oar on the
    starboard quarter, the net heaped amidships."""
    h = Hull(7.5, 2.2, 0.95, 0.42, 6, sheer=0.48, rocker=0.12, end0=0.85, end_pow=2.2, stations=18, tar_below=5)
    parts = []
    rng = hull_parts(h, parts, lap=0.02)
    posts(h, parts, 0.3, 0.22, 0.08, w=0.07)
    for s in (0.42, 0.08, -0.5):
        thwart(h, parts, s, 0.74, rng, w=0.24, th=0.05)
    mx = 0.42 * h.X(0.74) - 0.15
    mast(parts, mx, h.keel_z(0.25) + 0.1, 6.2 - h.draft, 0.085, 11)
    yard(parts, mx + 0.1, 5.0 - h.draft, 4.2, 0.06, 12)
    furled_sail(parts, mx + 0.1, 5.0 - h.draft, 4.2, r=0.16)
    top = Vector((mx, 0, 6.0 - h.draft))
    stays(parts, top, [h.P(1.0, 1.0) + Vector((0.12, 0, 0.2)), h.P(0.0, 1.0, 1), h.P(0.0, 1.0, -1)])
    # Steering oar, starboard quarter.
    q = h.P(-0.78, 1.0, -1)
    parts.append(wood(q + Vector((0.05, -0.05, 0.05)), q + Vector((0.05, -0.05, -0.25)), 0.12, 0.12, rng, up=Vector((1, 0, 0)), name="boss"))
    oar(parts, q + Vector((0.4, -0.12, 0.65)), q + Vector((-0.8, -0.22, -1.25)), blade=1.0, w=0.24, seed=13)
    # The net heaped amidships: a dark lump, the net drawn over it.
    z = h.P(-0.15, 0.3).z
    lump = L.new_bm()
    bmesh.ops.create_icosphere(lump, subdivisions=2, radius=1.0)
    for v in lump.verts:
        k = 1 + noise.noise(v.co * 2.3) * 0.25
        v.co = Vector((v.co.x * 0.75 * k, v.co.y * 0.55 * k, max(0.0, v.co.z) * 0.32 * k))
    L.transform(lump, Matrix.Translation((-0.15 * h.X(0.3), 0, z)))
    bmesh.ops.remove_doubles(lump, verts=lump.verts, dist=0.01)
    L.uv_box_band(lump, list(lump.faces), "ha_tar", scale=0.4)
    over = lump.copy()
    for v in over.verts:
        v.co.z += 0.02
        v.co.x *= 1.02
        v.co.y *= 1.03
    _, u0, v0, u1, v1 = L.RECTS["ha_net"]
    uvn = over.loops.layers.uv["UVMap"]
    for f in over.faces:
        for l in f.loops:
            p = l.vert.co
            l[uvn].uv = (u0 + (u1 - u0) * (0.5 + 0.45 * math.sin(p.x * 3.0)),
                         v0 + (v1 - v0) * (0.5 + 0.45 * math.sin(p.y * 3.0 + p.z * 2.0)))
    parts.append(obj(lump, "net_heap", HA, smooth=50))
    parts.append(obj(over, "net", CUT, smooth=50))
    return parts


def ship_keel():
    """A trading ship in the Scandinavian clinker tradition, about 16 m
    (a "keel", as the English called such ships): nine strakes a side,
    half decks fore and aft over an open hold of wool and casks, under sail
    (a striped square sail filled from astern), steered by a side rudder
    on the starboard quarter."""
    h = Hull(16.0, 4.6, 1.9, 0.95, 9, sheer=1.05, rocker=0.25, end0=0.86, end_pow=2.2, stations=24, tar_below=8)
    parts = []
    rng = hull_parts(h, parts, lap=0.025)
    posts(h, parts, 0.75, 0.6, 0.35, w=0.11)
    deck(h, parts, 0.48, 0.86, 0.8, name="deck_fore")
    deck(h, parts, -0.86, -0.5, 0.8, name="deck_aft")
    for s in (0.32, 0.0, -0.32):
        thwart(h, parts, s, 0.8, rng, w=0.22, th=0.14)   # cross beams over the hold
    # The cargo in the open hold.
    hz = h.P(0.0, 0.42).z
    for x, y, yaw in ((2.2, 0.5, 0.1), (2.1, -0.5, -0.05), (0.9, 0.0, 0.08), (-0.6, 0.45, -0.1), (-0.7, -0.5, 0.04)):
        bale(parts, (x, y, hz), (1.0, 0.8, 0.7), rng, yaw=yaw)
    for x, y in ((-2.3, 0.6), (-2.4, -0.55), (-1.6, 0.0)):
        cask(parts, (x, y, h.P(-0.2, 0.25).z), r=0.3, hgt=0.8, lying=True)
    # Mast, yard and the sail set.
    mx = 0.4
    top = Vector((mx, 0, 11.0))
    mast(parts, mx, h.keel_z(0.05) + 0.15, top.z + 0.3, 0.16, 21)
    yard(parts, mx + 0.25, 10.2, 9.2, 0.1, 22)
    clews = square_sail(parts, mx + 0.32, 10.1, 8.8, 7.0, 1.3, band="ha_stripe")
    # Sheets from the clews down to the sides aft, the shrouds and forestay.
    for c, side in zip(clews, (-1, 1)):
        rope(parts, [c, h.P(-0.42, 1.0, side) + Vector((0, 0, 0.05))], r=0.016, name="sheet")
    shrouds = [h.P(s, 1.0, side) for s in (0.1, -0.08, -0.25) for side in (1, -1)]
    stays(parts, top, shrouds + [h.P(1.0, 1.0) + Vector((0.3, 0, 0.5))])
    # The side rudder on the starboard quarter, its tiller athwartships.
    q = h.P(-0.86, 0.85, -1)
    parts.append(wood(q + Vector((0, -0.1, 0.0)), q + Vector((0, -0.1, 0.35)), 0.22, 0.22, rng, up=Vector((1, 0, 0)), name="boss"))
    blade_top, blade_bot = q + Vector((0.2, -0.35, 0.9)), q + Vector((-0.55, -0.42, -2.1))
    parts.append(obj(L.log(blade_top, blade_top.lerp(blade_bot, 0.55), 0.08, sides=6, band="wood_dark", seed=23), "rudder_stock", "MI_WoodTrim", smooth=40))
    parts.append(wood(blade_top.lerp(blade_bot, 0.5), blade_bot, 0.52, 0.07, rng, up=Vector((1, 0, 0)), name="rudder"))
    parts.append(wood(blade_top + Vector((0, 0, -0.1)), blade_top + Vector((0, 1.3, -0.05)), 0.07, 0.07, rng, name="tiller"))
    return parts


def ship_cog():
    """A cog, about 20 m: a flat, flush-planked bottom, high clinker sides
    tarred to the top strake, straight stem and sternpost raked out, beams
    run out through its sides,
    a deck with a hatch over the hold, a raised deck aft with a rail, the
    new stern rudder hung on the sternpost, the sail furled on its yard."""
    h = Hull(20.0, 6.4, 3.3, 1.6, 10, shape="flat", sheer=0.7, rocker=0.05, end0=0.72, end_pow=1.0,
             full=3.2, full_pow=0.42, stations=26, tar_below=9)
    parts = []
    rng = hull_parts(h, parts, lap=0.03)
    posts(h, parts, 0.55, 0.5, 0.0, w=0.14)
    td = 0.82
    deck(h, parts, -0.66, 0.8, td, name="deck", hatch=(-0.08, 0.24, 1.0))
    # Beams through the sides, ends standing out (the cog's mark).
    for s in (0.42, 0.12, -0.2, -0.5):
        hw = abs(h.P(s, 0.66).y) + 0.32
        z = h.P(s, 0.66).z
        x = s * h.X(0.66)
        parts.append(wood((x, -hw, z), (x, hw, z), 0.24, 0.24, rng, name="through_beam"))
    # The raised deck aft, on posts, with a rail.
    s0, s1, t_aft = -0.92, -0.66, 1.0
    za = h.P(-0.79, t_aft).z + 0.35
    xa, xb = s0 * h.X(t_aft), s1 * h.X(t_aft)
    wa = h.half_width(-0.79, t_aft)
    planks(parts, (xa, -wa, za), (1, 0, 0), (0, 1, 0), xb - xa, 2 * wa, 0.1, (1.5, 1.5), name="aft_deck")
    for x in (xb, (xa + xb) / 2, xa + 0.3):
        for side in (1, -1):
            y = side * (h.half_width(x / h.X(t_aft), t_aft) - 0.1)
            parts.append(wood((x, y, za), (x, y, za + 0.95), 0.12, 0.12, rng, up=Vector((1, 0, 0)), name="rail_post"))
    for side in (1, -1):
        y = side * (wa - 0.1)
        parts.append(wood((xa + 0.3, y, za + 0.95), (xb, y, za + 0.95), 0.1, 0.1, rng, name="rail"))
    parts.append(wood((xb, -wa + 0.1, za + 0.95), (xb, wa - 0.1, za + 0.95), 0.1, 0.1, rng, name="rail"))
    # The stern rudder on the sternpost, its tiller inboard over the aft deck.
    sp_lo, sp_hi = h.P(-1.0, 0.05), h.P(-1.0, 0.95)
    d = (sp_hi - sp_lo).normalized()
    back = Vector((-1, 0, 0))
    outline = [sp_lo + back * 0.05, sp_lo + back * 1.05 + d * 0.3, sp_lo.lerp(sp_hi, 0.55) + back * 0.75,
               sp_lo.lerp(sp_hi, 0.98) + back * 0.25, sp_lo.lerp(sp_hi, 0.98) + back * 0.05]
    rb = slab([(p.x, p.z) for p in outline], -0.07, 0.07)
    L.uv_box_band(rb, list(rb.faces), "wood_dark")
    parts.append(obj(rb, "rudder", "MI_WoodTrim", recalc=False))
    head = sp_lo.lerp(sp_hi, 0.98) + back * 0.15
    parts.append(wood(head + Vector((0, 0, 0.1)), head + Vector((2.8, 0, 0.55)), 0.12, 0.1, rng, name="tiller"))
    for f in (0.3, 0.6, 0.9):   # pintles and gudgeons
        p = sp_lo.lerp(sp_hi, f)
        parts.append(obj(L.sweep([p + Vector((-0.15, -0.1, 0)), p + Vector((0.08, -0.12, 0)), p + Vector((0.08, 0.12, 0)), p + Vector((-0.15, 0.1, 0))],
                                 0.025, sides=4, band="wood_dark"), "gudgeon", "MI_MetalOrnaments"))
    # Mast, yard and furled sail, the stays and shrouds.
    mx = 1.2
    top = Vector((mx, 0, 16.0))
    mast(parts, mx, h.keel_z(0.1) + 0.2, top.z + 0.3, 0.22, 31)
    yard(parts, mx + 0.3, 13.6, 11.5, 0.13, 32)
    furled_sail(parts, mx + 0.3, 13.6, 11.5, r=0.3)
    shrouds = [h.P(s, 1.0, side) for s in (0.05, -0.08, -0.21) for side in (1, -1)]
    stays(parts, top, shrouds + [h.P(1.0, 1.0) + (h.P(1.0, 1.0) - h.P(1.0, 0.9)).normalized() * 0.4])
    # Wool going aboard: bales and casks by the hatch.
    dz = h.P(0.4, td).z
    for x, y, yaw in ((4.2, 1.4, 0.2), (4.3, 0.2, -0.1), (5.4, 1.0, 0.05)):
        bale(parts, (x, y, dz), (1.0, 0.8, 0.7), rng, yaw=yaw)
    for x, y in ((-2.2, -1.6), (-2.9, -1.2)):
        cask(parts, (x, y, h.P(-0.12, td).z), r=0.32, hgt=0.85)
    return parts


# --- The waterfront -------------------------------------------------------------------------------

def quay_top(parts, y0, y1=4.0, x0=-2.0, x1=2.0):
    """The quay's trodden top from its edge back to y1, in the earth band."""
    band_strip(parts, [(x0, y1, QUAY), (x1, y1, QUAY)], [(x0, y0, QUAY), (x1, y0, QUAY)], "ha_earth", u_scale=0.25, name="quay_top")


def quay_timber():
    """4 m of timber revetment quay: squared posts on the face every metre,
    planks laid edge on edge behind them holding back the fill, raking
    braces in front down to the bed, a capping plate, the tide line on it
    all, the trodden top behind."""
    rng = random.Random(41)
    parts = []
    for x in (-1.5, -0.5, 0.5, 1.5):
        parts.append(wood((x, 0.0, BED - 0.5), (x, 0.0, QUAY + 0.06), 0.24, 0.24, rng, up=Vector((1, 0, 0)), name="post"))
        parts.append(wood((x, -0.05, 0.75), (x, -1.45, BED + 0.1), 0.18, 0.18, rng, up=Vector((1, 0, 0)), name="brace"))
        tide_sleeve(parts, x, 0.0, 0.14)
    zs = []
    z = BED
    while z < QUAY - 0.05:
        zs.append(z)
        z += 0.26
    for z in zs:
        parts.append(wood((-2.0, 0.17, z + 0.12), (2.0, 0.17, z + 0.12), 0.07, 0.24, rng, name="plank"))
    parts.append(wood((-2.0, 0.12, QUAY - 0.05), (2.0, 0.12, QUAY - 0.05), 0.34, 0.16, rng, name="plate"))
    band_strip(parts, [(-2.0, 0.125, -0.8), (2.0, 0.125, -0.8)], [(-2.0, 0.125, 0.6), (2.0, 0.125, 0.6)], "ha_tide", name="tide", mat=CUT)
    quay_top(parts, 0.29)
    return parts


def quay_stone(steps=False):
    """4 m of stone quay: a rubble wall battered back from the bed, a
    coping of dressed stone, an iron mooring ring, the tide line, the
    trodden top behind; with `steps`, water stairs down its face."""
    parts = []
    bm = L.new_bm()
    v = [bm.verts.new(p) for p in [(-2.0, -0.35, BED - 0.3), (2.0, -0.35, BED - 0.3), (2.0, 0.0, QUAY - 0.22), (-2.0, 0.0, QUAY - 0.22),
                                   (-2.0, 0.9, BED - 0.3), (2.0, 0.9, BED - 0.3), (2.0, 0.9, QUAY - 0.22), (-2.0, 0.9, QUAY - 0.22)]]
    for q in ((0, 1, 2, 3), (1, 5, 6, 2), (5, 4, 7, 6), (4, 0, 3, 7), (3, 2, 6, 7), (4, 5, 1, 0)):
        bm.faces.new([v[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(obj(uv_stone(bm), "wall", STONE, recalc=False))
    # The coping, stone by stone, standing a little proud.
    x = -2.0
    k = 0
    while x < 2.0 - 1e-6:
        w = min(2.0 - x, (0.9, 0.7, 1.1, 0.8, 0.5)[k % 5])
        parts.append(ashlar(box(x + 0.01, x + w - 0.01, -0.08, 0.6, QUAY - 0.22, QUAY), "coping"))
        x += w
        k += 1
    z_hi, z_lo = QUAY - 0.22, BED - 0.3

    def face_y(z):   # the battered face, a hand's breadth proud of it
        return -0.35 * (z_hi - z) / (z_hi - z_lo) - 0.02
    band_strip(parts, [(-2.0, face_y(-0.8), -0.8), (2.0, face_y(-0.8), -0.8)], [(-2.0, face_y(0.6), 0.6), (2.0, face_y(0.6), 0.6)], "ha_tide", name="tide", mat=CUT)
    quay_top(parts, 0.6)
    ring_at = Vector((-1.0, face_y(0.55) + 0.01, 0.55))
    parts.append(obj(L.sweep([ring_at + Vector((0, 0, 0.12)), ring_at + Vector((0, -0.04, 0.12))], 0.04, sides=6, band="wood_dark"), "ring_bolt", "MI_MetalOrnaments"))
    pts = [ring_at + Vector((0.12 * math.sin(a), -0.06, 0.12 * math.cos(a) - 0.0)) for a in [2 * math.pi * i / 12 for i in range(13)]]
    parts.append(obj(L.sweep(pts, 0.018, sides=5, band="wood_dark", closed=True), "ring", "MI_MetalOrnaments"))
    if steps:
        stairs(parts)
    return parts


def stairs(parts, x_top=-1.7, x_low=1.7, z_low=-0.75, out=0.95, n=12):
    """Water stairs down the quay's face: a flight against the wall falling
    toward +X from the quay's top to below the water. One solid of rubble,
    its sides laid out as explicit triangles (a column per step, so nothing
    overlaps), a dressed tread on each step."""
    run = (x_low - x_top) / n
    rise = (QUAY - z_low) / (n - 1)
    z_of = [QUAY - k * rise for k in range(n)]   # step k's top
    bed = BED - 0.3
    y0, y1 = -out, -0.02
    bm = L.new_bm()
    va, vb = {}, {}

    def vert(store, p, y):
        key = (round(p[0], 6), round(p[1], 6))
        if key not in store:
            store[key] = bm.verts.new((p[0], y, p[1]))
        return store[key]

    def quad(pts, store_y):
        return [vert(store, p, y) for p, (store, y) in zip(pts, store_y)]
    for k in range(n):
        xa, xb = x_top + k * run, x_top + (k + 1) * run
        A, B, D, E = (xa, bed), (xb, bed), (xb, z_of[k]), (xa, z_of[k])
        tris = [(A, D, E)]
        if k + 1 < n:
            C = (xb, z_of[k + 1])
            tris += [(A, B, C), (A, C, D)]
            # The riser below this step's nose, down to the next step.
            bm.faces.new([vert(va, D, y0), vert(va, C, y0), vert(vb, C, y1), vert(vb, D, y1)])
        else:
            tris += [(A, B, D)]
            bm.faces.new([vert(va, D, y0), vert(va, B, y0), vert(vb, B, y1), vert(vb, D, y1)])   # the low end
        for t in tris:
            bm.faces.new([vert(va, p, y0) for p in t])
            bm.faces.new([vert(vb, p, y1) for p in reversed(t)])
        bm.faces.new([vert(va, E, y0), vert(va, D, y0), vert(vb, D, y1), vert(vb, E, y1)])   # the step's top
        bm.faces.new([vert(va, B, y0), vert(va, A, y0), vert(vb, A, y1), vert(vb, B, y1)])   # underneath
    E0, A0 = (x_top, z_of[0]), (x_top, bed)
    bm.faces.new([vert(va, A0, y0), vert(va, E0, y0), vert(vb, E0, y1), vert(vb, A0, y1)])   # the top end
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    parts.append(obj(uv_stone(bm), "stairs", STONE, recalc=False))
    for k in range(n):
        xa = x_top + k * run
        z = z_of[k]
        parts.append(ashlar(box(xa, xa + run + 0.04, y0 - 0.04, y1 - 0.01, z - 0.06, z + 0.02), "tread"))


def bent(parts, x, half, rng, n=2, seed=0):
    """A pile bent across the jetty at x: piles, a head beam, cross braces;
    weed on the piles at the water."""
    ys = [-half + 2 * half * k / (n - 1) for k in range(n)]
    for k, y in enumerate(ys):
        parts.append(pole((x, y, BED - 0.8), (x, y, JETTY - 0.28), 0.14, seed + k, name="pile"))
        tide_sleeve(parts, x, y, 0.16)
    parts.append(wood((x, -half - 0.25, JETTY - 0.3), (x, half + 0.25, JETTY - 0.3), 0.24, 0.22, rng, name="head"))
    for a, b in ((ys[0], ys[-1]), (ys[-1], ys[0])):
        parts.append(wood((x + 0.12, a, JETTY - 0.45), (x + 0.12, b, -0.6), 0.12, 0.12, rng, up=Vector((1, 0, 0)), name="brace"))


def jetty():
    """4 m of jetty: plank decking laid across on three stringers, carried
    on a bent of two piles in the middle, braced."""
    rng = random.Random(45)
    parts = []
    bent(parts, 0.0, 1.0, rng, 2, seed=50)
    for y in (-0.9, 0.0, 0.9):
        parts.append(wood((-2.0, y, JETTY - 0.18), (2.0, y, JETTY - 0.18), 0.16, 0.2, rng, name="stringer"))
    planks(parts, (-2.0, 1.2, JETTY), (0, -1, 0), (1, 0, 0), 2.4, 4.0, 0.08, (2.4, 1.5), name="deck")
    return parts


def jetty_end():
    """The jetty's head, 4 m along it and 4.4 m across: two bents of three
    piles, decking, mooring posts at its corners, a ladder down the end to
    the water."""
    rng = random.Random(47)
    parts = []
    for x, seed in ((-1.6, 60), (1.6, 63)):
        bent(parts, x, 1.95, rng, 3, seed=seed)
    for y in (-1.8, -0.9, 0.0, 0.9, 1.8):
        parts.append(wood((-2.0, y, JETTY - 0.18), (2.0, y, JETTY - 0.18), 0.16, 0.2, rng, name="stringer"))
    planks(parts, (-2.0, 2.2, JETTY), (0, -1, 0), (1, 0, 0), 4.4, 4.0, 0.08, (2.2, 1.5), name="deck")
    for x, y in ((-1.75, -1.95), (1.75, -1.95), (1.75, 1.95)):
        parts.append(pole((x, y, JETTY - 0.3), (x, y, JETTY + 0.75), 0.13, int(x * 10 + y), name="bollard"))
    # A rope round the seaward post, its end coiled on the deck.
    p = Vector((1.75, -1.95, JETTY + 0.5))
    rope(parts, [p + Vector((0.14 * math.cos(a), 0.14 * math.sin(a), 0.02 * a)) for a in [i * 0.5 for i in range(14)]], name="rope")
    coil = L.lathe([(0.32, 0.0), (0.34, 0.05), (0.32, 0.1)], 12, rect="ha_rope")
    L.cap(coil, 0.1, "ha_rope", top=True)
    L.transform(coil, Matrix.Translation((1.1, -1.5, JETTY)))
    parts.append(obj(coil, "coil", HA, smooth=50))
    # The ladder down the end.
    lx = 2.05
    for y in (-0.3, 0.3):
        parts.append(wood((lx, y, JETTY + 0.45), (lx, y, -0.9), 0.09, 0.09, rng, up=Vector((1, 0, 0)), name="ladder"))
    for z in [JETTY - 0.15 - 0.32 * k for k in range(7)]:
        parts.append(wood((lx, -0.3, z), (lx, 0.3, z), 0.06, 0.06, rng, name="rung"))
    return parts


def slipway():
    """A log slipway down the shore into the water: logs laid across two
    runners, 8 m from the ground (+Y) down to below the water (-Y). The
    origin is where it meets the water."""
    parts = []
    y_hi, z_hi, y_lo, z_lo = 4.0, 0.95, -4.0, -0.9

    def z_at(y):
        return z_lo + (y - y_lo) / (y_hi - y_lo) * (z_hi - z_lo)
    for x in (-1.0, 1.0):
        parts.append(pole((x, y_hi + 0.3, z_at(y_hi + 0.3) - 0.22), (x, y_lo - 0.3, z_at(y_lo - 0.3) - 0.22), 0.13, int(x * 7 + 20), name="runner"))
    y = y_lo + 0.2
    k = 0
    while y < y_hi:
        parts.append(pole((-1.55, y, z_at(y) - 0.02), (1.55, y, z_at(y) - 0.02), 0.11 + 0.012 * (k % 3), 70 + k, name="log"))
        y += 0.55
        k += 1
    return parts


def mooring_post():
    """A stout oak post on the quay, a mooring rope turned round it."""
    parts = [pole((0, 0, -0.6), (0, 0, 1.0), 0.17, 81, name="post")]
    p = Vector((0, 0, 0.62))
    rope(parts, [p + Vector((0.19 * math.cos(a), 0.19 * math.sin(a), 0.025 * a)) for a in [i * 0.45 for i in range(18)]], name="rope")
    rope(parts, [p + Vector((0.19, 0, 0)), p + Vector((0.4, -0.6, -0.3)), p + Vector((0.6, -1.4, -0.62))], name="rope")
    return parts


def hoist():
    """A hoist on the quay: a post on crossed sole beams with raking struts,
    a jib braced out from its head, a block at the jib's end and the rope
    down to a bale on the hook, back along the jib and down to a windlass
    at the post's foot."""
    rng = random.Random(53)
    parts = []
    H, J = 5.2, 3.2
    parts.append(wood((0, 0, -0.1), (0, 0, H), 0.32, 0.32, rng, up=Vector((1, 0, 0)), name="post"))
    for d in (Vector((1, 0, 0)), Vector((0, 1, 0))):
        parts.append(wood(-d * 1.3 + Vector((0, 0, 0.12)), d * 1.3 + Vector((0, 0, 0.12)), 0.26, 0.24, rng, name="sole"))
    for d in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, -1, 0))):
        parts.append(wood(d * 1.1 + Vector((0, 0, 0.24)), d * 0.12 + Vector((0, 0, 1.6)), 0.14, 0.14, rng, up=Vector((0, 0, 1)) if abs(d.x) < 0.5 else Vector((0, 1, 0)), name="strut"))
    jz = H - 0.4
    parts.append(wood((0.0, 0, jz), (-0.2, -J, jz + 0.25), 0.24, 0.26, rng, name="jib"))
    parts.append(wood((0.0, 0, H - 2.2), (-0.12, -J * 0.62, jz + 0.1), 0.16, 0.16, rng, up=Vector((1, 0, 0)), name="jib_brace"))
    end = Vector((-0.2, -J, jz + 0.25))
    blk = box(-0.12, 0.12, -0.12, 0.12, -0.2, 0.2)
    L.uv_box_band(blk, list(blk.faces), "wood_dark")
    L.transform(blk, Matrix.Translation(end + Vector((0, 0, -0.32))))
    parts.append(obj(blk, "block", "MI_WoodTrim"))
    hook = end + Vector((0, 0, -2.6))
    rope(parts, [end + Vector((0, 0, -0.45)), hook + Vector((0, 0, 0.2))], name="fall")
    parts.append(obj(L.sweep([hook + Vector((0, 0, 0.2)), hook, hook + Vector((0.12, 0, -0.12)), hook + Vector((0.16, 0, 0.02))], 0.025, sides=5, band="wood_dark"), "hook", "MI_MetalOrnaments"))
    bale(parts, hook + Vector((0, 0, -1.25)), (1.0, 0.75, 0.75), rng)
    for d in (-0.32, 0.32):   # slings from the hook to the bale's corners
        rope(parts, [hook + Vector((0, 0, -0.05)), hook + Vector((d, 0.28, -0.52))], r=0.016, name="sling")
        rope(parts, [hook + Vector((0, 0, -0.05)), hook + Vector((d, -0.28, -0.52))], r=0.016, name="sling")
    rope(parts, [end + Vector((0, 0, 0.15)), Vector((0.0, -0.1, H + 0.12)), Vector((0.22, -0.2, H - 0.2)), Vector((0.24, 0.0, 0.85))], name="rope")
    # The windlass: a drum between two frames, a crank at each end.
    for y in (-0.55, 0.55):
        parts.append(wood((0.55, y, 0.12), (0.4, y, 1.0), 0.12, 0.12, rng, up=Vector((1, 0, 0)), name="frame"))
        parts.append(wood((0.0, y, 0.12), (0.4, y, 1.0), 0.12, 0.12, rng, up=Vector((1, 0, 0)), name="frame"))
    drum = L.log((0.32, -0.62, 0.9), (0.32, 0.62, 0.9), 0.15, sides=8, band="wood_dark", taper=1.0, jitter=0.0, seed=55)
    parts.append(obj(drum, "drum", "MI_WoodTrim", smooth=40))
    for y, a in ((-0.68, 0.0), (0.68, math.pi)):
        c = Vector((0.32, y, 0.9))
        arm = c + Vector((0.35 * math.cos(a + 0.6), 0, 0.35 * math.sin(a + 0.6)))
        parts.append(wood(c, arm, 0.06, 0.06, rng, up=Vector((0, 1, 0)), name="crank"))
        parts.append(wood(arm, arm + Vector((0, math.copysign(0.25, y), 0)), 0.05, 0.05, rng, name="handle"))
    coil = L.lathe([(0.17, -0.12), (0.19, 0.0), (0.17, 0.12)], 10, rect="ha_rope")
    L.transform(coil, Matrix.Translation((0.32, 0, 0.9)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    parts.append(obj(coil, "rope_on_drum", HA, smooth=50))
    return parts


# --- The shore ------------------------------------------------------------------------------------

def net_rack():
    """Nets drying: three crossed-pole trestles carrying a ridge pole, the
    nets hung over it down both sides, cork floats along their head rope."""
    parts = []
    xs = (-2.0, 0.0, 2.0)
    for k, x in enumerate(xs):
        for side in (1, -1):
            parts.append(pole((x + 0.05 * side, side * 0.75, -0.1), (x - 0.02 * side, -side * 0.1, 2.1), 0.05, 90 + 2 * k + (side > 0), name="leg"))
    parts.append(pole((-2.3, 0.0, 2.05), (2.3, 0.0, 2.05), 0.055, 97, name="ridge"))
    _, u0, v0, u1, v1 = L.RECTS["ha_net"]
    for side in (1, -1):
        bm = L.new_bm()
        uv = bm.loops.layers.uv["UVMap"]
        cols, rows = 14, 8
        grid = []
        for j in range(rows + 1):
            v = j / rows
            row = []
            for i in range(cols + 1):
                u = i / cols
                x = -2.2 + 4.4 * u
                sag = 0.18 * math.sin(math.pi * ((u * 2) % 1.0))
                drop = v * (1.55 + 0.12 * math.sin(u * 9.0)) + sag * v
                y = side * (0.06 + 0.32 * v + 0.05 * math.sin(u * 13.0 + v * 4.0))
                row.append(bm.verts.new((x, y, 2.05 - drop)))
            grid.append(row)
        for j in range(rows):
            for i in range(cols):
                f = bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
                for l, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                    # The net cell repeats every 0.6 m: one quad of the grid per repeat.
                    l[uv].uv = (u0 + (u1 - u0) * (a - i), v0 + (v1 - v0) * (b - j))
        bm.normal_update()
        head = [grid[0][i].co.copy() for i in range(1, cols, 2)]
        parts.append(obj(bm, "net", CUT, smooth=60, recalc=False))
        for p in head:
            cork = L.lathe([(0.0, -0.05), (0.06, -0.04), (0.07, 0.0), (0.06, 0.04), (0.0, 0.05)], 7, band="ha_oak")
            L.transform(cork, Matrix.Translation(p + Vector((0, side * 0.05, -0.08))) @ Matrix.Rotation(math.pi / 2, 4, "X"))
            parts.append(obj(cork, "float", HA, smooth=50))
    return parts


def boat_ashore():
    """The rowing boat turned over on two trestles on the shore, its
    bottom up to be tarred."""
    rng = random.Random(59)
    parts = boat_rowing()
    h = rowing_hull()
    lift = 0.75 + (h.sheer_z(0.0))
    turn = Matrix.Translation((0, 0, lift + 0.05)) @ Matrix.Rotation(math.pi, 4, "X")
    keep = []
    for o in parts:
        if o.name.startswith(("oar", "blade", "thwart", "thole")):
            bpy.data.objects.remove(o)
            continue
        o.data.transform(turn)
        keep.append(o)
    parts = keep
    for x in (-1.1, 1.1):
        for side in (1, -1):
            parts.append(wood((x, side * 0.55, 0.0), (x, side * 0.15, 0.78), 0.08, 0.08, rng, up=Vector((1, 0, 0)), name="trestle_leg"))
        parts.append(wood((x, -0.7, 0.78), (x, 0.7, 0.78), 0.12, 0.1, rng, name="trestle"))
    return parts


BUILDERS = {
    "SE_Quay_Timber": quay_timber,
    "SE_Quay_Stone": quay_stone,
    "SE_Quay_Steps": lambda: quay_stone(steps=True),
    "SE_Jetty": jetty,
    "SE_Jetty_End": jetty_end,
    "SE_Slipway": slipway,
    "SE_Mooring_Post": mooring_post,
    "SE_Hoist": hoist,
    "SE_Boat_Rowing": boat_rowing,
    "SE_Boat_Fishing": boat_fishing,
    "SE_Ship_Keel": ship_keel,
    "SE_Ship_Cog": ship_cog,
    "SE_Net_Rack": net_rack,
    "SE_Boat_Ashore": boat_ashore,
}


# --- Build, export, review -------------------------------------------------------------------------

def setup():
    L.reset()
    L.custom_material(HA, (1.0, 1.0, 1.0), roughness=0.85, image=HA_TEX)
    L.custom_material(SAIL, (1.0, 1.0, 1.0), roughness=0.9, image=HA_TEX)
    m = L.custom_material(CUT, (1.0, 1.0, 1.0), roughness=0.9, image=HA_TEX)
    # Cut the nets and the weed out in the review renders as the game does.
    nodes, links = m.node_tree.nodes, m.node_tree.links
    tex = [n for n in nodes if n.type == "TEX_IMAGE"][0]
    links.new(tex.outputs["Alpha"], nodes["Principled BSDF"].inputs["Alpha"])


def build(only=None):
    built = []
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)  # same source, same GLBs
        objs = fn()
        for o in objs:
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
        o.location = ((i % 4) * 26.0, (i // 4) * 26.0, 0)
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
            save_blend(built, os.path.join(HERE, "harbour.blend"))
            built = [o for o in bpy.data.objects if o.name in BUILDERS]
    if "--review" in args:
        out = args[args.index("--review") + 1]
        os.makedirs(out, exist_ok=True)
        for o in built:
            # Lifted to stand on the review's ground, so what is under the water shows.
            low = min((o.matrix_world @ Vector(c)).z for c in o.bound_box) if o.location.z == 0 else 0.0
            for other in built:
                other.hide_render = other is not o
                other.location = (0, 0, 0)
            o.location = (0, 0, -low)
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
