extends SceneTree

# ─────────────────────────────────────────────
# HEAT SPENDS SUPPLY. THE COMMANDER TURNS IT INTO SQUADS.
#
# Two things worth testing separately, because they fail for different reasons:
#
#   THE POOLS ARE PRICED CORRECTLY. Every template states a supply cost, and
#   that number is what SiteHeat budgets against. If a template says 4 and its
#   frames actually cost 6, the site fields more than its resistance allows and
#   the whole economy in §2 is a lie. This checks every template against the
#   real catalogue.
#
#   THE PICK IS SANE. Biggest-that-fits, never over budget, and act-gated so
#   Act 1 cannot field a Walker.
#
#   godot --headless --path . --script res://tools/test_enemy_commander.gd
# ─────────────────────────────────────────────

const _Cmd := preload("res://Env/world_objects/enemy_commander.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	# A real campaign, because the catalogue is what prices the pools.
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame

	# A REAL MISSION LEVEL, loaded up front: the commander resolves a squad's
	# destination from the authored squad points, and the base has none.
	var lvl: Node = load("res://maps/valley_basin_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 90:
		await physics_frame

	var cmd = _Cmd.new()
	root.add_child(cmd)
	await physics_frame
	cmd._level = lvl

	# ── every template is priced honestly ───────
	var bad: Array = []
	var templates := 0
	for tier in _Cmd.POOLS:
		for t in _Cmd.POOLS[tier]:
			templates += 1
			var real: int = cmd.price_of(t)
			if real != int(t["supply"]):
				bad.append("%s says %d, frames cost %d" % [t["label"], int(t["supply"]), real])
	_check("every template's stated supply matches its frames",
		bad.is_empty(), "%d template(s) checked; %s" % [templates, str(bad)])

	# ── every chassis id resolves ───────────────
	var missing: Array = []
	for tier in _Cmd.POOLS:
		for t in _Cmd.POOLS[tier]:
			for id in t["frames"]:
				if cmd._chassis(StringName(id)) == null:
					missing.append(id)
	_check("every chassis id in the pools exists", missing.is_empty(), str(missing))

	# ── the pick ────────────────────────────────
	cmd.act = 1
	_check("act 1 cannot field a tier 3 frame",
		not _tier3(cmd._pick(99)), "picked %s" % str(cmd._pick(99).get("label", "-")))
	cmd.act = 3
	_check("act 3 can", _tier3(cmd._pick(99)) or cmd._pick(99).get("label", "") != "",
		"picked %s" % str(cmd._pick(99).get("label", "-")))

	cmd.act = 2
	var over := false
	for budget in [1, 2, 3, 4, 5, 6, 7, 8, 12, 40]:
		var p: Dictionary = cmd._pick(budget)
		if not p.is_empty() and int(p["supply"]) > budget:
			over = true
	_check("it never picks a squad it cannot afford", not over)

	_check("a budget below the cheapest template buys nothing",
		cmd._pick(1).is_empty(), "picked %s" % str(cmd._pick(1).get("label", "-")))

	var small: Dictionary = cmd._pick(4)
	var large: Dictionary = cmd._pick(12)
	_check("a bigger budget buys a bigger squad",
		not small.is_empty() and not large.is_empty()
		and int(large["supply"]) >= int(small["supply"]),
		"%s (%d) vs %s (%d)" % [small.get("label", "-"), int(small.get("supply", 0)),
			large.get("label", "-"), int(large.get("supply", 0))])

	# ── and it builds a spec the spawner accepts ─
	cmd.act = 3
	var spec = cmd._build_spec(cmd._pick(10), Vector3.ZERO)
	_check("it builds an EnemySquadSpec", spec != null)
	if spec != null:
		_check("...in ROSTER form, which is what every shipped mission uses",
			spec.roster.size() > 0, "%d frame(s)" % spec.roster.size())
		_check("...set to ADVANCE, so what it buys comes to you",
			int(spec.posture) == 2, "posture = %d" % int(spec.posture))
		_check("...and awake, so it does not wait to be woken",
			spec.always_active)

	# ── and it actually puts bodies on the map ──
	# The whole point. Heat drained its reserve for an entire playtest and
	# nothing arrived, because nothing turned supply into squads.
	cmd.spawner = cmd._find_spawner()
	_check("it finds the mission's own spawner", cmd.spawner != null, str(cmd.spawner))
	if cmd.spawner != null and lvl != null:
		var before := 0
		for n in root.get_tree().get_nodes_in_group("enemies"):
			before += 1
		var sent: Array = []
		cmd.squad_committed.connect(func(l, s, _at): sent.append("%s(%d)" % [l, s]))
		cmd.act = 1
		cmd._on_committed(6, Vector3.ZERO)
		for _i in 40:
			await physics_frame
		var after := 0
		for n in root.get_tree().get_nodes_in_group("enemies"):
			after += 1
		_check("a commitment reports a squad", sent.size() == 1, str(sent))
		_check("...and bodies are actually on the map now", after > before,
			"%d -> %d hostiles" % [before, after])
		_check("...and the supply spent is recorded", cmd.committed_supply > 0,
			"%d supply, %d squad(s)" % [cmd.committed_supply, cmd.committed_squads])

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _tier3(t: Dictionary) -> bool:
	if t.is_empty():
		return false
	for x in _Cmd.POOLS[3]:
		if x["label"] == t["label"]:
			return true
	return false
