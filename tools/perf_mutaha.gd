extends SceneTree

# ─────────────────────────────────────────────
# MUTAHA FRAME COST — how long a physics frame actually takes out there.
#
# Measured with Performance.TIME_PHYSICS_PROCESS, NOT wall clock between ticks:
# the engine sleeps to hold its tick rate, so wall clock reports 16.67 ms for
# any frame that fits in budget, however much work is in it.
#
# Runs the same window twice on the same load, same machine, same robots:
#   CULLED   the distance cull as it stands
#   AWAKE    every hostile's activation distance raised past the map, so
#            nothing is ever culled — the cost the mission had before
# Headless, so there is no rendering in the number: this is script and physics,
# which is what the profiler was showing.
# ─────────────────────────────────────────────

const WARMUP := 60
const SAMPLE := 240


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	var op: MissionDefinition = cm.get_mission(&"mutaha_1_blocks")
	cm.select_mission(op.id)
	await world.load_next_level(op.level_scene)
	for _i in 180:
		await physics_frame

	print("[FRAMES] %s" % _census())
	var culled := await _measure()
	_report("CULLED  (as it stands)", culled)

	# Now raise every hostile's activation distance past the far corner of the
	# map so the cull can never fire, and run the identical window again.
	var raised := 0
	for n in get_nodes_in_group("enemies"):
		if n is Soldier and is_instance_valid(n):
			var s := n as Soldier
			s.activation_distance = 100000
			s.activation_distance_sq = 1.0e10
			raised += 1
	for _i in 120:
		await physics_frame
	print("[FRAMES] activation distance raised on %d robots -> %s" % [raised, _census()])
	var awake := await _measure()
	_report("AWAKE   (nothing culled)", awake)

	var a: float = culled["avg"]
	var b: float = awake["avg"]
	if a > 0.0:
		print("[FRAMES] culling saves %.2f ms of every physics frame (%.0f%% of %.2f)" % [
			b - a, (b - a) / b * 100.0, b])
	quit(0)


func _census() -> String:
	var total := 0
	var passive := 0
	for n in get_nodes_in_group("enemies"):
		if not (n is Soldier) or not is_instance_valid(n):
			continue
		total += 1
		if (n as Soldier).ai_state == Enemy.AIState.PASSIVE:
			passive += 1
	return "robots=%d passive=%d full-brain=%d" % [total, passive, total - passive]


# WALL CLOCK BETWEEN TICKS MEASURES THE PACING, NOT THE WORK. The engine sleeps
# to hold 60 Hz, so every frame that fits inside its budget takes 16.67 ms
# whatever is in it — the first version of this probe duly reported that culling
# 139 robots saved 0.03 ms. Ask the engine what it actually spent instead.
# TIME_PHYSICS_PROCESS reports the PREVIOUS step, which is why it cannot be
# trusted as a single reading, but over a few hundred samples the lag averages
# out and the number is the real one.
func _measure() -> Dictionary:
	for _i in WARMUP:
		await physics_frame
	var ms: Array[float] = []
	for _i in SAMPLE:
		await physics_frame
		ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	ms.sort()
	var sum := 0.0
	for v in ms:
		sum += v
	return {
		"avg": sum / float(ms.size()),
		"median": ms[ms.size() / 2],
		"p95": ms[int(float(ms.size()) * 0.95)],
		"max": ms[ms.size() - 1],
	}


func _report(label: String, r: Dictionary) -> void:
	print("[FRAMES] %s  avg %.2f ms  median %.2f  p95 %.2f  worst %.2f" % [
		label, r["avg"], r["median"], r["p95"], r["max"]])
