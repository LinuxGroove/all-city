"""Street furniture: what stands on a pavement in any town. Each function
builds one model facing -y on z = 0 (see ackit.py) and returns it; run
build_art.py to write them to assets/models/street/.

Kept chunky on purpose: thick posts, big bevels and one bold colour per
part, so they read at a skate's speed under the game's toon light and ink.
"""
import math

from ackit import ball, blob, box, cyl, fit_height, join, profile, strut, tube

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


@asset
def bollard():
    parts = [
        cyl(0.15, 0.08, colour="steel_dark", bevel=0.02),
        cyl(0.115, 0.78, (0, 0, 0.08), colour="steel_dark", sides=14, top=0.1),
        cyl(0.118, 0.07, (0, 0, 0.6), colour="signal_yellow", sides=14),
        cyl(0.105, 0.06, (0, 0, 0.86), colour="steel_dark", sides=14, bevel=0.02),
        ball(0.1, (0, 0, 0.92), colour="steel_dark", subdiv=2, squash=0.6),
    ]
    return join(parts, "bollard")


@asset
def street_lamp():
    """A sodium lamp: a fluted base, a tall pole and a swan-neck arm."""
    h = 6.2
    parts = [
        cyl(0.22, 0.18, colour="steel_dark", sides=8, bevel=0.03),
        cyl(0.16, 0.7, (0, 0, 0.18), colour="iron_green", sides=8, top=0.11, bevel=0.02),
        cyl(0.13, 0.08, (0, 0, 0.88), colour="iron_green", sides=8, bevel=0.02),
        cyl(0.085, h - 0.96, (0, 0, 0.96), colour="iron_green", sides=10, top=0.06),
        cyl(0.09, 0.1, (0, 0, h - 0.4), colour="signal_yellow", sides=10),
    ]
    # The arm curves out over the street (towards -y).
    arm = []
    for i in range(9):
        t = i / 8
        a = t * math.pi * 0.5
        arm.append((0, -math.sin(a) * 1.1 - t * 0.3, h - 0.1 + math.cos(a) * 0.0 + math.sin(a * 2) * 0.35))
    parts.append(tube(arm, 0.055, colour="iron_green", sides=8))
    hx, hy, hz = 0, arm[-1][1] - 0.05, arm[-1][2] - 0.22
    parts += [
        box((0.34, 0.62, 0.16), (hx, hy, hz), colour="steel_dark", bevel=0.05, segments=2),
        box((0.26, 0.5, 0.05), (hx, hy, hz - 0.03), colour="sodium", role="Glow", bevel=0.015),
        box((0.08, 0.2, 0.06), (hx, hy + 0.2, hz + 0.16), colour="steel_dark", bevel=0.02),
    ]
    return join(parts, "street_lamp")


@asset
def bench():
    parts = []
    for x in (-0.75, 0.75):
        # Cast iron ends: a leg, an arm and a back support.
        parts += [
            box((0.09, 0.56, 0.08), (x, 0.02, 0.0), colour="iron_green", bevel=0.02),
            box((0.08, 0.08, 0.44), (x, -0.2, 0.0), colour="iron_green", bevel=0.02),
            box((0.08, 0.08, 0.44), (x, 0.22, 0.0), colour="iron_green", bevel=0.02),
            box((0.09, 0.5, 0.06), (x, 0.02, 0.42), colour="iron_green", bevel=0.02),
            box((0.08, 0.07, 0.48), (x, 0.26, 0.44), colour="iron_green", bevel=0.02, rot=(-0.2, 0, 0)),
            box((0.08, 0.42, 0.06), (x, -0.02, 0.66), colour="iron_green", bevel=0.025),
        ]
    for y in (-0.16, 0.0, 0.16):
        parts.append(box((1.9, 0.13, 0.05), (0, y, 0.46), colour="wood", bevel=0.02))
    for z in (0.62, 0.8):
        parts.append(box((1.9, 0.05, 0.12), (0, 0.27 + (z - 0.62) * 0.2, z), colour="wood", bevel=0.02,
                         rot=(-0.2, 0, 0)))
    return join(parts, "bench")


@asset
def litter_bin():
    parts = [
        cyl(0.27, 0.06, colour="steel_dark", sides=16, bevel=0.02),
        cyl(0.25, 0.8, (0, 0, 0.06), colour="iron_green", sides=16),
        cyl(0.27, 0.12, (0, 0, 0.82), colour="iron_green", sides=16, bevel=0.03),
        cyl(0.22, 0.04, (0, 0, 0.94), colour="ink", sides=16),
        cyl(0.255, 0.06, (0, 0, 0.5), colour="signal_yellow", sides=16),
    ]
    for k in range(8):
        a = k * math.pi / 4
        parts.append(box((0.06, 0.04, 0.68), (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.1), colour="iron_green",
                         rot=(0, 0, a)))
    return join(parts, "litter_bin")


@asset
def hydrant():
    parts = [
        cyl(0.17, 0.06, colour="signal_red", sides=12, bevel=0.02),
        cyl(0.12, 0.5, (0, 0, 0.06), colour="signal_red", sides=12),
        cyl(0.15, 0.07, (0, 0, 0.5), colour="signal_red", sides=12, bevel=0.02),
        ball(0.12, (0, 0, 0.57), colour="signal_red", squash=0.75),
        cyl(0.04, 0.08, (0, 0, 0.64), colour="chrome", sides=6),
    ]
    for s in (-1, 1):
        parts.append(cyl(0.05, 0.12, (s * 0.12, 0, 0.36), colour="chrome", sides=8, rot=(0, s * math.pi / 2, 0)))
    parts.append(cyl(0.065, 0.1, (0, -0.12, 0.3), colour="chrome", sides=8, rot=(math.pi / 2, 0, 0)))
    return join(parts, "hydrant")


@asset
def sign_post():
    """A one-way sign: no words, so it fits any town."""
    parts = [
        cyl(0.045, 2.7, colour="steel", sides=8),
        cyl(0.05, 0.04, (0, 0, 2.7), colour="steel", sides=8),
        box((0.66, 0.05, 0.42), (0, -0.06, 2.1), colour="white", bevel=0.03),
        box((0.6, 0.03, 0.36), (0, -0.085, 2.13), colour="civic_blue", bevel=0.01),
        box((0.38, 0.03, 0.08), (-0.03, -0.1, 2.27), colour="white"),
        box((0.14, 0.03, 0.14), (0.17, -0.1, 2.24), colour="white", rot=(0, math.pi / 4, 0)),
    ]
    return join(parts, "sign_post")


@asset
def traffic_light():
    parts = [
        cyl(0.11, 0.1, colour="steel_dark", sides=10, bevel=0.02),
        cyl(0.07, 2.6, (0, 0, 0.1), colour="steel_dark", sides=10),
        box((0.34, 0.26, 0.98), (0, -0.06, 2.45), colour="ink", bevel=0.05, segments=2),
    ]
    for i, c in enumerate(("signal_red", "signal_amber", "signal_green")):
        z = 3.18 - i * 0.3
        parts.append(cyl(0.1, 0.03, (0, -0.2, z), colour=c, role="Glow", sides=14, rot=(math.pi / 2, 0, 0)))
        parts.append(box((0.26, 0.16, 0.03), (0, -0.25, z + 0.11), colour="ink", rot=(0.35, 0, 0)))
    parts.append(box((0.2, 0.1, 0.24), (0, 0.1, 1.15), colour="signal_yellow", bevel=0.03))
    return join(parts, "traffic_light")


@asset
def planter():
    parts = [
        box((1.3, 0.7, 0.55), colour="concrete_light", bevel=0.06, segments=2),
        box((1.18, 0.58, 0.04), (0, 0, 0.53), colour="bark"),
        ball(0.36, (-0.32, 0, 0.78), colour="leaf", subdiv=2, squash=0.85),
        ball(0.42, (0.22, 0.04, 0.85), colour="leaf_dark", subdiv=2, squash=0.85),
        ball(0.24, (0.45, -0.12, 0.7), colour="leaf_light", subdiv=1),
    ]
    return join(parts, "planter")


@asset
def utility_box():
    """A street cabinet: the first wall every writer hits."""
    parts = [
        box((0.95, 0.5, 0.12), colour="concrete", bevel=0.02),
        box((0.9, 0.44, 1.2), (0, 0, 0.12), colour="concrete_light", bevel=0.04, segments=2),
        box((0.98, 0.52, 0.06), (0, 0, 1.32), colour="concrete", bevel=0.02),
        box((0.012, 0.02, 1.0), (0, -0.225, 0.22), colour="concrete_dark"),
        box((0.06, 0.03, 0.12), (0.1, -0.235, 0.75), colour="steel_dark", bevel=0.01),
        box((0.06, 0.03, 0.12), (-0.1, -0.235, 0.75), colour="steel_dark", bevel=0.01),
        box((0.16, 0.02, 0.14), (0.28, -0.232, 1.05), colour="signal_yellow", rot=(0, math.pi / 4, 0)),
    ]
    for z in (0.3, 0.38, 0.46):
        parts.append(box((0.3, 0.02, 0.03), (-0.25, -0.232, z), colour="concrete_dark"))
    return join(parts, "utility_box")


@asset
def dumpster():
    parts = []
    for x in (-0.7, 0.7):
        for y in (-0.35, 0.35):
            parts.append(cyl(0.09, 0.07, (x, y, 0.09), colour="rubber", sides=10, rot=(0, math.pi / 2, 0)))
    parts += [
        box((1.7, 0.9, 0.95), (0, 0, 0.15), colour="sea", bevel=0.05, segments=2),
        box((1.78, 0.98, 0.08), (0, 0, 1.1), colour="sea", bevel=0.03),
        box((0.86, 1.0, 0.07), (-0.44, 0.0, 1.18), colour="rubber", bevel=0.03, rot=(0, -0.05, 0)),
        box((0.86, 1.0, 0.07), (0.44, 0.0, 1.18), colour="rubber", bevel=0.03, rot=(0, 0.05, 0)),
        box((1.5, 0.05, 0.1), (0, -0.47, 0.8), colour="signal_yellow"),
    ]
    return join(parts, "dumpster")


@asset
def power_pole():
    """A wooden pole with a crossarm; the wires between poles are grind lines
    the game draws."""
    parts = [
        cyl(0.15, 9.0, colour="wood_dark", sides=10, top=0.12),
        box((2.0, 0.14, 0.14), (0, 0, 8.3), colour="wood_dark", bevel=0.03),
        box((0.08, 0.6, 0.08), (0.55, 0, 7.95), colour="steel_dark", rot=(0.8, 0, 0)),
        box((0.08, 0.6, 0.08), (-0.55, 0, 7.95), colour="steel_dark", rot=(0.8, 0, 0)),
    ]
    for x in (-0.85, 0.0, 0.85):
        parts.append(cyl(0.05, 0.22, (x, 0, 8.44), colour="chrome", sides=8))
    return join(parts, "power_pole")


@asset
def street_tree():
    """A pavement tree in a grate: a round crown on a straight trunk."""
    parts = [
        box((1.0, 1.0, 0.04), colour="steel_dark"),
        cyl(0.12, 2.6, colour="bark", sides=8, top=0.09),
        ball(1.25, (0, 0, 3.5), colour="leaf", subdiv=2, squash=0.95),
        ball(0.85, (0.65, -0.3, 3.0), colour="leaf_dark", subdiv=2),
        ball(0.8, (-0.6, 0.35, 3.15), colour="leaf_light", subdiv=2),
    ]
    return join(parts, "street_tree")


@asset
def tree_oak():
    """A willow oak or red oak over a street or a yard: exactly 12.0 m to the
    top of the crown, about 11 m across. A thick flared trunk forks into
    limbs under a broad crown of lumps in three greens. No grate: the game
    stands it in grass or pavement and scales it by measured height / 12."""
    parts = [
        cyl(0.78, 0.7, colour="bark", sides=8, top=0.48),
        strut((0, 0, 0.6), (0.1, 0.05, 3.6), 0.48, 0.38, colour="bark", sides=8),
    ]
    fork = (0.1, 0.05, 3.4)
    for end, r in (((-2.6, 0.5, 6.6), 0.26), ((2.4, -0.7, 6.8), 0.26), ((0.5, 1.5, 7.6), 0.22),
                   ((-0.8, -1.6, 7.2), 0.2), ((0.2, 0.1, 8.4), 0.26)):
        parts.append(strut(fork, end, r, r * 0.45, colour="bark", sides=6))
    # A broad crown: a ring of lumps round a high middle one, darker
    # underneath and lighter on top, so the toon light reads its shape.
    ring = ((0.0, 3.5, 7.6, 2.5, "leaf_dark", 2), (1.25, 3.0, 7.9, 2.2, "leaf", 2),
            (2.3, 3.4, 7.7, 2.4, "leaf", 2), (3.3, 2.9, 8.1, 2.1, "leaf_dark", 2),
            (4.4, 3.3, 7.5, 2.3, "leaf_dark", 2), (5.4, 2.8, 8.3, 2.0, "leaf", 2))
    for i, (ang, dist, z, r, colour, sub) in enumerate(ring):
        at = (math.cos(ang) * dist * 1.05, math.sin(ang) * dist * 0.85, z)
        parts.append(blob((r * 1.1, r, r * 0.8), at, colour, subdiv=sub, lumps=0.16, seed=i + 1))
    parts += [
        blob((3.4, 3.1, 2.5), (0.2, 0.1, 9.0), "leaf", subdiv=2, lumps=0.14, seed=11),
        blob((2.2, 2.0, 1.5), (-0.9, 0.5, 10.6), "leaf_light", subdiv=2, lumps=0.16, seed=12),
        blob((1.9, 1.7, 1.3), (1.6, -0.6, 10.1), "leaf_light", subdiv=2, lumps=0.16, seed=13),
    ]
    return fit_height(join(parts, "tree_oak"), 12.0)


@asset
def tree_pine():
    """A loblolly pine: exactly 18.0 m to the top, about 7 m across the
    crown. A tall bare trunk with a few broken stubs, and an irregular dark
    crown of clumps in its top third."""
    parts = [
        cyl(0.58, 0.55, colour="bark", sides=8, top=0.4),
        strut((0, 0, 0.45), (0.25, 0.05, 9.0), 0.4, 0.28, colour="bark", sides=8),
        strut((0.25, 0.05, 9.0), (-0.1, 0.15, 16.6), 0.28, 0.12, colour="bark", sides=8),
    ]
    for z, a, l in ((4.8, 0.4, 0.7), (6.6, 2.6, 0.9), (8.2, 4.4, 0.6), (9.8, 1.4, 1.1), (11.0, 3.6, 0.8)):
        x, y = 0.2 + math.cos(a) * 0.25, 0.08 + math.sin(a) * 0.25
        parts.append(strut((x * 0.6, y * 0.6, z), (x + math.cos(a) * l, y + math.sin(a) * l, z + l * 0.35),
                           0.08, 0.04, colour="bark", sides=5))
    clumps = (
        ((1.9, -0.6, 12.6), (1.9, 1.6, 0.85), "pine", 2, 1, (0.2, 0, 11.9)),
        ((-1.8, 0.9, 13.2), (1.8, 1.7, 0.9), "pine", 2, 2, (0.15, 0.05, 12.6)),
        ((0.7, 1.9, 14.3), (1.7, 1.5, 0.9), "pine_light", 2, 3, (0.1, 0.1, 13.6)),
        ((-1.2, -1.5, 14.8), (1.8, 1.6, 0.95), "pine_light", 2, 4, (0.05, 0.1, 14.2)),
        ((1.5, 0.3, 15.7), (1.5, 1.4, 0.9), "pine", 2, 5, (0.0, 0.1, 15.2)),
        ((-1.4, 0.6, 16.2), (1.3, 1.2, 0.85), "pine_light", 2, 6, (-0.05, 0.12, 15.8)),
    )
    for at, radii, colour, sub, seed, root in clumps:
        parts.append(strut(root, at, 0.1, 0.05, colour="bark", sides=5))
        parts.append(blob(radii, at, colour, subdiv=sub, lumps=0.18, seed=seed))
    parts += [
        blob((2.0, 1.9, 1.3), (0.0, 0.1, 14.0), "pine", subdiv=2, lumps=0.16, seed=7),
        blob((1.4, 1.2, 0.95), (0.4, 0.3, 17.0), "pine_light", subdiv=2, lumps=0.16, seed=8),
    ]
    return fit_height(join(parts, "tree_pine"), 18.0)


@asset
def tree_small():
    """A small ornamental tree, a crepe myrtle (or a dogwood): exactly 6.0 m
    to the top, about 4.5 m across. Several pale stems fan out from the
    ground under a rounded crown with a few clusters of pink bloom."""
    parts = [cyl(0.32, 0.25, colour="bark_light", sides=8, top=0.2)]
    for i, (ax, ay, bx, by) in enumerate(((0.1, 0.0, 0.9, -0.4), (-0.1, 0.05, -1.0, 0.2),
                                          (0.0, 0.1, 0.2, 1.0), (0.05, -0.1, -0.2, -1.0))):
        mid = (ax + (bx - ax) * 0.45, ay + (by - ay) * 0.45, 1.6)
        top = (bx, by, 3.3 + 0.2 * (i % 2))
        parts += [
            strut((ax, ay, 0.15), mid, 0.11, 0.08, colour="bark_light", sides=6),
            strut(mid, top, 0.08, 0.05, colour="bark_light", sides=6),
        ]
    for at, radii, colour, sub, seed in (
            ((0.0, 0.0, 4.4), (2.1, 1.9, 1.4), "leaf_light", 2, 1),
            ((-1.1, 0.4, 3.8), (1.2, 1.1, 0.9), "leaf", 2, 2),
            ((1.1, -0.3, 3.9), (1.2, 1.1, 0.9), "leaf", 2, 3),
            ((0.1, 1.0, 4.0), (1.1, 1.0, 0.85), "leaf", 2, 4)):
        parts.append(blob(radii, at, colour, subdiv=sub, lumps=0.14, seed=seed))
    # Bloom in clusters breaking through the top of the crown.
    for i, (x, y, z, r) in enumerate(((0.5, -0.9, 5.2, 0.62), (-0.9, -0.3, 5.3, 0.58), (1.5, 0.3, 4.8, 0.52),
                                      (-0.2, 0.7, 5.6, 0.6), (-1.7, 0.6, 4.4, 0.48), (0.9, -1.4, 4.4, 0.45))):
        parts.append(blob((r, r * 0.95, r * 0.8), (x, y, z), "blossom", subdiv=2, lumps=0.2, seed=20 + i))
    return fit_height(join(parts, "tree_small"), 6.0)


# Far trees: the same silhouette, size and colours as the full ones in a
# handful of faceted lumps (icosahedra) on a plain trunk, under 80
# triangles each, for the thousands of trees past shadow distance.


@asset
def tree_oak_far():
    """tree_oak seen from far off: exactly 12.0 m tall, about 11 m across."""
    parts = [
        cyl(0.42, 6.0, colour="bark", sides=5, top=0.3),
        blob((3.3, 3.6, 2.6), (-2.6, 0.3, 7.9), "leaf_dark", subdiv=1, lumps=0.0, turn=0.5),
        blob((3.2, 3.5, 2.5), (2.5, -0.2, 8.0), "leaf", subdiv=1, lumps=0.0, turn=1.4),
        blob((3.6, 3.6, 2.6), (0.2, 0.1, 9.4), "leaf_light", subdiv=1, lumps=0.0, turn=0.2),
    ]
    return fit_height(join(parts, "tree_oak_far"), 12.0)


@asset
def tree_pine_far():
    """tree_pine seen from far off: exactly 18.0 m tall, about 7 m across."""
    parts = [
        cyl(0.4, 14.5, colour="bark", sides=4, top=0.14),
        blob((2.6, 2.8, 1.4), (1.1, -0.3, 13.0), "pine", subdiv=1, lumps=0.0, turn=0.4),
        blob((2.5, 2.6, 1.4), (-1.1, 0.4, 14.4), "pine", subdiv=1, lumps=0.0, turn=1.3),
        blob((1.9, 2.0, 1.3), (0.4, 0.2, 16.2), "pine_light", subdiv=1, lumps=0.0, turn=0.9),
    ]
    return fit_height(join(parts, "tree_pine_far"), 18.0)


@asset
def tree_small_far():
    """tree_small seen from far off: exactly 6.0 m tall, about 4.5 m across."""
    parts = [
        cyl(0.2, 3.4, colour="bark_light", sides=4, top=0.12),
        blob((2.6, 2.4, 1.5), (0.0, 0.0, 4.2), "leaf_light", subdiv=1, lumps=0.0, turn=0.3),
        blob((1.3, 1.3, 0.9), (-0.9, 0.3, 3.7), "leaf", subdiv=1, lumps=0.0, turn=1.1),
        blob((1.2, 1.2, 0.8), (0.4, -0.5, 5.2), "blossom", subdiv=1, lumps=0.0, turn=0.7),
    ]
    return fit_height(join(parts, "tree_small_far"), 6.0)
