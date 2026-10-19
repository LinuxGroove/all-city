extends RefCounted
## People: writers wear fitted clothes over their skin, everyone else is
## painted by the shader, and all of them stand and move on the same skeleton.

const CLOTHES := ["Hoodie", "Hood", "Rib", "Strings", "Metal", "Trousers", "Shoes", "Soles", "Laces", "Pack", "Straps", "Loops"]


func test_writer_clothes(t) -> void:
	for female in [false, true]:
		var who := "the %s writer" % ("woman" if female else "man")
		var w := Person.make("writer", female, 3)
		t.check(w.outfit == "streetwear", "%s wears the streetwear" % who)
		var pieces := []
		var cloth := 0
		var skin := 0
		for m in w.meshes:
			pieces.append(String(m.name))
			if String(m.name).begins_with("Eye"):
				continue
			var mat := m.material_override as ShaderMaterial
			t.check(mat != null and mat.shader == Person.CLOTH, "%s's %s is drawn by the cloth shader" % [who, m.name])
			if mat != null and int(mat.get_shader_parameter("kind")) == 2 and Person.SKINS.has(mat.get_shader_parameter("color")):
				skin += 1
			elif not CLOTHES.has(String(m.name)):
				t.check(false, "%s has a piece nobody named: %s" % [who, m.name])
			else:
				cloth += 1
		for piece in CLOTHES:
			t.check(pieces.has(piece), "%s has a %s" % [who, piece])
		t.check(skin >= 1, "%s's body under the clothes is in a skin colour" % who)
		t.check(cloth >= CLOTHES.size() - 2, "%s's clothes are coloured" % who)
		t.check(w.board != null and w.rig != null and w.skeleton != null, "%s still has a skateboard and a skeleton" % who)
		t.check(w.skeleton.find_bone("Head") >= 0 and w.skeleton.find_bone("foot_l") >= 0, "%s keeps the base skeleton" % who)
		w.free()


func test_others_are_painted(t) -> void:
	for role in ["buff", "civic", "passer"]:
		var p := Person.make(role, false, 5)
		t.check(p.outfit == "", "a %s is dressed by the shader" % role)
		for m in p.meshes:
			if String(m.name).begins_with("Eye"):
				continue
			var mat := m.material_override as ShaderMaterial
			t.check(mat != null and mat.shader == Person.SHADER, "a %s's %s uses the painted shader" % [role, m.name])
		p.free()


func test_clothes_in_motion(t) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for female in [false, true]:
		var who := "the %s" % ("woman" if female else "man")
		var w := Person.make("writer", female, 2)
		tree.root.add_child(w)
		for clip in ["Idle", "Sprint", "Crouch_Idle", "NinjaJump_Idle"]:
			w.pose(clip, 0.5)
			w.skeleton.force_update_all_bone_transforms()
			t.check(w.bone_position("Head").y > w.bone_position("foot_l").y + 0.5,
					"%s's head is above the foot in %s" % [who, clip])
		w.queue_free()
