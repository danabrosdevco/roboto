extends SceneTree

# ─────────────────────────────────────────────
# SHOTS ASCENT — survey pictures of maps/ascent_level.tscn, for looking at the
# shape of the map rather than for key art. probe_splash.gd is the moody one.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_ascent.gd
#   RENDER_OUT=<dir> ONLY=03 godot --path . --script res://tools/probe_shots_ascent.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# It changes nothing. The level's own environment and sun are what you see.
# ─────────────────────────────────────────────

## name, camera, look at, fov. Every camera's height is a STATION's own height
## plus an eye, or it is well clear of the ground: pick one out of the air on a
## map whose relief is 130 m and the shot comes back from inside a hill.
const SHOTS: Array = [
	["01_from_the_trailhead", Vector3(0.0, 2.6, 442.0), Vector3(20.0, 112.0, -270.0), 55.0],
	["02_the_hills", Vector3(-320.0, 78.0, 292.0), Vector3(110.0, 60.0, -80.0), 52.0],
	["03_the_tor_from_the_east", Vector3(392.0, 196.0, -238.0), Vector3(30.0, 118.0, -278.0), 45.0],
	["04_the_gate", Vector3(-196.0, 64.0, 146.0), Vector3(60.0, 96.0, -80.0), 55.0],
	# Standing on the ramp itself, at the ramp's own height for that point.
	["05_up_the_ramp", Vector3(-44.0, 119.0, -196.0), Vector3(30.0, 134.0, -272.0), 60.0],
	["06_down_from_the_summit", Vector3(30.0, 135.0, -228.0), Vector3(-110.0, 30.0, 220.0), 66.0],
	["07_the_terrace", Vector3(214.0, 88.0, 16.0), Vector3(40.0, 104.0, -160.0), 55.0],
	["08_the_relay", Vector3(-16.0, 136.0, -238.0), Vector3(46.0, 140.0, -292.0), 62.0],
	["08b_the_dish_line", Vector3(56.0, 136.0, -286.0), Vector3(-20.0, 140.0, -300.0), 58.0],
	["09_aerial_whole_map", Vector3(0.0, 780.0, 720.0), Vector3(10.0, 70.0, -120.0), 50.0],
	["10_aerial_the_route", Vector3(-40.0, 520.0, 300.0), Vector3(20.0, 100.0, -200.0), 46.0],
	["11_the_upland", Vector3(236.0, 124.0, 64.0), Vector3(30.0, 128.0, -270.0), 44.0],
	["12_the_tor_ring", Vector3(160.0, 122.0, -336.0), Vector3(30.0, 130.0, -276.0), 50.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("ONLY")
	var packed := load("res://maps/ascent_level.tscn") as PackedScene
	if packed == null:
		print("FAIL  maps/ascent_level.tscn will not load")
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
				root.get_texture().get_image().save_png(out.path_join("ascent_%s.png" % s[0]))
		done += 1
		print("   %s" % s[0])
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()
