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
	for model in items:
		var mesh := Kit.mesh(model)
		if mesh == null:
			continue
		var list: Array = items[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
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
