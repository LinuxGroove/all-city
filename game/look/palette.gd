class_name Palette
extends RefCounted
## The swatches of assets/art/palette.png by name, written by
## tools/blender/palette.py: game code colours things from the same
## palette the models use.

const CELLS := {
	"ink": [0, 0, Color("#14121c")],
	"asphalt": [1, 0, Color("#2b2a33")],
	"asphalt_light": [2, 0, Color("#403e4a")],
	"concrete_dark": [3, 0, Color("#6b6670")],
	"concrete": [4, 0, Color("#8e8a8f")],
	"concrete_light": [5, 0, Color("#b9b3ae")],
	"paving": [6, 0, Color("#a59a90")],
	"stone": [7, 0, Color("#d2c4ae")],
	"cream": [8, 0, Color("#efe2c6")],
	"white": [9, 0, Color("#f4efe6")],
	"kerb": [10, 0, Color("#c9c2b8")],
	"shadow": [11, 0, Color("#221f2b")],
	"brick": [0, 1, Color("#b5452f")],
	"brick_dark": [1, 1, Color("#7e2c22")],
	"ochre": [2, 1, Color("#d89a3c")],
	"terracotta": [3, 1, Color("#c8613d")],
	"teal": [4, 1, Color("#2f7f86")],
	"sea": [5, 1, Color("#2a5d8f")],
	"pink": [6, 1, Color("#e07a8b")],
	"mint": [7, 1, Color("#8fcfb1")],
	"lilac": [8, 1, Color("#8f7ab8")],
	"sand": [9, 1, Color("#e3c48f")],
	"plaster": [10, 1, Color("#e9dccb")],
	"slate": [11, 1, Color("#4a5160")],
	"steel": [0, 2, Color("#5d6878")],
	"steel_dark": [1, 2, Color("#353b47")],
	"iron_green": [2, 2, Color("#2f5a48")],
	"signal_red": [3, 2, Color("#e8463a")],
	"signal_yellow": [4, 2, Color("#f2c641")],
	"hivis": [5, 2, Color("#c6f03c")],
	"civic_blue": [6, 2, Color("#3a6fd8")],
	"chrome": [7, 2, Color("#c3ccd6")],
	"rubber": [8, 2, Color("#1e1d24")],
	"orange": [9, 2, Color("#f08a2c")],
	"purple": [10, 2, Color("#6a3fb5")],
	"cobalt": [11, 2, Color("#2846b8")],
	"sodium": [0, 3, Color("#ffb347")],
	"neon_pink": [1, 3, Color("#ff4fa3")],
	"neon_cyan": [2, 3, Color("#3ff2ff")],
	"window_warm": [3, 3, Color("#ffd28a")],
	"window_cool": [4, 3, Color("#a8d8ff")],
	"lamp_white": [5, 3, Color("#fff4dc")],
	"signal_green": [6, 3, Color("#4dff8a")],
	"signal_amber": [7, 3, Color("#ffbf3f")],
	"grass": [0, 4, Color("#4f8f4a")],
	"leaf": [1, 4, Color("#3c7a3f")],
	"leaf_dark": [2, 4, Color("#285a33")],
	"leaf_light": [3, 4, Color("#6aa84f")],
	"wood": [4, 4, Color("#8a5a3a")],
	"wood_dark": [5, 4, Color("#5c3a26")],
	"bark": [6, 4, Color("#4a3427")],
	"glass": [7, 4, Color("#1f3550")],
}


static func color(name: String) -> Color:
	return CELLS[name][2] if CELLS.has(name) else Color.MAGENTA


## The UV of a swatch's middle, for meshes the game builds itself.
static func uv(name: String) -> Vector2:
	var c: Array = CELLS.get(name, [0, 0])
	return Vector2((c[0] + 0.5) / 16.0, (c[1] + 0.5) / 16.0)
