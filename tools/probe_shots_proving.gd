extends SceneTree

# ─────────────────────────────────────────────
# SHOTS PROVING — survey pictures of maps/proving_level.tscn.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_proving.gd
#   RENDER_OUT=<dir> ONLY=03 godot --path . --script res://tools/probe_shots_proving.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# It changes nothing. The level's own environment and sun are what you see.
#
# The arena is flat, so unlike the hillfort shots these heights are just the
# height above a floor at y = 0 — no ray needed to find the ground.
# ─────────────────────────────────────────────

## name, camera, look at, fov.
##
## MIND THE AXES. FuncGodot turns Quake (x, y, z) into Godot (y, z, x), so the
## map's 88 m LENGTH — the base-to-base axis, x in block_arena.gd — is Godot's
## Z, and its 54 m width is Godot's X. Written the other way round these
## cameras all stood outside the wall, and the first run came back as ten
## pictures of the inside of a rampart.
const SHOTS: Array = [
	["01_from_the_east_base", Vector3(0.0, 5.6, 38.0), Vector3(0.0, 4.0, -20.0), 62.0],
	["02_eye_level_middle_lane", Vector3(0.0, 1.7, 30.0), Vector3(0.0, 3.0, -10.0), 65.0],
	["03_the_tower", Vector3(-1.0, 2.0, 22.0), Vector3(0.0, 9.0, 0.0), 62.0],
	["04_the_derrick", Vector3(2.0, 7.0, 14.0), Vector3(0.0, 13.0, 0.0), 55.0],
	["05_the_lanes_from_above", Vector3(0.0, 62.0, 30.0), Vector3(0.0, 0.0, 0.0), 58.0],
	["06_the_wall_and_piers", Vector3(18.0, 2.0, -30.0), Vector3(24.0, 3.0, 26.0), 62.0],
	["07_the_west_base", Vector3(0.0, 1.7, -20.0), Vector3(0.0, 3.5, -40.0), 62.0],
	["08_cover_across_the_north", Vector3(17.0, 1.7, 34.0), Vector3(17.0, 2.0, -20.0), 65.0],
	["09_aerial", Vector3(0.0, 96.0, 74.0), Vector3(0.0, 0.0, 0.0), 52.0],
	["10_the_skyline", Vector3(0.0, 8.0, 0.0), Vector3(20.0, 8.0, 66.0), 60.0],
	["11_the_tower_ramp", Vector3(16.0, 1.7, 0.0), Vector3(0.0, 5.0, 0.0), 62.0],
	["12_a_base_ramp", Vector3(14.0, 1.7, 34.0), Vector3(2.0, 3.6, 40.0), 62.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("ONLY")
	var packed := load("res://maps/proving_level.tscn") as PackedScene
	if packed == null:
		print("FAIL  maps/proving_level.tscn will not load")
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var cam := Camera3D.new()
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()
	var done := 0
	for s: Array in SHOTS:
		if only != "" and not (only in str(s[0])):
			continue
		cam.fov = float(s[3])
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		# The first frame of a fresh run comes back blank while the renderer
		# warms up, so every shot is taken twice and the second one kept.
		for pass_i in 2:
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(out.path_join("proving_%s.png" % s[0]))
		done += 1
		print("   %s" % s[0])
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()
