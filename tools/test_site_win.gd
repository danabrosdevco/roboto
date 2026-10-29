extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# TAKING THE BUNKER ACTUALLY ENDS THE OPERATION.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_site_win.gd
#
# §12.7 is "take the ground, stand down, go home", and the going-home half was
# never wired. The basin attack had its extraction objective removed when
# attack and defence were unified onto the same four cores, on the grounds that
# site_operation.gd wins at the bunker — which it does, but winning only
# emitted a signal. BunkerObjective ticked a line and the player was left
# standing in a finished mission.
#
# WORSE THAN "NO MARKER": LevelExit.requires_objectives_complete refuses to
# open while any required objective is outstanding, and §12.7 says explicitly
# you do not have to clear the cores to take the bunker. So an operation won
# the intended way walked you to a door that would not let you through.
#
# This asserts the whole chain on the real level: cores still hostile, bunker
# taken, stand-down run, and the player ends up at the exit with the required
# objectives satisfied.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_sitewin.json"
	Engine.max_fps = 60
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	cm.reset_campaign()

	var m = cm.get_mission(&"basin_1_anchor")
	_check("(setup) the basin attack exists", m != null)
	if m == null:
		_done()
		return
	cm.in_mission = false
	cm.debug_mission = m
	cm.select_mission(&"basin_1_anchor")
	await world.load_next_level(m.level_scene)
	# NO SECOND on_level_loaded(). World.load_next_level() ends by calling it
	# itself, so an explicit call here redeploys BOTH spawners in the same frame
	# as the first deploy — and tearing a robot down that few frames after it
	# was stood up leaves the engine something it only trips over in final
	# cleanup: every assertion printed PASS and the run still handed the shell
	# exit 139. H10, root-caused 2026-10-24: dropping this one line is the whole
	# fix. A 10-frame gap before the second call also cures it; one or two
	# frames do not. The call was redundant either way.
	for _i in 120:
		await physics_frame

	_check("the attack names no extraction objective", not _has_extraction(cm),
		"it has one, so this whole path is moot")

	var slice = _find(world.current_level, "BasinSlice")
	_check("(setup) the level carries a site slice", slice != null)
	if slice == null:
		_done()
		return
	var op = slice.get("operation")
	_check("(setup) ...which built an operation with a bunker",
		op != null and op.get("bunker") != null)
	if op == null or op.get("bunker") == null:
		_done()
		return

	# CORES STILL THEIRS, which is the case the design calls out and the one
	# that used to strand the player.
	var held := 0
	for c in op.cores:
		if c != null and c.is_held_by_player():
			held += 1
	_check("the cores are still theirs when the bunker is taken", held == 0,
		"%d of %d already held" % [held, op.cores.size()])

	var exit = _mission_exit()
	_check("(setup) the level has an exit to be sent to", exit != null)
	# CAMPAIGN'S OWN LOOKUP, not a reimplementation. is_class() only knows
	# engine classes, so a script class_name like Player answers false to it —
	# this test reported "the player is not in the tree" on a tree that had one.
	var player = cm._first_of_class(root, "Player")
	_check("(setup) the player is in the tree", player != null)
	if exit == null or player == null:
		_done()
		return
	var started: Vector3 = (player as Node3D).global_position
	var away: float = started.distance_to((exit as Node3D).global_position)
	_check("(setup) the player does not start at the exit", away > 5.0,
		"%.1f m away" % away)
	_check("(setup) ...and the exit is shut to begin with",
		exit.requires_objectives_complete,
		"it is already open, so unlocking it proves nothing")

	# TAKE THE BUNKER and let the stand-down run.
	op.bunker.start_held()
	op.stand_down_seconds = 0.5
	for _i in 240:
		await physics_frame

	_check("taking the bunker ends the operation", bool(op.get("_settled")),
		"the stand-down ran and nothing concluded")
	# THE WAY OUT IS OPENED, NOT TAKEN FOR YOU.
	#
	# The first cut teleported the squad into the exit. That took the walk out
	# of the player's hands at the one moment they have earned it, and it
	# depended on an Area3D producing body_entered for a teleported body, which
	# it does not reliably do — the squad arrived half a metre from an open door
	# and the operation never ended.
	_check("...and the way out is open", not exit.requires_objectives_complete,
		"the exit still demands every objective, which this win does not satisfy")
	_check("...and the player is left to walk it",
		(player as Node3D).global_position.distance_to(started) < 5.0,
		"the squad was moved %.1f m" % (player as Node3D).global_position.distance_to(started))
	_check("...and the operation is still running until they do", cm.in_mission,
		"the mission ended on its own, so the walk means nothing")

	# AND THE DOOR IS LIT, because an exit that has quietly become usable is one
	# the player has no reason to walk to.
	var lit := false
	for part in exit.live_parts:
		if part != null and is_instance_valid(part) and part.visible:
			lit = true
	_check("...and the gate is lit so they can see where to go", lit,
		"%d live part(s), none visible" % exit.live_parts.size())

	_done()




func _has_extraction(cm) -> bool:
	var m = cm.get_mission(&"basin_1_anchor")
	for id in m.active_objectives:
		if String(id).contains("extract"):
			return true
	return false


func _mission_exit():
	for n in _all(root):
		if n is LevelExit and not n.is_departure:
			return n
	return null



func _find(n: Node, named: String):
	if n == null:
		return null
	if n.name == named:
		return n
	for c in n.get_children():
		var h = _find(c, named)
		if h != null:
			return h
	return null


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _done() -> void:
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
