extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE BUNKER ENTRANCE, ON EVERY MAP.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_bunkers.gd -- <out dir>
#
# Nine sites, nine entrances, three different mountings, and nobody has looked
# at any of them in place. The slice builds the thing at runtime off a marker,
# so the only way to see where it actually lands on each map is to load the
# level and go and look.
#
# SHOT MID-STAND-DOWN, at 45% open. Sealed shows a shut door and tells you
# nothing about the mechanism; fully open is a hole. Half way shows the leaves
# apart, the light from inside, and how the whole thing sits on that map's
# ground — which is the thing being judged.
#
# HEADFUL, because the dummy renderer returns blank textures. It opens a window
# for a minute or so. Each level's own WorldEnvironment and sun are used, so
# these are that map's real light rather than a studio set.
#
# It loads no campaign and writes none.
# ─────────────────────────────────────────────

# THE SITES ARE DERIVED, NOT TYPED (backlog H14). The table that used to be
# here carried both Hillforts, so one of the ten pictures was of the retired
# maps/hillfort_level.tscn — a photograph of a bunker on a map the game does
# not load, filed beside nine real ones with nothing to tell them apart.
const Sites := preload("res://tools/_live_sites.gd")

## Where the camera stands relative to the entrance, and what it looks at.
## The mouth faces +Z — ExitVolume is at z -4, down the tunnel — so the camera
## goes round in front of it and a little to one side.
const EYE := Vector3(7.0, 5.5, 15.0)
const AIM := Vector3(0.0, 2.6, 0.0)

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing. Run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(50, 40))

	for s in Sites.sites():
		if s.node == "":
			print("FAIL  %s carries no slice node, so there is no bunker to photograph" % s.level)
			continue
		await _one(s.label, s.level, s.node)
	print("BUNKER SHOTS DONE")
	quit()


func _one(label: String, level_path: String, node_name: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	# Long enough for FuncGodot to build collision and the slice to seat its
	# cores and raise the entrance.
	for _i in 70:
		await physics_frame

	var slice = level.get_node_or_null(NodePath(node_name))
	if slice == null:
		print("FAIL  %s has no %s" % [label, node_name])
		level.queue_free()
		await process_frame
		return
	var bunker = slice.get_node_or_null(^"SiteBunker")
	if bunker == null:
		print("FAIL  %s built no bunker" % label)
		level.queue_free()
		await process_frame
		return

	# HALF OPEN. Driven through the slice's own door handler, so this is the
	# same path a real stand-down uses rather than a pose set for the camera.
	slice._on_doors(0.45)

	var cam := Camera3D.new()
	level.add_child(cam)
	cam.current = true
	var at: Vector3 = (bunker as Node3D).global_position
	cam.global_position = at + EYE
	cam.look_at(at + AIM)
	for _i in 4:
		await process_frame

	var img := root.get_viewport().get_texture().get_image()
	var path: String = "%s/bunker_%s.png" % [_out, label]
	img.save_png(path)
	print("OK    %-11s at %v -> %s" % [label, at, path])
	level.queue_free()
	await process_frame
