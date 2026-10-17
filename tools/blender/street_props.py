"""Street furniture: what stands on a pavement in any town. Each function
builds one model facing -y on z = 0 (see ackit.py) and returns it; run
build_art.py to write them to assets/models/street/.

Kept chunky on purpose: thick posts, big bevels and one bold colour per
part, so they read at a skate's speed under the game's toon light and ink.
"""
import math

from ackit import ball, box, cyl, join, profile, tube

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
