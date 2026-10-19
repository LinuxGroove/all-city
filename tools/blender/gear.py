"""The writer's gear: the skateboard and the spray can. Each faces -y on
z = 0 (see ackit.py); run build_art.py to write them to assets/models/gear/.

The board is a real street deck, 0.81 m nose to tail, its nose to -y and
its wheels on z = 0; the game stands the writer on it, kicks it up to hold
while painting and slots it into the backpack to climb. The underside's
graphic is the "Wall" role, so the game paints it each writer's colour.
The can's body is the "Wall" role too, so the game paints it the colour it
sprays.
"""
import math

import bmesh
from mathutils import Vector

import ackit
from ackit import box, cyl, join

ASSETS = {}

# The board's measurements, shared with the game (Skater.DECK_TOP).
DECK_LENGTH = 0.81
DECK_WIDTH = 0.21
# Where the flat middle ends and the kicktails start, and how steep they rise.
KICK_AT = 0.235
KICK = math.radians(19.0)
WHEEL_R = 0.027
WHEEL_W = 0.034
# The trucks' axles, along the board, and the wheels' middles across it.
AXLE_Y = 0.2
WHEEL_X = 0.083
DECK_BOTTOM = 0.094
DECK_CORE = 0.011
GRIP = 0.0025


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


def _kick(y):
    """How far the deck rises at y along it: flat in the middle, then up each tail on a short curve."""
    d = abs(y) - KICK_AT
    if d <= 0:
        return 0.0
    bend = 0.05
    if d < bend:
        return math.tan(KICK) * d * d / (2 * bend)
    return math.tan(KICK) * (d - bend / 2)


def _outline(inset, n_side=26, n_end=10):
    """The deck from above, counter-clockwise: straight sides and round ends, `inset` in from the edge."""
    hw = DECK_WIDTH / 2 - inset
    hl = DECK_LENGTH / 2 - inset
    straight = hl - hw * 0.95
    pts = []
    for i in range(n_side + 1):
        pts.append((hw, -straight + 2 * straight * i / n_side))
    for i in range(1, n_end):
        a = math.pi * i / n_end
        pts.append((hw * math.cos(a), straight + hw * 0.95 * math.sin(a)))
    for i in range(n_side + 1):
        pts.append((-hw, straight - 2 * straight * i / n_side))
    for i in range(1, n_end):
        a = math.pi * i / n_end
        pts.append((-hw * math.cos(a), -straight - hw * 0.95 * math.sin(a)))
    return pts


def _slab(outline, z0, thick, colour, role="Palette", bevel=0.0):
    """A slab over an outline from z0 up, bent up into the kicktails."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0.0)) for x, y in outline]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, thick)), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5,
                        clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    for v in bm.verts:
        v.co.z += z0 + _kick(v.co.y)
    return ackit._new_object("slab", bm, colour, role)


def _truck(y):
    """A truck: the baseplate under the deck, the hanger with its kingpin and bushing, the axle."""
    axle_z = WHEEL_R
    parts = [
        box((0.06, 0.085, 0.012), (0, y, DECK_BOTTOM - 0.012), colour="steel_dark", bevel=0.003),
        cyl(0.012, 0.03, (0, y + 0.012 * (1 if y > 0 else -1), axle_z + 0.03), colour="hivis", sides=10, bevel=0.003),
        cyl(0.004, 0.05, (0, y + 0.012 * (1 if y > 0 else -1), axle_z + 0.03), colour="chrome", sides=6),
        # The hanger: a wide wedge across the board.
        box((0.15, 0.03, 0.026), (0, y, axle_z - 0.009), colour="chrome", bevel=0.007),
        box((0.06, 0.04, 0.03), (0, y, axle_z + 0.012), colour="chrome", bevel=0.008),
        cyl(0.0045, 2 * WHEEL_X + WHEEL_W + 0.012, (-(WHEEL_X + WHEEL_W / 2 + 0.006), y, axle_z), colour="steel",
            sides=6, rot=(0, math.pi / 2, 0)),
    ]
    for s in (-1, 1):
        x0 = s * WHEEL_X - WHEEL_W / 2
        parts += [
            cyl(WHEEL_R, WHEEL_W, (x0, y, WHEEL_R), colour="cream", sides=18, bevel=0.007, segments=2,
                rot=(0, math.pi / 2, 0)),
            cyl(WHEEL_R * 0.48, WHEEL_W + 0.004, (x0 - 0.002, y, WHEEL_R), colour="signal_red", sides=10,
                rot=(0, math.pi / 2, 0)),
        ]
    return parts


@asset
def skateboard():
    """A street deck with kicktails, black grip tape with bolt heads, the graphic underneath, chunky
    chrome trucks and fat cream wheels."""
    parts = [
        _slab(_outline(0.0), DECK_BOTTOM + 0.002, DECK_CORE - 0.002, "wood", bevel=0.003),
        _slab(_outline(0.003), DECK_BOTTOM, 0.0025, "white", role="Wall"),
        _slab(_outline(0.004), DECK_BOTTOM + DECK_CORE, GRIP, "rubber"),
    ]
    # A stripe of the graphic peeking up the tail and nose edges.
    for y in (AXLE_Y, -AXLE_Y):
        parts += _truck(y)
        for dx in (-0.021, 0.021):
            for dy in (-0.019, 0.019):
                parts.append(cyl(0.0045, 0.003, (dx, y + dy, DECK_BOTTOM + DECK_CORE + GRIP - 0.001), colour="chrome",
                                 sides=6))
    return join(parts, "skateboard")


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
