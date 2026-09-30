extends SceneTree

# ─────────────────────────────────────────────
# SHOTS SALIENT — survey pictures of maps/salient_level.tscn.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_salient.gd
#   RENDER_OUT=<dir> ONLY=03 godot --path . --script res://tools/probe_shots_salient.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# It changes nothing. The level's own environment and sun are what you see.
#
# EVERY CAMERA IS PUT ON THE COLLISION, not at a guessed height. A trench is a
# cut, so its floor is a metre below the ground beside it and a fixed y is
# either buried or floating — which is how the first pass of these came back as
# pictures of the inside of a parapet.
# ─────────────────────────────────────────────

## How far above whatever is underneath the camera stands.
const EYE := 1.65

## name, from x/z, look-at x/z, fov. Heights come off the collision.
const SHOTS: Array = [
	["01_the_jump_off", -186.0, 40.0, 80.0, 20.0, 62.0],
	["02_fire_bay", -175.0, -110.0, -175.0, 110.0, 60.0],
	["03_communication_trench", -390.0, 130.0, -180.0, 130.0, 60.0],
	["04_no_mans_land", -95.0, 105.0, 60.0, 55.0, 64.0],
	["05_the_crater", -60.0, 46.0, 70.0, -10.0, 64.0],
	["06_their_wire", -20.0, -30.0, 120.0, -10.0, 62.0],
	["07_looking_back", 210.0, 60.0, -420.0, 20.0, 60.0],
	["08_the_rear", -410.0, -70.0, -110.0, -10.0, 62.0],
	["09_the_village", 330.0, 95.0, 480.0, 60.0, 62.0],
	["10_railhead", 250.0, -195.0, 480.0, -180.0, 62.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("ONLY")
	var packed := load("res://maps/salient_level.tscn") as PackedScene
	if packed == null:
		print("FAIL  maps/salient_level.tscn will not load")
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for _i in 60:
		await physics_frame
	var space := level.get_world_3d().direct_space_state
	var cam := Camera3D.new()
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()
	var done := 0
	for s: Array in SHOTS:
		if only != "" and not (only in str(s[0])):
			continue
		cam.fov = float(s[5])
		cam.position = Vector3(s[1], _ground(space, float(s[1]), float(s[2])) + EYE, s[2])
		cam.look_at(Vector3(s[3], _ground(space, float(s[3]), float(s[4])) + 2.0, s[4]), Vector3.UP)
		# The first frame of a fresh camera comes back blank while the renderer
		# warms up, so every shot is taken twice and the second one kept.
		for pass_i in 2:
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("salient_%s.png" % s[0]))
		done += 1
		print("   %s" % s[0])
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, 200.0, z), Vector3(x, -80.0, z)))
	return float(hit["position"].y) if hit.has("position") else 0.0
