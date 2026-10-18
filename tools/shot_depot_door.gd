extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE WAY OUT LOOKS LIKE NOW.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_depot_door.gd -- <out dir>
#
# TERRAIN moved the platform door from the far end of the rake onto the
# Operations car, which took the walk out from 65 m to 10 m. The muster and the
# exit both resolve to PlatformDoor_Outside now, which means they are the SAME
# POINT — and whether that reads as a squad waiting on the platform or four
# robots standing in a doorway is not a thing a distance can answer.
#
# Two angles: from where the player wakes, looking at the door, and from
# outside on the platform looking back in.
#
# HEADFUL — the dummy renderer returns blank textures. Loads no campaign.
# ─────────────────────────────────────────────

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(50, 40))

	var level = load("res://maps/railhead_level.tscn").instantiate()
	root.add_child(level)
	for _i in 90:
		await physics_frame

	var cam := Camera3D.new()
	level.add_child(cam)
	cam.current = true

	# From the spawn, at eye height, looking at the door.
	var shots := {
		"depot_door_inside": [Vector3(-2.9, 2.9, -32.0), Vector3(7.25, 1.8, -32.0)],
		"depot_door_outside": [Vector3(16.0, 3.4, -26.0), Vector3(4.5, 1.8, -32.0)],
		"depot_car": [Vector3(-11.0, 4.2, -24.0), Vector3(2.0, 1.6, -32.0)],
	}
	for name in shots:
		cam.global_position = shots[name][0]
		cam.look_at(shots[name][1])
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path: String = "%s/%s.png" % [_out, name]
		img.save_png(path)
		print("OK    %s -> %s" % [name, path])
	print("DEPOT SHOTS DONE")
	quit()
