"""Quarters: the unit of territory. The map's own named neighbourhoods where
it has them (areas first, then the nearest named place point), otherwise
cells of about half a kilometre named after their busiest street.

A quarter's number comes from its name, so rebuilding a town from a newer
extract keeps the walls' quarters (the game server keeps paint by town and
quarter).
"""
import math

import numpy as np
from shapely.geometry import Point, Polygon
from shapely.prepared import prep

from .geo import stable_seed

PLACES = ("quarter", "neighbourhood", "suburb", "borough")
# A place point names the land within this of it, nearest first.
PLACE_REACH = 1200.0
CELL = 500.0
MAX_ID = 10000


class Quarters:
    def __init__(self):
        self.list = []  # {"id", "name", "centre": (x, z)}
        self._areas = []  # (prepared polygon, index)
        self._points = []  # (x, z, index)
        self._cells = {}  # (i, j) -> index
        self._ids = set()

    def _add(self, name, centre):
        q = stable_seed("quarter", name) % MAX_ID
        while q in self._ids:
            q = (q + 1) % MAX_ID
        self._ids.add(q)
        self.list.append({"id": q, "name": name, "centre": (float(centre[0]), float(centre[1]))})
        return len(self.list) - 1

    def at(self, x, z):
        """The quarter (its dict) a point is in."""
        p = Point(x, z)
        for poly, k in self._areas:
            if poly.contains(p):
                return self.list[k]
        best, best_d = None, PLACE_REACH
        for px, pz, k in self._points:
            d = math.hypot(px - x, pz - z)
            if d < best_d:
                best, best_d = k, d
        if best is not None:
            return self.list[best]
        key = (int(math.floor(x / CELL)), int(math.floor(z / CELL)))
        return self.list[self._cells[key]] if key in self._cells else self.list[0]

    def grid(self, x0, z0, size, n):
        """The quarters' numbers over a square, n x n cells (int32)."""
        out = np.zeros((n, n), dtype=np.int32)
        step = size / n
        for j in range(n):
            for i in range(n):
                out[j, i] = self.at(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step)["id"]
        return out


def build(map_data, ways, box, town_name):
    qs = Quarters()
    named = []
    for a in map_data.areas:
        place = a["tags"].get("place")
        if place in PLACES and a["tags"].get("name"):
            for outer, inners in a["polys"]:
                try:
                    p = Polygon(outer, inners).buffer(0)
                except (ValueError, TypeError):
                    continue
                if not p.is_empty:
                    named.append((a["tags"]["name"], p))
    for name, p in sorted(named, key=lambda t: t[0]):
        k = qs._add(name, (p.centroid.x, p.centroid.y))
        qs._areas.append((prep(p), k))
    pts = sorted((p for p in map_data.points if p["tags"].get("place") in PLACES and p["tags"].get("name")),
                 key=lambda p: p["tags"]["name"])
    for p in pts:
        if any(q["name"] == p["tags"]["name"] for q in qs.list):
            continue
        k = qs._add(p["tags"]["name"], (p["x"], p["z"]))
        qs._points.append((p["x"], p["z"], k))
    # Cells for land no named place reaches.
    for i in range(int(math.floor(box.x0 / CELL)), int(math.floor(box.x1 / CELL)) + 1):
        for j in range(int(math.floor(box.z0 / CELL)), int(math.floor(box.z1 / CELL)) + 1):
            cx, cz = (i + 0.5) * CELL, (j + 0.5) * CELL
            if qs._points and min(math.hypot(px - cx, pz - cz) for px, pz, _ in qs._points) < PLACE_REACH:
                continue
            name = _main_street(ways, i * CELL, j * CELL) or "%s %d-%d" % (town_name, i, j)
            k = qs._add(name, (cx, cz))
            qs._cells[(i, j)] = k
    if not qs.list:
        qs._add(town_name, (0.0, 0.0))
    return qs


def _main_street(ways, x0, z0):
    best, best_w = "", 0.0
    for w in ways:
        if not w["name"] or w["tunnel"] or w["rail"]:
            continue
        minx, minz, maxx, maxz = w["line"].bounds
        if maxx < x0 or minx > x0 + CELL or maxz < z0 or minz > z0 + CELL:
            continue
        inside = w["line"].intersection(Polygon([(x0, z0), (x0 + CELL, z0), (x0 + CELL, z0 + CELL), (x0, z0 + CELL)]))
        score = inside.length * w["weight"]
        if score > best_w:
            best, best_w = w["name"], score
    return best
