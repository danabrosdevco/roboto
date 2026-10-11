extends SceneTree

# ─────────────────────────────────────────────
# WHAT A MINE'S TRIGGER SCAN COSTS, OLD AGAINST NEW.
#
# The in-editor profile of a real firefight put Mine._physics_process at
# 68.56 ms of a 128.16 ms Script Functions total — more than every robot chassis
# on the map combined — with almost all of it in _hostile_in_reach at ~0.56 ms a
# scan, and ~232 live mines each scanning every scan_interval.
#
# This times the real _hostile_in_reach() against a faithful reconstruction of
# what it used to do, on the SAME bodies in the SAME process, called directly a
# few hundred times each with a clock around them. Out of band on purpose: no
# timers, no stagger, no "only some of them scanned this frame" — just the cost
# of one scan, which is the thing that had to come down.
#
# Same approach as tools/bench_ai_calls.gd.
#
#   godot --headless --audio-driver Dummy --path . --script tools/_mine_scan_cost.gd
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const MINE := "res://Character/weapon/mines/mine_heavy.tscn"
const BODIES := 130      # a big firefight's worth of hostiles
const REPS := 400


func _init() -> void:
	# See tools/bench_qamareen.gd: headless runs _process flat out and starves
	# everything measured beside it.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player
	var mgr: Node = world.ai_manager
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/mutaha_wip_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	var nmap: RID = player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	player.global_position = centre + Vector3.UP
	for _i in 20:
		await physics_frame

	seed(20260930)
	var bots: Array = []
	for i in BODIES:
		var bot = load(RIFLE).instantiate()
		bot.always_active = true
		level.add_child(bot)
		await process_frame
		var a := randf() * TAU
		bot.global_position = centre + Vector3(cos(a) * (10.0 + randf() * 50.0), 2.0,
			sin(a) * (10.0 + randf() * 50.0))
		bot.faction = Enums.Factions.ENEMY
		bot.player = player
		bot.ai_manager = mgr
		if mgr != null and mgr.has_method("register_enemy"):
			mgr.register_enemy(bot)
		bot.health = 100000000
		bot.max_health = 100000000
		bot.exempt_from_culling(100000.0)
		bots.append(bot)
	for _i in 120:
		await physics_frame

	var mine = load(MINE).instantiate()
	level.add_child(mine)
	await process_frame
	mine.global_position = centre + Vector3(0.0, 1.0, 0.0)
	for _i in 60:
		await physics_frame

	var hostiles: Array = mgr.hostiles_for(Enums.Factions.PLAYER) if mgr != null else []
	print("")
	print("MINE SCAN COST — %d hostiles in the list, %d reps each" % [hostiles.size(), REPS])

	# ── NEW: the shipped _hostile_in_reach ───────
	var t0 := Time.get_ticks_usec()
	for _i in REPS:
		mine._hostile_in_reach()
	var new_us := float(Time.get_ticks_usec() - t0) / float(REPS)

	# ── OLD: exactly what it used to do ──────────
	#
	# THE FALLBACK PATH, because that is the path it always took. Nothing was
	# ever added to the "ai_manager" group, so _ai_manager() returned null on
	# every scan of every mine and the cached hostiles_for() list was never once
	# used. The fallback walks the whole `enemies` group and calls _faction()
	# and are_hostile() PER NODE — which is the signature the profiler caught:
	# Mine._faction 2686 calls, Enums.are_hostile 2735.
	#
	# A first version of this bench reconstructed the manager path instead and
	# reported the old scan at 0.3 us, which is impossible for 127 bodies. That
	# wrong number is what exposed the empty group.
	var at: Vector3 = mine.global_position
	var radius: float = mine.trigger_radius
	var thrower = mine._thrower
	var t1 := Time.get_ticks_usec()
	for _i in REPS:
		var out: Array = []
		for n in root.get_tree().get_nodes_in_group("enemies"):
			# _faction() per node, as it was.
			var fac: int = thrower.faction if thrower != null and is_instance_valid(thrower) \
				and "faction" in thrower else Enums.Factions.PLAYER
			if n is Node3D and "faction" in n and Enums.are_hostile(fac, n.faction):
				out.append(n)
		for body in out:
			if body == null or not is_instance_valid(body) or not (body is Node3D):
				continue
			var living = body.get("alive")
			if living != null and not bool(living):
				continue
			if at.distance_to((body as Node3D).global_position) <= radius:
				break
	var old_us := float(Time.get_ticks_usec() - t1) / float(REPS)

	print("  old scan   %8.1f us" % old_us)
	print("  new scan   %8.1f us   (%.1fx faster)" % [new_us, old_us / maxf(new_us, 0.01)])
	print("")
	# 232 mines, each scanning every scan_interval (0.1 s = 6 frames at 60 Hz),
	# is 232/6 scans a frame on average.
	var per_frame: float = 232.0 / 6.0
	print("  at 232 live mines that is %.2f ms/frame before, %.2f ms/frame after" % [
		old_us * per_frame / 1000.0, new_us * per_frame / 1000.0])
	quit(0)
