extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE CYBERSPACE WIPE AND THE LAB.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_wipe.gd -- <out dir>
#
# HEADFUL, because this grabs the window's viewport and the headless dummy
# renderer has no image to give. It opens a window for a few seconds.
#
# The wipe is a shader driven by one `progress` uniform, so it can be stopped
# at any point and photographed — which is the only way anyone can look at it
# without playing. Three frames: going under, fully covered (the point the
# screen behind is swapped), and clearing.
#
# It never loads a campaign and never writes one.
# ─────────────────────────────────────────────

const _Wipe := preload("res://Character/hud/cyberspace_wipe.gd")

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing. Run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(60, 40))

	# Something behind it, so the cover actually reads as covering something.
	var behind := ColorRect.new()
	behind.color = Color(0.07, 0.10, 0.09)
	behind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(behind)
	var note := Label.new()
	note.text = "OPERATIONS BOARD"
	note.position = Vector2(60, 60)
	behind.add_child(note)

	var wipe = _Wipe.new()
	root.add_child(wipe)
	for _i in 10:
		await process_frame

	for step in [0.12, 0.42, 0.78]:
		wipe.material.set_shader_parameter("progress", step)
		# Two frames: one to apply the uniform, one to draw with it.
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path: String = "%s/wipe_%03d.png" % [_out, int(step * 100.0)]
		img.save_png(path)
		print("OK    progress %.2f -> %s" % [step, path])

	print("WIPE SHOTS DONE")
	quit()
