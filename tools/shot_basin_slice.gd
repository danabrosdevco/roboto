extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE SLICE ON VALLEY BASIN.
#
# The first playtest reported "exactly the same" — and it was, because every
# system was running and none of it was visible. This answers the only question
# that matters before the next attempt: CAN YOU SEE IT.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_basin_slice.gd -- <out dir>
#
# HEADFUL, because this grabs the window's viewport; the headless dummy
# renderer has no image to give. It does not resize the window.
#
# A camera of its own, never the player — the player is a CharacterBody3D and
# falls back to the floor across the frames before each grab, so a view set by
# moving it silently ends up at standing height wherever it was put.
# ─────────────────────────────────────────────

var _cam: Camera3D = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var lvl: Node = load("res://maps/valley_basin_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 120:
		await physics_frame

	var slice := lvl.get_node_or_null(^"BasinSlice")
	if slice == null:
		printerr("no BasinSlice in the level")
		quit(1)
		return
	print("    %d cores, bunker = %s" % [slice.cores.size(), str(slice.operation.bunker != null)])

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	# ── the cores ───────────────────────────────
	# Eye height, at the distance you would first see one from.
	for i in slice.cores.size():
		var core = slice.cores[i]
		var host: Node3D = core.get_parent()
		var at: Vector3 = host.global_position
		await _look(at + Vector3(-16.0, 7.0, -16.0), at + Vector3(0.0, 2.5, 0.0))
		await _grab("%s/slice_core_%d_%s.png" % [out_dir, i, host.name], "%s — hostile" % host.name)

	# ── one core, taken ─────────────────────────
	var first = slice.cores[0]
	var fhost: Node3D = first.get_parent()
	var fat: Vector3 = fhost.global_position
	await _look(fat + Vector3(-11.0, 5.0, -11.0), fat + Vector3(0.0, 2.5, 0.0))
	await _grab("%s/slice_core_before.png" % out_dir, "close, before")
	# Through the real path, so what is photographed is the anchor that lands
	# rather than a flag being flipped.
	first._call_tap()
	for _i in 400:
		await physics_frame
		if first.is_held_by_player():
			break
	for _i in 20:
		await physics_frame
	await _grab("%s/slice_core_held.png" % out_dir, "the same core, held — anchor landed")

	# ── the tap ─────────────────────────────────
	# Called directly: the channel needs a player in range and this scene has no
	# World, so what is photographed here is the tap arriving, not the F press
	# that calls it.
	var second = slice.cores[1]
	var shost: Node3D = second.get_parent()
	var sat: Vector3 = shost.global_position
	await _look(sat + Vector3(-13.0, 8.0, -13.0), sat + Vector3(0.0, 6.0, 0.0))
	second._call_tap()
	for _i in 45:
		await physics_frame
	await _grab("%s/slice_tap_inbound.png" % out_dir, "the tap, coming down")
	for _i in 140:
		await physics_frame
	await _grab("%s/slice_tap_docked.png" % out_dir, "docked — the core is held from here")

	# ── a channel in progress ───────────────────
	# THE ONE THING THE EARLIER SHOTS COULD NOT SHOW. Capturing was photographed
	# only at its two ends — hostile, then held — so the ten seconds in between,
	# which is where most of a capture is actually spent, had no picture at all.
	#
	# The progress signal is driven by hand. A real channel needs a player
	# inside the interact volume and this scene has no World, so what is
	# photographed is the light the fraction produces, which is the part being
	# checked; the fraction itself comes from HoldableCore in play.
	var third = slice.cores[2]
	var thost: Node3D = third.get_parent()
	var tat: Vector3 = thost.global_position
	await _look(tat + Vector3(-13.0, 6.0, -13.0), tat + Vector3(0.0, 4.0, 0.0))
	await _grab("%s/slice_channel_00.png" % out_dir, "before the channel — nothing lit")
	for step in [[0.35, "35"], [0.85, "85"]]:
		third.channel_progress.emit(float(step[0]))
		third.beat_reached.emit(1 if float(step[0]) < 0.8 else 2)
		for _i in 6:
			await physics_frame
		await _grab("%s/slice_channel_%s.png" % [out_dir, String(step[1])],
			"channel at %d%% — the light climbs the shaft" % int(float(step[0]) * 100.0))
	third.channel_interrupted.emit()
	for _i in 30:
		await physics_frame
	await _grab("%s/slice_channel_broken.png" % out_dir, "interrupted — the light falls back")

	# ── the bunker ──────────────────────────────
	var bunker = slice.get_node_or_null(^"BasinBunker")
	if bunker != null:
		var bat: Vector3 = bunker.global_position
		await _look(bat + Vector3(-26.0, 11.0, -22.0), bat + Vector3(0.0, 2.0, 0.0))
		await _grab("%s/slice_bunker_far.png" % out_dir, "the bunker, from the approach")
		await _look(bat + Vector3(-9.0, 4.0, -9.0), bat + Vector3(0.0, 2.0, 0.0))
		await _grab("%s/slice_bunker_near.png" % out_dir, "the bunker, close")
		# The tap arriving at the bunker — the thing the playtest could not see.
		await _look(bat + Vector3(-17.0, 7.0, -14.0), bat + Vector3(2.0, 6.0, 1.0))
		var bh = slice.operation.bunker
		bh._call_tap()
		for _i in 55:
			await physics_frame
		await _grab("%s/slice_bunker_tap_in.png" % out_dir, "tap inbound at the bunker")
		for _i in 220:
			await physics_frame
		await _look(bat + Vector3(-9.0, 4.5, -9.0), bat + Vector3(0.0, 4.0, 0.0))
		await _grab("%s/slice_bunker_tap_docked.png" % out_dir, "docked on the post — bunker held")

	print("")
	quit(0)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	for _i in 20:
		await physics_frame


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-34s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])
