class_name GameConfig
extends RefCounted
## Game-wide constants: identity, setting defaults and the input map.

const GAME_ID := "all-city"
const TITLE := "All City"

## This round's own questions at the end of a play test (LGPlaytest), on top
## of the standard ones, and standard ones that don't fit the game. Change
## them for each round of play testing.
const PLAYTEST := {
	"skip": [],
	"questions": [
		{"id": "town", "text": "How soon did you recognise a place in the town?", "kind": "rating"},
		{"id": "grind", "text": "How good did grinding a real handrail feel?", "kind": "rating"},
	],
}

const SETTING_DEFAULTS := {
	"online": {
		"enabled": true,
		"host": OnlineServer.HOST,
		"port": OnlineServer.PORT,
		"scheme": OnlineServer.SCHEME,
		"server_key": OnlineServer.SERVER_KEY,
	},
	"player": {
		# The writer's name (two to six letters) and look.
		"tag": "",
		"body": 0,
	},
	"camera": {
		# How far round the camera swings behind you, 0 (never) to 1.
		"follow": 0.6,
		"fov": 70.0,
		"invert_y": false,
	},
	"controls": {
		# "skater": left and right turn you, up pushes and down brakes.
		# "camera": the stick points the way you go on screen.
		"steering": "skater",
	},
	"paint": {
		# Holding paint is enough to finish a tag; the stick only speeds it up.
		"assist": true,
	},
	"comfort": {
		# The drone's searchlight and the paint's shine stay steady.
		"reduce_flashing": false,
	},
	"video": {
		# 0 low (handhelds), 1 medium, 2 high.
		"detail": 1,
	},
}

## Every in-game action, with keyboard and controller bindings (see LGInput).
const ACTIONS := {
	"move_forward": ["key:W", "key:Up", "axis:ly-"],
	"move_back": ["key:S", "key:Down", "axis:ly+"],
	"move_left": ["key:A", "key:Left", "axis:lx-"],
	"move_right": ["key:D", "key:Right", "axis:lx+"],
	"look_left": ["axis:rx-"],
	"look_right": ["axis:rx+"],
	"look_up": ["axis:ry-"],
	"look_down": ["axis:ry+"],
	"jump": ["key:Space", "joy:a"],
	"crouch": ["key:Ctrl", "key:C", "joy:b"],
	"grind": ["key:Shift", "mouse:right", "joy:rb"],
	"paint": ["key:E", "mouse:left", "joy:x"],
	"trick": ["key:Q", "joy:y"],
	"look_back": ["key:Tab", "axis:lt+"],
	"boost": ["key:F", "axis:rt+"],
	"map": ["key:M", "joy:back"],
	"pause": ["key:Escape", "key:P", "joy:start"],
}


static func version() -> String:
	return LGVersion.current()
