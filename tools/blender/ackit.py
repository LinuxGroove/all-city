"""Helpers the All City model scripts share: chunky bevelled primitives
coloured by palette swatch, joined into one object and written as GLB.

Blender is z up and the game is y up; the glTF exporter turns Blender's -y
into the game's +z. So every model here faces -y (towards Blender's front
view), stands on z = 0, and is centred on x unless its doc says otherwise.

Materials are roles, named so the game's import script can swap in its own
shaders: "Palette" (flat swatches), "Wall" (a swatch the game tints per
building or per car), "Glass" (dark glass the game may light per window)
and "Glow" (lamps, neon and signals, drawn bright at night). Every face's UV
sits in the middle of its swatch, so a model reads the same anywhere.
"""
import math
import os
import sys

import bpy  # noqa: I001 (bpy first: it makes bmesh and mathutils importable)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import palette  # noqa: E402

PALETTE_PNG = os.path.join(ROOT, "assets", "art", "palette.png")
ROLES = ("Palette", "Wall", "Glass", "Glow")
SHARP = math.radians(32.0)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(role: str) -> bpy.types.Material:
    if role in bpy.data.materials:
        return bpy.data.materials[role]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = bpy.data.images.get("palette.png") or bpy.data.images.load(PALETTE_PNG)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85 if role != "Glass" else 0.15
    if role == "Glow":
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return m


def _new_object(name, bm, colour, role):
    uv = bm.loops.layers.uv.verify()
    u = palette.uv(colour)
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            loop[uv].uv = u
    for e in bm.edges:
        if e.is_manifold and e.calc_face_angle(0.0) > SHARP:
            e.smooth = False
        elif not e.is_manifold:
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(role))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _place(bm, at, rot):
    m = Matrix.Translation(Vector(at))
    if rot:
        m = m @ (Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X"))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


def _bevel(bm, amount, segments=1, edges=None):
    if amount <= 0:
        return
    bmesh.ops.bevel(bm, geom=list(edges if edges is not None else bm.edges), offset=amount, segments=segments,
                    affect="EDGES", profile=0.5, clamp_overlap=True)


def box(size, at=(0, 0, 0), colour="concrete", role="Palette", bevel=0.0, segments=1, rot=None, base=True):
    """A box `size` (x, y, z). `at` is the middle of its bottom face, or its
    centre with base=False."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if base:
        bmesh.ops.translate(bm, vec=Vector((0, 0, size[2] / 2)), verts=bm.verts)
    _bevel(bm, min(bevel, min(size) * 0.45), segments)
    _place(bm, at, rot)
    return _new_object("box", bm, colour, role)


def cyl(radius, height, at=(0, 0, 0), colour="steel", role="Palette", sides=16, bevel=0.0, top=None, rot=None,
        segments=1):
    """An upright cylinder (or a cone frustum with `top`) standing on `at`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
                          radius2=radius if top is None else top, depth=height)
    bmesh.ops.translate(bm, vec=Vector((0, 0, height / 2)), verts=bm.verts)
    if bevel > 0:
        rim = [e for e in bm.edges if len(e.link_faces) == 2 and
               abs(e.link_faces[0].normal.z) + abs(e.link_faces[1].normal.z) > 0.9 and
               abs(e.link_faces[0].normal.z - e.link_faces[1].normal.z) > 0.5]
        _bevel(bm, bevel, segments, rim)
    _place(bm, at, rot)
    return _new_object("cyl", bm, colour, role)


def ball(radius, at=(0, 0, 0), colour="leaf", role="Palette", subdiv=2, squash=1.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    bmesh.ops.scale(bm, vec=Vector((1, 1, squash)), verts=bm.verts)
    _place(bm, at, None)
    ob = _new_object("ball", bm, colour, role)
    return ob


def blob(radii, at=(0, 0, 0), colour="leaf", role="Palette", subdiv=2, lumps=0.12, seed=0, turn=0.0):
    """A lumpy ellipsoid with radii (x, y, z): tree crowns, rough stone,
    muscle. `lumps` pushes each vertex in or out by up to that fraction of
    its radius, from a fixed seed, so a model builds the same every time.
    `turn` spins it about z first, so faceted ones don't all line up."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in bm.verts:
        n = v.co.normalized()
        # Smooth noise: a few fixed waves round the sphere.
        k = (math.sin(n.x * 3.1 + seed * 1.7) * math.cos(n.y * 2.7 - seed * 0.9) +
             math.sin(n.z * 3.7 + n.x * 1.3 + seed * 2.3)) * 0.5
        v.co = n * (1.0 + lumps * k)
    if turn:
        bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(turn, 3, "Z"), verts=bm.verts)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    _place(bm, at, None)
    return _new_object("blob", bm, colour, role)


def strut(a, b, radius, top=None, colour="steel", role="Palette", sides=8):
    """A cylinder (or a taper to `top`) from point a to point b: legs,
    braces, branches."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
                          radius2=radius if top is None else top, depth=d.length)
    bmesh.ops.translate(bm, vec=Vector((0, 0, d.length / 2)), verts=bm.verts)
    m = Matrix.Translation(a) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _new_object("strut", bm, colour, role)


def tube(points, radius, colour="steel", role="Palette", sides=10, caps=True):
    """A round tube along a polyline of (x, y, z) points (rails, pipes,
    arms), with mitred joints."""
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            d = (pts[1] - p).normalized()
        elif i == len(pts) - 1:
            d = (p - pts[i - 1]).normalized()
        else:
            d = ((p - pts[i - 1]).normalized() + (pts[i + 1] - p).normalized()).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        a = d.cross(up).normalized()
        b = d.cross(a).normalized()
        scale = 1.0
        if 0 < i < len(pts) - 1:
            cosang = max((p - pts[i - 1]).normalized().dot(d), 0.3)
            scale = 1.0 / cosang
        ring = []
        for k in range(sides):
            t = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * radius * scale))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_object("tube", bm, colour, role)


def prism(outline, height, at=(0, 0, 0), colour="concrete", role="Palette", bevel=0.0, rot=None):
    """A 2D outline [(x, y), ...] (counter-clockwise from above) extruded
    up by `height`."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in outline]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, height)), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel(bm, bevel)
    _place(bm, at, rot)
    return _new_object("prism", bm, colour, role)


def plate(outline, thickness, at=(0, 0, 0), colour="steel", role="Palette"):
    """A flat cut-out: an outline [(x, z), ...] in the x-z plane (a side
    view, as seen from the front) given `thickness` along y, centred on
    y = 0. Signs, silhouettes, panels."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -thickness / 2, z)) for x, z in outline]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    back = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, thickness, 0)), verts=back)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, at, None)
    return _new_object("plate", bm, colour, role)


def profile(points, length, at=(0, 0, 0), colour="stone", role="Palette", bevel=0.0):
    """A moulding: a profile [(y, z), ...] in the y-z plane (counter-
    clockwise seen from +x) swept along x for `length`, centred on x."""
    bm = bmesh.new()
    vs = [bm.verts.new((-length / 2, y, z)) for y, z in points]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((length, 0, 0)), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel(bm, bevel)
    _place(bm, at, None)
    return _new_object("profile", bm, colour, role)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    # Merge the duplicate material slots join leaves behind. Clearing the
    # slots resets the faces' indices, so they're read first and written
    # back after.
    slots = {}
    me = ob.data
    remap = []
    for i, m in enumerate(me.materials):
        if m.name not in slots:
            slots[m.name] = len(slots)
        remap.append(slots[m.name])
    index = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", index)
    index = [remap[i] for i in index]
    names = list(slots.keys())
    me.materials.clear()
    for n in names:
        me.materials.append(bpy.data.materials[n])
    me.polygons.foreach_set("material_index", index)
    me.update()
    return ob


def mirror_x(objs):
    """Copies of objects mirrored across x = 0."""
    out = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        c.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
        c.data.flip_normals()
        out.append(c)
    return out


def fit_height(ob, height):
    """Scales a joined model about its foot so its top is exactly `height`
    above z = 0 (the game scales by measured height / model height)."""
    top = max(v.co.z for v in ob.data.vertices)
    ob.data.transform(Matrix.Scale(height / top, 4))
    return ob


def dims(ob):
    """(width x, depth y, height z) of a model's bounds."""
    vs = [v.co for v in ob.data.vertices]
    return tuple(max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3))


def export(ob, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_texcoords=True,
                              export_normals=True, export_tangents=False, export_vertex_color="NONE",
                              export_animations=False, export_extras=False, export_cameras=False,
                              export_lights=False)
    ob.select_set(False)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
