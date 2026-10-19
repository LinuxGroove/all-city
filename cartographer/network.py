"""Streets, paths, steps, bridges and rail lines: their widths, how busy
they are, where the kerbs run, the lanes traffic drives in, and every flight
of steps cut into the hill.
"""
import math

from shapely.geometry import LineString, Point
from shapely.ops import unary_union

# Carriageway widths (m) by highway kind, used when the map gives none.
WIDTH = {"motorway": 14.0, "motorway_link": 7.0, "trunk": 12.0, "trunk_link": 7.0, "primary": 10.0,
         "primary_link": 6.5, "secondary": 9.0, "secondary_link": 6.0, "tertiary": 8.0, "tertiary_link": 6.0,
         "residential": 6.5, "unclassified": 6.0, "living_street": 5.0, "service": 4.5, "road": 6.0,
         "pedestrian": 6.0, "footway": 2.5, "path": 1.8, "cycleway": 2.2, "bridleway": 2.0, "track": 3.0,
         "steps": 2.4, "corridor": 2.0, "platform": 3.0}
# How busy each kind is, for the eyes score: how many people pass a wall.
WEIGHT = {"motorway": 1.0, "trunk": 0.9, "primary": 0.8, "secondary": 0.6, "tertiary": 0.45, "residential": 0.25,
          "unclassified": 0.2, "living_street": 0.2, "service": 0.1, "road": 0.2, "pedestrian": 0.55,
          "footway": 0.15, "path": 0.05, "cycleway": 0.1, "steps": 0.2, "track": 0.03, "platform": 0.4}
MOTOR = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary",
         "secondary_link", "tertiary", "tertiary_link", "residential", "unclassified", "living_street", "service",
         "road"}
RAIL = {"rail", "light_rail", "tram", "narrow_gauge", "subway", "monorail", "funicular"}
RAIL_WEIGHT = {"rail": 0.6, "light_rail": 0.5, "tram": 0.5, "narrow_gauge": 0.3, "subway": 0.4, "funicular": 0.3,
               "monorail": 0.4}
PAVEMENT = 2.5   # pavement beside a street with traffic
RISE = 0.17      # a step's height
MAX_GOING = 0.6  # longer than this and a flight gets a landing at the top


def _num(v, default):
    try:
        return float(str(v).split()[0].replace(",", "."))
    except (ValueError, IndexError):
        return default


def ways(map_data):
    """Every street, path, step and rail line, as dicts: line (LineString),
    kind, width, weight, motor, rail, bridge, tunnel, layer, oneway, name."""
    out = []
    for l in map_data.lines:
        tags = l["tags"]
        if len(l["pts"]) < 2:
            continue
        hw = tags.get("highway")
        rw = tags.get("railway")
        if hw and hw in WIDTH:
            kind = hw
            lanes = _num(tags.get("lanes"), 0)
            width = _num(tags.get("width"), lanes * 3.2 + 1.0 if lanes else WIDTH[hw])
            weight = WEIGHT.get(hw, 0.1)
            motor = hw in MOTOR
            rail = False
        elif rw in RAIL and tags.get("service") not in ("yard", "siding", "spur"):
            kind = rw
            width = 3.2 if rw not in ("tram",) else 2.8
            weight = RAIL_WEIGHT.get(rw, 0.3)
            motor = False
            rail = True
        else:
            continue
        if tags.get("indoor") == "yes" or tags.get("level", "0").startswith("-") or tags.get("location") == "underground":
            continue
        out.append({
            "id": l["id"], "line": LineString(l["pts"]), "kind": kind, "width": max(1.0, min(width, 40.0)),
            "weight": weight, "motor": motor, "rail": rail,
            "bridge": tags.get("bridge") not in (None, "no"), "tunnel": tags.get("tunnel") not in (None, "no") or
            tags.get("covered") == "yes",
            "layer": int(_num(tags.get("layer"), 0)), "oneway": tags.get("oneway") in ("yes", "1", "true") or
            tags.get("junction") == "roundabout", "name": tags.get("name", ""),
        })
    return out


def surface(ws, kinds="motor"):
    """The union of carriageways ("motor"), of everything walkable
    ("walk": pavements beside traffic, footways, squares) or of rail beds."""
    shapes = []
    for w in ws:
        if w["tunnel"] or w["bridge"]:
            continue
        if kinds == "motor" and w["motor"]:
            shapes.append(w["line"].buffer(w["width"] * 0.5, cap_style="flat", join_style="round"))
        elif kinds == "walk":
            if w["motor"]:
                shapes.append(w["line"].buffer(w["width"] * 0.5 + PAVEMENT, cap_style="round"))
            elif not w["rail"]:
                shapes.append(w["line"].buffer(w["width"] * 0.5, cap_style="round"))
        elif kinds == "rail" and w["rail"]:
            shapes.append(w["line"].buffer(w["width"] * 0.5 + 0.6, cap_style="flat"))
    return unary_union(shapes) if shapes else None


def kerbs(ws, areas_walk=None):
    """The kerb lines: the edge of the carriageways, as LineStrings, left
    out where a pedestrian area covers the street."""
    road = surface(ws, "motor")
    if road is None:
        return []
    edge = road.boundary
    if areas_walk is not None and not areas_walk.is_empty:
        edge = edge.difference(areas_walk)
    out = []
    for g in getattr(edge, "geoms", [edge]):
        if g.geom_type == "LineString" and g.length > 2.0:
            out.append(g)
        elif g.geom_type == "MultiLineString":
            out += [s for s in g.geoms if s.length > 2.0]
    return out


def lanes(ws, drive="right"):
    """Lane centrelines for traffic: one per direction (one for one-way
    streets), offset to the driving side, as lists of (x, z) points in the
    direction of travel. Tunnels are left out."""
    out = []
    side = 1.0 if drive == "right" else -1.0
    for w in ws:
        if not w["motor"] or w["tunnel"] or w["kind"] == "service":
            continue
        line = w["line"]
        if w["oneway"]:
            out.append({"pts": list(line.coords), "kind": w["kind"], "bridge": w["bridge"]})
            continue
        off = w["width"] * 0.25
        # shapely offsets to the left for positive distances in the math
        # sense (x right, y up); with z south that's the right of travel.
        fwd = line.offset_curve(off * side)
        back = LineString(list(line.coords)[::-1]).offset_curve(off * side)
        for g in (fwd, back):
            if not g.is_empty and g.geom_type == "LineString" and g.length > 4:
                out.append({"pts": list(g.coords), "kind": w["kind"], "bridge": w["bridge"]})
    return out


def flights(map_data, field, ws):
    """Every flight of steps, as straight runs between the map's points:
    bottom (x, y, z), up (dx, dz), steps, rise, going, run (the flight's
    length, then a landing to the next point) and width. Heights come from
    the land; `carve()` then shapes the land to match."""
    out = []
    for w in ws:
        if w["kind"] != "steps" or w["tunnel"]:
            continue
        pts = list(w["line"].coords)
        hs = [field.at(x, z) for x, z in pts]
        for (x0, z0), (x1, z1), h0, h1 in zip(pts, pts[1:], hs, hs[1:]):
            if h1 < h0:
                x0, z0, x1, z1, h0, h1 = x1, z1, x0, z0, h1, h0
            length = math.hypot(x1 - x0, z1 - z0)
            if length < 0.6:
                continue
            dh = h1 - h0
            steps = max(1, int(round(dh / RISE)))
            rise = dh / steps if dh > 0.05 else RISE
            if dh <= 0.05:
                steps = max(1, int(length / 0.4))
                rise = 0.0
            going = min(length / steps, MAX_GOING)
            out.append({"bottom": (x0, h0, z0), "up": ((x1 - x0) / length, (z1 - z0) / length), "steps": steps,
                        "rise": rise, "going": going, "length": length, "width": min(w["width"], 12.0),
                        "way": w["id"]})
    return out


def flight_height(f, s):
    """The height along a flight `s` metres from its bottom (the line the
    skater rolls on: up the steps, then level to the end)."""
    run = f["steps"] * f["going"]
    t = min(max(s / run, 0.0), 1.0) if run > 0 else 1.0
    return f["bottom"][1] + f["steps"] * f["rise"] * t


def carve(field, flights_list, margin=2.0):
    """Sets the land under and beside each flight to the flight's own
    slope, so the steps neither float nor sink."""
    import numpy as np
    for f in flights_list:
        bx, by, bz = f["bottom"]
        ux, uz = f["up"]
        half = f["width"] * 0.5 + margin
        x0 = min(bx, bx + ux * f["length"]) - half
        x1 = max(bx, bx + ux * f["length"]) + half
        z0 = min(bz, bz + uz * f["length"]) - half
        z1 = max(bz, bz + uz * f["length"]) + half
        i0 = max(0, int((x0 - field.x0) / field.cell))
        i1 = min(field.nx - 1, int((x1 - field.x0) / field.cell) + 1)
        j0 = max(0, int((z0 - field.z0) / field.cell))
        j1 = min(field.nz - 1, int((z1 - field.z0) / field.cell) + 1)
        for j in range(j0, j1 + 1):
            for i in range(i0, i1 + 1):
                px = field.x0 + i * field.cell - bx
                pz = field.z0 + j * field.cell - bz
                s = px * ux + pz * uz
                d = abs(-px * uz + pz * ux)
                if s < -margin or s > f["length"] + margin or d > half:
                    continue
                target = flight_height(f, s)
                blend = 1.0 if d <= f["width"] * 0.5 + 0.5 else max(0.0, 1.0 - (d - f["width"] * 0.5 - 0.5) / margin)
                field.h[j, i] = field.h[j, i] * (1 - blend) + target * blend
    return field


def bridges(field, ws):
    """Bridges with their decks' heights: straight from the land at one end
    to the land at the other, and never lower than 5.5 m over a street or
    rail it crosses (2.5 m over anything else)."""
    out = []
    under = [w["line"] for w in ws if not w["bridge"] and not w["tunnel"] and (w["motor"] or w["rail"])]
    for w in ws:
        if not w["bridge"]:
            continue
        pts = list(w["line"].coords)
        h0, h1 = field.at(*pts[0]), field.at(*pts[-1])
        total = w["line"].length
        pts3 = []
        s = 0.0
        prev = pts[0]
        for p in pts:
            s += math.hypot(p[0] - prev[0], p[1] - prev[1])
            prev = p
            t = s / total if total > 0 else 0.0
            y = h0 + (h1 - h0) * t
            ground = field.at(*p)
            clearance = 5.5 if any(Point(p).distance(u) < 6.0 for u in under) else 2.5
            if 0.0 < t < 1.0:
                y = max(y, ground + clearance * min(t, 1 - t) * 4.0 if min(t, 1 - t) < 0.25 else ground + clearance)
            pts3.append((p[0], y, p[1]))
        out.append({"pts": pts3, "width": w["width"], "kind": w["kind"], "rail": w["rail"], "motor": w["motor"]})
    return out
