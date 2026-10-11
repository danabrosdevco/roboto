extends SceneTree

# ─────────────────────────────────────────────
# THE ADVANCING PATH, WHICH IS THE EXPENSIVE ONE.
#
# bench_ai_calls.gd reports find_advance_target at 0.002 ms and the in-editor
# profiler reports 3.14 ms for the same function. Both are right: the bench's
# robots are already inside engage_standoff, so the call early-returns at
# "if dist <= standoff" and never reaches the loop underneath. A reserve squad
# that has just spawned and is walking in is the other branch — three
# map_get_closest_point queries and three is_path_clear rays, every call.
#
# So this measures it with a target far enough away that the loop runs, on a map
# big enough for the navigation query to cost what it costs. Three Rivers is
# 1.3 km across; the valley is not, and that difference is most of the gap.
#
#   godot --headless --path . --script res://tools/bench_advance.gd -- [map] [reps]
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _level: Node = null
var _player: Node3D = null
var _mgr: Node = null


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


## Times `reps` calls back to back. Anything that answers to a PER-FRAME budget
## will exhaust it after the first few and report the cheap refusal path for the
## rest, so use _time_framed for those.
func _time(label: String, reps: int, fn: Callable) -> float:
	fn.call()                                  # one untimed: lazily built state
	var t0 := Time.get_ticks_usec()
	for _i in reps:
		fn.call()
	var ms := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0
	print("  %-40s %8.3f ms/call" % [label, ms])
	return ms


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var map: String = str(args[0]) if args.size() > 0 else "pittsburgh"
	var reps: int = int(args[1]) if args.size() > 1 else 150

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/%s_level.tscn" % map).instantiate())
	for _i in 40:
		await physics_frame

	var nav_map: RID = _player.get_world_3d().navigation_map
	var space := _player.get_world_3d().direct_space_state

	# Two robots on the navmesh, FAR APART — one advancing on the other.
	var a_at := NavigationServer3D.map_get_closest_point(nav_map, Vector3(-280, 0, -150))
	var b_at := NavigationServer3D.map_get_closest_point(nav_map, Vector3(350, 0, 200))
	var mover: Node3D = load(RIFLE).instantiate()
	var mark: Node3D = load(RIFLE).instantiate()
	mover.faction = Enums.Factions.ENEMY
	mark.faction = Enums.Factions.PLAYER
	mover.always_active = true
	mark.always_active = true
	_level.add_child(mover)
	_level.add_child(mark)
	mover.global_position = a_at + Vector3.UP
	mark.global_position = b_at + Vector3.UP
	if _mgr != null and _mgr.has_method("register_enemy"):
		_mgr.register_enemy(mover)
		_mgr.register_enemy(mark)
	for _i in 60:
		await physics_frame

	mover.combat_target = mark
	var dist: float = mover.global_position.distance_to(mark.global_position)
	print("")
	print("ADVANCE BENCH — %s, target %.0f m away (standoff %.0f m)" % [
		map, dist, mover._max_range() * mover.engage_standoff])
	print("  (a distance this far out is the branch that does the work)")
	print("")

	await _time_framed("find_advance_target  [far, budget fresh]", mini(reps, 60), func(): mover.find_advance_target())
	_time("find_advance_target  [far, back to back]", reps, func(): mover.find_advance_target())
	# The two things that loop is made of, on their own.
	var probe := mover.global_position + Vector3(12, 0, 12)
	_time("  NavigationServer3D.map_get_closest_point", reps, func():
		NavigationServer3D.map_get_closest_point(nav_map, probe))
	_time("  is_path_clear (one ray, far)", reps, func():
		mover.is_path_clear(mover.global_position + Vector3.UP * 0.8, mark.global_position, mark))
	_time("find_reposition_target", reps, func(): mover.find_reposition_target())
	if mover.has_method("find_best_cover_point"):
		_time("find_best_cover_point", reps, func(): mover.find_best_cover_point())
	_time("reconsider_movement", reps, func(): mover.reconsider_movement())
	_time("roll_combat_action", reps, func(): mover.roll_combat_action())

	# And the same call once the robot is CLOSE, to show the two branches apart.
	mover.global_position = mark.global_position + Vector3(6, 0, 6)
	for _i in 10:
		await physics_frame
	print("")
	_time("find_advance_target  [close: early-returns]", reps, func(): mover.find_advance_target())
	quit(0)


## One call per physics frame, so a frame-budgeted query gets a fresh allowance
## every time. This is what one robot's decision actually costs; _time() with a
## budgeted call measures the budget, not the work.
func _time_framed(label: String, reps: int, fn: Callable) -> void:
	fn.call()
	var total := 0
	for _i in reps:
		await physics_frame
		var t0 := Time.get_ticks_usec()
		fn.call()
		total += Time.get_ticks_usec() - t0
	print("  %-40s %8.3f ms/call   [one per frame]" % [label, float(total) / float(reps) / 1000.0])
