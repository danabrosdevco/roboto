extends SceneTree

# ─────────────────────────────────────────────
# WHAT DOES SNAPPING ACTUALLY COST, IN A REAL FRAME?
#
# map_get_closest_point is 295 us a call on Qamareen (tools/bench_nav_chunking.gd).
# That is the price of ONE. It says nothing about the bill, because the bill is
# calls-per-frame times price, and the calls are spread across nine sites with a
# budget already throttling two of them.
#
# Enemy already instruments its own: `_snap_spent_us` is microseconds spent this
# physics frame and `_snap_refused` counts the ones the budget turned away. Both
# reset per frame, so this reads them at the end of every frame and totals them.
#
# WHAT THIS DOES NOT SEE. Only Enemy._snap_to_nav and Enemy.snap_on_map are
# counted. The calls in mechanic.gd, reclaimer.gd, enemy_nest.gd, squad.gd,
# enemy_force_spawner.gd and ground_snap.gd go through the server directly and
# are invisible here — so every figure below is a FLOOR, not a total. A low
# reading means "cheap in Enemy", not "cheap in the game".
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_snap_cost.gd
# ─────────────────────────────────────────────

const MISSION := "mutaha_2_city"
const FRAMES := 600


func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	# Headless runs _process flat out, which starves physics and makes every
	# number measured beside it a measurement of that instead.
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
		printerr("probe_snap_cost: no mission '%s'." % MISSION)
		quit(1)
		return
	cm.state.selected_mission_id = mission.id
	_find(root, "World").load_next_level(mission.level_scene, true)
	for _i in 420:
		await physics_frame

	var spent := 0
	var refused_before: int = Enemy._snap_refused
	var busiest := 0
	var frames_with_any := 0
	for _i in FRAMES:
		await physics_frame
		var us: int = Enemy._snap_spent_us
		spent += us
		busiest = maxi(busiest, us)
		if us > 0:
			frames_with_any += 1
	var refused: int = Enemy._snap_refused - refused_before

	var per_frame := float(spent) / float(FRAMES)
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("")
	print("SNAP COST — Enemy only, over %d physics frames" % FRAMES)
	print("  spent on snapping        %8.3f ms per frame (avg)" % (per_frame / 1000.0))
	print("  busiest single frame     %8.3f ms" % (float(busiest) / 1000.0))
	print("  frames that snapped at all %6d of %d" % [frames_with_any, FRAMES])
	print("  refused for budget       %8d" % refused)
	print("  physics CPU              %8.3f ms per frame" % physics_ms)
	if physics_ms > 0.0:
		print("  snapping is              %8.1f%% of the physics frame" % (
			100.0 * (per_frame / 1000.0) / physics_ms))
	print("")
	print("  (floor, not total: six other files call the server directly and are not counted)")
	quit(0)
