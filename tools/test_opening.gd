extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# WHAT A FRESH CAMPAIGN ASKS OF YOU, IN ORDER.
#
#   1. the depot      heal yourself, get your squadmate up, buy and fit a
#                     rifle, give two orders, choose an operation
#   2. CONTACT        solo, against a few. Eliminate and extract
#   3. FIRING LINE    with your squad, against four. Work a core, take the
#                     bunker, extract from it
#   4. the war        Hillfort opens, and so does free play in the Lab
#
# Each step has to be the ONLY thing available at the time, or the order is a
# suggestion rather than a sequence.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_opening.gd
# ─────────────────────────────────────────────

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 140:
		await physics_frame
	var cm = world.get_node("CampaignManager")
	var state = cm.state
	# The DEBUG switch opens the whole ladder and would hide every gate here.
	Settings.set_value("debug.unlock_all_missions", false)

	# ── 1 · the depot teaches, and ends at the table ──
	var ind := load("res://Campaign/induction.gd")
	_check("the induction ends by sending you to the operations table",
		FileAccess.file_exists("res://Campaign/induction.gd"))

	# ── 2 · only training is open ───────────────
	var open := _ids(cm.available_missions())
	_check("A FRESH CAMPAIGN OFFERS ONLY THE FIRST EXERCISE",
		open == ["arena_1_contact"], str(open))

	# CONTACT is solo, against a few.
	var a1 = cm.get_mission(&"arena_1_contact")
	_check("...and it is SOLO", a1.squad_size == 0, "squad_size %d" % a1.squad_size)
	_check("...against a few", _bodies(a1) <= 3, "%d hostiles" % _bodies(a1))
	_check("...eliminate and extract, nothing else",
		a1.active_objectives == ([&"proving_clear", &"proving_extract"] as Array[StringName]),
		str(a1.active_objectives))

	# ── 3 · clearing it opens the second ────────
	state.completed_missions.append(&"arena_1_contact")
	open = _ids(cm.available_missions())
	_check("clearing it opens the second exercise", open.has("arena_3_firing_line"),
		str(open))
	_check("...and the war is still shut", not open.has("hfw_1_fort"), str(open))

	var a3 = cm.get_mission(&"arena_3_firing_line")
	_check("the second brings your squad", a3.squad_size != 0,
		"squad_size %d" % a3.squad_size)
	_check("...against four", _bodies(a3) == 4, "%d hostiles" % _bodies(a3))
	# CORE, BUNKER, THEN OUT — and out is the BAY gate, not the blockhouse one.
	# The proving ground holds both extractions and the mission picks which; the
	# second exercise ends where the bunker is, rather than walking 46 m back
	# the way it came. See docs/briefs/SIM_ARENA_MODE.md.
	_check("...and it teaches the CORE and the BUNKER",
		a3.active_objectives.has(&"proving_capture")
		and a3.active_objectives.has(&"proving_bunker")
		and a3.active_objectives.has(&"proving_extract_bay"),
		str(a3.active_objectives))
	_check("...and it does NOT send you back to the blockhouse to leave",
		not a3.active_objectives.has(&"proving_extract"), str(a3.active_objectives))

	# ── 4 · then the war opens ──────────────────
	state.completed_missions.append(&"arena_3_firing_line")
	open = _ids(cm.available_missions())
	_check("CLEARING THE SECOND OPENS HILLFORT", open.has("hfw_1_fort"), str(open))
	_check("...and nothing deeper than that", not open.has("basin_1_anchor"), str(open))

	# ── two exercises, not three ────────────────
	var sims := 0
	for m in cm.missions:
		if m != null and m.sim:
			sims += 1
	_check("THERE ARE TWO EXERCISES, NOT THREE", sims == 2, "%d" % sims)
	_check("...and the retired one is out of the campaign",
		cm.get_mission(&"arena_5_proving") == null)

	# ── both are free, always ───────────────────
	var costly: Array = []
	for m in cm.missions:
		if m != null and m.sim and (m.reward_resources > 0 or m.compute_reward > 0
				or not m.repeatable):
			costly.append(String(m.id))
	_check("neither exercise costs or pays anything", costly.is_empty(), str(costly))

	# ── the arena is ONE entry on the board ─────
	var table = _find(root, "OpsTable")
	if table != null:
		var drawn := _ids(table._board_missions())
		var arena_pins: Array = []
		for id in drawn:
			if id.begins_with("arena_"):
				arena_pins.append(id)
		_check("THE EXERCISES ARE NOT SITES ON THE BOARD", arena_pins.is_empty(), str(arena_pins))
		_check("...the arena is one entry instead", table._has_training())
		_check("...and it sits off to one side of the war",
			table.SIM_PLACE != Vector2.ZERO, str(table.SIM_PLACE))
		# TAKEABLE sites are drawn larger — the board has no colour left.
		var f_open := {"deployable": true, "held": false, "under_attack": false}
		var f_held := {"deployable": true, "held": true, "under_attack": false}
		var f_shut := {"deployable": false, "held": false, "under_attack": false}
		_check("somewhere you can go reads as takeable", table._takeable(f_open))
		_check("...somewhere you already hold does not", not table._takeable(f_held))
		_check("...and neither does somewhere out of reach", not table._takeable(f_shut))

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _ids(missions: Array) -> Array:
	var out: Array = []
	for m in missions:
		if m != null:
			out.append(String(m.id))
	out.sort()
	return out


func _bodies(m) -> int:
	var n := 0
	for spec in m.enemy_force:
		if spec != null:
			n += spec.body_count()
	return n


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null
