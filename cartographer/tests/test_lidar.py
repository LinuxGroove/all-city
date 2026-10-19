"""The lidar survey on a made-up cloud: ground, a flat-roofed block, a
gabled house and a tree, and the landmarks a map's tags make."""
import math
import unittest

import numpy as np
from shapely.geometry import Polygon

from cartographer import landmarks, lidar, terrain
from cartographer.geo import Box

GROUND = 10.0


def cloud():
    rng = np.random.default_rng(1)
    xs, ys, zs, cls = [], [], [], []

    def add(x, z, y, c):
        xs.append(x)
        zs.append(z)
        ys.append(y)
        cls.append(np.full(len(x), c, np.uint8))

    # Ground everywhere, four points a square metre.
    x = rng.uniform(-60, 60, 120 * 120 * 4)
    z = rng.uniform(-60, 60, len(x))
    add(x, z, np.full(len(x), GROUND), 2)
    # A block 20 x 10 m with a flat roof 12 m up.
    x = rng.uniform(-40, -20, 20 * 10 * 4)
    z = rng.uniform(-40, -30, len(x))
    add(x, z, np.full(len(x), GROUND + 12.0), 6)
    # A house 12 x 8 m, eaves at 5 m, a ridge along x 3 m over them.
    x = rng.uniform(10, 22, 12 * 8 * 6)
    z = rng.uniform(-40, -32, len(x))
    add(x, z, GROUND + 5.0 + 3.0 * (1.0 - np.abs(z + 36.0) / 4.0), 6)
    # A tree 11 m tall, its crown 3 m across.
    r = np.sqrt(rng.uniform(0, 1, 400)) * 3.0
    t = rng.uniform(0, math.tau, len(r))
    add(30 + r * np.cos(t), 30 + r * np.sin(t), GROUND + 11.0 - r * 1.2, 5)
    x, y, z, c = (np.concatenate(a).astype(np.float32 if a is not cls else np.uint8) for a in (xs, ys, zs, cls))
    n = len(x)
    return lidar.Cloud(x, y, z, c, np.ones(n, np.uint8), np.ones(n, np.uint8), None)


class LidarTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.box = Box(-60, -60, 60, 60)
        cls.survey = lidar.Survey(cloud(), cls.box)

    def test_ground(self):
        self.assertAlmostEqual(self.survey.ground_at(0.0, 0.0), GROUND, places=3)
        # Under the block, where no ground was seen, it's filled in.
        self.assertAlmostEqual(self.survey.ground_at(-30.0, -35.0), GROUND, delta=0.05)
        field = lidar.terrain(self.survey, terrain.CELL, terrain.flat(self.box, 0.0))
        self.assertAlmostEqual(float(field.at(0.0, 0.0)), GROUND, delta=0.05)

    def test_flat_roof(self):
        parts = lidar.measure(self.survey, Polygon([(-40, -40), (-20, -40), (-20, -30), (-40, -30)]), GROUND)
        self.assertTrue(parts)
        self.assertAlmostEqual(max(p["top"] for p in parts), GROUND + 12.0, delta=0.3)
        self.assertTrue(all(not p.get("roof") for p in parts))

    def test_gabled_roof(self):
        parts = lidar.measure(self.survey, Polygon([(10, -40), (22, -40), (22, -32), (10, -32)]), GROUND)
        self.assertTrue(parts)
        roof = parts[0].get("roof")
        self.assertTrue(roof, "the house's roof is pitched")
        self.assertIn(roof["shape"], ("gable", "hip"))
        self.assertAlmostEqual(parts[0]["top"], GROUND + 5.0, delta=1.0)

    def test_unsurveyed(self):
        # Nothing stands there: no measurement, so the rules decide.
        self.assertIsNone(lidar.measure(self.survey, Polygon([(40, -50), (50, -50), (50, -40), (40, -40)]),
                                        GROUND))

    def test_trees(self):
        found = lidar.trees(self.survey)
        self.assertEqual(len(found), 1)
        t = found[0]
        self.assertLess(math.hypot(t["p"][0] - 30.0, t["p"][2] - 30.0), 1.5)
        self.assertAlmostEqual(t["p"][1], GROUND, delta=0.1)
        height = lidar.TREE_MODELS[t["m"]] * t["s"]
        self.assertAlmostEqual(height, 11.0, delta=1.0)


class _Map:
    def __init__(self, areas=(), buildings=(), points=()):
        self.areas, self.buildings, self.points = list(areas), list(buildings), list(points)


class LandmarkTest(unittest.TestCase):
    def setUp(self):
        self.field = terrain.flat(Box(-300, -300, 300, 300), 5.0)

    def test_ballpark_and_stand(self):
        # A fan with home plate at the origin, opening north (-z).
        fan = [(0.0, 0.0)] + [(110 * math.sin(a), -110 * math.cos(a))
                              for a in np.linspace(-math.pi / 4, math.pi / 4, 9)]
        stand = [(-30.0, 10.0), (30.0, 10.0), (30.0, 30.0), (-30.0, 30.0)]
        m = _Map(areas=[{"tags": {"leisure": "pitch", "sport": "baseball"}, "polys": [(fan, [])]}],
                 buildings=[{"tags": {"building": "grandstand"}, "polys": [(stand, [])]}])
        found = {lm["kind"]: lm for lm in landmarks.find(m, self.field) if lm}
        park = found["ballpark"]
        self.assertLess(math.hypot(park["home"][0], park["home"][2]), 0.01)
        self.assertAlmostEqual(math.sin(park["yaw"]), 0.0, places=3)
        self.assertLess(math.cos(park["yaw"]), 0.0, "centre field is north")
        st = found["stand"]
        self.assertAlmostEqual(st["height"], landmarks.STAND_HEIGHT)
        ys = [v[1] for v in st["verts"]]
        # Rows rise away from the pitch (round home plate, behind it): the
        # back row is the stand's height.
        self.assertAlmostEqual(max(ys), 5.0 + landmarks.STAND_HEIGHT, places=3)
        front = [v[1] for v in st["verts"] if v[2] < 12.0 and abs(v[0]) < 5.0]
        back = [v[1] for v in st["verts"] if v[2] > 28.0 and abs(v[0]) < 5.0]
        self.assertLess(max(front), min(back))
        self.assertTrue(st["rows"], "row lips to grind")
        self.assertTrue(landmarks.skip_building({"building": "grandstand"}))

    def test_towers(self):
        m = _Map(points=[{"id": 7, "x": 50.0, "z": 50.0, "tags": {"man_made": "water_tower", "height": "30"}},
                         {"id": 8, "x": 52.0, "z": 50.0, "tags": {"man_made": "water_tower"}},
                         {"id": 9, "x": -50.0, "z": 0.0, "tags": {"man_made": "chimney", "name": "Big Stack"}}])
        found = landmarks.find(m, self.field)
        towers = [lm for lm in found if lm["kind"] == "water_tower"]
        self.assertEqual(len(towers), 1, "two points 2 m apart are one tower")
        self.assertAlmostEqual(towers[0]["s"] * landmarks.HEIGHTS["landmark/water_tower"], 30.0, delta=0.1)
        stack = [lm for lm in found if lm["kind"] == "smokestack"][0]
        self.assertEqual(stack["name"], "Big Stack")
        self.assertTrue(landmarks.skip_building({"building": "yes", "man_made": "chimney"}))


if __name__ == "__main__":
    unittest.main()
