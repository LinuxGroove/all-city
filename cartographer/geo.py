"""Local projection: metres east (x) and south (z) of a town's centre."""
import math


class Projection:
    """Equirectangular metres around (lat0, lon0), accurate to a few
    centimetres per kilometre at a town's size. x runs east and z south, as
    in the game (Godot's -z is north)."""

    def __init__(self, lat0: float, lon0: float):
        self.lat0 = lat0
        self.lon0 = lon0
        phi = math.radians(lat0)
        self.m_lat = 111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
        self.m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi) + 0.118 * math.cos(5 * phi)

    def xz(self, lat: float, lon: float):
        return ((lon - self.lon0) * self.m_lon, (self.lat0 - lat) * self.m_lat)

    def latlon(self, x: float, z: float):
        return (self.lat0 - z / self.m_lat, self.lon0 + x / self.m_lon)


class Box:
    """An axis-aligned box in metres (x0, z0) to (x1, z1)."""

    def __init__(self, x0, z0, x1, z1):
        self.x0, self.z0, self.x1, self.z1 = float(x0), float(z0), float(x1), float(z1)

    def contains(self, x, z, margin=0.0):
        return self.x0 - margin <= x <= self.x1 + margin and self.z0 - margin <= z <= self.z1 + margin

    def grow(self, m):
        return Box(self.x0 - m, self.z0 - m, self.x1 + m, self.z1 + m)

    @property
    def width(self):
        return self.x1 - self.x0

    @property
    def depth(self):
        return self.z1 - self.z0

    def as_list(self):
        return [round(self.x0, 2), round(self.z0, 2), round(self.x1, 2), round(self.z1, 2)]

    def __repr__(self):
        return "Box(%.1f, %.1f, %.1f, %.1f)" % (self.x0, self.z0, self.x1, self.z1)


def latlon_box(proj: Projection, box: Box):
    """The (south, west, north, east) bounds that cover a box."""
    n, w = proj.latlon(box.x0, box.z0)
    s, e = proj.latlon(box.x1, box.z1)
    return (min(s, n), min(w, e), max(s, n), max(w, e))


def stable_seed(*parts) -> int:
    """A seed from ids and names that is the same on every machine and run
    (Python's hash() of strings is not)."""
    h = 2166136261
    for p in parts:
        for ch in str(p).encode():
            h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
        h = ((h ^ 0x2F) * 16777619) & 0xFFFFFFFF
    return h


def stable_id(*parts, prefix="w", bits=48) -> str:
    """A short id from parts, the same everywhere (64-bit FNV-1a, cut to
    `bits`): the Cartographer's own ids for walls and buildings, made from
    their shape, never from a map identifier."""
    h = 0xCBF29CE484222325
    for p in parts:
        for ch in str(p).encode():
            h = ((h ^ ch) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
        h = ((h ^ 0x2F) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    h >>= 64 - bits
    return "%s%0*x" % (prefix, bits // 4, h)
