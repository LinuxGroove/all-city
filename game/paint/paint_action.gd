class_name PaintAction
extends RefCounted
## A writer painting a wall. Holding paint at a paintable wall face (the
## nearest within REACH that the writer faces, not on the respect list, with
## room at arm's height) starts the paint: the writer is held still through
## `lock`, the guide for the name appears on the wall, and the left stick
## pushes the spray along it. Full tilt goes a little faster than the
## guide's pace; rushing round its corners makes the outline wobble and
## pushing across it makes the line stray; hesitating lets the paint pool
## and run into drips. The result grades Clean, Solid or Drippy (0 to 100)
## and always takes at least the rank's PaintRules.MIN_SECONDS. A wall on
## the respect list only gets a quiet "Not here".
##
## Driven by `step(PaintInput, delta)`, so tests and bots run it headless.
## The writer is any Node3D; its colours come from its `crew_colours` or
## `can_colour` when it has them. With a PaintLayer the paint shows going
## on; with a WallStore the finished paint goes to it (and the server) and
## onto the layer.

## A line for the HUD: "Not here", the grade, why paint didn't stick, or "".
signal line_changed(text: String)
signal started(face: Dictionary, kit: Dictionary)
## {face, rank, kit, grade, label, seconds}: the painting's done.
signal finished(result: Dictionary)
## The finished result with the store's verdict merged in ({ok, reason, wall, ...}).
signal stored(result: Dictionary)
## The writer let go before the end; nothing was painted.
signal stopped

enum State { IDLE, PAINTING, DONE }

## How close to a wall a writer paints from, in metres.
const REACH := 1.5
## The paint's middle above the writer's feet.
const ARM := 1.45
## How far up or down from that the paint can go.
const STRETCH := 0.9
## Room left at a face's ends.
const MARGIN := 0.12
## How far to the writer's right (the spraying hand) the paint's middle is.
const HAND := 0.3
## The smallest a tag gets on a narrow face, in metres high.
const SMALLEST := 0.45
## Seconds each rank takes at the guide's pace.
const TAKES := {"tag": 3.0, "throwup": 20.0, "piece": 150.0, "burner": 300.0}
## Full tilt along the guide, against its pace.
const TOP_SPEED := 1.2
## Slower than this share of the pace, paint pools, and after DRIP_AFTER
## seconds of it, runs.
const POOL := 0.35
const DRIP_AFTER := 0.45
## How fast a drip grows while the spray waits, in quad heights a second.
const DRIP_GROWTH := 0.14
const LONGEST_DRIP := 0.34
## Letting go of paint for this long drops the painting.
const LET_GO := 0.4
## Grades from here up are Clean, then Solid; below, Drippy.
const CLEAN := 75
const SOLID := 45
## What each refusal says.
const REFUSED := {
	"respect": "Not here",
	"rank": "Too fresh to go over",
	"rate": "Ease off for a while",
	"full": "No more room in this quarter",
	"busy": "Didn't stick, try again",
	"too_quick": "Too quick",
}

var walls: Walls
var writer: Node3D
## Called with true when painting starts and false when it ends.
var lock: Callable
## Where the writer looks (a Vector3); the writer's +z when not set, as the
## game's models face +z.
var facing: Callable
var layer: PaintLayer
var store: WallStore
var rank := "tag"
## The writer's name; the player/tag setting when empty.
var writer_name := ""
## The crew's colours; the writer's own when empty.
var colours: Array = []
## Go over better paint with a lower rank anyway.
var cap := false

var state := State.IDLE
var line := ""
var face := {}
var kit := {}
var grade := 100
var seconds := 0.0

var _path := PackedVector2Array()
var _at := PackedFloat32Array()
var _size := Vector2.ONE
var _s := 0.0
var _seg := 0
var _reveal := 0.0
var _pool := 0.0
var _drip := -1
var _drip_cost := 0.0
var _wobble := 0.0
var _let_go := 0.0


func _init(p_walls: Walls, p_writer: Node3D, p_lock := Callable(), p_layer: PaintLayer = null,
		p_store: WallStore = null) -> void:
	walls = p_walls
	writer = p_writer
	lock = p_lock
	layer = p_layer
	store = p_store


func step(input: PaintInput, delta: float) -> void:
	match state:
		State.IDLE:
			_idle(input)
		State.PAINTING:
			_painting(input, delta)
		State.DONE:
			# A new painting needs the button pressed again.
			if not input.paint:
				state = State.IDLE


func is_painting() -> bool:
	return state == State.PAINTING


## The wall the writer would paint now: Walls.nearest's hit, or {}.
func target() -> Dictionary:
	if walls == null or writer == null:
		return {}
	return walls.nearest(writer.global_position, REACH, _facing())


## How far along the guide the spray is, 0 to 1.
func progress() -> float:
	return _s / maxf(_at[-1], 0.001) if not _at.is_empty() else 0.0


## The way the guide goes from the spray now (x right, y down), which is
## the way to push the stick.
func guide_direction() -> Vector2:
	if _path.size() < 2:
		return Vector2.ZERO
	return (_path[_seg + 1] - _path[_seg]).normalized()


## The spray's spot on the paint, in UV.
func nozzle() -> Vector2:
	return _point(_s) / _size


static func label_for(p_grade: int) -> String:
	if p_grade >= CLEAN:
		return "Clean"
	if p_grade >= SOLID:
		return "Solid"
	return "Drippy"


## A node's crew colours: its `crew_colours` (an Array) or `can_colour` (a
## Color) when it has them, else [].
static func colours_of(node: Object) -> Array:
	if node == null:
		return []
	var crew = node.get("crew_colours")
	if crew is Array and not crew.is_empty():
		return crew
	var can = node.get("can_colour")
	if can is Color:
		return [can]
	return []


func _idle(input: PaintInput) -> void:
	if not input.paint:
		_say("")
		return
	var hit := target()
	if hit.is_empty():
		_say("")
		return
	var f: Dictionary = hit.face
	if int(f.paint) == Walls.NEVER:
		_say(REFUSED.respect)
		return
	var name := writer_name if writer_name != "" else str(LGSettings.get_value("player", "tag", ""))
	var cols := colours if not colours.is_empty() else colours_of(writer)
	var k := TagKit.kit_for(name, rank, cols)
	var fit := _fit(hit, float(TagKit.art(k).aspect))
	if fit.is_empty():
		return
	if store and not cap:
		var on := store.wall(int(f.quarter), str(f.id))
		if not PaintRules.can_paint(on, store.me(), rank, false, store.now()).ok:
			_say(REFUSED.rank)
			return
	k.at = [snappedf(fit.u, 0.01), snappedf(fit.v, 0.01)]
	k.h = snappedf(fit.h, 0.01)
	_start(f, k)


## Where the paint goes on the wall hit: {u, v (its middle), h}, or {} with
## the reason said.
func _fit(hit: Dictionary, aspect: float) -> Dictionary:
	var f: Dictionary = hit.face
	var length := Vector2(f.b.x - f.a.x, f.b.z - f.a.z).length()
	var room := Walls.paint_height(f)
	var h := minf(float(TagKit.HEIGHT.get(rank, TagKit.HEIGHT.tag)), minf((length - 2.0 * MARGIN) / aspect, room))
	if h < SMALLEST:
		_say("No room")
		return {}
	var w := h * aspect
	# Facing the wall, a→b runs to the writer's right.
	var u := clampf(float(hit.u) + HAND, w * 0.5 + MARGIN, length - w * 0.5 - MARGIN)
	var arm := writer.global_position.y - float(f.base) + ARM
	var v := clampf(arm, h * 0.5, room - h * 0.5)
	if absf(v - arm) > STRETCH:
		_say("Out of reach")
		return {}
	return {"u": u, "v": v, "h": h}


func _start(f: Dictionary, k: Dictionary) -> void:
	face = f
	kit = k
	var art := TagKit.art(kit)
	_size = Vector2(float(kit.h) * float(art.aspect), float(kit.h))
	_path = PackedVector2Array()
	_at = PackedFloat32Array()
	var run := 0.0
	for p in art.guide:
		var m: Vector2 = p * _size
		if not _path.is_empty():
			run += _path[-1].distance_to(m)
		_path.append(m)
		_at.append(run)
	_s = 0.0
	_seg = 0
	_reveal = 0.0
	_pool = 0.0
	_drip = -1
	_drip_cost = 0.0
	_wobble = 0.0
	_let_go = 0.0
	seconds = 0.0
	grade = 100
	state = State.PAINTING
	if lock.is_valid():
		lock.call(true)
	if layer:
		layer.begin_preview(face, kit)
	_say("")
	started.emit(face, kit)
	_show()


func _painting(input: PaintInput, delta: float) -> void:
	if not input.paint:
		_let_go += delta
		if _let_go >= LET_GO:
			_stop()
		return
	_let_go = 0.0
	seconds += delta
	var total := _at[-1]
	var pace := total / float(TAKES.get(rank, 3.0))
	if _s < total:
		var dir := guide_direction()
		var along := clampf(input.stick.dot(dir), 0.0, 1.0)
		var across := absf(input.stick.dot(Vector2(-dir.y, dir.x)))
		var speed := pace * TOP_SPEED * along if along > 0.2 else 0.0
		_s = minf(_s + speed * delta, total)
		# Rushing round a corner makes the outline wobble.
		while _seg < _path.size() - 2 and _at[_seg + 1] <= _s:
			var turn := absf(dir.angle_to((_path[_seg + 2] - _path[_seg + 1]).normalized()))
			if speed > pace * 0.8:
				_wobble += (speed / pace - 0.8) * turn / PI * 2.0 / maxf(_path.size() - 2, 1)
			_seg += 1
			dir = guide_direction()
		# Pushing across the guide makes the line stray.
		if along > 0.2:
			_wobble += across * across * delta * 0.5
		# Hesitating lets the paint pool, and then run.
		if speed < pace * POOL:
			_pool += delta
			if _pool >= DRIP_AFTER:
				_grow_drip(delta)
		else:
			_pool = 0.0
			_drip = -1
	_reveal = maxf(_reveal, nozzle().x)
	_show()
	if _s >= total and seconds >= float(PaintRules.MIN_SECONDS.get(rank, 2)):
		_finish()


func _grow_drip(delta: float) -> void:
	var drips: Array = kit.drips
	if _drip < 0:
		if drips.size() >= TagKit.MAX_DRIPS:
			return
		var at := nozzle()
		drips.append([snappedf(at.x, 0.001), snappedf(at.y, 0.001), 0.02, 1])
		_drip = drips.size() - 1
		_drip_cost += 10.0
	var d: Array = drips[_drip]
	var grown := minf(float(d[2]) + DRIP_GROWTH * delta, LONGEST_DRIP)
	_drip_cost += (grown - float(d[2])) * 60.0
	d[2] = snappedf(grown, 0.001)


func _finish() -> void:
	state = State.DONE
	_reveal = 1.0
	grade = clampi(roundi(100.0 - _wobble * 60.0 - _drip_cost), 0, 100)
	kit.wobble = snappedf(clampf(_wobble, 0.0, 1.0), 0.01)
	if lock.is_valid():
		lock.call(false)
	var result := {"face": face, "rank": rank, "kit": kit, "grade": grade, "label": label_for(grade),
		"seconds": snappedf(seconds, 0.01)}
	_say(result.label)
	if layer and store == null:
		layer.end_preview()
	finished.emit(result)
	if store:
		_store(result)


## Hands the paint to the store, then shows what stuck.
func _store(result: Dictionary) -> void:
	var res: Dictionary = await store.paint(face, rank, kit, grade, float(result.seconds), cap)
	result.merge(res, true)
	if layer:
		layer.end_preview()
		if res.ok:
			layer.show_paint(str(face.id), res.wall, store.now())
	if not res.ok:
		_say(REFUSED.get(res.reason, REFUSED.busy))
	stored.emit(result)


func _stop() -> void:
	state = State.IDLE
	if lock.is_valid():
		lock.call(false)
	if layer:
		layer.end_preview()
	_say("")
	stopped.emit()


func _show() -> void:
	if layer == null:
		return
	var ahead := PackedVector2Array()
	for i in range(_seg + 1, mini(_seg + 7, _path.size())):
		ahead.append(_path[i] / _size)
	layer.update_preview(_reveal, nozzle(), ahead, kit)


func _point(s: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	var i := _seg
	while i < _path.size() - 2 and _at[i + 1] < s:
		i += 1
	var span := _at[i + 1] - _at[i] if i + 1 < _at.size() else 0.0
	if span <= 0.0:
		return _path[i]
	return _path[i].lerp(_path[i + 1], clampf((s - _at[i]) / span, 0.0, 1.0))


func _facing() -> Vector3:
	if facing.is_valid():
		return facing.call()
	return writer.global_basis.z


func _say(text: String) -> void:
	if text != line:
		line = text
		line_changed.emit(text)
