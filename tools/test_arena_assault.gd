extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE TWO SIM ARENA EXERCISES ARE ASSAULTS, AND EACH LEAVES BY ITS OWN DOOR.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_arena_assault.gd
#
# The proving ground holds BOTH extractions: the blockhouse gate at z 37 for
# the first exercise, which only has to clear the floor, and the bay gate at
# z 86 for the second, which works a core and takes the bunker behind the
# blockhouse and should not then walk 46 m back the way it came.
#
# WHY THIS NEEDS A RUNNING LEVEL AND NOT PACKED DATA. MissionObjective._ready
# frees the objective whose id the operation left out, and LevelExit._ready
# frees the gate paired with it. Neither happens in a .tscn — packed, the level
# has two of everything, which is what tools/test_mission_objectives.gd sees
# and correctly accepts. The failure this guards against is the opposite of
# missing: TWO live extraction gates, either of which ends the run, in the one
# level that exists to teach the player what extraction is.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_arena_test.json"
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	# NEVER THE PLAYER'S SAVE. Every suite does this; see the note in test.sh.
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	cm.reset_campaign()

	# ── 1 · CLEAR AND GO HOME ───────────────────
	# AN OPERATION THAT IS NOT IN THE CAMPAIGN. First Contact was cut on
	# 2026-10-22, so the only thing left that leaves by the BLOCKHOUSE is
	# arena_5_proving, which is on disk and not in Campaign.missions. It is
	# loaded straight off the file rather than asked for by id — because the
	# rule under test is the LEVEL's, not the campaign's: the proving ground
	# holds both gates and whichever operation runs must light exactly one.
	# Drop this half and the two-live-gates failure stops being tested at all.
	# ADOPTED INTO THE CAMPAIGN FIRST, and that is not a formality:
	# MissionObjective._ready asks Campaign.is_objective_active(), which reads
	# the CURRENT mission — and select_mission() on an operation the campaign
	# has never heard of leaves that null, so nothing is pruned and all five
	# objectives stay up. Skipping this step produced, exactly, the two live
	# extraction gates this suite exists to catch.
	var floor_op = load("res://Campaign/missions/mission_arena_5_proving.tres")
	if not cm.missions.has(floor_op):
		cm.missions.append(floor_op)
	await _deploy_def(cm, world, floor_op)
	var one := _objective_ids(cm)
	_check("an operation that only clears the floor asks for that", one.has(&"proving_clear"), str(one))
	_check("...and leaves by the blockhouse", one.has(&"proving_extract"), str(one))
	_check("...and is not asked to capture anything",
		not one.has(&"proving_capture") and not one.has(&"proving_bunker"), str(one))
	_check("...and the bay gate is not in the level at all",
		not one.has(&"proving_extract_bay"), str(one))
	_check("ONE live way out, at the blockhouse", _exit_zs(world) == [37.0],
		"gates at z %s" % str(_exit_zs(world)))

	# ── 2 · TAKE GROUND ─────────────────────────
	await _deploy(cm, world, &"arena_3_firing_line")
	var two := _objective_ids(cm)
	_check("the second works a core", two.has(&"proving_capture"), str(two))
	_check("...then takes the bunker", two.has(&"proving_bunker"), str(two))
	_check("...and leaves from the bay", two.has(&"proving_extract_bay"), str(two))
	_check("...not from the blockhouse it came through",
		not two.has(&"proving_extract"), str(two))
	_check("ONE live way out, in the bay", _exit_zs(world) == [86.0],
		"gates at z %s" % str(_exit_zs(world)))

	# THE ORDER IS THE LESSON: core, then bunker, then out. Each waits on the
	# one before it, so the HUD asks for one thing at a time.
	var core = _objective(cm, &"proving_capture")
	var bunker = _objective(cm, &"proving_bunker")
	var out = _objective(cm, &"proving_extract_bay")
	_check("(setup) all three are in the tree",
		core != null and bunker != null and out != null)
	if core != null and bunker != null and out != null:
		_check("the core is live from the start", core.active)
		_check("...the bunker waits on the core", not bunker.active)
		_check("...and the way out waits on the bunker", not out.active)
		_check("the bunker's prerequisite IS the core",
			bunker.prerequisites.size() == 1 and bunker.prerequisites[0] == core)
		_check("...and the gate's is the bunker",
			out.prerequisites.size() == 1 and out.prerequisites[0] == bunker)

		# AND THE ORDER IS ENFORCED, not merely displayed. HoldableCore
		# completes its objective on capture without consulting `active`, so
		# the bunker is shut — layer 0, invisible to the interact ray — until
		# the core is done. Without this you could walk past the core, press F
		# on the bunker and tick a line the HUD had never shown.
		# FOUND ANYWHERE UNDER IT, not as a direct child. The arena raises real
		# art now (2026-10-16) and the prefab carries its own Interactible
		# several nodes down, so a direct-child lookup returned null for a
		# terminal that is present and working.
		var b_inter = _find_interactible(bunker)
		var c_inter = _find_interactible(core)
		_check("(setup) both captures built a terminal",
			b_inter != null and c_inter != null)
		if b_inter != null and c_inter != null:
			_check("the core can be worked straight away", c_inter.collision_layer == 3,
				"layer %d" % c_inter.collision_layer)
			_check("...and the bunker cannot be touched yet", b_inter.collision_layer == 0,
				"layer %d" % b_inter.collision_layer)
			core.complete()
			await process_frame
			_check("taking the core opens the bunker", b_inter.collision_layer == 3,
				"layer %d" % b_inter.collision_layer)
			_check("...and the bunker is now the live objective", bunker.active)

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## Put the squad on the proving ground for one operation.
##
## THE DIRECT-LAUNCH PATH, not the train. select_mission only chooses; it is
## begin_deploy() that sets in_mission, and that is driven by the departure
## ride. Campaign.on_level_loaded adopts `debug_mission` precisely so a tool
## can skip the base flow — and in_mission has to be cleared first or the
## second deployment of a run is still reported as the first one, which is how
## this suite first failed.
func _deploy(cm, world, id: StringName) -> void:
	var m = cm.get_mission(id)
	if m == null:
		_check("(setup) %s exists" % String(id), false)
		return
	await _deploy_def(cm, world, m)


## The same, for an operation that is not in Campaign.missions — see the note
## on the first section.
func _deploy_def(cm, world, m) -> void:
	if m == null:
		_check("(setup) the operation loaded", false)
		return
	cm.in_mission = false
	cm.debug_mission = m
	cm.select_mission(m.id)
	await world.load_next_level(m.level_scene)
	# NO SECOND on_level_loaded(). World.load_next_level() ends by calling it
	# itself, so an explicit call here redeploys BOTH spawners in the same frame
	# as the first deploy — and tearing a robot down that few frames after it
	# was stood up leaves the engine something it only trips over in final
	# cleanup: every assertion printed PASS and the run still handed the shell
	# exit 139. H10, root-caused 2026-10-24: dropping this one line is the whole
	# fix. A 10-frame gap before the second call also cures it; one or two
	# frames do not. The call was redundant either way.
	for _i in 60:
		await physics_frame

## The ids the tracker actually ended up with — what survived the prune.
func _objective_ids(cm) -> Array:
	var out := []
	for o in cm.objectives.objectives():
		if o != null and is_instance_valid(o):
			out.append(o.id)
	return out


func _objective(cm, id: StringName):
	for o in cm.objectives.objectives():
		if o != null and is_instance_valid(o) and o.id == id:
			return o
	return null


## Every gate that would take you off the map, by its z, sorted. A departure is
## the train at base and is not one.
func _exit_zs(world) -> Array:
	var out := []
	for e in world.get_tree().get_nodes_in_group("levelexit"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if e.get("is_departure"):
			continue
		out.append(snappedf(e.global_position.z, 0.5))
	out.sort()
	return out


## The Interactible under a capture, wherever the art happens to put it.
func _find_interactible(n: Node):
	if n == null:
		return null
	if n is Interactible:
		return n
	for c in n.get_children():
		var f = _find_interactible(c)
		if f != null:
			return f
	return null
