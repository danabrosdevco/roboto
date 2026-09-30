extends SceneTree

# ─────────────────────────────────────────────
# WHAT EACH EXPENSIVE AI DECISION COSTS, ON ITS OWN.
#
# bench_ai.gd says the frame is spiky. This says which call is doing it. It
# stands up a real fight, grabs a robot that is actually in combat, and calls
# the suspects directly a few hundred times each with a clock around them.
#
# Calling them out of band like this is exactly what makes the number useful:
# no timers, no culling, no "only 11 of them ran this frame" — just the cost of
# one decision, which is the thing that has to come down.
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const REPS := 200

var _level: Node = null
var _mgr: Node = null
var _player: Node3D = null


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _time(label: String, subject: Object, fn: Callable) -> void:
	# One untimed call first: the first run of anything pays for lazily built
	# state and would be reported as the cost of every run.
	fn.call()
	var t0 := Time.get_ticks_usec()
	for _i in REPS:
		fn.call()
	var us := float(Time.get_ticks_usec() - t0) / float(REPS)
	print("  %-34s %8.3f ms/call" % [label, us / 1000.0])


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var count: int = int(args[0]) if args.size() > 0 else 80

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 20:
		await physics_frame

	var space := _player.get_world_3d().direct_space_state
	var ground := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	_player.global_position = (ground.call(300.0, 200.0) as Vector3) + Vector3.UP
	for _i in 20:
		await physics_frame

	seed(20260930)
	var half: int = count / 2
	var subjects: Array = []
	for i in count:
		var enemy_side: bool = i < half
		var body: Node = load(RIFLE).instantiate()
		body.faction = Enums.Factions.ENEMY if enemy_side else Enums.Factions.PLAYER
		body.always_active = true
		_level.add_child(body)
		var x: float = 300.0 + randf_range(-30.0, 30.0)
		var z: float = (170.0 if enemy_side else 230.0) + randf_range(-14.0, 14.0)
		(body as Node3D).global_position = (ground.call(x, z) as Vector3) + Vector3.UP
		if _mgr != null and _mgr.has_method("register_enemy"):
			_mgr.register_enemy(body)
		if enemy_side:
			subjects.append(body)
	for _i in 180:
		await physics_frame

	# Somebody actually in the fight — an idle robot takes the cheap branch of
	# everything here and would report that all of it is free.
	var who: Node = null
	for s in subjects:
		if is_instance_valid(s) and s.alive and s.combat_target != null:
			who = s
			break
	if who == null:
		who = subjects[0]
	print("")
	print("AI CALL COSTS — %d robots, %d in all_ai, subject in combat: %s" % [
		count, _mgr.all_ai.size(), str(who.combat_target != null)])

	_time("_nearest_hostile (cached/frame)", who, func(): who._nearest_hostile())
	_time("AIManager.get_nearest_hostile", who, func(): _mgr.get_nearest_hostile(who))
	_time("AIManager.hostiles_for", who, func(): _mgr.hostiles_for(who.faction))
	_time("reconsider_target", who, func(): who.reconsider_target())
	_time("roll_combat_action", who, func(): who.roll_combat_action())
	if who.has_method("find_best_cover_point"):
		_time("find_best_cover_point", who, func(): who.find_best_cover_point())
	_time("find_advance_position", who, func(): who.find_advance_position())
	_time("is_path_clear (one ray)", who, func():
		who.is_path_clear(who.global_position + Vector3.UP * 0.8,
			who.global_position + Vector3(20, 1, 20)))
	quit(0)
