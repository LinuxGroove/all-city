class_name TownTiles
extends RefCounted
## Reads the Cartographer's tiles: each one a gzipped Godot Variant
## (a Dictionary of packed arrays), so loading is one decompress and one
## `bytes_to_var` with no parsing. docs/tiles.md has the format.

## The newest tile format this game reads (cartographer/__init__.py).
const FORMAT := 1
## A tile's side in metres.
const SIZE := 256.0


## The tile at grid (i, j) of the town in `folder`, or {} when it's missing.
static func load_tile(folder: String, i: int, j: int) -> Dictionary:
	var path := folder.path_join("tiles/%d_%d.tile" % [i, j])
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return {}
	var raw := data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var tile = bytes_to_var(raw)
	return tile if tile is Dictionary else {}
