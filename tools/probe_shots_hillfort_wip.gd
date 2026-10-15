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
	# is 376 x 248 inside the boundary walls.
	["00_plan", Vector3(0.0, 420.0, 0.0), Vector3(0.0, 0.0, 0.0), 40.0, "abs"],
	["00b_plan_north", Vector3(0.0, 260.0, -56.0), Vector3(0.0, 0.0, -56.0), 46.0, "abs"],
	# Obliques, for reading the shape: a broad gentle dome with a walled fort on
	# the crown and two wall lines dividing the approach into three.
	["01_from_the_south", Vector3(-20.0, 150.0, 230.0), Vector3(0.0, 24.0, -40.0), 50.0, "abs"],
	["02_from_the_west", Vector3(-320.0, 130.0, 60.0), Vector3(10.0, 24.0, -40.0), 48.0, "abs"],
	["03_the_fort_from_the_east", Vector3(290.0, 120.0, -40.0), Vector3(0.0, 40.0, -70.0), 46.0, "abs"],

	# ── EYE LEVEL, 1.50 m, through the game's own signal filter.
	# From the spawn, looking at the fort. The one question the whole redesign
	# had to not break: on gentle ground there is no mesa to lift the dish, so
	# it has to carry itself.
	["10_trailhead_looking_up", Vector3(0.0, EYE, 112.0), Vector3(-10.0, 50.0, -58.0), 62.0, "eye"],
	# THE FAN. Standing at the spawn looking north: the two lane walls end
	# twenty metres short of here, and this is where the choice is made.
	["11_the_fan_from_the_spawn", Vector3(0.0, EYE, 122.0), Vector3(0.0, 8.0, 40.0), 72.0, "eye"],

	# ── ONE PER LANE, FROM ITS FOOT, which is where the choice is taken.
	["12_centre_lane_foot", Vector3(0.0, EYE, 100.0), Vector3(0.0, 8.0, 8.0), 66.0, "eye"],
	["13_west_lane_foot", Vector3(-118.0, EYE, 104.0), Vector3(-134.0, 8.0, 28.0), 66.0, "eye"],
	["14_east_lane_foot", Vector3(108.0, EYE, 108.0), Vector3(110.0, 8.0, 28.0), 66.0, "eye"],

	# ── THE CENTRE LANE: short and exposed, one bunker, straight at the gate.
	["15_centre_the_bunker", Vector3(-34.0, EYE, 74.0), Vector3(4.0, 10.0, 48.0), 66.0, "eye"],
	["16_centre_under_the_wall", Vector3(0.0, EYE, 40.0), Vector3(0.0, 26.0, -40.0), 62.0, "eye"],
	["17_the_south_gate", Vector3(0.0, EYE, 12.0), Vector3(0.0, 10.0, -26.0), 62.0, "eye"],

	# ── THE WEST LANE: long and covered, two bunkers, berms on the open bits.
	["18_west_the_cistern", Vector3(-154.0, EYE, 92.0), Vector3(-126.0, 10.0, 68.0), 66.0, "eye"],
	["19_west_the_shoulder", Vector3(-166.0, EYE, -4.0), Vector3(-136.0, 10.0, -24.0), 66.0, "eye"],
	["20_from_the_fort_looking_back", Vector3(0.0, EYE, -12.0), Vector3(0.0, -6.0, 110.0), 70.0, "eye"],
	["21_the_west_gate", Vector3(-92.0, EYE, -54.0), Vector3(-54.0, 10.0, -54.0), 62.0, "eye"],

	# ── THE EAST LANE: blocked until the gatehouse is taken.
	["22_east_the_cross_wall", Vector3(140.0, EYE, 86.0), Vector3(106.0, 8.0, 36.0), 66.0, "eye"],
	["23_east_through_the_gate", Vector3(104.0, EYE, 56.0), Vector3(106.0, 10.0, 8.0), 66.0, "eye"],
	["24_east_the_terrace", Vector3(120.0, EYE, -32.0), Vector3(146.0, 10.0, -28.0), 66.0, "eye"],
	["25_the_east_gate", Vector3(92.0, EYE, -54.0), Vector3(54.0, 10.0, -54.0), 62.0, "eye"],

	# ── INSIDE.
	["26_the_yard", Vector3(0.0, EYE, -100.0), Vector3(-10.0, 30.0, -62.0), 66.0, "eye"],
	["27_under_the_dish", Vector3(-52.0, EYE, -58.0), Vector3(-10.0, 45.0, -58.0), 70.0, "eye"],
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
