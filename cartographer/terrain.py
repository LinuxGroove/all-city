"""The land's shape: a height for every 4 m of the town, from elevation
tiles in Mapzen's Terrarium format (on AWS's open data, public domain and
open licences; see `ATTRIBUTION`).

Elevation models of towns often carry the tops of buildings and trees, so
the field is opened (the lowest point in each neighbourhood, then the
highest of those) to take away anything narrower than a block, then
smoothed. The sea is cut down to y = 0 and the land beside it lifted just
above, so the shore is a clean line the water meets.
"""
import io
import math
import os
import urllib.request

import numpy as np
from PIL import Image

TERRARIUM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
ATTRIBUTION = ("Elevation: Mapzen Terrarium tiles on AWS Open Data (SRTM, GMTED, NED, ETOPO1 and others; "
               "see https://github.com/tilezen/joerd/blob/master/docs/attribution.md)")
USER_AGENT = "AllCityCartographer/0.1 (+https://github.com/LinuxGroove/all-city)"
CELL = 4.0


class Heightfield:
    """Heights on a grid: `h[j, i]` is the height at x = x0 + i * cell,
    z = z0 + j * cell."""

    def __init__(self, x0, z0, cell, h):
        self.x0 = x0
        self.z0 = z0
        self.cell = cell
        self.h = h

    @property
    def nx(self):
        return self.h.shape[1]

    @property
    def nz(self):
        return self.h.shape[0]

    def at(self, x, z):
        """The height at a point (or arrays of points), bilinear."""
        fx = (np.asarray(x, dtype=np.float64) - self.x0) / self.cell
        fz = (np.asarray(z, dtype=np.float64) - self.z0) / self.cell
        fx = np.clip(fx, 0, self.nx - 1.000001)
        fz = np.clip(fz, 0, self.nz - 1.000001)
        i = np.floor(fx).astype(int)
        j = np.floor(fz).astype(int)
        tx = fx - i
        tz = fz - j
        h = self.h
        top = h[j, i] * (1 - tx) + h[j, i + 1] * tx
        bottom = h[j + 1, i] * (1 - tx) + h[j + 1, i + 1] * tx
        out = top * (1 - tz) + bottom * tz
        return float(out) if np.ndim(out) == 0 else out

    def block(self, x0, z0, n):
        """An n x n block of heights starting at a grid point (for a tile)."""
        i = int(round((x0 - self.x0) / self.cell))
        j = int(round((z0 - self.z0) / self.cell))
        out = np.zeros((n, n), dtype=np.float32)
        ii = np.clip(np.arange(i, i + n), 0, self.nx - 1)
        jj = np.clip(np.arange(j, j + n), 0, self.nz - 1)
        out[:, :] = self.h[np.ix_(jj, ii)]
        return out


def _tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1.0 - math.asinh(math.tan(lat_r)) / math.pi) / 2.0 * n
    return x, y


def _fetch(z, x, y, cache):
    path = os.path.join(cache, "terrarium", str(z), str(x), "%d.png" % y) if cache else None
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
    else:
        req = urllib.request.Request(TERRARIUM.format(z=z, x=x, y=y), headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        if path:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
    rgb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), dtype=np.float64)
    return rgb[..., 0] * 256.0 + rgb[..., 1] + rgb[..., 2] / 256.0 - 32768.0


def sample(proj, box, zoom=14, cache=None, cell=CELL):
    """Heights from Terrarium tiles over `box` (local metres), one per
    `cell`, before any cleaning. Raises OSError when the tiles can't be
    fetched (no network and nothing cached)."""
    nx = int(math.ceil(box.width / cell)) + 1
    nz = int(math.ceil(box.depth / cell)) + 1
    xs = box.x0 + np.arange(nx) * cell
    zs = box.z0 + np.arange(nz) * cell
    gx, gz = np.meshgrid(xs, zs)
    lat, lon = proj.latlon(gx, gz)
    n = 2 ** zoom
    px = (lon + 180.0) / 360.0 * n * 256.0
    py = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / np.pi) / 2.0 * n * 256.0
    tx0, ty0 = int(px.min() // 256), int(py.min() // 256)
    tx1, ty1 = int(px.max() // 256), int(py.max() // 256)
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256))
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = _fetch(zoom, tx, ty, cache)
    # Pixel centres sit at half a pixel.
    fx = np.clip(px - tx0 * 256 - 0.5, 0, mosaic.shape[1] - 1.000001)
    fy = np.clip(py - ty0 * 256 - 0.5, 0, mosaic.shape[0] - 1.000001)
    i = np.floor(fx).astype(int)
    j = np.floor(fy).astype(int)
    ax = fx - i
    ay = fy - j
    h = (mosaic[j, i] * (1 - ax) * (1 - ay) + mosaic[j, i + 1] * ax * (1 - ay) +
         mosaic[j + 1, i] * (1 - ax) * ay + mosaic[j + 1, i + 1] * ax * ay)
    return Heightfield(box.x0, box.z0, cell, h.astype(np.float32))


def flat(box, height=10.0, cell=CELL):
    """A flat field, for building without the network."""
    nx = int(math.ceil(box.width / cell)) + 1
    nz = int(math.ceil(box.depth / cell)) + 1
    return Heightfield(box.x0, box.z0, cell, np.full((nz, nx), height, dtype=np.float32))


def _filter1d(a, k, axis, op):
    pad = k // 2
    widths = [(0, 0)] * a.ndim
    widths[axis] = (pad, pad)
    p = np.pad(a, widths, mode="edge")
    win = np.lib.stride_tricks.sliding_window_view(p, k, axis=axis)
    return op(win, axis=-1)


def _filter2d(a, k, op):
    return _filter1d(_filter1d(a, k, 0, op), k, 1, op)


def clean(field, open_m=24.0, blur_passes=2):
    """Takes away bumps narrower than `open_m` (buildings, trees) and
    smooths what's left."""
    k = max(3, int(round(open_m / field.cell)) | 1)
    h = _filter2d(field.h, k, np.min)
    h = _filter2d(h, k, np.max)
    for _ in range(blur_passes):
        h = _filter2d(h, 3, np.mean)
    field.h = h.astype(np.float32)
    return field


def apply_sea(field, sea_mask, shore=0.6):
    """Puts the sea (a boolean grid the field's size) at y = 0 and keeps
    the land at least `shore` above it."""
    h = field.h
    h[sea_mask] = -0.5
    land = ~sea_mask
    h[land] = np.maximum(h[land], shore)
    field.h = h
    return field
