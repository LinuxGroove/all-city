"""Landmarks: the things a town is known by, from the map's own tags and,
where there's a survey, measured to size.

Kinds the game draws (see docs/tiles.md):

- `ballpark`: a baseball pitch (`leisure=pitch` + `sport=baseball`) big
  enough for a real game, with its stadium where the map has one: the
  diamond, the outfield wall, foul poles, lights, a scoreboard and stands.
- `water_tower`, `smokestack`: a tank on legs and a chimney
  (`man_made=water_tower`, `man_made=chimney`), scaled to their height.
- `statue`: a statue or monument the kit has a model for (a bull, so far).
- `spire`: a steeple on a place of worship whose survey shows a tower.
- `stand`: a grandstand (`building=grandstand`), its outline drawn as rows
  of seats rising away from the pitch it looks at, to its measured height.

A few landmarks have more to them than their kind says; `SPECIAL` adds that
by the map's Wikidata id, which is stable across map edits and names.
Water towers, chimneys and grandstands mapped as buildings are taken out
of the buildings (`skip_building`), so they aren't drawn twice.
"""
import math

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.polygon import orient

from .geo import stable_seed

BALLPARK_MIN = 6000.0   # square metres of field for a ballpark with stands
STATUE_MODELS = {"bull": "landmark/bull_statue"}
# The models' own sizes (tools/blender/landmarks.py), which instances are
# scaled from.
STAND_HEIGHT = 8.0     # a grandstand's back, with no survey
STAND_ROW = 1.6        # how deep a grandstand's rows are
HEIGHTS = {"landmark/water_tower": 40.0, "landmark/smokestack": 33.0, "landmark/spire": 14.0}
SPECIAL = {
    # Durham Bulls Athletic Park: the Blue Monster, a 32 ft wall in left
    # field with the bull on top, and the scoreboard under it.
    "Q3041567": {"wall": 2.4, "monster": {"side": "left", "height": 9.8, "colour": "civic_blue"},
                 "bull_sign": True, "canopy": True},
    # Durham Athletic Park, the Bulls' old ground (the one in the film).
    "Q5316463": {"wall": 3.0, "bull_sign": True, "wall_colour": "iron_green"},
}


def skip_building(tags):
    """Whether a building outline is really a landmark the game draws."""
    return tags.get("man_made") in ("water_tower", "chimney") or tags.get("building") == "grandstand"


def find(map_data, field, survey=None, buildings=None):
    """Every landmark in the map: dicts ready for their tile."""
    out = []
    stadiums = []
    for a in map_data.areas:
        t = a["tags"]
        if t.get("leisure") == "stadium":
            for outer, inners in a["polys"]:
                try:
                    stadiums.append((Polygon(outer, inners).buffer(0), t))
                except (ValueError, TypeError):
                    pass
    for a in map_data.areas:
        t = a["tags"]
        if t.get("leisure") == "pitch" and t.get("sport") == "baseball":
            for outer, _ in a["polys"]:
                park = _ballpark(outer, t, stadiums, field)
                if park:
                    out.append(park)
        elif t.get("man_made") in ("water_tower", "chimney"):
            for outer, _ in a["polys"]:
                out.append(_tower(t, Polygon(outer).centroid, field, survey, Polygon(outer)))
    for b in map_data.buildings:
        t = b["tags"]
        if t.get("man_made") in ("water_tower", "chimney"):
            for outer, _ in b["polys"]:
                out.append(_tower(t, Polygon(outer).centroid, field, survey, Polygon(outer)))
    for p in map_data.points:
        t = p["tags"]
        if t.get("man_made") in ("water_tower", "chimney"):
            out.append(_tower(t, Point(p["x"], p["z"]), field, survey, None))
        elif t.get("tourism") == "artwork" and t.get("artwork_type") in ("statue", "sculpture") or \
                t.get("historic") in ("monument", "memorial"):
            name = t.get("name", "").lower()
            for word, model in STATUE_MODELS.items():
                if word in name:
                    out.append({"kind": "statue", "m": model, "name": t.get("name", ""),
                                "p": (p["x"], float(field.at(p["x"], p["z"])), p["z"]),
                                "yaw": (stable_seed(p["id"]) % 628) / 100.0, "s": 1.0})
    pitches = [Polygon(o).buffer(0) for a in map_data.areas if a["tags"].get("leisure") in ("pitch", "stadium")
               for o, _ in a["polys"]]
    for b in map_data.buildings:
        if b["tags"].get("building") == "grandstand":
            for outer, _ in b["polys"]:
                out.append(_stand(outer, pitches, field, survey))
    if survey is not None and buildings is not None:
        out += _spires(map_data, survey, buildings)
    # One landmark per place: a tower mapped as an area and a point is one.
    kept = []
    for lm in out:
        if lm is None:
            continue
        if lm["kind"] in ("water_tower", "smokestack") and any(
                k["kind"] == lm["kind"] and math.hypot(k["p"][0] - lm["p"][0], k["p"][2] - lm["p"][2]) < 8.0
                for k in kept):
            continue
        kept.append(lm)
    return kept


def _tower(tags, at, field, survey, outline):
    kind = "water_tower" if tags.get("man_made") == "water_tower" else "smokestack"
    model = "landmark/" + kind
    x, z = at.x, at.y
    ground = float(field.at(x, z))
    h = None
    if survey is not None:
        poly = outline if outline is not None and outline.area > 4 else Point(x, z).buffer(3.0)
        ii, jj = survey.cells_in(poly, shrink=0.0)
        if len(ii):
            h = float(np.max(survey.surface[jj, ii])) - ground
    if h is None or h < 6.0:
        try:
            h = float(str(tags.get("height", "")).split()[0])
        except (ValueError, IndexError):
            h = HEIGHTS[model]
    h = max(8.0, min(h, 90.0))
    return {"kind": kind, "m": model, "name": tags.get("name", ""), "p": (x, ground, z),
            "yaw": (stable_seed(round(x), round(z)) % 628) / 100.0, "s": round(h / HEIGHTS[model], 3)}


def covers(found):
    """The ground landmarks take up (a ballpark's field, a stand's rows),
    where nothing else (trees) should stand."""
    out = []
    for lm in found:
        if lm["kind"] == "ballpark":
            out.append(Polygon([(p[0], p[2]) for p in lm["field"]]).buffer(2.0))
        elif lm["kind"] == "stand":
            v, t = lm["verts"], lm["tris"]
            out.append(shapely.union_all([Polygon([(v[t[k + n]][0], v[t[k + n]][2]) for n in range(3)]).buffer(0.05)
                                          for k in range(0, len(t), 3)]).buffer(1.0))
    return out


def _stand(outer, pitches, field, survey):
    """A grandstand: rows rising away from the nearest pitch (or from its
    long side when there's none) to its measured height, as terraces."""
    try:
        poly = Polygon(outer).buffer(0)
    except (ValueError, TypeError):
        return None
    if poly.is_empty or poly.area < 20.0 or poly.geom_type != "Polygon":
        return None
    poly = orient(poly.simplify(0.3), 1.0)
    c = poly.centroid
    ground = float(field.at(c.x, c.y))
    near = [p for p in pitches if p.distance(c) < 200.0 and not p.contains(c)]
    if near:
        front = min(near, key=lambda q: q.distance(c))
    else:
        r = list(poly.minimum_rotated_rectangle.exterior.coords)
        sides = [LineString([r[k], r[k + 1]]) for k in range(4)]
        front = max(sides, key=lambda e: e.length)
    h = None
    if survey is not None:
        ii, jj = survey.cells_in(poly, shrink=0.0)
        if len(ii) > 10:
            # The back of a stand is its highest row; the 95th percentile
            # leaves out light poles and flags.
            h = float(np.percentile(survey.surface[jj, ii], 95)) - ground
    if h is None or h < 2.0:
        h = STAND_HEIGHT
    h = min(max(h, 3.0), 30.0)
    verts, tris, walls, rows = _terraces(poly, front, ground, h)
    if not tris:
        return None
    return {"kind": "stand", "name": "", "p": (c.x, ground, c.y), "height": round(h, 2),
            "verts": verts, "tris": tris, "walls": walls, "rows": rows}


def _terraces(poly, front, ground, h):
    """Rows `STAND_ROW` deep across `poly`, each a step higher the farther
    it is from `front`: (verts, tris, walls, rows) as `pitched()` gives a
    roof, with `rows` the lip of each row as [(x, y, z), ...] lines."""
    d0 = poly.distance(front)
    far = max(Point(x, z).distance(front) for x, z in poly.exterior.coords)
    n = max(1, int(math.ceil((far - d0) / STAND_ROW)))
    step = h / n
    verts, tris, walls, rows = [], [], [], []
    lower = None
    for k in range(n):
        y = ground + step * (k + 1)
        band = poly.intersection(front.buffer(d0 + STAND_ROW * (k + 1), 8))
        if lower is not None:
            band = band.difference(lower)
        lower = poly.intersection(front.buffer(d0 + STAND_ROW * (k + 1) + 0.001, 8))
        for g in (band.geoms if hasattr(band, "geoms") else [band]):
            if g.geom_type != "Polygon" or g.area < 0.05:
                continue
            try:
                tri = shapely.constrained_delaunay_triangles(g)
            except Exception:
                continue
            for t in getattr(tri, "geoms", []):
                cs = list(t.exterior.coords)[:3]
                (x0, z0), (x1, z1), (x2, z2) = cs
                if (x1 - x0) * (z2 - z0) - (z1 - z0) * (x2 - x0) > 0:
                    cs = [cs[0], cs[2], cs[1]]
                base = len(verts)
                for x, z in cs:
                    verts.append((x, y, z))
                tris += [base, base + 1, base + 2]
            # Risers: down to the ground on the outline, down a row inside.
            ring = list(g.exterior.coords)
            for (xa, za), (xb, zb) in zip(ring, ring[1:]):
                if math.hypot(xb - xa, zb - za) < 0.05:
                    continue
                mid = Point((xa + xb) * 0.5, (za + zb) * 0.5)
                outside = poly.exterior.distance(mid) < 0.02
                if not outside and mid.distance(front) > d0 + STAND_ROW * (k + 0.5):
                    continue  # the row behind's riser
                y0 = ground - 1.5 if outside else y - step
                quad = [(xa, y0, za), (xb, y0, zb), (xb, y, zb), (xa, y, za)]
                walls += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
                if not outside and math.hypot(xb - xa, zb - za) > 0.5:
                    rows.append([(xa, y, za), (xb, y, zb)])
    return verts, tris, walls, _join(rows)


def _join(segments):
    """Segments end to end as longer lines (a row's lip comes in pieces)."""
    lines = []
    for a, b in segments:
        for line in lines:
            if math.dist(line[-1], a) < 0.05:
                line.append(b)
                break
            if math.dist(line[0], b) < 0.05:
                line.insert(0, a)
                break
        else:
            lines.append([a, b])
    return [line for line in lines if sum(math.dist(p, q) for p, q in zip(line, line[1:])) > 3.0]


def _ballpark(outer, tags, stadiums, field):
    field_poly = Polygon(outer).buffer(0)
    if field_poly.is_empty or field_poly.area < BALLPARK_MIN:
        return None
    pts = list(field_poly.exterior.coords)[:-1]
    if len(pts) < 3:
        return None
    # Home plate is the corner nearest everything else: from the apex of a
    # fan the farthest point is the fence; from a foul corner it's the other
    # foul corner, farther still.
    arr = np.asarray(pts)
    far = [float(np.max(np.hypot(*(arr - p).T))) for p in arr]
    home = arr[int(np.argmin(far))]
    c = field_poly.centroid
    yaw = math.atan2(c.x - home[0], c.y - home[1])
    stadium, stags = None, {}
    for s, st in stadiums:
        if s.intersects(field_poly.buffer(-5.0)):
            stadium, stags = s, st
            break
    wid = stags.get("wikidata") or tags.get("wikidata", "")
    special = SPECIAL.get(wid, {})
    hx, hz = float(home[0]), float(home[1])
    ring = [(float(x), float(field.at(x, z)), float(z)) for x, z in pts]
    rec = {
        "kind": "ballpark", "name": stags.get("name") or tags.get("name", ""),
        "home": (hx, float(field.at(hx, hz)), hz), "yaw": yaw, "field": ring,
        "big": bool(stadium is not None or field_poly.area > BALLPARK_MIN * 1.5),
    }
    if stadium is not None:
        rec["stadium"] = [(float(x), float(field.at(x, z)), float(z)) for x, z in list(stadium.exterior.coords)[:-1]]
    rec.update(special)
    return rec


def _spires(map_data, survey, built):
    """Steeples on places of worship whose survey shows a narrow tower
    standing well over the roof."""
    out = []
    worship = []
    for b in map_data.buildings:
        if b["tags"].get("amenity") == "place_of_worship" or b["tags"].get("building") in ("church", "chapel",
                                                                                           "cathedral"):
            for outer, _ in b["polys"]:
                try:
                    worship.append(Polygon(outer).buffer(0))
                except (ValueError, TypeError):
                    pass
    for poly in worship:
        ii, jj = survey.cells_in(poly, shrink=0.0)
        if len(ii) < 20:
            continue
        hs = survey.surface[jj, ii]
        k = int(np.argmax(hs))
        peak, roof = float(hs[k]), float(np.percentile(hs, 70))
        # A tower: a few cells far over the rest.
        if peak - roof < 6.0 or (hs > roof + 4.0).sum() > 60:
            continue
        x = survey.x0 + (ii[k] + 0.5) * survey.cell
        z = survey.z0 + (jj[k] + 0.5) * survey.cell
        # Stands on the building part under the peak, at its top.
        top = None
        for b in built:
            if b["poly"].contains(Point(x, z)):
                top = float(b["top"]) + 0.6
                break
        if top is None or peak - top < 4.0:
            continue
        out.append({"kind": "spire", "m": "landmark/spire", "name": "", "p": (x, top, z),
                    "yaw": 0.0, "s": round(min(2.0, max(0.5, (peak - top) / HEIGHTS["landmark/spire"])), 3)})
    return out
