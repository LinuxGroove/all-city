class_name TownMapData
extends RefCounted
## What the town map draws, read from a town's tiles (docs/tiles.md): each
## tile's ground cover picture shrunk to a few pixels a metre, every
## building's roof as triangles with a shade by storeys, the water, one
## colour per quarter cell, and where every wall is (so paint can be put on
## the map). Pure CPU work with no scene or rendering calls, so it runs on a
## worker thread; TownMap makes the nodes from it.

## Ground cover pixels a tile gets: 1 m a pixel for a small town, less for a big one.
const PIXELS_SMALL := 256
const PIXELS_MID := 128
const PIXELS_BIG := 64
## Tiles up to which the sizes above apply.
const SMALL_TOWN := 100
const MID_TOWN := 400
## The shades a building goes through by storeys (low to high).
const LOW := Color("3b3652")
const HIGH := Color("7c74a8")
const TALL := 12.0
## Quarter cells in a tile's side, and their size in metres.
const CELLS := 8


## Reads the town in `town` (its manifest, with "path"). Returns {} when it
## has no tiles, else:
## box: Rect2 of the town in metres (x, z);
## ground: Array of {key: Vector2i, image: Image}, `pixels` a side;
## roofs: {verts, colors, indices} (Vector2 in metres);
## water: {verts, indices};
## faces: {wall id: Vector2, its middle in metres};
## cells: {origin: Vector2i (first tile), cols, rows, ids: PackedInt32Array (-1 for none)}.
## `cancel` is polled between tiles: set it to stop early (returns {}).
static func read(town: Dictionary, cancel := {}) -> Dictionary:
	var folder := str(town.get("path", ""))
	var keys: Array = town.get("tiles", [])
	if folder == "" or keys.is_empty():
		return {}
	var count := keys.size()
	var pixels := PIXELS_SMALL if count <= SMALL_TOWN else (PIXELS_MID if count <= MID_TOWN else PIXELS_BIG)
	var i0 := 1 << 30
	var j0 := 1 << 30
	var i1 := -(1 << 30)
	var j1 := -(1 << 30)
	for k in keys:
		i0 = mini(i0, int(k[0]))
		j0 = mini(j0, int(k[1]))
		i1 = maxi(i1, int(k[0]))
		j1 = maxi(j1, int(k[1]))
	var cols := (i1 - i0 + 1) * CELLS
	var rows := (j1 - j0 + 1) * CELLS
	var ids := PackedInt32Array()
	ids.resize(cols * rows)
	ids.fill(-1)
	var ground := []
	var roofs := {"verts": PackedVector2Array(), "colors": PackedColorArray(), "indices": PackedInt32Array()}
	var water := {"verts": PackedVector2Array(), "indices": PackedInt32Array()}
	var faces := {}
	for k in keys:
		if cancel.get("stop", false):
			return {}
		var i := int(k[0])
		var j := int(k[1])
		var tile := TownTiles.load_tile(folder, i, j)
		if tile.is_empty():
			continue
		var img := _ground(tile, pixels)
		if img != null:
			ground.append({"key": Vector2i(i, j), "image": img})
		_buildings(tile, roofs, faces)
		_water(tile, water)
		var q: PackedInt32Array = tile.get("quarters", PackedInt32Array())
		if q.size() == CELLS * CELLS:
			for r in CELLS:
				for c in CELLS:
					ids[((j - j0) * CELLS + r) * cols + (i - i0) * CELLS + c] = q[r * CELLS + c]
	var size := TownTiles.SIZE
	return {
		"box": Rect2(i0 * size, j0 * size, (i1 - i0 + 1) * size, (j1 - j0 + 1) * size),
		"pixels": pixels,
		"ground": ground,
		"roofs": roofs,
		"water": water,
		"faces": faces,
		"cells": {"origin": Vector2i(i0, j0), "cols": cols, "rows": rows, "ids": ids},
	}


## A tile's ground cover picture at `pixels` a side, or null.
static func _ground(tile: Dictionary, pixels: int) -> Image:
	var png: PackedByteArray = tile.get("ground", PackedByteArray())
	if png.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != pixels:
		img.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
	return img


## Adds a tile's roofs to `roofs`, and each wall's middle to `faces`.
static func _buildings(tile: Dictionary, roofs: Dictionary, faces: Dictionary) -> void:
	var verts: PackedVector2Array = roofs.verts
	var colors: PackedColorArray = roofs.colors
	var indices: PackedInt32Array = roofs.indices
	for b in tile.get("buildings", []):
		var base := verts.size()
		var colour := LOW.lerp(HIGH, clampf(float(b.get("storeys", 3)) / TALL, 0.0, 1.0))
		for ring in b.rings:
			for p in ring:
				verts.append(p)
				colors.append(colour)
		var tris: PackedInt32Array = b.get("tris", PackedInt32Array())
		for t in tris:
			indices.append(base + t)
		for f in b.get("faces", []):
			var a: Vector3 = f.p0
			var c: Vector3 = f.p1
			faces[str(f.id)] = Vector2((a.x + c.x) * 0.5, (a.z + c.z) * 0.5)
	roofs.verts = verts
	roofs.colors = colors
	roofs.indices = indices


## Adds a tile's water to `water`.
static func _water(tile: Dictionary, water: Dictionary) -> void:
	var w = tile.get("water")
	if not w is Dictionary:
		return
	var src: PackedVector3Array = w.get("verts", PackedVector3Array())
	var tris: PackedInt32Array = w.get("tris", PackedInt32Array())
	if tris.is_empty():
		return
	var verts: PackedVector2Array = water.verts
	var indices: PackedInt32Array = water.indices
	var base := verts.size()
	for v in src:
		verts.append(Vector2(v.x, v.z))
	for t in tris:
		indices.append(base + t)
	water.verts = verts
	water.indices = indices


## One colour for each quarter id: stable, and far apart for neighbours.
static func quarter_colour(id: int) -> Color:
	return Color.from_hsv(fmod(float(id) * 0.381966, 1.0), 0.55, 0.95)
