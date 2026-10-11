extends SceneTree

# ─────────────────────────────────────────────
# THE OPERATIONS TABLE, ON REAL CAMPAIGN DATA.
#
# Not synthetic sites: a real OpsTable, which finds the CampaignManager for
# itself, reads Campaign.missions, lays the twelve of them out from the
# requires DAG and prices each garrison. The printed table is as much the
# point as the photograph — a board that draws beautifully and reports the
# wrong resistance is worse than no board.
#
# Shot in the BASE, not a mission level: it is where the table goes, and an
# additive projection reads without overdriving in an interior.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_ops_table.gd -- <out dir> [--clear-some]
# ─────────────────────────────────────────────

const TABLE := "res://Env/world_objects/ops_table.gd"

## A CAMERA OF ITS OWN, rather than aiming the player.
##
## Every attempt to frame this by setting player.global_position failed
## silently: the player is a CharacterBody3D and falls back to the floor
## across the physics frames before each capture, so the view ended up at
## standing height wherever it was put. Measured: a readout placed on the
## table projected to screen (-254, 742) on a 1152x648 shot, with the camera
## effectively sitting on the board.
##
## A plain Camera3D made current has no body, no gravity and no opinions.
## tools/mockup_shots.gd already works this way.
var _shot_cam: Camera3D = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var player: Node3D = world.player
	var level: Node = player.get_parent()
	var campaign = world.get_node("CampaignManager")

	# --clear-some: pretend a few early ops are done, so the board has all
	# three states on it at once instead of a wall of identical locked grey.
	if args.has("--clear-some"):
		for id in [&"arena_1_contact", &"arena_3_firing_line", &"arena_5_proving"]:
			if not campaign.state.completed_missions.has(id):
				campaign.state.completed_missions.append(id)
			campaign.state.record_clear(id)

	var table = load(TABLE).new()
	level.add_child(table)
	# ─────────────────────────────────────────────
	# THE TABLE MOVES, NOT THE CAMERA.
	#
	# Every attempt to frame this by setting player.global_position failed,
	# and silently: the player is a CharacterBody3D, so across the twenty
	# physics frames before each grab it simply FALLS BACK TO THE FLOOR. The
	# camera ended up at standing height every time regardless of where it
	# was put, which is why the readout kept landing off the bottom of frame
	# — measured at screen (-254, 742) on a 1152x648 shot.
	#
	# So the table is placed relative to where the player actually stands,
	# at the height a table would be, and nothing moves the player at all.
	# That is also the only honest view of this thing: what you see standing
	# at it.
	# ─────────────────────────────────────────────
	# 1.6 m, which is standing at the EDGE of a metre-wide table rather than
	# over its middle. At 0.85 the board was effectively underfoot: a 60
	# degree look-down, and the near margin where the readout sits fell below
	# the bottom of the frame.
	table.global_position = player.global_position + _forward(player) * 1.6 \
		+ Vector3(0.0, -0.35, 0.0)
	for _i in 30:
		await physics_frame

	# ── the numbers ─────────────────────────────
	print("")
	print("    %-24s %-10s %7s %7s %10s %7s" % ["SITE", "STATE", "COMPUTE", "RES", "RESIST", "BODIES"])
	var drawn := 0
	for m in campaign.missions:
		if m == null:
			continue
		var f: Dictionary = table.facts.get(m.id, {})
		if f.is_empty():
			print("    %-24s  NO FACTS" % String(m.id))
			continue
		drawn += 1
		var state := "locked" if f["locked"] else ("cleared" if f["cleared"] else "open")
		print("    %-24s %-10s %7d %7d %10d %7d" % [
			String(m.id).substr(0, 24), state, f["compute"], f["resources"],
			f["resistance"], f["bodies"]])
	print("")
	print("    %d sites drawn, %d borders" % [drawn, table.ADJACENCY.size()])

	# ── the picture ─────────────────────────────
	_shot_cam = Camera3D.new()
	root.add_child(_shot_cam)
	_shot_cam.global_position = table.global_position + Vector3(0.0, 0.50, 0.66)
	_shot_cam.look_at(table.global_position + Vector3(0.0, 0.02, 0.0), Vector3.UP)
	_shot_cam.make_current()
	for _i in 20:
		await physics_frame
	await _grab("%s/ops_01_board.png" % out_dir, "the board, twelve real sites")

	_shot_cam.global_position = table.global_position + Vector3(0.0, 0.40, 0.52)
	_shot_cam.look_at(table.global_position + Vector3(0.0, 0.02, 0.02), Vector3.UP)
	for _i in 20:
		await physics_frame
	await _grab("%s/ops_02_close.png" % out_dir, "close, for the landmark icons")

	# A site hovered, so the readout can be judged.
	table.show_readout(&"basin_1_anchor")
	for _i in 10:
		await physics_frame
	var ro = null
	for c in table.get_children():
		if c is Label3D:
			ro = c
	if ro == null:
		print("    READOUT: no Label3D was created at all")
	else:
		var cam := root.get_camera_3d()
		print("    READOUT vis=%s  local=%s  global=%s  px=%.5f" % [str(ro.visible), str(ro.position), str(ro.global_position), ro.pixel_size])
		print("    READOUT text=%s" % ro.text.replace("
", " | "))
		if cam != null:
			print("    camera at %s  behind=%s  screen=%s" % [str(cam.global_position), str(cam.is_position_behind(ro.global_position)), str(cam.unproject_position(ro.global_position))])
	await _grab("%s/ops_03_hover.png" % out_dir, "Valley Basin hovered — yields and resistance")

	print("")
	quit(0)


func _edge_count(campaign) -> int:
	var n := 0
	for m in campaign.missions:
		if m != null:
			n += m.requires.size()
	return n


func _forward(n: Node3D) -> Vector3:
	var f := -n.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-24s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])
