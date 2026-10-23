extends SceneTree

# ─────────────────────────────────────────────
# IS FREEZING CULLED ROBOTS WORTH ANYTHING? A/B/A/B, IN ONE PROCESS.
#
# Two separate attempts to answer this disagreed: the agent that wrote the
# feature measured ~2.8 ms for it, and a single run afterwards measured nothing.
# Both were taken on a box with other work on it, and an identical control run
# drifted 5.60 -> 7.52 ms between them. Neither number means anything.
#
# A number taken in one process, alternating, does. The level is loaded ONCE and
# the same robots are measured frozen, then thawed, then frozen again, then
# thawed again. Machine drift moves all four readings together, so the
# difference between the pairs survives it where a before-and-after across two
# processes does not.
#
# The A/B is `Enemy.cull_frozen`, which is what the feature actually does:
# true means the robot's _physics_process is off. Thawing here deliberately does
# NOT wake the brain — ai_state stays PASSIVE either way — so this measures the
# callback, which is the thing the feature removes, and nothing else.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/bench_freeze_ab.gd
# ─────────────────────────────────────────────

const MISSION := "mutaha_2_city"
## Frames per reading. Long enough that one hitch cannot colour a pass.
const WINDOW := 400
## Discarded after each switch: the physics server takes a few frames to settle
## after 176 bodies change their processing state.
const WARMUP := 60


func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _all(n: Node, cls: String, out: Array) -> void:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)


## Sets every culled robot's physics callback on or off, and says how many it
## touched. PASSIVE (5) is what the distance cull sets; awake robots are left
## alone in both passes, because they are not what is under test.
func _set_frozen(bots: Array, frozen: bool) -> int:
	var n := 0
	for b in bots:
		if int(b.get("ai_state")) != 5:
			continue
		b.set("cull_frozen", frozen)
		b.set_physics_process(not frozen)
		n += 1
	return n


func _measure(label: String) -> float:
	for _i in WARMUP:
		await physics_frame
	var worst := 0.0
	var total := 0.0
	for _i in WINDOW:
		await physics_frame
		var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total += ms
		worst = maxf(worst, ms)
	var avg := total / float(WINDOW)
	print("    %-18s %7.2f ms   (worst frame %.2f)" % [label, avg, worst])
	return avg


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
		printerr("bench_freeze_ab: no mission '%s'." % MISSION)
		quit(1)
		return
	cm.state.selected_mission_id = mission.id
	_find(root, "World").load_next_level(mission.level_scene, true)
	for _i in 420:
		await physics_frame

	var bots: Array = []
	_all(root, "Soldier", bots)
	_all(root, "Rover", bots)
	var culled := 0
	for b in bots:
		if int(b.get("ai_state")) == 5:
			culled += 1
	if culled == 0:
		# EVERY EMPTY RESULT SAYS WHY. Nothing culled means nothing to freeze,
		# and a clean-looking zero difference would be measuring an empty set.
		printerr("bench_freeze_ab: no culled robots to measure — the cull did not run.")
		quit(1)
		return
	print("")
	print("FREEZE A/B — %d robots in the level, %d of them culled" % [bots.size(), culled])
	print("  alternating in one process, so machine drift moves every reading together")
	print("")

	var frozen_runs: Array = []
	var thawed_runs: Array = []
	for pass_n in 2:
		_set_frozen(bots, true)
		frozen_runs.append(await _measure("frozen  (pass %d)" % (pass_n + 1)))
		_set_frozen(bots, false)
		thawed_runs.append(await _measure("thawed  (pass %d)" % (pass_n + 1)))

	var frozen_avg: float = (frozen_runs[0] + frozen_runs[1]) * 0.5
	var thawed_avg: float = (thawed_runs[0] + thawed_runs[1]) * 0.5
	var saved := thawed_avg - frozen_avg
	print("")
	print("  frozen   %6.2f ms   thawed %6.2f ms" % [frozen_avg, thawed_avg])
	print("  FREEZING SAVES %+.2f ms a frame (%+.1f%%), over %d culled robots" % [
		saved, 100.0 * saved / maxf(thawed_avg, 0.001), culled])
	# The spread between the two passes of the SAME state is the noise floor.
	# A saving smaller than it is not a saving.
	var noise := maxf(absf(frozen_runs[0] - frozen_runs[1]), absf(thawed_runs[0] - thawed_runs[1]))
	print("  noise floor (spread between repeats of the same state) %.2f ms" % noise)
	if absf(saved) <= noise:
		print("  -> THE SAVING IS INSIDE THE NOISE. This measurement cannot tell them apart.")
	quit(0)
