class_name Traffic
extends Node3D
## The town's traffic: a few dozen cars near the player, driving the lanes
## the Cartographer laid (one per direction, on the town's side of the
## road), at each street's speed, turning at random where lanes meet. Cars
## stop for writers in front of them and keep behind the car ahead. They're
## kinematic bodies on the traffic layer, so a skater bumps off them.
##
## Lanes come and go with their tiles (`add_lanes`, `drop_lanes`, by the
## tile's key); everything is in the scene's coordinates and moves with
## the world (`shift`).

const CARS := 22
## Cars live within RADIUS of the player and appear no nearer than SPAWN_MIN.
const RADIUS := 170.0
const SPAWN_MIN := 45.0
const SPEEDS := {"motorway": 22.0, "trunk": 18.0, "primary": 13.0, "secondary": 12.0, "tertiary": 10.0,
	"residential": 8.0, "unclassified": 8.0, "living_street": 4.0}
const ACCEL := 2.5
const BRAKE := 7.0
## How close a lane's start must be to another's end to drive on to it.
const JOIN := 2.5
const CELL := 4.0
const TINTS := ["signal_red", "cobalt", "ochre", "teal", "white", "slate", "mint", "pink", "sand", "civic_blue",
	"white", "concrete_light"]
const SIZE := Vector3(1.8, 1.5, 4.0)

var drive := "right"
## Nodes the cars stop for (writers), and where the player is.
var watch: Array[Node3D] = []
var focus := Vector3.ZERO
var enabled := true

## id -> {"pts", "cum", "kind", "owner"}
var _lanes := {}
var _owned := {}
## Vector2i -> Array of lane ids starting in that cell.
var _starts := {}
var _next := 1
var _cars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Traffic"
	_rng.seed = 1


## Adds a tile's lanes ({"pts", "kind"} in the scene's coordinates).
func add_lanes(owner_key: String, list: Array) -> void:
	drop_lanes(owner_key)
	var ids := []
	for lane in list:
		var pts: PackedVector3Array = lane.pts
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
		if cum[cum.size() - 1] < 3.0:
			continue
		var id := _next
		_next += 1
		_lanes[id] = {"pts": pts, "cum": cum, "kind": str(lane.kind), "owner": owner_key}
		ids.append(id)
		_index(id)
	_owned[owner_key] = ids


func drop_lanes(owner_key: String) -> void:
	if not _owned.has(owner_key):
		return
	for id in _owned[owner_key]:
		_unindex(id)
		_lanes.erase(id)
	_owned.erase(owner_key)
	for car in _cars.duplicate():
		if not _lanes.has(car.lane):
			_remove(car)


func lane_count() -> int:
	return _lanes.size()


func car_count() -> int:
	return _cars.size()


func cars() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for car in _cars:
		out.append(car.node)
	return out


## Moves every lane and car `by` metres (the world re-centring).
func shift(by: Vector3) -> void:
	_starts.clear()
	for id in _lanes:
		var pts: PackedVector3Array = _lanes[id].pts
		for k in pts.size():
			pts[k] += by
		_lanes[id].pts = pts
		_index(id)
	focus += by
	for car in _cars:
		var node: Node3D = car.node
		node.position += by
		node.reset_physics_interpolation()


func clear() -> void:
	for car in _cars:
		(car.node as Node).queue_free()
	_cars.clear()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if not watch.is_empty() and is_instance_valid(watch[0]):
		focus = watch[0].global_position
	for car in _cars.duplicate():
		_drive(car, delta)
	if _cars.size() < CARS and not _lanes.is_empty():
		_spawn()


func _drive(car: Dictionary, delta: float) -> void:
	var lane: Dictionary = _lanes.get(car.lane, {})
	if lane.is_empty():
		_remove(car)
		return
	var node: Node3D = car.node
	if node.position.distance_to(focus) > RADIUS + 40.0:
		_remove(car)
		return
	var target: float = SPEEDS.get(lane.kind, 8.0)
	var fwd := node.global_basis.z
	var gap := _clear_ahead(node.position, fwd, car)
	if gap < 14.0:
		target = minf(target, maxf(0.0, (gap - 5.0) * 0.9))
	var v: float = car.v
	v = move_toward(v, target, (ACCEL if target > v else BRAKE) * delta)
	car.v = v
	car.s += v * delta
	var length: float = lane.cum[lane.cum.size() - 1]
	if car.s >= length:
		var next := _next_lane(car.lane)
		if next < 0:
			_remove(car)
			return
		car.s -= length
		car.lane = next
		lane = _lanes[next]
	_place(car, lane)


## How far ahead the way is clear for a car: writers and other cars in
## front of it, in its lane.
func _clear_ahead(at: Vector3, fwd: Vector3, me: Dictionary) -> float:
	var best := 1e9
	for w in watch:
		if is_instance_valid(w):
			best = minf(best, _ahead(at, fwd, w.global_position, 2.4))
	for other in _cars:
		if other != me:
			var p: Vector3 = (other.node as Node3D).position
			var d := _ahead(at, fwd, p, 1.6)
			if d < best and (other.node as Node3D).global_basis.z.dot(fwd) > 0.3:
				best = d
	return best


static func _ahead(at: Vector3, fwd: Vector3, p: Vector3, half_width: float) -> float:
	var rel := p - at
	var along := rel.dot(fwd)
	if along < 0.0 or along > 30.0 or absf(rel.y) > 3.0:
		return 1e9
	var side := (rel - fwd * along)
	side.y = 0.0
	return along if side.length() < half_width else 1e9


func _place(car: Dictionary, lane: Dictionary) -> void:
	var p := _point(lane, car.s)
	var ahead := _point(lane, car.s + 2.0)
	var dir := ahead - p
	if dir.length() < 0.01:
		return
	var z := dir.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var node: Node3D = car.node
	node.transform = Transform3D(Basis(x, z.cross(x), z), p)


static func _point(lane: Dictionary, s: float) -> Vector3:
	var cum: PackedFloat32Array = lane.cum
	var pts: PackedVector3Array = lane.pts
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var k := cum.bsearch(s)
	k = clampi(k, 1, cum.size() - 1)
	var seg := cum[k] - cum[k - 1]
	var t := (s - cum[k - 1]) / seg if seg > 0.0 else 0.0
	return pts[k - 1].lerp(pts[k], t)


func _next_lane(id: int) -> int:
	var lane: Dictionary = _lanes[id]
	var pts: PackedVector3Array = lane.pts
	var end := pts[pts.size() - 1]
	var dir := (end - pts[pts.size() - 2]).normalized()
	var ahead := []
	var back := []
	var c := _cell(end)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for other in _starts.get(c + Vector2i(di, dj), []):
				if other == id:
					continue
				var o: PackedVector3Array = _lanes[other].pts
				if o[0].distance_to(end) > JOIN:
					continue
				if (o[1] - o[0]).normalized().dot(dir) > -0.3:
					ahead.append(other)
				else:
					back.append(other)
	if not ahead.is_empty():
		return ahead[_rng.randi() % ahead.size()]
	if not back.is_empty():
		return back[_rng.randi() % back.size()]
	return -1


func _spawn() -> void:
	var ids := _lanes.keys()
	for attempt in 12:
		var id: int = ids[_rng.randi() % ids.size()]
		var lane: Dictionary = _lanes[id]
		var s := _rng.randf() * float(lane.cum[lane.cum.size() - 1])
		var p := _point(lane, s)
		var d := p.distance_to(focus)
		if d < SPAWN_MIN or d > RADIUS:
			continue
		var crowded := false
		for other in _cars:
			if (other.node as Node3D).position.distance_to(p) < 9.0:
				crowded = true
				break
		if crowded:
			continue
		var car := {"node": _car_node(), "lane": id, "s": s, "v": float(SPEEDS.get(lane.kind, 8.0)) * 0.8}
		add_child(car.node)
		_place(car, lane)
		(car.node as Node3D).reset_physics_interpolation()
		_cars.append(car)
		return


func _car_node() -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "Car"
	body.collision_layer = Kit.LAYER_TRAFFIC
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, SIZE.y * 0.5 + 0.15, 0)
	body.add_child(cs)
	var tint := Palette.color(TINTS[_rng.randi() % TINTS.size()])
	body.add_child(Kit.instance("vehicles/hatchback", tint))
	return body


func _remove(car: Dictionary) -> void:
	(car.node as Node).queue_free()
	_cars.erase(car)


func _index(id: int) -> void:
	var c := _cell(_lanes[id].pts[0])
	if not _starts.has(c):
		_starts[c] = []
	_starts[c].append(id)


func _unindex(id: int) -> void:
	var c := _cell(_lanes[id].pts[0])
	if _starts.has(c):
		_starts[c].erase(id)


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))
