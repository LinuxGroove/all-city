class_name Person
extends Node3D
## A person in town: a writer with a skateboard, one of the Buff's crew, a Civic
## officer or a passer-by. A Universal Base Character dressed by
## [code]person.gdshader[/code] and animated with the Universal Animation
## Libraries. Clothes are drawn on the rest pose, so one shader dresses
## everyone.

const MALE := "res://assets/people/Superhero_Male_FullBody.gltf"
const FEMALE := "res://assets/people/Superhero_Female_FullBody.gltf"
const UAL1 := "res://assets/people/UAL1_Standard.glb"
const UAL2 := "res://assets/people/UAL2_Standard.glb"
const HAIR := "res://assets/people/hair/%s.gltf"
const OUTFIT := "res://assets/people/outfits/%s_%s.gltf"
const SHADER := preload("res://game/people/person.gdshader")
const CLOTH := preload("res://game/people/cloth.gdshader")

## What each role wears: the outfit (see the shader) and its colours.
const ROLES := {
	"writer": {"outfit": 0, "main": Color("2846b8"), "accent": Color("ff4fa3"), "legs": Color("403e4a"), "shoe": Color("f4efe6"),
			"wardrobe": "streetwear"},
	"buff": {"outfit": 1, "main": Color("c6f03c"), "accent": Color("c6f03c"), "legs": Color("2b2a33"), "shoe": Color("221f2b")},
	"civic": {"outfit": 2, "main": Color("1f2a4a"), "accent": Color("3a6fd8"), "legs": Color("1f2a4a"), "shoe": Color("14121c")},
	"passer": {"outfit": 3, "main": Color("e07a8b"), "accent": Color("e07a8b"), "legs": Color("2a5d8f"), "shoe": Color("f4efe6")},
}
## Real clothes, piece by piece (the outfit's mesh names): the colour (a key
## of the role's colours, or a colour) and the kind (see cloth.gdshader).
## Any mesh an outfit doesn't list is skin.
const WARDROBE := {
	"streetwear": {
		"Hoodie": ["main", 0], "Hood": ["main", 0], "Rib": ["main", 1], "Strings": ["accent", 2],
		"Trousers": ["legs", 0], "Metal": [Color("a7a9b3"), 2],
		"Shoes": [Color("221f2b"), 0], "Soles": [Color("f4efe6"), 1], "Laces": [Color("f4efe6"), 2],
		"Pack": ["accent", 0], "Straps": [Color("221f2b"), 0], "Loops": [Color("221f2b"), 1],
	},
}
## Hoodie and T-shirt colours writers and passers-by come in.
const TOPS := [Color("2846b8"), Color("e8463a"), Color("f2c641"), Color("2f7f86"), Color("6a3fb5"), Color("f08a2c"),
	Color("14121c"), Color("8fcfb1"), Color("e07a8b"), Color("f4efe6")]
const BOTTOMS := [Color("403e4a"), Color("2b2a33"), Color("5c3a26"), Color("2a5d8f"), Color("6b6670"), Color("2f5a48")]
const SKINS := [Color(0.88, 0.69, 0.56), Color(0.78, 0.56, 0.44), Color(0.6, 0.42, 0.3), Color(0.42, 0.28, 0.2), Color(0.3, 0.2, 0.15)]
const HAIR_COLORS := [Color(0.08, 0.06, 0.05), Color(0.25, 0.15, 0.08), Color(0.5, 0.35, 0.18), Color(0.62, 0.58, 0.52), Color(0.55, 0.22, 0.1), Color(0.75, 0.6, 0.35)]
const HAIR_STYLES := {
	"female": ["Hair_Buns", "Hair_Long", "Hair_BuzzedFemale", "Hair_SimpleParted"],
	"male": ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", "Hair_Buzzed"],
}
## Clips that loop.
const LOOPS := ["Idle", "Jump", "Sprint", "Jog_Fwd", "Walk", "Crouch_Idle", "Crouch_Fwd", "Driving", "Slide",
	"Idle_TalkingPhone", "NinjaJump_Idle", "Sitting_Idle", "Idle_Talking", "Idle_FoldArms", "Push",
	"Idle_Rail", "Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Walk_Carry", "Swim_Fwd"]
## Bones that make up each region, for the shader.
const HEAD_BONES := ["Head", "neck_01"]
const FOOT_BONES := ["foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"]
## How far shoes lift a dressed writer: their soles reach this far under the
## bare foot (tools/blender/wardrobe.py's SOLE).
const SOLE := 0.016
## The skateboard's deck: the top of its grip above the bottom of the wheels
## (tools/blender/gear.py), and where the board lies under a regular stance in
## this person's space: nose to the left (+x), so the left foot leads.
const DECK_TOP := 0.108
const STANCE := Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), Vector3(0.045, 0.0, 0.0))
## Painting, the board stands on its tail at the person's left, held by
## the nose (in the person's space): nose up, the grip towards the leg, leaning
## in to it by 8°.
const HELD := Transform3D(Basis(Vector3(0, 0, -1), Vector3(-0.990268, -0.139173, 0), Vector3(-0.139173, 0.990268, 0)),
		Vector3(0.40, 0.41, 0.06))

static var _libs := {}
static var _baked := {}
static var _mats := {}
static var _cloths := {}
static var _hair_mats := {}

var role := "writer"
var female := false
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
## A writer's skateboard (gear/skateboard, a child of this person unless it's
## on the backpack) and the rig that stands them on it; null for everyone else.
var board: MeshInstance3D
var rig: BoardRig
## The outfit this person wears ("" when the shader paints one on).
var outfit := ""
var _current := ""
var _slot: Node3D


## A person. `look` can set "skin", "hair" and "style" (indexes) and "main",
## "accent" and "legs" colours; anything missing comes from `seed`. Writers
## have a skateboard (its graphic in `look.deck`, or the accent) unless
## `look.board` is false.
static func make(p_role := "writer", p_female := false, seed := 0, look := {}) -> Person:
	var c := Person.new()
	c.name = "Person"
	c.role = p_role if ROLES.has(p_role) else "passer"
	c.female = p_female
	c._build(seed, look)
	return c


func _build(seed: int, look: Dictionary) -> void:
	var wear := str(ROLES[role].get("wardrobe", ""))
	var dressed := OUTFIT % [wear, "female" if female else "male"]
	if wear != "" and ResourceLoader.exists(dressed):
		outfit = wear
	var ps: PackedScene = load(dressed if outfit != "" else (FEMALE if female else MALE))
	model = ps.instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var skin_i := int(look.get("skin", r.randi() % SKINS.size())) % SKINS.size()
	var hair_i := int(look.get("hair", r.randi() % HAIR_COLORS.size())) % HAIR_COLORS.size()
	var styles: Array = HAIR_STYLES["female" if female else "male"]
	var style_i := int(look.get("style", r.randi() % styles.size())) % styles.size()
	var j: Dictionary = ROLES[role].duplicate()
	if role == "writer" or role == "passer":
		j.main = TOPS[r.randi() % TOPS.size()]
		j.legs = BOTTOMS[r.randi() % BOTTOMS.size()]
		j.accent = TOPS[r.randi() % TOPS.size()]
	for k in ["main", "accent", "legs"]:
		if look.has(k):
			j[k] = look[k]
	j["wrist"] = 0.6 if female else 0.66
	var mat := _material(j, skin_i)
	for mi in model.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		meshes.append(m)
		if m.name.begins_with("Eye"):
			m.material_override = Look.flat(Color(0.9, 0.88, 0.85) if m.name == "Eyes" else HAIR_COLORS[hair_i] * 0.7)
			continue
		m.mesh = bake(m.mesh, m.skin, skeleton)
		m.material_override = _piece_material(String(m.name), j, skin_i) if outfit != "" else mat
	_add_hair(str(styles[style_i]), HAIR_COLORS[hair_i])
	if not female and r.randf() < 0.3 and role != "civic":
		_add_hair("Hair_Beard", HAIR_COLORS[hair_i])
	if model.find_child("Shoes", true, false):
		model.position.y = SOLE
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.add_animation_library("ual1", _lib(UAL1))
	anim.add_animation_library("ual2", _lib(UAL2))
	anim.playback_default_blend_time = 0.15
	if role == "writer" and bool(look.get("board", true)):
		_add_board(look.get("deck", j.accent))


## Hair is made in the rest pose's space, so it rides the head bone offset
## by its rest.
func _add_hair(style: String, color: Color) -> void:
	var path := HAIR % style
	if skeleton == null or not ResourceLoader.exists(path):
		return
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = "Head"
	skeleton.add_child(at)
	var hair: Node3D = (load(path) as PackedScene).instantiate()
	hair.transform = skeleton.get_bone_global_rest(head).affine_inverse()
	at.add_child(hair)
	if not _hair_mats.has(color.to_html()):
		_hair_mats[color.to_html()] = Look.flat(color * 1.6)
	for mi in hair.find_children("", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _hair_mats[color.to_html()]


## The skateboard, its graphic in `deck`, standing under the feet in a
## regular stance, with the BoardRig that puts the feet on it, and the slot
## on the backpack that carries it.
func _add_board(deck: Color) -> void:
	board = Kit.instance("gear/skateboard", deck)
	board.name = "Board"
	board.transform = STANCE
	add_child(board)
	rig = BoardRig.new()
	rig.name = "BoardRig"
	rig.board = board
	rig.sole = model.position.y
	rig.frame = self
	rig.stand = STANCE
	skeleton.add_child(rig)
	var spine := skeleton.find_bone("spine_03")
	if spine < 0:
		return
	var at := BoneAttachment3D.new()
	at.name = "PackAt"
	at.bone_name = "spine_03"
	skeleton.add_child(at)
	_slot = Node3D.new()
	_slot.name = "BoardSlot"
	at.add_child(_slot)
	# On the pack's back, behind the loops: nose up, the grip against the
	# pack and the wheels out (in the rest pose, the back is towards -z).
	var loops := model.find_child("Loops", true, false) as MeshInstance3D
	var pack := model.find_child("Pack", true, false) as MeshInstance3D
	var behind := -0.3
	var mid := 1.15
	if loops and pack:
		var box := loops.get_aabb()
		behind = box.position.z
		mid = pack.get_aabb().get_center().y - 0.03
	var on_back := Transform3D(Basis(Vector3.LEFT, Vector3.BACK, Vector3.UP), Vector3(0.0, mid, behind - DECK_TOP))
	_slot.transform = skeleton.get_bone_global_rest(spine).affine_inverse() * on_back


## Where the board is when it's on the backpack, in this person's space (the
## slot rides the spine, so this follows the body's pose).
func pack_place() -> Transform3D:
	if _slot == null or not _slot.is_inside_tree():
		return STANCE
	return global_transform.affine_inverse() * _slot.global_transform


## Hangs the board on the backpack (or takes it back to carry about),
## keeping where it is in the world, for the skater to ease it home.
func carry_on_back(on: bool) -> void:
	if board == null or _slot == null or (board.get_parent() == _slot) == on:
		return
	var inside := board.is_inside_tree()
	var was := board.global_transform if inside else Transform3D.IDENTITY
	board.get_parent().remove_child(board)
	(_slot if on else self as Node).add_child(board)
	if inside and board.is_inside_tree():
		board.global_transform = was
	else:
		board.transform = Transform3D.IDENTITY if on else STANCE
	board.reset_physics_interpolation()


func board_on_back() -> bool:
	return board != null and _slot != null and board.get_parent() == _slot


## Raises the body (standing on the deck, Person.DECK_TOP) over its shoes.
func lift(by: float) -> void:
	model.position.y = (SOLE if rig and rig.sole > 0.0 else 0.0) + by


## For still pictures (the title's backdrop, art previews): a writer on the
## board in a 50-50 down a line going `along`, the board tipped to its slope.
## Stand the person on the line, Skater.GRIND_DROP below it.
func grind_still(along: Vector3) -> void:
	if board == null:
		return
	var flat := Vector3(along.x, 0.0, along.z).normalized()
	rotation.y = atan2(-flat.z, flat.x)
	var slope := asin(clampf(-along.normalized().y, -1.0, 1.0))
	board.transform = STANCE * Transform3D(Basis(Vector3.RIGHT, slope), Vector3.ZERO)
	rig.stand = board.transform
	rig.crouch = 0.04
	rig.arms_out = 0.9
	rig.twist = deg_to_rad(60.0)
	lift(DECK_TOP)


## For still pictures: the board held up by its nose, as when painting.
func hold_board_still() -> void:
	if board == null:
		return
	board.transform = HELD
	rig.front_on = 0.0
	rig.back_on = 0.0
	rig.hand_on = 1.0
	rig.crouch = 0.0
	rig.twist = 0.0
	rig.arms_out = 0.0
	lift(0.0)


## For still pictures: the board on the backpack, standing on the ground.
func board_on_pack_still() -> void:
	if board == null:
		return
	rig.active = false
	carry_on_back(true)
	board.transform = Transform3D.IDENTITY
	lift(0.0)


## A spray can in the right hand, its body the paint's colour.
func hold_can(colour: Color) -> MeshInstance3D:
	var bone := skeleton.find_bone("hand_r")
	if bone < 0:
		return null
	var at := BoneAttachment3D.new()
	at.bone_name = "hand_r"
	skeleton.add_child(at)
	var can := Kit.instance("gear/spray_can", colour)
	var rest_hand := skeleton.get_bone_global_rest(bone)
	# In the rest pose the right arm points along -x; the can sits in the
	# palm, upright with its nozzle forward.
	var place := Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, PI * 0.5),
			rest_hand.origin + Vector3(-0.09, -0.04, 0.03))
	can.transform = rest_hand.affine_inverse() * place
	at.add_child(can)
	return can


static func _material(j: Dictionary, skin_i: int) -> ShaderMaterial:
	var key := "%s/%s/%s/%s/%s/%s/%d" % [j.outfit, j.main.to_html(), j.accent.to_html(), j.legs.to_html(),
			j.shoe.to_html(), j.wrist, skin_i]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("outfit", int(j.outfit))
		m.set_shader_parameter("main_color", j.main)
		m.set_shader_parameter("accent", j.accent)
		m.set_shader_parameter("legs", j.legs)
		m.set_shader_parameter("shoe", j.shoe)
		m.set_shader_parameter("wrist", float(j.wrist))
		m.set_shader_parameter("skin", SKINS[skin_i])
		_mats[key] = m
	return _mats[key]


## A piece of the outfit, or the skin under it (any mesh the outfit doesn't list).
func _piece_material(piece: String, j: Dictionary, skin_i: int) -> ShaderMaterial:
	var look: Array = WARDROBE[outfit].get(piece, [])
	var col: Color = SKINS[skin_i]
	var kind := 2
	if not look.is_empty():
		col = look[0] if look[0] is Color else j[look[0]]
		kind = int(look[1])
	var key := "%s/%s/%d" % [outfit, col.to_html(), kind]
	if not _cloths.has(key):
		var m := ShaderMaterial.new()
		m.shader = CLOTH
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("kind", kind)
		_cloths[key] = m
	return _cloths[key]


static func _lib(path: String) -> AnimationLibrary:
	if not _libs.has(path):
		var lib: AnimationLibrary = load(path)
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if String(n) in LOOPS else Animation.LOOP_NONE
		_libs[path] = lib
	return _libs[path]


## A copy of a skinned body mesh with its rest pose in CUSTOM0 and how much
## of each vertex is head, hand and foot in CUSTOM1 (cached per mesh).
static func bake(mesh: Mesh, skin: Skin, skel: Skeleton3D) -> Mesh:
	if mesh == null or _baked.has(mesh):
		return _baked.get(mesh, mesh)
	var region_of := {}
	if skin:
		for i in skin.get_bind_count():
			var bname := String(skin.get_bind_name(i))
			if bname == "" and skel:
				bname = skel.get_bone_name(skin.get_bind_bone(i))
			var reg := Vector3.ZERO
			if bname in HEAD_BONES:
				reg = Vector3(1, 0, 0)
			elif bname.begins_with("hand_") or bname.begins_with("index_") or bname.begins_with("middle_") \
					or bname.begins_with("ring_") or bname.begins_with("pinky_") or bname.begins_with("thumb_"):
				reg = Vector3(0, 1, 0)
			elif bname in FOOT_BONES:
				reg = Vector3(0, 0, 1)
			region_of[i] = reg
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var fmt: int = (mesh as ArrayMesh).surface_get_format(s) if mesh is ArrayMesh else 0
		var per := 8 if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		c0.resize(verts.size() * 3)
		c1.resize(verts.size() * 4)
		for i in verts.size():
			c0[i * 3] = verts[i].x
			c0[i * 3 + 1] = verts[i].y
			c0[i * 3 + 2] = verts[i].z
			var reg := Vector3.ZERO
			if bones != null and weights != null and bones.size() >= (i + 1) * per:
				for k in per:
					reg += region_of.get(int(bones[i * per + k]), Vector3.ZERO) * float(weights[i * per + k])
			c1[i * 4] = reg.x
			c1[i * 4 + 1] = reg.y
			c1[i * 4 + 2] = reg.z
			c1[i * 4 + 3] = 0.0
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		var flags: int = (fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) \
				| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
	_baked[mesh] = out
	return out


## Plays a clip from either library by name ("Sprint", "Hit_Knockback").
func play(clip: String, blend := -1.0, speed := 1.0, restart := false) -> void:
	var full := clip_path(clip)
	if full == "":
		return
	anim.speed_scale = speed
	if full == _current and not restart and anim.is_playing():
		return
	_current = full
	anim.play(full, blend)
	if restart:
		anim.seek(0.0, true)


## Holds a clip at a moment (0 to 1 of its length).
func pose(clip: String, at := 1.0) -> void:
	var full := clip_path(clip)
	if full == "":
		return
	anim.play(full, 0.0)
	var a := anim.get_animation(full)
	anim.seek(a.length * clampf(at, 0.0, 0.999), true)
	anim.pause()
	_current = full


func current() -> String:
	return _current.get_slice("/", 1)


func clip_path(clip: String) -> String:
	for lib in ["ual1", "ual2"]:
		var p := "%s/%s" % [lib, clip]
		if anim.has_animation(p):
			return p
	push_warning("Person: no clip %s" % clip)
	return ""


func clip_length(clip: String) -> float:
	var p := clip_path(clip)
	return anim.get_animation(p).length if p != "" else 0.0


func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
