class_name Person
extends Node3D
## A person in town: a writer on skates, one of the Buff's crew, a Civic
## officer or a passer-by. A Universal Base Character dressed by
## [code]person.gdshader[/code] and animated with the Universal Animation
## Libraries. Clothes are drawn on the rest pose, so one shader dresses
## everyone.

const MALE := "res://assets/people/Superhero_Male_FullBody.gltf"
const FEMALE := "res://assets/people/Superhero_Female_FullBody.gltf"
const UAL1 := "res://assets/people/UAL1_Standard.glb"
const UAL2 := "res://assets/people/UAL2_Standard.glb"
const HAIR := "res://assets/people/hair/%s.gltf"
const SHADER := preload("res://game/people/person.gdshader")

## What each role wears: the outfit (see the shader) and its colours.
const ROLES := {
	"writer": {"outfit": 0, "main": Color("2846b8"), "accent": Color("ff4fa3"), "legs": Color("403e4a"), "shoe": Color("f4efe6")},
	"buff": {"outfit": 1, "main": Color("c6f03c"), "accent": Color("c6f03c"), "legs": Color("2b2a33"), "shoe": Color("221f2b")},
	"civic": {"outfit": 2, "main": Color("1f2a4a"), "accent": Color("3a6fd8"), "legs": Color("1f2a4a"), "shoe": Color("14121c")},
	"passer": {"outfit": 3, "main": Color("e07a8b"), "accent": Color("e07a8b"), "legs": Color("2a5d8f"), "shoe": Color("f4efe6")},
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
	"Idle_Rail", "Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Walk_Carry"]
## Bones that make up each region, for the shader.
const HEAD_BONES := ["Head", "neck_01"]
const FOOT_BONES := ["foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"]
## How far the skates lift a writer: the boot's sole above the wheels' bottom.
const SKATE_LIFT := 0.09

static var _libs := {}
static var _baked := {}
static var _mats := {}
static var _hair_mats := {}

var role := "writer"
var female := false
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var skates := false
var _current := ""


## A person. `look` can set "skin", "hair" and "style" (indexes) and "main",
## "accent" and "legs" colours; anything missing comes from `seed`. Writers
## wear skates unless `look.skates` is false.
static func make(p_role := "writer", p_female := false, seed := 0, look := {}) -> Person:
	var c := Person.new()
	c.name = "Person"
	c.role = p_role if ROLES.has(p_role) else "passer"
	c.female = p_female
	c._build(seed, look)
	return c


func _build(seed: int, look: Dictionary) -> void:
	var ps: PackedScene = load(FEMALE if female else MALE)
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
		m.material_override = mat
	_add_hair(str(styles[style_i]), HAIR_COLORS[hair_i])
	if not female and r.randf() < 0.3 and role != "civic":
		_add_hair("Hair_Beard", HAIR_COLORS[hair_i])
	if role == "writer" and bool(look.get("skates", true)):
		_add_skates(look.get("wheels", Color("c6f03c")))
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.add_animation_library("ual1", _lib(UAL1))
	anim.add_animation_library("ual2", _lib(UAL2))
	anim.playback_default_blend_time = 0.15


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


## A skate on each foot, placed in the rest pose under the foot and carried
## by the foot bone. The body stands SKATE_LIFT higher on them.
func _add_skates(wheels: Color) -> void:
	skates = true
	for side in ["l", "r"]:
		var bone := skeleton.find_bone("foot_" + side)
		if bone < 0:
			continue
		var rest_foot := skeleton.get_bone_global_rest(bone)
		var at := BoneAttachment3D.new()
		at.bone_name = "foot_" + side
		skeleton.add_child(at)
		var skate := Kit.instance("gear/inline_skate")
		skate.set_instance_shader_parameter("tint", wheels)
		var place := Transform3D(Basis.IDENTITY, Vector3(rest_foot.origin.x, -SKATE_LIFT + 0.005, 0.0))
		skate.transform = rest_foot.affine_inverse() * place
		at.add_child(skate)
	model.position.y = SKATE_LIFT


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
