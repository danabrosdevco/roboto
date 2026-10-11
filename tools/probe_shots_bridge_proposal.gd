extends SceneTree

# ─────────────────────────────────────────────
# BRIDGE SHOTS — the same five cameras pointed at a bridge prefab, so before
# and after can be flipped between rather than squinted at.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_bridge_proposal.gd
#   RENDER_OUT=<dir> DIR=res://maps/blocks/bridges PIECES=bridge_long,bridge_short ...
#   RENDER_OUT=<dir> TAG=_before ...
#
# NOT headless: the dummy renderer returns blank images.
#
# THE CAMERAS ARE PLACED OFF EACH BRIDGE'S OWN SPAN AND DECK HEIGHT, from the
# table below, and not off its bounding box. A camera framed on the bounds
# moves when the thing changes size, and then two pictures of two versions are
# also two pictures from two places, which is worth nothing as a comparison.
#
# It builds a bank at the ramp-foot height on each side and water between
# them, because the complaint being answered is bodies ending up in the river
# and a picture with no river in it cannot show that.
# ─────────────────────────────────────────────

## piece -> [half span, deck top]. Both are what the builder was called with,
## not anything measured, so the cameras do not move when the bridge does.
const BRIDGE := {
	"bridge_short": [6.0, 2.25],
	"bridge_medium": [15.0, 3.5],
	"bridge_long": [36.0, 4.0],
	"bridge_very_long": [64.0, 5.0],
	"bridge_wide": [18.0, 4.0],
	"bridge_highway": [30.0, 5.0],
	"bridge_damaged": [20.0, 3.5],
	"bridge_truss": [24.0, 3.0],
	"bridge_truss_long": [36.0, 3.0],
	"prop_truss_now": [36.0, 3.0],
	"prop_truss_edges": [36.0, 3.0],
	"prop_truss_full": [36.0, 3.0],
}

const BANK := -0.5
const WATER := -1.2
const EYE := 1.6


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
	var dir := OS.get_environment("DIR")
	if dir == "":
		dir = "res://maps/blocks/proposals"
	var tag := OS.get_environment("TAG")
	var pieces: Array = []
	var listed := OS.get_environment("PIECES")
	if listed == "":
		pieces = ["prop_truss_now", "prop_truss_edges", "prop_truss_full"]
	else:
		for p in listed.split(",", false):
			pieces.append(p.strip_edges())

	for piece: String in pieces:
		if not BRIDGE.has(piece):
			# Guessing a camera for an unlisted bridge gives a picture of the
			# sky or the inside of a pier, and both look like a broken tool.
			print("FAIL  %s is not in the camera table — add its half span and deck height" % piece)
			quit(1)
			return
		var packed := load("%s/%s.tscn" % [dir, piece]) as PackedScene
		if packed == null:
			print("FAIL  no prefab at %s/%s.tscn" % [dir, piece])
			quit(1)
			return
		var half: float = BRIDGE[piece][0]
		var deck: float = BRIDGE[piece][1]
		var world := Node3D.new()
		root.add_child(world)
		_light(world)
		world.add_child(packed.instantiate())
		_banks(world, half, deck)
		_figures(world, half, deck)

		var cam := Camera3D.new()
		cam.far = 2000.0
		world.add_child(cam)
		cam.make_current()
		# Where the ramp foot lands, from the builder's own numbers: half a
		# metre of level deck, then 1 in 3 down to half a metre below the
		# origin.
		var foot: float = half + 0.5 + (deck + 0.5) * 3.0
		for s: Array in _shots(half, deck, foot):
			cam.fov = float(s[3])
			cam.position = s[1]
			cam.look_at(s[2], Vector3.UP)
			# The first frame off a fresh camera comes back blank while the
			# renderer warms up, so each is taken twice and the second kept.
			for pass_i in 2:
				for _i in 10:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(
							out.path_join("%s_%s%s.png" % [piece, s[0], tag]))
			print("   %-20s %s" % [piece, s[0]])
		root.remove_child(world)
		world.queue_free()
		await process_frame
	print("   written to %s" % out)
	quit()


func _shots(half: float, deck: float, foot: float) -> Array:
	return [
		# Walking at the bridge. What a body coming off the road sees, and
		# whether anything at all stands between it and the water on the way up.
		["01_the_approach", Vector3(0.0, BANK + EYE, foot + 9.0), Vector3(0.0, deck + 1.0, half * 0.5), 62.0],
		# Standing on the deck: how high the barrier is against a 1.5 m body.
		["02_on_the_deck", Vector3(2.4, deck + EYE, half * 0.7), Vector3(1.2, deck + 1.2, -half * 0.6), 68.0],
		# The end of the span from outside it: the abutment, the flank, and
		# the point where the deck's parapet stops.
		["03_where_the_barrier_stops", Vector3(half * 0.45 + 6.0, deck + 5.5, foot - 2.0),
				Vector3(0.0, deck, half * 0.8), 50.0],
		# The same junction from above: the only view that shows how wide the
		# walkable top is and what shape the approach is.
		["04_the_approach_from_above", Vector3(0.0, deck + 30.0, foot + 9.0), Vector3(0.0, 0.0, half * 0.8), 52.0],
		# From the water, level with it, looking at the embankment flank: the
		# surface a squad can presently be ordered down.
		["05_the_flank_from_the_water", Vector3(half * 0.5 + 8.0, WATER + 1.4, foot - 5.0),
				Vector3(2.0, 1.0, foot - 10.0), 58.0],
	]


## A bank at the ramp-foot height beyond each end, meeting the embankment
## about halfway down the ramp — which is what a river bank under one of these
## actually looks like — and water between them.
func _banks(world: Node3D, half: float, deck: float) -> void:
	var foot: float = half + 0.5 + (deck + 0.5) * 3.0
	var meet: float = half + (foot - half) * 0.55
	for s: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var p := BoxMesh.new()
		p.size = Vector3(320.0, 1.0, 160.0)
		m.mesh = p
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.34, 0.31, 0.26)
		mat.roughness = 1.0
		m.material_override = mat
		world.add_child(m)
		m.position = Vector3(0.0, BANK - 0.5, s * (meet + 80.0))
	var w := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(320.0, 400.0)
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
func _figures(world: Node3D, half: float, deck: float) -> void:
	var foot: float = half + 0.5 + (deck + 0.5) * 3.0
	for at: Vector3 in [Vector3(-2.6, deck, -half * 0.2), Vector3(2.0, deck, half * 0.85),
			Vector3(0.0, BANK, foot + 4.0), Vector3(deck * 2.2, WATER - 0.6, foot - 8.0)]:
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
