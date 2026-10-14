extends SceneTree

# ─────────────────────────────────────────────
# SHOTS BUNKER — the bunker entrance, in its three mountings, at the three door
# fractions, THROUGH THE GAME'S OWN SIGNAL FILTER.
#
#   RENDER_OUT=<dir> godot --audio-driver Dummy --path . \
#       --script res://tools/probe_shots_bunker.gd
#   RENDER_OUT=<dir> ONLY=cliff godot --path . ...      (substring of the shot id)
#   RENDER_OUT=<dir> NOFILTER=1 godot --path . ...      (the same cameras, raw)
#
# NOT headless: the dummy renderer returns blank images, and a shader that
# reads the screen has no screen to read.
#
# WHY THE FILTER. docs say it and this kit depends on it: the player sees ten
# luma steps on an integer grid, not a lit render. The whole claim being tested
# here is "the half-open doors read as about halfway, from cover, with no HUD",
# and a shot taken outside the filter answers a question nobody asks. The
# material is READ OUT OF Character/hud/hud.tscn rather than copied, so it
# cannot drift from the one that ships, and it is read from the SceneState
# because hud.gd wants a player and a campaign that do not exist here.
#
# THE EYE IS 1.50 m. That is where this game's camera actually is — not the
# 1.65 the older survey tools use.
#
# THE DOORS ARE POSED BY THE SAME TWO LINES GAMEPLAY WILL USE, and that is
# deliberate: if this rig had to do anything cleverer than set position.x on two
# nodes, the model would not be the model it was asked for.
# ─────────────────────────────────────────────

const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"
const EYE := 1.50

const B := preload("res://tools/block_bunker.gd")
const MOUNTED := "res://maps/blocks/bunker/bunker_entrance_%s.tscn"

## mounting, fraction, id, camera, look at, fov.
## The camera positions are the squad's: on the ground, on the approach, at
## ranges a player actually holds a bunker from. Godot +Z is the approach, so
## every outside camera is at positive z looking toward the doors at z ≈ 0.
const SHOTS: Array = [
	# THE FRAME THAT MATTERS. If 0.5 does not read as about halfway from 60 m,
	# the design has failed and no other picture rescues it.
	["cliff", 0.5, "01_half_at_60m", Vector3(0.0, EYE, 60.0), Vector3(0.0, 3.0, 0.0), 62.0],
	["cliff", 0.0, "02_shut_at_60m", Vector3(0.0, EYE, 60.0), Vector3(0.0, 3.0, 0.0), 62.0],
	["cliff", 1.0, "03_open_at_60m", Vector3(0.0, EYE, 60.0), Vector3(0.0, 3.0, 0.0), 62.0],
	# The same three from cover, off the axis, which is where the player spends
	# the 45 seconds.
	["cliff", 0.0, "04_shut_from_cover", Vector3(26.0, EYE, 34.0), Vector3(0.0, 2.5, 0.0), 58.0],
	["cliff", 0.5, "05_half_from_cover", Vector3(26.0, EYE, 34.0), Vector3(0.0, 2.5, 0.0), 58.0],
	["cliff", 1.0, "06_open_from_cover", Vector3(26.0, EYE, 34.0), Vector3(0.0, 2.5, 0.0), 58.0],
	# Twice the distance again: the silhouette test.
	["cliff", 0.5, "07_half_at_120m", Vector3(0.0, EYE, 120.0), Vector3(0.0, 4.0, 0.0), 62.0],
	["cliff", 1.0, "08_open_at_120m", Vector3(0.0, EYE, 120.0), Vector3(0.0, 4.0, 0.0), 62.0],
	# Close enough to read the mechanism and the terminal.
	["cliff", 0.5, "09_half_at_14m", Vector3(0.0, EYE, 14.0), Vector3(0.0, 2.5, 0.0), 66.0],
	["cliff", 1.0, "10_the_terminal", Vector3(10.5, EYE, 6.0), Vector3(8.0, 1.3, 2.8), 62.0],
	# FROM INSIDE LOOKING OUT, which is the first thing seen on every defence.
	["cliff", 1.0, "11_inside_looking_out", Vector3(0.0, EYE, -7.0), Vector3(0.0, 2.0, 30.0), 70.0],
	["cliff", 0.5, "12_inside_half_open", Vector3(0.0, EYE, -7.0), Vector3(0.0, 2.0, 30.0), 70.0],
	# The other two mountings, at the fraction that matters.
	["open", 0.5, "13_court_half", Vector3(0.0, EYE, 46.0), Vector3(0.0, 2.5, 0.0), 62.0],
	["open", 0.5, "14_court_from_the_lip", Vector3(-8.0, EYE + 2.5, 34.0), Vector3(0.0, 2.5, 0.0), 62.0],
	["open", 1.0, "15_court_open", Vector3(0.0, EYE, 24.0), Vector3(0.0, 2.5, 0.0), 64.0],
	["wall", 0.5, "16_flush_half", Vector3(0.0, EYE, 24.0), Vector3(0.0, 2.5, 0.0), 62.0],
	["wall", 1.0, "17_flush_open", Vector3(0.0, EYE, 12.0), Vector3(0.0, 2.5, 0.0), 66.0],
	# From above, so the dock pad and the beacon mount can be seen to be clear.
	["cliff", 1.0, "18_the_deck", Vector3(0.0, 18.0, 22.0), Vector3(0.0, 5.0, -2.0), 58.0],
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
	var bare := OS.get_environment("NOFILTER") != ""
	var suffix := "_raw" if bare else ""

	var mat := _hud_filter()
	if mat == null and not bare:
		print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	if not bare:
		print("   filter: %s" % mat.shader.resource_path.get_file())

	var layer: CanvasLayer = null
	if not bare:
		# The filter goes in the ROOT viewport, over the world, exactly where
		# hud.tscn puts it when the game runs. A SubViewport is a different
		# render target and a shader that READS THE SCREEN can tell.
		layer = CanvasLayer.new()
		layer.layer = 100
		var rect := ColorRect.new()
		rect.material = mat
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rect)
		root.add_child(layer)
	var seen := root.get_visible_rect().size
	if int(seen.y) != HEIGHT:
		push_warning("probe_shots_bunker: viewport is %dx%d, not %dx%d — the signal grid snaps to floor(height / signal_height), so this is a different picture, not just a bigger one" % [
				int(seen.x), int(seen.y), WIDTH, HEIGHT])

	var done := 0
	# One staging per (mounting, fraction): loading and posing is the expensive
	# part, so the list is walked in that order and the cameras move inside it.
	var keys: Array = []
	for s: Array in SHOTS:
		var k := "%s|%.2f" % [s[0], s[1]]
		if not keys.has(k):
			keys.append(k)
	for k: String in keys:
		var wanted: Array = []
		for s: Array in SHOTS:
			if "%s|%.2f" % [s[0], s[1]] != k:
				continue
			if only != "" and not (only in String(s[2]) or only in String(s[0])):
				continue
			wanted.append(s)
		if wanted.is_empty():
			continue
		var mounting: String = k.get_slice("|", 0)
		var f: float = float(k.get_slice("|", 1))
		var world := _stage(mounting, f)
		if world == null:
			print("FAIL  no %s — run block_bunker.gd, block_prefabs.gd, build_bunker.gd" % (MOUNTED % mounting))
			quit(1)
			return
		var cam := Camera3D.new()
		cam.far = 3000.0
		world.add_child(cam)
		cam.make_current()
		for _i in 20:
			await process_frame
		for s: Array in wanted:
			cam.fov = float(s[5])
			cam.position = s[3]
			cam.look_at(s[4], Vector3.UP)
			# Every shot is taken twice and the second kept: the first frame off
			# a fresh camera comes back blank while the renderer warms up, and
			# the filter reads the screen, so a blank screen filters to a blank
			# picture.
			for pass_i in 2:
				for _i in 12:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(
							out.path_join("bunker_%s%s.png" % [s[2], suffix]))
			done += 1
			print("   %-6s f=%.2f  %s" % [mounting, f, s[2]])
		root.remove_child(world)
		world.queue_free()
		await process_frame
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


## An empty site with a sun, a sky and a floor, the mounting dropped at the
## origin and the doors posed at `f`. Nothing else: this is a picture of the
## model, and a level round it would answer a different question.
func _stage(mounting: String, f: float) -> Node3D:
	var packed := load(MOUNTED % mounting) as PackedScene
	if packed == null:
		return null
	var world := Node3D.new()
	world.name = "Stage"
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.40, 0.46, 0.52)
	pm.sky_horizon_color = Color(0.62, 0.62, 0.58)
	pm.ground_bottom_color = Color(0.26, 0.26, 0.24)
	pm.ground_horizon_color = Color(0.48, 0.47, 0.43)
	sky.sky_material = pm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	world.add_child(sun)
	# OVER THE PLAYER'S SHOULDER. A DirectionalLight3D shines down its own -Z,
	# so a light with no yaw lights the faces pointing at +Z — which is the
	# approach, which is where the doors face and where the camera is. The
	# first version of this rig had 155° of yaw on it and photographed a
	# silhouette: a door whose POSITION is the readout has to be lit on the
	# face, or there is nothing to read.
	sun.rotation_degrees = Vector3(-46.0, 24.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true

	# The ground, just under the module's own slab so it can never poke through
	# it, and big enough that its edge is never in a frame. The sunken court's
	# grade is 2.5 m above the mouth's datum — one number, read off the block
	# tool rather than retyped — and the court is a HOLE in that grade, so
	# there the apron is laid in three pieces round the cut instead of one.
	var y: float = B.COURT_DEEP - 0.02 if mounting == "open" else -0.02
	var pieces: Array = [[Vector2(600.0, 600.0), Vector3(0.0, y, 0.0)]]
	if mounting == "open":
		var w: float = B.COURT_HALF + 1.0
		pieces = [
			[Vector2(300.0, 600.0), Vector3(-w - 150.0, y, 0.0)],
			[Vector2(300.0, 600.0), Vector3(w + 150.0, y, 0.0)],
			[Vector2(2.0 * w, 300.0), Vector3(0.0, y, B.COURT_X1 + 1.0 + 150.0)],
			[Vector2(2.0 * w, 300.0), Vector3(0.0, y, B.SLAB_X0 - 0.5 - 150.0)],
		]
	for i in pieces.size():
		var mi := MeshInstance3D.new()
		mi.name = "Ground_%d" % i
		var plane := PlaneMesh.new()
		plane.size = pieces[i][0]
		mi.mesh = plane
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.40, 0.39, 0.35)
		mi.material_override = gm
		world.add_child(mi)
		mi.position = pieces[i][1]

	var ent := packed.instantiate() as Node3D
	world.add_child(ent)
	var ll := ent.find_child("LeafLeft", true, false) as Node3D
	var lr := ent.find_child("LeafRight", true, false) as Node3D
	if ll == null or lr == null:
		push_warning("probe_shots_bunker: no LeafLeft/LeafRight in %s — the doors cannot be posed" % mounting)
	else:
		# THE WHOLE MECHANISM, and all of it.
		ll.position.x = -B.TRAVEL * f
		lr.position.x = B.TRAVEL * f
	return world


## The HUD's own filter material, read out of the scene file rather than
## instantiated: hud.gd wants a player and a campaign that do not exist here.
func _hud_filter() -> ShaderMaterial:
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != FILTER_NODE:
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) != "material":
				continue
			var m: Variant = state.get_node_property_value(i, j)
			if m is ShaderMaterial:
				# Duplicated so nothing here can write back into the HUD's own
				# resource if this tool ever grows a knob.
				return (m as ShaderMaterial).duplicate()
			return null
	return null
