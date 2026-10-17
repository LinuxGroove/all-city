class_name Stairs
extends RefCounted
## Lays the staircase set along a flight of steps: treads stretched to the
## flight's width, a low wall down each side with a coping to grind, and a
## handrail on posts down the middle of wide flights. The treads are only
## looks: the skater rolls on a smooth ramp under them (see `ramp()`).
##
## A flight runs from `bottom` (the middle of the lowest nosing, on the
## ground) up along `up` (level, unit length).

const RISE := 0.17
const GOING := 0.34
## The rail's height above the steps, as building rules ask.
const RAIL_HEIGHT := 0.9
## Flights at least this wide get a handrail down the middle.
const MIDDLE_RAIL := 3.0


## Adds a straight flight to `batch` and returns its grind lines: "rails"
## (handrails, PackedVector3Array each) and "copings" (the side walls' tops),
## plus "top", the middle of the top step. Real flights come with their own
## `rise` and `going` (a step's height and depth); a flight too narrow for
## a middle rail and with no walls gets its rail along one side.
static func lay(batch: Batch, bottom: Vector3, up: Vector3, steps: int, width: float, wall_tint: Color,
		walls := true, rise := RISE, going := GOING) -> Dictionary:
	up = Vector3(up.x, 0, up.z).normalized()
	var side := Vector3.UP.cross(-up).normalized()
	var tread_basis := Basis(side * width, Vector3.UP * (rise / RISE), -up * (going / GOING))
	for i in steps:
		var at := bottom + up * (going * (i + 0.5)) + Vector3.UP * (rise * (i + 1))
		batch.add("stairs/stair_tread", Transform3D(tread_basis, at))
	var run := going * steps
	var climb := rise * steps
	var top := bottom + up * run + Vector3.UP * climb
	var out := {"rails": [], "copings": [], "top": top}
	if walls:
		# Side walls follow the nosing line: a sheared copy of the 1 m wall
		# piece, set one riser lower so no gap shows above a tread.
		var along := up * run + Vector3.UP * climb
		for s in [-1.0, 1.0]:
			var off: Vector3 = side * (s * (width * 0.5 + 0.18))
			var wall_basis := Basis(along, Vector3.UP * 1.18, side * s)
			var start := bottom + off + along * 0.5 - Vector3.UP * (rise * 0.2)
			if s < 0:
				wall_basis = Basis(-along, Vector3.UP * 1.18, side * s)
			batch.add("stairs/stair_wall", Transform3D(wall_basis, start), wall_tint)
			for end in [bottom + off - up * 0.1, top + off + up * 0.1]:
				batch.add("stairs/stair_pier", Transform3D(Basis.IDENTITY, end - Vector3.UP * (rise * 0.2)), wall_tint)
			var coping := PackedVector3Array([bottom + off + Vector3.UP * 1.2, top + off + Vector3.UP * 1.2])
			out.copings.append(coping)
			# A lantern on the inside of each wall, halfway up.
			batch.add("stairs/wall_lantern", Transform3D(Basis(-up * s, Vector3.UP, -side * s),
					bottom + off + along * 0.5 - side * (s * 0.25) + Vector3.UP * 0.75))
	var rail_at := 0.0
	if width < MIDDLE_RAIL:
		if walls or steps < 3:
			return out
		rail_at = width * 0.5 - 0.15
	# The rail runs parallel to the flight, a little past each end.
	var slope := (top - bottom).normalized()
	var lift := Vector3.UP * (RAIL_HEIGHT + rise * 0.5)
	var over := side * rail_at
	var rail := PackedVector3Array([bottom - slope * 0.3 + lift + over, top + slope * 0.3 + lift + over])
	out.rails.append(rail)
	var posts := maxi(2, ceili(run / 2.4) + 1)
	for k in posts:
		var x := run * (0.04 + 0.92 * float(k) / (posts - 1))
		var step := clampi(int(x / going), 0, steps - 1)
		var foot := bottom + up * x + Vector3.UP * (rise * (step + 1)) + over
		var rail_y := bottom.y + climb * (x / run) + lift.y - 0.04
		var post := Basis.IDENTITY.scaled(Vector3(1, (rail_y - foot.y) / 0.95, 1))
		batch.add("stairs/rail_post", Transform3D(post, foot))
	return out


## The collision for a flight: one box tilted along it, its top on the
## nosing line, so wheels roll up and down without catching on steps.
static func ramp(bottom: Vector3, up: Vector3, steps: int, width: float, rise := RISE,
		going := GOING) -> CollisionShape3D:
	var box := ramp_box(bottom, up, steps, width, rise, going)
	var shape := BoxShape3D.new()
	shape.size = box[1]
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = box[0]
	return cs


## The ramp's box as [Transform3D, size], for building it later.
static func ramp_box(bottom: Vector3, up: Vector3, steps: int, width: float, rise := RISE,
		going := GOING) -> Array:
	up = Vector3(up.x, 0, up.z).normalized()
	var along := up * (going * steps) + Vector3.UP * (rise * steps)
	var fwd := along.normalized()
	var side := Vector3.UP.cross(-up).normalized()
	var normal := side.cross(fwd)
	return [Transform3D(Basis(side, normal, -fwd), bottom + along * 0.5 - normal * 0.2),
			Vector3(width, 0.4, along.length())]
