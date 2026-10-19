"""Buildings: footprints into walls with storeys, a roof and the faces the
facade kit dresses.

Only a few buildings in the map carry a height, so the rest get storeys by
rule (3 m a storey): from their kind, their footprint, how built up the
streets round them are and their neighbours, seeded by their own id so every
copy of the town matches. A building on a slope stands on the lowest ground
along its outline and gets extra storeys below so its top is the same height
above the high side.

Faces are the outline's edges with near-straight runs merged, split where a
neighbour leans on them (the part above a lower neighbour still gets a
facade) and into lengths of at most six bays. Each face knows its ground
floor (shopfronts, homes or a plain wall), its way up (a drainpipe or a fire
escape) and how much of it may be painted. Ids come from the geometry,
never from the map: a building's from where it stands, a wall's from its
two ends.
"""
import math
import random

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.polygon import orient
from shapely.strtree import STRtree

from . import landmarks, respect
from .geo import stable_id, stable_seed

STOREY = 3.0
BAY = 2.0
MAX_BAYS = 6
MIN_FACE = 1.2
# Turns smaller than this along an outline are one face.
MERGE_DEG = 10.0
SIMPLIFY = 0.25
MIN_AREA = 12.0
# A neighbour this much lower leaves the upper part of a shared wall open.
OPEN_ABOVE = 1.5
MAX_PLINTH = 4

SKIP_KINDS = {"roof", "carport", "construction", "ruins", "no", "collapsed", "proposed", "destroyed",
              "demolished", "abandoned_construction", "canopy", "shelter_roof"}
KIND_STOREYS = {
    "house": (2, 2), "detached": (2, 3), "semidetached_house": (2, 2), "terrace": (2, 3), "bungalow": (1, 1),
    "farm": (2, 2), "cabin": (1, 1), "hut": (1, 1), "shed": (1, 1), "garage": (1, 1), "garages": (1, 1),
    "kiosk": (1, 1), "toilets": (1, 1), "service": (1, 1), "transformer_tower": (2, 2), "greenhouse": (1, 1),
    "barn": (2, 2), "farm_auxiliary": (1, 2), "boathouse": (1, 1), "static_caravan": (1, 1),
    "retail": (1, 2), "supermarket": (1, 2), "warehouse": (2, 3), "industrial": (2, 3), "hangar": (3, 4),
    "church": (4, 6), "chapel": (2, 3), "cathedral": (6, 8), "mosque": (3, 4), "temple": (2, 4),
    "school": (2, 4), "kindergarten": (1, 2), "hospital": (4, 8), "train_station": (2, 3),
    "apartments": (4, 8), "residential": (3, 6), "dormitory": (3, 5), "hotel": (5, 9), "office": (4, 10),
    "commercial": (2, 5), "civic": (2, 4), "public": (2, 4), "government": (3, 5), "university": (3, 5),
    "stadium": (4, 5), "grandstand": (2, 3), "parking": (2, 4), "fire_station": (2, 2),
}
WORKS_KINDS = {"industrial", "warehouse", "hangar", "manufacture", "factory", "garages", "parking", "service",
               "transformer_tower", "train_station"}
MODERN_KINDS = {"office", "commercial", "hotel", "hospital", "university", "supermarket", "retail"}
# Which kit a town's country gets, with the share of each style.
REGION_STYLES = {
    "brick": {"brick": 0.7, "plaster": 0.15, "modern": 0.15},
    "plaster": {"plaster": 0.75, "modern": 0.2, "brick": 0.05},
    "modern": {"modern": 0.5, "plaster": 0.4, "brick": 0.1},
}
COUNTRY_REGION = {
    "gb": "brick", "ie": "brick", "us": "brick", "ca": "brick", "nl": "brick", "be": "brick", "dk": "brick",
    "fr": "plaster", "mc": "plaster", "it": "plaster", "es": "plaster", "pt": "plaster", "gr": "plaster",
    "hr": "plaster", "mt": "plaster", "cy": "plaster", "mx": "plaster", "br": "plaster", "ar": "plaster",
}
# Streets whose ground floors are mostly shops.
SHOP_STREETS = {"primary": 0.55, "secondary": 0.5, "tertiary": 0.35, "pedestrian": 0.7, "living_street": 0.3,
                "residential": 0.12, "unclassified": 0.1}
STREET_KINDS = set(SHOP_STREETS) | {"trunk", "motorway", "service", "footway", "steps", "path", "cycleway",
                                    "primary_link", "secondary_link", "tertiary_link"}


def _num(v):
    try:
        return float(str(v).split()[0].replace(",", ".").rstrip("m"))
    except (ValueError, IndexError):
        return None


def footprints(map_data):
    """Every usable building outline: (Polygon oriented for faces, tags),
    cleaned of slivers and duplicate points."""
    out = []
    for b in map_data.buildings:
        tags = b["tags"]
        kind = tags.get("building", "yes")
        if kind in SKIP_KINDS or tags.get("location") == "underground":
            continue
        if landmarks.skip_building(tags):
            continue  # a landmark the game draws
        if (_num(tags.get("min_height")) or 0.0) > 2.0:
            continue  # an overhang or a bridge between buildings
        for outer, inners in b["polys"]:
            try:
                p = Polygon(outer, inners)
            except (ValueError, TypeError):
                continue
            p = p.buffer(0).simplify(SIMPLIFY, preserve_topology=True)
            parts = [p] if p.geom_type == "Polygon" else [g for g in getattr(p, "geoms", []) if g.geom_type == "Polygon"]
            for part in parts:
                if part.is_empty or part.area < MIN_AREA:
                    continue
                out.append((orient(part, -1.0), tags))
    return out


def _region(country):
    return REGION_STYLES[COUNTRY_REGION.get((country or "").lower(), "modern")]


def _pick(weights, rng):
    r = rng.random() * sum(weights.values())
    for k, w in weights.items():
        r -= w
        if r <= 0:
            return k
    return next(iter(weights))


def _ring_heights(field, ring, step=4.0):
    pts = []
    coords = list(ring.coords)
    for (x0, z0), (x1, z1) in zip(coords, coords[1:]):
        n = max(1, int(math.hypot(x1 - x0, z1 - z0) / step))
        for k in range(n):
            t = k / n
            pts.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t))
    xs = np.array([p[0] for p in pts])
    zs = np.array([p[1] for p in pts])
    return np.atleast_1d(field.at(xs, zs))


def _zone_of(zones, poly):
    c = poly.representative_point()
    for kind, z in zones:
        if z.contains(c):
            return kind
    return ""


def zones(map_data):
    """Land use areas as (kind, prepared polygon), for homes and shops."""
    from shapely.prepared import prep
    out = []
    for a in map_data.areas:
        lu = a["tags"].get("landuse")
        if lu not in ("residential", "retail", "commercial", "industrial"):
            continue
        for outer, inners in a["polys"]:
            try:
                p = Polygon(outer, inners).buffer(0)
            except (ValueError, TypeError):
                continue
            if not p.is_empty:
                out.append((lu, prep(p)))
    return out


def rule_storeys(area, dense, rng):
    """Storeys for an untagged building from its footprint and how built up
    the streets round it are (0 to 1)."""
    if area < 30:
        lo, hi = 1, 1
    elif area < 80:
        lo, hi = 1, 3
    elif area < 200:
        lo, hi = 2, 4
    elif area < 600:
        lo, hi = 3, 6
    elif area < 2000:
        lo, hi = 4, 8
    else:
        lo, hi = 3, 7
    if area >= 120:
        lo += int(round(dense * 2))
        hi += int(round(dense * 5))
    return rng.randint(lo, hi)


def measured(feet, survey):
    """Footprints as a lidar survey saw them: a footprint whose roof steps
    becomes one footprint per part, each with its measured top and roof.
    Returns [(poly, tags, part or None)]: None where the survey can't say
    (built since, or hidden under trees), which keeps the rules."""
    from . import lidar
    out = []
    for poly, tags in feet:
        ground = float(np.min(survey.ground_at(*np.asarray(poly.exterior.coords).T)))
        parts = lidar.measure(survey, poly, ground)
        if not parts:
            out.append((poly, tags, None))
            continue
        for part in parts:
            g = part["poly"]
            if len(parts) > 1:
                g = g.buffer(0).simplify(SIMPLIFY, preserve_topology=True)
                if g.geom_type != "Polygon" or g.area < MIN_AREA:
                    continue
                g = orient(g, -1.0)
            out.append((g, tags, part))
    return out


def build(map_data, field, ways, proj, country="", places=None, survey=None):
    """Every building as a dict ready for its tile (see docs/tiles.md):
    id, rings, tris, y0, top, storeys, style, seed, paint, kind, props,
    faces and, for a pitched roof, roof. `ways` are network.ways();
    `places` a respect.Places; `survey` a lidar.Survey, whose measured
    heights and roofs replace the rules wherever it saw a building."""
    places = places or respect.Places(map_data)
    feet = footprints(map_data)
    if not feet:
        return []
    parts = measured(feet, survey) if survey is not None else [(p, t, None) for p, t in feet]
    feet = [(p, t) for p, t, _ in parts]
    polys = [p for p, _ in feet]
    tree = STRtree(polys)
    zone_list = zones(map_data)
    region = _region(country)
    streets = [w for w in ways if (w["kind"] in STREET_KINDS) and not w["tunnel"]]
    street_tree = STRtree([w["line"] for w in streets]) if streets else None

    # How built up each building's surroundings are: the share of a circle
    # of 80 m round it covered by buildings.
    cents = shapely.points([(p.centroid.x, p.centroid.y) for p in polys])
    areas = np.array([p.area for p in polys])
    near = tree.query(shapely.buffer(cents, 80.0), predicate="intersects")
    covered = np.zeros(len(polys))
    np.add.at(covered, near[0], areas[near[1]])
    dense = np.clip(covered / (math.pi * 80.0 ** 2) / 0.45, 0.0, 1.0)

    recs = []
    for k, (poly, tags) in enumerate(feet):
        c = poly.centroid
        lat, lon = proj.latlon(c.x, c.y)
        bid = stable_id(round(lat, 5), round(lon, 5), int(poly.area), prefix="b")
        seed = stable_seed(bid) & 0x7FFFFFFF
        rng = random.Random(seed)
        kind = tags.get("building", "yes")
        tagged = None
        part = parts[k][2]
        if part is not None:
            tagged = max(1, int(round((part["top"] - float(field.at(c.x, c.y))) / STOREY)))
        elif "building:levels" in tags and _num(tags["building:levels"]):
            tagged = max(1, int(round(_num(tags["building:levels"]) + (_num(tags.get("roof:levels")) or 0) * 0.5)))
        elif "height" in tags and _num(tags["height"]):
            tagged = max(1, int(round(_num(tags["height"]) / STOREY)))
        if tagged is None and kind in KIND_STOREYS:
            lo, hi = KIND_STOREYS[kind]
            storeys = rng.randint(lo, hi)
        elif tagged is None:
            storeys = rule_storeys(poly.area, float(dense[k]), rng)
        else:
            storeys = tagged
        recs.append({"poly": poly, "tags": tags, "kind": kind, "id": bid, "seed": seed, "rng": rng,
                     "storeys": min(storeys, 60), "tagged": tagged is not None,
                     "measured": part["top"] if part else None, "roof": part["roof"] if part else None})

    # Untagged buildings lean towards their neighbours' heights, so a street
    # reads as a street.
    near = tree.query(shapely.buffer(cents, 25.0), predicate="intersects")
    by = {}
    for i, j in zip(near[0], near[1]):
        if i != j:
            by.setdefault(int(i), []).append(recs[int(j)]["storeys"])
    for i, r in enumerate(recs):
        if not r["tagged"] and r["kind"] not in KIND_STOREYS and i in by:
            r["storeys"] = max(1, int(round(0.6 * r["storeys"] + 0.4 * float(np.median(by[i])))))

    for r in recs:
        poly = r["poly"]
        hs = _ring_heights(field, poly.exterior)
        lo, hi = float(hs.min()), float(hs.max())
        plinth = min(MAX_PLINTH, max(0, int(math.ceil((hi - lo - 0.6) / STOREY))))
        r["y0"] = lo
        if r["measured"] is not None:
            # Measured walls reach their own height above the low side.
            r["total"] = min(60, max(1, int(round((r["measured"] - lo) / STOREY))))
            r["storeys"] = r["total"]
        else:
            r["total"] = r["storeys"] + plinth
        r["top"] = lo + r["total"] * STOREY
        kind = r["kind"]
        if kind in WORKS_KINDS:
            style = "works"
        elif kind in MODERN_KINDS or r["storeys"] >= 9:
            style = "modern" if r["rng"].random() < 0.75 else _pick(region, r["rng"])
        else:
            style = _pick(region, r["rng"])
        r["style"] = style
        zone = _zone_of(zone_list, poly)
        inside = places.points_in(poly)
        paint, shops = respect.judge(r["tags"], inside, places.in_respect_land(poly), zone)
        r["paint"], r["shops"], r["zone"] = paint, shops, zone

    out = []
    for i, r in enumerate(recs):
        faces = _faces(i, r, recs, tree, field, streets, street_tree, proj)
        # Shops by rule on busy streets make an untagged block a home over
        # shops: its upper floors are someone's flat.
        if r["paint"] == respect.ALL and r["kind"] in ("yes", "residential", "apartments") and r["storeys"] >= 4 and \
                any(f["ground"] == "shop" for f in faces):
            r["paint"] = respect.GROUND
        _ways_up(r, faces)
        for f in faces:
            f["paint"] = r["paint"]
            f["paint_top"] = f["base"] + STOREY if r["paint"] == respect.GROUND else r["top"]
        rings, tris = _roof(r["poly"])
        rec = {
            "id": r["id"], "rings": rings, "tris": tris, "y0": r["y0"], "top": r["top"], "storeys": r["total"],
            "style": r["style"], "seed": r["seed"], "paint": r["paint"], "kind": r["kind"],
            "props": [] if r["roof"] else _roof_props(r), "faces": faces, "poly": r["poly"],
            "measured": r["measured"] is not None,
        }
        if r["roof"]:
            verts, tris, walls = pitched(r["poly"], r["top"], r["roof"])
            if tris:
                rec["roof"] = dict(r["roof"], verts=verts, tris=tris, walls=walls)
            else:
                rec["props"] = _roof_props(r)
        out.append(rec)
    return out


def _street_front(mid, out, streets, street_tree):
    """The busiest street in front of a face within 16 m, or None."""
    if street_tree is None:
        return None
    probe = Point(mid[0] + out[0] * 5.0, mid[1] + out[1] * 5.0)
    best = None
    for j in street_tree.query(probe.buffer(11.0)):
        w = streets[int(j)]
        p = w["line"].interpolate(w["line"].project(probe))
        dx, dz = p.x - mid[0], p.y - mid[1]
        d = math.hypot(dx, dz)
        if d > 16.0 or d < 0.5 or (dx * out[0] + dz * out[1]) / d < 0.35:
            continue
        if best is None or w["weight"] > best["weight"]:
            best = w
    return best


def _faces(i, r, recs, tree, field, streets, street_tree, proj):
    poly = r["poly"]
    faces = []
    rings = [poly.exterior] + list(poly.interiors)
    for ring in rings:
        pts = _merged(list(ring.coords)[:-1])
        n = len(pts)
        for k in range(n):
            a, b = pts[k], pts[(k + 1) % n]
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            if length < MIN_FACE:
                continue
            d = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
            out = (-d[1], d[0])
            for run in _runs(i, r, recs, tree, a, d, out, length):
                faces += _segments(r, run, a, d, out, field, streets, street_tree, proj)
    return faces


def _merged(pts):
    """An outline's corners with the near-straight ones dropped."""
    changed = True
    while changed and len(pts) > 3:
        changed = False
        for k in range(len(pts)):
            p0, p1, p2 = pts[k - 1], pts[k], pts[(k + 1) % len(pts)]
            a0 = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
            a1 = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
            turn = abs((a1 - a0 + math.pi) % (2 * math.pi) - math.pi)
            if math.degrees(turn) < MERGE_DEG:
                pts.pop(k)
                changed = True
                break
    return pts


def _runs(i, r, recs, tree, a, d, out, length):
    """A face split where neighbours lean on it: (s0, s1, base) runs, base
    being the height the open wall starts at (the neighbour's top, or None
    on open ground). Fully covered parts are left out."""
    bays = max(1, int(round(length / BAY)))
    step = length / bays
    probes = [Point(a[0] + d[0] * step * (k + 0.5) + out[0] * 0.6, a[1] + d[1] * step * (k + 0.5) + out[1] * 0.6)
              for k in range(bays)]
    hits = tree.query(probes, predicate="within")
    lean = [None] * bays
    for pk, j in zip(hits[0], hits[1]):
        if int(j) == i:
            continue
        t = recs[int(j)]["top"]
        if lean[pk] is None or t > lean[pk]:
            lean[pk] = t
    runs = []
    for k in range(bays):
        base = lean[k]
        if base is not None and base >= r["top"] - OPEN_ABOVE:
            key = "hidden"
        else:
            key = base
        if runs and runs[-1][2] == key:
            runs[-1][1] = (k + 1) * step
        else:
            runs.append([k * step, (k + 1) * step, key])
    return [(s0, s1, key) for s0, s1, key in runs if key != "hidden"]


def _segments(r, run, a, d, out, field, streets, street_tree, proj):
    s0, s1, lean = run
    length = s1 - s0
    n = max(1, int(math.ceil(length / (BAY * MAX_BAYS) - 1e-6)))
    faces = []
    for k in range(n):
        t0 = s0 + length * k / n
        t1 = s0 + length * (k + 1) / n
        p0 = (a[0] + d[0] * t0, a[1] + d[1] * t0)
        p1 = (a[0] + d[0] * t1, a[1] + d[1] * t1)
        mid = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5)
        if lean is not None:
            storeys = int((r["top"] - lean) // STOREY)
            if storeys < 1:
                continue
            base = r["top"] - storeys * STOREY
            ground = "upper"
            street = None
        else:
            ground_h = float(np.min(field.at(np.array([p0[0], mid[0], p1[0]]), np.array([p0[1], mid[1], p1[1]]))))
            storeys = max(1, int((r["top"] - ground_h) / STOREY + 0.3))
            base = r["top"] - storeys * STOREY
            street = _street_front(mid, out, streets, street_tree)
            ground = _ground(r, street)
        la, oa = proj.latlon(*p0)
        lb, ob = proj.latlon(*p1)
        wid = stable_id(round(la, 5), round(oa, 5), round(lb, 5), round(ob, 5))
        faces.append({
            "id": wid, "p0": (p0[0], base, p0[1]), "p1": (p1[0], base, p1[1]), "base": base, "storeys": storeys,
            "ground": ground, "seed": stable_seed(wid) & 0x7FFFFFFF, "ends": [1 if (k == 0 and t0 == 0.0) else 0, 0],
            "street": street["weight"] if street else 0.0, "street_kind": street["kind"] if street else "",
            "pipe": -1, "escape": -1, "out": out, "length": t1 - t0,
        })
    return faces


def _ground(r, street):
    """What a face's ground floor is: shops, a home's windows or a plain wall."""
    if street is None:
        return "blank"
    if r["paint"] == respect.NONE and r["kind"] not in ("yes", "residential", "apartments"):
        return "blank"
    p = SHOP_STREETS.get(street["kind"], 0.0)
    if r["zone"] in ("retail", "commercial"):
        p = max(p, 0.6)
    if r["zone"] == "industrial":
        p *= 0.3
    if r["shops"] or r["rng"].random() < p * (0.6 + 0.4 * min(1.0, r["storeys"] / 4.0)):
        return "shop"
    return "home" if r["kind"] not in WORKS_KINDS else "blank"


def _ways_up(r, faces):
    """Drainpipes and fire escapes: every building of two storeys or more
    gets at least one way to its roof, on its busiest open face."""
    open_faces = [f for f in faces if f["ground"] != "upper"]
    if r["total"] < 2 or not open_faces:
        return
    rng = r["rng"]
    escapes = r["style"] in ("brick", "works")
    for f in open_faces:
        bays = max(1, int(round(f["length"] / BAY)))
        if escapes and f["storeys"] >= 3 and bays >= 3 and rng.random() < 0.35:
            f["escape"] = rng.randint(1, bays - 2)
        elif bays >= 2 and rng.random() < 0.25:
            f["pipe"] = rng.randint(1, bays - 1)
    if not any(f["pipe"] >= 0 or f["escape"] >= 0 for f in open_faces):
        best = max(open_faces, key=lambda f: (f["street"], f["length"]))
        bays = max(1, int(round(best["length"] / BAY)))
        if bays >= 2:
            best["pipe"] = rng.randint(1, bays - 1)


def _roof(poly):
    """The outline's rings (outer first, as float32 (n, 2) arrays without
    the closing point) and the roof's triangles as indices into them, each
    turning anticlockwise seen from above with z south."""
    exact = [list(poly.exterior.coords)[:-1]] + [list(r.coords)[:-1] for r in poly.interiors]
    rings = [np.asarray(ring, dtype=np.float32) for ring in exact]
    index = {}
    base = 0
    for ring in exact:
        for k, (x, z) in enumerate(ring):
            index[(round(x, 3), round(z, 3))] = base + k
        base += len(ring)
    tris = []
    try:
        tri = shapely.constrained_delaunay_triangles(poly)
    except Exception:
        tri = None
    for t in getattr(tri, "geoms", []):
        cs = list(t.exterior.coords)[:3]
        ids = [index.get((round(x, 3), round(z, 3))) for x, z in cs]
        if None in ids:
            continue
        (x0, z0), (x1, z1), (x2, z2) = cs
        # Anticlockwise on the map (z south) is clockwise in maths terms.
        if (x1 - x0) * (z2 - z0) - (z1 - z0) * (x2 - x0) > 0:
            ids = [ids[0], ids[2], ids[1]]
        tris += ids
    return rings, np.asarray(tris, dtype=np.int32)


def _roof_props(r):
    """Vents, tanks and huts on flat roofs, inside the parapet."""
    poly = r["poly"]
    inner = poly.buffer(-1.6)
    if inner.is_empty or r["total"] < 2:
        return []
    rng = random.Random(r["seed"] ^ 0x5A5A)
    rect = poly.minimum_rotated_rectangle
    cs = list(rect.exterior.coords)
    yaw = math.atan2(cs[1][1] - cs[0][1], cs[1][0] - cs[0][0]) if len(cs) > 2 else 0.0
    count = min(5, int(poly.area / 120.0))
    if count == 0 and poly.area > 40:
        count = 1
    minx, minz, maxx, maxz = inner.bounds
    props = []
    hut = r["total"] >= 4 and poly.area > 150
    for _ in range(count * 6):
        if len(props) >= count:
            break
        x, z = rng.uniform(minx, maxx), rng.uniform(minz, maxz)
        if not inner.contains(Point(x, z)):
            continue
        if any(math.hypot(x - p["p"][0], z - p["p"][2]) < 3.0 for p in props):
            continue
        if hut:
            model, hut = "facade/roof_hut", False
        elif r["total"] >= 5 and rng.random() < 0.4:
            model = "facade/roof_tank"
        else:
            model = "facade/roof_vent"
        props.append({"m": model, "p": (x, r["top"], z), "yaw": yaw + (math.pi / 2) * rng.randint(0, 3)})
    return props


def pitched(poly, top, roof):
    """A pitched roof's mesh over a footprint: the facets of a gable or hip
    roof over the footprint's oriented rectangle (ridge along
    `roof["along"]`), cut to the outline. Returns (verts, tris, walls):
    verts as (x, y, z) in town metres, tris three indices a triangle wound
    anticlockwise seen from above, and walls a flat list of (x, y, z)
    triangles closing the gap between the eaves at `top` and the roof (the
    gable ends, and wherever the outline cuts into the rectangle)."""
    a = float(roof["along"])
    ua = (math.cos(a), math.sin(a))
    va = (-ua[1], ua[0])
    pts = np.asarray(poly.exterior.coords)[:-1]
    us = pts[:, 0] * ua[0] + pts[:, 1] * ua[1]
    vs = pts[:, 0] * va[0] + pts[:, 1] * va[1]
    u0, u1, v0, v1 = float(us.min()), float(us.max()), float(vs.min()), float(vs.max())
    uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
    half_l, half_w = (u1 - u0) * 0.5, (v1 - v0) * 0.5
    rise = float(roof["rise"])
    slope = rise / max(half_w, 0.5)

    def world(u, v):
        return (u * ua[0] + v * va[0], u * ua[1] + v * va[1])

    # Each facet: its outline in (u, v) and the height of its plane there.
    facets = [
        ([(u0, v0), (u1, v0), (u1, vc), (u0, vc)], lambda u, v: (v - v0) * slope),
        ([(u0, vc), (u1, vc), (u1, v1), (u0, v1)], lambda u, v: (v1 - v) * slope),
    ]
    if roof["shape"] == "hip" and half_l > half_w * 0.5:
        inset = min(half_w, half_l)
        r0, r1 = u0 + inset, u1 - inset
        facets = [
            ([(u0, v0), (u1, v0), (r1, vc), (r0, vc)], lambda u, v: (v - v0) * slope),
            ([(r0, vc), (r1, vc), (u1, v1), (u0, v1)], lambda u, v: (v1 - v) * slope),
            ([(u0, v0), (r0, vc), (u0, v1)], lambda u, v: (u - u0) * slope),
            ([(u1, v0), (u1, v1), (r1, vc)], lambda u, v: (u1 - u) * slope),
        ]
    verts, tris, walls = [], [], []
    for outline, height in facets:
        face = Polygon([world(u, v) for u, v in outline]).buffer(0)
        piece = poly.intersection(face).buffer(0)
        for g in (piece.geoms if hasattr(piece, "geoms") else [piece]):
            if g.geom_type != "Polygon" or g.area < 0.05:
                continue

            def h(x, z):
                return top + max(0.0, height(x * ua[0] + z * ua[1], x * va[0] + z * va[1]))
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
                    verts.append((x, h(x, z), z))
                tris += [base, base + 1, base + 2]
            # Walls under the roof where this piece's edge is the outline.
            ring = list(g.exterior.coords)
            for (xa, za), (xb, zb) in zip(ring, ring[1:]):
                mid = Point((xa + xb) * 0.5, (za + zb) * 0.5)
                if poly.exterior.distance(mid) > 0.01:
                    continue
                ha, hb = h(xa, za), h(xb, zb)
                if max(ha, hb) - top < 0.05:
                    continue
                quad = [(xa, top, za), (xb, top, zb), (xb, hb, zb), (xa, ha, za)]
                walls += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
    return verts, tris, walls
