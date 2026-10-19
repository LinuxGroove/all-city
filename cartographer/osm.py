"""Reads an OpenStreetMap file (.osm.pbf, .osm or .osm.bz2) into the plain
lists the rest of the Cartographer works from: building and land areas,
lines (streets, steps, barriers, rails, wires, water) and tagged points, all
in metres from the town's centre, inside the town's box.

Only the tags the game uses are kept. Nothing about people is in the map in
the first place; postal addresses (addr:*) are dropped here so they can't
reach a tile.
"""
import osmium

from .geo import Box, Projection

BUILDING_TAGS = ("building", "building:levels", "height", "min_height", "roof:shape", "roof:levels",
                 "building:material", "building:colour", "amenity", "shop", "religion", "name", "layer",
                 "location", "man_made", "tourism", "historic", "office", "leisure", "wikidata", "sport",
                 "tower:type")
AREA_TAGS = ("landuse", "leisure", "natural", "amenity", "man_made", "water", "waterway", "highway", "area",
             "area:highway", "place", "military", "sport", "surface", "name", "railway", "historic",
             "social_facility", "parking", "layer", "tunnel", "bridge", "wikidata", "tourism")
LINE_TAGS = ("highway", "name", "bridge", "tunnel", "layer", "width", "lanes", "oneway", "handrail",
             "handrail:left", "handrail:right", "handrail:center", "incline", "step_count", "barrier",
             "height", "railway", "service", "usage", "power", "voltage", "waterway", "natural",
             "man_made", "area", "junction", "sidewalk", "level", "covered", "indoor", "location",
             "cables", "wires", "material", "wall")
POINT_TAGS = ("amenity", "shop", "place", "name", "natural", "power", "man_made", "advertising", "highway",
              "leisure", "tourism", "historic", "religion", "height", "tower:type", "barrier", "craft",
              "office", "social_facility", "healthcare", "wikidata", "artwork_type")
# Points worth keeping; everything else (crossings, bus stops...) isn't used.
POINT_KEYS = ("amenity", "shop", "place", "power", "man_made", "advertising", "leisure", "tourism",
              "historic", "craft", "office", "healthcare")
POINT_VALUES = {("natural", "tree"), ("highway", "street_lamp"), ("natural", "peak")}
AREA_KEYS = ("landuse", "leisure", "natural", "amenity", "man_made", "water", "waterway", "area:highway",
             "place", "military", "railway")
LINE_KEYS = ("highway", "barrier", "railway", "power", "waterway", "natural", "man_made")


def _keep(tags, keys):
    return {k: v for k, v in tags.items() if k in keys}


class MapData:
    """Everything read from the map inside the box."""

    def __init__(self):
        # {"id": osm id, "kind": "way" or "relation", "tags": {...}, "rings": [[(x, z), ...] outer, inner, ...]}
        # grouped as polygons: a list of (outer, [inners]) per area.
        self.buildings = []
        self.areas = []
        # {"id", "tags", "pts": [(x, z)], "nodes": [node ids]}
        self.lines = []
        # {"id", "tags", "x", "z"}
        self.points = []
        # Tags of the nodes lines pass through that matter (power poles,
        # towers), by node id.
        self.node_tags = {}
        self.newest = ""  # the newest object's timestamp, as the data's date


class _Reader(osmium.SimpleHandler):
    def __init__(self, proj: Projection, box: Box):
        super().__init__()
        self.proj = proj
        self.box = box
        self.data = MapData()

    def _xz(self, loc):
        return self.proj.xz(loc.lat, loc.lon)

    def _stamp(self, obj):
        try:
            t = obj.timestamp.strftime("%Y-%m-%d")
        except (AttributeError, ValueError):
            return
        if t > self.data.newest:
            self.data.newest = t

    def node(self, n):
        if not n.tags:
            return
        tags = {t.k: t.v for t in n.tags}
        power = tags.get("power")
        if power in ("pole", "tower", "portal"):
            self.data.node_tags[n.id] = _keep(tags, ("power", "height", "material"))
        if not (any(k in tags for k in POINT_KEYS) or any((k, tags.get(k)) in POINT_VALUES for k, _ in POINT_VALUES)):
            return
        if not n.location.valid():
            return
        x, z = self._xz(n.location)
        if not self.box.contains(x, z):
            return
        self._stamp(n)
        self.data.points.append({"id": n.id, "tags": _keep(tags, POINT_TAGS), "x": x, "z": z})

    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        if not any(k in tags for k in LINE_KEYS):
            return
        if tags.get("area") == "yes" or "building" in tags:
            return  # read as an area
        if tags.get("highway") in ("pedestrian", "footway", "service") and tags.get("area") == "yes":
            return
        try:
            pts = [self._xz(n.location) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(pts) < 2 or not any(self.box.contains(x, z, 50.0) for x, z in pts):
            return
        self._stamp(w)
        self.data.lines.append({"id": w.id, "tags": _keep(tags, LINE_TAGS), "pts": pts,
                                "nodes": [n.ref for n in w.nodes]})

    def area(self, a):
        tags = {t.k: t.v for t in a.tags}
        is_building = "building" in tags and tags["building"] != "no"
        if not is_building and not any(k in tags for k in AREA_KEYS):
            return
        if not is_building and "highway" in tags and tags.get("area") != "yes":
            return
        polys = []
        try:
            for outer in a.outer_rings():
                ring = [self._xz(n) for n in outer]
                inners = [[self._xz(n) for n in inner] for inner in a.inner_rings(outer)]
                polys.append((ring, inners))
        except osmium.InvalidLocationError:
            return
        if not polys or not any(self.box.contains(x, z, 30.0) for ring, _ in polys for x, z in ring):
            return
        self._stamp(a)
        rec = {"id": a.orig_id(), "kind": "way" if a.from_way() else "relation", "polys": polys}
        if is_building:
            rec["tags"] = _keep(tags, BUILDING_TAGS)
            self.data.buildings.append(rec)
        else:
            rec["tags"] = _keep(tags, AREA_TAGS)
            self.data.areas.append(rec)


def read(path: str, proj: Projection, box: Box) -> MapData:
    r = _Reader(proj, box)
    r.apply_file(path, locations=True, idx="flex_mem")
    return r.data
