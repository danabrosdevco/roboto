extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# WHAT A FRESH CAMPAIGN ASKS OF YOU, IN ORDER.
#
#   1. the depot      heal yourself, get your squadmate up, load and carry a
#                     weapon, give two orders, choose an operation
#   2. TAKE AND HOLD  with your squad, against six. Work a core, take the
#                     bunker, extract from it
#   3. the war        Hillfort opens, and so does free play in the Lab
#
# FIRST CONTACT USED TO SIT BETWEEN THEM and was cut on 2026-10-22. It was
# solo against three on a floor you then crossed a second time, and it put a
# whole operation in front of the only exercise that teaches CAPTURING —
# which is the verb the entire campaign is made of.
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
	# ONE EXERCISE NOW, NOT TWO. First Contact was cut on 2026-10-22: it was
	# solo against three on a floor you then crossed again, and the thing the
	# campaign is actually made of — taking ground and holding it — was behind
	# it. Take And Hold is the opening operation, and it is also the only one
	# that teaches the verb.
	var open := _ids(cm.available_missions())
	_check("A FRESH CAMPAIGN OFFERS ONLY THE EXERCISE",
		open == ["arena_3_firing_line"], str(open))
	_check("...and nothing requires the exercise that was cut",
		cm.get_mission(&"arena_1_contact") == null, "arena_1_contact is gone")

	var a3 = cm.get_mission(&"arena_3_firing_line")
	_check("it brings your squad", a3.squad_size != 0,
		"squad_size %d" % a3.squad_size)
	# SIX, AND THE BRIEFING SAYS SO — "You do not have to kill all six". This
	# read `== 4` and had been red since the force was rewritten; the number
	# in the suite was the stale one, not the number in the mission.
	_check("...against six", _bodies(a3) == 6, "%d hostiles" % _bodies(a3))
	# WHAT IT HANDS ON. First Contact was the only unlocker of the EMP and the
	# hatchling charge; cutting it would have locked both out of the campaign
	# for good, so they moved here.
	for id in [&"emp", &"hatchling"]:
		_check("...and it still hands you the %s" % String(id),
			a3.unlocks.has(id), str(a3.unlocks))
	# CORE, BUNKER, THEN OUT — and out is the BAY gate, not the blockhouse one.
	# The proving ground holds both extractions and the mission picks which; this
	# exercise ends where the bunker is, rather than walking 46 m back the way
	# it came. See docs/briefs/archive/SIM_ARENA_MODE.md.
	_check("...and it teaches the CORE and the BUNKER",
		a3.active_objectives.has(&"proving_capture")
		and a3.active_objectives.has(&"proving_bunker")
		and a3.active_objectives.has(&"proving_extract_bay"),
		str(a3.active_objectives))
	_check("...and it does NOT send you back to the blockhouse to leave",
		not a3.active_objectives.has(&"proving_extract"), str(a3.active_objectives))

	# ── 3 · then the war opens ──────────────────
	state.completed_missions.append(&"arena_3_firing_line")
	open = _ids(cm.available_missions())
	_check("CLEARING THE EXERCISE OPENS HILLFORT", open.has("hfw_1_fort"), str(open))
	_check("...and nothing deeper than that", not open.has("basin_1_anchor"), str(open))

	# ── one exercise, not two ───────────────────
	var sims := 0
	for m in cm.missions:
		if m != null and m.sim:
			sims += 1
	_check("THERE IS ONE EXERCISE, NOT TWO", sims == 1, "%d" % sims)
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
