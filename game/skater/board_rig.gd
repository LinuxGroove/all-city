class_name BoardRig
extends SkeletonModifier3D
## Stands a writer on their skateboard: after the clip has posed the body,
## it bends the knees, turns the hips, shoulders and head towards the nose,
## and puts each foot on its spot on the board (or on the ground beside it,
## pushing) with two-bone IK, and can bring the left hand to the board's nose
## to hold it. Universal Animation Library clips have no skate clips, so this
## is what makes a stance of them.
##
## The board is any Node3D whose +z is the nose, +y up from the deck and
## y = 0 the bottom of the wheels (gear/skateboard). Spots are in the board's
## space. A regular stance: the left foot forward, so the writer faces the
## board's right and their left shoulder leads.

const BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"]
## How much of the twist each bone of the back takes, from the hips up.
const TWIST_SHARE := [0.2, 0.12, 0.12, 0.14, 0.18, 0.24]

## The board the feet stand on.
var board: Node3D
## With a `frame` (the person), the feet stand on `stand` in its space
## instead of on the board itself: where the deck would be under them while
## the board flips below.
var frame: Node3D
var stand := Transform3D.IDENTITY
## Each foot on its spot (1) or left to the clip (0).
var front_on := 1.0
var back_on := 1.0
## The ankles' spots, in the board's space, and how far each foot turns
## from straight across the board towards the nose (radians).
var front_spot := Vector3(0.07, Person.DECK_TOP, 0.16)
var back_spot := Vector3(0.07, Person.DECK_TOP, -0.25)
var front_yaw := deg_to_rad(28.0)
var back_yaw := deg_to_rad(-6.0)
## How far the hips sink (metres), and the hips' shift towards the nose.
var crouch := 0.08
var lean := 0.0
## How far the shoulders and head turn towards the nose (radians), all told.
var twist := deg_to_rad(70.0)
## Arms out for balance, 0 to 1.
var arms_out := 0.3
## The left hand to the board's nose (1), holding it.
var hand_on := 0.0
var hand_spot := Vector3(0.0, Person.DECK_TOP, 0.37)
## How far the shoes lift the sole off the bare foot (Person.SOLE, or 0).
var sole := 0.0

var _ids := {}
var _rest := {}
var _ankle_height := 0.0


func _ready() -> void:
	_learn()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_learn()


func _learn() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for b in BONES + ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "upperarm_l", "lowerarm_l",
			"hand_l", "upperarm_r"]:
		_ids[b] = skel.find_bone(b)
		_rest[b] = skel.get_bone_global_rest(_ids[b]) if _ids[b] >= 0 else Transform3D.IDENTITY
	_ankle_height = (_rest.foot_l as Transform3D).origin.y


## The ankle's height above the sole, for spots on the deck or the ground.
func ankle_height() -> float:
	if _rest.is_empty():
		_learn()
	return _ankle_height


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _ids.is_empty() or int(_ids.pelvis) < 0:
		return
	var deck: Transform3D
	if frame and frame.is_inside_tree():
		deck = frame.global_transform * stand
	elif board and board.is_inside_tree():
		deck = board.global_transform
	else:
		return
	var to_skel := skel.global_transform.affine_inverse() * deck
	# The board's way in the skeleton's space when it lies as the stance wants it.
	var stance := Basis(Vector3.UP, PI * 0.5)
	# The hips: down, a little towards the nose, and turned that way.
	var nose := (to_skel.basis.z * Vector3(1, 0, 1)).normalized()
	if nose.length() < 0.5:
		nose = Vector3.RIGHT
	var p := skel.get_bone_global_pose(_ids.pelvis)
	p.origin += Vector3.DOWN * crouch + nose * lean
	skel.set_bone_global_pose(_ids.pelvis, p)
	for i in BONES.size():
		var b: String = BONES[i]
		var t := skel.get_bone_global_pose(_ids[b])
		var up := Vector3.UP
		t.basis = Basis(up, twist * TWIST_SHARE[i]) * t.basis
		skel.set_bone_global_pose(_ids[b], t)
	# Arms a little out from the sides.
	if arms_out > 0.0:
		for side in [["upperarm_l", 1.0], ["upperarm_r", -1.0]]:
			var t := skel.get_bone_global_pose(_ids[side[0]])
			t.basis = Basis(Vector3.BACK, deg_to_rad(38.0) * arms_out * float(side[1])) * t.basis
			skel.set_bone_global_pose(_ids[side[0]], t)
	# The feet: on the left the front, on the right the back (regular).
	var feet := [["l", front_spot, front_yaw, front_on], ["r", back_spot, back_yaw, back_on]]
	for f in feet:
		var w: float = f[3]
		if w <= 0.001:
			continue
		var s: String = f[0]
		var spot: Vector3 = f[1]
		var at := to_skel * (spot + Vector3.UP * (_ankle_height + sole))
		var basis := to_skel.basis * stance.inverse() * Basis(Vector3.UP, f[2]) * (_rest["foot_" + s] as Transform3D).basis
		var now := skel.get_bone_global_pose(_ids["foot_" + s])
		at = now.origin.lerp(at, w)
		basis = now.basis.slerp(basis.orthonormalized(), w)
		# Knees forward, and out over their own end of the board.
		var out := nose * (1.0 if s == "l" else -1.0)
		_two_bone(skel, "thigh_" + s, "calf_" + s, "foot_" + s, at, (Vector3.BACK + out * 0.5).normalized(), Vector3.BACK)
		var foot := skel.get_bone_global_pose(_ids["foot_" + s])
		foot.basis = basis
		skel.set_bone_global_pose(_ids["foot_" + s], foot)
	# The left hand on the board's nose.
	if hand_on > 0.001:
		var hand := skel.get_bone_global_pose(_ids.hand_l)
		var at := hand.origin.lerp(to_skel * hand_spot, hand_on)
		_two_bone(skel, "upperarm_l", "lowerarm_l", "hand_l", at, (Vector3.FORWARD + Vector3.RIGHT * 0.6).normalized(), Vector3.FORWARD)


## Two-bone IK: turns `root` and `mid` so the end bone's origin reaches `at`,
## the joint between them bulging towards `pole` (all in the skeleton's
## space). `bend` is the way the joint bulges in the rest pose.
func _two_bone(skel: Skeleton3D, root: String, mid: String, end: String, at: Vector3, pole: Vector3, bend: Vector3) -> void:
	var a := skel.get_bone_global_pose(_ids[root])
	var b := skel.get_bone_global_pose(_ids[mid])
	var c := skel.get_bone_global_pose(_ids[end])
	var l1: float = (_rest[mid] as Transform3D).origin.distance_to((_rest[root] as Transform3D).origin)
	var l2: float = (_rest[end] as Transform3D).origin.distance_to((_rest[mid] as Transform3D).origin)
	var to := at - a.origin
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u := to.normalized()
	var v := pole - u * pole.dot(u)
	if v.length() < 0.001:
		v = u.cross(Vector3.RIGHT)
	v = v.normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var knee := a.origin + u * along + v * sqrt(maxf(l1 * l1 - along * along, 0.0))
	var bend_a := (_rest[root] as Transform3D).basis.inverse() * bend
	var bend_b := (_rest[mid] as Transform3D).basis.inverse() * bend
	a.basis = (_turn(b.origin - a.origin, a.basis * bend_a, knee - a.origin, v) * a.basis).orthonormalized()
	skel.set_bone_global_pose(_ids[root], a)
	b = skel.get_bone_global_pose(_ids[mid])
	c = skel.get_bone_global_pose(_ids[end])
	b.basis = (_turn(c.origin - b.origin, b.basis * bend_b, a.origin + u * d - knee, v) * b.basis).orthonormalized()
	skel.set_bone_global_pose(_ids[mid], b)


## The turn that takes direction `from` onto `to`, and the side `from_side`
## (square to `from`, or made so) onto `to_side`.
static func _turn(from: Vector3, from_side: Vector3, to: Vector3, to_side: Vector3) -> Basis:
	return _frame(to, to_side) * _frame(from, from_side).inverse()


static func _frame(dir: Vector3, side: Vector3) -> Basis:
	var x := dir.normalized()
	var z := side - x * side.dot(x)
	if z.length() < 0.0001:
		z = x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT)
	z = z.normalized()
	return Basis(x, z.cross(x), z)
