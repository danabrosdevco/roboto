extends SceneTree

# ─────────────────────────────────────────────
# SHOTS FILTERED — survey pictures of the levels THROUGH THE GAME'S OWN SIGNAL
# FILTER, so what comes back is what a player sees rather than what the editor
# viewport shows.
#
#   RENDER_OUT="D:/Godot Games/roboto_shots" \
#       godot --path . --script res://tools/probe_shots_filtered.gd
#   RENDER_OUT=... ONLY=salient godot --path . ...   (substring of level or name)
#
# NOT headless: the dummy renderer returns blank images, and a shader that
# reads the screen has no screen to read.
#
# THE MATERIAL IS READ OUT OF Character/hud/hud.tscn, not copied into this
# file. The HUD's SignalFilter rect is the one the player looks through; a
# second set of numbers here would drift from it the first time anyone tuned
# the real one, and then these pictures would be of a filter that ships
# nowhere. It is read from the scene's SceneState rather than by instantiating
# the HUD, because hud.gd expects a player and a campaign and this has neither.
#
# RENDERED AT 1152x648, WHICH IS WHAT THE GAME RENDERS AT. project.godot sets
# window/stretch/mode="viewport" and leaves the viewport size at the default
# 1152x648, so the game draws at 648p and scales that up to the window — the
# filter never sees a 1080p image. It matters because the shader snaps to an
# integer grid of floor(height / signal_height): at 648p that is 1, and at
# 1080p it would be 3, which is a visibly chunkier picture than anybody plays.
# A SubViewport rather than the window, so a maximised or resized window
# cannot quietly change the answer.
#
# It changes nothing in the levels. Their own environment and sun are what you
# see, with the filter over the top.
# ─────────────────────────────────────────────

const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"

## Height above whatever is under the camera, in "eye" shots.
const EYE := 1.65

# level, name, camera, look at, fov, mode.
#   "abs" — both vectors are world positions.
#   "eye" — the Y of each vector is a height ABOVE THE COLLISION under it. A
#           trench is a cut and a slag heap is a rise, so a fixed Y is either
#           buried or floating depending on where you stood.
# The cameras are the ones already proven in the per-level shot tools. This
# tool is about the filter, not about finding new angles.
const SHOTS: Array = [
	["pittsburgh", "01_ohio_works", Vector3(-300.0, EYE, -60.0), Vector3(-400.0, 2.0, -170.0), 62.0, "eye"],
	["pittsburgh", "02_ohio_works_lane", Vector3(-352.0, EYE, -20.0), Vector3(-352.0, 2.0, -200.0), 62.0, "eye"],
	# The Strip was here and came back almost black: the camera stands in the
	# shade of a rise, and the filter has ten luma steps to spend on a frame
	# that is two of them. A shot that survives the filter is not the same
	# thing as a shot that survives the editor viewport.
	# Three ground-level Pittsburgh cameras were tried here — the Strip, the
	# river approach, the dam — and every one of them came back with a wall of
	# terrain across it. That level's ground is jagged and its near faces are
	# in shadow, and ten luma steps turn a shadowed slope into one flat black.
	# This is the long view from the south, which is the Pittsburgh frame the
	# human already kept. The fix for the others is the terrain, not the shot.
	["pittsburgh", "03_the_whole_valley", Vector3(0.0, 420.0, 640.0), Vector3(0.0, 0.0, -40.0), 50.0, "abs"],
	# These two are 10-16 m up rather than at eye level, and that is the
	# filter talking. Both looked up a slope whose near face is in shadow, and
	# ten luma steps render a shadowed slope as one flat black. Over the top
	# of it the same view has a skyline and a lit yard in it.
	["pittsburgh", "04_the_furnace", Vector3(300.0, 16.0, 250.0), Vector3(430.0, 2.0, 210.0), 60.0, "eye"],
	["hillfort", "05_the_trailhead", Vector3(0.0, 2.6, 442.0), Vector3(20.0, 112.0, -270.0), 55.0, "abs"],
	["hillfort", "06_the_gate", Vector3(-196.0, 64.0, 146.0), Vector3(60.0, 96.0, -80.0), 55.0, "abs"],
	["hillfort", "07_the_relay", Vector3(-16.0, 136.0, -240.0), Vector3(46.0, 140.0, -292.0), 62.0, "abs"],
	["hillfort", "08_the_upland", Vector3(236.0, 124.0, 64.0), Vector3(30.0, 128.0, -270.0), 44.0, "abs"],
	["salient", "09_the_jump_off", Vector3(-186.0, EYE, 40.0), Vector3(80.0, 2.0, 20.0), 62.0, "eye"],
	["salient", "10_no_mans_land", Vector3(-95.0, EYE, 105.0), Vector3(60.0, 2.0, 55.0), 64.0, "eye"],
	["salient", "11_the_crater", Vector3(-60.0, EYE, 46.0), Vector3(70.0, 2.0, -10.0), 64.0, "eye"],
	["salient", "12_their_wire", Vector3(-20.0, EYE, -30.0), Vector3(120.0, 2.0, -10.0), 62.0, "eye"],
	["mutaha_wip", "13_new_crossing_gate", Vector3(-150.0, 1.7, 312.0), Vector3(-80.0, 1.5, 318.0), 70.0, "abs"],
	["mutaha_wip", "14_quarter_street", Vector3(-208.5, 1.7, 200.0), Vector3(-208.5, 1.4, 110.0), 70.0, "abs"],
	["mutaha_wip", "15_island_tip_above", Vector3(-46.0, 96.0, 268.0), Vector3(-56.0, 0.0, 180.0), 64.0, "abs"],
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
	# NOFILTER=1 shoots the same cameras through the same viewport with the
	# rect left off. It is the only way to tell "the filter looks like that"
	# from "my viewport is lighting the level wrong", and the answer to that
	# question is not guessable from one picture.
	var bare := OS.get_environment("NOFILTER") != ""
	var suffix := "_raw" if bare else ""

	var mat := _hud_filter()
	if mat == null:
		print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	print("   filter: %s%s" % [mat.shader.resource_path.get_file(), "  (OFF — NOFILTER set)" if bare else ""])

	# One shot list, but a level is expensive to load, so walk it level by
	# level and keep the order of SHOTS inside each.
	var order: Array = []
	for s: Array in SHOTS:
		if not order.has(s[0]):
			order.append(s[0])

	var done := 0
	for level_name: String in order:
		var wanted: Array = []
		for s: Array in SHOTS:
			if s[0] == level_name and (only == "" or only in level_name or only in String(s[1])):
				wanted.append(s)
		if wanted.is_empty():
			continue
		var path := "res://maps/%s_level.tscn" % level_name
		var packed := load(path) as PackedScene
		if packed == null:
			print("FAIL  %s will not load" % path)
			quit(1)
			return

		var level := packed.instantiate() as Node3D
		root.add_child(level)
		# The filter goes in the ROOT viewport, over the world, exactly where
		# hud.tscn puts it when the game runs. It was in a SubViewport first,
		# to pin the resolution — but a SubViewport is a different render
		# target, and a shader that READS THE SCREEN is the one kind that can
		# tell. The root viewport is already 1152x648 here because the project
		# stretches rather than resizes it, so there was nothing to gain and a
		# colour-space difference to lose.
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
			# Not fatal, but say it: the grid the shader snaps to is
			# floor(height / signal_height), so a different height is a
			# different picture, not just a bigger one.
			push_warning("probe_shots_filtered: viewport is %dx%d, not %dx%d — the signal grid will not match the game's" % [
					int(seen.x), int(seen.y), WIDTH, HEIGHT])

		# Terrain colliders and anything that settles need frames before a
		# raycast against them means anything.
		for _i in 60:
			await physics_frame
		var space := level.get_world_3d().direct_space_state
		var cam := Camera3D.new()
		cam.far = 4000.0
		level.add_child(cam)
		cam.make_current()

		for s: Array in wanted:
			var from: Vector3 = s[2]
			var at: Vector3 = s[3]
			if s[5] == "eye":
				from.y += _ground(space, from.x, from.z)
				at.y += _ground(space, at.x, at.z)
			cam.fov = float(s[4])
			cam.position = from
			cam.look_at(at, Vector3.UP)
			# The first frame off a fresh camera comes back blank while the
			# renderer warms up, so every shot is taken twice and the second
			# kept. The filter needs the warm one as well — it reads the
			# screen, and a blank screen filters to a blank picture.
			for pass_i in 2:
				for _i in 12:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(
							out.path_join("%s_%s%s.png" % [level_name, s[1], suffix]))
			done += 1
			print("   %-12s %s" % [level_name, s[1]])
		# remove_child before the free: queue_free is deferred, and the next
		# level would otherwise be loaded into a tree that still holds this
		# one — two suns, two environments, two sets of colliders under the
		# raycasts.
		root.remove_child(level)
		level.queue_free()
		if layer != null:
			root.remove_child(layer)
			layer.queue_free()
		await process_frame
	print("   wrote %d shot(s) to %s" % [done, out])
	quit()


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


## The top of the collision under x,z. Cast from well above the tallest thing
## any of these levels has.
func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1200.0, z), Vector3(x, -400.0, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Say so. A camera placed off the end of the world takes a picture of
		# the sky, which reads as a rendering fault rather than a bad number.
		push_warning("probe_shots_filtered: nothing under %.0f, %.0f — camera placed at y = 0" % [x, z])
		return 0.0
	return (hit["position"] as Vector3).y
