extends SceneTree

# ─────────────────────────────────────────────
# SHOTS PITTSBURGH — survey pictures of maps/pittsburgh_level.tscn.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_pittsburgh.gd
#   RENDER_OUT=<dir> ONLY=ohio godot --path . --script res://tools/probe_shots_pittsburgh.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# Every camera stands on the collision rather than at a guessed height — this
# map has real relief and a guessed y is either buried or in the air.
# ─────────────────────────────────────────────

const EYE := 1.65

## name, from x/z, look-at x/z, fov
const SHOTS: Array = [
	["01_ohio_works", -300.0, -60.0, -400.0, -170.0, 62.0],
	["02_ohio_works_lane", -352.0, -20.0, -352.0, -200.0, 62.0],
	["03_ohio_from_the_river", -250.0, -40.0, -420.0, -140.0, 58.0],
	["04_the_dam", -230.0, -190.0, -320.0, -165.0, 60.0],
	["05_the_strip", 20.0, -60.0, 220.0, -140.0, 62.0],
	["06_south_bank", 150.0, 150.0, 420.0, 230.0, 60.0],
	["07_the_furnace", 300.0, 250.0, 430.0, 210.0, 60.0],
	["08_the_port", 300.0, -230.0, 420.0, -340.0, 60.0],
	["09_aerial_north", -300.0, 200.0, -340.0, -140.0, 55.0],
	["10_aerial_whole", 0.0, 900.0, 0.0, 0.0, 50.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("ONLY")
	var packed := load("res://maps/pittsburgh_level.tscn") as PackedScene
	if packed == null:
		print("FAIL  maps/pittsburgh_level.tscn will not load")
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for _i in 60:
		await physics_frame
	var space := level.get_world_3d().direct_space_state
	var cam := Camera3D.new()
	cam.far = 4000.0
	level.add_child(cam)
	cam.make_current()
	var done := 0
	for s: Array in SHOTS:
		if only != "" and not (only in str(s[0])):
			continue
		cam.fov = float(s[5])
		# The whole-map shot is the one that wants to be above everything, not
		# standing in it.
		var lift: float = 420.0 if str(s[0]).contains("whole") else EYE
		cam.position = Vector3(s[1], _ground(space, float(s[1]), float(s[2])) + lift, s[2])
		cam.look_at(Vector3(s[3], _ground(space, float(s[3]), float(s[4])) + 4.0, s[4]), Vector3.UP)
		for pass_i in 2:
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("pitt_%s.png" % s[0]))
		done += 1
		print("   %s" % s[0])
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, 300.0, z), Vector3(x, -120.0, z)))
	return float(hit["position"].y) if hit.has("position") else 0.0
