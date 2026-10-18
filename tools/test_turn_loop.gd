extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE TURN LOOP, END TO END.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 6.1 and 6.2. EnemyTurn has its own suite
# for the rules; this is about them actually happening in a campaign — the
# wiring that makes the board come alive rather than the arithmetic behind it.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_turn_loop.gd
# ─────────────────────────────────────────────

const _Turn := preload("res://Campaign/enemy_turn.gd")

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

	# ── a defence is not a mission you can just pick ──
	var defence_open := func() -> bool:
		for m in cm.available_missions():
			if m != null and m.defence:
				return true
		return false
	_check("a defence is NOT offered when nothing is under attack", not defence_open.call())
	state.under_attack = &"valley_basin"
	_check("...and IS offered when its site is", defence_open.call())
	state.under_attack = &""

	# ── a turn is an operation ──────────────────
	state.earned = 100000
	# ENOUGH COMPUTE THAT RAIDS LAND IN DOUBT. A raid is 18 supply at act 1 and
	# the doubt band is 0.8-1.25, so a garrison of 8 + 12 sits at 1.11 — which
	# is the only way the DECLINE path below is reachable at all.
	state.compute_earned = 12
	state.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	var before_turn: int = state.turn
	cm.select_mission(&"basin_1_anchor")
	cm.current_mission = cm.get_mission(&"basin_1_anchor")
	var r: Dictionary = cm.extract(true)
	_check("clearing an operation advances the turn", state.turn == before_turn + 1,
		"%d -> %d" % [before_turn, state.turn])
	_check("...and the other side gets a say", r.has("enemy"),
		str(r.get("enemy", {}).get("outcome", "-")))

	# ── the enemy eventually moves ──────────────
	# Run operations until a turn it acts on, and check something happened.
	var moved := false
	var doubted := false
	for i in 12:
		cm.current_mission = cm.get_mission(&"basin_1_anchor")
		var rr: Dictionary = cm.extract(true)
		var e: Dictionary = rr.get("enemy", {})
		if int(e.get("outcome", 0)) == _Turn.Outcome.LOST:
			moved = true
		if int(e.get("outcome", 0)) == _Turn.Outcome.IN_DOUBT:
			doubted = true
			_check("an in-doubt raid marks the site as under attack",
				state.under_attack == e["site"],
				"%s vs %s" % [state.under_attack, e["site"]])
			break
		if moved:
			break
	_check("THE OTHER SIDE ACTUALLY PLAYS", moved or doubted,
		"lost=%s doubt=%s after 12 operations" % [str(moved), str(doubted)])

	# ── declining settles it ────────────────────
	if doubted:
		var pending: StringName = state.under_attack
		_check("(setup) a raid is pending", pending != &"")
		# Do something ELSE. That is how you decline.
		cm.current_mission = cm.get_mission(&"basin_1_anchor")
		var r3: Dictionary = cm.extract(true)
		_check("doing something else DECLINES the defence",
			r3.has("declined_site") and String(r3["declined_site"]) == String(pending),
			str(r3.get("declined_site", "-")))
		_check("...and the raid is no longer pending", state.under_attack != pending
			or state.under_attack == &"")

	# ── A SIM ARENA IS A FREE ACTION (Phase 6.4) ─
	# No turn, no pay, no ground, and the other side does not get a move.
	# Practising must never cost you the campaign.
	var t_before: int = state.turn
	var money_before: int = state.available()
	var compute_before: int = state.compute_earned
	state.under_attack = &""
	cm.current_mission = cm.get_mission(&"arena_1_contact")
	var sim_r: Dictionary = cm.extract(true)
	_check("a sim run is marked as one", bool(sim_r.get("sim", false)))
	_check("NO TURN PASSES", state.turn == t_before, "%d -> %d" % [t_before, state.turn])
	_check("...nothing is paid", state.available() == money_before
		and state.compute_earned == compute_before,
		"%d res, %d compute" % [state.available() - money_before,
			state.compute_earned - compute_before])
	_check("...and the other side does not get a move", not sim_r.has("enemy"))
	_check("...and it can be run again", cm.get_mission(&"arena_1_contact").repeatable)
	_check("...but it still counts for the ladder, which runs through it",
		state.completed_missions.has(&"arena_1_contact"))

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
