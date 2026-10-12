extends SceneTree

# ─────────────────────────────────────────────
# THE DEPARTURE RIDE, PHOTOGRAPHED.
#
# Three things in this feature cannot be settled by a passing probe, because
# they are all about whether something is VISIBLE:
#
#   1. Can you see the tunnel scroll through the glass at all? The plates are
#      20 m outside the hull, so the car wall occludes them by design and only
#      the window apertures show them. If TERRAIN's glass writes depth, the
#      answer is no and the whole effect is invisible — and a probe that checks
#      the shader's `rate` uniform would still pass.
#   2. Does the generated handle read as a lever, or as two brass boxes?
#   3. Does the door leaf fill its opening, or is it the wrong size?
#
# So this stages the real base, drives the ride by hand, and writes PNGs.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_departure_ride.gd -- <out dir>
#
# HEADFUL, because this grabs the window's own viewport — the headless dummy
# renderer has no image to give. It does NOT resize the window: this machine
# runs borderless fullscreen and native is the only size that looks right.
#
# A CAMERA OF ITS OWN, never the player. The player is a CharacterBody3D and
# falls back to the floor across the physics frames before each grab, so a view
# set by moving it silently ends up at standing height wherever it was put.
# tools/shot_ops_table.gd has the measurement that cost.
# ─────────────────────────────────────────────

const RIDE := "res://Env/world_objects/departure_ride.gd"
const LEVER := "res://Env/world_objects/departure_lever.gd"

var _cam: Camera3D = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	# NEVER let a shot run write the campaign.
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var player: Node3D = world.player
	var level: Node = world.current_level
	if level == null:
		printerr("shot_departure_ride: no level loaded")
		quit(1)
		return

	var ride = _one(level, load(RIDE))
	var lever = _one(level, load(LEVER))
	if ride == null:
		printerr("shot_departure_ride: no DepartureRide in the level — has railhead_level.gd fitted it?")
		quit(1)
		return
	print("    ride found: %d tunnel plates, %d lamps, leaf = %s" % [
		ride._mats.size(), ride._lamps.size(), str(ride._leaf != null)])
	# WHERE THE PLATES ACTUALLY ARE. They are generated into TERRAIN's car
	# nodes at a car-LOCAL offset, on the assumption that car-local X is world
	# X; if a car carries a rotation that assumption is silently wrong and the
	# plates end up somewhere else entirely.
	var shown := 0
	for c in _all_named(level, "TunnelScroll"):
		if shown < 4:
			print("    plate %-18s world %s  size %s" % [
				c.name, str(c.global_position.snapped(Vector3.ONE * 0.01)),
				str((c.mesh as QuadMesh).size) if c is MeshInstance3D else "-"])
		shown += 1
	print("    %d plate node(s) in the tree" % shown)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()

	# ── 1. the windows, at rest and running ─────
	# Across the ops car at eye height, so the table is in the foreground and
	# the far wall's apertures are the background. The ops car sits at the
	# player's own spawn, so its position comes from the player rather than
	# being typed.
	var car_z: float = player.global_position.z
	var eye: float = player.global_position.y
	await _look(Vector3(-4.0, eye, car_z), Vector3(4.5, eye + 0.4, car_z))
	await _grab("%s/ride_01_windows_rest.png" % out_dir, "the apertures at a standstill — nothing outside")

	# Driven by hand rather than by begin(), so the frame is exactly line speed
	# and not whatever the curve happened to be at when the shutter fell.
	_set_rate(ride, 1.0, 3.1)
	for _i in 10:
		await physics_frame
	await _grab("%s/ride_02_windows_running.png" % out_dir, "the same frame at line speed — THE TEST")

	# ── BISECT, when nothing shows up outside ───
	# Two different failures look identical through a window: the plate is in
	# the wrong place or occluded, OR it is in the right place and the bar
	# maths never lights a pixel. Flooding the whole plate separates them — if
	# a solid glowing wall is still invisible it is position, not the shader.
	if args.has("--flood"):
		for p in ride._mats:
			p.set_shader_parameter(&"bar_width", 400.0)
			p.set_shader_parameter(&"gain", 6.0)
			p.set_shader_parameter(&"edge", 1.0)
		for _i in 10:
			await physics_frame
		await _grab("%s/ride_02b_flood.png" % out_dir, "every plate flooded — position test")
		# OUTSIDE THE HULL, with nothing between the camera and the plate. If
		# the flooded plate is visible HERE and not through a window, the plate
		# is fine and the window is what stops it.
		await _look(Vector3(10.0, 4.19, car_z), Vector3(19.7, 4.19, car_z))
		await _grab("%s/ride_02c_flood_outside.png" % out_dir, "the same plate from outside the train")
		await _look(Vector3(-4.0, eye, car_z), Vector3(4.5, eye + 0.4, car_z))
		for p in ride._mats:
			p.set_shader_parameter(&"bar_width", 0.9)
			p.set_shader_parameter(&"gain", 1.7)
			p.set_shader_parameter(&"edge", 0.55)

	# Half a bar along, to confirm the bars move rather than sit still.
	_set_rate(ride, 1.0, 7.1)
	for _i in 10:
		await physics_frame
	await _grab("%s/ride_03_windows_moved.png" % out_dir, "four metres later — the bars have moved")

	# And with the interior at its running level, which is what it looks like
	# in play: the inside dim, the outside the brightest thing.
	ride._set_lamp_level(ride.running_lamp_level)
	for _i in 10:
		await physics_frame
	await _grab("%s/ride_04_windows_dim.png" % out_dir, "lamps at the running level, as it plays")
	ride._set_lamp_level(1.0)
	_set_rate(ride, 0.0, 0.0)

	# ── 2. the lever ────────────────────────────
	if lever != null:
		var lp: Vector3 = lever.global_position
		# A RIG LIGHT. The ops car is dark on purpose — "low, dark, and empty.
		# The brightest thing is the projection" — which is right for the room
		# and useless for judging a small brass fitting in it. This is lighting
		# for the photograph only and no part of the feature.
		var key := OmniLight3D.new()
		root.add_child(key)
		key.global_position = lp + Vector3(-0.8, 0.9, -0.9)
		key.light_energy = 3.0
		key.omni_range = 4.0
		key.light_color = Color("F2D9A8")

		# Three states, same frame: dark with nothing queued, breathing once there
		# is somewhere to go, steady once the handle is over.
		# RIG LIGHT OFF for the first two. The whole point of the glow is that it
		# is the only lit thing in a dark car; photographing it under a key light
		# shows the brass, not the signal.
		key.light_energy = 0.0
		await _look(lp + Vector3(-1.5, 1.05, -1.9), lp + Vector3(0.0, 0.45, -0.35))
		await _grab("%s/ride_05a_lever_dark.png" % out_dir, "nothing queued — the lever is inert")
		var camp = root.get_tree().get_first_node_in_group(&"campaign")
		if camp != null:
			var opts: Array = camp.available_missions()
			if not opts.is_empty():
				camp.select_mission(opts[0].id)
				for _i in 50:
					await process_frame
				await _grab("%s/ride_05b_lever_ready.png" % out_dir, "an operation queued — the lever lights")
		key.light_energy = 3.0
		for _i in 5:
			await physics_frame
		await _grab("%s/ride_05_lever_stowed.png" % out_dir, "the handle stowed, close")
		# Pose and glow set directly, NOT through _on_interacted: that fires the
		# `thrown` signal, which starts the ride, opens the platform door and arms
		# the pad — and the door frames further down photograph it shut.
		lever.pose = lever.Pose.THROWN
		lever._swing_to(lever.thrown_degrees)
		lever._refresh_glow()
		for _i in 45:
			await process_frame
		await _grab("%s/ride_06_lever_thrown.png" % out_dir, "and thrown")
		# Wider, to judge it against the table it is bolted to. From above the
		# slab, because that is the eye line of somebody standing at it.
		key.light_energy = 5.0
		key.omni_range = 7.0
		await _look(lp + Vector3(-1.9, 0.75, -1.9), lp + Vector3(0.0, -0.05, 1.1))
		await _grab("%s/ride_07_lever_in_place.png" % out_dir, "the lever on the end of the table")
		key.queue_free()
	else:
		print("    no lever in the level")

	# ── 3. the door ─────────────────────────────
	if ride._leaf != null:
		var shut: Vector3 = ride._leaf_shut
		# Inboard of the opening, looking at it square.
		await _look(shut + Vector3(-5.0, 0.0, 0.0), shut)
		await _grab("%s/ride_08_door_shut.png" % out_dir, "the platform door, shut — the gate")
		ride._leaf.global_position = ride._leaf_open
		for _i in 10:
			await physics_frame
		await _grab("%s/ride_09_door_open.png" % out_dir, "and open, with the leaf in its pocket")
	else:
		print("    no door leaf was built")

	print("")
	quit(0)


## Drive the tunnel shader directly. The ride's own _physics_process is off
## unless a ride is running, so setting the uniforms here is not fighting it.
func _set_rate(ride, rate: float, scroll: float) -> void:
	for m in ride._mats:
		m.set_shader_parameter(&"rate", rate)
		m.set_shader_parameter(&"scroll", scroll)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	for _i in 20:
		await physics_frame


func _one(n: Node, script: Script):
	if n.get_script() == script:
		return n
	for c in n.get_children():
		var f = _one(c, script)
		if f != null:
			return f
	return null


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-32s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])


func _all_named(n: Node, prefix: String, out: Array = []) -> Array:
	if String(n.name).begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		_all_named(c, prefix, out)
	return out
