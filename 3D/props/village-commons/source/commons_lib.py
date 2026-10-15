"""Modelling helpers for the Village Commons family (Blender 4.2, bpy).

Everything is built from code so the assets can be regenerated and tuned:
lathe (turned/round parts), beams and planks, rough logs, rubble stones,
swept tubes (rope, iron), roof slabs and cloth. UVs are laid straight onto
the shared Quaternius trim sheets, so the commons use the same wood, stone,
tile and iron textures as the village buildings.

Units are meters, Z up (the glTF exporter converts to Godot's Y up).
"""
import math
import os
import random

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector, noise

SOURCE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(SOURCE)
LIB3D = os.path.dirname(os.path.dirname(FAMILY))
VILLAGE_TEX = os.path.join(LIB3D, "environments", "quaternius-medieval-village-standard", "models")

# 1 UV unit = 2 m on the 2048 px trim sheets (1024 px per meter).
UV_PER_M = 0.5

# Horizontal trim bands in Blender UV space (v up); u tiles freely.
BANDS = {
    "wood_light": ("MI_WoodTrim", 0.702, 0.990),
    "wood_dark": ("MI_WoodTrim", 0.394, 0.682),
    "wood_moulding": ("MI_WoodTrim", 0.058, 0.200),
    "rock_cobble": ("MI_RockTrim", 0.692, 0.992),
    "rock_slate": ("MI_RockTrim", 0.428, 0.668),
    "rock_ashlar": ("MI_RockTrim", 0.008, 0.408),
}
# Rectangles (u0, v0, u1, v1) for things that don't tile.
RECTS = {
    "end_grain": ("MI_WoodTrim", 0.346, 0.228, 0.489, 0.366),
    "end_grain_pale": ("MI_WoodTrim", 0.844, 0.228, 0.987, 0.366),
    "iron_strap": ("MI_MetalOrnaments", 0.088, 0.040, 0.202, 0.830),
    "iron_bar": ("MI_MetalOrnaments", 0.006, 0.030, 0.054, 0.970),
    "iron_plate": ("MI_MetalOrnaments", 0.848, 0.040, 0.982, 0.520),
}

MATERIALS = {
    "MI_WoodTrim": ("T_WoodTrim_BaseColor.png", "T_WoodTrim_Normal.png"),
    "MI_RockTrim": ("T_RockTrim_BaseColor.png", "T_RockTrim_Normal.png"),
    "MI_RoundTiles": ("T_RoundTiles_BaseColor.png", "T_RoundTiles_Normal.png"),
    "MI_MetalOrnaments": ("T_MetalOrnaments_BaseColor.png", None),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    """A preview material for Cycles; export replaces it with the kit's."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    if name in MATERIALS:
        base, normal = MATERIALS[name]
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(VILLAGE_TEX, base), check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if normal:
            ntex = nt.nodes.new("ShaderNodeTexImage")
            ntex.image = bpy.data.images.load(os.path.join(VILLAGE_TEX, normal), check_existing=True)
            ntex.image.colorspace_settings.name = "Non-Color"
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = 0.8
        if name == "MI_MetalOrnaments":
            bsdf.inputs["Metallic"].default_value = 0.6
            bsdf.inputs["Roughness"].default_value = 0.5
    return m


def custom_material(name, color, roughness=0.8, image=None):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image, check_existing=True)
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


# --- Mesh plumbing ---------------------------------------------------------------------------

def new_bm():
    """A bmesh with the texture UVs ("UVMap", active) and a second channel
    ("Sway") that banners use for wind weights (0 = fixed, 1 = free)."""
    bm = bmesh.new()
    bm.loops.layers.uv.new("UVMap")
    bm.loops.layers.uv.new("Sway")
    return bm


def set_sway(bm, fn):
    """Writes wind weights fn(vertex position) into the Sway channel."""
    sw = bm.loops.layers.uv["Sway"]
    for f in bm.faces:
        for l in f.loops:
            l[sw].uv = (max(0.0, min(1.0, fn(l.vert.co))), 0.0)


def to_object(bm, name, mat_name, smooth_angle=35.0, collection=None, recalc=True):
    me = bpy.data.meshes.new(name)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(obj)
    me.materials.append(material(mat_name) if not mat_name.startswith("MI_Commons") else bpy.data.materials[mat_name])
    if smooth_angle is not None:
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    return obj


def join(objs, name):
    objs = [o for o in objs if o is not None]
    ctx = {"active_object": objs[0], "selected_editable_objects": objs, "object": objs[0]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.join()
    o = objs[0]
    o.name = name
    o.data.name = name
    return o


def weighted_normals(obj):
    mod = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
    mod.keep_sharp = True
    mod.weight = 50
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def transform(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)


def bevel_edges(bm, width, segments=1, angle=30.0):
    """Bevels edges sharper than `angle` degrees (rounded, crafted edges)."""
    edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > math.radians(angle)]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)


def frame_from(p0, p1, up=Vector((0, 0, 1))):
    """Matrix taking local X to the segment p0 -> p1 (origin at p0)."""
    p0, p1 = Vector(p0), Vector(p1)
    x = (p1 - p0).normalized()
    if abs(x.dot(up)) > 0.99:
        up = Vector((1, 0, 0)) if abs(x.x) < 0.9 else Vector((0, 1, 0))
    y = up.cross(x).normalized()
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = p0
    return m


# --- UV mapping ---------------------------------------------------------------------------------

def _band(name):
    mat, v0, v1 = BANDS[name]
    return mat, v0, v1


def uv_beam_local(bm, length, band, end_rect="end_grain", v_off=None, scale=UV_PER_M, rng=None):
    """UVs for a box/log built along local +X: long faces -> band, ends -> end grain."""
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = _band(band)
    rng = rng or random
    cross = 0.0
    for v in bm.verts:
        cross = max(cross, abs(v.co.y), abs(v.co.z))
    span = 2 * cross * scale
    if v_off is None:
        v_off = rng.uniform(0.0, max(0.0, (v1 - v0) - span * 2.2))
    u_off = rng.uniform(0.0, 1.0)
    er = RECTS[end_rect] if end_rect else None
    for f in bm.faces:
        n = f.normal
        if abs(n.x) > 0.8 and end_rect:
            for l in f.loops:
                p = l.vert.co
                a = (p.y / (2 * cross) + 0.5) if cross else 0.5
                b = (p.z / (2 * cross) + 0.5) if cross else 0.5
                l[uv].uv = (er[1] + (er[3] - er[1]) * a, er[2] + (er[4] - er[2]) * b)
            continue
        # Wrap the cross-section around: y for top/bottom, z for sides, plus
        # a quarter-turn offset per side so grain doesn't mirror.
        for l in f.loops:
            p = l.vert.co
            if abs(n.z) >= abs(n.y):
                c = p.y + (0 if n.z > 0 else 2 * cross)
            else:
                c = p.z + (cross if n.y > 0 else 3 * cross)
            l[uv].uv = (u_off + p.x * scale, v0 + v_off + (c + cross) * scale * 0.5)


def uv_planar_band(bm, faces, band, axis_u, axis_v, origin=Vector((0, 0, 0)), scale=UV_PER_M, v_off=0.0, u_off=0.0):
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = _band(band)
    for f in faces:
        for l in f.loops:
            d = l.vert.co - origin
            l[uv].uv = (u_off + d.dot(axis_u) * scale, v0 + v_off + d.dot(axis_v) * scale)


def uv_rect_planar(bm, faces, rect, axis_u, axis_v, center, size_u, size_v):
    uv = bm.loops.layers.uv["UVMap"]
    _, u0, v0, u1, v1 = RECTS[rect]
    for f in faces:
        for l in f.loops:
            d = l.vert.co - center
            a = d.dot(axis_u) / size_u + 0.5
            b = d.dot(axis_v) / size_v + 0.5
            l[uv].uv = (u0 + (u1 - u0) * a, v0 + (v1 - v0) * b)


def uv_box_band(bm, faces, band, scale=UV_PER_M, v_off=0.0, u_off=0.0):
    """Box projection into a band (stones and lumpy parts): each face is
    projected along its dominant axis; v starts at the part's lowest point."""
    uv = bm.loops.layers.uv["UVMap"]
    _, v0, v1 = _band(band)
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    for f in faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for l in f.loops:
            p = l.vert.co
            l[uv].uv = (u_off + p[a] * scale, v0 + v_off + (p[b] - lo[b]) * scale)


# --- Primitives -----------------------------------------------------------------------------

def lathe(profile, segs, band=None, mat=None, rect=None, r_ref=None, phase=0.0, scale=UV_PER_M,
          v_off=0.0, u_off=0.0, jitter=0.0, seed=0, flat=False):
    """Revolves (r, z) points (bottom to top) around Z. UV: u around, v along
    the profile (inside `band`), or the whole surface into `rect`."""
    bm = new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    rng = random.Random(seed)
    rings = []
    for k, (r, z) in enumerate(profile):
        ring = []
        for i in range(segs):
            a = phase + 2 * math.pi * i / segs
            rr = r * (1.0 + (rng.uniform(-jitter, jitter) if jitter else 0.0))
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    lens = [0.0]
    for k in range(1, len(profile)):
        (r0, z0), (r1, z1) = profile[k - 1], profile[k]
        lens.append(lens[-1] + math.hypot(r1 - r0, z1 - z0))
    if r_ref is None:
        r_ref = max(r for r, _ in profile) or 0.1
    circ = 2 * math.pi * r_ref
    if band:
        _, bv0, bv1 = _band(band)
        vs = min(scale, (bv1 - bv0 - v_off) / max(lens[-1], 1e-4))
    for k in range(len(profile) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            quad = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            if profile[k][0] < 1e-5:
                quad = [rings[k][i], rings[k + 1][j], rings[k + 1][i]]
            elif profile[k + 1][0] < 1e-5:
                quad = [rings[k][i], rings[k][j], rings[k + 1][i]]
            try:
                f = bm.faces.new(quad)
            except ValueError:
                continue
            for l in f.loops:
                idx = rings[k].index(l.vert) if l.vert in rings[k] else rings[k + 1].index(l.vert)
                kk = k if l.vert in rings[k] else k + 1
                ii = idx
                if ii == 0 and (i == segs - 1):
                    ii = segs
                if band:
                    l[uv].uv = (u_off + ii / segs * circ * scale, bv0 + v_off + lens[kk] * vs)
                elif rect:
                    _, u0, v0, u1, v1 = RECTS[rect]
                    l[uv].uv = (u0 + (u1 - u0) * (ii / segs), v0 + (v1 - v0) * lens[kk] / lens[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    # Caps where the profile ends away from the axis.
    return bm


def cap(bm, z, rect_or_band, kind="rect", top=True):
    """Fills the open ring at height z with an n-gon (end grain or a band)."""
    uv = bm.loops.layers.uv["UVMap"]
    edges = [e for e in bm.edges if e.is_boundary and abs(e.verts[0].co.z - z) < 1e-4 and abs(e.verts[1].co.z - z) < 1e-4]
    if not edges:
        return
    res = bmesh.ops.edgeloop_fill(bm, edges=edges)
    for f in res["faces"]:
        f.normal_update()
        if (f.normal.z < 0) == top:
            f.normal_flip()
        rmax = max((Vector((l.vert.co.x, l.vert.co.y)).length for l in f.loops), default=0.1) or 0.1
        for l in f.loops:
            p = l.vert.co
            if kind == "rect":
                _, u0, v0, u1, v1 = RECTS[rect_or_band]
                l[uv].uv = (u0 + (u1 - u0) * (p.x / rmax * 0.5 + 0.5), v0 + (v1 - v0) * (p.y / rmax * 0.5 + 0.5))
            else:
                _, v0, v1 = _band(rect_or_band)
                l[uv].uv = (p.x * UV_PER_M, v0 + (p.y / rmax * 0.5 + 0.5) * min(v1 - v0, 2 * rmax * UV_PER_M))


def box(size, band, bevel=0.015, segments=1, end_rect=None, rng=None, v_off=None):
    """A box along local X (length size[0]), centered, with rounded edges."""
    bm = new_bm()
    bmesh.ops.create_cube(bm, size=1.0)
    transform(bm, Matrix.Diagonal((size[0], size[1], size[2], 1)))
    if bevel:
        bevel_edges(bm, bevel, segments)
    bm.normal_update()
    uv_beam_local(bm, size[0], band, end_rect=end_rect, rng=rng, v_off=v_off)
    return bm


def beam(p0, p1, w, h, band="wood_dark", bevel=0.012, segments=1, end_rect="end_grain", roll=0.0, up=Vector((0, 0, 1)), rng=None):
    """A squared timber from p0 to p1 (w across, h tall)."""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    bm = box((L, w, h), band, bevel, segments, end_rect, rng)
    transform(bm, Matrix.Translation((L / 2, 0, 0)))
    if roll:
        transform(bm, Matrix.Rotation(roll, 4, "X"))
    transform(bm, frame_from(p0, p1, up))
    return bm


def log(p0, p1, r, sides=8, band="wood_dark", taper=0.9, jitter=0.12, bend=0.0, seed=0, end_rect="end_grain", rings=5):
    """A rough round log (posts, axles): an irregular, slightly tapered tube."""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    rng = random.Random(seed)
    bm = new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    loops = []
    for k in range(rings + 1):
        t = k / rings
        rr = r * (1.0 + (taper - 1.0) * t)
        off = Vector((0, math.sin(t * math.pi) * bend, 0))
        ring = []
        for i in range(sides):
            a = 2 * math.pi * i / sides + seed
            j = 1.0 + rng.uniform(-jitter, jitter) + 0.6 * jitter * noise.noise(Vector((t * 3.0, i * 0.7, seed)))
            ring.append(bm.verts.new((t * L, rr * j * math.cos(a) + off.y, rr * j * math.sin(a))))
        loops.append(ring)
    _, v0, v1 = _band(band)
    circ = 2 * math.pi * r * UV_PER_M
    vs = min(1.0, (v1 - v0) / circ) * UV_PER_M
    u0 = rng.uniform(0, 1)
    vo = rng.uniform(0, max(0.0, (v1 - v0) - circ * vs / UV_PER_M))
    for k in range(rings):
        for i in range(sides):
            j = (i + 1) % sides
            f = bm.faces.new([loops[k][i], loops[k][j], loops[k + 1][j], loops[k + 1][i]])
            for l in f.loops:
                kk = k if l.vert in loops[k] else k + 1
                ii = loops[kk].index(l.vert)
                if ii == 0 and i == sides - 1:
                    ii = sides
                l[uv].uv = (u0 + kk / rings * L * UV_PER_M, v0 + vo + ii / sides * 2 * math.pi * r * vs)
    _, eu0, ev0, eu1, ev1 = RECTS[end_rect]
    for ring, flip in ((loops[0], True), (loops[-1], False)):
        f = bm.faces.new(ring if not flip else list(reversed(ring)))
        c = sum((v.co for v in ring), Vector()) / len(ring)
        for l in f.loops:
            d = l.vert.co - c
            l[uv].uv = (eu0 + (eu1 - eu0) * (d.y / (2.2 * r) + 0.5), ev0 + (ev1 - ev0) * (d.z / (2.2 * r) + 0.5))
    transform(bm, frame_from(p0, p1))
    return bm


def stone(center, size, seed, band="rock_cobble", detail=2, rough=0.22, flat_bottom=True):
    """A rounded rubble stone (icosphere, squashed and dented)."""
    rng = random.Random(seed)
    bm = new_bm()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=0.5)
    for v in bm.verts:
        n = v.co.normalized()
        d = 1.0 + rough * noise.noise(n * 1.7 + Vector((seed * 1.3, seed * 0.7, 0)))
        v.co = n * 0.5 * d
        if flat_bottom and v.co.z < -0.28:
            v.co.z = -0.28 - (v.co.z + 0.28) * 0.15
    transform(bm, Matrix.Diagonal((size[0], size[1], size[2], 1)))
    bm.normal_update()
    _, v0, v1 = _band(band)
    ext = max(size) * UV_PER_M * 0.8
    vo = rng.uniform(0.0, max(0.0, (v1 - v0) - ext))
    uv_box_band(bm, list(bm.faces), band, scale=UV_PER_M * 0.8, v_off=vo, u_off=rng.uniform(0, 1))
    transform(bm, Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z"))
    transform(bm, Matrix.Translation(center))
    return bm


def sweep(points, radius, sides=8, band=None, rect=None, closed=False, twist=0.0, ridges=0, ridge_depth=0.0,
          scale=UV_PER_M, end_caps=True, radius_fn=None, square=False):
    """A tube along a polyline (rope, iron bars, hoops, handles)."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    bm = new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    # Parallel-transport frames.
    tangents = []
    for i in range(n):
        if closed:
            t = (pts[(i + 1) % n] - pts[(i - 1) % n])
        else:
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        tangents.append(t.normalized())
    ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    frames = []
    for i in range(n):
        if i > 0:
            normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized()
        frames.append((normal.copy(), tangents[i].cross(normal).normalized()))
    lengths = [0.0]
    for i in range(1, n):
        lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
    if closed:
        lengths.append(lengths[-1] + (pts[0] - pts[-1]).length)
    rings = []
    for i in range(n):
        nn, bb = frames[i]
        r = radius * (radius_fn(i / max(n - 1, 1)) if radius_fn else 1.0)
        ring = []
        for k in range(sides):
            th = 2 * math.pi * k / sides + (math.pi / sides if square else 0.0)
            # Twisted strands: ridges that wind along the length.
            rr = r * (1.0 + ridge_depth * math.cos(ridges * (th - twist * lengths[i]))) if ridges else r
            ring.append(bm.verts.new(pts[i] + (nn * math.cos(th) + bb * math.sin(th)) * rr))
        rings.append(ring)
    segs = n if closed else n - 1
    circ = 2 * math.pi * radius
    for i in range(segs):
        i2 = (i + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new([rings[i][k], rings[i][k2], rings[i2][k2], rings[i2][k]])
            for l in f.loops:
                ii = i if l.vert in rings[i] else i + 1
                kk = rings[i].index(l.vert) if l.vert in rings[i] else rings[i2].index(l.vert)
                if kk == 0 and k == sides - 1:
                    kk = sides
                s = lengths[ii] if ii < len(lengths) else lengths[-1]
                if band:
                    _, v0, v1 = _band(band)
                    vs = min(scale, (v1 - v0) / max(circ, 1e-4))
                    l[uv].uv = (s * scale, v0 + kk / sides * circ * vs)
                else:
                    _, u0, v0, u1, v1 = RECTS[rect]
                    # Long iron strips run along v on the metal sheet.
                    l[uv].uv = (u0 + (u1 - u0) * kk / sides, v0 + (v1 - v0) * min(s / max(lengths[-1], 1e-4), 1.0))
    if end_caps and not closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(list(reversed(ring)) if flip else ring)
            c = sum((v.co for v in ring), Vector()) / len(ring)
            for l in f.loops:
                d = (l.vert.co - c) / max(radius, 1e-4)
                if band:
                    _, v0, v1 = _band(band)
                    l[uv].uv = (0.5 + d.x * 0.02, (v0 + v1) * 0.5 + d.y * 0.02)
                else:
                    _, u0, v0, u1, v1 = RECTS[rect]
                    l[uv].uv = ((u0 + u1) * 0.5 + d.x * 0.01, v0 + 0.02 + d.y * 0.01)
    bm.normal_update()
    return bm


def arc_points(center, radius, a0, a1, count, axis="Y", z_fn=None):
    """Points on an arc in the plane normal to `axis` (for hoops, handles)."""
    pts = []
    for i in range(count):
        a = a0 + (a1 - a0) * i / (count - 1)
        if axis == "Z":
            p = Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
        elif axis == "Y":
            p = Vector((math.cos(a) * radius, 0, math.sin(a) * radius))
        else:
            p = Vector((0, math.cos(a) * radius, math.sin(a) * radius))
        if z_fn:
            p.z += z_fn(i / (count - 1))
        pts.append(Vector(center) + p)
    return pts


def helix(center, radius, z0, z1, turns, count_per_turn=16, axis="Z"):
    pts = []
    n = int(turns * count_per_turn) + 1
    for i in range(n):
        t = i / (n - 1)
        a = turns * 2 * math.pi * t
        h = z0 + (z1 - z0) * t
        if axis == "Z":
            pts.append(Vector(center) + Vector((math.cos(a) * radius, math.sin(a) * radius, h)))
        else:  # along X
            pts.append(Vector(center) + Vector((h, math.cos(a) * radius, math.sin(a) * radius)))
    return pts


def tile_slab(p_eave_left, p_eave_right, p_ridge_left, thickness=0.06, scale=UV_PER_M * 1.15, mat="MI_RoundTiles"):
    """A roof plane: a thick quad slab with tiles running down the slope."""
    a, b, c = Vector(p_eave_left), Vector(p_eave_right), Vector(p_ridge_left)
    d = b + (c - a)
    bm = new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    nrm = (b - a).cross(c - a).normalized()
    top = [bm.verts.new(p) for p in (a, b, d, c)]
    bot = [bm.verts.new(p - nrm * thickness) for p in (a, b, d, c)]
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bot)))]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new([top[j], top[i], bot[i], bot[j]]))
    along = (b - a).normalized()
    slope = (c - a).normalized()
    for f in bm.faces:
        for l in f.loops:
            q = l.vert.co - a
            l[uv].uv = (q.dot(along) * scale, q.dot(slope) * scale)
    bm.normal_update()
    return bm


def cloth(width, height, cols, rows, shape, wave, seed=0, region=(0.0, 0.0, 1.0, 1.0)):
    """A hanging cloth grid in the XZ plane, top edge at z=0, hanging down.
    `shape(u)` gives how far down column u reaches (0..1, for points and
    swallowtails); `wave(u, v)` gives the y offset (folds)."""
    bm = new_bm()
    uv = bm.loops.layers.uv["UVMap"]
    grid = []
    for j in range(rows + 1):
        v = j / rows
        row = []
        for i in range(cols + 1):
            u = i / cols
            depth = shape(u) * v
            x = (u - 0.5) * width
            z = -depth * height
            y = wave(u, depth)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    u0, v0, u1, v1 = region
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
            for l in f.loops:
                p = l.vert.co
                uu = p.x / width + 0.5
                vv = -p.z / height
                l[uv].uv = (u0 + (u1 - u0) * uu, v1 - (v1 - v0) * vv)
    bm.normal_update()
    return bm


def merge_bm(dst, src):
    """Appends src's geometry (with UVs) into dst."""
    me = bpy.data.meshes.new("_tmp")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)
    return dst


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)
