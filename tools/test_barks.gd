extends SceneTree
# BUCKET: frames

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
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
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

	_test_no_repeat_across_the_seam()

	print("")
	print("ALL BARK CHECKS PASS" if _fails == 0 else "%d BARK CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# ─────────────────────────────────────────────
# THE SHUFFLE BAG NEVER PLAYS THE SAME CLIP TWICE RUNNING (Backlog K14).
#
# Clips are drawn with pop_back(), so within one bag every index appears
# exactly once and a repeat is impossible. The ONLY place two identical clips
# can land back to back is the seam between one bag and the next — which is
# precisely what the seam guard exists to prevent, and precisely what it used
# to cause: it tested `bag[0]` and then moved the front to the BACK, straight
# into the next draw. A guaranteed repeat whenever it fired, and 2/n across a
# reshuffle instead of 1/n.
#
# SEEDED, so a failure is reproducible rather than a thing that happens on
# some runs. Many reshuffles rather than one, because the bug is probabilistic
# at ~2/4 per seam here — one seam would pass half the time with the bug still
# in, which is the kind of test that is worse than none.
# ─────────────────────────────────────────────
func _test_no_repeat_across_the_seam() -> void:
	seed(20261026)
	var b := Bark.new()
	var clips: Array[AudioStream] = []
	for i in 4:
		clips.append(AudioStreamWAV.new())
	b.bark_clips = clips
	var line: int = BarkSet.Line.HURT

	var draws: Array[int] = []
	var seams := 0
	var last_bag_size := -1
	for i in 400:
		var clip := b._next_clip(line)
		if clip == null:
			break
		draws.append(clips.find(clip))
		# A bag that has just been refilled is the seam; count them so the
		# check below cannot pass by never reaching one.
		var size: int = (b._bags.get(line, []) as Array).size()
		if size > last_bag_size and i > 0:
			seams += 1
		last_bag_size = size

	var repeat_at := -1
	for i in range(1, draws.size()):
		if draws[i] == draws[i - 1]:
			repeat_at = i
			break
	_check("(setup) the bag reshuffled enough times to be worth testing",
		seams >= 50 and draws.size() == 400, "%d seams, %d draws" % [seams, draws.size()])
	_check("the shuffle bag never plays the same clip twice running",
		repeat_at < 0,
		"clip %d repeated at draw %d" % [draws[repeat_at] if repeat_at >= 0 else -1, repeat_at])
	b.free()
