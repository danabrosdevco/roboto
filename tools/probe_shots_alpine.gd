extends SceneTree

# ─────────────────────────────────────────────
# SHOTS OF THE ALPINE SET — every piece in a line on a flat floor, and a
# stand-in valley with all three scatter layers running, so the set can be
# judged as objects and as a texture.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_alpine.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# The grove shot is hand-placed, not a real TerrainScatter — this tool touches
# no level. It is here to answer "what does a hillside of these look like",
# which a line-up cannot.
# ─────────────────────────────────────────────

const ORDER: Array = [
	"alpine_pine_dead", "alpine_snag_tall", "alpine_snag_leaning",
	"alpine_pine_skeleton", "alpine_snag_broken", "alpine_root_plate",
	"alpine_stump", "alpine_marker_post", "alpine_deadfall",
	"alpine_log_pile", "alpine_erratic", "alpine_scrub",
	"alpine_talus", "alpine_tussock",
]

## The mix a hillside gets: piece, per-hectare weight.
const GROVE: Array = [
	["alpine_tussock", 46], ["alpine_talus", 10], ["alpine_scrub", 14],
	["alpine_snag_tall", 5], ["alpine_pine_dead", 3], ["alpine_snag_broken", 4],
	["alpine_snag_leaning", 3], ["alpine_pine_skeleton", 4], ["alpine_stump", 5],
	["alpine_deadfall", 3], ["alpine_log_pile", 2], ["alpine_erratic", 3],
	["alpine_root_plate", 2], ["alpine_marker_post", 1],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	_ground(world, 260.0)
	_light(world)

	var x := -44.0
	for n: String in ORDER:
		var packed := load("res://maps/blocks/alpine/%s.tscn" % n) as PackedScene
		if packed == null:
			print("   %s will not load" % n)
			continue
		var inst := packed.instantiate() as Node3D
		world.add_child(inst)
		inst.position = Vector3(x, 0.0, 0.0)
		x += 7.0
	# A hillside of the same set, seeded so the picture is the same every run.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for row: Array in GROVE:
		var packed := load("res://maps/blocks/alpine/%s.tscn" % row[0]) as PackedScene
		if packed == null:
			continue
		for _i in int(row[1]):
			var inst := packed.instantiate() as Node3D
			world.add_child(inst)
			inst.position = Vector3(rng.randf_range(-58.0, 58.0), 0.0,
					rng.randf_range(60.0, 172.0))
			inst.rotation.y = rng.randf_range(0.0, TAU)
			var sc := rng.randf_range(0.8, 1.25)
			inst.scale = Vector3(sc, sc, sc)
	for _i in 30:
		await process_frame

	var cam := Camera3D.new()
	cam.far = 900.0
	world.add_child(cam)
	cam.make_current()
	var shots: Array = [
		["01_lineup", Vector3(0.0, 9.0, 62.0), Vector3(0.0, 4.0, 0.0), 58.0],
		["02_lineup_low", Vector3(-30.0, 2.0, 26.0), Vector3(14.0, 4.0, 0.0), 62.0],
		["03_grove", Vector3(0.0, 2.0, 40.0), Vector3(0.0, 6.0, 150.0), 65.0],
		["04_grove_high", Vector3(-40.0, 46.0, 30.0), Vector3(10.0, 0.0, 140.0), 55.0],
	]
	for s: Array in shots:
		cam.fov = float(s[3])
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for pass_i in 2:
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("alpine_%s.png" % s[0]))
		print("   %s" % s[0])
	print("   wrote %d shot(s) to %s" % [shots.size(), out])
	quit()


func _ground(world: Node3D, size: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.39, 0.33)
	mat.roughness = 1.0
	mi.material_override = mat
	world.add_child(mi)
	mi.position = Vector3(0.0, 0.0, size * 0.35)


func _light(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.53, 0.57)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.44, 0.48)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.52, 0.54, 0.56)
	e.fog_density = 0.0016
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 130.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
