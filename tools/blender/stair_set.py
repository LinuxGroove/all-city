"""The staircase set: the pieces the game lays along every flight of steps
the map has (highway=steps). Treads are 1 m wide and stretched to the
flight's width; walls and balustrades are 1 m long and stretched to fit;
the handrail itself is a tube the game sweeps along the grind line, held up
by these posts.

A tread's top is at z = 0 and its front (the nosing) faces -y, down the
flight; its body reaches down to z = -0.5 so stacked treads leave no gaps.
"""
import math

from ackit import box, cyl, join, prism

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


@asset
def stair_tread():
    parts = [
        box((1.0, 0.34, 0.44), (0, 0.0, -0.5), colour="concrete"),
        box((1.0, 0.36, 0.06), (0, -0.01, -0.06), colour="stone", bevel=0.015),
        box((1.0, 0.035, 0.012), (0, -0.165, -0.006), colour="kerb"),
    ]
    return join(parts, "stair_tread")


@asset
def stair_landing():
    parts = [
        box((1.0, 1.0, 0.44), (0, 0, -0.5), colour="concrete"),
        box((1.0, 1.0, 0.06), (0, 0, -0.06), colour="paving", bevel=0.01),
        box((0.9, 0.9, 0.008), (0, 0, 0.0), colour="stone"),
    ]
    return join(parts, "stair_landing")


@asset
def rail_post():
    """A handrail post, 0.95 m to the rail's underside."""
    parts = [
        box((0.14, 0.14, 0.02), colour="steel_dark", bevel=0.01),
        box((0.055, 0.055, 0.92), (0, 0, 0.02), colour="steel", bevel=0.012),
        box((0.08, 0.08, 0.03), (0, 0, 0.92), colour="steel_dark", bevel=0.01),
    ]
    return join(parts, "rail_post")


@asset
def rail_bracket():
    """Holds a handrail off a wall: the wall is at y = +0.12, the rail's
    middle at the origin's height 0."""
    parts = [
        cyl(0.045, 0.02, (0, 0.12, 0), colour="steel_dark", sides=10, rot=(math.pi / 2, 0, 0)),
        box((0.025, 0.11, 0.025), (0, 0.06, -0.06), colour="steel"),
        box((0.025, 0.025, 0.07), (0, 0.0, -0.07), colour="steel"),
    ]
    return join(parts, "rail_bracket")


@asset
def stair_wall():
    """A 1 m piece of the wall beside a flight: a rendered block with a
    stone coping; stretched along x and in height by the game. Its outer
    face (the paintable one) is -y."""
    parts = [
        box((1.0, 0.36, 0.12), (0, 0, 0.0), colour="concrete_dark"),
        box((1.0, 0.3, 0.86), (0, 0, 0.12), colour="plaster", role="Wall"),
        box((1.02, 0.42, 0.08), (0, 0, 0.98), colour="stone", bevel=0.015),
    ]
    return join(parts, "stair_wall")


@asset
def stair_pier():
    """A pier for the ends of walls and balustrades, with a cap."""
    parts = [
        box((0.44, 0.44, 1.04), colour="plaster", role="Wall", bevel=0.02),
        box((0.52, 0.52, 0.08), (0, 0, 1.04), colour="stone", bevel=0.015),
        prism([(-0.2, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2)], 0.12, (0, 0, 1.12), colour="stone"),
        cyl(0.11, 0.06, (0, 0, 1.24), colour="stone", sides=12),
        cyl(0.07, 0.12, (0, 0, 1.3), colour="stone", sides=12, top=0.02),
    ]
    return join(parts, "stair_pier")


def _baluster(x):
    return [
        cyl(0.06, 0.06, (x, 0, 0.12), colour="stone", sides=10),
        cyl(0.045, 0.16, (x, 0, 0.18), colour="stone", sides=10, top=0.075),
        cyl(0.075, 0.16, (x, 0, 0.34), colour="stone", sides=10, top=0.04),
        cyl(0.04, 0.22, (x, 0, 0.5), colour="stone", sides=10, top=0.035),
        cyl(0.055, 0.06, (x, 0, 0.72), colour="stone", sides=10),
    ]


@asset
def balustrade():
    """A 1 m run of stone balustrade: a plinth, five balusters and a broad
    top rail to grind on."""
    parts = [box((1.0, 0.3, 0.12), colour="stone", bevel=0.01)]
    for i in range(5):
        parts += _baluster(-0.4 + i * 0.2)
    parts.append(box((1.0, 0.32, 0.1), (0, 0, 0.78), colour="stone", bevel=0.02))
    return join(parts, "balustrade")


@asset
def wall_lantern():
    """A lantern on a bracket for stair walls; the wall is at y = +0.1."""
    parts = [
        box((0.14, 0.04, 0.22), (0, 0.08, -0.1), colour="steel_dark", bevel=0.01),
        box((0.03, 0.22, 0.03), (0, -0.02, 0.06), colour="steel_dark"),
        box((0.2, 0.2, 0.04), (0, -0.14, 0.04), colour="steel_dark", bevel=0.01),
        box((0.16, 0.16, 0.24), (0, -0.14, -0.22), colour="lamp_white", role="Glow", bevel=0.01),
        prism([(-0.13, -0.27), (0.13, -0.27), (0.13, -0.01), (-0.13, -0.01)], 0.05, (0, 0, 0.0),
              colour="steel_dark"),
    ]
    return join(parts, "wall_lantern")
