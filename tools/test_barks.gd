extends SceneTree

# ─────────────────────────────────────────────
# BARKS — the squad says the right thing at the right moment.
#
# "LOST CONTACT, SEARCHING" used to be barked whenever a robot's target
# vanished — including when a squadmate had just KILLED it. The fix separates
# "the target went down" from "the target slipped out of sight".
#
# This is fiddly to test honestly, and the first three attempts passed for the
# wrong reason, so the traps are written down:
#   * A robot with no squad and no faction on its Bark node lands on the
#     HOSTILE channel, which the comms log never carries — nothing is heard at
#     all, and "no SEARCH bark" passes vacuously. Robots here are in a
#     player-commandable squad.
#   * Entering combat barks CONTACT, which starts 6s speaker / 3s squad
#     cooldowns. A SEARCH requested inside them is silently dropped — vacuous
#     again. BarkDirector.reset() clears the cooldowns before each moment.
#   * If any other hostile exists, the robot just switches targets and never
#     reaches the search path. The kill scenario runs with nobody else hostile,
#     and asserts it really left COMBAT.
#   * The CONTROL proves barks are audible in this setup at all: a live target
#     moved out of sight still gets its SEARCH line.
# ─────────────────────────────────────────────

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


func _heard_search(heard: Array) -> bool:
	for h in heard:
		if h[1] == BarkSet.Line.SEARCH:
			return true
	return false


func _init() -> void:
	await process_frame
	# Autosave off: this reads the save on this machine but must never write it.
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var mgr := _find(root, "AIManager")
	var heard: Array = []
	# Kept, so it can be unregistered before quit. BarkDirector is static: a
	# lambda left in its list outlives this script at shutdown and the engine
	# segfaults tearing it down — every check passed and the suite still failed.
	var listener := func(who: String, line: int, _ctx: String) -> void: heard.append([who, line])
	BarkDirector.add_listener(listener)

	var spawn := func(faction: int, at: Vector3) -> Soldier:
		var s: Soldier = load("res://Character/characters/ai/soldier_shotgun.tscn").instantiate()
		s.faction = faction
		s.always_active = true
		level.add_child(s)
		s.global_position = at
		mgr.register_enemy(s)
		return s
	var make_squad := func(members: Array, sign: String) -> Squad:
		var q := Squad.new()
		q.callsign = sign
		q.player_commandable = true
		var typed: Array[Soldier] = []
		for m in members:
			typed.append(m)
		q.squad_members = typed
		level.add_child(q)
		return q
	var base: Vector3 = player.global_position + Vector3(0, 0, 12)

	# ── THE BUG: the target is killed by someone else ──
	var ally: Soldier = spawn.call(Enums.Factions.PLAYER, base + Vector3(4, 0, -8))
	var foe: Soldier = spawn.call(Enums.Factions.ENEMY, base + Vector3(10, 0, 0))
	make_squad.call([ally], "BRAVO")
	for _i in 10:
		await physics_frame
	ally.trigger_combat(foe)
	ally._remember_last_seen(foe.global_position + Vector3(0, 0, 5))
	for _i in 30:
		await physics_frame
	BarkDirector.reset()
	heard.clear()
	foe.apply_damage(9999, player)
	ally.reconsider_target()
	var state_after: int = ally.ai_state
	for _i in 30:
		await physics_frame
	_check("(setup) the target-down path really ran — nothing else hostile, so it left COMBAT",
		state_after != Enemy.AIState.COMBAT, "state=%s" % Enemy.AIState.keys()[state_after])
	_check("a squad robot whose target is killed does NOT bark 'lost contact, searching'",
		not _heard_search(heard), str(heard))

	# ── CONTROL: a live target that slipped out of sight ──
	var watcher: Soldier = spawn.call(Enums.Factions.PLAYER, base + Vector3(0, 0, -4))
	var ghost: Soldier = spawn.call(Enums.Factions.ENEMY, base + Vector3(-6, 0, 0))
	make_squad.call([watcher], "ALPHA")
	for _i in 10:
		await physics_frame
	watcher.trigger_combat(ghost)
	watcher._remember_last_seen(ghost.global_position)
	ghost.global_position += Vector3(0, 0, 300)
	for _i in 30:
		await physics_frame
	BarkDirector.reset()
	heard.clear()
	watcher._enter_search(false)
	for _i in 30:
		await physics_frame
	_check("(control) a squad robot that lost sight of a live target still barks SEARCH",
		_heard_search(heard), str(heard))

	BarkDirector.remove_listener(listener)
	BarkDirector.reset()
	print("")
	print("ALL BARK CHECKS PASS" if _fails == 0 else "%d BARK CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
