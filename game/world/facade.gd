class_name Facade
extends RefCounted
## Lays the facade kit along one wall face of a building: a module per bay
## per storey, the cornice and parapet on top, piers on the corners, and the
## ways up (drainpipes, fire escapes). The Cartographer picks each face's
## recipe (style, ground floor, colours); everything here is decided from
## the recipe and the face's seed, so every player's copy is the same.
##
## A face runs from `a` to `b` along the ground at its floor's height, with
## its outside on the right when walking from a to b seen from above (the
## Cartographer orients them so). Modules face +z and stand on y = 0 with
## their wall plane at z = 0 (see tools/blender/facade_kit.py).

const BAY := 2.0
const STOREY := 3.0
## Faces shorter than this get no modules: the building's shell covers them.
const MIN_LENGTH := 1.2

## The styles: which windows go on the upper storeys (with weights), what
## the ground floor of a home looks like, the top, and the colours walls
## come in. Colours are palette swatch names.
const STYLES := {
	"brick": {
		"upper": {"window_sash": 6, "window_twin": 3},
		"balcony_row": 0.25, "home_ground": "window_sash", "top": ["cornice", "parapet"],
		"walls": ["brick", "brick_dark", "terracotta", "brick"], "piers": true, "escapes": true,
	},
	"plaster": {
		"upper": {"window_shutters": 6, "window_sash": 2, "window_twin": 1},
		"balcony_row": 0.55, "home_ground": "window_shutters", "top": ["cornice"],
		"walls": ["ochre", "pink", "sand", "cream", "terracotta", "mint", "plaster", "lilac"], "piers": true,
		"escapes": false,
	},
	"modern": {
		"upper": {"window_modern": 8, "wall_plain": 1},
		"balcony_row": 0.0, "home_ground": "window_modern", "top": ["parapet"],
		"walls": ["concrete_light", "white", "slate", "teal", "plaster", "cobalt"], "piers": false, "escapes": false,
	},
	"works": {
		"upper": {"window_twin": 3, "wall_plain": 2},
		"balcony_row": 0.0, "home_ground": "ground_plain", "top": ["parapet"],
		"walls": ["concrete", "brick_dark", "steel", "concrete_dark"], "piers": false, "escapes": true,
	},
}


## A recipe with every field filled in from the style and the seed: the
## Cartographer's own recipe only needs "style" and "ground".
static func recipe(style: String, ground: String, seed: int) -> Dictionary:
	var s: Dictionary = STYLES.get(style, STYLES.plaster)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var walls: Array = s.walls
	return {
		"style": style,
		"ground": ground,
		"wall": Palette.color(walls[rng.randi() % walls.size()]),
		"pipe": rng.randf() < 0.7,
		"escape": rng.randf() < 0.45,
	}


## Adds one face's modules to `batch`. `storeys` counts the ground floor;
## `ends` says which ends are the building's outer corners (a pier there).
## The recipe's "pipe_at" and "escape_bay" (bay indexes, -1 for none) say
## where the ways up go when the Cartographer chose them. Returns the ways
## up as "climbs" (lines from the ground to the top of the parapet) and that
## height as "crest".
static func lay(batch: Batch, a: Vector3, b: Vector3, storeys: int, rec: Dictionary, seed: int,
		ends := Vector2i(1, 0)) -> Dictionary:
	var climbs: Array[PackedVector3Array] = []
	var along := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := along.length()
	if length < MIN_LENGTH or storeys < 1:
		return {"climbs": climbs, "crest": a.y + storeys * STOREY}
	var d := along / length
	var out := Vector3(-d.z, 0, d.x)
	var basis := Basis(d, Vector3.UP, out)
	var bays := maxi(1, roundi(length / BAY))
	var bw := length / bays
	var sx := bw / BAY
	var style: Dictionary = STYLES.get(str(rec.get("style", "plaster")), STYLES.plaster)
	var wall: Color = rec.get("wall", Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var top_y := a.y + storeys * STOREY
	# Columns share their window, as real facades do; rows share balconies.
	var columns: Array[String] = []
	for i in bays:
		columns.append(_pick(style.upper, rng))
	var balconies: Array[bool] = []
	for s in storeys:
		balconies.append(s > 0 and rng.randf() < float(style.balcony_row))
	var ground := _ground_row(str(rec.get("ground", "home")), bays, style, rng)
	var escape_bay := -1
	if bool(rec.get("escape", false)) and bool(style.escapes) and storeys >= 3 and bays >= 3:
		escape_bay = rng.randi_range(1, bays - 2)
	var pipe_at := -1
	if bool(rec.get("pipe", false)) and bays >= 2:
		pipe_at = rng.randi_range(1, bays - 1)
	if rec.has("escape_bay"):
		escape_bay = int(rec.escape_bay) if int(rec.escape_bay) < bays else -1
	if rec.has("pipe_at"):
		pipe_at = int(rec.pipe_at) if int(rec.pipe_at) < bays else -1
	var crest := top_y
	for piece in style.top:
		crest += 0.6 if piece == "cornice" else 0.95
	for i in bays:
		var mid := a + d * (bw * (i + 0.5))
		for s in storeys:
			var model: String = ground[i] if s == 0 else columns[i]
			if s > 0 and balconies[s] and model != "wall_plain" and model != "window_modern" and i != escape_bay:
				model = "window_balcony"
			var xf := Transform3D(basis.scaled_local(Vector3(sx, 1, 1)), mid + Vector3.UP * (s * STOREY))
			batch.add("facade/" + model, xf, wall)
			if s > 0 and model == "window_sash" and rng.randf() < 0.12:
				var ac := Transform3D(basis, mid + d * 0.45 * sx + Vector3.UP * (s * STOREY + 0.12))
				batch.add("facade/ac_unit", ac)
			if s > 0 and i == escape_bay:
				batch.add("facade/fire_escape", Transform3D(basis, mid + Vector3.UP * (s * STOREY)))
		# Shops get awnings and signs.
		if ground[i] == "shop_front" and rng.randf() < 0.55:
			batch.add("facade/awning", Transform3D(basis.scaled_local(Vector3(sx, 1, 1)), mid))
		elif ground[i] == "shop_front" and rng.randf() < 0.5:
			batch.add("facade/sign_box", Transform3D(basis, mid - d * (bw * 0.5 - 0.15) + Vector3.UP * 3.4))
		# The top.
		var y := top_y
		for piece in style.top:
			batch.add("facade/" + piece, Transform3D(basis.scaled_local(Vector3(sx, 1, 1)), Vector3(mid.x, y, mid.z)),
					wall)
			y += 0.6 if piece == "cornice" else 0.95
	if pipe_at >= 0:
		var at := a + d * (bw * pipe_at)
		batch.add("facade/drain_shoe", Transform3D(basis, at))
		for s in storeys:
			batch.add("facade/drainpipe", Transform3D(basis, at + Vector3.UP * (s * STOREY)))
		batch.add("facade/drain_hopper", Transform3D(basis, at + Vector3.UP * (top_y - a.y - 0.95)))
		var pipe := at + out * 0.14
		climbs.append(PackedVector3Array([pipe, Vector3(pipe.x, crest, pipe.z)]))
	if escape_bay >= 0:
		var foot := a + d * (bw * (escape_bay + 0.5)) + out * 0.55
		climbs.append(PackedVector3Array([foot, Vector3(foot.x, crest, foot.z)]))
	# Corner piers: each face puts one on its own start, so every corner
	# gets one.
	if not bool(style.piers):
		ends = Vector2i.ZERO
	if ends.x:
		for s in storeys:
			batch.add("facade/pier", Transform3D(basis, a + Vector3.UP * (s * STOREY)), wall)
	if ends.y:
		for s in storeys:
			batch.add("facade/pier", Transform3D(basis, b + Vector3.UP * (s * STOREY)), wall)
	return {"climbs": climbs, "crest": crest}


## The ground floor's modules, bay by bay.
static func _ground_row(kind: String, bays: int, style: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var row: Array[String] = []
	var door := rng.randi() % bays
	for i in bays:
		match kind:
			"shop":
				if i == door and bays > 2:
					row.append("door")
				else:
					row.append("shop_front" if rng.randf() < 0.62 else "shop_shutter")
			"blank":
				row.append("door" if i == door else "ground_plain")
			_:
				row.append("door" if i == door else str(style.home_ground))
	return row


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]
