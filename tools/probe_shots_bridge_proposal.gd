extends SceneTree

# ─────────────────────────────────────────────
# BRIDGE PROPOSAL SHOTS — the same five cameras pointed at each of the
# proposal bridges in maps/blocks/proposals, so the pictures can be flipped
# between rather than squinted at.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_bridge_proposal.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# THE CAMERAS ARE FIXED, not framed off each piece's bounds. A camera that
# frames what it is given moves when the thing changes size, and then two
# pictures of two bridges are also two pictures from two places, which is
# worth nothing as a comparison.
#
# It builds a bank at the ramp-foot height on each side and water between
# them, because the complaint being answered is bodies ending up in the river
# and a picture with no river in it cannot show that.
# ─────────────────────────────────────────────

const PIECES := ["prop_truss_now", "prop_truss_edges", "prop_truss_full"]

## The bridge runs along the prefab's Z. Deck top is 3.0, the span reaches
## z = +-36, the ramps run out to about +-47, and the ramp feet sit 0.5 m
## below the origin.
const DECK := 3.0
const SPAN := 36.0
const BANK := -0.5
const WATER := -1.2
const EYE := 1.6

## name, camera, look at, fov.
const SHOTS: Array = [
	# Walking at the bridge. What a body coming off the road sees, and whether
	# anything at all stands between it and the water on the way up.
	["01_the_approach", Vector3(0.0, BANK + EYE, 56.0), Vector3(0.0, DECK + 1.0, 20.0), 62.0],
	# Standing on the deck. How high the barrier is against a 1.5 m body.
	["02_on_the_deck", Vector3(2.4, DECK + EYE, 24.0), Vector3(1.2, DECK + 1.2, -20.0), 68.0],
	# The end of the span from outside it: the abutment, the flank, and the
	# point where the deck's barrier stops.
	["03_where_the_barrier_stops", Vector3(16.0, 8.5, 48.0), Vector3(0.0, DECK, 30.0), 50.0],
	# The same junction from above, which is the only view that shows how wide
	# the walkable top is and what shape the approach is.
	["04_the_approach_from_above", Vector3(0.0, 34.0, 56.0), Vector3(0.0, 0.0, 28.0), 52.0],
	# From the water, level with it, looking at the embankment flank: the
	# surface a squad can presently be ordered down.
	["05_the_flank_from_the_water", Vector3(19.0, WATER + 1.4, 44.0), Vector3(2.0, 1.0, 38.0), 58.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	if not DirAccess.dir_exists_absolute(out):
		var err := DirAccess.make_dir_recursive_absolute(out)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [out, error_string(err)])
			quit(1)
			return
	var only := OS.get_environment("ONLY")

	for piece: String in PIECES:
		if only != "" and not (only in piece):
			continue
		var packed := load("res://maps/blocks/proposals/%s.tscn" % piece) as PackedScene
		if packed == null:
			print("FAIL  no prefab at maps/blocks/proposals/%s.tscn" % piece)
			quit(1)
			return
		var world := Node3D.new()
		root.add_child(world)
		_light(world)
		world.add_child(packed.instantiate())
		_banks(world)
		_figures(world)

		var cam := Camera3D.new()
		cam.far = 2000.0
		world.add_child(cam)
		cam.make_current()
		for s: Array in SHOTS:
			cam.fov = float(s[3])
			cam.position = s[1]
			cam.look_at(s[2], Vector3.UP)
			# The first frame off a fresh camera comes back blank while the
			# renderer warms up, so each is taken twice and the second kept.
			for pass_i in 2:
				for _i in 10:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [piece, s[0]]))
			print("   %-18s %s" % [piece, s[0]])
		root.remove_child(world)
		world.queue_free()
		await process_frame
	print("   written to %s" % out)
	quit()


## A bank at the ramp-foot height out beyond each end, and water between them.
## The banks stop short of the abutments so the embankment flanks are not
## buried in ground — those flanks are the thing being looked at.
func _banks(world: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var p := BoxMesh.new()
		p.size = Vector3(260.0, 1.0, 120.0)
		m.mesh = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.34, 0.31, 0.26)
		mat.roughness = 1.0
		m.material_override = mat
		world.add_child(m)
		# The bank meets the embankment about halfway down the ramp, so the
		# flank is over water near the abutment and over land further out —
		# which is what a river bank under one of these actually looks like.
		m.position = Vector3(0.0, BANK - 0.5, s * (SPAN + 65.0))
	var w := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(260.0, 300.0)
	w.mesh = wp
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.17, 0.26, 0.3)
	wm.metallic = 0.4
	wm.roughness = 0.12
	w.material_override = wm
	world.add_child(w)
	w.position = Vector3(0.0, WATER, 0.0)


## 1.5 m stand-ins, because every number in this argument is a height measured
## against a body and the pictures should be too. One on the deck, one at the
## ramp foot, one in the river where they keep ending up.
func _figures(world: Node3D) -> void:
	for at: Vector3 in [Vector3(-2.6, DECK, 6.0), Vector3(2.0, DECK, 30.0),
			Vector3(0.0, BANK, 50.0), Vector3(8.5, WATER - 0.6, 40.0)]:
		var m := MeshInstance3D.new()
		var c := CapsuleMesh.new()
		c.height = 1.5
		c.radius = 0.3
		m.mesh = c
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.36, 0.18)
		m.material_override = mat
		world.add_child(m)
		m.position = at + Vector3(0.0, 0.75, 0.0)


func _light(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.56, 0.62, 0.68)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.53, 0.57)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, 36.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	world.add_child(sun)
