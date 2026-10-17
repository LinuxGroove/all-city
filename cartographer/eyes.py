"""Eyes: how much of the town sees each wall.

Every street, path and railway is sampled every few metres, weighted by how
busy it is. A wall scores each sample in front of it that can see it (the
line of sight passes over whatever stands between), more for closer
samples and ones straight ahead, and taller walls reach further. Scores are
then spread over 0 to 100 for the town, so a wall on the high street that
every bus passes scores near the top and an alley's walls near the bottom.
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from shapely.strtree import STRtree
import shapely

SPACING = 10.0
REACH = 80.0
CANDIDATES = 32
CELL = 1.0
EYE = 1.7


def samples(ways):
    """Points along every street and railway open to the sky, with their
    weights: (n, 2) positions and (n,) weights."""
    pts, weights = [], []
    for w in ways:
        if w["tunnel"]:
            continue
        line = w["line"]
        n = max(1, int(line.length / SPACING))
        for k in range(n + 1):
            p = line.interpolate(min(line.length, k * SPACING))
            pts.append((p.x, p.y))
            weights.append(w["weight"])
    return np.asarray(pts, dtype=np.float64).reshape(-1, 2), np.asarray(weights, dtype=np.float64)


class Tops:
    """The height of the tallest building over each metre of the town."""

    def __init__(self, box, built):
        self.x0, self.z0 = box.x0, box.z0
        self.w = int(math.ceil(box.width / CELL)) + 1
        self.h = int(math.ceil(box.depth / CELL)) + 1
        img = Image.new("F", (self.w, self.h), -1000.0)
        draw = ImageDraw.Draw(img)
        for b in sorted(built, key=lambda b: b["top"]):
            ring = [((x - self.x0) / CELL, (z - self.z0) / CELL) for x, z in b["poly"].exterior.coords]
            draw.polygon(ring, fill=float(b["top"]))
        self.grid = np.asarray(img, dtype=np.float32)

    def at(self, x, z):
        i = np.clip(((x - self.x0) / CELL).astype(np.int64), 0, self.w - 1)
        j = np.clip(((z - self.z0) / CELL).astype(np.int64), 0, self.h - 1)
        return self.grid[j, i]


def score(built, ways, field, box):
    """Sets "eyes" (0 to 100) on every face of every building."""
    faces = [f for b in built for f in b["faces"]]
    if not faces:
        return
    pts, weights = samples(ways)
    if len(pts) == 0:
        for f in faces:
            f["eyes"] = 0
        return
    tops = Tops(box, built)
    ground = np.atleast_1d(field.at(pts[:, 0], pts[:, 1]))
    tree = STRtree(shapely.points(pts))
    mids = np.array([((f["p0"][0] + f["p1"][0]) * 0.5, (f["p0"][2] + f["p1"][2]) * 0.5) for f in faces])
    outs = np.array([f["out"] for f in faces])
    heights = np.array([f["storeys"] * 3.0 for f in faces])
    targets = np.array([f["base"] + 1.8 for f in faces])
    reach = REACH * (1.0 + np.minimum(heights, 30.0) / 30.0)
    hits = tree.query(shapely.buffer(shapely.points(mids), reach), predicate="contains")
    fi, si = hits[0], hits[1]
    dx = pts[si, 0] - mids[fi, 0]
    dz = pts[si, 1] - mids[fi, 1]
    dist = np.hypot(dx, dz)
    facing = (dx * outs[fi, 0] + dz * outs[fi, 1]) / np.maximum(dist, 1e-6)
    keep = (facing > 0.15) & (dist > 1.0)
    fi, si, dist, facing = fi[keep], si[keep], dist[keep], facing[keep]
    value = weights[si] * facing / (1.0 + dist / 25.0)
    # The best few candidates per wall, before the costly sight lines.
    order = np.lexsort((-value, fi))
    fi, si, dist, value = fi[order], si[order], dist[order], value[order]
    first = np.searchsorted(fi, fi, side="left")
    rank = np.arange(len(fi)) - first
    keep = rank < CANDIDATES
    fi, si, dist, value = fi[keep], si[keep], dist[keep], value[keep]
    seen = np.zeros(len(fi), dtype=bool)
    chunk = 200000
    steps = np.linspace(0.06, 0.94, 24)
    for c0 in range(0, len(fi), chunk):
        f, s = fi[c0:c0 + chunk], si[c0:c0 + chunk]
        sx = mids[f, 0] + outs[f, 0] * 0.8
        sz = mids[f, 1] + outs[f, 1] * 0.8
        ex, ez = pts[s, 0], pts[s, 1]
        hy0, hy1 = targets[f], ground[s] + EYE
        xs = sx[:, None] + (ex - sx)[:, None] * steps[None, :]
        zs = sz[:, None] + (ez - sz)[:, None] * steps[None, :]
        line_y = hy0[:, None] + (hy1 - hy0)[:, None] * steps[None, :]
        blocked = (tops.at(xs, zs) > line_y).any(axis=1)
        seen[c0:c0 + chunk] = ~blocked
    raw = np.zeros(len(faces))
    np.add.at(raw, fi[seen], value[seen])
    raw *= 1.0 + np.minimum(heights, 24.0) / 48.0
    top = np.percentile(raw[raw > 0], 97) if np.any(raw > 0) else 1.0
    eyes = np.clip(np.power(raw / max(top, 1e-6), 0.7) * 100.0, 0, 100)
    for f, e in zip(faces, eyes):
        f["eyes"] = int(round(e))
