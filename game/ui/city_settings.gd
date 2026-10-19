class_name CitySettings
extends VBoxContainer
## All City's own settings rows (the controls, camera, comfort and detail) above the
## shared screen, sound, online and play test rows. Used by the title's
## Settings and the pause menu.

const FOLLOW := [[0.0, "Never"], [0.3, "A little"], [0.6, "Some"], [1.0, "All the way"]]
const FOV := [[60.0, "60°"], [70.0, "70°"], [80.0, "80°"], [90.0, "90°"]]
const STEERING := [["skater", "Turns you"], ["camera", "Points the way"]]
const DETAIL := [[0, "Low (handhelds)"], [1, "Medium"], [2, "High"]]
const WIDTH := 560

## Whether to include the shared rows (screen, sound, online, play tests).
var shared := true


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_head("Controls")
	_row("Left and right", STEERING, "controls", "steering")
	_row("Paint by holding", SettingsPanel.ON_OFF, "paint", "assist")
	_head("Camera")
	_row("Swings behind you", FOLLOW, "camera", "follow")
	_row("Field of view", FOV, "camera", "fov")
	_row("Invert up and down", SettingsPanel.ON_OFF, "camera", "invert_y")
	_head("Comfort")
	_row("Reduce flashing", SettingsPanel.ON_OFF, "comfort", "reduce_flashing")
	_row("Detail", DETAIL, "video", "detail")
	if shared:
		_head("Screen and sound")
		add_child(SettingsPanel.new())


func _head(text: String) -> void:
	add_child(LGUi.label(text.to_upper(), "CapsLabel"))


func _row(label: String, options: Array, section: String, key: String) -> void:
	add_child(LGCycler.make(label, options, LGSettings.get_value(section, key), _store.bind(section, key), WIDTH))


static func _store(value: Variant, section: String, key: String) -> void:
	LGSettings.set_value(section, key, value)
	if section == "comfort" and key == "reduce_flashing":
		apply_comfort()


## Sets the global shader uniform the drone's searchlight and the paint's
## shine read (1 = steady).
static func apply_comfort() -> void:
	var steady := bool(LGSettings.get_value("comfort", "reduce_flashing", false))
	RenderingServer.global_shader_parameter_set("steady", 1.0 if steady else 0.0)
