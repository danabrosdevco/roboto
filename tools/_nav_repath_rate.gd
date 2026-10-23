extends SceneTree

# ─────────────────────────────────────────────
# ARE THEY REALLY RE-PATHING EVERY 0.6 SECONDS?
#
# The throttle in _tick_nav is described as "how often a robot thinks", and the
# worry is that it is a whole-map path search on that schedule. It is not, and
# this counts the difference.
#
# A NavigationAgent3D only re-resolves when something marked it dirty — a new
# set_target_position, a drift past path_max_distance, a navmesh change. Asking
# it for the next point in between is a lookup into an array it already has.
# Measured per call: 0.3 us for get_next_path_position in steady state against
# 135 us on the frame the destination changed.
#
# So: run a real mission with its real enemy force, and for every robot, every
# frame, compare the agent's current path to the one it had last frame. A change
# is a re-resolve. Everything else is the cheap lookup.
#
# If re-resolves are a small fraction of queries, then "only re-query when
# something changed" is already how it works, and the lever for performance is
# the number of ORDERS the squad layer issues, not the think interval.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/georgetown_level.tscn"
const SECONDS := 20.0
const FROM := Vector3(-34.0, -7.5, 132.0)    # obj_gt_bandstand
const TO := Vector3(-200.0, -8.0, 152.0)     # obj_gt_landing, 167 m away
const SQUAD := 40
const CHASSIS := [
	"res://Character/characters/ai/enemy_chaser.tscn",
	"res://Character/characters/ai/walker.tscn",
	"res://Character/characters/ai/soldier_rifle.tscn",
]


func _init() -> void:
	Settings.path = "user://settings_repath.json"
	await process_frame
	# Same boot as tools/_nav_oscillation.gd, and for the same reason: going in
	# through start_game() leaves the mission briefing holding the pause, so
	# `await physics_frame` never fires again and the probe hangs forever.
	var ms: Node = load("res://Managers/master.tscn").instantiate()
	ms.skip_splash = true
	ms.show_main_menu = false
	root.add_child(ms)
	for _i in 200:
		await process_frame
	var w := _find(root, "World")
	if w == null:
		push_warning("[repath] no World node; the probe cannot run")
		quit(1)
		return
	var cm = w.get_node_or_null("CampaignManager")
	if cm != null:
		cm.autosave = false   # NEVER write the real save from a probe
	w.load_next_level(load(LEVEL), true)
	for _i in 420:
		await process_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	# A FORCE OF OUR OWN. Loading a level does not deploy a mission's hostiles —
	# that needs an operation selected and Campaign.begin_deploy() — so an
	# earlier version of this probe counted 0 robots and reported nothing. These
	# are spawned and ordered the same way _nav_oscillation.gd does it, which
	# makes the measurement independent of whatever a mission currently rosters.
	var bots: Array = []
	for i in SQUAD:
		var scene: String = CHASSIS[i % CHASSIS.size()]
		var bot = load(scene).instantiate()
		w.current_level.add_child(bot)
		await process_frame
		# Fanned out, so they are walking their own routes rather than one route
		# twelve times over.
		bot.global_position = FROM + Vector3(float(i % 4) * 3.0, 0.0, float(i / 4) * 3.0)
		bot.faction = Enums.Factions.ENEMY
		bot.ai_manager = w.ai_manager
		bot.player = w.player
		if w.ai_manager != null:
			w.ai_manager.register_enemy(bot)
		bot.exempt_from_culling(600.0)   # never culled, so every frame counts
		bots.append(bot)
	await process_frame
	for bot in bots:
		bot.move_to(TO)

	# Settle, so first-frame path resolution is not counted as churn.
	for _i in 120:
		await physics_frame

	var seen: Dictionary = {}        # robot -> last path
	var queries: int = 0             # frames a robot held a resolved path
	var resolves: int = 0            # frames that path was a different one
	var bodies: Dictionary = {}      # robot -> true, to count distinct robots
	var frames: int = 0
	# WHAT THE THROTTLED TICK ACTUALLY COSTS. Enemy._nav_spent_us is the static
	# accumulator _tick_nav already keeps — it is reset at the top of each frame
	# and holds the microseconds that frame's nav queries took. Read at the end
	# of the frame it is that frame's whole nav bill.
	var tick_us: int = 0
	var tick_us_max: int = 0
	# And what the per-frame path read costs, measured on the same call the fix
	# makes, once per robot per frame — the loop below IS that workload.
	var read_us: int = 0
	var read_us_max: int = 0
	var t := 0.0
	while t < SECONDS:
		await physics_frame
		t += 1.0 / 60.0
		frames += 1
		var spent: int = Enemy._nav_spent_us
		tick_us += spent
		tick_us_max = maxi(tick_us_max, spent)
		var began := Time.get_ticks_usec()
		for bot in root.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(bot) or not ("nav_agent" in bot):
				continue
			if bot.nav_agent == null or not bot.alive:
				continue
			var path: PackedVector3Array = bot.nav_agent.get_current_navigation_path()
			if path.size() < 2:
				continue
			bodies[bot] = true
			queries += 1
			var id := bot.get_instance_id()
			if not seen.has(id) or seen[id] != path:
				resolves += 1
			seen[id] = path
		var took := Time.get_ticks_usec() - began
		read_us += took
		read_us_max = maxi(read_us_max, took)

	print("")
	print("RE-PATH RATE on Georgetown, %d robots, %d physics frames (%.0f s)" % [
		bodies.size(), frames, SECONDS])
	print("  robot-frames holding a path:  %d" % queries)
	print("  of those, the path CHANGED:   %d  (%.2f%%)" % [
		resolves, 100.0 * float(resolves) / maxf(float(queries), 1.0)])
	if bodies.size() > 0:
		print("  per robot that is one re-resolve every %.1f s" % [
			SECONDS / maxf(float(resolves) / float(bodies.size()), 0.001)])
	print("")
	print("WHAT IT COSTS A FRAME, with %d robots all walking" % bodies.size())
	print("  throttled _tick_nav queries:  %.1f us/frame avg, %d us worst" % [
		float(tick_us) / maxf(float(frames), 1.0), tick_us_max])
	print("  per-frame path read (the fix): %.1f us/frame avg, %d us worst" % [
		float(read_us) / maxf(float(frames), 1.0), read_us_max])
	print("  a 60 fps frame is 16667 us.")
	print("")
	print("  A re-resolve costs ~135 us. A query that finds the path unchanged")
	print("  costs ~0.3-2 us. The throttle is pacing the cheap one.")
	quit(0)


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null
