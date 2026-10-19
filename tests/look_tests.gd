extends RefCounted
## The look and the kit: every model loads with its roles, and facades and
## stairs lay out as the Cartographer expects.


func test_kit_models(t) -> void:
	for set_name in ["street", "stairs", "facade", "vehicles", "gear", "landmark"]:
		var names := Kit.models(set_name)
		t.check(names.size() > 0, "the %s set has models" % set_name)
		for n in names:
			t.check(Kit.mesh(n) != null, "%s loads" % n)


func test_facade_climbs(t) -> void:
	var batch := Batch.new()
	var rec := Facade.recipe("brick", "shop", 7)
	rec["pipe_at"] = 2
	rec["escape_bay"] = 1
	var out := Facade.lay(batch, Vector3(0, 0, 0), Vector3(10, 0, 0), 4, rec, 7)
	t.check(batch.count() > 20, "a facade lays modules")
	t.check(out.climbs.size() == 2, "a drainpipe and a fire escape to climb")
	t.check(is_equal_approx(out.crest, 4 * Facade.STOREY + 0.6 + 0.95), "the crest is the parapet's top")
	# The outside of a face walking east is south (+z).
	for c in out.climbs:
		t.check(c[0].z > 0.0, "climbs are on the outside of the wall")


func test_stairs_rails(t) -> void:
	var batch := Batch.new()
	var wide := Stairs.lay(batch, Vector3.ZERO, Vector3(0, 0, -1), 12, 4.0, Color.WHITE)
	t.check(wide.rails.size() == 1 and wide.copings.size() == 2, "a wide flight has a middle rail and two copings")
	t.check(is_equal_approx(wide.top.y, 12 * Stairs.RISE), "the top is twelve rises up")
	var narrow := Stairs.lay(batch, Vector3.ZERO, Vector3(1, 0, 0), 10, 2.0, Color.WHITE, false, 0.15, 0.4)
	t.check(narrow.rails.size() == 1, "a narrow flight with no walls gets a side rail")
	t.check(is_equal_approx(narrow.top.x, 4.0) and is_equal_approx(narrow.top.y, 1.5), "real rise and going set the top")
