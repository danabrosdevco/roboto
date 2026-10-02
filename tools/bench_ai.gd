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
#   godot --headless --path . --script res://tools/bench_ai.gd -- [count] [frames] [mode] [map]
#
# THE MAP MATTERS, and for a long time this could only measure the valley. Three
# Rivers is 1.3 km across and its navigation map has the polygon count to match,
# so a query that costs 0.1 ms in the valley costs 1.0 ms out there. A change
# benched only on the valley can look free and still cost 50 ms a frame on the
# map the complaint came from.
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
	var flat: bool = args.size() > 2 and String(args[2]) == "flat"
	var immortal: bool = args.size() > 2 and String(args[2]) == "immortal"
	var map: String = String(args[3]) if args.size() > 3 else "valley"

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/%s_level.tscn" % map).instantiate())
	for _i in 20:
		await physics_frame

	var space := _player.get_world_3d().direct_space_state
	var ground := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	# ON THE NAVMESH, so this works on any map rather than at coordinates that
	# only mean something in the valley.
	var nmap: RID = _player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	_player.global_position = centre + Vector3.UP
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
		# SPREAD ACROSS THE MAP, not piled on the player. A tight scrum puts
		# everything inside the near band, where nothing strides and the LOD is
		# never exercised — the first version of this bench measured a change
		# that could not possibly have fired. Three Rivers is a fight strung out
		# over a couple of hundred metres, so this is too.
		var x: float = centre.x + randf_range(-60.0, 60.0)
		var z: float = centre.z + (randf_range(-130.0, -55.0) if enemy_side else randf_range(-45.0, 70.0))
		var body: Node = load(RIFLE).instantiate()
		body.faction = fac
		body.always_active = true
		_level.add_child(body)
		(body as Node3D).global_position = (ground.call(x, z) as Vector3) + Vector3.UP
		if _mgr != null and _mgr.has_method("register_enemy"):
			_mgr.register_enemy(body)
		if immortal:
			# Nothing dies. If the spike survives this it is not the death path,
			# whatever the downed counter happens to be doing on that frame.
			body.health = 100000000
			body.max_health = 100000000
		if flat:
			# A/B control: every robot thinks every frame, which is what the
			# code did before the distance-scaled stride.
			body.far_think_every = 1
			body.distant_think_every = 1

	for _i in WARMUP:
		await physics_frame

	# ── MEASURE ──────────────────────────────────
	# A RESERVE WAVE, MID-MEASUREMENT.
	#
	# The complaint is specifically "when new reserve squads spawn in and are
	# advancing". Standing the whole population up before the clock starts and
	# warming for ninety frames measures a settled fight and never that — which is
	# how a spike that only happens on reinforcement stays invisible to a bench
	# that reports a flat median. Pass a fifth argument to drop a wave in at the
	# quarter mark and watch what it costs.
	var wave: int = int(args[4]) if args.size() > 4 else 0
	var wave_at: int = frames / 4

	var samples: PackedFloat64Array = PackedFloat64Array()
	# Nav spend alongside the frame time. Enemy keeps a static microsecond
	# tally per physics frame for its own query budget; sampling it here says
	# whether a spike is pathfinding or something else, which is the difference
	# between two completely different fixes.
	var nav: PackedFloat64Array = PackedFloat64Array()
	var states: PackedStringArray = PackedStringArray()
	for _f in frames:
		if wave > 0 and _f == wave_at:
			# Everything a real reinforcement does at once: spawn, register, and be
			# given somewhere to go.
			for i in wave:
				var body: Node = load(RIFLE).instantiate()
				body.faction = Enums.Factions.ENEMY
				body.always_active = true
				_level.add_child(body)
				var wx: float = centre.x + randf_range(-40.0, 40.0)
				var wz: float = centre.z - 240.0 + randf_range(-30.0, 30.0)
				(body as Node3D).global_position = (ground.call(wx, wz) as Vector3) + Vector3.UP
				if _mgr != null and _mgr.has_method("register_enemy"):
					_mgr.register_enemy(body)
				body.move_to(centre)
		var t0 := Time.get_ticks_usec()
		await physics_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		nav.append(float(Enemy._nav_spent_us) / 1000.0)
		# A cheap per-frame signature of what the population is doing. If the
		# spike frame is also the frame a hundred robots change state, the spike
		# is that transition and not the steady-state cost of anything.
		var in_combat := 0
		var downed := 0
		for a in _mgr.all_ai:
			if a == null or not is_instance_valid(a):
				continue
			if a.get("combat_target") != null:
				in_combat += 1
			if a.get("downed"):
				downed += 1
		states.append("%d/%d" % [in_combat, downed])

	var total := 0.0
	var worst := 0.0
	var worst_i := 0
	var nav_total := 0.0
	for i in samples.size():
		total += samples[i]
		nav_total += nav[i]
		if samples[i] > worst:
			worst = samples[i]
			worst_i = i
	var sorted := Array(samples)
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var p50: float = sorted[int(sorted.size() * 0.5)]

	print("")
	print("AI BENCH — %d robots on %s, %d frames%s" % [count, map, frames, "  [FLAT: no LOD stride]" if flat else "  [distance-scaled thinking]"])
	print("  median %7.2f ms" % p50)
	print("  mean   %7.2f ms" % (total / float(samples.size())))
	print("  p95    %7.2f ms" % p95)
	print("  WORST  %7.2f ms   (nav %.2f ms of it)" % [worst, nav[worst_i]])
	print("  nav    %7.2f ms mean" % (nav_total / float(nav.size())))
	# WHICH frames were bad, not just how bad. One outlier is an event; a run of
	# them every N frames is a timer or a cache expiring.
	var idx: Array = []
	for i in samples.size():
		idx.append(i)
	idx.sort_custom(func(a, b): return samples[a] > samples[b])
	var worst_list := PackedStringArray()
	for i in mini(8, idx.size()):
		worst_list.append("f%d=%.0fms" % [idx[i], samples[idx[i]]])
	print("  worst frames: %s" % " ".join(worst_list))
	var lo: int = maxi(0, worst_i - 3)
	var hi: int = mini(states.size() - 1, worst_i + 3)
	var around := PackedStringArray()
	for i in range(lo, hi + 1):
		around.append("f%d %s %.0fms" % [i, states[i], samples[i]])
	print("  in_combat/downed around the spike: %s" % "  |  ".join(around))
	if wave > 0:
		var at_wave := PackedStringArray()
		for i in range(maxi(0, wave_at - 2), mini(samples.size() - 1, wave_at + 10)):
			at_wave.append("f%d=%.0f" % [i, samples[i]])
		print("  WAVE of %d at frame %d: %s" % [wave, wave_at, " ".join(at_wave)])
	print("  registered with the manager: %d" % (_mgr.all_ai.size() if _mgr != null else -1))
	quit(0)
