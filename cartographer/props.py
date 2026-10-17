"""Street furniture and trees, from the map where it has them and by rule
where it doesn't: lamps along streets, trees in parks and woods, benches
and bins by paths and squares, hydrants at the kerb. Every prop is
{"m": model, "p": (x, y, z), "yaw": radians}, turned with
Basis(Vector3.UP, yaw) in the game so the model's front (+z) faces the
street. Placement is seeded, so every copy of a town matches.
"""
import math
import random

from shapely.geometry import Point
from shapely.prepared import prep
from shapely.strtree import STRtree

from .geo import stable_seed

LAMP_EVERY = 32.0
HYDRANT_EVERY = 95.0
BIN_EVERY = 70.0
PARK_TREE_AREA = 90.0
WOOD_TREE_AREA = 35.0
MAX_TREES_PER_AREA = 600
LAMP_STREETS = {"primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "trunk",
                "primary_link", "secondary_link", "tertiary_link", "road"}


def _yaw_to(dx, dz):
    return math.atan2(dx, dz)


class Placer:
    """Keeps props off roads, out of buildings and apart from each other."""

    def __init__(self, road, built):
        self.road = prep(road) if road is not None else None
        polys = [b["poly"] for b in built]
        self.tree = STRtree(polys) if polys else None
        self.polys = polys
        self.taken = {}
        self.props = []

    def free(self, x, z, gap=1.2):
        p = Point(x, z)
        if self.road is not None and self.road.contains(p):
            return False
        if self.tree is not None and len(self.tree.query(p, predicate="within")) > 0:
            return False
        key = (int(x // 4), int(z // 4))
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for ox, oz in self.taken.get((key[0] + i, key[1] + j), ()):
                    if (ox - x) ** 2 + (oz - z) ** 2 < gap * gap:
                        return False
        return True

    def put(self, model, x, z, yaw, field, gap=1.2):
        if not self.free(x, z, gap):
            return False
        self.taken.setdefault((int(x // 4), int(z // 4)), []).append((x, z))
        self.props.append({"m": model, "p": (float(x), float(field.at(x, z)), float(z)), "yaw": float(yaw)})
        return True


def place(map_data, ways, field, road, built, areas_green):
    placer = Placer(road, built)
    # The map's own trees and lamps first.
    for p in map_data.points:
        t = p["tags"]
        if t.get("natural") == "tree":
            placer.put("street/street_tree", p["x"], p["z"], stable_seed(p["x"], p["z"]) % 628 / 100.0, field, 1.5)
        elif t.get("highway") == "street_lamp":
            placer.put("street/street_lamp", p["x"], p["z"], 0.0, field, 2.0)
    for w in ways:
        if w["tunnel"] or w["bridge"]:
            continue
        rng = random.Random(stable_seed("props", w["id"]))
        line = w["line"]
        if w["kind"] in LAMP_STREETS and line.length > 12.0:
            _along(placer, field, line, w["width"] * 0.5 + 0.7, LAMP_EVERY, "street/street_lamp", rng, 4.0,
                   alternate=w["width"] > 7.0, facing="street")
        if w["motor"] and w["kind"] != "service" and line.length > 40.0:
            _along(placer, field, line, w["width"] * 0.5 + 0.45, HYDRANT_EVERY, "street/hydrant", rng, 1.5,
                   offset=HYDRANT_EVERY * rng.random())
        if w["kind"] in ("pedestrian", "footway", "living_street") and line.length > 20.0:
            _along(placer, field, line, w["width"] * 0.5 + 0.6, BIN_EVERY, "street/litter_bin", rng, 1.5,
                   offset=BIN_EVERY * rng.random())
            _along(placer, field, line, w["width"] * 0.5 + 0.8, BIN_EVERY * 1.3, "street/bench", rng, 2.0,
                   offset=BIN_EVERY * rng.random(), facing="street")
        if w["kind"] == "pedestrian" and line.length > 20.0:
            _along(placer, field, line, w["width"] * 0.5 - 0.8, 18.0, "street/street_tree", rng, 3.0,
                   alternate=True, offset=9.0)
        if w["kind"] == "service" and line.length > 15.0 and rng.random() < 0.35:
            _along(placer, field, line, w["width"] * 0.5 + 0.9, 60.0, "street/dumpster", rng, 2.5,
                   offset=line.length * rng.random(), facing="street")
    for kind, poly in areas_green:
        rng = random.Random(stable_seed("trees", round(poly.centroid.x), round(poly.centroid.y)))
        per = WOOD_TREE_AREA if kind == "wood" else PARK_TREE_AREA
        count = min(MAX_TREES_PER_AREA, int(poly.area / per))
        minx, minz, maxx, maxz = poly.bounds
        inside = prep(poly)
        for _ in range(count * 3):
            if count <= 0:
                break
            x, z = rng.uniform(minx, maxx), rng.uniform(minz, maxz)
            if inside.contains(Point(x, z)) and placer.put("street/street_tree", x, z, rng.uniform(0, 6.28), field,
                                                            3.5 if kind == "wood" else 5.0):
                count -= 1
    return placer.props


def _along(placer, field, line, off, every, model, rng, gap, alternate=False, offset=None, facing=None):
    s = every * 0.5 if offset is None else offset
    side = 1.0 if rng.random() < 0.5 else -1.0
    while s < line.length:
        a = line.interpolate(max(0.0, s - 0.5))
        b = line.interpolate(min(line.length, s + 0.5))
        dx, dz = b.x - a.x, b.y - a.y
        d = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / d * side, dx / d * side
        p = line.interpolate(s)
        x, z = p.x + nx * off, p.y + nz * off
        yaw = _yaw_to(-nx, -nz) if facing == "street" else _yaw_to(dx, dz)
        placer.put(model, x, z, yaw, field, gap)
        if alternate:
            side = -side
        s += every
