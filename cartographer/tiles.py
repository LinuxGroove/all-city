"""Cuts a built town into 256 m tiles and writes them, with the town's
manifest. docs/tiles.md is the format.
"""
import gzip
import json
import math
import os

import numpy as np
import shapely
from shapely.geometry import box as shapely_box

from . import FORMAT, VERSION
from .godot_variant import Vec2, Vec3, encode

SIZE = 256.0
HEIGHT_CELLS = 64
QUARTER_CELLS = 8


def key(x, z):
    return (int(math.floor(x / SIZE)), int(math.floor(z / SIZE)))


def _v3(p):
    return Vec3(p[0], p[1], p[2])


def _pts(pts):
    return np.asarray(pts, dtype=np.float32).reshape(-1, 3)


def split(pts):
    """A polyline cut where it crosses from one tile to the next, each piece
    keyed by the tile of its first point (pieces share their joining point)."""
    out = []
    cur = [pts[0]]
    cur_key = key(pts[0][0], pts[0][2])
    for p in pts[1:]:
        cur.append(p)
        k = key(p[0], p[2])
        if k != cur_key:
            out.append((cur_key, cur))
            cur = [p]
            cur_key = k
    if len(cur) >= 2:
        out.append((cur_key, cur))
    return out


def _trees(trees):
    """A tile's trees as packed arrays: `models` (names), and per tree its
    model's index in `kind`, its foot `p`, `yaw` and scale `s`."""
    models = sorted({t["m"] for t in trees})
    return {
        "models": models,
        "kind": np.asarray([models.index(t["m"]) for t in trees], dtype=np.uint8),
        "p": _pts([t["p"] for t in trees]) if trees else np.zeros((0, 3), np.float32),
        "yaw": np.asarray([t["yaw"] for t in trees], dtype=np.float32),
        "s": np.asarray([t["s"] for t in trees], dtype=np.float32),
    }


class Town:
    """Everything built, sorted into tiles as it's added."""

    def __init__(self, box):
        self.box = box
        self.tiles = {}
        for i in range(int(math.floor(box.x0 / SIZE)), int(math.ceil(box.x1 / SIZE))):
            for j in range(int(math.floor(box.z0 / SIZE)), int(math.ceil(box.z1 / SIZE))):
                self.tiles[(i, j)] = {"buildings": [], "lines": [], "flights": [], "bridges": [], "props": [],
                                      "trees": [], "landmarks": [], "lanes": [], "water": {"verts": [], "tris": []}}

    def _tile(self, x, z):
        return self.tiles.get(key(x, z))

    def add_building(self, b):
        c = b["poly"].representative_point()
        t = self._tile(c.x, c.y)
        if t is None:
            return
        faces = []
        for f in b["faces"]:
            faces.append({
                "id": f["id"], "p0": _v3(f["p0"]), "p1": _v3(f["p1"]), "storeys": int(f["storeys"]),
                "ground": f["ground"], "pipe": int(f["pipe"]), "escape": int(f["escape"]), "ends": list(f["ends"]),
                "paint": int(f["paint"]), "paint_top": float(f["paint_top"]), "eyes": int(f.get("eyes", 0)),
                "quarter": int(f.get("quarter", 0)), "seed": int(f["seed"]),
            })
        rec = {
            "id": b["id"], "rings": [np.asarray(r, dtype=np.float32) for r in b["rings"]], "tris": b["tris"],
            "y0": float(b["y0"]), "top": float(b["top"]), "storeys": int(b["storeys"]), "style": b["style"],
            "seed": int(b["seed"]), "paint": int(b["paint"]), "kind": b["kind"],
            "props": [{"m": p["m"], "p": _v3(p["p"]), "yaw": float(p["yaw"])} for p in b["props"]],
            "faces": faces,
        }
        if b.get("roof"):
            r = b["roof"]
            rec["roof"] = {"shape": r["shape"], "rise": float(r["rise"]), "verts": _pts(r["verts"]),
                           "tris": np.asarray(r["tris"], dtype=np.int32), "walls": _pts(r["walls"])}
        t["buildings"].append(rec)

    def add_line(self, line):
        for k, piece in split(line["pts"]):
            t = self.tiles.get(k)
            if t is None:
                continue
            rec = {k2: v for k2, v in line.items() if k2 != "pts"}
            rec["pts"] = _pts(piece)
            t["lines"].append(rec)

    def add_lane(self, lane):
        for k, piece in split(lane["pts"]):
            t = self.tiles.get(k)
            if t is not None:
                t["lanes"].append({"pts": _pts(piece), "kind": lane["kind"], "bridge": bool(lane["bridge"])})

    def add_flight(self, f):
        bx, by, bz = f["bottom"]
        t = self._tile(bx, bz)
        if t is not None:
            t["flights"].append({
                "bottom": Vec3(bx, by, bz), "up": Vec2(*f["up"]), "steps": int(f["steps"]), "rise": float(f["rise"]),
                "going": float(f["going"]), "width": float(f["width"]), "walls": bool(f["walls"]),
            })

    def add_bridge(self, b):
        x, _, z = b["pts"][len(b["pts"]) // 2]
        t = self._tile(x, z)
        if t is not None:
            t["bridges"].append({"pts": _pts(b["pts"]), "width": float(b["width"]), "rail": bool(b["rail"]),
                                 "motor": bool(b["motor"])})

    def add_prop(self, p):
        t = self._tile(p["p"][0], p["p"][2])
        if t is not None:
            t["props"].append({"m": p["m"], "p": _v3(p["p"]), "yaw": float(p["yaw"])})

    def add_landmark(self, lm):
        at = lm.get("home", lm.get("p"))
        t = self._tile(at[0], at[2])
        if t is None:
            return
        rec = {}
        for k, v in lm.items():
            if k in ("p", "home"):
                rec[k] = _v3(v)
            elif k in ("field", "stadium", "verts", "walls"):
                rec[k] = _pts(v)
            elif k == "tris":
                rec[k] = np.asarray(v, dtype=np.int32)
            elif k == "rows":
                rec[k] = [_pts(line) for line in v]
            elif isinstance(v, bool):
                rec[k] = v
            elif isinstance(v, (int, float)):
                rec[k] = float(v)
            else:
                rec[k] = v
        t["landmarks"].append(rec)

    def add_tree(self, tree):
        t = self._tile(tree["p"][0], tree["p"][2])
        if t is not None:
            t["trees"].append(tree)

    def add_water(self, geom, level):
        """Sea or a lake (a Polygon or MultiPolygon), cut and triangulated
        per tile, at `level`."""
        if geom is None or geom.is_empty:
            return
        for (i, j), t in self.tiles.items():
            frame = shapely_box(i * SIZE, j * SIZE, (i + 1) * SIZE, (j + 1) * SIZE)
            part = geom.intersection(frame)
            if part.is_empty:
                continue
            tri = shapely.constrained_delaunay_triangles(part) if part.geom_type in ("Polygon", "MultiPolygon") else None
            if tri is None:
                polys = [g for g in getattr(part, "geoms", []) if g.geom_type in ("Polygon", "MultiPolygon")]
                tri = shapely.GeometryCollection([shapely.constrained_delaunay_triangles(g) for g in polys])
            verts, tris = t["water"]["verts"], t["water"]["tris"]
            for g in _triangles(tri):
                cs = list(g.exterior.coords)[:3]
                (x0, z0), (x1, z1), (x2, z2) = cs
                if (x1 - x0) * (z2 - z0) - (z1 - z0) * (x2 - x0) > 0:
                    cs = [cs[0], cs[2], cs[1]]
                base = len(verts)
                verts += [(x, level, z) for x, z in cs]
                tris += [base, base + 1, base + 2]

    def write(self, out_dir, field, cover, quarters, manifest):
        """Writes tiles/<i>_<j>.tile and town.json; returns the bytes written."""
        os.makedirs(os.path.join(out_dir, "tiles"), exist_ok=True)
        total = 0
        written = []
        for (i, j), t in sorted(self.tiles.items()):
            x0, z0 = i * SIZE, j * SIZE
            heights = field.block(x0, z0, HEIGHT_CELLS + 1)
            tile = {
                "format": FORMAT, "i": i, "j": j, "x0": x0, "z0": z0, "size": SIZE,
                "heights": heights.astype(np.float32).ravel(),
                "ground": cover.picture(x0, z0, SIZE),
                "quarters": quarters.grid(x0, z0, SIZE, QUARTER_CELLS).ravel(),
                "buildings": t["buildings"], "lines": t["lines"], "flights": t["flights"], "bridges": t["bridges"],
                "props": t["props"], "lanes": t["lanes"], "trees": _trees(t["trees"]),
                "landmarks": t["landmarks"],
                "water": {"verts": _pts(t["water"]["verts"]) if t["water"]["verts"] else np.zeros((0, 3), np.float32),
                          "tris": np.asarray(t["water"]["tris"], dtype=np.int32)},
            }
            data = gzip.compress(encode(tile), compresslevel=6, mtime=0)
            with open(os.path.join(out_dir, "tiles", "%d_%d.tile" % (i, j)), "wb") as f:
                f.write(data)
            total += len(data)
            written.append([i, j])
        manifest = dict(manifest)
        manifest["format"] = FORMAT
        manifest["cartographer"] = VERSION
        manifest["tile_size"] = SIZE
        manifest["tiles"] = written
        used = {f["quarter"] for t in self.tiles.values() for b in t["buildings"] for f in b["faces"]}
        manifest["quarters"] = [{"id": q["id"], "name": q["name"], "centre": [round(q["centre"][0], 1),
                                                                              round(q["centre"][1], 1)]}
                                for q in quarters.list if q["id"] in used or not used]
        manifest.setdefault("stats", {})["tile_bytes"] = total
        with open(os.path.join(out_dir, "town.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1, ensure_ascii=False)
            f.write("\n")
        return total


def _triangles(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    out = []
    for part in getattr(g, "geoms", []):
        out += _triangles(part)
    return out
