extends SceneTree

# ─────────────────────────────────────────────
# SHOTS HILLFORT WIP — the picture the brief actually asks for: a top-down
# plan of maps/hillfort_wip_level.tscn, plus eye-level views THROUGH THE
# GAME'S OWN SIGNAL FILTER at the real 1.50 m eye.
#
#   RENDER_OUT=<dir> godot --path . --audio-driver Dummy \
#       --script res://tools/probe_shots_hillfort_wip.gd
#   RENDER_OUT=<dir> ONLY=01 godot --path . ...
#   RENDER_OUT=<dir> NOFILTER=1 godot --path . ...
#
# NOT headless. The dummy renderer returns blank images, and the filter is a
# shader that READS THE SCREEN — with no screen there is nothing to read, so a
# headless run comes back as a flat picture of nothing and looks like proof.
#
# WHY THIS FILE RATHER THAN A ROW IN tools/probe_shots_filtered.gd OR A LINE IN
# tools/minimap_bake.gd. Both of those are shared: the shots tool holds the
# cameras for eight levels and the minimap bake writes into maps/minimaps/ for
# every level in a hard-coded list, which the brief warns about by name. Three
# lanes share this checkout, so a WIP gets its own file and touches neither.
#
# THE FILTER MATERIAL IS READ OUT OF Character/hud/hud.tscn, the way
# probe_shots_filtered.gd does it — scene values beat shader defaults, and the
# shader's declared defaults are not what ships. It is read from the scene's
# SceneState rather than by instantiating the HUD, because hud.gd expects a
# player and a campaign and this has neither.
#
# 1152 x 648, WHICH IS WHAT THE GAME RENDERS AT. The shader snaps to an
# integer grid of floor(height / signal_height): at 648p that is 1 and at 1080p
# it would be 3, which is a visibly chunkier picture than anybody plays.
#
# THE EYE IS 1.50 m. Not the 1.65 the older shot tools use and not the shader's
# own default — 1.50 is where the proving-ground shots settled and it is the
# height a judgement about whether the fort READS has to be made from.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/hillfort_wip_level.tscn"
const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"

## How far above the ground under it an "eye" camera stands.
const EYE := 1.50

# name, camera, look at, fov, mode
#   "abs" — both vectors are world positions.
#   "eye" — the Y of each vector is a height ABOVE THE COLLISION under it, AND
#           THAT INCLUDES THE LOOK-AT. Four shots here first used the look-at
#           Y as a world height — 70 for "the plateau" — on points where the
#           ground already was 70, and came back as pictures of the sky. On a
#           map whose relief is 74 m, a fixed Y is either buried or floating
#           depending on where you stood; every eye shot in the big map's
#           history that came back black was this mistake.
const SHOTS: Array = [
	# ── THE PLAN. Straight down, framed on the whole playable rectangle, which
	# is 376 x 248 inside the boundary walls. A 16:9 frame over a 1.52:1 map
	# means the width is what fills it.
	["00_plan", Vector3(0.0, 460.0, 0.0), Vector3(0.0, 0.0, 0.0), 40.0, "abs"],
	["00b_plan_north", Vector3(0.0, 300.0, -56.0), Vector3(0.0, 0.0, -56.0), 46.0, "abs"],
	# Obliques, for reading the climb as a climb.
	["01_from_the_south", Vector3(-20.0, 190.0, 240.0), Vector3(0.0, 40.0, -40.0), 50.0, "abs"],
	["02_from_the_west", Vector3(-330.0, 160.0, 60.0), Vector3(10.0, 40.0, -40.0), 48.0, "abs"],
	["03_the_fort_from_the_east", Vector3(300.0, 150.0, -40.0), Vector3(0.0, 56.0, -70.0), 46.0, "abs"],

	# ── EYE LEVEL, 1.50 m, through the filter. The three the brief names, plus
	# the ones that answer whether a bench is a bench.
	# From the trailhead looking up: the whole question of whether 62 m of dish
	# on a 70 m plateau reads from the spawn at 190 m.
	["10_trailhead_looking_up", Vector3(-137.0, EYE, 61.0), Vector3(-10.0, 70.0, -50.0), 62.0, "eye"],
	["11_trailhead_the_staging", Vector3(-150.0, EYE, 68.0), Vector3(-120.0, 2.0, 50.0), 66.0, "eye"],
	# A mid bench: the Pillars, a third of the way up, looking at the fort.
	["12_pillars_looking_up", Vector3(48.0, EYE, 82.0), Vector3(-6.0, 70.0, -56.0), 62.0, "eye"],
	["13_pillars_on_the_pad", Vector3(30.0, EYE, 90.0), Vector3(66.0, 2.0, 74.0), 66.0, "eye"],
	# The Gate and the Terrace: the two stations whose near lip has to clear
	# 23 m or the objective is invisible from the approach.
	["14_the_gate_looking_up", Vector3(115.0, EYE, 18.0), Vector3(0.0, 70.0, -56.0), 60.0, "eye"],
	["15_the_terrace_looking_up", Vector3(124.0, EYE, -66.0), Vector3(0.0, 70.0, -66.0), 58.0, "eye"],
	# The last ramp, walked: along the front of the wall to the gate.
	["16_the_ramp", Vector3(96.0, EYE, 4.0), Vector3(48.0, 6.0, -16.0), 62.0, "eye"],
	# ON the new causeway, two thirds of the way up, with the gate at the head
	# of it. This is the camera for the change the human asked for: the last
	# move is up and in, not up and then sideways.
	["16b_up_the_ramp", Vector3(92.0, EYE, 4.0), Vector3(48.0, 10.0, -18.0), 62.0, "eye"],
	["16c_the_causeway_from_below", Vector3(104.0, EYE, 54.0), Vector3(48.0, 16.0, -18.0), 58.0, "eye"],
	["17_the_apron", Vector3(48.0, EYE, 12.0), Vector3(48.0, 12.0, -30.0), 62.0, "eye"],
	# Inside: the yard, and the dish from its own foot.
	["18_the_yard", Vector3(20.0, EYE, -104.0), Vector3(-10.0, 24.0, -64.0), 66.0, "eye"],
	["19_under_the_dish", Vector3(-52.0, EYE, -58.0), Vector3(-10.0, 45.0, -58.0), 70.0, "eye"],
	# And from the fort, looking back down the whole climb.
	["20_from_the_fort_looking_back", Vector3(48.0, EYE, -4.0), Vector3(-120.0, 10.0, 70.0), 64.0, "eye"],
	["21_from_the_wall_looking_back", Vector3(0.0, EYE, -14.0), Vector3(-40.0, 20.0, 110.0), 66.0, "eye"],
	# The ground the road does not go: the flanker's side of the map.
	["22_the_west_shelf", Vector3(-140.0, EYE, -40.0), Vector3(-20.0, 40.0, -60.0), 60.0, "eye"],
	["23_the_watchpost", Vector3(-6.0, EYE, 44.0), Vector3(-6.0, 30.0, -50.0), 60.0, "eye"],
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
		print("   made %s" % out)
	var only := OS.get_environment("ONLY")
	# NOFILTER=1 shoots the same cameras with the rect left off. It is the only
	# way to tell "the filter looks like that" from "my viewport is lighting
	# the level wrong", and that is not guessable from one picture.
	var bare := OS.get_environment("NOFILTER") != ""
	var suffix := "_raw" if bare else ""

	var mat := _hud_filter()
	if mat == null:
		print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	print("   filter: %s%s" % [mat.shader.resource_path.get_file(),
			"  (OFF — NOFILTER set)" if bare else ""])

	var packed := load(LEVEL) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % LEVEL)
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)

	# The filter goes in the ROOT viewport, over the world, exactly where
	# hud.tscn puts it when the game runs. A SubViewport is a different render
	# target and a shader that READS THE SCREEN is the one kind that can tell.
	var layer: CanvasLayer = null
	if not bare:
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
		push_warning("probe_shots_hillfort_wip: viewport is %dx%d, not %dx%d — the signal grid will not match the game's" % [
				int(seen.x), int(seen.y), WIDTH, HEIGHT])

	# Terrain colliders need frames before a raycast against them means
	# anything, and the "eye" shots are all raycasts.
	for _i in 60:
		await physics_frame
	var space := level.get_world_3d().direct_space_state
	var cam := Camera3D.new()
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()

	var done := 0
	for s: Array in SHOTS:
		if only != "" and not (only in String(s[0])):
			continue
		var from: Vector3 = s[1]
		var at: Vector3 = s[2]
		if s[4] == "eye":
			from.y += _ground(space, from.x, from.z)
			at.y += _ground(space, at.x, at.z)
		cam.fov = float(s[3])
		cam.position = from
		# STRAIGHT DOWN NEEDS A DIFFERENT UP. look_at refuses when the up
		# vector and the view direction are parallel, and it refuses by
		# printing an error and leaving the camera where it was — so the plan
		# shots came back as whatever the previous camera was looking at, which
		# is the kind of failure that looks like a picture. For a vertical
		# view, north is up.
		var dir := (at - from).normalized()
		cam.look_at(at, Vector3.FORWARD if absf(dir.y) > 0.999 else Vector3.UP)
		# The first frame off a fresh camera comes back blank while the
		# renderer warms up, so every shot is taken twice and the second kept.
		# The filter needs the warm one too — it reads the screen, and a blank
		# screen filters to a blank picture.
		for pass_i in 2:
			for _i in 12:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("hfw_%s%s.png" % [s[0], suffix]))
		done += 1
		print("   %-32s eye at %.1f" % [s[0], from.y])
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


## The height of whatever is under (x, z). ASK, DO NOT WORK IT OUT: the ground
## here is two cones plus five hills minus five hollows plus twelve stamps plus
## five road beds plus the sketch's relief, and computing it by hand gets it
## wrong every time — which comes back as a black rectangle.
func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -60.0, z))
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		return float(hit["position"].y)
	# Every early return warns. A miss means the ray found nothing at all,
	# which on a map with a floor means the coordinate is off it.
	push_warning("probe_shots_hillfort_wip: nothing under (%.0f, %.0f) — is it off the map?" % [x, z])
	return 0.0


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
