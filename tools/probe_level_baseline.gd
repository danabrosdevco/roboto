extends SceneTree

# ─────────────────────────────────────────────
# WHAT DOES AN EMPTY QAMAREEN COST?
#
# tools/bench_qamareen.gd --bare strips the enemy force and still measures 5.60
# ms of physics CPU a frame — a third of a 16.6 ms budget spent before a single
# hostile exists. On a weak machine that is the floor nobody can play under, and
# it is paid whether the battle is 5v5 or 50v50.
#
# Nothing here is attributed by guesswork. It counts every node that has
# _physics_process ENABLED, grouped by script, because that is the set of things
# the engine will call back sixty times a second. A script with one instance and
# a script with four hundred look identical in a profiler flame graph taken at
# the wrong zoom; this says which is which.
#
# Jolt reports 0 active bodies and 0 collision pairs on this run, so whatever
# the 5.6 ms is, it is NOT simulation — it is callbacks.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_level_baseline.gd
# ─────────────────────────────────────────────

const MISSION := "mutaha_2_city"
const SETTLE := 420


func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


## Everything under `n`, with how it is scripted and whether it will be called
## back. `physics` counts only nodes where the callback is actually ON — a node
## that has overridden _physics_process and switched it off costs nothing, which
## is the whole point of the exercise.
func _census(n: Node, by_script: Dictionary, totals: Array) -> void:
	totals[0] += 1
	if n is Node3D or n is Node:
		if n.is_inside_tree() and n.is_physics_processing():
			totals[1] += 1
			var s: Script = n.get_script() as Script
			var key := "(no script) %s" % n.get_class()
			if s != null:
				key = s.resource_path.get_file()
			by_script[key] = int(by_script.get(key, 0)) + 1
		if n.is_inside_tree() and n.is_processing():
			totals[2] += 1
			var s2: Script = n.get_script() as Script
			var key2 := "_process: %s" % (s2.resource_path.get_file() if s2 != null else n.get_class())
			by_script[key2] = int(by_script.get(key2, 0)) + 1
	for c in n.get_children():
		_census(c, by_script, totals)


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame

	var cm: Node = world.get_node("CampaignManager")
	var mission = null
	for m in cm.missions:
		if m != null and str(m.id) == MISSION:
			mission = m
	if mission == null:
		printerr("probe_level_baseline: no mission '%s'." % MISSION)
		quit(1)
		return
	# Bare by default, like the bench: the garrison would drown everything the
	# level itself is doing. --full keeps it, to see what 66 squads add to
	# _process rather than to physics.
	var full := OS.get_cmdline_user_args().has("--full")
	if not full:
		mission.enemy_force.clear()
	cm.state.selected_mission_id = mission.id
	_find(root, "World").load_next_level(mission.level_scene, true)
	for _i in SETTLE:
		await physics_frame

	# --hush: switch _process OFF on the weapons and muzzle flashes of robots the
	# cull has already put to sleep, the way --freeze does for _physics_process.
	# Measures the win before anyone writes the real thing.
	if OS.get_cmdline_user_args().has("--hush"):
		var bots: Array = []
		_all_scripted(root, "Soldier", bots)
		_all_scripted(root, "Rover", bots)
		var hushed := 0
		for b in bots:
			if int(b.get("ai_state")) != 5:
				continue   # awake: its weapon has work to do
			hushed += _hush(b)
		print("  hushed _process on %d node(s) under culled robots" % hushed)
		for _i in 60:
			await physics_frame

	# --hush-squads: the 67 Squad objects, which tick in _process and are not
	# robots, so neither the cull nor --hush touches them.
	if OS.get_cmdline_user_args().has("--hush-squads"):
		var squads: Array = []
		_all_scripted(root, "Squad", squads)
		for s in squads:
			s.set_process(false)
		print("  hushed _process on %d squad(s)" % squads.size())
		for _i in 60:
			await physics_frame

	var by_script: Dictionary = {}
	var totals := [0, 0, 0]
	_census(root, by_script, totals)

	# Let it run a while with nothing happening, then read the steady state.
	for _i in 300:
		await physics_frame

	print("")
	print("QAMAREEN, %s" % ("FULL GARRISON" if full else "NO ENEMY FORCE"))
	print("  physics CPU            %7.3f ms per frame" % (
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))
	print("  process CPU            %7.3f ms per frame" % (
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	print("  nodes in the tree      %7d" % totals[0])
	print("  with _physics_process  %7d" % totals[1])
	print("  with _process          %7d" % totals[2])
	print("  active physics objects %7d" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	print("  collision pairs        %7d" % Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	print("  physics islands        %7d" % Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
	print("  orphan nodes           %7d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("")
	print("  WHO IS BEING CALLED BACK, by script:")
	var rows: Array = []
	for k in by_script:
		rows.append([int(by_script[k]), str(k)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		if int(r[0]) < 2 and rows.size() > 24:
			continue   # the long tail of singletons says nothing useful
		print("    %5d  %s" % [r[0], r[1]])
	quit(0)


func _all_scripted(n: Node, cls: String, out: Array) -> void:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		out.append(n)
	for c in n.get_children():
		_all_scripted(c, cls, out)


## Silences every _process under one robot, and says how many it silenced.
func _hush(n: Node) -> int:
	var count := 0
	if n.is_inside_tree() and n.is_processing():
		n.set_process(false)
		count += 1
	for c in n.get_children():
		count += _hush(c)
	return count
