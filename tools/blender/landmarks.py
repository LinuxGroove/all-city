"""Landmarks: the big one-off things a town is known by, made generic so
they stand in for the real ones (no names, logos or lettering). Each faces
-y on z = 0 (see ackit.py); run build_art.py to write them to
assets/models/landmark/.

The game places some of them at measured sizes, scaling each uniformly, so
every docstring gives the model's exact height and its footprint (x by y,
the game's x by z), and fit_height() holds the height exactly.
"""
import math

from ackit import ball, blob, box, cyl, fit_height, join, plate, strut, tube

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


def _ring(radius, z, n=24):
    return [(math.cos(2 * math.pi * k / n) * radius, math.sin(2 * math.pi * k / n) * radius, z) for k in range(n + 1)]


@asset
def water_tower():
    """An early-1900s steel water tower: exactly 40.0 m tall, about 13 m
    across the catwalk and 10.5 m between the legs' feet. A round tank (Wall
    role, tinted by the game, usually white) with a coloured band, a conical
    cap and finial, a catwalk ring, on four braced lattice legs round a
    riser pipe."""
    parts = []
    foot, head = 5.2, 4.3
    legs = []
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        legs.append(((math.cos(a) * foot, math.sin(a) * foot, 0.4), (math.cos(a) * head, math.sin(a) * head, 28.6)))
    levels = (0.4, 9.6, 19.0, 28.0)

    def on_leg(leg, z):
        (ax, ay, _az), (bx, by, bz) = leg
        t = (z - leg[0][2]) / (bz - leg[0][2])
        return (ax + (bx - ax) * t, ay + (by - ay) * t, z)

    for leg in legs:
        parts += [
            box((1.3, 1.3, 0.7), (leg[0][0], leg[0][1], 0.0), colour="concrete", bevel=0.08),
            strut(leg[0], leg[1], 0.34, colour="steel_dark", sides=8),
        ]
    for i in range(4):
        a, b = legs[i], legs[(i + 1) % 4]
        for j in range(1, 4):
            parts.append(strut(on_leg(a, levels[j]), on_leg(b, levels[j]), 0.16, colour="steel_dark", sides=6))
        for j in range(3):
            lo, hi = levels[j] + 0.3, levels[j + 1] - 0.3
            parts += [
                strut(on_leg(a, lo), on_leg(b, hi), 0.07, colour="steel", sides=4),
                strut(on_leg(b, lo), on_leg(a, hi), 0.07, colour="steel", sides=4),
            ]
    parts += [
        cyl(0.9, 0.5, colour="concrete", sides=12, bevel=0.05),
        cyl(0.7, 27.5, (0, 0, 0.5), colour="steel", sides=12),
        # The tank: a shallow cone under a drum, a band, a cap.
        cyl(0.9, 2.2, (0, 0, 27.0), colour="white", role="Wall", sides=24, top=5.6),
        cyl(5.6, 8.0, (0, 0, 29.2), colour="white", role="Wall", sides=24),
        cyl(5.66, 1.3, (0, 0, 32.6), colour="signal_red", sides=24),
        cyl(5.9, 0.25, (0, 0, 37.2), colour="steel_dark", sides=24, bevel=0.06),
        cyl(5.75, 2.6, (0, 0, 37.45), colour="white", role="Wall", sides=24, top=0.5),
        cyl(0.55, 0.35, (0, 0, 39.9), colour="steel_dark", sides=10, bevel=0.05),
        ball(0.32, (0, 0, 40.45), colour="steel_dark", subdiv=2),
        cyl(0.05, 0.9, (0, 0, 40.6), colour="steel_dark", sides=6),
        # The catwalk round the tank's foot, with its rail.
        cyl(6.6, 0.18, (0, 0, 28.9), colour="steel_dark", sides=24),
        tube(_ring(6.5, 30.0), 0.06, colour="steel_dark", sides=4, caps=False),
        tube(_ring(6.5, 29.5), 0.04, colour="steel_dark", sides=4, caps=False),
    ]
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        parts.append(strut((math.cos(a) * 6.5, math.sin(a) * 6.5, 29.05), (math.cos(a) * 6.5, math.sin(a) * 6.5, 30.0),
                           0.05, colour="steel_dark", sides=4))
    # A ladder up the tank's front to the cap.
    for x in (-0.28, 0.28):
        parts.append(strut((x, -5.72, 29.1), (x, -5.72, 37.3), 0.05, colour="steel_dark", sides=4))
    for z in range(7):
        parts.append(box((0.56, 0.06, 0.06), (0, -5.72, 29.6 + z * 1.1), colour="steel_dark"))
    return fit_height(join(parts, "water_tower"), 40.0)


@asset
def smokestack():
    """A mill's brick chimney: exactly 33.0 m tall on a stepped square brick
    base 3.2 m across (3.2 x 3.2 m). The round shaft tapers to a corbelled
    crown with a sooty mouth."""
    parts = [
        box((3.2, 3.2, 0.5), colour="stone", bevel=0.05),
        box((2.9, 2.9, 3.6), (0, 0, 0.5), colour="brick", bevel=0.04),
        box((3.1, 3.1, 0.3), (0, 0, 4.1), colour="stone", bevel=0.05),
        box((2.7, 2.7, 0.5), (0, 0, 4.4), colour="brick_dark", bevel=0.04),
        # A bricked-up flue arch on the front.
        box((0.9, 0.12, 1.3), (0, -1.45, 0.9), colour="brick_dark", bevel=0.03),
        cyl(0.45, 0.12, (0, -1.45, 2.2), colour="brick_dark", sides=12, rot=(math.pi / 2, 0, 0)),
        cyl(1.3, 25.8, (0, 0, 4.9), colour="brick", sides=16, top=0.86),
    ]
    # Darker courses round the shaft, and the corbelled crown.
    for z, h in ((12.0, 0.5), (21.5, 0.5)):
        r = 1.3 - (1.3 - 0.86) * (z - 4.9) / 25.8
        parts.append(cyl(r + 0.04, h, (0, 0, z), colour="brick_dark", sides=16, top=r + 0.03))
    z = 30.7
    for r, h, c in ((0.95, 0.4, "brick"), (1.05, 0.4, "brick_dark"), (1.14, 0.45, "brick"),
                    (1.22, 0.55, "brick_dark")):
        parts.append(cyl(r, h, (0, 0, z), colour=c, sides=16, bevel=0.03))
        z += h
    parts += [
        cyl(1.12, 0.3, (0, 0, z), colour="concrete_dark", sides=16, bevel=0.04),
        cyl(0.8, 0.02, (0, 0, z + 0.3), colour="ink", sides=16),
        strut((0.95, 0, z), (0.95, 0, 33.0), 0.03, colour="steel_dark", sides=4),
    ]
    return fit_height(join(parts, "smokestack"), 33.0)


@asset
def bull_statue():
    """A bronze bull on a rough granite block, head a little down, facing
    the game's +z: exactly 3.2 m tall, the plinth 1.0 m and the bull 2.2 m
    to the top of its shoulders, its lowered head and horns under that.
    Footprint 2.2 x 5.4 m (the plinth, centred 0.4 m towards the front; the
    bull is about 2.0 m across the horns and 5.0 m long)."""
    z0 = 1.0
    parts = [
        box((2.2, 5.4, 0.4), (0, -0.4, 0), colour="granite_dark", bevel=0.08),
        box((2.05, 5.2, 0.3), (0.02, -0.35, 0.4), colour="granite", bevel=0.1, rot=(0, 0, 0.02)),
        box((2.0, 5.1, 0.32), (-0.02, -0.44, 0.68), colour="granite", bevel=0.1, rot=(0, 0, -0.015)),
        # The body: barrel, shoulder hump and hindquarters, high on its legs.
        blob((0.62, 1.4, 0.56), (0, 0.15, z0 + 1.45), "bronze", subdiv=3, lumps=0.05, seed=1),
        blob((0.74, 0.85, 0.72), (0, -0.8, z0 + 1.48), "bronze", subdiv=3, lumps=0.06, seed=2),
        blob((0.62, 0.72, 0.62), (0, 1.15, z0 + 1.5), "bronze", subdiv=2, lumps=0.05, seed=3),
        blob((0.38, 0.5, 0.42), (0, -1.3, z0 + 1.05), "bronze_dark", subdiv=2, lumps=0.06, seed=4),
        # Neck, head down and forward, muzzle.
        blob((0.5, 0.6, 0.55), (0, -1.6, z0 + 1.4), "bronze", subdiv=2, lumps=0.05, seed=5),
        blob((0.4, 0.55, 0.44), (0, -2.15, z0 + 1.0), "bronze", subdiv=2, lumps=0.05, seed=6),
        blob((0.34, 0.3, 0.3), (0, -2.58, z0 + 0.68), "bronze_dark", subdiv=2, lumps=0.04, seed=7),
    ]
    for s in (-1, 1):
        # Horns sweep out, then forward and up; ears sit under them.
        a, b, c = (s * 0.26, -2.05, z0 + 1.3), (s * 0.72, -2.02, z0 + 1.38), (s * 0.98, -2.32, z0 + 1.7)
        parts += [
            strut(a, b, 0.11, 0.08, colour="bronze_dark", sides=8),
            strut(b, c, 0.08, 0.02, colour="bronze_dark", sides=8),
            blob((0.2, 0.08, 0.11), (s * 0.46, -1.95, z0 + 1.12), "bronze_dark", subdiv=1, lumps=0.0),
        ]
    # Legs: the near front one a step ahead, the hind ones bent at the hock.
    for x, y, step in ((-0.36, -0.9, -0.25), (0.36, -0.9, 0.05)):
        knee = (x, y + step * 0.5, z0 + 0.55)
        parts += [
            strut((x, y, z0 + 1.25), knee, 0.24, 0.15, colour="bronze", sides=8),
            strut(knee, (x, y + step, z0 + 0.1), 0.14, 0.12, colour="bronze", sides=8),
            cyl(0.16, 0.12, (x, y + step, z0), colour="bronze_dark", sides=8, bevel=0.03),
        ]
    for x in (-0.34, 0.34):
        hock = (x, 1.5, z0 + 0.65)
        parts += [
            strut((x, 1.15, z0 + 1.35), hock, 0.28, 0.14, colour="bronze", sides=8),
            strut(hock, (x, 1.3, z0 + 0.1), 0.13, 0.11, colour="bronze", sides=8),
            cyl(0.16, 0.12, (x, 1.3, z0), colour="bronze_dark", sides=8, bevel=0.03),
        ]
    parts += [
        tube([(0, 1.8, z0 + 1.9), (0.05, 2.0, z0 + 1.55), (0.12, 2.05, z0 + 1.0), (0.15, 2.0, z0 + 0.7)], 0.045,
             colour="bronze_dark", sides=6),
        blob((0.09, 0.09, 0.18), (0.15, 2.0, z0 + 0.58), "bronze_dark", subdiv=2, lumps=0.1, seed=8),
    ]
    return fit_height(join(parts, "bull_statue"), 3.2)


@asset
def light_tower():
    """A ballpark light tower: exactly 30.0 m tall, a tapered steel pole
    with a bank of 18 lamps (3 rows of 6, the Glow role) on a frame at the
    top, aimed at the game's +z. The bank is 7.6 m wide; the footprint is
    7.6 x 2.4 m (the pole's base plate 1.6 x 1.6 m)."""
    parts = [
        box((1.6, 1.6, 0.5), colour="concrete", bevel=0.06),
        cyl(0.6, 25.5, (0, 0, 0.5), colour="steel", sides=12, top=0.32),
        cyl(0.65, 0.4, (0, 0, 0.5), colour="steel_dark", sides=12, bevel=0.04),
        # A ladder up the back of the pole.
        strut((0.18, 0.62, 1.0), (0.18, 0.4, 25.6), 0.04, colour="steel_dark", sides=4),
        strut((-0.18, 0.62, 1.0), (-0.18, 0.4, 25.6), 0.04, colour="steel_dark", sides=4),
        # The catwalk under the bank, with a rail behind.
        box((7.6, 1.6, 0.15), (0, 0.3, 25.6), colour="steel_dark", bevel=0.03),
        box((7.6, 0.06, 0.06), (0, 1.05, 26.6), colour="steel_dark"),
        box((0.9, 0.9, 0.6), (0, 0, 25.0), colour="steel_dark", bevel=0.05),
    ]
    for x in (-3.75, 3.75):
        parts.append(box((0.08, 0.08, 1.0), (x, 1.05, 25.75), colour="steel_dark"))
    # The frame: three rails and uprights, then the lamps on the rails.
    for z in (26.0, 27.35, 28.7, 29.75):
        parts.append(box((7.4, 0.18, 0.18), (0, 0.15, z), colour="steel_dark", bevel=0.03))
    for x in (-3.6, -1.2, 1.2, 3.6):
        parts.append(box((0.18, 0.18, 4.0), (x, 0.15, 25.75), colour="steel_dark", bevel=0.03))
    for row in range(3):
        z = 26.25 + row * 1.35
        for col in range(6):
            x = -3.0 + col * 1.2
            parts += [
                box((1.0, 0.55, 0.95), (x, -0.25, z), colour="steel", bevel=0.08, rot=(-0.22, 0, 0)),
                box((0.8, 0.05, 0.74), (x, -0.56, z + 0.06), colour="lamp_white", role="Glow", bevel=0.02,
                    rot=(-0.22, 0, 0)),
            ]
    parts.append(strut((0, 0.15, 29.9), (0, 0.15, 30.6), 0.03, colour="steel_dark", sides=4))
    return fit_height(join(parts, "light_tower"), 30.0)


@asset
def foul_pole():
    """A ballpark foul pole: exactly 15.0 m tall, yellow, with its mesh fin
    on +x (the fair side, seen face on from home plate at the game's +z;
    turn it round for the other line). Footprint 1.85 x 1.2 m."""
    parts = [
        cyl(0.6, 0.4, colour="concrete", sides=12, bevel=0.05),
        cyl(0.3, 14.4, (0, 0, 0.4), colour="signal_yellow", sides=12, top=0.22),
        cyl(0.26, 0.2, (0, 0, 14.8), colour="signal_yellow", sides=12, bevel=0.06),
        # The fin: a frame round a mesh panel, ribbed so it reads as mesh.
        box((0.12, 0.12, 11.2), (1.25, 0, 3.0), colour="signal_yellow", bevel=0.03),
        box((1.1, 0.12, 0.12), (0.75, 0, 3.0), colour="signal_yellow", bevel=0.03),
        box((1.1, 0.12, 0.12), (0.75, 0, 14.08), colour="signal_yellow", bevel=0.03),
        box((1.0, 0.04, 11.0), (0.75, 0, 3.1), colour="ochre"),
    ]
    for i in range(1, 11):
        parts.append(box((1.0, 0.08, 0.06), (0.75, 0, 3.0 + i * 1.0), colour="signal_yellow"))
    return fit_height(join(parts, "foul_pole"), 15.0)


# The outfield bull, side on and facing -x: (x, z) with the hooves on z = 0.
_BULL = [(2.7, 0.0), (3.35, 0.0), (3.3, 0.7), (3.6, 1.7), (3.75, 2.6), (3.5, 3.3), (3.75, 3.35), (4.2, 3.7),
         (4.4, 4.2), (4.15, 4.25), (3.95, 3.85), (3.55, 3.55), (2.5, 3.45), (0.5, 3.7), (-0.8, 4.3), (-1.6, 4.45),
         (-2.3, 4.2), (-2.9, 3.75), (-3.3, 3.55), (-3.8, 2.8), (-4.05, 2.35), (-4.1, 2.0), (-3.8, 1.85),
         (-3.35, 1.95), (-2.95, 1.75), (-2.6, 1.4), (-2.35, 1.35), (-2.4, 0.5), (-2.5, 0.0), (-1.85, 0.0),
         (-1.85, 0.45), (-1.75, 1.35), (-1.0, 1.55), (0.8, 1.65), (2.0, 1.65), (2.4, 1.3), (2.75, 0.45)]
_HORN = [(-2.75, 3.75), (-2.45, 4.1), (-2.45, 4.6), (-2.75, 5.0), (-3.05, 5.05), (-2.78, 4.75), (-2.78, 4.4),
         (-3.05, 3.85)]
# The far legs, behind the body.
_FAR_LEGS = ([(-1.75, 0.0), (-1.15, 0.0), (-1.2, 1.7), (-1.8, 1.7)],
             [(2.05, 0.0), (2.65, 0.0), (2.95, 0.8), (2.8, 1.9), (2.1, 1.8), (2.3, 0.7)])


@asset
def bull_sign():
    """The outfield bull: a big flat bull cut out side on, on two steel
    posts, over a strip of grass-green panel, eyes lit (Glow). No words.
    Exactly 10.0 m tall; the bull is 6.8 m long with its hooves 6.0 m off
    the ground and its horns 4 m above them. Footprint 7.4 x 1.05 m (the grass panel; the bull itself is 6.8 m)."""
    k = 4.0 / 5.05  # the horn tip 4 m over the hooves
    cx = 0.15
    bull = [((x - cx) * k, z * k) for x, z in _BULL]
    horn = [((x - cx) * k, z * k) for x, z in _HORN]
    # A cream edge: the same outline a little larger, just behind.
    mid_x = sum(p[0] for p in bull) / len(bull)
    mid_z = sum(p[1] for p in bull) / len(bull)
    edge = [(mid_x + (x - mid_x) * 1.035, mid_z + (z - mid_z) * 1.05) for x, z in bull]
    base = 6.0
    parts = [
        plate(bull, 0.3, (0, 0, base), colour="wood_dark"),
        plate(edge, 0.2, (0, 0.12, base - 0.05), colour="cream"),
        plate(horn, 0.36, (0, -0.02, base), colour="cream"),
        plate([(x - 0.35 * k, z) for x, z in horn], 0.36, (0, 0.06, base), colour="cream"),
        box((7.2, 0.25, 0.8), (0, -0.05, base - 0.85), colour="grass", bevel=0.04),
    ]
    parts += [plate([((x - cx) * k, z * k) for x, z in leg], 0.2, (0, 0.1, base), colour="shadow")
              for leg in _FAR_LEGS]
    parts += [
        box((7.4, 0.3, 0.12), (0, -0.05, base - 0.97), colour="steel_dark", bevel=0.02),
    ]
    # The eyes, lit, one on each face.
    for y, turn in ((0.0, math.pi / 2), (0.0, -math.pi / 2)):
        parts.append(cyl(0.14, 0.2, ((-3.4 - cx) * k, y, base + 3.15 * k), colour="signal_red", role="Glow", sides=10,
                         rot=(turn, 0, 0)))
    for x in (-2.0, 2.0):
        parts += [
            box((1.0, 1.0, 0.35), (x, 0.35, 0), colour="concrete", bevel=0.05),
            box((0.35, 0.35, base + 2.2), (x, 0.35, 0), colour="steel_dark", bevel=0.04),
        ]
    for z in (base - 0.6, base + 1.4):
        parts.append(box((4.4, 0.2, 0.2), (0, 0.35, z), colour="steel_dark"))
    return fit_height(join(parts, "bull_sign"), 10.0)


@asset
def scoreboard():
    """A ballpark scoreboard: exactly 13.0 m tall, a dark green board 16 m
    wide and 7 m tall on two legs 6 m high, its face a screen and a grid
    of lit and dark panels (Glass and Glow) in a frame, facing the game's
    +z. Footprint 16.4 x 2.0 m. No words."""
    parts = []
    for x in (-5.5, 5.5):
        parts += [
            box((1.4, 2.0, 0.4), (x, 0.1, 0), colour="concrete", bevel=0.05),
            box((0.8, 0.8, 6.1), (x, 0.1, 0.0), colour="steel_dark", bevel=0.05),
            strut((x, 0.9, 0.4), (x, 0.4, 5.0), 0.1, colour="steel_dark", sides=6),
        ]
    parts += [
        strut((-5.5, 0.1, 1.0), (5.5, 0.1, 5.5), 0.1, colour="steel_dark", sides=6),
        strut((5.5, 0.1, 1.0), (-5.5, 0.1, 5.5), 0.1, colour="steel_dark", sides=6),
        box((16.0, 1.2, 6.7), (0, 0.1, 6.0), colour="iron_green", bevel=0.06),
        box((16.4, 1.6, 0.3), (0, 0.1, 12.7), colour="steel_dark", bevel=0.05),
        box((16.4, 1.6, 0.2), (0, 0.1, 6.0), colour="steel_dark", bevel=0.04),
        # The screen, framed.
        box((9.8, 0.1, 3.7), (-2.6, -0.52, 8.6), colour="steel_dark", bevel=0.03),
        box((9.4, 0.1, 3.3), (-2.6, -0.58, 8.8), colour="glass", role="Glass"),
    ]
    # Ball, strike and out lamps beside the screen.
    for row, colour, n in ((0, "signal_green", 3), (1, "signal_amber", 2), (2, "signal_red", 2)):
        z = 11.6 - row * 1.15
        parts.append(box((0.9, 0.08, 0.5), (3.8, -0.54, z - 0.25), colour="cream", bevel=0.02))
        for i in range(n):
            parts.append(cyl(0.3, 0.12, (5.0 + i * 0.85, -0.6, z), colour=colour, role="Glow", sides=12,
                             rot=(math.pi / 2, 0, 0)))
    # The line score: two rows of twelve panels, some lit.
    for row in range(2):
        z = 6.55 + row * 0.95
        for i in range(12):
            x = -7.0 + i * 1.04 + (0.5 if i >= 10 else 0.0)
            lit = (i * 7 + row * 3) % 5 < 2
            parts.append(box((0.82, 0.08, 0.78), (x, -0.56, z), colour="window_warm" if lit else "glass",
                             role="Glow" if lit else "Glass"))
    # Edge frame round the face.
    for x in (-7.95, 7.95):
        parts.append(box((0.18, 0.2, 6.7), (x, -0.52, 6.0), colour="cream"))
    parts.append(box((16.0, 0.2, 0.16), (0, -0.52, 12.54), colour="cream"))
    parts.append(box((16.0, 0.2, 0.16), (0, -0.52, 8.35), colour="cream"))
    return fit_height(join(parts, "scoreboard"), 13.0)


@asset
def spire():
    """A church steeple's top, to stand on a tower's roof: exactly 14.0 m
    tall, 4.0 m square at the base (4.5 x 4.5 m over the cornice). A
    belfry stage (the Wall role, tinted by the game) with a louvred
    opening on each side, then a tall octagonal slate spire with broaches
    and a finial."""
    parts = [
        box((4.0, 4.0, 4.6), colour="white", role="Wall", bevel=0.03),
        box((4.2, 4.2, 0.35), colour="cream", bevel=0.04),
        box((4.5, 4.5, 0.35), (0, 0, 4.6), colour="cream", bevel=0.05),
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts += [
                box((0.55, 0.55, 4.6), (sx * 1.8, sy * 1.8, 0), colour="white", role="Wall", bevel=0.04),
                cyl(0.3, 1.3, (sx * 2.0, sy * 2.0, 4.95), colour="cream", sides=4, top=0.02, rot=(0, 0, math.pi / 4)),
                cyl(0.95, 1.6, (sx * 1.45, sy * 1.45, 4.95), colour="slate", sides=4, top=0.02,
                    rot=(0, 0, math.pi / 4)),
            ]
    # A louvred opening on each face: dark arch, slats.
    for k in range(4):
        a = k * math.pi / 2
        c, s = math.sin(a), -math.cos(a)
        face = 2.02
        opening = [
            box((1.5, 0.1, 2.3), (c * face, s * face, 1.3), colour="ink", rot=(0, 0, a)),
            cyl(0.75, 0.1, (c * face, s * face, 3.6), colour="ink", sides=16, rot=(math.pi / 2, 0, a)),
            box((1.8, 0.14, 0.14), (c * (face + 0.04), s * (face + 0.04), 1.16), colour="cream", rot=(0, 0, a)),
        ]
        for i in range(6):
            opening.append(box((1.44, 0.07, 0.1), (c * (face + 0.05), s * (face + 0.05), 1.5 + i * 0.4),
                               colour="slate", rot=(-0.6, 0, a)))
        parts += opening
    parts += [
        cyl(1.95, 8.4, (0, 0, 4.95), colour="slate", sides=8, top=0.06, rot=(0, 0, math.pi / 8)),
        cyl(2.0, 0.2, (0, 0, 4.95), colour="steel_dark", sides=8, rot=(0, 0, math.pi / 8)),
        ball(0.2, (0, 0, 13.4), colour="ochre", subdiv=2),
        cyl(0.04, 0.8, (0, 0, 13.3), colour="steel_dark", sides=6),
    ]
    return fit_height(join(parts, "spire"), 14.0)
