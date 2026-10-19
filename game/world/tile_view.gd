class_name TileView
extends Node3D
## One tile of a town in the scene, made from its `TilePlan` a piece at a
## time (`step()` within a time budget each frame), so a tile streaming in
## never stalls a frame. Its node sits at the tile's north-west corner,
## less the streamer's origin.

var plan: TilePlan
var key := Vector2i.ZERO
var corner := Vector3.ZERO
var near := false
var detail: Node3D
## The plan's quarter grid, kept when the plan goes.
var quarters := PackedInt32Array()

var _todo: Array[Callable] = []
var _ctx := {}
var _solid: StaticBody3D


static func from_plan(p: TilePlan, ctx: Dictionary) -> TileView:
	var view := TileView.new()
	view.plan = p
	view.key = p.key
	view.corner = p.corner
	view.near = p.near
	view.quarters = p.quarters
	view.name = "Tile_%d_%d" % [p.key.x, p.key.y]
	view._ctx = ctx
	view._todo = [view._make_ground, view._make_water, view._make_shells, view._make_far_trees, view._make_landmarks]
	if p.near:
		view._todo.append(view._make_detail)
		view._todo.append(view._make_land)
		view._todo.append(view._make_solid)
		for k in range(0, p.shapes.size(), 48):
			view._todo.append(view._make_shapes.bind(k, mini(k + 48, p.shapes.size())))
		for block in p.facades:
			view._todo.append(view._make_batch.bind(block, p.facades[block], float(ctx.facade_range)))
		view._todo.append(view._make_batch.bind("Props", p.props, float(ctx.props_range)))
		view._todo.append(view._make_batch.bind("Steps", p.steps, float(ctx.props_range) * 1.5))
		view._todo.append(view._make_batch.bind("Trees", p.trees_near, float(ctx.props_range) * TilePlan.TREE_NEAR))
		view._todo.append(view._make_street)
	return view


## Builds pieces until `budget_usec` has gone; true once the tile is whole.
func step(budget_usec := 4000) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _todo.is_empty():
		var job: Callable = _todo.pop_front()
		job.call()
		if Time.get_ticks_usec() - t0 > budget_usec:
			break
	return _todo.is_empty()


func done() -> bool:
	return _todo.is_empty()


## Drops the near detail (the tile stays as far scenery).
func drop_detail() -> void:
	if detail:
		detail.queue_free()
		detail = null
	_todo = _todo.filter(_is_base)
	near = false
	# The near trees went with the detail: the far ones show all the way in.
	var far_trees := get_node_or_null("FarTrees")
	if far_trees:
		for n in far_trees.get_children():
			(n as GeometryInstance3D).visibility_range_begin = 0.0


func _is_base(job: Callable) -> bool:
	return job.get_method() in [&"_make_ground", &"_make_water", &"_make_shells", &"_make_far_trees", &"_make_landmarks"]


func _mesh_node(node_name: String, arrays: Array, mat: Material, parent: Node3D, shadows := true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _make_ground() -> void:
	var mat: ShaderMaterial = _ctx.mats.ground.duplicate()
	if plan.cover:
		mat.set_shader_parameter("cover", ImageTexture.create_from_image(plan.cover))
	_mesh_node("Ground", plan.ground, mat, self)


func _make_water() -> void:
	if not plan.water.is_empty():
		_mesh_node("Water", plan.water, _ctx.mats.water, self, false)


func _make_shells() -> void:
	if plan.shell_walls.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plan.shell_walls)
	mesh.surface_set_material(0, _ctx.mats.shell)
	if not plan.roofs.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plan.roofs)
		mesh.surface_set_material(1, _ctx.mats.roof)
	var node := MeshInstance3D.new()
	node.name = "Shells"
	node.mesh = mesh
	add_child(node)


func _make_detail() -> void:
	detail = Node3D.new()
	detail.name = "Detail"
	add_child(detail)
	_solid = StaticBody3D.new()
	_solid.name = "Solid"
	_solid.collision_layer = Kit.LAYER_WORLD
	_solid.collision_mask = 0
	detail.add_child(_solid)


func _make_land() -> void:
	# A height map spaces its points a metre apart round its middle, so it's
	# scaled up (uniformly: shapes don't take uneven scales) to the tile.
	var shape := HeightMapShape3D.new()
	shape.map_width = TilePlan.CELLS + 1
	shape.map_depth = TilePlan.CELLS + 1
	var data := plan.heights.duplicate()
	for k in data.size():
		data[k] /= TilePlan.CELL
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.name = "Land"
	cs.shape = shape
	cs.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * TilePlan.CELL),
			Vector3(TilePlan.SIZE * 0.5, 0.0, TilePlan.SIZE * 0.5))
	_solid.add_child(cs)


func _make_solid() -> void:
	if plan.solid_faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(plan.solid_faces)
	var cs := CollisionShape3D.new()
	cs.name = "Built"
	cs.shape = shape
	_solid.add_child(cs)


func _make_shapes(from: int, to: int) -> void:
	for k in range(from, to):
		var s: Array = plan.shapes[k]
		var cs := CollisionShape3D.new()
		if s[0] == "post":
			var cyl := CylinderShape3D.new()
			cyl.radius = s[1].x
			cyl.height = s[1].y
			cs.shape = cyl
		else:
			var box := BoxShape3D.new()
			box.size = s[1]
			cs.shape = box
		cs.transform = s[2]
		_solid.add_child(cs)


## The far trees: simple models without shadows, from where the near ones
## end (on a near tile) or from anywhere (far tiles have no near ones).
func _make_far_trees() -> void:
	if plan.trees_far.is_empty():
		return
	var node := Node3D.new()
	node.name = "FarTrees"
	add_child(node)
	var begin := float(_ctx.props_range) * TilePlan.TREE_NEAR - 8.0 if plan.near else 0.0
	Batch.nodes(plan.trees_far, node, false, 0.0, begin)


## Landmarks stay in sight at any distance, as the shells do.
func _make_landmarks() -> void:
	if plan.landmark_mesh.is_empty() and plan.landmark_models.is_empty():
		return
	var node := Node3D.new()
	node.name = "Landmarks"
	add_child(node)
	if not plan.landmark_mesh.is_empty():
		_mesh_node("Built", plan.landmark_mesh, _ctx.mats.palette, node)
	Batch.nodes(plan.landmark_models, node, true)


func _make_batch(node_name: String, bufs: Dictionary, range_end: float) -> void:
	if bufs.is_empty():
		return
	var node := Node3D.new()
	node.name = node_name
	detail.add_child(node)
	Batch.nodes(bufs, node, true, range_end)


func _make_street() -> void:
	if not plan.street.is_empty():
		_mesh_node("Street", plan.street, _ctx.mats.palette, detail)
	if not plan.tubes.is_empty():
		_mesh_node("Rails", plan.tubes, _ctx.mats.palette, detail)
