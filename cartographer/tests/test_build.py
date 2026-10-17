"""Builds a small made-up town from an .osm file written here (two streets,
a block of shops, a school, a flight of steps, a fence, a power line and a
coast) and checks what the tiles say about it. Run from the repository:

  python3 -m unittest discover -s cartographer/tests -t .
"""
import gzip
import json
import math
import os
import re
import shutil
import tempfile
import unittest

from cartographer import build, geo, godot_variant, respect
from cartographer.geo import Projection

LAT, LON = 50.0, 0.0
PROJ = Projection(LAT, LON)


class Osm:
    """Writes a tiny .osm file from shapes in local metres."""

    def __init__(self):
        self.nodes = []
        self.ways = []
        self.next = 1

    def node(self, x, z, tags=None):
        lat, lon = PROJ.latlon(x, z)
        nid = self.next
        self.next += 1
        self.nodes.append((nid, lat, lon, tags or {}))
        return nid

    def way(self, pts, tags, closed=False):
        ids = [self.node(x, z) for x, z in pts]
        if closed:
            ids.append(ids[0])
        wid = self.next
        self.next += 1
        self.ways.append((wid, ids, tags))
        return wid

    def write(self, path):
        stamp = 'version="1" timestamp="2026-10-01T00:00:00Z"'
        with open(path, "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6">\n')
            for nid, lat, lon, tags in self.nodes:
                f.write('<node id="%d" lat="%.8f" lon="%.8f" %s>' % (nid, lat, lon, stamp))
                for k, v in tags.items():
                    f.write('<tag k="%s" v="%s"/>' % (k, v))
                f.write("</node>\n")
            for wid, ids, tags in self.ways:
                f.write('<way id="%d" %s>' % (wid, stamp))
                for i in ids:
                    f.write('<nd ref="%d"/>' % i)
                for k, v in tags.items():
                    f.write('<tag k="%s" v="%s"/>' % (k, v))
                f.write("</way>\n")
            f.write("</osm>\n")


def rect(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def town_osm(path):
    o = Osm()
    o.way([(-200, 0), (200, 0)], {"highway": "primary", "name": "High Street"})
    o.way([(0, -200), (0, 200)], {"highway": "residential", "name": "Mill Lane"})
    # A block of shops facing the high street, with a shop point inside.
    o.way(rect(10, -30, 40, -10), {"building": "yes"}, closed=True)
    o.node(25, -20, {"shop": "bakery"})
    # Its neighbour, lower, leaning on its east wall.
    o.way(rect(40, -30, 60, -10), {"building": "yes", "building:levels": "2"}, closed=True)
    o.way(rect(-60, 20, -20, 50), {"building": "school"}, closed=True)
    o.way(rect(20, 20, 30, 28), {"building": "house"}, closed=True)
    o.way([(80, 10), (80, 60)], {"highway": "steps", "width": "4"})
    o.way([(-100, -60), (-40, -60)], {"barrier": "fence"})
    p1 = o.node(-150, 100, {"power": "pole"})
    p2 = o.node(-100, 100, {"power": "pole"})
    o.ways.append((o.next, [p1, p2], {"power": "minor_line"}))
    o.next += 1
    # The coast runs west to east along z = 150 with the land on its left
    # (north), so the sea is south of it.
    o.way([(-300, 150), (300, 150)], {"natural": "coastline"})
    o.write(path)


class BuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix="cartographer-test-")
        cls.osm = os.path.join(cls.dir, "town.osm")
        town_osm(cls.osm)
        cls.out = os.path.join(cls.dir, "town")
        cls.stats = build.build_town(cls.osm, cls.out, "testtown", "Testtown", LAT, LON, radius=256.0,
                                     country="gb", terrain_source="flat")
        with open(os.path.join(cls.out, "town.json"), encoding="utf-8") as f:
            cls.town = json.load(f)
        cls.tiles = []
        for i, j in cls.town["tiles"]:
            with open(os.path.join(cls.out, "tiles", "%d_%d.tile" % (i, j)), "rb") as f:
                cls.tiles.append(godot_variant.decode(gzip.decompress(f.read())))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def buildings(self):
        return [b for t in self.tiles for b in t["buildings"]]

    def test_manifest(self):
        self.assertEqual(self.town["id"], "testtown")
        self.assertEqual(self.town["drive"], "left")
        self.assertEqual(self.town["utc_offset_min"], 0)
        self.assertEqual(len(self.town["tiles"]), 4)
        self.assertTrue(any("OpenStreetMap" in a for a in self.town["attribution"]))
        self.assertEqual(self.town["data_date"], "2026-10-01")

    def test_tiles_shape(self):
        for t in self.tiles:
            self.assertEqual(len(t["heights"]), 65 * 65)
            self.assertEqual(t["ground"][:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(len(t["quarters"]), 64)

    def test_buildings_and_respect(self):
        bs = self.buildings()
        self.assertEqual(len(bs), 4)
        school = [b for b in bs if b["kind"] == "school"]
        self.assertEqual(len(school), 1)
        self.assertEqual(school[0]["paint"], respect.NONE)
        house = [b for b in bs if b["kind"] == "house"][0]
        self.assertEqual(house["paint"], respect.NONE)
        levels = [b for b in bs if b["storeys"] == 2 and b["kind"] == "yes"]
        self.assertEqual(len(levels), 1, "building:levels sets the storeys")

    def test_wall_ids(self):
        ids = [f["id"] for b in self.buildings() for f in b["faces"]]
        self.assertEqual(len(ids), len(set(ids)))
        for i in ids:
            self.assertRegex(i, r"^w[0-9a-f]{6,16}$", "wall ids are what the server accepts")
        self.assertEqual(geo.stable_id(1, 2), geo.stable_id(1, 2))

    def test_faces_face_out(self):
        for b in self.buildings():
            ring = b["rings"][0]
            cx = sum(p[0] for p in ring) / len(ring)
            cz = sum(p[1] for p in ring) / len(ring)
            for f in b["faces"]:
                ax, _, az = f["p0"]
                bx, _, bz = f["p1"]
                dx, dz = bx - ax, bz - az
                length = math.hypot(dx, dz)
                ox, oz = -dz / length, dx / length
                mx, mz = (ax + bx) / 2 - cx, (az + bz) / 2 - cz
                self.assertGreater(mx * ox + mz * oz, 0.0, "a face's outside is away from the middle")

    def test_shops_and_ways_up(self):
        shops = [b for b in self.buildings() if b["kind"] == "yes" and b["storeys"] != 2]
        self.assertEqual(len(shops), 1)
        grounds = {f["ground"] for f in shops[0]["faces"]}
        self.assertIn("shop", grounds, "the bakery's block has shopfronts on the high street")
        self.assertIn("upper", grounds, "its wall above the lower neighbour is open")
        tall = [b for b in self.buildings() if b["storeys"] >= 2]
        for b in tall:
            self.assertTrue(any(f["pipe"] >= 0 or f["escape"] >= 0 for f in b["faces"]), "every roof has a way up")

    def test_eyes(self):
        eyes = [f["eyes"] for b in self.buildings() for f in b["faces"]]
        self.assertTrue(all(0 <= e <= 100 for e in eyes))
        self.assertGreater(max(eyes), 50)

    def test_lines_steps_water(self):
        kinds = {l["kind"] for t in self.tiles for l in t["lines"]}
        for k in ("kerb", "fence", "wire"):
            self.assertIn(k, kinds)
        props = [p["m"] for t in self.tiles for p in t["props"]]
        self.assertEqual(props.count("street/power_pole"), 2)
        self.assertIn("street/street_lamp", props)
        # Flat land: steps with no rise aren't steps.
        self.assertEqual(sum(len(t["flights"]) for t in self.tiles), 0)
        sea = [t for t in self.tiles if len(t["water"]["tris"]) > 0]
        self.assertTrue(sea, "the sea is drawn")
        for t in sea:
            v = t["water"]["verts"]
            self.assertTrue((v[:, 2] >= 149.0).all(), "the sea is on the coastline's right")

    def test_variant_roundtrip(self):
        value = {"a": [1, 2.5, "x"], "v": godot_variant.Vec3(1, 2, 3), "b": b"\x00\x01"}
        self.assertEqual(godot_variant.decode(godot_variant.encode(value)), value)


if __name__ == "__main__":
    unittest.main()
