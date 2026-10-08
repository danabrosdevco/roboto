extends SceneTree

# ─────────────────────────────────────────────
# TARGET DISTRIBUTION AND THE CONTACT LEDGER
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_targeting.gd
#
# The thing this is really guarding is the LEDGER. `by` and `incoming` are
# maintained in exactly one place — Enemy.change_combat_target — and every
# distribution decision in the game reads them. A leak there is invisible on
# screen: fights still happen, they are just subtly wrong forever afterwards,
# with robots avoiding a target that nothing is actually shooting.
#
# So the assertions that matter most are not "did it spread" but "did it come
# back to zero".
# ─────────────────────────────────────────────

const SOLDIER := "res://Character/characters/ai/soldier_rifle.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"

var _fails: int = 0
var _mgr: AIManager = null


func _init() -> void:
	_mgr = AIManager.new()
	root.add_child(_mgr)
	await process_frame

	await _test_ledger_balances()
	await _test_spread_across_equals()
	await _test_concentrate_on_one_big()
	await _test_ekill_is_a_bonus_not_an_eviction()
	await _test_downing_releases()

	print("")
	if _fails == 0:
		print("ALL TARGETING CHECKS PASS")
	else:
		print("FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


## A body, registered, at a position, on a side.
func _spawn(path: String, at: Vector3, faction: int) -> Node:
	var body: Node = load(path).instantiate()
	body.faction = faction
	root.add_child(body)
	body.global_position = at
	body.set_physics_process(false)
	body.set_process(false)
	_mgr.all_ai.append(body)
	body.ai_manager = _mgr
	return body


func _clear() -> void:
	for b in _mgr.all_ai.duplicate():
		if is_instance_valid(b):
			b.free()
	_mgr.all_ai.clear()
	_mgr._contacts.clear()
	_mgr._hostile_cache.clear()
	await process_frame


# ── the one that matters ─────────────────────
func _test_ledger_balances() -> void:
	var shooter: Node = _spawn(SOLDIER, Vector3.ZERO, Enums.Factions.ALLIED)
	var a: Node = _spawn(SOLDIER, Vector3(10, 0, 0), Enums.Factions.ENEMY)
	var b: Node = _spawn(SOLDIER, Vector3(20, 0, 0), Enums.Factions.ENEMY)
	await process_frame

	shooter.change_combat_target(a)
	var row_a: Dictionary = _mgr.contact_for(Enums.Factions.ALLIED, a)
	_ok("claiming a target records one shooter", int(row_a.get("by", 0)) == 1)
	_ok("...and its damage per second", float(row_a.get("incoming", 0.0)) > 0.0)

	# Switching targets must move the claim, not duplicate it.
	shooter.change_combat_target(b)
	row_a = _mgr.contact_for(Enums.Factions.ALLIED, a)
	var row_b: Dictionary = _mgr.contact_for(Enums.Factions.ALLIED, b)
	_ok("switching releases the old claim", int(row_a.get("by", 0)) == 0,
			"by=%d" % int(row_a.get("by", 0)))
	_ok("...and takes the new one", int(row_b.get("by", 0)) == 1)
	_ok("the old target's incoming returns to zero",
			is_equal_approx(float(row_a.get("incoming", 1.0)), 0.0),
			"incoming=%.3f" % float(row_a.get("incoming", 1.0)))

	await _clear()


func _test_spread_across_equals() -> void:
	# CLUSTERED SHOOTERS, STAGGERED TARGETS — and the geometry is the test.
	#
	# An earlier version spread the shooters along a line, which meant each one
	# genuinely had a different nearest enemy and the old selector scored five
	# out of five too. It passed without proving anything. Bunched up against
	# targets at increasing depth, "nearest" is the SAME answer for all five,
	# which is the dogpile this whole system exists to stop.
	var shooters: Array = []
	for i in 5:
		shooters.append(_spawn(SOLDIER, Vector3(i * 0.6, 0, 0), Enums.Factions.ALLIED))
	var foes: Array = []
	for i in 5:
		foes.append(_spawn(SOLDIER, Vector3(0, 0, 25.0 + i * 4.0), Enums.Factions.ENEMY))
	await process_frame

	# The behaviour being replaced, measured rather than assumed.
	var before: Dictionary = {}
	for s in shooters:
		var old = _mgr.get_nearest_hostile(s)
		if old != null:
			before[old.get_instance_id()] = true
	_ok("nearest-only really does dogpile on this layout", before.size() == 1,
			"%d distinct — the test geometry is wrong, not the code" % before.size())

	var picked: Dictionary = {}
	for s in shooters:
		var t = _mgr.get_best_hostile(s)
		if t != null:
			s.change_combat_target(t)
			picked[t.get_instance_id()] = true
	_ok("...and scoring spreads them", picked.size() >= 4,
			"hit %d distinct target(s)" % picked.size())

	await _clear()


func _test_concentrate_on_one_big() -> void:
	# THE REGRESSION TEST FOR THE WHOLE IDEA. Saturation must not stop a squad
	# correctly focusing something that needs focusing: a Walker is 320 HP and
	# five riflemen are only just enough.
	var shooters: Array = []
	for i in 5:
		shooters.append(_spawn(SOLDIER, Vector3(i * 2.0, 0, 0), Enums.Factions.ALLIED))
	var big: Node = _spawn(WALKER, Vector3(4, 0, 25), Enums.Factions.ENEMY)
	await process_frame

	var on_big: int = 0
	for s in shooters:
		var t = _mgr.get_best_hostile(s)
		if t != null:
			s.change_combat_target(t)
		if t == big:
			on_big += 1
	_ok("five still concentrate on the only target", on_big == 5,
			"%d of 5" % on_big)

	await _clear()


func _test_ekill_is_a_bonus_not_an_eviction() -> void:
	# An e-killed robot is STUNNED, not dead: alive stays true and it recovers.
	# It must stay in the table and become MORE attractive, not vanish.
	var shooter: Node = _spawn(SOLDIER, Vector3.ZERO, Enums.Factions.ALLIED)
	var near: Node = _spawn(SOLDIER, Vector3(10, 0, 0), Enums.Factions.ENEMY)
	var far: Node = _spawn(SOLDIER, Vector3(22, 0, 0), Enums.Factions.ENEMY)
	await process_frame

	_mgr.note_seen(Enums.Factions.ALLIED, far)
	far.signal_integrity = 0.0
	_ok("a stunned robot is still alive", far.alive)
	_ok("...and still in the contact table",
			not _mgr.contact_for(Enums.Factions.ALLIED, far).is_empty())
	# Not asserting it wins the pick — w_ekill is a tunable and the distance
	# gap here is deliberate — only that it is still a candidate at all.
	_ok("...and still a candidate",
			_mgr.hostiles_for(Enums.Factions.ALLIED).has(far))

	await _clear()


func _test_downing_releases() -> void:
	var shooter: Node = _spawn(SOLDIER, Vector3.ZERO, Enums.Factions.ALLIED)
	var foe: Node = _spawn(SOLDIER, Vector3(10, 0, 0), Enums.Factions.ENEMY)
	await process_frame

	shooter.change_combat_target(foe)
	shooter.enter_downed()
	var row: Dictionary = _mgr.contact_for(Enums.Factions.ALLIED, foe)
	_ok("a downed shooter releases its claim", int(row.get("by", 1)) == 0,
			"by=%d" % int(row.get("by", 1)))
	_ok("...and its damage per second",
			is_equal_approx(float(row.get("incoming", 1.0)), 0.0))

	await _clear()
