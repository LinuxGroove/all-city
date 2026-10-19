extends Node
## Headless tests: run with
##   godot --headless --path . tests/run_tests.tscn
## Every `tests/*_tests.gd` is a set of tests: each `test_*` method gets the
## runner as `t` and calls `t.check(ok, "what")` (and may await). Add
## `--only=name` to run one set (`skater`) or one of its methods. Exits
## non-zero on failure.

var failures := 0
var checks := 0
var only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGTheme.apply(get_tree().root)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	await get_tree().process_frame
	var files := []
	for f in DirAccess.get_files_at("res://tests"):
		var file := f.trim_suffix(".remap")
		if file.ends_with("_tests.gd"):
			files.append(file)
	files.sort()
	for f in files:
		var set_name := str(f).trim_suffix("_tests.gd")
		var set: Object = load("res://tests/" + f).new()
		var methods := []
		for m in set.get_method_list():
			if str(m.name).begins_with("test_"):
				methods.append(str(m.name))
		for m in methods:
			if only != "" and only != set_name and only != m:
				continue
			printerr("- %s.%s" % [set_name, m])
			await set.call(m, self)
	print("%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAILED: ", what)
