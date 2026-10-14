extends SceneTree

# ─────────────────────────────────────────────
# WHERE DOES A ROBOT'S 0.1 ms A FRAME ACTUALLY GO?
#
# Established across three tools: a robot in the scene costs ~0.10-0.124 ms of
# physics frame whether it is awake, asleep or frozen, and only ~8% of that is
# its brain. nav + think + weapon rays + sight rays together account for 3.15 ms
# of the 17.9 ms that 160 robots add. The other ~15 ms has no owner.
#
# This finds the owner by ABLATION, A/B/A/B IN ONE PROCESS.
#
# That design is not optional. Run-to-run drift on this machine is several ms:
# two bench_ai batches an hour apart gave the same 80-robot configs as 11.01 vs
# 16.94 ms and then 13.49 vs 13.59 ms, and the first pair was read as "combat
# costs +54%" when it was noise. Machine drift moves all four readings of an
# A/B/A/B together, so the difference between the PAIRS survives it.
# tools/bench_freeze_ab.gd established this; this generalises it to a list of
# suspects.
#
# The population is immortal and culling-exempt for the whole run, because an
# A/B is meaningless if the number of robots changes between readings.
#
#   godot --headless --audio-driver Dummy --path . --script tools/_robot_cost_ab.gd -- [count] [frames] [map]
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const CHASER := "res://Character/characters/ai/enemy_chaser.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"
## Frames per reading. Long enough that one hitch cannot colour a pass.
const READING := 180
const WARMUP := 120

var _bots: Array = []
var _saved: Dictionary = {}


func _init() -> void:
	# PACE THE LOOP, OR MEASURE NOTHING. Headless runs _process as fast as it
	# can, and Squad ticks six functions in _process, 66 squads of them on
	# Qamareen. Unthrottled, that saturates the core and every physics reading
	# beside it is really measuring _process starving the frame.
	#
	# Leaving this out is what made four sweeps unreadable: the control row,
	# which must be ~0, came out at 6.09 and 7.53 ms; the unablated baseline
	# swung 38 -> 17 within a single row; and two runs of bench_qamareen on the
	# identical configuration gave 29.82 and 20.03 ms. bench_qamareen.gd has
	# carried this line, and the reason for it, since it was written.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	var count: int = int(args[0]) if args.size() > 0 else 160
	var frames: int = int(args[1]) if args.size() > 1 else READING
	var map: String = String(args[2]) if args.size() > 2 else "mutaha_wip"
	# TWO POPULATIONS, AND THE SECOND ONE IS THE ONE THAT MATTERS.
	#
	# "awake" exempts every robot from culling, so all of them run a full brain.
	# That is the fight you are standing in.
	#
	# "frozen" is the real mission: on Qamareen 167 of 186 hostiles are culled
	# AND frozen — _physics_process switched off entirely — and they still cost
	# ~0.12 ms each. Whatever a robot pays for while its tick is OFF is the cost
	# that distance culling cannot touch and that a bigger map makes worse,
	# because a bigger map is mostly robots you are nowhere near.
	var frozen: bool = args.size() > 3 and String(args[3]) == "frozen"
	# "combat": a real two-sided fight instead of a walk.
	#
	# ENEMY and ALLIED are mutually hostile and NEITHER is the player's side, so
	# both halves are culled and throttled by the ordinary rules — which a
	# PLAYER-faction half would not be (_is_player_side is exempt from the cull,
	# and squad_directed robots skip the LOD stride). The two sides are placed
	# apart and ordered onto each other, so they close and then stay in contact.
	var combat: bool = args.size() > 3 and String(args[3]) == "combat"

	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # NEVER write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	# OFF WORLD'S OWN EXPORTS, not by node name. The player node in world.tscn
	# is called `test_character` — "Player" is its class_name — so a name search
	# returns null and the next line dies on it. The other benches search by
	# script global name for the same reason.
	var player: Node3D = world.player
	var mgr: Node = world.ai_manager
	if player == null:
		push_warning("[cost_ab] world.player is null; the probe cannot run")
		quit(1)
		return
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/%s_level.tscn" % map).instantiate())
	for _i in 30:
		await physics_frame

	var nmap: RID = player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	player.global_position = centre + Vector3.UP
	for _i in 40:
		await physics_frame

	# EMPTY-MAP FLOOR FIRST, so every saving below can be read as a share of
	# what the robots actually add rather than of the whole frame.
	var floor_ms := await _measure(frames)

	seed(20260930)
	var scenes := [RIFLE, RIFLE, RIFLE, CHASER, WALKER]   # a mixed force, as a mission is
	for i in count:
		var bot = load(String(scenes[i % scenes.size()])).instantiate()
		bot.always_active = true
		level.add_child(bot)
		await process_frame
		var a := randf() * TAU
		var r := 20.0 + randf() * 60.0
		(bot as Node3D).global_position = centre + Vector3(cos(a) * r, 2.0, sin(a) * r)
		bot.faction = Enums.Factions.ENEMY
		if combat:
			# Two clusters 70 m apart, alternating sides, so each half has to
			# cross to the other and then fights where they meet.
			var side := i % 2
			bot.faction = Enums.Factions.ENEMY if side == 0 else Enums.Factions.ALLIED
			var off := Vector3(-35.0 if side == 0 else 35.0, 2.0, 0.0)
			(bot as Node3D).global_position = centre + off \
				+ Vector3(randf_range(-14.0, 14.0), 0.0, randf_range(-20.0, 20.0))
		bot.player = player
		bot.ai_manager = mgr
		if mgr != null and mgr.has_method("register_enemy"):
			mgr.register_enemy(bot)
		# CONSTANT POPULATION. Nothing dies and nothing is culled, for the whole
		# run — an A/B whose two readings have different robot counts measures
		# the count.
		bot.health = 100000000
		bot.max_health = 100000000
		if not frozen:
			bot.exempt_from_culling(100000.0)
		_bots.append(bot)
	for i in _bots.size():
		var bot = _bots[i]
		if combat:
			# Onto the other side's start, so they advance into contact.
			bot.move_to(centre + Vector3(35.0 if i % 2 == 0 else -35.0, 0.0, 0.0))
		else:
			bot.move_to(centre)
	# A fight needs longer than a walk to actually join.
	for _i in (WARMUP * 4 if combat else WARMUP):
		await physics_frame

	if frozen:
		# Put them where the cull will take them and let the cull do it, rather
		# than switching the tick off by hand: the cull's own path is what the
		# real mission runs, and enter_passive_mode() does bookkeeping that a
		# bare set_physics_process(false) would skip.
		for bot in _bots:
			(bot as Node3D).global_position += Vector3(0.0, 0.0, 4000.0)
		for _i in 180:
			await physics_frame
		var still_ticking := 0
		for bot in _bots:
			if bot.is_physics_processing():
				still_ticking += 1
		print("  [frozen run] %d of %d robots still ticking after the cull" % [
			still_ticking, _bots.size()])

	# Zeroed here so the ray counters describe the measured baseline and not the
	# spawn-in and the walk to contact.
	AIWeapon._shot_spent_us = 0
	AIWeapon._shot_rays = 0
	Enemy._sight_spent_us = 0
	Enemy._sight_rays = 0
	var base_ms := await _measure(frames)

	var floor_tot: float = floor_ms.x + floor_ms.y
	var base_tot: float = base_ms.x + base_ms.y
	print("")
	print("ROBOT COST ABLATION — %d robots on %s, %s, %d frames a reading, A/B/A/B" % [
		count, map, "FROZEN (culled)" if frozen else "AWAKE (cull-exempt)", frames])
	print("  empty map floor      physics %6.2f + idle %6.2f = %6.2f ms" % [
		floor_ms.x, floor_ms.y, floor_tot])
	print("  with %3d robots      physics %6.2f + idle %6.2f = %6.2f ms" % [
		count, base_ms.x, base_ms.y, base_tot])
	print("  robots add           physics %6.2f + idle %6.2f = %6.2f ms  (%.3f ms each)" % [
		base_ms.x - floor_ms.x, base_ms.y - floor_ms.y, base_tot - floor_tot,
		(base_tot - floor_tot) / maxf(float(count), 1.0)])
	# PROVE THE FIGHT IS REAL. A combat run that quietly failed to join would
	# look exactly like a walking run and silently answer a different question.
	var fighting := 0
	var ticking := 0
	for bot in _bots:
		if not is_instance_valid(bot):
			continue
		if bot.is_physics_processing():
			ticking += 1
		var t = bot.get("combat_target")
		if t != null and is_instance_valid(t):
			fighting += 1
	print("  %d of %d robots have a combat target, %d still ticking" % [
		fighting, _bots.size(), ticking])
	print("  shoot %.2f ms/frame (%.0f rays), sight %.2f ms/frame (%.0f rays) over the baseline reading" % [
		float(AIWeapon._shot_spent_us) / 1000.0 / float(frames),
		float(AIWeapon._shot_rays) / float(frames),
		float(Enemy._sight_spent_us) / 1000.0 / float(frames),
		float(Enemy._sight_rays) / float(frames)])
	print("")
	print("  SUSPECT                    with   without    SAVING    share   [what it is]")

	# Share is of the PHYSICS cost robots add, to match the physics-only savings.
	var added: float = maxf(base_ms.x - floor_ms.x, 0.01)
	for suspect in _suspects():
		var sname: String = suspect["name"]
		if bool(suspect.get("frozen_only", false)) and not frozen:
			print("  %-24s   skipped: only valid on a frozen population, see the note" % sname)
			continue
		var on := await _reading(suspect, false, frames)
		var off := await _reading(suspect, true, frames)
		var on2 := await _reading(suspect, false, frames)
		var off2 := await _reading(suspect, true, frames)
		_apply(suspect, false)
		# NO RE-ISSUING ORDERS BETWEEN ROWS, and the attempt is instructive.
		#
		# Re-ordering all 160 robots to keep the fight fresh called
		# set_target_position 160 times at once, which is 160 path resolutions at
		# ~135 us each, and the first reading of every row caught the burst: the
		# unablated readings went 38 / 27 / 22 / 34 / 36 / 27 / 31 / 33 on the
		# first half and ~17.5 on the second, so EVERY row's two halves
		# disagreed and the whole sweep had to be thrown away. The fight is left
		# to run on its own; robots are immortal, so it does not end.
		# PHYSICS ONLY, and the control row is why. TIME_PROCESS reads ~9 ms on an
		# EMPTY map in headless, so it is measuring the main loop's frame pacing
		# rather than work, and folding it in made every row noise: the
		# meshes-hidden control, which must be ~0, came out at 6.61 ms. Idle is
		# still printed above as context, but it cannot carry an A/B. Anything
		# that ticks only in the idle frame (particles, audio) will therefore
		# read ~0 here, which is correct rather than a null result.
		var with_it: float = (on.x + on2.x) * 0.5
		var without: float = (off.x + off2.x) * 0.5
		var saved := with_it - without
		# THE TWO HALVES, SEPARATELY, AND EVERY RAW READING.
		#
		# A/B/A/B only protects against drift that moves all four together. If
		# the population itself changed during the row — robots fell out of the
		# world, a fight burned out — the two halves disagree, and averaging
		# them hides exactly that. So both are printed: when d1 and d2 are not
		# close, the row means nothing, whatever the mean says. The unablated
		# readings (on1, on2) should also match each other and the baseline; if
		# they walk, the run is degrading.
		var d1: float = on.x - off.x
		var d2: float = on2.x - off2.x
		var agree: String = "" if absf(d1 - d2) <= maxf(0.25 * absf(saved), 1.0) else "  <-- HALVES DISAGREE, ignore"
		print("  %-24s %6.2f    %6.2f   %7.2f ms   %5.1f%%   [%s]" % [
			sname, with_it, without, saved, 100.0 * saved / added, suspect.get("what", "")])
		print("        on %6.2f off %6.2f | on %6.2f off %6.2f   d1 %+.2f  d2 %+.2f%s" % [
			on.x, off.x, on2.x, off2.x, d1, d2, agree])
	print("")
	print("  Readings are TIME_PHYSICS_PROCESS means. Each SAVING is the mean of")
	print("  two with-readings minus two without-readings, interleaved in this")
	print("  one process, so machine drift moves all four together.")
	quit(0)


func _reading(suspect: Dictionary, ablate: bool, frames: int) -> Vector2:
	_apply(suspect, ablate)
	# LONG SETTLE. The physics server re-broadphases when shapes or areas go on
	# or off, and timing that transition rather than the steady state is how a
	# 30-frame reading produced a 6.61 ms "saving" on a control that must be 0.
	for _i in 40:
		await physics_frame
	return await _measure(frames)


## BOTH HALVES OF THE FRAME. x is physics, y is idle.
##
## Every measurement in this investigation until now read TIME_PHYSICS_PROCESS
## alone, which misses anything that ticks in the idle frame — and a trooper
## carries two CPUParticles3D and three AudioStreamPlayer3D, none of which run
## in physics. A player's frame rate is paid out of the sum, so the sum is what
## has to be ablated.
func _measure(frames: int) -> Vector2:
	var ms := 0.0
	var idle := 0.0
	for _i in frames:
		await physics_frame
		ms += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		idle += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var n := maxf(float(frames), 1.0)
	return Vector2(ms / n, idle / n)


# ── THE SUSPECTS ──────────────────────────────
# Each is a name, a one-line note, and a setter taking (bot, off).
## The control runs FIRST and LAST, bracketing the sweep: two readings of a
## suspect that cannot possibly cost anything, one at each end, is the honest
## measure of how much drift the run accumulated.
func _suspects() -> Array:
	return [
		{
			"name": "control (meshes) FIRST",
			"what": "CONTROL: headless draws nothing, so expect ~0",
			"set": _set_meshes,
		},
		{
			"name": "_physics_process",
			"what": "the robot's own script callback",
			"set": _set_callback,
		},
		{
			"name": "nav agent avoidance",
			"what": "NavigationServer RVO, one agent each",
			"set": _set_avoidance,
		},
		{
			"name": "nav agent entirely",
			"what": "the NavigationAgent3D node's own processing",
			"set": _set_agent,
		},
		# COLLISION SHAPES ONLY IN A FROZEN RUN, and this is not fussiness.
		#
		# On a moving population, switching the body's shape off drops every
		# robot through the terrain, and they never come back. In the combat run
		# that did it this cost was measured at 21.12 ms — "118% of everything
		# robots add" — and the real tell was the unablated baseline, which is
		# supposed to be identical on every row and instead went
		# 37 -> 19 -> 18 -> 37 -> 11 -> 16 -> 12 -> 8.6 -> 7.65 as the population
		# fell out of the world. Every row after it was junk, the control
		# included.
		#
		# A frozen robot runs no _physics_process, so no gravity and no
		# move_and_slide: it stays exactly where it is with its shape off, and
		# the measurement is of the shape's presence in the space and nothing
		# else. That is also the question that matters, since a big map is mostly
		# robots the player is nowhere near.
		{
			"name": "collision shapes",
			"what": "2 each in the physics space (frozen runs only)",
			"set": _set_shapes,
			"frozen_only": true,
		},
		{
			"name": "CSG nodes",
			"what": "runtime CSG, 2-6 per chassis",
			"set": _set_csg,
		},
		{
			"name": "Area3D monitoring",
			"what": "the Detection cone, one each, overlap-tested every frame",
			"set": _set_areas,
		},
		{
			"name": "CPUParticles3D",
			"what": "2 each: oil_spray, spark_burst. Idle frame, not physics",
			"set": _set_particles,
		},
		{
			"name": "AudioStreamPlayer3D",
			"what": "3 each: bark + 2 on the weapon",
			"set": _set_audio,
		},
		{
			"name": "control (meshes) LAST",
			"what": "CONTROL again: the gap between this and the first row is drift",
			"set": _set_meshes,
		},
	]


func _set_callback(bot: Node, off: bool) -> void:
	bot.set_physics_process(not off)


func _set_avoidance(bot: Node, off: bool) -> void:
	var a = bot.get("nav_agent")
	if a == null or not is_instance_valid(a):
		return
	if not _saved.has(a):
		_saved[a] = a.avoidance_enabled
	a.avoidance_enabled = false if off else bool(_saved[a])


func _set_agent(bot: Node, off: bool) -> void:
	var a = bot.get("nav_agent")
	if a == null or not is_instance_valid(a):
		return
	a.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT


func _set_shapes(bot: Node, off: bool) -> void:
	for s in _collect(bot, "CollisionShape3D"):
		s.disabled = off


func _set_csg(bot: Node, off: bool) -> void:
	for s in _collect(bot, "CSGShape3D"):
		s.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT


## Monitoring, not the node: an Area3D's per-frame cost is the overlap test it
## asks the physics server for, and PHYSICS_3D_COLLISION_PAIRS came back 0 while
## the frame cost 29.82 ms — area overlaps are not counted there.
func _set_areas(bot: Node, off: bool) -> void:
	for s in _collect(bot, "Area3D"):
		s.monitoring = not off
		s.monitorable = not off


func _set_particles(bot: Node, off: bool) -> void:
	for s in _collect(bot, "CPUParticles3D"):
		s.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT


func _set_audio(bot: Node, off: bool) -> void:
	for s in _collect(bot, "AudioStreamPlayer3D"):
		s.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT


func _set_meshes(bot: Node, off: bool) -> void:
	for s in _collect(bot, "MeshInstance3D"):
		s.visible = not off


func _apply(suspect: Dictionary, off: bool) -> void:
	var setter: Callable = suspect["set"]
	for bot in _bots:
		if is_instance_valid(bot):
			setter.call(bot, off)


## Every descendant that IS-A `cls`, by class rather than by name, so a renamed
## node in one chassis does not quietly drop out of the count.
func _collect(n: Node, cls: String, out: Array = []) -> Array:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_collect(c, cls, out)
	return out


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null
