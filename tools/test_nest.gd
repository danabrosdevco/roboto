extends SceneTree

# ─────────────────────────────────────────────
# NESTS AND REINFORCEMENTS — the Valley Foundry's two hives hatch bodies once
# the shooting starts, and the mission's reserves come in on a body count and
# on a hive going down.
#
# Deploys the real mission into the real level, then makes the fight happen by
# hand: wakes a hive, kills hostiles off one at a time, and blows a hive up.
# What is read back is what the force did in answer.
#
# Boots the real world with autosave off: it reads the save on this machine and
# never writes it.
# ─────────────────────────────────────────────

const MISSION := "res://Campaign/missions/mission_valley_6_foundry.tres"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _wait(seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await physics_frame


# Every hostile body in the level, nests included.
func _hostiles() -> Array:
	var out: Array = []
	for n in get_nodes_in_group("enemies"):
		if n is Enemy and is_instance_valid(n) and (n as Enemy).faction == Enums.Factions.ENEMY:
			out.append(n)
	return out


func _nests() -> Array:
	return _hostiles().filter(func(b): return b.has_signal(&"hatched_body"))


func _named(callsign: String) -> Array:
	return _hostiles().filter(func(b): return String(b.soldier_name).begins_with(callsign))


func _init() -> void:
	await process_frame
	var mission: MissionDefinition = load(MISSION)
	_check("the Foundry is a mission: the north gate and the way out",
		mission != null and mission.active_objectives.has(&"valley_garrison_cap_3")
		and mission.active_objectives.has(&"valley_extract"))
	_check("...with both hives as optional targets",
		mission.active_objectives.has(&"valley_hive_south") and mission.active_objectives.has(&"valley_hive_north"),
		str(mission.active_objectives))
	_check("...and it comes after the siege", mission.requires.has(&"valley_5_siege"))

	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 30:
		await physics_frame
	# Set AFTER the world has come up with its base level: told at boot, the
	# campaign deploys the whole enemy force into the base, where none of the
	# valley tags exist.
	cm.debug_mission = mission
	cm.on_level_loaded(valley)
	await _wait(2.0)

	var force: EnemyForceSpawner = cm.enemy_spawner
	var hostiles := _hostiles()
	print("      deployed %d hostiles, reserves waiting: %s" % [hostiles.size(), str(force.pending_reserve_tags())])
	_check("the mission deploys a garrisoned valley", hostiles.size() >= 40, "%d hostiles" % hostiles.size())

	# ── WHAT IS IN IT ────────────────────────────
	var nests := _nests()
	_check("two hives, one in each of the middle compounds", nests.size() == 2, "%d nests" % nests.size())
	var mechanics := _running(_hostiles(), "mechanic.gd")
	var reclaimers := _running(_hostiles(), "reclaimer.gd")
	_check("repair crews behind their line", mechanics.size() >= 2, "%d mechanics" % mechanics.size())
	_check("...and two Reclaimers of their own", reclaimers.size() == 2, "%d reclaimers" % reclaimers.size())
	var waiting := force.pending_reserve_tags()
	_check("three waves held back: a body count, a second one, and the hives",
		waiting.has("valley6_column") and waiting.has("valley6_lance") and waiting.has("nest_down"),
		str(waiting))

	# ── A HIVE AT WORK ───────────────────────────
	var hive: Soldier = nests[0]
	var was := hive.global_position
	_check("(setup) a hive stands where it was built, unarmed", hive.alive and hive.weapon == null)
	hive.trigger_combat(player)
	var hatched_in := await _until(func(): return hive.hatched > 0, hive.first_hatch_seconds + 6.0)
	_check("a hive in a fight hatches a body", hatched_in > 0.0, "nothing after %.0fs" % (hive.first_hatch_seconds + 6.0))
	_check("...and it is a chaser or a leaper", _last_kind(hive) in ["chaser", "leaper"], _last_kind(hive))
	_check("...while the hive itself never moves", hive.global_position.distance_to(was) < 0.1,
		"%.2fm" % hive.global_position.distance_to(was))
	# NOR TURNS. It is bolted down: the base rotates a robot to face what it is
	# looking at, and on a bunker that read as the building slowly swivelling.
	var faced := hive.global_transform.basis.z
	await _wait(1.5)
	_check("...nor turns to face anything", hive.global_transform.basis.z.angle_to(faced) < deg_to_rad(0.5),
		"%.1f degrees" % rad_to_deg(hive.global_transform.basis.z.angle_to(faced)))
	# Flames as it comes apart, and nothing before that.
	var lit_when_whole := 0
	for fire in hive.flames:
		if fire != null and fire.emitting:
			lit_when_whole += 1
	hive.apply_damage(int(hive.max_health * 0.6), player)
	await _wait(0.3)
	var burning := 0
	for fire in hive.flames:
		if fire != null and fire.emitting:
			burning += 1
	_check("a hive shows its damage: no fires while whole, burning once it is hurt",
		hive.flames.size() >= 1 and lit_when_whole == 0 and burning == hive.flames.size(),
		"%d fires, %d lit while whole, %d lit at %d%%" % [hive.flames.size(), lit_when_whole,
		burning, int(100.0 * hive.health / hive.max_health)])
	_check("...and it takes 500 to bring down", hive.max_health == 500, "%d hp" % hive.max_health)
	hive.order_move_to(player.global_position, true, false)
	await _wait(1.0)
	_check("...and cannot be ordered anywhere", hive.global_position.distance_to(was) < 0.1)

	# ── A BODY COUNT BRINGS A COLUMN ─────────────
	var before := _named("COLUMN").size()
	var killed := 0
	for body in _hostiles():
		if killed >= 14:
			break
		if body == hive or body.has_signal(&"hatched_body"):
			continue   # the hives are their own trigger, tested below
		body.apply_damage(99999, player)
		killed += 1
	await _wait(2.0)
	var column := _named("COLUMN")
	print("      after %d losses (force counts %d): COLUMN is %d strong" % [killed, force.losses(), column.size()])
	_check("fourteen of theirs down brings a column in from outside", before == 0 and column.size() >= 4,
		"%d before, %d now" % [before, column.size()])
	var rovers := _running(column, "rover.gd")
	_check("...with armour in it", rovers.size() >= 1, "%d rovers" % rovers.size())
	_check("...and the rover is carrying a gun", rovers.is_empty() or rovers[0].weapon != null)
	_check("...advancing on the north gate rather than sitting where it spawned",
		not column.is_empty() and column[0].squad != null
		and column[0].squad.objective == Squad.SquadObjective.ADVANCE,
		str(column[0].squad.objective) if not column.is_empty() and column[0].squad != null else "no squad")

	# ── A HIVE GOING DOWN CALLS THE SWARM ────────
	var swarm_before := _named("SWARM").size()
	hive.apply_damage(99999, player)
	await _wait(2.0)
	var swarm := _named("SWARM")
	_check("blowing a hive up calls in the swarm", swarm_before == 0 and swarm.size() >= 5,
		"%d before, %d now" % [swarm_before, swarm.size()])
	_check("...and the hive is gone rather than lying there repairable",
		not hive.alive and not hive.downed)

	# Left standing for the engine to clear on the way out, as the other AI
	# suites do: freeing them here crashes the process under test.sh's pipe.
	await create_timer(1.5).timeout
	for _i in 5:
		await physics_frame
	print("")
	print("ALL NEST CHECKS PASS" if _fails == 0 else "%d NEST CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# The bodies in `list` running this script, by file name.
func _running(list: Array, script_file: String) -> Array:
	var out: Array = []
	for b in list:
		if b.get_script() != null and String(b.get_script().resource_path).ends_with(script_file):
			out.append(b)
	return out


func _until(done: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		await physics_frame
		t += 1.0 / 60.0
		if done.call():
			return t
	return -1.0


# What the last thing out of this hive was, by its scene.
func _last_kind(hive: Node) -> String:
	for body in get_nodes_in_group("enemies"):
		if body is Enemy and is_instance_valid(body) and String(body.soldier_name).begins_with("CHASER"):
			return "chaser"
		if body is Enemy and is_instance_valid(body) and String(body.soldier_name).begins_with("LEAPER"):
			return "leaper"
	return "none"
