class_name Towns
extends RefCounted
## The towns this copy can play: the ones that came with the game
## (res://towns/<id>/) and the ones built or downloaded since
## (user://towns/<id>/), each a folder the Cartographer wrote with a
## town.json manifest and its tiles (see docs/tiles.md).

const BUNDLED := "res://towns"
const BUILT := "user://towns"
const PLAY_SCENE := "res://game/play/play.tscn"

## The town being played, as `list()` gives it.
static var current := {}


## Every town found, sorted by name: the manifest's fields plus "path" (the
## folder). A town in user:// replaces a bundled one with the same id.
static func list() -> Array[Dictionary]:
	var found := {}
	for root in [BUNDLED, BUILT]:
		for id in DirAccess.get_directories_at(root):
			var town := read(root.path_join(id))
			if not town.is_empty():
				found[str(town.id)] = town
	var out: Array[Dictionary] = []
	for id in found:
		out.append(found[id])
	out.sort_custom(_by_name)
	return out


## The manifest in `folder`, or {} when there's none or it's for a newer game.
static func read(folder: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(folder.path_join("town.json"))
	if text == "":
		return {}
	var data = JSON.parse_string(text)
	if not data is Dictionary or int(data.get("format", 0)) > TownTiles.FORMAT:
		return {}
	data["path"] = folder
	return data


static func find(id: String) -> Dictionary:
	for town in list():
		if town.id == id:
			return town
	return {}


## Goes into a town (by id): its night starts in the play scene.
static func play(id: String) -> bool:
	var town := find(id)
	if town.is_empty():
		return false
	current = town
	LGScenes.change_scene(PLAY_SCENE)
	return true


static func _by_name(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("name", a.id)) < str(b.get("name", b.id))
