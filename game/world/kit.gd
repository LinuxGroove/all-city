class_name Kit
extends RefCounted
## The game's models by name ("street/bench", "facade/window_sash"), as
## meshes with the game's materials in place of the ones Blender wrote.
## Every model is made by tools/blender/build_art.py; see ackit.py for how
## they face and stand.

const ROOT := "res://assets/models/"

## Physics layers.
const LAYER_WORLD := 1
const LAYER_SKATER := 2
const LAYER_GRIND := 4
const LAYER_PAINT := 8
const LAYER_TRAFFIC := 16

static var _meshes := {}


## The mesh of a model, shared. Its surfaces carry the game's role
## materials, so a Wall surface takes a MultiMesh's instance colour or a
## node's `tint`.
static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var path := ROOT + model + ".glb"
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Kit: no model %s" % model)
		_meshes[model] = null
		return null
	var root := scene.instantiate()
	var found := _first_mesh(root)
	var out: Mesh = null
	if found:
		out = found.mesh.duplicate() as Mesh
		for i in out.get_surface_count():
			var m := out.surface_get_material(i)
			var role := m.resource_name if m else "Palette"
			out.surface_set_material(i, Look.material(role))
	root.free()
	_meshes[model] = out
	return out


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m:
			return m
	return null


## A node showing a model, tinted (the Wall role) when `tint` isn't white.
static func instance(model: String, tint := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = model.get_file()
	mi.mesh = mesh(model)
	if tint != Color.WHITE:
		mi.set_instance_shader_parameter("tint", tint)
	return mi


## Every model in a set, by name.
static func models(set_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ROOT + set_name)
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported games list the imported copies.
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if f.ends_with(".glb") and not out.has(set_name + "/" + f.get_basename()):
			out.append(set_name + "/" + f.get_basename())
	out.sort()
	return out
