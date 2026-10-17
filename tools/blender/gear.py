"""The writer's gear: the inline skate and the spray can. Each faces -y on
z = 0 (see ackit.py); run build_art.py to write them to assets/models/gear/.

The skate is one foot's, toe to -y, sized for the Universal Base
Characters' feet; the game puts one on each foot bone. The can's body is
the "Wall" role, so the game paints it the colour it sprays.
"""
import math

from ackit import box, cyl, join, profile

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


@asset
def inline_skate():
    """A chunky street skate: a high boot with a cuff and buckles, an
    aluminium frame and four fat wheels."""
    r = 0.034
    parts = [
        # The frame and its wheels.
        box((0.03, 0.3, 0.05), (0, 0.0, 0.03), colour="steel", bevel=0.01),
        box((0.05, 0.08, 0.035), (0, -0.09, 0.065), colour="steel_dark", bevel=0.01),
        box((0.05, 0.08, 0.035), (0, 0.09, 0.065), colour="steel_dark", bevel=0.01),
    ]
    for i in range(4):
        y = -0.12 + i * 0.08
        parts += [
            cyl(r, 0.024, (0.012, y, r), colour="hivis", sides=14, bevel=0.008, rot=(0, math.pi / 2, 0)),
            cyl(r * 0.45, 0.032, (0.016, y, r), colour="chrome", sides=8, rot=(0, math.pi / 2, 0)),
        ]
    # The boot: a sole, the shell, the cuff and the tongue.
    sole = profile([(-0.15, 0.08), (0.13, 0.08), (0.14, 0.1), (-0.15, 0.1)], 0.1, colour="rubber", bevel=0.01)
    shell = profile([(-0.15, 0.1), (0.13, 0.1), (0.13, 0.2), (0.06, 0.24), (-0.02, 0.17), (-0.12, 0.15),
                     (-0.16, 0.12)], 0.096, colour="ink", bevel=0.02)
    cuff = profile([(0.0, 0.18), (0.14, 0.2), (0.14, 0.3), (0.02, 0.3)], 0.104, colour="signal_red", bevel=0.015)
    parts += [
        sole, shell, cuff,
        box((0.06, 0.05, 0.1), (0, -0.0, 0.2), colour="concrete_dark", bevel=0.015, rot=(0.5, 0, 0)),
        box((0.108, 0.02, 0.02), (0, 0.08, 0.27), colour="chrome", bevel=0.005),
        box((0.1, 0.02, 0.016), (0, -0.04, 0.18), colour="signal_red", rot=(0.4, 0, 0)),
        box((0.1, 0.02, 0.016), (0, -0.09, 0.155), colour="signal_red", rot=(0.3, 0, 0)),
        box((0.03, 0.05, 0.03), (0, 0.15, 0.02), colour="rubber", bevel=0.008),
    ]
    return join(parts, "inline_skate")


@asset
def spray_can():
    """A 400 ml can: the body in its paint's colour, a white band, the
    shoulder, the valve and a cap the same colour."""
    h, rad = 0.2, 0.033
    parts = [
        cyl(rad, 0.012, colour="chrome", sides=16, top=rad - 0.003),
        cyl(rad, h - 0.03, (0, 0, 0.012), colour="white", role="Wall", sides=16),
        cyl(rad + 0.0005, 0.03, (0, 0, 0.12), colour="white", sides=16),
        cyl(rad, 0.022, (0, 0, h - 0.018), colour="chrome", sides=16, top=0.014),
        cyl(0.012, 0.012, (0, 0, h + 0.004), colour="chrome", sides=10),
        cyl(0.012, 0.016, (0, 0, h + 0.012), colour="white", sides=10, bevel=0.003),
        box((0.006, 0.006, 0.004), (0, -0.012, h + 0.02), colour="ink"),
    ]
    return join(parts, "spray_can")
