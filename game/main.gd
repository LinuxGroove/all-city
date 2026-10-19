extends Node
## Boots the game: settings, the launch ping, play tests, the input map, the
## theme, comfort and the window, then the title.
##
## Developer shortcuts (after `--`):
##   --town=<id>     straight into a town (an id from Towns.list())
##   --yard          straight to the yard (res://tools/yard.tscn, from source)
##   --title         the title (where the game starts anyway, for now)
##   --playtest      record a play test (see LGPlaytest)
##   --set=section/key=value   any setting, for one run (LGSettings reads it)

const YARD := "res://tools/yard.tscn"


func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGLaunchPing.send(GameConfig.GAME_ID)
	LGPlaytest.setup(GameConfig.GAME_ID, GameConfig.PLAYTEST)
	LGInput.register_actions(GameConfig.ACTIONS, float(LGSettings.get_value("input", "stick_deadzone", 0.25)))
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	CityTheme.apply(get_tree().root, 22)
	CitySettings.apply_comfort()
	get_window().title = GameConfig.TITLE
	var start := plan(OS.get_cmdline_user_args())
	if start.has("town"):
		Towns.play(str(start.town))
	elif start.scene == TitleScreen.SCENE and str(start.get("message", "")) != "":
		LGScenes.change_scene(start.scene, TitleScreen.with_message.bind(str(start.message)))
	else:
		LGScenes.change_scene(start.scene)


## Where the game starts for these arguments: {"town": id} to open a town,
## or {"scene": path} and maybe a "message" for the title, when a shortcut
## can't go where it asked (no such town, or a scene this build hasn't got).
static func plan(args: PackedStringArray) -> Dictionary:
	for a in args:
		if a.begins_with("--town="):
			var id := a.trim_prefix("--town=")
			if Towns.find(id).is_empty():
				return {"scene": TitleScreen.SCENE, "message": "There's no town called \"%s\" here." % id}
			if not ResourceLoader.exists(Towns.PLAY_SCENE):
				return {"scene": TitleScreen.SCENE, "message": "Towns can't open in this build yet."}
			return {"town": id, "scene": Towns.PLAY_SCENE}
		if a == "--yard":
			if ResourceLoader.exists(YARD):
				return {"scene": YARD}
			return {"scene": TitleScreen.SCENE, "message": "The yard isn't in this build."}
	return {"scene": TitleScreen.SCENE}
