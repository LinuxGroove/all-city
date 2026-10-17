"""Water: the sea from the coastline, and lakes, ponds and wide rivers
from their areas.

OpenStreetMap draws the coastline as lines with the land on their left, so
the sea is every piece of the town's box that lies on the right of them.
"""
from shapely.geometry import LineString, Point, Polygon, box as shapely_box
from shapely.ops import linemerge, polygonize, unary_union

def sea(map_data, box):
    """The sea inside `box` as one (Multi)Polygon, or None when the town has
    no coast."""
    coast = [l["pts"] for l in map_data.lines if l["tags"].get("natural") == "coastline" and len(l["pts"]) >= 2]
    if not coast:
        return None
    frame = shapely_box(box.x0, box.z0, box.x1, box.z1)
    lines = linemerge([LineString(p) for p in coast])
    lines = unary_union([lines, frame.exterior])
    seas = []
    coast_lines = [LineString(p) for p in coast]
    for face in polygonize(lines):
        if face.area < 1.0:
            continue
        side = _side_of_coast(face, coast_lines)
        if side == "sea":
            seas.append(face)
    if not seas:
        return None
    return unary_union(seas)


def _side_of_coast(face, coast_lines):
    """Whether a face of the cut-up box is sea: find a coastline segment on
    its edge and see which side of it the face lies. x runs east and z south,
    so seen on a map the right of a line walking (dx, dz) is (-dz, dx)."""
    edge = face.exterior
    for line in coast_lines:
        if not line.intersects(edge.buffer(0.01)):
            continue
        coords = list(line.coords)
        for (x0, z0), (x1, z1) in zip(coords, coords[1:]):
            mx, mz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
            if edge.distance(Point(mx, mz)) > 0.05:
                continue
            dx, dz = x1 - x0, z1 - z0
            length = (dx * dx + dz * dz) ** 0.5
            if length < 0.2:
                continue
            # The right of the walking direction, a little off the line.
            rx, rz = -dz / length, dx / length
            right = Point(mx + rx * 0.3, mz + rz * 0.3)
            left = Point(mx - rx * 0.3, mz - rz * 0.3)
            if face.contains(right):
                return "sea"
            if face.contains(left):
                return "land"
    return "unknown"


def areas(map_data):
    """Lakes, ponds, reservoirs and the areas of wide rivers, as Polygons
    (pools are left out: they're small and on private land)."""
    out = []
    for a in map_data.areas:
        tags = a["tags"]
        if tags.get("leisure") == "swimming_pool":
            continue
        if tags.get("natural") == "water" or tags.get("waterway") == "riverbank" or \
                tags.get("landuse") in ("reservoir", "basin"):
            for outer, inners in a["polys"]:
                try:
                    p = Polygon(outer, inners).buffer(0)
                except ValueError:
                    continue
                if not p.is_empty and p.area > 20.0:
                    out.append(p)
    return out
