extends SceneTree

# ─────────────────────────────────────────────
# SHOTS BLOCK — one piece out of maps/blocks, photographed from all four sides
# and from above, on a flat floor with a 1.5 m figure beside it for scale.
#
#   PIECE=industrial/industrial_lock_dam RENDER_OUT=<dir> \
#       godot --path . --script res://tools/probe_shots_block.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# For looking at a piece on its own when something about it is wrong. Judging
# a block from inside a 1 km level means the thing you are looking for is
# forty pixels across and half behind a hill.
# ─────────────────────────────────────────────

## A stand-in for a player, so "is that wall chest high or head high" has an
## answer in the picture rather than in the source.
const FIGURE := 1.5


func _initialize() -> void:
	await process_frame
	var piece := OS.get_environment("PIECE")
	var out := OS.get_environment("RENDER_OUT")
	if piece == "" or out == "":
		print("usage: PIECE=family/piece RENDER_OUT=<dir>")
		quit(2)
		return
	var packed := load("res://maps/blocks/%s.tscn" % piece) as PackedScene
	if packed == null:
		print("FAIL  no piece at maps/blocks/%s.tscn" % piece)
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	_light(world)
	var inst := packed.instantiate() as Node3D
	world.add_child(inst)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("   %s" % piece)
	print("   %.2f x %.2f x %.2f m, y %.2f .. %.2f" % [box.size.x, box.size.z, box.size.y,
			box.position.y, box.end.y])
	_floor(world, maxf(box.size.x, box.size.z) * 3.0)
	_figure(world, Vector3(box.end.x + 2.0, 0.0, 0.0))

	var cam := Camera3D.new()
	cam.far = 2000.0
	world.add_child(cam)
	cam.make_current()
	var c := box.get_center()
	var reach: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var eye := Vector3(c.x, box.size.y * 0.4, c.z)
	# ALL FOUR SIDES, not two. A block is rarely symmetrical — this family has
	# its alcove on one face and its cable runs on the opposite one — and two
	# views leave half of it unphotographed while the header claims otherwise.
	var shots: Array = [
		["01_plus_x", Vector3(c.x + reach * 1.1, FIGURE, c.z), eye, 55.0],
		["02_plus_z", Vector3(c.x, FIGURE, c.z + reach * 1.1), eye, 55.0],
		["02b_minus_x", Vector3(c.x - reach * 1.1, FIGURE, c.z), eye, 55.0],
		["02c_minus_z", Vector3(c.x, FIGURE, c.z - reach * 1.1), eye, 55.0],
		["03_three_quarter", Vector3(c.x + reach * 0.8, reach * 0.45, c.z + reach * 0.8), c, 50.0],
		["04_plan", Vector3(c.x, reach * 1.5, c.z + reach * 0.35), c, 50.0],
		["05_on_the_deck", Vector3(c.x, box.end.y + FIGURE, c.z - box.size.z * 0.45),
				Vector3(c.x, box.end.y + FIGURE, c.z + box.size.z * 0.5), 62.0],
	]
	for s: Array in shots:
		cam.fov = float(s[3])
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for pass_i in 2:
			for _i in 8:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("%s_%s.png" % [piece.get_file(), s[0]]))
		print("   %s" % s[0])
	quit()


func _floor(world: Node3D, size: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.34, 0.3)
	mat.roughness = 1.0
	mi.material_override = mat
	world.add_child(mi)


func _figure(world: Node3D, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = FIGURE
	cap.radius = 0.3
	mi.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.35, 0.2)
	mi.material_override = mat
	world.add_child(mi)
	mi.position = at + Vector3(0.0, FIGURE * 0.5, 0.0)


func _light(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.56)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 125.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
