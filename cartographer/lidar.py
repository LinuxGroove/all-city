"""Measured shapes from airborne lidar: the bare ground, how tall every
building really is, the colour of its roof, and where the trees stand.

Public lidar is served as Entwine Point Tiles (EPT): an octree of LAZ files
whose hierarchy says how many points each node holds, so the Cartographer
reads only the nodes over a town's box. Two open collections are searched:

- USGS 3DEP on AWS Open Data (public domain), with an index of every
  project's outline (`USGS_INDEX`).
- NOAA's Digital Coast on AWS (public domain; it holds the states' own
  statewide surveys, such as North Carolina's of 2015), found by the bounds
  in each project's `ept.json`.

For a town, every project whose bounds cover the box is counted from its
hierarchy and the one with the most points there is read. Points come as
(x east, y up, z south) in town metres with their class (ASPRS: 2 ground,
3-5 vegetation, 6 building, 7 and 18 noise, 9 water), return numbers and,
where the survey was coloured, red, green and blue.
"""
import concurrent.futures
import json
import math
import os
import urllib.error
import urllib.request

import numpy as np

from .terrain import USER_AGENT

USGS_INDEX = "https://raw.githubusercontent.com/hobu/usgs-lidar/master/boundaries/resources.geojson"
NOAA = "https://noaa-nos-coastal-lidar-pds.s3.amazonaws.com"
NOAA_EPT = NOAA + "/entwine/geoid18/%s/ept.json"
ATTRIBUTION = {
    "usgs": "Lidar: U.S. Geological Survey 3D Elevation Program (public domain)",
    "noaa": "Lidar: NOAA Office for Coastal Management Digital Coast, %s (public domain)",
}
CELL = 1.0
# How far past the town's box points are read, so buildings on its edge
# are measured whole.
MARGIN = 40.0


def _get(url, timeout=120, tries=3):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last = e
    raise OSError("couldn't fetch %s: %s" % (url, last))


def _cached(url, path, timeout=120):
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    data = _get(url, timeout)
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".part", "wb") as f:
            f.write(data)
        os.replace(path + ".part", path)
    return data


def _transformer(epsg, to_source):
    from pyproj import Transformer
    if to_source:
        return Transformer.from_crs(4326, int(epsg), always_xy=True)
    return Transformer.from_crs(int(epsg), 4326, always_xy=True)


class Source:
    """One EPT project: where it is, its metadata and how to name it."""

    def __init__(self, url, kind, name, meta):
        self.url = url
        self.base = url.rsplit("/", 1)[0]
        self.kind = kind
        self.name = name
        self.meta = meta
        self.epsg = int(meta["srs"]["horizontal"])
        self.bounds = meta["bounds"]

    def attribution(self):
        line = ATTRIBUTION[self.kind]
        return line % self.name if "%s" in line else line

    def box_in_source(self, proj, box):
        """(x0, y0, x1, y1) in the project's own coordinates over `box`."""
        t = _transformer(self.epsg, True)
        xs, ys = [], []
        for x in (box.x0, (box.x0 + box.x1) * 0.5, box.x1):
            for z in (box.z0, (box.z0 + box.z1) * 0.5, box.z1):
                lat, lon = proj.latlon(x, z)
                sx, sy = t.transform(lon, lat)
                xs.append(sx)
                ys.append(sy)
        return min(xs), min(ys), max(xs), max(ys)

    def _hierarchy(self, key, cache):
        path = os.path.join(cache, "hierarchy", key + ".json") if cache else None
        return json.loads(_cached(self.base + "/ept-hierarchy/%s.json" % key, path))

    def nodes(self, sbox, cache=None):
        """Every node over `sbox` (x0, y0, x1, y1 in the project's
        coordinates) with points: {key: count}."""
        b = self.bounds
        found = {}

        def overlaps(d, x, y):
            n = 2 ** d
            sx = (b[3] - b[0]) / n
            sy = (b[4] - b[1]) / n
            nx0, ny0 = b[0] + x * sx, b[1] + y * sy
            return nx0 <= sbox[2] and nx0 + sx >= sbox[0] and ny0 <= sbox[3] and ny0 + sy >= sbox[1]

        def walk(hier, key):
            count = hier.get(key)
            if count is None:
                return
            if count == -1:
                hier = self._hierarchy(key, cache)
                count = hier.get(key, 0)
            d, x, y, z = (int(v) for v in key.split("-"))
            if not overlaps(d, x, y):
                return
            if count > 0:
                found[key] = count
            for dx in (0, 1):
                for dy in (0, 1):
                    for dz in (0, 1):
                        walk(hier, "%d-%d-%d-%d" % (d + 1, 2 * x + dx, 2 * y + dy, 2 * z + dz))

        walk(self._hierarchy("0-0-0-0", cache), "0-0-0-0")
        return found


def find(proj, box, cache=None, log=print):
    """The open lidar projects over `box`, most points there first:
    [(source, points)]. An empty list where there's none (or no network)."""
    lat_s, lon_w = proj.latlon(box.x0, box.z1)
    lat_n, lon_e = proj.latlon(box.x1, box.z0)
    cands = []
    try:
        cands += _usgs_candidates(lon_w, lat_s, lon_e, lat_n, cache)
    except (OSError, ValueError) as e:
        log("no USGS lidar index (%s)" % e)
    try:
        cands += _noaa_candidates(lon_w, lat_s, lon_e, lat_n, cache)
    except (OSError, ValueError) as e:
        log("no NOAA lidar index (%s)" % e)
    out = []
    for src in cands:
        try:
            sbox = src.box_in_source(proj, box)
            points = sum(src.nodes(sbox, os.path.join(cache, "lidar", src.kind, _slug(src.name)) if cache else None).values())
        except (OSError, ValueError, KeyError) as e:
            log("skipping %s (%s)" % (src.name, e))
            continue
        if points > 0:
            out.append((src, points))
    out.sort(key=lambda sp: -sp[1])
    return out


def _slug(s):
    return "".join(c if c.isalnum() else "_" for c in str(s))


def _usgs_candidates(w, s, e, n, cache):
    from shapely.geometry import box as sbox, shape
    path = os.path.join(cache, "lidar", "usgs-resources.geojson") if cache else None
    index = json.loads(_cached(USGS_INDEX, path, timeout=300))
    area = sbox(w, s, e, n)
    out = []
    for f in index["features"]:
        if not shape(f["geometry"]).intersects(area):
            continue
        url = f["properties"]["url"]
        name = f["properties"]["name"]
        meta = json.loads(_cached(url, os.path.join(cache, "lidar", "usgs", _slug(name), "ept.json") if cache else None))
        out.append(Source(url, "usgs", name, meta))
    return out


def _noaa_candidates(w, s, e, n, cache):
    ids = _noaa_ids(cache)

    def meta(i):
        path = os.path.join(cache, "lidar", "noaa", i, "ept.json") if cache else None
        try:
            return i, json.loads(_cached(NOAA_EPT % i, path, timeout=60))
        except (OSError, ValueError):
            return i, None

    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        metas = list(pool.map(meta, ids))
    out = []
    for i, m in metas:
        if not m or "srs" not in m or not m["srs"].get("horizontal"):
            continue
        try:
            t = _transformer(m["srs"]["horizontal"], True)
        except Exception:
            continue
        b = m.get("boundsConforming", m["bounds"])
        xs, ys = t.transform([w, e, w, e], [s, s, n, n])
        if max(xs) < b[0] or min(xs) > b[3] or max(ys) < b[1] or min(ys) > b[4]:
            continue
        out.append(Source(NOAA_EPT % i, "noaa", _noaa_name(i, cache), m))
    return out


def _noaa_ids(cache):
    path = os.path.join(cache, "lidar", "noaa-ids.json") if cache else None
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    ids, token = [], None
    while True:
        url = NOAA + "/?list-type=2&prefix=entwine/geoid18/&delimiter=/"
        if token:
            url += "&continuation-token=" + urllib.request.quote(token, safe="")
        xml = _get(url).decode("utf-8")
        for part in xml.split("<Prefix>")[1:]:
            p = part.split("</Prefix>")[0]
            if p.count("/") == 3:
                ids.append(p.split("/")[2])
        if "<NextContinuationToken>" not in xml:
            break
        token = xml.split("<NextContinuationToken>")[1].split("</NextContinuationToken>")[0]
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ids, f)
    return ids


def _noaa_name(i, cache):
    """A NOAA project's title, from its metadata, or its number."""
    path = os.path.join(cache, "lidar", "noaa", i, "name.txt") if cache else None
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    name = "Digital Coast %s" % i
    try:
        xml = _get(NOAA + "/?list-type=2&prefix=laz/geoid18/%s/&delimiter=/" % i).decode("utf-8")
        metas = [k.split("</Key>")[0] for k in xml.split("<Key>")[1:] if k.split("</Key>")[0].endswith(".xml")]
        if metas:
            doc = _get(NOAA + "/" + metas[0]).decode("utf-8", "replace")
            # The dataset's own title is the first one after its identification.
            at = doc.find("<gmd:title>", max(0, doc.find("<gmd:identificationInfo>")))
            start = doc.find("<gco:CharacterString>", at) + len("<gco:CharacterString>") if at >= 0 else -1
            title = doc[start:doc.find("<", start)].strip() if start > 0 else ""
            if title:
                name = title
    except OSError:
        pass
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(name)
    return name


class Cloud:
    """Points in town metres: `x`, `y` (up), `z` (south) as float32 arrays,
    with `cls`, `ret` and `nret` (uint8) and `rgb` (n x 3 uint8, or None)."""

    def __init__(self, x, y, z, cls, ret, nret, rgb):
        self.x, self.y, self.z = x, y, z
        self.cls, self.ret, self.nret = cls, ret, nret
        self.rgb = rgb

    def __len__(self):
        return len(self.x)


def read(src, proj, box, cache=None, log=print):
    """Every point of `src` over `box` (grown by MARGIN) as a Cloud."""
    import laspy
    box = box.grow(MARGIN)
    sbox = src.box_in_source(proj, box)
    node_cache = os.path.join(cache, "lidar", src.kind, _slug(src.name)) if cache else None
    nodes = src.nodes(sbox, node_cache)
    log("lidar: %s, %d nodes, %.1f M points" % (src.name, len(nodes), sum(nodes.values()) / 1e6))

    def fetch(key):
        path = os.path.join(node_cache, "data", key + ".laz") if node_cache else None
        return _cached(src.base + "/ept-data/%s.laz" % key, path, timeout=300)

    to_ll = _transformer(src.epsg, False)
    parts = []
    with concurrent.futures.ThreadPoolExecutor(12) as pool:
        for data in pool.map(fetch, sorted(nodes)):
            las = laspy.read(_Bytes(data))
            sx = np.asarray(las.x)
            sy = np.asarray(las.y)
            keep = (sx >= sbox[0]) & (sx <= sbox[2]) & (sy >= sbox[1]) & (sy <= sbox[3])
            if not keep.any():
                continue
            lon, lat = to_ll.transform(sx[keep], sy[keep])
            x, z = proj.xz(np.asarray(lat), np.asarray(lon))
            inside = (x >= box.x0) & (x <= box.x1) & (z >= box.z0) & (z <= box.z1)
            names = set(las.point_format.dimension_names)
            rgb = None
            if {"red", "green", "blue"} <= names:
                r = np.asarray(las.red)[keep][inside]
                g = np.asarray(las.green)[keep][inside]
                b = np.asarray(las.blue)[keep][inside]
                # 16-bit colour in LAS; some surveys store 8-bit values in it.
                peak = max(int(r.max(initial=0)), int(g.max(initial=0)), int(b.max(initial=0)))
                shift = 8 if peak > 255 else 0
                rgb = np.stack([r >> shift, g >> shift, b >> shift], axis=1).astype(np.uint8)
            parts.append((x[inside].astype(np.float32), np.asarray(las.z)[keep][inside].astype(np.float32),
                          z[inside].astype(np.float32), np.asarray(las.classification)[keep][inside].astype(np.uint8),
                          np.asarray(las.return_number)[keep][inside].astype(np.uint8),
                          np.asarray(las.number_of_returns)[keep][inside].astype(np.uint8), rgb))
    if not parts:
        return Cloud(*(np.zeros(0, np.float32),) * 3, *(np.zeros(0, np.uint8),) * 3, None)
    cat = [np.concatenate([p[k] for p in parts]) for k in range(6)]
    rgb = np.concatenate([p[6] for p in parts]) if all(p[6] is not None for p in parts) else None
    if rgb is not None and not rgb.any():
        rgb = None
    return Cloud(*cat, rgb)


class _Bytes:
    """A file-like view of bytes for laspy (which wants a stream)."""

    def __init__(self, data):
        import io
        self._io = io.BytesIO(data)

    def __getattr__(self, name):
        return getattr(self._io, name)


class Survey:
    """A cloud made into grids every CELL over a box: the bare ground
    (`ground`, holes under buildings filled), the highest first return
    (`surface`), what each cell mostly is (`kind`: 0 nothing, 1 ground,
    2 building, 3 vegetation, 4 water) and its colour (`rgb`, or None).
    `grid[j, i]` is at x = x0 + (i + 0.5) * cell, z = z0 + (j + 0.5) * cell."""

    def __init__(self, cloud, box, cell=CELL, source=None):
        self.box = box
        self.cell = cell
        self.x0, self.z0 = box.x0, box.z0
        self.nx = int(math.ceil(box.width / cell))
        self.nz = int(math.ceil(box.depth / cell))
        self.source = source
        n = self.nx * self.nz
        c = cloud
        good = (c.cls != 7) & (c.cls != 18)
        i = np.clip(((c.x - self.x0) / cell).astype(np.int64), 0, self.nx - 1)
        j = np.clip(((c.z - self.z0) / cell).astype(np.int64), 0, self.nz - 1)
        flat = j * self.nx + i

        g = good & ((c.cls == 2) | (c.cls == 9))
        ground = np.full(n, np.inf, np.float32)
        np.minimum.at(ground, flat[g], c.y[g])
        self.has_ground = np.isfinite(ground).reshape(self.nz, self.nx)
        ground[~np.isfinite(ground)] = np.nan
        self.ground = _fill(ground.reshape(self.nz, self.nx))

        surface = np.full(n, -np.inf, np.float32)
        np.maximum.at(surface, flat[good], c.y[good])
        surface[~np.isfinite(surface)] = np.nan
        self.surface = surface.reshape(self.nz, self.nx)
        missing = np.isnan(self.surface)
        self.surface[missing] = self.ground[missing]

        kind = np.zeros(n, np.uint8)
        counts = np.zeros((5, n), np.int32)
        for k, classes in ((1, (2,)), (2, (6,)), (3, (3, 4, 5)), (4, (9,))):
            m = good & np.isin(c.cls, classes)
            np.add.at(counts[k], flat[m], 1)
        kind = np.argmax(counts, axis=0).astype(np.uint8)
        kind[counts.sum(axis=0) == 0] = 0
        self.kind = kind.reshape(self.nz, self.nx)
        self.counts = counts.reshape(5, self.nz, self.nx)

        self.rgb = None
        if c.rgb is not None:
            # The colour of each cell's highest point: the roof, the canopy
            # or the ground, as seen from above.
            order = np.argsort(c.y[good], kind="stable")
            f = flat[good][order]
            rgb = np.zeros((n, 3), np.uint8)
            rgb[f] = c.rgb[good][order]
            self.rgb = rgb.reshape(self.nz, self.nx, 3)

    def cell_of(self, x, z):
        i = np.clip(((np.asarray(x) - self.x0) / self.cell).astype(np.int64), 0, self.nx - 1)
        j = np.clip(((np.asarray(z) - self.z0) / self.cell).astype(np.int64), 0, self.nz - 1)
        return i, j

    def ground_at(self, x, z):
        i, j = self.cell_of(x, z)
        return self.ground[j, i]

    def cells_in(self, poly, shrink=0.6):
        """(i, j) of the cells whose middles lie inside `poly` shrunk by
        `shrink` (so walls and eaves at the edge don't count)."""
        import shapely
        p = poly.buffer(-shrink) if shrink else poly
        if p.is_empty:
            p = poly
        x0, z0, x1, z1 = p.bounds
        i0, j0 = self.cell_of(x0, z0)
        i1, j1 = self.cell_of(x1, z1)
        ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1))
        xs = self.x0 + (ii + 0.5) * self.cell
        zs = self.z0 + (jj + 0.5) * self.cell
        inside = shapely.contains_xy(p, xs, zs)
        return ii[inside], jj[inside]


def _fill(h):
    """Fills NaN holes in a grid from the nearest known cells, then smooths
    what was filled, so the ground runs on under buildings."""
    known = ~np.isnan(h)
    if known.all():
        return h
    if not known.any():
        return np.zeros_like(h)
    try:
        from scipy import ndimage
        idx = ndimage.distance_transform_edt(~known, return_distances=False, return_indices=True)
        out = h[tuple(idx)]
        blurred = ndimage.uniform_filter(out, 9)
        out[~known] = blurred[~known]
        return out
    except ImportError:
        out = h.copy()
        out[~known] = np.nanmedian(h)
        for _ in range(64):
            pad = np.pad(out, 1, mode="edge")
            mean = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]) * 0.25
            out[~known] = mean[~known]
        return out


def terrain(survey, cell, like):
    """The ground as a Heightfield on `like`'s grid (every `cell`), from
    the survey's bare earth: the mean of the 1 m cells round each point."""
    from .terrain import Heightfield
    xs = like.x0 + np.arange(like.nx) * like.cell
    zs = like.z0 + np.arange(like.nz) * like.cell
    k = max(1, int(round(cell / survey.cell)))
    try:
        from scipy import ndimage
        smooth = ndimage.uniform_filter(survey.ground, k + 1)
    except ImportError:
        smooth = survey.ground
    gx, gz = np.meshgrid(xs, zs)
    fx = np.clip((gx - survey.x0) / survey.cell - 0.5, 0, survey.nx - 1.000001)
    fz = np.clip((gz - survey.z0) / survey.cell - 0.5, 0, survey.nz - 1.000001)
    i = np.floor(fx).astype(int)
    j = np.floor(fz).astype(int)
    tx, tz = fx - i, fz - j
    h = (smooth[j, i] * (1 - tx) * (1 - tz) + smooth[j, i + 1] * tx * (1 - tz) +
         smooth[j + 1, i] * (1 - tx) * tz + smooth[j + 1, i + 1] * tx * tz)
    return Heightfield(like.x0, like.z0, like.cell, h.astype(np.float32))


# Buildings ------------------------------------------------------------------

MIN_COVER = 0.35     # share of a footprint's cells that must be roof for a measure
PART_SPREAD = 5.0    # a footprint whose roof spans more than this splits into parts
PART_MIN = 40.0      # the smallest part, in square metres
PITCH_MIN = 0.9      # a roof rising less than this is flat
PITCH_MAX_AREA = 900.0


def measure(survey, poly, ground):
    """A footprint as the survey saw it: a list of parts, each
    {"poly", "top", "roof"} where `top` is the height (above the sea) the
    walls reach and `roof` is None for a flat roof or {"shape": "gable" or
    "hip", "rise", "along"} for a pitched one (`along` the ridge's
    direction in radians, atan2(dz, dx)). Returns None where the survey
    can't say (the building is newer than it, or hidden under trees).
    `ground` is the lowest ground along the outline."""
    ii, jj = survey.cells_in(poly)
    if len(ii) < 4:
        ii, jj = survey.cells_in(poly, shrink=0.0)
    if len(ii) < 3:
        return None
    roof_cells = survey.counts[2][jj, ii] > 0
    cover = float(roof_cells.mean())
    surf = survey.surface[jj, ii]
    above = surf - ground
    # A footprint with almost no building points and nothing standing in it
    # is something built since the survey.
    if cover < MIN_COVER and float(np.percentile(above, 75)) < 2.5:
        return None
    if cover < MIN_COVER * 0.5:
        return None
    use = roof_cells if roof_cells.sum() >= 3 else np.ones_like(roof_cells)
    hs = surf[use]
    lo, hi = float(np.percentile(hs, 10)), float(np.percentile(hs, 95))
    if hi - lo > PART_SPREAD and poly.area > PART_MIN * 3:
        parts = _parts(survey, poly, ii[use], jj[use], hs, ground)
        if parts:
            return parts
    return [{"poly": poly, **_roof_of(survey, poly, ii[use], jj[use], hs, ground)}]


def _roof_of(survey, poly, ii, jj, hs, ground):
    """The top and roof of one part from its roof cells' heights."""
    top = float(np.percentile(hs, 90))
    roof = None
    if poly.area <= PITCH_MAX_AREA and len(hs) >= 12:
        fit = _pitch(survey, poly, ii, jj, hs)
        if fit is not None:
            eaves, rise, shape, along = fit
            if rise >= PITCH_MIN and eaves - ground >= 2.2:
                top = eaves
                roof = {"shape": shape, "rise": round(rise, 2), "along": round(along, 4)}
    return {"top": top, "roof": roof}


def _pitch(survey, poly, ii, jj, hs):
    """Fits a gable and a hip roof over the footprint's oriented rectangle:
    (eaves, rise, shape, along) for the better one, or None when a flat
    roof fits as well."""
    rect = poly.minimum_rotated_rectangle
    cs = list(rect.exterior.coords)[:4]
    if len(cs) < 4:
        return None
    e0 = np.subtract(cs[1], cs[0])
    e1 = np.subtract(cs[2], cs[1])
    if np.hypot(*e0) < np.hypot(*e1):
        e0, e1 = e1, e0
    length, width = float(np.hypot(*e0)), float(np.hypot(*e1))
    if width < 3.0:
        return None
    ua = e0 / length
    va = np.array([-ua[1], ua[0]])
    c = np.mean(cs, axis=0)
    xs = survey.x0 + (ii + 0.5) * survey.cell - c[0]
    zs = survey.z0 + (jj + 0.5) * survey.cell - c[1]
    us = xs * ua[0] + zs * ua[1]
    vs = xs * va[0] + zs * va[1]
    half_w = width * 0.5
    # Distance in from the eaves for each shape: a gable falls across the
    # rectangle's width only; a hip falls from every edge of the outline
    # itself (the roof over an L-shaped house hips round its corner).
    import shapely
    d_hip = shapely.distance(poly.exterior, shapely.points(xs + c[0], zs + c[1]))
    best = None
    # A near-square house may have its ridge either way: try both. The map's
    # outline is often a metre or two off the survey, so the ridge may sit
    # off the middle.
    tries = [("hip", d_hip, 0.0)]
    for off in np.linspace(-half_w * 0.4, half_w * 0.4, 7):
        tries.append(("gable", np.clip(half_w - np.abs(vs - off), 0.0, half_w), 0.0))
    if length < width * 1.35:
        for off in np.linspace(-length * 0.2, length * 0.2, 7):
            tries.append(("gable", np.clip(length * 0.5 - np.abs(us - off), 0.0, length * 0.5), math.pi * 0.5))
    for shape, d, turn in tries:
        a = np.stack([np.ones_like(d), d], axis=1)
        keep = np.ones(len(d), bool)
        coef = None
        # Trees over the eaves and chimneys poke out: fit, drop the worst
        # sixth, fit again.
        for _ in range(2):
            coef, *_ = np.linalg.lstsq(a[keep], hs[keep], rcond=None)
            res = np.abs(a @ coef - hs)
            keep = res <= np.percentile(res, 83)
        eaves, slope = float(coef[0]), float(coef[1])
        if slope <= 0.2 or slope > 1.8:
            continue
        err = float(np.sqrt(np.mean((a[keep] @ coef - hs[keep]) ** 2)))
        rise = slope * float(d[keep].max(initial=0.0))
        if best is None or err < best[0]:
            best = (err, eaves, rise, shape, turn, float(np.std(hs[keep])))
    if best is None or best[0] > max(0.35, best[5] * 0.7):
        return None
    err, eaves, rise, shape, turn, _ = best
    return eaves, rise, shape, math.atan2(ua[1], ua[0]) + turn


def _parts(survey, poly, ii, jj, hs, ground):
    """A footprint whose roof steps (a tower on a podium, wings of different
    heights) cut into one part per height band."""
    import shapely
    from shapely.geometry import shape as to_shape
    try:
        from rasterio import features
        from rasterio.transform import Affine
    except ImportError:
        return None
    # Height bands: gaps of more than 2.5 m in the sorted heights split them.
    order = np.sort(hs)
    cuts = [order[0] - 1.0]
    for a, b in zip(order[:-1], order[1:]):
        if b - a > 2.5:
            cuts.append((a + b) * 0.5)
    if len(cuts) == 1:
        # One smooth slope of heights: split it in two at its middle.
        cuts.append(float(np.median(order)))
    cuts.append(order[-1] + 1.0)
    band = np.digitize(hs, cuts[1:-1])
    i0, j0 = int(ii.min()) - 1, int(jj.min()) - 1
    grid = np.full((int(jj.max()) - j0 + 2, int(ii.max()) - i0 + 2), 255, np.uint8)
    grid[jj - j0, ii - i0] = band.astype(np.uint8)
    try:
        from scipy import ndimage
        # Smooth the bands' edges: each cell takes its neighbourhood's
        # commonest band.
        filled = ndimage.generic_filter(grid, lambda w: np.bincount(w[w < 255].astype(int)).argmax()
                                        if (w < 255).any() else 255, size=3, mode="nearest")
        grid = np.where(grid < 255, filled, grid).astype(np.uint8)
    except ImportError:
        pass
    t = Affine(survey.cell, 0, survey.x0 + i0 * survey.cell, 0, survey.cell, survey.z0 + j0 * survey.cell)
    pieces = {}
    for geom, value in features.shapes(grid, mask=grid < 255, transform=t):
        pieces.setdefault(int(value), []).append(to_shape(geom))
    out = []
    taken = None
    for b in sorted(pieces, reverse=True):
        region = shapely.union_all(pieces[b]).buffer(0.75).buffer(-0.75)
        part = poly.intersection(region)
        if taken is not None:
            part = part.difference(taken)
        part = part.buffer(0)
        for g in (part.geoms if hasattr(part, "geoms") else [part]):
            if g.geom_type != "Polygon" or g.area < PART_MIN:
                continue
            g = g.simplify(0.5, preserve_topology=True)
            out.append(g)
        taken = region if taken is None else taken.union(region)
    if len(out) < 2:
        return None
    # Whatever's left of the footprint goes to the part it touches most.
    rest = poly.difference(shapely.union_all(out)).buffer(0)
    for g in (rest.geoms if hasattr(rest, "geoms") else [rest]):
        if g.is_empty or g.area < 1.0:
            continue
        k = max(range(len(out)), key=lambda n: out[n].buffer(0.3).intersection(g).area)
        merged = out[k].union(g).buffer(0)
        if merged.geom_type == "Polygon":
            out[k] = merged
    parts = []
    for g in out:
        pi, pj = survey.cells_in(g, shrink=0.4)
        if len(pi) < 3:
            pi, pj = survey.cells_in(g, shrink=0.0)
        if len(pi) < 3:
            continue
        parts.append({"poly": g, **_roof_of(survey, g, pi, pj, survey.surface[pj, pi], ground)})
    return parts if len(parts) >= 2 else None


# Trees ----------------------------------------------------------------------

TREE_MIN = 4.5       # metres above the ground for a crown to count
TREE_MAX = 40.0
# The models' own heights (tools/blender/street_props.py), which instances
# are scaled from.
TREE_MODELS = {"street/tree_oak": 12.0, "street/tree_pine": 18.0, "street/tree_small": 6.0}


def trees(survey, avoid=None):
    """Every tree crown the survey saw: [{"m", "p": (x, y, z), "yaw", "s"}]
    with `s` the scale that makes the model the crown's height. Crowns are
    the highest points of the vegetation's canopy in a window that grows
    with their height; a crown narrow for its height is a pine, a short one
    a small tree. `avoid` is a prepared geometry trunks may not stand in
    (buildings)."""
    from scipy import ndimage
    import shapely
    chm = survey.surface - survey.ground
    veg = (survey.counts[3] > 0) & (survey.kind != 2) & (chm > TREE_MIN) & (chm < TREE_MAX)
    canopy = np.where(veg, chm, 0.0).astype(np.float32)
    smooth = ndimage.gaussian_filter(canopy, 1.0)
    peaks = np.zeros_like(veg)
    # Small windows find small trees; big trees must also top a wider one.
    for size, least in ((5, TREE_MIN), (9, 12.0), (13, 20.0)):
        top = ndimage.maximum_filter(smooth, size=size)
        here = (smooth >= top - 1e-4) & veg & (canopy >= least * 0.5)
        if size == 5:
            peaks = here
        else:
            peaks &= here | (canopy < least)
    jj, ii = np.nonzero(peaks)
    if len(ii) == 0:
        return []
    # Each crown's spread: the canopy cells nearer this peak than any other.
    markers = np.zeros(chm.shape, np.int32)
    markers[jj, ii] = np.arange(1, len(ii) + 1)
    _, (mj, mi) = ndimage.distance_transform_edt(markers == 0, return_indices=True)
    owner = markers[mj, mi]
    owner[~veg] = 0
    area = np.bincount(owner.ravel(), minlength=len(ii) + 1)[1:]
    xs = survey.x0 + (ii + 0.5) * survey.cell
    zs = survey.z0 + (jj + 0.5) * survey.cell
    if avoid is not None:
        shapely.prepare(avoid)
        inside = shapely.contains_xy(avoid, xs, zs)
    else:
        inside = np.zeros(len(xs), bool)
    out = []
    for k in range(len(ii)):
        if inside[k] or area[k] < 6:
            continue
        h = float(canopy[jj[k], ii[k]])
        width = 2.0 * math.sqrt(area[k] / math.pi)
        if h < 7.5:
            model = "street/tree_small"
        elif width < h * 0.38 and h > 14.0:
            model = "street/tree_pine"
        else:
            model = "street/tree_oak"
        x, z = float(xs[k]), float(zs[k])
        seed = (int(x * 7.0) * 73856093) ^ (int(z * 7.0) * 19349663)
        out.append({"m": model, "p": (x, float(survey.ground[jj[k], ii[k]]), z),
                    "yaw": (seed % 628) / 100.0, "s": round(h / TREE_MODELS[model], 3)})
    return out
