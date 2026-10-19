extends SceneTree
## Draws an SVG to a PNG with Godot's own SVG renderer, so the icon looks
## as the game shows it:
##
##     godot --headless --path . -s tools/svg_to_png.gd -- icon.svg icon.png 512


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- in.svg out.png [size]")
		quit(1)
		return
	var text := FileAccess.get_file_as_string(args[0])
	var size := int(args[2]) if args.size() > 2 else 512
	var img := Image.new()
	var err := img.load_svg_from_string(text, size / 512.0)
	if err != OK:
		printerr("couldn't read ", args[0])
		quit(1)
		return
	img.save_png(args[1])
	print("wrote ", args[1], " (", img.get_width(), "x", img.get_height(), ")")
	quit()
