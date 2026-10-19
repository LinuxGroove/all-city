"""The lines a skater rides: kerbs, fences and walls along their tops,
railway rails, power lines between their poles and bridge parapets. Each is
a dict {"kind", "pts": [(x, y, z), ...], ...}; the game builds what stands
under a line (a kerb, a fence, a wall, the sleepers) from its kind.

Handrails and copings on steps and the ways up walls aren't here: the game
lays those with the steps and the facades, from the same numbers.
"""
import math

import numpy as np
from shapely.geometry import LineString, Point

KERB = 0.14
GAUGE = 1.435
RAIL_TOP = 0.2
POLE_TOP = 8.66
WIRE_SPREAD = 0.85
# How far a wire sags at the middle of a span, as a share of its length.
SAG = 0.025
BARRIERS = {"fence": ("fence", 1.2), "wall": ("wall", 1.2), "retaining_wall": ("wall", 1.0),
            "city_wall": ("wall", 3.0), "guard_rail": ("fence", 0.8), "handrail": ("fence", 0.95),
            "railing": ("fence", 1.0), "jersey_barrier": ("wall", 0.8)}


def _lift(field, pts, dy):
    a = np.asarray(pts, dtype=np.float64)
    y = np.atleast_1d(field.at(a[:, 0], a[:, 1])) + dy
    return [(float(x), float(h), float(z)) for (x, z), h in zip(a, y)]


def _dense(line, step):
    n = max(1, int(math.ceil(line.length / step)))
    return [(p.x, p.y) for p in (line.interpolate(line.length * k / n) for k in range(n + 1))]


def kerbs(kerb_lines, field):
    out = []
    for line in kerb_lines:
        out.append({"kind": "kerb", "pts": _lift(field, _dense(line, 4.0), KERB)})
    return out


def barriers(map_data, field):
    out = []
    for l in map_data.lines:
        b = l["tags"].get("barrier")
        if b not in BARRIERS or len(l["pts"]) < 2:
            continue
        kind, h = BARRIERS[b]
        try:
            h = float(str(l["tags"].get("height", h)).split()[0])
        except ValueError:
            pass
        h = max(0.5, min(h, 4.0))
        line = LineString(l["pts"])
        if line.length < 1.5:
            continue
        out.append({"kind": kind, "pts": _lift(field, _dense(line, 3.0), h), "height": h})
    return out


def rails(ways, field, bridges_by_way=None):
    """Two rails for every track open to the sky, and its middle (kind
    "track") for the sleepers and ballast."""
    out = []
    for w in ways:
        if not w["rail"] or w["tunnel"] or w["bridge"]:
            continue
        line = w["line"]
        if line.length < 4.0:
            continue
        mid = _dense(line, 3.0)
        out.append({"kind": "track", "pts": _lift(field, mid, 0.0), "rail": w["kind"]})
        for side in (-1.0, 1.0):
            g = line.offset_curve(side * GAUGE * 0.5)
            if g.is_empty or g.geom_type != "LineString":
                continue
            out.append({"kind": "rail", "pts": _lift(field, _dense(g, 3.0), RAIL_TOP)})
    return out


def wires(map_data, field):
    """Power lines: three wires per span, sagging between the poles, and the
    poles themselves as props."""
    lines, poles = [], []
    for l in map_data.lines:
        if l["tags"].get("power") not in ("line", "minor_line") or len(l["pts"]) < 2:
            continue
        pts = l["pts"]
        hs = np.atleast_1d(field.at(np.array([p[0] for p in pts]), np.array([p[1] for p in pts])))
        for k, (x, z) in enumerate(pts):
            a = pts[max(0, k - 1)]
            b = pts[min(len(pts) - 1, k + 1)]
            dx, dz = b[0] - a[0], b[1] - a[1]
            yaw = math.atan2(-dx, -dz) if (dx or dz) else 0.0
            poles.append({"m": "street/power_pole", "p": (x, float(hs[k]), z), "yaw": yaw})
        for k in range(len(pts) - 1):
            (x0, z0), (x1, z1) = pts[k], pts[k + 1]
            span = math.hypot(x1 - x0, z1 - z0)
            if span < 3.0 or span > 120.0:
                continue
            px, pz = -(z1 - z0) / span, (x1 - x0) / span
            for off in (-WIRE_SPREAD, 0.0, WIRE_SPREAD):
                wire = []
                n = max(4, int(span / 4.0))
                for s in range(n + 1):
                    t = s / n
                    y = (hs[k] * (1 - t) + hs[k + 1] * t) + POLE_TOP - SAG * span * 4.0 * t * (1 - t)
                    wire.append((x0 + (x1 - x0) * t + px * off, float(y), z0 + (z1 - z0) * t + pz * off))
                lines.append({"kind": "wire", "pts": wire})
    return lines, poles


def parapets(bridge_list):
    """Both edges of every bridge deck, a metre up."""
    out = []
    for b in bridge_list:
        pts = b["pts"]
        if len(pts) < 2:
            continue
        flat = LineString([(x, z) for x, _, z in pts])
        for side in (-1.0, 1.0):
            g = flat.offset_curve(side * (b["width"] * 0.5 + 0.25))
            if g.is_empty or g.geom_type != "LineString":
                continue
            edge = []
            for x, z in _dense(g, 3.0):
                s = flat.project(Point(x, z))
                edge.append((x, _deck_y(pts, flat, s) + 1.0, z))
            out.append({"kind": "parapet", "pts": edge})
    return out


def _deck_y(pts, flat, s):
    acc = 0.0
    for (x0, y0, z0), (x1, y1, z1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, z1 - z0)
        if acc + seg >= s or (x1, y1, z1) == pts[-1]:
            t = 0.0 if seg == 0 else min(1.0, max(0.0, (s - acc) / seg))
            return y0 + (y1 - y0) * t
        acc += seg
    return pts[-1][1]
