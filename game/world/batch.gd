class_name Batch
extends RefCounted
## Many copies of the kit's models, collected and then drawn as one
## MultiMesh per model, each copy with its own colour (the Wall role's tint).

## model -> Array of [Transform3D, Color]
var items := {}


func add(model: String, xf: Transform3D, colour := Color.WHITE) -> void:
	if not items.has(model):
		items[model] = []
	items[model].append([xf, colour])


func count() -> int:
	var n := 0
	for m in items:
		n += items[m].size()
	return n


## Adds one MultiMeshInstance3D per model under `parent`. `range_end` hides
## them past that distance (0 shows them at any distance).
func build(parent: Node3D, shadows := true, range_end := 0.0) -> void:
	nodes(buffers(), parent, shadows, range_end)


## Every model's instances as a MultiMesh buffer: {model: [buffer, count]}.
## Only arithmetic, so it runs on a worker thread.
func buffers() -> Dictionary:
	var out := {}
	for model in items:
		var list: Array = items[model]
		# One buffer write: a town tile lays tens of thousands of modules.
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var k := 0
		for item in list:
			var xf: Transform3D = item[0]
			var c: Color = item[1]
			buf[k] = xf.basis.x.x
			buf[k + 1] = xf.basis.y.x
			buf[k + 2] = xf.basis.z.x
			buf[k + 3] = xf.origin.x
			buf[k + 4] = xf.basis.x.y
			buf[k + 5] = xf.basis.y.y
			buf[k + 6] = xf.basis.z.y
			buf[k + 7] = xf.origin.y
			buf[k + 8] = xf.basis.x.z
			buf[k + 9] = xf.basis.y.z
			buf[k + 10] = xf.basis.z.z
			buf[k + 11] = xf.origin.z
			buf[k + 12] = c.r
			buf[k + 13] = c.g
			buf[k + 14] = c.b
			buf[k + 15] = c.a
			k += 16
		out[model] = [buf, list.size()]
	return out


## The MultiMeshInstance3Ds for `buffers()`, under `parent`.
static func nodes(bufs: Dictionary, parent: Node3D, shadows := true, range_end := 0.0) -> void:
	for model in bufs:
		var mesh := Kit.mesh(model)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = bufs[model][1]
		mm.buffer = bufs[model][0]
		var node := MultiMeshInstance3D.new()
		node.name = model.replace("/", "_")
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			node.visibility_range_end = range_end
			node.visibility_range_end_margin = 8.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if model.begins_with("facade/window") or model.begins_with("facade/shop"):
			node.set_instance_shader_parameter("lit_share", 0.38)
		parent.add_child(node)
