extends SceneTree

# ─────────────────────────────────────────────
# ONE PIN PER PLACE, AND THE ARENA IS THE ONLY ONE YOU CAN ACT ON AT FIRST.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_ops_board.gd
#
# Four things reported off one screenshot of the board, all of them about what
# the table DRAWS rather than what the campaign knows:
#
#   1. Valley Basin had two markers stacked on one spot — the attack and its
#      defence, both keyed into LAYOUT at the same coordinates.
#   2. The arena's card ran off the bottom: three rows of zero and an
#      "ADVERSARY HELD" line, for a training facility with no Location.
#   3. The war was selectable before the two exercises were done.
#   4. Clicking the arena did nothing (that one is in ops_table_ui._queue).
#
# THE FACTS, NOT THE PROJECTION. refresh() needs a HoloBoard and a SubViewport;
# everything being asserted here is decided before any of that, in
# _board_missions, _facts_for and _training_done. So this seats the script on a
# bare node with a real campaign behind it and asks those directly.
# ─────────────────────────────────────────────

const _Table := preload("res://Env/world_objects/ops_table.gd")

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_board_test.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	# NEVER WRITE THE PLAYER'S CAMPAIGN.
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 150:
		await physics_frame
	var cm = world.get_node("CampaignManager")
	var state = cm.state
	_check("(setup) a campaign is running with a board", state != null and state.locations != null)
	if state == null or state.locations == null:
		_done()
		return
	# AND RE-READ THE STATE. reset_campaign() swaps in a NEW CampaignState, so
	# a reference taken before it points at an object nothing else reads any
	# more — clears written to it come back as zero everywhere that matters.
	cm.reset_campaign()
	state = cm.state

	var table := Node3D.new()
	table.set_script(_Table)
	table.Campaign = cm
	root.add_child(table)

	# ── 1 · ONE PIN PER PLACE ───────────────────
	var drawn: Array = table._board_missions()
	var ids: Array = drawn.map(func(m): return String(m.id))
	var defences: Array = []
	var sims: Array = []
	for m in cm.missions:
		if m == null:
			continue
		if m.defence:
			defences.append(String(m.id))
		elif m.sim:
			sims.append(String(m.id))
	_check("(setup) there is a defence to get wrong", not defences.is_empty())
	var dup := false
	for d in defences:
		if ids.has(d):
			dup = true
	_check("no defence gets a marker of its own", not dup,
		"board draws %s and the defences are %s" % [str(ids), str(defences)])
	_check("...and no exercise does either",
		sims.all(func(s): return not ids.has(s)), str(ids))
	_check("Valley Basin is on the board exactly once",
		ids.count("basin_1_anchor") == 1, str(ids))

	# ── 2 · THE WAR IS SHUT UNTIL TRAINING IS DONE ──
	_check("a fresh campaign has not finished training", not table._training_done())
	var hill = cm.get_mission(&"hillfort_1_relay")
	_check("(setup) the first real site exists", hill != null)
	if hill != null:
		var f: Dictionary = table._facts_for(hill)
		_check("...and it cannot be deployed to yet", not bool(f["deployable"]))
		_check("...and the card says why, rather than going quiet",
			bool(f["needs_training"]))

	# ── 3 · THE ARENA IS THE ONE THING TO DO ────
	# Built the way refresh() builds it; see the synthetic pin there.
	var sim_facts := {"sim_site": true, "name": "SIM ARENA",
		"training_next": not table._training_done()}
	_check("the arena is pointed at while training is unfinished",
		bool(sim_facts["training_next"]))
	var readout: String = table._readout_text(sim_facts)
	_check("...and the table does NOT call it adversary ground",
		not readout.contains("ADVERSARY"), readout.replace("\n", " / "))
	_check("...it says to start there", readout.contains("START HERE"),
		readout.replace("\n", " / "))

	# ── 4 · CLEAR THE EXERCISES AND THE WAR OPENS ──
	for s in sims:
		state.record_clear(StringName(s)) if state.has_method("record_clear") \
			else state.completed_missions.append(StringName(s))
	_check("training is finished once both exercises are run", table._training_done(),
		"clears: %s" % str(sims.map(func(s): return state.clears_of(StringName(s)))))
	if hill != null:
		var f2: Dictionary = table._facts_for(hill)
		_check("...and the first site is no longer held back by training",
			not bool(f2["needs_training"]))
	var done_facts: Dictionary = {"sim_site": true, "name": "SIM ARENA",
		"training_next": not table._training_done()}
	_check("...and the arena stops shouting once it is done",
		not table._readout_text(done_facts).contains("START HERE"))

	# ── 5 · A RAID IS ANSWERED FROM THE SITE'S OWN PIN ──
	var site = state.locations.for_mission(&"basin_1_anchor")
	_check("(setup) the basin resolves to a place", site != null)
	if site != null:
		var basin = cm.get_mission(&"basin_1_anchor")
		_check("no defence is offered while nothing is attacking",
			table._defence_waiting(site) == &"")
		state.under_attack = site.id
		_check("a raid in doubt offers the defence from the attack's pin",
			table._defence_waiting(site) == &"basin_2_defend",
			"got '%s'" % String(table._defence_waiting(site)))
		if basin != null:
			var bf: Dictionary = table._facts_for(basin)
			_check("...and it rides on the site's own facts",
				StringName(bf.get("defend_id", &"")) == &"basin_2_defend",
				str(bf.get("defend_id", &"")))
			_check("...which is also marked under attack", bool(bf["under_attack"]))
		# AND THE QUEUED RING LANDS ON THE SITE'S OWN PIN. HoloBoard.set_queued
		# draws nothing for an id it has no point for, so without this mapping
		# choosing DEFEND IT put the ring nowhere and you got no confirmation
		# of what you had just picked.
		table.facts[&"basin_1_anchor"] = table._facts_for(basin)
		_check("queueing the defence rings the basin's marker",
			table._pin_for(&"basin_2_defend") == &"basin_1_anchor",
			"got '%s'" % String(table._pin_for(&"basin_2_defend")))
		_check("...and an attack still rings its own",
			table._pin_for(&"basin_1_anchor") == &"basin_1_anchor")
		state.under_attack = &""

	_done()


func _done() -> void:
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
