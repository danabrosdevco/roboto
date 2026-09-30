extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE AI ACTUALLY COSTS PER FRAME, MEASURED.
#
# The in-editor profiler says where the time goes on a real mission but cannot
# be run twice under identical conditions, so it cannot tell you whether a
# change helped. This can: the same map, the same spawn positions from a fixed
# seed, the same number of frames, every run.
#
# It reports the MEAN and — the number that matters here — the WORST frame.
# The complaint is spikes, not throughput: a mean of 12ms with an 83ms spike
# feels far worse than a flat 20ms, and averaging hides exactly that.
#
#   godot --headless --path . --script res://tools/bench_ai.gd -- [count] [frames]
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const WARMUP := 90

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


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var count: int = int(args[0]) if args.size() > 0 else 80
	var frames: int = int(args[1]) if args.size() > 1 else 400

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

	# FIXED SEED. Two runs have to spawn the same fight in the same places or
	# the comparison is noise.
	seed(20260930)
	var half: int = count / 2
	for i in count:
		var enemy_side: bool = i < half
		var fac: int = Enums.Factions.ENEMY if enemy_side else Enums.Factions.PLAYER
		# Two lines facing each other, close enough that everyone acquires —
		# which is the expensive state and the one being complained about.
		var x: float = 300.0 + randf_range(-30.0, 30.0)
		var z: float = (170.0 if enemy_side else 230.0) + randf_range(-14.0, 14.0)
		var body: Node = load(RIFLE).instantiate()
		body.faction = fac
		body.always_active = true
		_level.add_child(body)
		(body as Node3D).global_position = (ground.call(x, z) as Vector3) + Vector3.UP
		if _mgr != null and _mgr.has_method("register_enemy"):
			_mgr.register_enemy(body)

	for _i in WARMUP:
		await physics_frame

	# ── MEASURE ──────────────────────────────────
	var samples: PackedFloat64Array = PackedFloat64Array()
	for _i in frames:
		var t0 := Time.get_ticks_usec()
		await physics_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)

	var total := 0.0
	var worst := 0.0
	for s in samples:
		total += s
		worst = maxf(worst, s)
	var sorted := Array(samples)
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var p50: float = sorted[int(sorted.size() * 0.5)]

	print("")
	print("AI BENCH — %d robots, %d frames" % [count, frames])
	print("  median %7.2f ms" % p50)
	print("  mean   %7.2f ms" % (total / float(samples.size())))
	print("  p95    %7.2f ms" % p95)
	print("  WORST  %7.2f ms" % worst)
	print("  registered with the manager: %d" % (_mgr.all_ai.size() if _mgr != null else -1))
	quit(0)
