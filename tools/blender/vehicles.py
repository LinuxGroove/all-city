"""Vehicles: the town's cars, the Buff's van, Civic's patrol car and its
drone. Each faces -y on z = 0 (see ackit.py); run build_art.py to write
them to assets/models/vehicles/.

Cars are short and chunky, with fat tyres and a glass band, so traffic
reads at a glance. A car's body is the "Wall" role, tinted per car in the
game; the Buff's van and Civic's car wear their own liveries.
"""
import math

from ackit import ball, box, cyl, join, profile, tube

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


def _wheel(x, y, r=0.34, w=0.24, hub="chrome"):
    side = 1 if x > 0 else -1
    rot = (0, math.pi / 2, 0)
    return [
        cyl(r, w, (x - side * w / 2, y, r), colour="rubber", sides=16, bevel=0.06, segments=2, rot=rot),
        cyl(r * 0.55, w + 0.02, (x - side * (w + 0.02) / 2, y, r), colour=hub, sides=10, rot=rot),
        cyl(r * 0.2, w + 0.05, (x - side * (w + 0.05) / 2, y, r), colour="steel_dark", sides=8, rot=rot),
    ]


def _wheels(half_width, ys, r=0.34, w=0.24, hub="chrome"):
    out = []
    for y in ys:
        for x in (-half_width, half_width):
            out += _wheel(x, y, r, w, hub)
    return out


def _lights(front_y, rear_y, half_width, z_front, z_rear, rear_colour="signal_red"):
    out = []
    for s in (-1, 1):
        out += [
            box((0.36, 0.06, 0.16), (s * (half_width - 0.28), front_y - 0.02, z_front), colour="lamp_white",
                role="Glow", bevel=0.03),
            box((0.3, 0.06, 0.2), (s * (half_width - 0.24), rear_y + 0.02, z_rear), colour=rear_colour,
                role="Glow", bevel=0.03),
        ]
    return out


def _plate(y, z, facing):
    """A blank number plate: no letters, so no real car's plate."""
    return box((0.5, 0.03, 0.12), (0, y + facing * 0.015, z), colour="white", bevel=0.01)


@asset
def hatchback():
    """The town's car: 3.9 m, with a body the game tints per car."""
    hw = 0.86
    body = profile([(-1.95, 0.3), (1.95, 0.3), (1.97, 0.62), (1.9, 0.98), (1.62, 1.02), (-1.02, 1.0),
                    (-1.86, 0.86), (-1.98, 0.6)], hw * 2, colour="white", role="Wall", bevel=0.09)
    glass = profile([(-1.02, 0.98), (1.62, 1.0), (1.5, 1.42), (-0.2, 1.44)], hw * 2 - 0.2, colour="glass",
                    role="Glass", bevel=0.04)
    roof = profile([(-0.25, 1.4), (1.52, 1.38), (1.45, 1.5), (-0.1, 1.52)], hw * 2 - 0.16, colour="white",
                   role="Wall", bevel=0.05)
    parts = [body, glass, roof]
    # Pillars between the windows, in the body's colour.
    for x in (-hw + 0.1, hw - 0.1):
        parts += [
            box((0.06, 0.1, 0.46), (x, 0.55, 0.98), colour="white", role="Wall"),
            box((0.06, 0.16, 0.42), (x, 1.5, 0.98), colour="white", role="Wall", rot=(0.25, 0, 0)),
        ]
    parts += [
        box((hw * 2 + 0.04, 0.22, 0.24), (0, -1.95, 0.28), colour="rubber", bevel=0.06),
        box((hw * 2 + 0.04, 0.22, 0.24), (0, 1.95, 0.28), colour="rubber", bevel=0.06),
        box((hw * 2 + 0.06, 3.0, 0.1), (0, 0.0, 0.26), colour="rubber", bevel=0.03),
        box((0.9, 0.04, 0.12), (0, -2.0, 0.66), colour="steel_dark", bevel=0.02),
        _plate(-2.07, 0.34, -1), _plate(2.07, 0.34, 1),
    ]
    for s in (-1, 1):
        parts.append(box((0.1, 0.16, 0.08), (s * (hw + 0.04), -0.75, 0.92), colour="steel_dark", bevel=0.03))
    parts += _lights(-1.96, 1.94, hw, 0.68, 0.74)
    parts += _wheels(hw + 0.02, (-1.22, 1.22))
    return join(parts, "hatchback")


@asset
def buff_van():
    """The Buff's van: a tall white panel van in hi-vis livery, with an
    amber beacon, a ladder on the roof and the pressure washer's reel."""
    hw = 0.98
    body = profile([(-2.4, 0.34), (2.4, 0.34), (2.42, 2.12), (-1.25, 2.12), (-1.6, 1.32), (-2.38, 1.1),
                    (-2.44, 0.62)], hw * 2, colour="white", bevel=0.1)
    glass = profile([(-1.58, 1.3), (-1.2, 2.04), (-0.8, 2.04), (-0.8, 1.3)], hw * 2 + 0.02, colour="glass",
                    role="Glass", bevel=0.03)
    parts = [body, glass]
    # Hi-vis livery: a band down each side and chevrons on the back.
    parts.append(box((hw * 2 + 0.03, 3.1, 0.28), (0, 0.75, 0.9), colour="hivis"))
    parts.append(box((hw * 2 + 0.03, 0.8, 0.28), (0, -1.6, 0.9), colour="hivis"))
    for i in range(5):
        c = "signal_red" if i % 2 == 0 else "signal_yellow"
        parts.append(box((0.32, 0.03, 0.9), (-0.72 + i * 0.36, 2.425, 0.55), colour=c, rot=(0, 0.6, 0)))
    parts += [
        box((0.03, 0.02, 1.4), (0, 2.43, 0.6), colour="steel_dark"),
        box((hw * 2 + 0.06, 0.24, 0.28), (0, -2.42, 0.3), colour="rubber", bevel=0.07),
        box((hw * 2 + 0.06, 0.2, 0.26), (0, 2.42, 0.3), colour="rubber", bevel=0.06),
        box((hw * 2 + 0.06, 4.0, 0.12), (0, 0.0, 0.3), colour="rubber", bevel=0.03),
        box((1.0, 0.04, 0.2), (0, -2.46, 0.7), colour="steel_dark", bevel=0.02),
        _plate(-2.55, 0.38, -1), _plate(2.53, 0.38, 1),
        # A sliding door's seam and its handle.
        box((0.02, 0.04, 1.5), (-hw - 0.01, -0.6, 0.45), colour="concrete_dark"),
        box((0.02, 0.04, 1.5), (-hw - 0.01, 0.75, 0.45), colour="concrete_dark"),
        box((0.04, 0.24, 0.06), (-hw - 0.02, -0.4, 1.15), colour="steel_dark"),
    ]
    for s in (-1, 1):
        parts.append(box((0.12, 0.2, 0.22), (s * (hw + 0.06), -1.4, 1.5), colour="rubber", bevel=0.04))
    # The roof: rack, ladder and beacon.
    for y in (-0.6, 0.4, 1.6):
        parts.append(box((hw * 2 - 0.2, 0.08, 0.08), (0, y, 2.12), colour="steel"))
    for x in (-0.3, 0.3):
        parts.append(box((0.06, 2.8, 0.06), (x, 0.7, 2.2), colour="chrome"))
    for i in range(9):
        parts.append(box((0.6, 0.04, 0.04), (0, -0.6 + i * 0.32, 2.21), colour="chrome"))
    parts += [
        box((0.5, 0.26, 0.08), (0, -1.0, 2.12), colour="steel_dark", bevel=0.02),
        box((0.36, 0.18, 0.16), (0, -1.0, 2.2), colour="signal_amber", role="Glow", bevel=0.05, segments=2),
        # The hose reel on the back step.
        cyl(0.3, 0.2, (0.5, 2.62, 0.62), colour="signal_yellow", rot=(math.pi / 2, 0, 0), bevel=0.04),
        cyl(0.16, 0.24, (0.5, 2.64, 0.62), colour="rubber", rot=(math.pi / 2, 0, 0)),
        box((1.6, 0.3, 0.06), (0, 2.6, 0.36), colour="steel"),
    ]
    parts += _lights(-2.44, 2.42, hw, 0.82, 1.2, rear_colour="signal_red")
    parts += _wheels(hw + 0.02, (-1.55, 1.6), r=0.36, w=0.26, hub="steel")
    return join(parts, "buff_van")


@asset
def civic_car():
    """Civic's patrol car: a low estate in white and civic blue, with a
    light bar that the game lights when the heat is up."""
    hw = 0.9
    body = profile([(-2.2, 0.3), (2.2, 0.3), (2.22, 0.6), (2.16, 1.0), (-1.2, 1.0), (-2.1, 0.86),
                    (-2.24, 0.58)], hw * 2, colour="white", bevel=0.09)
    glass = profile([(-1.2, 0.98), (2.1, 0.98), (1.95, 1.42), (-0.35, 1.42)], hw * 2 - 0.18, colour="glass",
                    role="Glass", bevel=0.04)
    roof = profile([(-0.4, 1.38), (1.98, 1.38), (1.92, 1.48), (-0.25, 1.48)], hw * 2 - 0.14, colour="white",
                   bevel=0.04)
    parts = [body, glass, roof]
    for x in (-hw + 0.1, hw - 0.1):
        parts += [
            box((0.06, 0.1, 0.44), (x, 0.55, 0.98), colour="white"),
            box((0.06, 0.1, 0.44), (x, 1.85, 0.98), colour="white"),
        ]
    # Livery: a blue band with a checker strip, both sides.
    parts.append(box((hw * 2 + 0.03, 4.1, 0.2), (0, 0.0, 0.62), colour="civic_blue"))
    for i in range(14):
        c = "signal_yellow" if i % 2 == 0 else "civic_blue"
        parts.append(box((hw * 2 + 0.035, 0.29, 0.08), (0, -1.9 + i * 0.29, 0.54), colour=c))
    parts += [
        box((hw * 2 + 0.04, 0.22, 0.24), (0, -2.2, 0.28), colour="rubber", bevel=0.06),
        box((hw * 2 + 0.04, 0.22, 0.24), (0, 2.2, 0.28), colour="rubber", bevel=0.06),
        box((hw * 2 + 0.06, 3.4, 0.1), (0, 0.0, 0.26), colour="rubber", bevel=0.03),
        box((1.0, 0.04, 0.12), (0, -2.25, 0.66), colour="steel_dark", bevel=0.02),
        _plate(-2.33, 0.34, -1), _plate(2.33, 0.34, 1),
        # The light bar: blue and amber, on a black base.
        box((1.2, 0.3, 0.06), (0, 0.6, 1.48), colour="rubber", bevel=0.02),
    ]
    for i, c in enumerate(("civic_blue", "signal_amber", "signal_amber", "civic_blue")):
        parts.append(box((0.26, 0.24, 0.12), (-0.42 + i * 0.28, 0.6, 1.53), colour=c, role="Glow", bevel=0.04))
    parts += _lights(-2.21, 2.19, hw, 0.68, 0.76)
    parts += _wheels(hw + 0.02, (-1.38, 1.4), hub="steel")
    return join(parts, "civic_car")


@asset
def drone():
    """Civic's drone: four rotors in guards round a body with a searchlight
    underneath. It hovers, so it stands on its own lowest point."""
    parts = [
        box((0.5, 0.62, 0.2), (0, 0, 0.18), colour="white", bevel=0.08, segments=2),
        box((0.36, 0.3, 0.1), (0, -0.05, 0.38), colour="civic_blue", bevel=0.04),
        box((0.52, 0.12, 0.06), (0, -0.32, 0.26), colour="civic_blue", bevel=0.02),
        # The searchlight in its gimbal.
        cyl(0.12, 0.08, (0, -0.1, 0.1), colour="steel_dark", sides=12),
        cyl(0.1, 0.1, (0, -0.1, 0.0), colour="steel_dark", sides=12, bevel=0.03),
        cyl(0.08, 0.02, (0, -0.1, -0.01), colour="lamp_white", role="Glow", sides=12),
        box((0.1, 0.04, 0.04), (0, -0.33, 0.28), colour="signal_red", role="Glow", bevel=0.01),
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 0.52, sy * 0.52
            parts.append(tube([(sx * 0.2, sy * 0.24, 0.26), (cx, cy, 0.3)], 0.04, colour="steel_dark", sides=8))
            ring = [(cx + 0.3 * math.cos(t * math.pi / 8), cy + 0.3 * math.sin(t * math.pi / 8), 0.32)
                    for t in range(17)]
            parts.append(tube(ring, 0.025, colour="civic_blue", sides=6, caps=False))
            parts += [
                cyl(0.05, 0.12, (cx, cy, 0.26), colour="steel_dark", sides=10),
                box((0.5, 0.06, 0.012), (cx, cy, 0.37), colour="concrete_dark", rot=(0, 0, sx * sy * 0.6)),
            ]
    for sx in (-1, 1):
        parts += [
            box((0.04, 0.04, 0.16), (sx * 0.2, -0.2, 0.0), colour="steel_dark"),
            box((0.04, 0.04, 0.16), (sx * 0.2, 0.2, 0.0), colour="steel_dark"),
            box((0.05, 0.5, 0.04), (sx * 0.2, 0, -0.02), colour="steel_dark", bevel=0.015),
        ]
    ob = join(parts, "drone")
    return ob
