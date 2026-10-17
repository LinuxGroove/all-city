"""All City's palette: every model made by the scripts in this folder is
coloured from these swatches, by UV, so the whole town shares one look and
one small texture (assets/art/palette.png). The game's shaders do the rest
(toon bands, rim, ink outlines, night glow).

Rows group the swatches: 0 neutrals, 1 walls (tinted again per building in
the game), 2 metals and signal colours, 3 lights (drawn as glow), 4 greens
and woods. Add a swatch at the end of a row; never move one, since models
point at cells by position.

Run `python3 tools/blender/palette.py` to write palette.png and the game's
copy of the names (game/look/palette.gd).
"""
import os

CELL = 8
GRID = 16

ROWS = [
    # Neutrals: ink, asphalt, concrete, paving, stone, cream, white.
    [("ink", "14121c"), ("asphalt", "2b2a33"), ("asphalt_light", "403e4a"), ("concrete_dark", "6b6670"),
     ("concrete", "8e8a8f"), ("concrete_light", "b9b3ae"), ("paving", "a59a90"), ("stone", "d2c4ae"),
     ("cream", "efe2c6"), ("white", "f4efe6"), ("kerb", "c9c2b8"), ("shadow", "221f2b")],
    # Walls.
    [("brick", "b5452f"), ("brick_dark", "7e2c22"), ("ochre", "d89a3c"), ("terracotta", "c8613d"),
     ("teal", "2f7f86"), ("sea", "2a5d8f"), ("pink", "e07a8b"), ("mint", "8fcfb1"), ("lilac", "8f7ab8"),
     ("sand", "e3c48f"), ("plaster", "e9dccb"), ("slate", "4a5160")],
    # Metals and signal colours.
    [("steel", "5d6878"), ("steel_dark", "353b47"), ("iron_green", "2f5a48"), ("signal_red", "e8463a"),
     ("signal_yellow", "f2c641"), ("hivis", "c6f03c"), ("civic_blue", "3a6fd8"), ("chrome", "c3ccd6"),
     ("rubber", "1e1d24"), ("orange", "f08a2c"), ("purple", "6a3fb5"), ("cobalt", "2846b8")],
    # Lights: lamps, neon and lit windows (the shader makes these glow).
    [("sodium", "ffb347"), ("neon_pink", "ff4fa3"), ("neon_cyan", "3ff2ff"), ("window_warm", "ffd28a"),
     ("window_cool", "a8d8ff"), ("lamp_white", "fff4dc"), ("signal_green", "4dff8a"), ("signal_amber", "ffbf3f")],
    # Greens and woods.
    [("grass", "4f8f4a"), ("leaf", "3c7a3f"), ("leaf_dark", "285a33"), ("leaf_light", "6aa84f"),
     ("wood", "8a5a3a"), ("wood_dark", "5c3a26"), ("bark", "4a3427"), ("glass", "1f3550")],
]

INDEX = {}
for r, row in enumerate(ROWS):
    for c, (name, _hex) in enumerate(row):
        INDEX[name] = (c, r)


def uv(name):
    """The middle of a swatch's cell, in Blender's UV space (v up)."""
    c, r = INDEX[name]
    return ((c + 0.5) / GRID, 1.0 - (r + 0.5) / GRID)


def rgb(name):
    c, r = INDEX[name]
    h = ROWS[r][c][1]
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def write_png(path):
    from PIL import Image
    img = Image.new("RGB", (GRID * CELL, GRID * CELL), (255, 0, 255))
    px = img.load()
    for r, row in enumerate(ROWS):
        for c, (_name, h) in enumerate(row):
            col = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
            for y in range(CELL):
                for x in range(CELL):
                    px[c * CELL + x, r * CELL + y] = col
    img.save(path)


def write_gd(path):
    lines = ["class_name Palette", "extends RefCounted",
             "## The swatches of assets/art/palette.png by name, written by",
             "## tools/blender/palette.py: game code colours things from the same",
             "## palette the models use.", "", "const CELLS := {"]
    for r, row in enumerate(ROWS):
        for c, (name, h) in enumerate(row):
            lines.append('\t"%s": [%d, %d, Color("#%s")],' % (name, c, r, h))
    lines += ["}", "", "", "static func color(name: String) -> Color:",
              "\treturn CELLS[name][2] if CELLS.has(name) else Color.MAGENTA", "", "",
              "## The UV of a swatch's middle, for meshes the game builds itself.",
              "static func uv(name: String) -> Vector2:",
              "\tvar c: Array = CELLS.get(name, [0, 0])",
              "\treturn Vector2((c[0] + 0.5) / %d.0, (c[1] + 0.5) / %d.0)" % (GRID, GRID), ""]
    open(path, "w").write("\n".join(lines))


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    write_png(os.path.join(root, "assets", "art", "palette.png"))
    os.makedirs(os.path.join(root, "game", "look"), exist_ok=True)
    write_gd(os.path.join(root, "game", "look", "palette.gd"))
    print("wrote assets/art/palette.png and game/look/palette.gd")
