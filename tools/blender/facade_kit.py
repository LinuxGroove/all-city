"""The facade kit: the modules the game lays along every wall of every
building the map has, one storey and one bay at a time.

A bay is 2 m wide (x from -1 to 1; the game stretches it from about 1.5 to
3 m to fit a wall exactly) and a storey 3 m tall (z from 0 to 3). The wall's
outer face is the plane y = 0, its front faces -y and the wall is 0.3 m
thick behind it. Wall surfaces use the "Wall" role so each building gets its
own colour; frames, sills and trim are fixed swatches, and glass lights up
per window at night.

Ground floors: shop, shutter, door and plain. Upper floors: windows in
several kinds. The top: cornice and parapet. Plus the pieces that make a
facade climbable (drainpipes and fire escapes) and the roof's furniture.
"""
import math

from ackit import box, cyl, join, profile, prism, tube

ASSETS = {}
T = 0.3       # wall thickness
W = 2.0       # bay width
H = 3.0       # storey height


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


def wall_with(openings, colour="white", z0=0.0, z1=H):
    """The wall slab of one bay with rectangular holes [(x0, x1, z0, z1)]."""
    xs = sorted({-W / 2, W / 2} | {o[0] for o in openings} | {o[1] for o in openings})
    parts = []
    for a, b in zip(xs, xs[1:]):
        mid = (a + b) / 2
        holes = sorted((o[2], o[3]) for o in openings if o[0] < mid < o[1])
        z = z0
        for h0, h1 in holes + [(z1, z1)]:
            if h0 > z + 1e-4:
                parts.append(box((b - a, T, h0 - z), ((a + b) / 2, T / 2, z), colour=colour, role="Wall"))
            z = max(z, h1)
    return parts


def reveal(x0, x1, z0, z1, depth=0.24, colour="plaster"):
    """The inner sides of an opening, a shade lighter than the wall."""
    w, h = x1 - x0, z1 - z0
    cx = (x0 + x1) / 2
    return [
        box((0.04, depth, h), (x0 + 0.02, depth / 2, z0), colour=colour),
        box((0.04, depth, h), (x1 - 0.02, depth / 2, z0), colour=colour),
        box((w, depth, 0.04), (cx, depth / 2, z1 - 0.04), colour=colour),
    ]


def sash(x0, x1, z0, z1, frame="white", inset=0.2, panes=(2, 2)):
    """A framed window set back `inset` into its opening."""
    w, h = x1 - x0, z1 - z0
    cx = (x0 + x1) / 2
    f = 0.06
    parts = [
        box((w - 0.08, 0.02, h - 0.04), (cx, inset + 0.02, z0 + 0.02), colour="glass", role="Glass"),
        box((w - 0.06, 0.07, f), (cx, inset, z0 + 0.02), colour=frame),
        box((w - 0.06, 0.07, f), (cx, inset, z1 - 0.04 - f), colour=frame),
        box((f, 0.07, h - 0.04), (x0 + 0.04 + f / 2, inset, z0 + 0.02), colour=frame),
        box((f, 0.07, h - 0.04), (x1 - 0.04 - f / 2, inset, z0 + 0.02), colour=frame),
    ]
    cols, rows = panes
    for i in range(1, cols):
        x = x0 + w * i / cols
        parts.append(box((0.035, 0.05, h - 0.1), (x, inset - 0.01, z0 + 0.05), colour=frame))
    for j in range(1, rows):
        z = z0 + h * j / rows
        parts.append(box((w - 0.1, 0.05, 0.035), (cx, inset - 0.01, z - 0.0175), colour=frame))
    return parts


def sill(x0, x1, z, colour="stone"):
    return [box((x1 - x0 + 0.16, 0.14, 0.07), ((x0 + x1) / 2, -0.05, z - 0.07), colour=colour, bevel=0.015)]


def lintel(x0, x1, z, colour="stone", key=True):
    parts = [box((x1 - x0 + 0.12, 0.06, 0.14), ((x0 + x1) / 2, -0.02, z), colour=colour, bevel=0.01)]
    if key:
        parts.append(prism([(-0.09, -0.07), (0.09, -0.07), (0.06, 0.0), (-0.06, 0.0)], 0.0001, (0, 0, 0)))
        parts[-1] = box((0.16, 0.08, 0.2), ((x0 + x1) / 2, -0.03, z - 0.02), colour=colour, bevel=0.015)
    return parts


def string_course(z=0.0, colour="stone"):
    """The band at each floor line that ties a facade's storeys together."""
    return [box((W, 0.06, 0.12), (0, -0.03, z), colour=colour)]


@asset
def wall_plain():
    return join(wall_with([]) + string_course(), "wall_plain")


@asset
def window_sash():
    o = (-0.48, 0.48, 0.8, 2.4)
    parts = wall_with([o]) + reveal(*o) + sash(*o) + sill(o[0], o[1], o[2]) + lintel(o[0], o[1], o[3])
    return join(parts + string_course(), "window_sash")


@asset
def window_shutters():
    """A window with open shutters, the Mediterranean way: the shutters take
    the building's second colour."""
    o = (-0.45, 0.45, 0.8, 2.35)
    parts = wall_with([o]) + reveal(*o) + sash(*o, panes=(2, 3)) + sill(o[0], o[1], o[2])
    for s in (-1, 1):
        x = s * (0.45 + 0.23)
        parts.append(box((0.44, 0.04, 1.55), (x, -0.03, 0.8), colour="teal", bevel=0.01))
        for k in range(7):
            parts.append(box((0.38, 0.03, 0.03), (x, -0.06, 0.95 + k * 0.19), colour="iron_green"))
    parts.append(box((0.98, 0.05, 0.1), (0, -0.02, 2.36), colour="plaster"))
    return join(parts + string_course(), "window_shutters")


@asset
def window_balcony():
    """A tall window onto a little balcony with an iron railing: a ledge to
    land on and a rail to grind."""
    o = (-0.5, 0.5, 0.1, 2.5)
    parts = wall_with([o]) + reveal(*o) + sash(*o, panes=(2, 3)) + lintel(o[0], o[1], o[3])
    parts.append(box((1.5, 0.62, 0.12), (0, -0.31, 0.0), colour="stone", bevel=0.02))
    parts.append(box((1.4, 0.06, 0.06), (0, -0.58, 1.02), colour="ink", bevel=0.01))
    for x in (-0.68, 0.68):
        parts.append(box((0.05, 0.56, 0.05), (x, -0.31, 1.02), colour="ink"))
        parts.append(box((0.05, 0.05, 0.9), (x, -0.58, 0.12), colour="ink"))
    for k in range(9):
        parts.append(box((0.025, 0.025, 0.88), (-0.6 + k * 0.15, -0.58, 0.12), colour="ink"))
    return join(parts + string_course(), "window_balcony")


@asset
def window_twin():
    a = (-0.75, -0.12, 0.8, 2.3)
    b = (0.12, 0.75, 0.8, 2.3)
    parts = wall_with([a, b])
    for o in (a, b):
        parts += reveal(*o) + sash(*o, panes=(1, 2)) + sill(o[0], o[1], o[2])
    parts += lintel(-0.75, 0.75, 2.3, key=False)
    return join(parts + string_course(), "window_twin")


@asset
def window_modern():
    """A wide strip window in a flat frame, for newer blocks."""
    o = (-0.9, 0.9, 0.9, 2.45)
    parts = wall_with([o]) + reveal(*o, depth=0.12) + sash(*o, frame="steel_dark", inset=0.1, panes=(3, 1))
    parts.append(box((1.84, 0.1, 0.05), (0, -0.04, 0.85), colour="steel_dark"))
    return join(parts + string_course(colour="concrete_light"), "window_modern")


@asset
def shop_front():
    """A lit shopfront: a big window on a low riser and a fascia with a neon
    strip. Signs are made-up kinds, never a real shop's name."""
    o = (-0.88, 0.88, 0.35, 2.35)
    parts = wall_with([o], z1=2.45)
    parts += [
        box((1.8, 0.04, 2.0), (0, 0.16, 0.35), colour="window_warm", role="Glow"),
        box((1.8, 0.03, 1.98), (0, 0.12, 0.36), colour="glass", role="Glass"),
        box((1.84, 0.12, 0.08), (0, 0.1, 0.3), colour="ink"),
        box((1.84, 0.12, 0.08), (0, 0.1, 2.3), colour="ink"),
        box((0.06, 0.12, 2.0), (0, 0.1, 0.35), colour="ink"),
        box((2.0, 0.22, 0.55), (0, -0.08, 2.45), colour="ink", bevel=0.02),
        box((1.8, 0.03, 0.05), (0, -0.2, 2.5), colour="neon_cyan", role="Glow"),
        box((1.8, 0.03, 0.05), (0, -0.2, 2.9), colour="neon_cyan", role="Glow"),
        box((1.9, 0.18, 0.35), (0, -0.02, 0.0), colour="concrete_dark"),
    ]
    return join(parts, "shop_front")


@asset
def shop_shutter():
    """A shop shut for the night behind a roller shutter: the flattest,
    widest canvas on the street."""
    o = (-0.9, 0.9, 0.0, 2.4)
    parts = wall_with([o], z1=2.45)
    for k in range(24):
        z = 0.02 + k * 0.1
        parts.append(box((1.8, 0.05, 0.085), (0, 0.08, z), colour="steel" if k % 2 else "chrome", bevel=0.012))
    parts += [
        box((0.08, 0.14, 2.4), (-0.92, 0.04, 0.0), colour="steel_dark"),
        box((0.08, 0.14, 2.4), (0.92, 0.04, 0.0), colour="steel_dark"),
        box((2.0, 0.3, 0.32), (0, -0.05, 2.4), colour="steel_dark", bevel=0.03),
        box((2.0, 0.22, 0.28), (0, -0.08, 2.72), colour="ink", bevel=0.02),
        box((1.8, 0.03, 0.04), (0, -0.2, 2.86), colour="neon_pink", role="Glow"),
    ]
    return join(parts, "shop_shutter")


@asset
def door():
    """A front door with a fanlight, a step and a lamp."""
    o = (-0.55, 0.55, 0.0, 2.6)
    parts = wall_with([o]) + reveal(*o, depth=0.28)
    parts += [
        box((1.0, 0.06, 2.0), (0, 0.24, 0.15), colour="wood_dark", bevel=0.01),
        box((0.38, 0.03, 0.8), (-0.24, 0.2, 1.1), colour="wood"),
        box((0.38, 0.03, 0.8), (0.24, 0.2, 1.1), colour="wood"),
        box((0.38, 0.03, 0.6), (-0.24, 0.2, 0.35), colour="wood"),
        box((0.38, 0.03, 0.6), (0.24, 0.2, 0.35), colour="wood"),
        box((1.0, 0.03, 0.38), (0, 0.26, 2.17), colour="window_warm", role="Glow"),
        box((1.04, 0.06, 0.06), (0, 0.22, 2.14), colour="white"),
        box((1.3, 0.4, 0.15), (0, -0.12, 0.0), colour="stone", bevel=0.02),
        box((0.08, 0.03, 0.08), (0.3, 0.2, 1.05), colour="signal_yellow"),
    ]
    parts += lintel(o[0], o[1], o[3])
    return join(parts + string_course(), "door")


@asset
def ground_plain():
    """A ground floor with no openings: a dark plinth and a smooth render."""
    parts = wall_with([], z0=0.5) + [box((W, T + 0.04, 0.5), (0, T / 2 - 0.02, 0.0), colour="concrete_dark")]
    return join(parts, "ground_plain")


@asset
def cornice():
    """The moulding along the top of a facade, 0.6 m tall: its top is a ledge
    the game makes grindable."""
    prof = [(0.0, 0.0), (0.0, 0.6), (-0.42, 0.6), (-0.42, 0.5), (-0.3, 0.46), (-0.3, 0.36), (-0.18, 0.3),
            (-0.18, 0.18), (-0.08, 0.14), (-0.08, 0.0)]
    parts = [profile(prof, W, (0, 0, 0), colour="stone"),
             box((W, T, 0.6), (0, T / 2, 0.0), colour="white", role="Wall")]
    for x in (-0.6, 0.0, 0.6):
        parts.append(box((0.14, 0.2, 0.2), (x, -0.12, 0.12), colour="stone", bevel=0.02))
    return join(parts, "cornice")


@asset
def parapet():
    """A low wall round a flat roof, with a coping to grind."""
    parts = [box((W, T, 0.85), (0, T / 2, 0.0), colour="white", role="Wall"),
             box((W, T + 0.12, 0.1), (0, T / 2, 0.85), colour="stone", bevel=0.015),
             box((W, 0.04, 0.08), (0, -0.02, 0.0), colour="stone")]
    return join(parts, "parapet")


@asset
def pier():
    """A corner pier with quoins, 3 m tall, set over a building's corners so
    two facades meet cleanly."""
    parts = [box((0.5, 0.5, H), (0, 0.2, 0), colour="white", role="Wall")]
    for k in range(5):
        wide = k % 2 == 0
        parts.append(box((0.56 if wide else 0.46, 0.56 if wide else 0.46, 0.5), (0, 0.2, 0.05 + k * 0.6),
                         colour="stone", bevel=0.03))
    return join(parts, "pier")


@asset
def drainpipe():
    """One storey of drainpipe with its brackets: a way up for the skater."""
    parts = [cyl(0.065, H, (0, -0.14, 0), colour="steel_dark", sides=10)]
    for z in (0.4, 2.2):
        parts.append(box((0.18, 0.16, 0.05), (0, -0.07, z), colour="steel_dark"))
        parts.append(cyl(0.08, 0.06, (0, -0.14, z - 0.005), colour="steel_dark", sides=10))
    return join(parts, "drainpipe")


@asset
def drain_hopper():
    parts = [cyl(0.065, 0.6, (0, -0.14, 0), colour="steel_dark", sides=10),
             prism([(-0.16, -0.3), (0.16, -0.3), (0.12, 0.0), (-0.12, 0.0)], 0.26, (0, 0, 0.6), colour="steel_dark"),
             box((0.4, 0.38, 0.06), (0, -0.16, 0.86), colour="steel_dark", bevel=0.01)]
    return join(parts, "drain_hopper")


@asset
def drain_shoe():
    pts = [(0, -0.14, 0.7), (0, -0.14, 0.25), (0, -0.2, 0.12), (0, -0.36, 0.08)]
    return join([tube(pts, 0.065, colour="steel_dark", sides=10)], "drain_shoe")


def _railing(x0, x1, y, z, h=1.0, colour="ink"):
    parts = [box((x1 - x0, 0.05, 0.05), ((x0 + x1) / 2, y, z + h - 0.05), colour=colour)]
    n = max(2, int((x1 - x0) / 0.12))
    for k in range(n + 1):
        parts.append(box((0.025, 0.025, h - 0.05), (x0 + (x1 - x0) * k / n, y, z), colour=colour))
    return parts


@asset
def fire_escape():
    """One storey of fire escape: a landing at the floor line with its
    railing, and the stair down to the landing below."""
    d = 1.1
    parts = []
    for k in range(10):
        parts.append(box((2.4, 0.07, 0.04), (0, -0.08 - k * 0.11, 0.0), colour="steel_dark"))
    parts += [box((2.4, 0.06, 0.12), (0, -d, -0.06), colour="steel_dark"),
              box((0.06, d, 0.12), (-1.2, -d / 2, -0.06), colour="steel_dark"),
              box((0.06, d, 0.12), (1.2, -d / 2, -0.06), colour="steel_dark")]
    parts += _railing(-1.2, 1.2, -d, 0.06, colour="steel_dark")
    for x in (-1.2, 1.2):
        parts += [box((0.04, d, 0.04), (x, -d / 2, 1.02), colour="steel_dark")]
    # The stair down: from this landing's right end to the one below.
    steps = 14
    for k in range(steps):
        t = k / steps
        parts.append(box((0.5, 0.08, 0.03), (1.0 - t * 1.6, -d + 0.5, -t * H), colour="steel_dark",
                         rot=(0, 0, 0)))
    for y in (-d + 0.26, -d + 0.74):
        parts.append(tube([(1.15, y, 0.0), (-0.65, y, -H)], 0.025, colour="steel_dark", sides=6))
    parts.append(tube([(1.15, -d + 0.74, 0.95), (-0.65, -d + 0.74, -H + 0.95)], 0.025, colour="steel_dark", sides=6))
    for x in (-1.15, 1.15):
        parts.append(box((0.06, 0.24, 0.06), (x, -0.12, -0.25), colour="steel_dark", rot=(0.6, 0, 0)))
    return join(parts, "fire_escape")


@asset
def fire_ladder():
    """The drop ladder under the lowest landing of a fire escape."""
    parts = []
    for x in (-0.22, 0.22):
        parts.append(box((0.04, 0.04, 2.6), (x, -0.95, -0.2), colour="steel_dark"))
    for k in range(9):
        parts.append(box((0.44, 0.03, 0.03), (0, -0.95, k * 0.3), colour="steel_dark"))
    return join(parts, "fire_ladder")


@asset
def ac_unit():
    parts = [box((0.82, 0.42, 0.58), (0, -0.21, 0.0), colour="concrete_light", bevel=0.03, segments=2),
             cyl(0.2, 0.03, (-0.12, -0.43, 0.29), colour="ink", sides=16, rot=(math.pi / 2, 0, 0)),
             cyl(0.05, 0.04, (-0.12, -0.45, 0.29), colour="steel", sides=8, rot=(math.pi / 2, 0, 0)),
             box((0.16, 0.03, 0.4), (0.27, -0.43, 0.09), colour="steel")]
    for x in (-0.3, 0.3):
        parts.append(box((0.04, 0.42, 0.04), (x, -0.2, -0.06), colour="steel_dark"))
    return join(parts, "ac_unit")


@asset
def awning():
    """A striped canvas awning over a ground floor bay, at 2.5 m."""
    parts = []
    n = 8
    for k in range(n):
        x = -1 + (k + 0.5) * W / n
        colour = "signal_red" if k % 2 == 0 else "white"
        parts.append(box((W / n, 1.2, 0.04), (x, -0.55, 2.55), colour=colour, rot=(-0.38, 0, 0), base=False))
        parts.append(box((W / n, 0.03, 0.22), (x, -1.12, 2.22), colour=colour))
    parts.append(box((W, 0.08, 0.08), (0, -0.04, 2.76), colour="steel_dark"))
    return join(parts, "awning")


@asset
def sign_box():
    """A lightbox sign that sticks out from the wall: a made-up shop kind,
    in neon."""
    parts = [box((0.06, 0.5, 0.06), (0, -0.25, 0.32), colour="steel_dark"),
             box((0.12, 0.7, 0.62), (0, -0.62, 0.0), colour="ink", bevel=0.03),
             box((0.14, 0.58, 0.5), (0, -0.62, 0.06), colour="neon_pink", role="Glow"),
             box((0.15, 0.3, 0.06), (0, -0.62, 0.28), colour="white")]
    return join(parts, "sign_box")


@asset
def roof_tank():
    """A rooftop water tank on legs: the classic heaven spot."""
    parts = []
    for x in (-0.9, 0.9):
        for y in (-0.9, 0.9):
            parts.append(box((0.14, 0.14, 2.2), (x, y, 0), colour="steel_dark"))
    parts += [box((2.2, 0.1, 0.1), (0, -0.9, 1.0), colour="steel_dark"),
              box((2.2, 0.1, 0.1), (0, 0.9, 1.0), colour="steel_dark"),
              box((2.4, 2.4, 0.12), (0, 0, 2.2), colour="steel_dark"),
              cyl(1.25, 2.6, (0, 0, 2.32), colour="wood", sides=20),
              cyl(1.3, 0.1, (0, 0, 2.9), colour="ink", sides=20),
              cyl(1.3, 0.1, (0, 0, 4.0), colour="ink", sides=20),
              cyl(1.32, 0.8, (0, 0, 4.92), colour="wood_dark", sides=20, top=0.15)]
    parts.append(tube([(1.25, 0, 0.0), (1.25, 0, 4.9)], 0.03, colour="steel"))
    for k in range(10):
        parts.append(box((0.3, 0.04, 0.03), (1.3, 0, 0.3 + k * 0.45), colour="steel"))
    return join(parts, "roof_tank")


@asset
def roof_hut():
    """The stair hut on a flat roof: a door, a vent and a light."""
    parts = [box((2.4, 2.0, 2.6), colour="concrete_light", bevel=0.03),
             box((2.6, 2.2, 0.15), (0, 0, 2.6), colour="concrete", bevel=0.03),
             box((0.9, 0.06, 2.05), (0.4, -1.0, 0.0), colour="steel"),
             box((0.2, 0.12, 0.12), (0.4, -1.06, 2.15), colour="lamp_white", role="Glow"),
             box((0.6, 0.1, 0.4), (-0.6, -1.02, 1.6), colour="steel_dark")]
    return join(parts, "roof_hut")


@asset
def roof_vent():
    parts = [box((0.7, 0.7, 0.5), colour="steel", bevel=0.03),
             cyl(0.22, 0.6, (0, 0, 0.5), colour="steel", sides=12),
             cyl(0.32, 0.08, (0, 0, 1.1), colour="steel_dark", sides=12),
             cyl(0.2, 0.15, (0, 0, 1.18), colour="steel_dark", sides=12, top=0.02)]
    return join(parts, "roof_vent")
