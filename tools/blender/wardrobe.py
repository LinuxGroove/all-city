"""Builds the writers' wardrobe: real clothes fitted over the Universal Base Characters.

Run with Blender's Python module, SciPy and scikit-image (pip install bpy scipy scikit-image into
a venv, Python 3.13):
    python tools/blender/wardrobe.py assets/people assets/people/outfits [outfit ...] [male|female]
WARDROBE_PARTS=1 keeps the pieces that are normally one mesh apart, to look at each one.

Writes <outfit>_<body>.gltf and .bin into the output folder for each outfit and body: the base
body's own skeleton (unchanged, so the Universal Animation Libraries drive it), its head and hands
(the skin under the clothes is cut away so it can't show through), its eyes and brows, and the
clothes as separate meshes named for what they are, each skinned to the same bones. The game
colours each by its name (Person.WARDROBE).

How the clothes are made: the body becomes a distance field on a grid, and a "closing" of it (the
body with every hollow narrower than the cloth's stiffness filled in) is the surface cloth lies on,
over the chest rather than into every muscle. Shells start as copies of the body's own faces, are
pushed onto that surface plus some ease, hang straight down the arms and legs, and are smoothed.
Everything else is built on top of those: bands, pockets, the hood. On the female body, smoothed
hulls of the bust and the seat join the field first, so cloth bridges the cleavage, the underbust
and the cleft between the buttocks rather than following them. Every point takes its skin weights
from the nearest point of the body.

The method is Silver Tongue's wardrobe.py (its halberd_suit and evening_dress), trimmed to what
this game wears.

Outfits so far:
- streetwear (male and female): a writer's baggy hoodie (hood down, drawstrings, a pouch pocket,
  ribbed cuffs and hem), wide skate trousers with cargo pockets that hang straight and stack over
  chunky skate shoes (cupsoles and laces), and a backpack with straps over the shoulders and two
  loops across its back that the skateboard slots into for climbing.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from scipy import ndimage, sparse
from scipy.interpolate import CubicSpline

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
PEOPLE, OUT = ARGS[0], ARGS[1]
WANT = set(ARGS[2:])
BODIES = {"male": "Superhero_Male_FullBody.gltf", "female": "Superhero_Female_FullBody.gltf"}
UP = np.array([0.0, 0.0, 1.0])
FWD = np.array([0.0, -1.0, 0.0])  # the bodies face -Y in Blender
SOLE = 0.016  # the shoes' soles reach this far below the bare foot (Person.SOLE lifts the body by it)



# --- The body ----------------------------------------------------------------------------------

class Body:
    """The base body: skeleton, skin mesh, weights and a few measurements, in its rest space
    (Blender: Z up, facing -Y, a T-pose)."""

    def __init__(self, kind):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=os.path.join(PEOPLE, BODIES[kind]), merge_vertices=True)
        self.kind = kind
        self.arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
        meshes = [o for o in bpy.data.objects if o.type == 'MESH']
        self.obj = max(meshes, key=lambda o: len(o.data.vertices))
        self.extras = [o for o in meshes if o is not self.obj and o.parent == self.arm]
        for o in meshes:
            if o is not self.obj and o not in self.extras:
                bpy.data.objects.remove(o)
        me = self.obj.data
        self.co = np.array([v.co[:] for v in me.vertices])
        self.groups = [g.name for g in self.obj.vertex_groups]
        W = np.zeros((len(me.vertices), len(self.groups)), np.float32)
        for v in me.vertices:
            for g in v.groups:
                W[v.index, g.group] = g.weight
        self.W = W
        me.calc_loop_triangles()
        self.tris = np.array([t.vertices[:] for t in me.loop_triangles])
        self.bvh = BVHTree.FromPolygons([Vector(c) for c in self.co], self.tris.tolist())

        def total(*prefixes):
            cols = [i for i, n in enumerate(self.groups) if n.startswith(prefixes)]
            return W[:, cols].sum(1)
        self.w_head = total("Head", "neck_01")
        self.w_hand = total("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")
        self.w_foot = total("foot_", "ball_")
        self.w_leg = total("thigh_", "calf_")
        self.w_pelvis = total("pelvis")

        def bone(n):
            return np.array(self.arm.matrix_world @ self.arm.data.bones[n].head_local)
        self.bone = bone
        self.hand = bone("hand_l")
        self.shoulder = bone("upperarm_l")
        self.hip = bone("thigh_l")
        self.ankle = bone("foot_l")
        self.pelvis_z = bone("pelvis")[2]
        self.neck_z = bone("neck_01")[2]
        self.floor = self.co[:, 2].min()
        self.top = self.co[:, 2].max()

    def triangles(self, vert_mask=None):
        """The body's triangles as corner positions, optionally only those touching vert_mask."""
        t = self.tris
        if vert_mask is not None:
            t = t[vert_mask[t].any(1)]
        return self.co[t]

    def weights(self, P, top=4):
        """Skin weights for points near the body: those of the nearest point on it."""
        out = np.zeros((len(P), len(self.groups)), np.float32)
        for i, p in enumerate(P):
            loc, _n, ti, _d = self.bvh.find_nearest(Vector(p))
            a, b, c = self.co[self.tris[ti]]
            out[i] = barycentric(np.array(loc), a, b, c) @ self.W[self.tris[ti]]
        return normalize_weights(out, top)

    def group(self, name):
        return self.groups.index(name)


def barycentric(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
    d20, d21 = v2 @ v0, v2 @ v1
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        return np.array([1.0, 0.0, 0.0])
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    bc = np.clip(np.array([1.0 - v - w, v, w]), 0.0, 1.0)
    return bc / bc.sum()


def normalize_weights(W, top=4):
    W = W.copy()
    if W.shape[1] > top:
        drop = np.argsort(-W, axis=1)[:, top:]
        np.put_along_axis(W, drop, 0.0, axis=1)
    return W / np.maximum(W.sum(1, keepdims=True), 1e-6)


# --- The cloth surface -------------------------------------------------------------------------

def hull_filler(P, rounds=3):
    """Triangles of the convex hull of some points, its ridges rounded off (by smoothing, which
    sinks it a little where it was sharp). Added to a body's field, cloth lies over the hull
    instead of following the body into a hollow; inside the body it's harmless, since cloth
    only meets the outside of the field."""
    from scipy.spatial import ConvexHull
    bm = bmesh.new()
    vs = new_verts(bm, P)
    for t in ConvexHull(P).simplices:
        try:
            bm.faces.new([vs[i] for i in t])
        except ValueError:
            pass
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    for _ in range(rounds):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        smooth(bm, 6, lam=0.6, mu=-0.6)
    bm.verts.ensure_lookup_table()
    P = coords(bm)
    return P[np.array([[v.index for v in f.verts] for f in bm.faces])]


def bust_filler(body, z0=1.17, z1=1.43, x1=0.15):
    """The front of the female body's chest filled over the cleavage and under the bust: cloth
    falls from the bust rather than into them."""
    c = body.co
    arm = sum(body.W[:, body.group(n)] for n in ("upperarm_l", "upperarm_r", "clavicle_l", "clavicle_r"))
    m = (c[:, 2] > z0) & (c[:, 2] < z1) & (c[:, 1] < 0.0) & (np.abs(c[:, 0]) < x1) & (arm < 0.3)
    return hull_filler(c[m])


def seat_filler(body, z0=0.74, z1=1.02, x1=0.2):
    """The back of the female body's hips filled over the cleft of the seat: a jacket hangs
    straight across it."""
    c = body.co
    near = (np.abs(c[:, 2] - body.pelvis_z) < 0.02) & (np.abs(c[:, 0]) < 0.05)
    cy = 0.5 * (c[near][:, 1].min() + c[near][:, 1].max())
    m = (c[:, 2] > z0) & (c[:, 2] < z1) & (c[:, 1] > cy) & (np.abs(c[:, 0]) < x1)
    return hull_filler(c[m])


def surface_points(tris, step, seed=7):
    """Points over triangles, about one per step squared, plus the corners."""
    rng = np.random.default_rng(seed)
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    n = np.ceil(area / (step * step) * 2.0).astype(int) + 2
    rep = np.repeat(np.arange(len(tris)), n)
    r1 = np.sqrt(rng.random(len(rep)))
    r2 = rng.random(len(rep))
    P = (1 - r1)[:, None] * a[rep] + (r1 * (1 - r2))[:, None] * b[rep] + (r1 * r2)[:, None] * c[rep]
    return np.concatenate([P, tris.reshape(-1, 3)])


class Field:
    """Distances round some of the body on a grid. D is the distance to its surface; for a cloth
    stiffness R, E is the distance to everywhere a ball of radius R can reach from outside, so
    E = R - ease is cloth lying over the body with that ease, bridging hollows narrower than R."""

    def __init__(self, tris, h=0.006, pad=0.12, box=None):
        """box (lo, hi) limits the grid to part of the triangles: cut through a closed body, its
        inside stays apart from the outside."""
        pts = tris.reshape(-1, 3)
        lo, hi = pts.min(0) - pad, pts.max(0) + pad
        if box is not None:
            lo, hi = np.maximum(lo, box[0]), np.minimum(hi, box[1])
        self.lo = lo
        self.h = h
        shape = tuple(np.ceil((hi - self.lo) / h).astype(int) + 1)
        idx = np.round((surface_points(tris, h * 0.45) - self.lo) / h).astype(int)
        if box is not None:
            idx = idx[np.all((idx >= 0) & (idx < np.array(shape)), axis=1)]
        surf = np.zeros(shape, bool)
        surf[tuple(idx.T)] = True
        self.D = (ndimage.distance_transform_edt(~surf) * h).astype(np.float32)
        self.closings = {}

    def closing(self, R):
        if R not in self.closings:
            lab, _ = ndimage.label(self.D > R)
            outside = lab == lab[0, 0, 0]
            E = (ndimage.distance_transform_edt(~outside) * self.h).astype(np.float32)
            self.closings[R] = (E, np.gradient(E, self.h))
        return self.closings[R]

    def at(self, A, P):
        return ndimage.map_coordinates(A, ((np.asarray(P, float) - self.lo) / self.h).T, order=1, mode='nearest')

    def onto(self, P, R, ease, iters=12, outward_only=False):
        """Moves points onto the cloth surface (or only out to it)."""
        E, G = self.closing(R)
        P = np.array(P, float)
        for _ in range(iters):
            e = self.at(E, P) - (R - ease)
            if outward_only:
                e = np.maximum(e, 0.0)
            g = np.stack([self.at(Gi, P) for Gi in G], 1)
            g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-6)
            P -= np.clip(e, -0.02, 0.02)[:, None] * g
        return P

    def reach(self, centers, dirs, R, ease, far=0.5, step=0.0015, miss=None):
        """How far out from each center, along its direction, the cloth surface is: walks in from far.
        A ray that never meets it (from a gap between the legs) gives miss, when one is given."""
        centers = np.asarray(centers, float)
        dirs = np.asarray(dirs, float)
        E, _ = self.closing(R)
        s = np.arange(far, 0.0, -step)
        P = centers[:, None, :] + dirs[:, None, :] * s[None, :, None]
        e = self.at(E, P.reshape(-1, 3)).reshape(len(centers), len(s)) - (R - ease)
        inside = e >= 0.0
        first = np.where(inside.any(1), inside.argmax(1), len(s) - 1)
        r = s[first]
        prev = np.clip(first - 1, 0, None)
        rows = np.arange(len(centers))
        e0, e1 = e[rows, prev], e[rows, first]
        t = np.where(first > 0, -e0 / np.where(np.abs(e1 - e0) > 1e-9, e1 - e0, 1.0), 0.0)
        if miss is not None:
            return np.where(inside.any(1), s[prev] - np.clip(t, 0.0, 1.0) * step, miss)
        return s[prev] - t * step

    def push_out(self, P, gap):
        """Moves points out until they're at least gap from the body's surface."""
        g = np.gradient(self.D, self.h) if not hasattr(self, "_gD") else self._gD
        self._gD = g
        P = np.array(P, float)
        for _ in range(10):
            d = self.at(self.D, P)
            need = np.maximum(gap - d, 0.0)
            if need.max() < 1e-4:
                break
            n = np.stack([self.at(gi, P) for gi in g], 1)
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
            P += need[:, None] * n
        return P


# --- Mesh helpers ------------------------------------------------------------------------------

def coords(bm):
    bm.verts.ensure_lookup_table()
    return np.array([v.co[:] for v in bm.verts])


def set_coords(bm, P):
    bm.verts.ensure_lookup_table()
    for v, p in zip(bm.verts, P):
        v.co = Vector(p)


def body_piece(body, keep):
    """A bmesh of the body faces whose corners are all in keep."""
    bm = bmesh.new()
    bm.from_mesh(body.obj.data)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if not all(keep[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    return bm


def cut(bm, co, no, faces=None):
    """Cuts away everything on the side of the plane its normal points to."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=Vector(co), plane_no=Vector(no), clear_outer=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def cut_level(bm, g):
    """Cuts away everything where g(point) > 0, along the curve where it crosses 0 (a plane cut,
    bent). Returns the new edge's points near which g was 0."""
    val = {v: g(np.array(v.co[:])) for v in bm.verts}
    new = set()
    for e in [e for e in bm.edges if (val[e.verts[0]] > 0) != (val[e.verts[1]] > 0)]:
        a, b = e.verts
        t = val[a] / (val[a] - val[b])
        pa, pb = a.co.copy(), b.co.copy()
        _e, nv = bmesh.utils.edge_split(e, a, t)
        nv.co = pa.lerp(pb, t)
        val[nv] = 0.0
        new.add(nv)
    for f in list(bm.faces):
        vs = [v for v in f.verts if v in new]
        if len(vs) == 2:
            bmesh.ops.connect_verts(bm, verts=vs)
    kill = [f for f in bm.faces if max(val[v] for v in f.verts) > 0]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    return [v for v in new if v.is_valid]


def subdivide(bm, times=1):
    for _ in range(times):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)


def smooth(bm, iters=6, lam=0.5, mu=-0.53, pin=None):
    """Taubin smoothing: rounds off lumps without shrinking. Boundary points slide along the boundary."""
    bm.verts.ensure_lookup_table()
    n = len(bm.verts)
    rows, cols = [], []
    for v in bm.verts:
        edges = [e for e in v.link_edges if e.is_boundary] if v.is_boundary else v.link_edges
        for e in edges:
            rows.append(v.index)
            cols.append(e.other_vert(v).index)
    A = sparse.csr_matrix((np.ones(len(rows)), (rows, cols)), shape=(n, n))
    deg = np.asarray(A.sum(1)).ravel()
    L = sparse.diags(1.0 / np.maximum(deg, 1)) @ A
    P = coords(bm)
    move = np.ones(n) if pin is None else (~pin).astype(float)
    move[deg == 0] = 0.0
    for _ in range(iters):
        for k in (lam, mu):
            P = P + k * (L @ P - P) * move[:, None]
    set_coords(bm, P)


def settle(bm, F, R, ease, rounds=4, iters=4, fixed=None):
    """Smooths and puts back on the cloth surface a few times, so points spread evenly over it
    instead of bunching (and folding) where the cloth bridges a hollow."""
    for _ in range(rounds):
        smooth(bm, iters, pin=fixed)
        P = coords(bm)
        Q = F.onto(P, R, ease, iters=6)
        if fixed is not None:
            Q[fixed] = P[fixed]
        set_coords(bm, Q)


def drape(P, sel, a, b, taper, t0=0.0, bins=32, dt=0.015):
    """Lets cloth hang straight along a limb from a to b: going down the limb, the cloth's radius at
    each angle shrinks by at most taper per meter, so it falls past the calf or forearm rather than
    following it in."""
    a = np.asarray(a, float)
    d = np.asarray(b, float) - a
    d /= np.linalg.norm(d)
    u = np.cross(d, [0.0, 1.0, 0.0])
    if np.linalg.norm(u) < 0.1:
        u = np.cross(d, [1.0, 0.0, 0.0])
    u /= np.linalg.norm(u)
    v = np.cross(d, u)
    Q = P[sel] - a
    t = Q @ d
    Rv = Q - t[:, None] * d
    r = np.linalg.norm(Rv, axis=1)
    th = np.arctan2(Rv @ v, Rv @ u)
    ib = np.floor((th + np.pi) / (2 * np.pi) * bins).astype(int) % bins
    it = np.clip(np.floor(t / dt).astype(int), 0, None)
    nt = it.max() + 1
    rmax = np.full((bins, nt), -1.0)
    np.maximum.at(rmax, (ib, it), r)
    rmax = np.maximum(rmax, np.maximum(np.roll(rmax, 1, 0), np.roll(rmax, -1, 0)) - 0.004)
    prof = rmax.copy()
    for j in range(max(int(t0 / dt), 0) + 1, nt):
        prof[:, j] = np.maximum(prof[:, j], prof[:, j - 1] - taper * dt)
    target = prof[ib, it]
    ramp = np.clip((t - t0) / 0.05, 0.0, 1.0)
    r_new = r + np.maximum(target - r, 0.0) * ramp
    P = P.copy()
    P[sel] = a + t[:, None] * d + Rv / np.maximum(r, 1e-6)[:, None] * r_new[:, None]
    return P


def grid_faces(bm, rows, closed=False, flip=False):
    """Faces between rows of vertices (lists of equal length)."""
    out = []
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        n = len(a)
        for j in range(n if closed else n - 1):
            k = (j + 1) % n
            q = [a[j], a[k], b[k], b[j]]
            if flip:
                q.reverse()
            if len({id(x) for x in q}) == 4:
                out.append(bm.faces.new(q))
    return out


def new_verts(bm, P):
    return [bm.verts.new(Vector(p)) for p in P]


def solidify(bm, thickness, flip=False, even=True):
    """Gives an open sheet some thickness, inwards, with closed edges. Even thickness blows up
    at a sharp fold, so folded sheets turn it off."""
    me = bpy.data.meshes.new("tmp")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("tmp", me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("solid", 'SOLIDIFY')
    m.thickness = thickness
    m.offset = -1.0 if not flip else 1.0
    m.use_even_offset = even
    m.use_rim = True
    dg = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    out = bmesh.new()
    out.from_mesh(me2)
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    bpy.data.meshes.remove(me2)
    return out


def recalc(bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def bvh_of(bm):
    bm.verts.ensure_lookup_table()
    return BVHTree.FromBMesh(bm)


def hit(bvh, origin, direction):
    loc, nrm, _i, _d = bvh.ray_cast(Vector(origin), Vector(direction))
    if loc is None:
        return None, None
    return np.array(loc), np.array(nrm)


def disc(bm, center, normal, radius, depth, segments=12, spin=0.0):
    """A little flat cylinder standing on a surface (buttons, the pin)."""
    n = Vector(normal).normalized()
    rot = n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m = Matrix.Translation(Vector(center) + n * depth * 0.5) @ rot @ Matrix.Rotation(spin, 4, 'Z')
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius * 0.92, depth=depth, matrix=m)


def tube(bm, points, radius, segments=8):
    """A tube along a polyline (the earpiece's cable)."""
    pts = [np.asarray(p, float) for p in points]
    rings = []
    prev_u = None
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        u = np.cross(t, [0.0, 0.0, 1.0]) if prev_u is None else prev_u - (prev_u @ t) * t
        if np.linalg.norm(u) < 1e-3:
            u = np.cross(t, [1.0, 0.0, 0.0])
        u /= np.linalg.norm(u)
        prev_u = u
        v = np.cross(t, u)
        ring = [p + radius * (math.cos(a) * u + math.sin(a) * v) for a in np.linspace(0, 2 * np.pi, segments, endpoint=False)]
        rings.append(new_verts(bm, ring))
    grid_faces(bm, rings, closed=True)
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])


def neck_round(body, cy, z, phis, out, rmax=0.125, bins=36):
    """Points round the neck at a height: at each angle, the outermost skin within rmax of the
    neck's middle (the neck, or the top of the chest and back where it meets them), then out more."""
    c = body.co
    dx, dy = c[:, 0], c[:, 1] - cy
    r = np.hypot(dx, dy)
    m = (np.abs(c[:, 2] - z) < 0.009) & (r < rmax)
    th = np.arctan2(dx[m], -dy[m]) % (2 * np.pi)
    ib = (th / (2 * np.pi) * bins).astype(int) % bins
    prof = np.full(bins, np.nan)
    for i in range(bins):
        if (ib == i).any():
            prof[i] = r[m][ib == i].max()
    good = ~np.isnan(prof)
    idx = np.arange(bins)
    prof = np.interp(idx, idx[good], prof[good], period=bins)
    prof = (np.roll(prof, 1) + 2 * prof + np.roll(prof, -1)) / 4
    centers = (idx + 0.5) / bins * 2 * np.pi
    rr = np.interp(np.asarray(phis) % (2 * np.pi), centers, prof, period=2 * np.pi) + out
    return np.stack([np.sin(phis) * rr, cy - np.cos(phis) * rr, np.full(len(phis), z)], 1)



def keep_skin(body, keep):
    """Cuts away the body's faces with no corner in keep."""
    bm = bmesh.new()
    bm.from_mesh(body.obj.data)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if not any(keep[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(body.obj.data)
    body.obj.name = "Body"


def add_part(body, name, bms, weights_fn=None, smooth_shade=True, smooth_weights=0):
    """One mesh from some bmeshes, skinned like the body under it. smooth_weights blurs the
    weights over the mesh that many times first, so cloth bridging a hollow (where the nearest
    skin jumps from one side to the other) doesn't tear as the body moves."""
    bm = bmesh.new()
    for b in bms:
        tmp = bpy.data.meshes.new("tmp")
        b.to_mesh(tmp)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bm.verts.ensure_lookup_table()
    for layer in list(bm.verts.layers.deform):
        bm.verts.layers.deform.remove(layer)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for g in body.groups:
        ob.vertex_groups.new(name=g)
    P = np.array([v.co[:] for v in me.vertices])
    W = body.weights(P)
    if smooth_weights:
        E = np.array([e.vertices[:] for e in me.edges])
        n = len(P)
        A = sparse.coo_matrix((np.ones(2 * len(E)), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
        deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)[:, None]
        for _ in range(smooth_weights):
            W = 0.5 * W + 0.5 * (A @ W) / deg
        W = normalize_weights(W.astype(np.float32))
    if weights_fn:
        W = weights_fn(P, W)
    for gi in range(W.shape[1]):
        idx = np.nonzero(W[:, gi] > 1e-4)[0]
        vg = ob.vertex_groups[gi]
        for i in idx:
            vg.add([int(i)], float(W[i, gi]), 'REPLACE')
    if smooth_shade:
        for poly in me.polygons:
            poly.use_smooth = True
        if hasattr(me, "set_sharp_from_angle"):
            me.set_sharp_from_angle(angle=math.radians(75))
    ob.parent = body.arm
    m = ob.modifiers.new("Armature", 'ARMATURE')
    m.object = body.arm
    return ob


def export(body, path):
    bpy.ops.object.select_all(action='DESELECT')
    body.arm.select_set(True)
    for o in bpy.data.objects:
        if o.parent == body.arm:
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLTF_SEPARATE', use_selection=True,
                              export_animations=False, export_materials='NONE', export_skins=True,
                              export_morph=False, export_extras=False, export_vertex_color='NONE')



# --- The streetwear ----------------------------------------------------------------------------

def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Neckline:
    """A line round the base of the neck by angle (0 at the front, 180 at the back), a height
    over each point of it, as offsets from the neck bone."""

    def __init__(self, body, dz):
        c = body.co
        near = (np.abs(c[:, 2] - body.neck_z) < 0.02) & (np.abs(c[:, 0]) < 0.09)
        self.y = 0.5 * (c[near][:, 1].min() + c[near][:, 1].max())
        at = np.radians([0, 28, 60, 90, 120, 150, 180])
        self._line = CubicSpline(at, body.neck_z + np.array(dz), bc_type=((1, 0.0), (1, 0.0)))

    def __call__(self, phi):
        a = np.abs((np.asarray(phi) + np.pi) % (2 * np.pi) - np.pi)
        return self._line(a)

    def angle(self, p):
        return math.atan2(p[0], -(p[1] - self.y))


class Street:
    """The streetwear's measurements, from the body's bones."""

    def __init__(self, body):
        b = body
        self.female = b.kind == "female"
        self.sleeve = b.hand[0] - 0.085           # where the hoodie's sleeves end and the cuffs start
        self.cuff_end = b.hand[0] - 0.045
        self.skin_hand = b.hand[0] - 0.075        # the skin is kept beyond this
        self.z_cut = b.pelvis_z + 0.05            # the hoodie's shell ends here, its body hangs below
        self.z_skirt = self.z_cut + 0.035
        self.z_hem = b.pelvis_z - (0.12 if self.female else 0.14)
        self.band_h = 0.075
        self.R_top, self.ease_top = 0.08, 0.032
        self.R_skirt, self.ease_skirt = 0.1, 0.045
        self.skirt_blend = 0.12
        self.R_pants, self.ease_pants = 0.045, 0.034
        self.z_pants = b.pelvis_z + 0.09
        self.z_leg = b.ankle[2] - 0.012           # the trousers' hem at the back of the heel
        self.hem_rise = 0.32                      # and how much higher it is towards the toe, per metre
        self.leg_max = 0.104                      # no leg wider than this round its middle (< half the ankles' 0.228)
        self.z_collar = b.ankle[2] + 0.04         # the shoes' collar
        # The neck opening: wide and low, over the slope of the shoulders.
        if self.female:
            dz = [-0.075, -0.07, -0.05, -0.04, -0.04, -0.045, -0.05]
        else:
            dz = [-0.045, -0.04, -0.03, -0.02, -0.02, -0.025, -0.03]
        self.neck = Neckline(b, dz)

    def collar_cut(self, p):
        """Above zero where the hoodie's shell is cut away round the neck."""
        dx, dy = p[0], p[1] - self.neck.y
        phi = math.atan2(dx, -dy)
        return p[2] - float(self.neck(phi)) - 2.0 * max(0.0, math.hypot(dx, dy) - 0.17)


def arm_axis(body, side):
    """The arm in the T-pose: a point on it and the direction out along it."""
    a = body.shoulder * [side, 1, 1]
    d = body.hand * [side, 1, 1] - a
    return a, d / np.linalg.norm(d)


def hoodie_shell(body, s, F):
    """The hoodie over the chest, back, shoulders and arms (its body below the waist is separate)."""
    c = body.co
    keep = ((c[:, 2] > s.z_cut - 0.08) & (body.w_head < 0.4) & (body.w_hand < 0.6)
            & (np.abs(c[:, 0]) < s.sleeve + 0.08) & (body.w_leg < 0.5))
    bm = body_piece(body, keep)
    cut(bm, (0, 0, s.z_cut), (0, 0, -1))
    cut(bm, (s.sleeve, 0, 0), (1, 0, 0))
    cut(bm, (-s.sleeve, 0, 0), (-1, 0, 0))
    subdivide(bm)
    set_coords(bm, F.onto(coords(bm), s.R_top, s.ease_top))
    settle(bm, F, s.R_top, s.ease_top)
    P = coords(bm)
    for side in (1, -1):
        a, _d = arm_axis(body, side)
        P = drape(P, P[:, 0] * side > abs(a[0]) + 0.02, a, body.hand * [side, 1, 1], taper=0.05, t0=0.06)
    set_coords(bm, P)
    smooth(bm, 24)
    P = F.onto(coords(bm), s.R_top, s.ease_top * 0.8, outward_only=True)
    set_coords(bm, P)
    # Sleeves narrow into their cuffs over the last stretch.
    ay, az = body.hand[1], body.hand[2]
    P = coords(bm)
    for side in (1, -1):
        m = P[:, 0] * side > s.sleeve - 0.1
        rv = P[m][:, 1:] - [ay, az]
        r = np.linalg.norm(rv, axis=1)
        t = smoothstep(s.sleeve - 0.1, s.sleeve - 0.005, P[m][:, 0] * side)
        r_new = r * (1 - t) + np.minimum(r, s.cuff_r + 0.012) * t
        P[m, 1:] = [ay, az] + rv / np.maximum(r, 1e-6)[:, None] * r_new[:, None]
    set_coords(bm, P)
    smooth(bm, 2)
    # The neck opening, cut along the neckline.
    edge = cut_level(bm, s.collar_cut)
    E = np.array([v.co[:] for v in edge])
    phi = np.arctan2(E[:, 0], -(E[:, 1] - s.neck.y)) % (2 * np.pi)
    order = np.argsort(phi)
    s.neck_edge = (phi[order], E[order])
    # The cut lines stay where they were cut.
    for e in bm.edges:
        if e.is_boundary:
            for v in e.verts:
                if abs(v.co.z - s.z_cut) < 0.03 and abs(v.co.x) < 0.3:
                    v.co.z = s.z_cut
                elif abs(abs(v.co.x) - s.sleeve) < 0.03:
                    v.co.x = math.copysign(s.sleeve, v.co.x)
    if s.female:
        bm.verts.ensure_lookup_table()
        waist = np.array([v.is_boundary and abs(v.co.z - s.z_cut) < 1e-4 for v in bm.verts])
        smooth(bm, 8, pin=~waist)
        P = coords(bm)
        P[waist] = F.onto(P[waist], s.R_top, s.ease_top - 0.004)
        P[waist, 2] = s.z_cut
        set_coords(bm, P)
    recalc(bm)
    return bm


def cuff_radius(body, F, s):
    """The snug radius round the wrist, by angle round the arm."""
    ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    dirs = np.stack([np.zeros(24), np.cos(ang), np.sin(ang)], 1)
    cs = np.repeat(np.array([[s.sleeve, body.hand[1], body.hand[2]]]), 24, 0)
    return float(np.mean(F.reach(cs, dirs, 0.02, 0.008, far=0.15)))


def cuffs(body, s, F, shell):
    """Ribbed cuffs where the sleeves end: from the sleeve's end, narrowing at once, then snug."""
    out = bmesh.new()
    ay, az = body.hand[1], body.hand[2]
    ang = np.linspace(0, 2 * np.pi, 28, endpoint=False)
    dirs = np.stack([np.zeros(28), np.cos(ang), np.sin(ang)], 1)
    for side in (1, -1):
        rings = []
        # Where the sleeve ends, at each angle.
        edge = [v.co for v in shell.verts if v.is_boundary and abs(abs(v.co.x) - s.sleeve) < 0.002 and v.co.x * side > 0]
        E = np.array([[p.y - ay, p.z - az] for p in edge])
        th = np.arctan2(E[:, 1], E[:, 0]) % (2 * np.pi)
        r_end = np.hypot(E[:, 0], E[:, 1])
        o = np.argsort(th)
        r0 = np.interp(ang, th[o], r_end[o], period=2 * np.pi)
        cs = lambda x: np.repeat(np.array([[side * x, ay, az]]), 28, 0)
        snug = F.reach(cs(s.sleeve), dirs, 0.02, 0.006, far=0.15)
        rows = [(s.sleeve - 0.004, r0 + 0.001), (s.sleeve + 0.012, snug + 0.012), (s.sleeve + 0.026, snug + 0.0065),
                (s.cuff_end, snug + 0.0065), (s.cuff_end + 0.003, snug + 0.001)]
        for x, r in rows:
            rings.append(new_verts(out, cs(x) + dirs * r[:, None]))
        grid_faces(out, rings, closed=True, flip=side > 0)
    recalc(out)
    return solidify(out, 0.004, even=False)


def hoodie_body(body, s, F, pants):
    """The hoodie below the waist: hangs from the hips over the seat, blousing over a ribbed hem."""
    near = np.abs(body.co[:, 2] - s.z_cut) < 0.02
    cy = 0.5 * (body.co[near][:, 1].min() + body.co[near][:, 1].max())
    z_band = s.z_hem + s.band_h
    rows = np.linspace(s.z_skirt, z_band, 16)
    cols = 64
    alpha = np.linspace(0, 2 * np.pi, cols, endpoint=False)
    dirs = np.stack([np.sin(alpha), -np.cos(alpha), np.zeros(cols)], 1)
    centre = lambda z: np.repeat(np.array([[0.0, cy, z]]), cols, 0)
    snug = F.reach(centre(z_band), dirs, 0.08, 0.016)

    def clear(z, r, margin):
        """r, but never inside the trousers' outer surface (found from outside, by ray) plus margin."""
        out = r.copy()
        for i in range(cols):
            p, _n = hit(pants, centre(z)[0] + dirs[i] * 0.6, -dirs[i])
            if p is not None:
                out[i] = max(out[i], np.hypot(p[0], p[1] - cy) + margin)
        return out
    snug = clear(z_band, snug, 0.016)
    bm = bmesh.new()
    vrows = []
    prev = None
    for z in rows:
        cs = centre(z)
        if z > s.z_cut - 0.004:
            r = F.reach(cs, dirs, s.R_top, s.ease_top) - 0.004
        else:
            r = F.reach(cs, dirs, s.R_skirt, s.ease_skirt)
            blend = np.clip((s.z_cut - z) / s.skirt_blend, 0, 1)
            rj = F.reach(cs, dirs, s.R_top, s.ease_top)
            r = rj + (r - rj) * blend
        if prev is not None and z < s.z_cut:
            r = np.maximum(r, prev - 0.006)
        prev = r
        # Over the last stretch it turns in to the band, a little looser than it.
        t = float(smoothstep(z_band + 0.05, z_band, z))
        r = clear(z, r, 0.01)
        r = r + (np.minimum(r, snug + 0.012) - r) * t
        vrows.append(new_verts(bm, cs + dirs * r[:, None]))
    grid_faces(bm, vrows, closed=True, flip=True)
    recalc(bm)
    face_out(bm, cy)
    # The band: ribbed, just inside the body's hem, and clear of the trousers under it.
    band = bmesh.new()
    zs = np.linspace(z_band + 0.004, s.z_hem, 7)
    base = F.reach(centre(z_band), dirs, 0.08, 0.016)
    brows = []
    for k, z in enumerate(zs):
        r = clear(z, base + (0.012 if k == 0 else 0.0065), 0.012 if k else 0.016)
        brows.append(new_verts(band, centre(z) + dirs * r[:, None]))
    grid_faces(band, brows, closed=True, flip=True)
    recalc(band)
    face_out(band, cy)
    return bm, solidify(band, 0.005, even=False), cy


def cargo_trousers(body, s):
    """Wide skate trousers from the waist down over the shoes: each leg hangs straight from the
    thigh, a little wider at the bottom, and stacks in folds over the shoe, its hem higher over the
    toe than at the heel."""
    c = body.co
    legs = (body.w_leg > 0.2) | (body.w_pelvis > 0.2) | (body.w_foot > 0.2)
    F = Field(body.triangles(legs & (c[:, 2] < s.z_pants + 0.1)))
    z_band = body.ankle[2] + 0.04
    keep = (c[:, 2] < s.z_pants + 0.05) & (c[:, 2] > z_band - 0.04) & (body.w_foot < 0.5) & (body.w_head < 0.1) & (body.w_hand < 0.1)
    keep &= np.abs(c[:, 0]) < 0.35
    bm = body_piece(body, keep)
    cut(bm, (0, 0, s.z_pants), (0, 0, 1))
    cut(bm, (0, 0, z_band), (0, 0, -1))
    subdivide(bm)
    set_coords(bm, F.onto(coords(bm), s.R_pants, s.ease_pants))
    settle(bm, F, s.R_pants, s.ease_pants)
    P = coords(bm)
    for side in (1, -1):
        a = body.hip * [side, 1, 1]
        b = body.ankle * [side, 1, 1]
        P = drape(P, P[:, 0] * side > 0.025, a, b, taper=0.012, t0=0.1)
    set_coords(bm, P)
    smooth(bm, 8)
    P = F.onto(coords(bm), s.R_pants, s.ease_pants * 0.7, outward_only=True)
    P = keep_legs_apart(body, s, P)
    set_coords(bm, P)
    smooth(bm, 2)
    P = keep_legs_apart(body, s, coords(bm))
    set_coords(bm, P)
    # No cloth across the gap below the crotch: a face there would stretch between the knees.
    z_crotch = body.hip[2] - 0.13
    web = [f for f in bm.faces if max(v.co.z for v in f.verts) < z_crotch
           and min(v.co.x for v in f.verts) < 0.0 < max(v.co.x for v in f.verts)]
    if web:
        print("trousers: %d faces across the legs taken out" % len(web))
        bmesh.ops.delete(bm, geom=web, context="FACES")
    # The stack: the leg's edge carried on down over the shoe in rings that flare and fold.
    bm.verts.ensure_lookup_table()
    edges = [e for e in bm.edges if e.is_boundary and all(v.co.z < z_band + 0.01 for v in e.verts)]
    for e in edges:
        for v in e.verts:
            v.co.z = z_band
    rings = 5
    for k in range(1, rings + 1):
        ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
        verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
        f = k / rings
        for v in verts:
            side = 1 if v.co.x > 0 else -1
            ax = body.ankle * [side, 1, 1]
            hem = s.z_leg + s.hem_rise * max(0.0, ax[1] - v.co.y)
            v.co.z = z_band + (hem - z_band) * f
            r = Vector((v.co.x - ax[0], v.co.y - ax[1], 0))
            grow = 0.01 * f + (0.007 if k % 2 else -0.003)
            out = r.normalized() * min(r.length + grow, s.leg_max)
            v.co.x, v.co.y = ax[0] + out.x, ax[1] + out.y
        vs = set(verts)
        edges = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMEdge) and all(v in vs for v in g.verts)]
    # The hem turned in a little, so it reads as cloth with a thickness.
    ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
    for g in ret["geom"]:
        if isinstance(g, bmesh.types.BMVert):
            side = 1 if g.co.x > 0 else -1
            ax = body.ankle * [side, 1, 1]
            r = Vector((g.co.x - ax[0], g.co.y - ax[1], 0))
            g.co -= r.normalized() * 0.009
            g.co.z += 0.022
    recalc(bm)
    return bm, F


def keep_legs_apart(body, s, P):
    """Below the crotch, each leg stays on its own side of the middle and no wider than leg_max
    round the line from hip to ankle (cloth crossing the middle would take the other leg's
    weights, and string between the legs as they move)."""
    P = P.copy()
    z_crotch = body.hip[2] - 0.13
    for side in (1, -1):
        a = body.hip * [side, 1, 1]
        b = body.ankle * [side, 1, 1]
        idx = np.nonzero((P[:, 0] * side > 0.0) & (P[:, 2] < z_crotch))[0]
        Q = P[idx]
        t = np.clip((Q[:, 2] - a[2]) / (b[2] - a[2]), 0.0, 1.0)
        axis = a + (b - a) * t[:, None]
        rv = Q[:, :2] - axis[:, :2]
        r = np.linalg.norm(rv, axis=1)
        k = smoothstep(z_crotch, z_crotch - 0.12, Q[:, 2])
        cap = s.leg_max * k + np.maximum(r, s.leg_max) * (1 - k)
        Q[:, :2] = axis[:, :2] + rv / np.maximum(r, 1e-6)[:, None] * np.minimum(r, cap)[:, None]
        Q[:, 0] = side * np.maximum(Q[:, 0] * side, 0.008)
        P[idx] = Q
    return P


def skate_shoes(body, s):
    """Chunky skate shoes: a padded upper over each foot on a flat cupsole, and laces across the
    tongue."""
    c = body.co
    feet = body.w_foot > 0.2
    F = Field(body.triangles(feet | ((body.w_leg > 0.2) & (c[:, 2] < s.z_collar + 0.08))), h=0.004)
    keep = ((body.w_foot > 0.3) | (body.w_leg > 0.2)) & (c[:, 2] < s.z_collar + 0.02)
    bm = body_piece(body, keep)
    cut(bm, (0, 0, s.z_collar), (0, 0, 1))
    subdivide(bm, 2)
    set_coords(bm, F.onto(coords(bm), 0.03, 0.017))
    settle(bm, F, 0.03, 0.017, rounds=3)
    # A flat sole under the whole foot.
    for _ in range(2):
        P = coords(bm)
        P[:, 2] = np.where(P[:, 2] < 0.006, -SOLE, P[:, 2])
        set_coords(bm, P)
        smooth(bm, 2)
    P = coords(bm)
    P[:, 2] = np.where(P[:, 2] < 0.0, -SOLE, P[:, 2])
    set_coords(bm, P)
    for e in bm.edges:
        if e.is_boundary:
            for v in e.verts:
                v.co.z = s.z_collar
    recalc(bm)
    # The sole is the low band of the shell, the upper the rest.
    sole = bm.copy()
    bmesh.ops.delete(sole, geom=[f for f in sole.faces if f.calc_center_median().z > 0.016], context='FACES')
    bmesh.ops.delete(sole, geom=[v for v in sole.verts if not v.link_faces], context='VERTS')
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z <= 0.016], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    upper = solidify(bm, 0.004, even=False)
    # Laces: bars across the top of the foot.
    bvh = bvh_of(upper)
    laces = bmesh.new()
    for side in (1, -1):
        ax = body.ankle * [side, 1, 1]
        for k in range(4):
            y = ax[1] - 0.04 - k * 0.022
            pts = []
            for u in np.linspace(-1, 1, 5):
                p, _n = hit(bvh, (ax[0] + u * 0.022, y, 0.4), (0, 0, -1))
                if p is not None:
                    pts.append(p + np.array([0, 0, 0.0035]))
            if len(pts) >= 3:
                tube(laces, pts, 0.0035, 6)
    recalc(laces)
    return upper, sole, laces


def backpack(body, s, bvh):
    """A backpack: a rounded pack on the upper back, resting on the hoodie with the hood bunched
    under it, straps over the shoulders that come round under the arms, and two loops across its back
    for the board."""
    top, bottom = body.neck_z - 0.17, body.neck_z - 0.56
    w, depth = 0.3, 0.12
    # The pack rests on the back: against most of what is under it (the hood, bunched under its top, is hidden inside).
    back = []
    for x in np.linspace(-w / 2, w / 2, 9):
        for z in np.linspace(bottom, top, 9):
            p, _n = hit(bvh, (x, 0.8, z), (0, -1, 0))
            if p is not None:
                back.append(p[1])
    y0 = float(np.percentile(back, 60)) + 0.004
    pack = bmesh.new()
    bmesh.ops.create_cube(pack, size=1.0)
    bmesh.ops.scale(pack, vec=Vector((w, depth, top - bottom)), verts=pack.verts)
    bmesh.ops.translate(pack, vec=Vector((0, y0 + depth / 2, (top + bottom) / 2)), verts=pack.verts)
    bmesh.ops.bevel(pack, geom=list(pack.edges), offset=0.04, segments=4, affect="EDGES", profile=0.5, clamp_overlap=True)
    # Fuller at the back and narrower at the top, as a packed bag sits.
    for v in pack.verts:
        u = min(max((v.co.z - bottom) / (top - bottom), 0.0), 1.0)
        if v.co.y > y0 + depth * 0.5:
            v.co.y += 0.02 * math.sin(math.pi * u) * max(0.0, 1 - (2 * v.co.x / w) ** 2)
        if u > 0.75:
            v.co.x *= 1.0 - (u - 0.75) * 0.5
    recalc(pack)
    # A pocket on the pack's back.
    pocket = bmesh.new()
    bmesh.ops.create_cube(pocket, size=1.0)
    bmesh.ops.scale(pocket, vec=Vector((w * 0.68, 0.035, (top - bottom) * 0.4)), verts=pocket.verts)
    bmesh.ops.translate(pocket, vec=Vector((0, y0 + depth + 0.004, bottom + (top - bottom) * 0.25)), verts=pocket.verts)
    bmesh.ops.bevel(pocket, geom=list(pocket.edges), offset=0.014, segments=3, affect="EDGES", profile=0.5, clamp_overlap=True)
    recalc(pocket)
    # The loops the board slides under, across the pack's back.
    loops = bmesh.new()
    for z in (bottom + (top - bottom) * 0.62, top - (top - bottom) * 0.12):
        bmesh.ops.create_cube(loops, size=1.0, matrix=Matrix.Translation(Vector((0, y0 + depth + 0.03, z)))
                              @ Matrix.Diagonal(Vector((w + 0.012, 0.016, 0.038, 1.0))))
    # The straps: from the pack's top over each shoulder, down the chest to a buckle, and back
    # round the ribs under the arm to the pack's bottom corner.
    straps = bmesh.new()
    buckles = bmesh.new()
    front = -0.25
    for side in (1, -1):
        key = [
            (side * 0.085, y0 + 0.01, top - 0.03),
            (side * 0.1, 0.03, body.neck_z - 0.02),
            (side * 0.12, -0.06, body.neck_z - 0.05),
            (side * 0.125, front, body.neck_z - 0.16),
            (side * 0.13, front, body.neck_z - 0.3),
        ]
        upper = band_on(bvh, key, 0.052, 0.008)
        grid_faces(straps, [new_verts(straps, r) for r in upper], closed=True)
        end = np.mean(upper[-1], 0)
        key2 = [
            tuple(end + np.array([0, 0, -0.03])),
            (side * 0.17, front, body.neck_z - 0.37),
            (side * 0.21, 0.0, body.neck_z - 0.42),
            (side * 0.13, y0 + 0.01, bottom + 0.05),
        ]
        lower = band_on(bvh, key2, 0.032, 0.007)
        grid_faces(straps, [new_verts(straps, r) for r in lower], closed=True)
        n = end - np.mean(upper[-2], 0)
        disc(buckles, end + np.array([0.0, -0.006, -0.01]), (0, -1, 0), 0.022, 0.009, 4, spin=math.pi / 4)
    recalc(straps)
    return pack, pocket, loops, straps, buckles


def band_on(bvh, key, width, thick, step=0.012):
    """A flat strap along a path of key points, laid on the nearest surface of bvh: rings of four
    points, a thin rectangle round the path."""
    K = np.array(key, float)
    seg = np.linalg.norm(np.diff(K, axis=0), axis=1)
    at = np.r_[0.0, np.cumsum(seg)]
    n = max(int(at[-1] / step), 4)
    ts = np.linspace(0, at[-1], n)
    P = np.stack([np.interp(ts, at, K[:, k]) for k in range(3)], 1)
    N = np.zeros_like(P)
    for _round in range(5):
        for i, p in enumerate(P):
            loc, nrm, _i, _d = bvh.find_nearest(Vector(p))
            if loc is not None:
                P[i] = np.array(loc) + np.array(nrm) * (thick * 0.5 + 0.004)
                N[i] = np.array(nrm)
        P[1:-1] = (P[:-2] + 2 * P[1:-1] + P[2:]) / 4
    rows = []
    for i, p in enumerate(P):
        t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        t /= max(np.linalg.norm(t), 1e-6)
        nn = N[i] - (N[i] @ t) * t
        nn /= max(np.linalg.norm(nn), 1e-6)
        b = np.cross(t, nn)
        h, d = width / 2, thick / 2
        rows.append([p + b * h + nn * d, p - b * h + nn * d, p - b * h - nn * d, p + b * h - nn * d])
    return rows


def to_spine(body):
    """The pack rides the upper back like a rigid thing: all of it on the spine's top bones."""
    def fn(P, W):
        W = np.zeros_like(W)
        W[:, body.group("spine_03")] = 0.75
        W[:, body.group("spine_02")] = 0.25
        return W
    return fn


def face_out(bm, axis_y):
    """Turns a sheet's faces away from the vertical axis through (0, axis_y), if they aren't already."""
    bm.faces.ensure_lookup_table()
    total = 0.0
    for f in bm.faces:
        c = f.calc_center_median()
        r = Vector((c.x, c.y - axis_y, 0.0))
        if r.length > 1e-6:
            total += f.normal.dot(r.normalized()) * f.calc_area()
    if total < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])


def bvh_union(bms):
    """One BVH tree over several meshes."""
    verts, faces = [], []
    for bm in bms:
        bm.verts.ensure_lookup_table()
        base = len(verts)
        verts += [v.co.copy() for v in bm.verts]
        for f in bm.faces:
            idx = [base + v.index for v in f.verts]
            for k in range(1, len(idx) - 1):
                faces.append((idx[0], idx[k], idx[k + 1]))
    return BVHTree.FromPolygons(verts, faces)


def hood(body, s, shell):
    """The hood, down: a rolled cowl round the neck, from the edge of the neck opening, and a bag over
    the upper back, a copy of the shell there standing a little off it."""
    phi_e, E = s.neck_edge
    n = 72
    phis = np.linspace(0, 2 * np.pi, n, endpoint=False)
    e = np.stack([np.interp(phis, phi_e, E[:, k], period=2 * np.pi) for k in range(3)], 1)

    def round_off(a, times=3):
        """Smooths a closed line of points (the cut and the neck's outline are jagged at the mesh's size)."""
        for _ in range(times):
            a = (np.roll(a, 2, 0) + 2 * np.roll(a, 1, 0) + 3 * a + 2 * np.roll(a, -1, 0) + np.roll(a, -2, 0)) / 9.0
        return a
    e = round_off(e)

    def ring(dz, out):
        return round_off(np.array([neck_round(body, s.neck.y, e[i, 2] + dz, [phis[i]], out)[0] for i in range(n)]))
    cowl = bmesh.new()
    rows = [e + [0.0, 0.0, -0.008], ring(0.012, 0.034), ring(0.033, 0.029), ring(0.044, 0.016),
            ring(0.036, 0.007), ring(0.012, 0.003)]
    grid_faces(cowl, [new_verts(cowl, r) for r in rows], closed=True, flip=True)
    recalc(cowl)
    cowl = solidify(cowl, 0.003, even=False)
    # The bag.
    bag = shell.copy()
    subdivide(bag)
    zc, hz, wx = body.neck_z - 0.1, 0.2, 0.15

    def outline(p):
        g = (abs(p[0]) / wx) ** 2.6 + (abs(p[2] - zc) / hz) ** 2.6 - 1.0
        return max(g, (s.neck.y + 0.03 - p[1]) * 20.0)
    cut_level(bag, outline)
    bag.normal_update()
    for v in bag.verts:
        nv = v.normal if v.normal.y > 0 else -v.normal
        inside = float(smoothstep(0.0, 0.5, -outline(np.array(v.co[:]))))
        top = float(smoothstep(zc - 0.1, zc + 0.14, v.co.z))
        v.co += nv * (0.008 + 0.034 * inside * (0.55 + 0.45 * top))
    smooth(bag, 3)
    recalc(bag)
    bag = solidify(bag, 0.004, even=False)
    return cowl, bag


def pouch(body, s, bvh):
    """The pouch pocket on the front: wider at the bottom, its sides open at a slant, standing off a little."""
    bm = bmesh.new()
    z0, z1 = s.z_hem + s.band_h + 0.014, s.z_cut + 0.1
    rows, cols = 14, 17
    grid = []
    for i in range(rows):
        v = i / (rows - 1)
        z = z0 + (z1 - z0) * v
        w = 0.155 - 0.04 * v
        row = []
        for j in range(cols):
            u = -1 + 2 * j / (cols - 1)
            p, nrm = hit(bvh, (u * w, -0.6, z), (0, 1, 0))
            if p is None:
                p = np.array([u * w, -0.1, z])
            side = float(smoothstep(0.7, 1.0, abs(u)))
            top = float(smoothstep(0.9, 1.0, v))
            lift = 0.009 + 0.008 * side * (1.0 - top) + 0.005 * (1.0 - abs(u)) * (1.0 - v) * (1.0 - top)
            row.append(p + FWD * lift)
        grid.append(row)
    grid_faces(bm, [new_verts(bm, r) for r in grid], flip=True)
    recalc(bm)
    face_out(bm, 0.05)
    return solidify(bm, 0.004, even=False)


def drawstrings(body, s, bvh):
    """Two cords hanging from the neck opening down the chest, with a metal tip each."""
    cords, tips = bmesh.new(), bmesh.new()
    phi_e, E = s.neck_edge
    z_top = float(np.interp(0.0, phi_e, E[:, 2], period=2 * np.pi)) + 0.004
    for side in (1, -1):
        pts = []
        for k in range(9):
            z = z_top - 0.012 - k * 0.026
            x = side * (0.043 + 0.006 * math.sin(k * 0.7) + 0.004 * k / 8)
            p, _n = hit(bvh, (x, -0.6, z), (0, 1, 0))
            if p is None:
                break
            pts.append(p + FWD * (0.0045 + 0.004 * math.sin(k * 1.3 + (0 if side > 0 else 2))))
        tube(cords, pts, 0.0034, 6)
        tip = pts[-1] + np.array([0.0, 0.0, -0.012])
        bmesh.ops.create_cone(tips, cap_ends=True, cap_tris=False, segments=8, radius1=0.0048, radius2=0.0048,
                              depth=0.026, matrix=Matrix.Translation(Vector(tip)))
    recalc(cords)
    return cords, tips


def cargo_pockets(body, s, bvh):
    """A cargo pocket on each thigh: a pouch that bulges toward the bottom, with a flap and a button."""
    pockets, buttons = bmesh.new(), bmesh.new()
    for side in (1, -1):
        yc = body.hip[1] + 0.005
        z0, z1 = body.hip[2] - 0.40, body.hip[2] - 0.20
        rows, cols = 14, 12
        grid = []
        for i in range(rows):
            v = i / (rows - 1)
            z = z0 + (z1 - z0) * v
            row = []
            for j in range(cols):
                u = -1 + 2 * j / (cols - 1)
                p, _n = hit(bvh, (side * 0.7, yc + u * 0.078, z), (-side, 0, 0))
                if p is None:
                    p = np.array([side * 0.2, yc + u * 0.078, z])
                edge = float(smoothstep(0.55, 1.0, abs(u)))
                belly = (1.0 - v) ** 0.7
                lift = 0.004 + 0.013 * belly * (1.0 - edge) + 0.003 * (1.0 - edge)
                row.append(p + np.array([side * lift, 0.0, 0.0]))
            grid.append(row)
        grid_faces(pockets, [new_verts(pockets, r) for r in grid], flip=side > 0)
        # The flap: over the top, pointed at the bottom.
        zf0, zf1 = z1 - 0.055, z1 + 0.012
        grid = []
        for i in range(5):
            v = i / 4
            z = zf0 + (zf1 - zf0) * v
            row = []
            for j in range(cols):
                u = -1 + 2 * j / (cols - 1)
                zz = z + 0.022 * (1.0 - abs(u)) * (1.0 - v) ** 1.0 * 0.0
                zz = z - 0.02 * (1.0 - abs(u)) * (1.0 - v)
                p, _n = hit(bvh, (side * 0.7, yc + u * 0.085, zz), (-side, 0, 0))
                if p is None:
                    p = np.array([side * 0.2, yc + u * 0.085, zz])
                row.append(p + np.array([side * (0.0235 - 0.006 * (1.0 - v)), 0.0, 0.0]))
            grid.append(row)
        grid_faces(pockets, [new_verts(pockets, r) for r in grid], flip=side > 0)
        p, nrm = hit(bvh, (side * 0.7, yc, zf0 - 0.0), (-side, 0, 0))
        if p is not None:
            disc(buttons, p + np.array([side * 0.0225, 0.0, 0.0]), (side, 0, 0), 0.0085, 0.004, 12)
    recalc(pockets)
    return solidify(pockets, 0.004, even=False), buttons


def foot_to_calf(body):
    """Trousers hang from the shin, not the foot: the foot's weights go to the calf above it."""
    def fn(P, W):
        W = W.copy()
        for side in ("l", "r"):
            calf = body.group("calf_" + side)
            for g in (body.group("foot_" + side), body.group("ball_" + side)):
                W[:, calf] += W[:, g]
                W[:, g] = 0.0
        return normalize_weights(W)
    return fn


def trim_body(body, s):
    """Cuts away the skin the clothes cover, keeping the head, the neck above a clean line just over the
    neckline (the cowl hides it), the hands and the feet below the trousers' hem."""
    c = body.co
    dx, dy = c[:, 0], c[:, 1] - s.neck.y
    neck = ((c[:, 2] > s.neck(np.arctan2(dx, -dy)) - 0.03) & (np.hypot(dx, dy) < 0.1)) \
        | ((c[:, 2] > body.neck_z + 0.02) & (np.hypot(dx, dy) < 0.17))
    keep_skin(body, (np.abs(c[:, 0]) > s.skin_hand) | neck | ((body.w_head > 0.5) & (c[:, 2] > body.neck_z + 0.08))
              | (c[:, 2] < s.z_collar + 0.01))
    bm = bmesh.new()
    bm.from_mesh(body.obj.data)

    def under(p):
        dx, dy = p[0], p[1] - s.neck.y
        if math.hypot(dx, dy) > 0.2 or p[2] < body.neck_z - 0.2 or abs(p[0]) > 0.2:
            return -1.0
        return float(s.neck(math.atan2(dx, -dy))) + 0.012 - p[2]
    cut_level(bm, under)
    bm.to_mesh(body.obj.data)


def streetwear(body):
    s = Street(body)
    tris = body.triangles()
    if s.female:
        tris = np.concatenate([tris, bust_filler(body), seat_filler(body)])
    F = Field(tris)
    s.cuff_r = cuff_radius(body, F, s)
    pants, _ = cargo_trousers(body, s)
    pants_bvh = bvh_of(pants)
    shell = hoodie_shell(body, s, F)
    low, hem, cy = hoodie_body(body, s, F, pants_bvh)
    front = bvh_union([shell, low])
    rib = cuffs(body, s, F, shell)
    cowl, bag = hood(body, s, shell)
    pocket = pouch(body, s, front)
    cords, tips = drawstrings(body, s, front)
    flaps, buttons = cargo_pockets(body, s, pants_bvh)
    shoes, soles, laces = skate_shoes(body, s)
    pack, pack_pocket, loops, straps, buckles = backpack(body, s, bvh_union([shell, low, bag, cowl]))
    trim_body(body, s)
    add_part(body, "Hoodie", [shell, low, pocket])
    add_part(body, "Hood", [cowl, bag], smooth_weights=3)
    add_part(body, "Rib", [rib, hem])
    add_part(body, "Strings", [cords])
    add_part(body, "Metal", [tips, buttons, buckles], smooth_shade=False)
    add_part(body, "Trousers", [pants, flaps], foot_to_calf(body))
    add_part(body, "Shoes", [shoes])
    add_part(body, "Soles", [soles])
    add_part(body, "Laces", [laces])
    add_part(body, "Pack", [pack, pack_pocket], to_spine(body))
    add_part(body, "Straps", [straps], smooth_weights=4)
    add_part(body, "Loops", [loops], to_spine(body), smooth_shade=False)


# Each outfit and the bodies it's made for.
OUTFITS = {"streetwear": (streetwear, ("male", "female"))}


def main():
    os.makedirs(OUT, exist_ok=True)
    outfits = [o for o in OUTFITS if not (WANT & set(OUTFITS)) or o in WANT]
    bodies = [b for b in BODIES if not (WANT & set(BODIES)) or b in WANT]
    for outfit in outfits:
        make, fits = OUTFITS[outfit]
        for kind in [b for b in bodies if b in fits]:
            body = Body(kind)
            make(body)
            path = os.path.join(OUT, "%s_%s.gltf" % (outfit, kind))
            export(body, path)
            print("wrote", path)


if __name__ == "__main__":
    main()
