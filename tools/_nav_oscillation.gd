extends SceneTree

# ─────────────────────────────────────────────
# WHY DO SOME ROBOTS RUN ON THE SPOT?
#
# Measured earlier: chasers held 158-167 m from their objective for 80 s at a
# full 11.9 m/s with their heading flipping between +1.00 and -1.00, and a Walker
# bounced 101 -> 112 m the same way. Troopers at 6 m/s were fine. It is not
# crowding — the Walker did it alone — and not the squad layer, the leash, or the
# nav agent's configuration.
#
# THE HYPOTHESIS: _tick_nav is throttled. It refreshes the cached steering
# direction every nav_think_interval * lod_scale() seconds, and move_along_nav
# then drives at FULL SPEED on that stale direction until the next query. Past
# lod_far_distance (80 m from the player) lod_scale is lod_far_multiplier (4.0),
# so the interval is 0.15 * 4 = 0.6 s. At 12 m/s that is 7.2 metres of travel
# toward a path point about 1 m away — it overshoots by six metres, and the next
# query points it back the way it came.
#
# PREDICTION, if that is the cause:
#   period    ~= 2 * 0.6 = 1.2 s
#   amplitude ~= move_speed * 0.6
#   net closure over several seconds ~= 0
# and all of it should vanish when lod_scale is forced to 1.
#
# This logs every physics frame and reports the period, so the number either
# matches that arithmetic or it does not.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/georgetown_level.tscn"
const FROM := Vector3(-34.0, -7.5, 132.0)    # obj_gt_bandstand
const TO := Vector3(-200.0, -8.0, 152.0)     # obj_gt_landing, 167 m away
const STEP := 1.0 / 60.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var ms: Node = load("res://Managers/master.tscn").instantiate()
	ms.skip_splash = true
	ms.show_main_menu = false
	root.add_child(ms)
	for _i in 200:
		await process_frame
	var w := _find(root, "World")
	var cm = w.get_node_or_null("CampaignManager")
	if cm != null:
		cm.autosave = false
	w.load_next_level(load(LEVEL), true)
	for _i in 420:
		await process_frame
	for who in PauseHold.holders():
		PauseHold.release(who)
	for _i in 20:
		await process_frame

	# Four conditions. The first two are the diagnosis; the third tests the fix the
	# arithmetic implies; the fourth asks whether the Walker fails for the same
	# reason, since it is at the opposite end of the speed range.
	await _run(w, "res://Character/characters/ai/enemy_chaser.tscn", "chaser, as shipped", 4.0, 0.0)
	await _run(w, "res://Character/characters/ai/enemy_chaser.tscn", "chaser, full rate (control)", 1.0, 0.0)
	await _run(w, "res://Character/characters/ai/enemy_chaser.tscn", "chaser, throttled but distance-bounded", 4.0, 0.8)
	await _run(w, "res://Character/characters/ai/walker.tscn", "walker, as shipped", 4.0, 0.0)
	await _run(w, "res://Character/characters/ai/walker.tscn", "walker, distance-bounded", 4.0, 0.8)
	quit(0)


## `bound_m` > 0 caps how far the robot may travel between nav queries, which is
## the invariant the time-based throttle quietly assumes and does not enforce.
func _run(w, scene: String, label: String, lod_mult: float, bound_m: float) -> void:
	var bot = load(scene).instantiate()
	w.current_level.add_child(bot)
	await process_frame
	bot.global_position = FROM
	bot.faction = Enums.Factions.ENEMY
	bot.ai_manager = w.ai_manager
	bot.player = w.player
	if w.ai_manager != null:
		w.ai_manager.register_enemy(bot)
	# Never culled, so a frozen robot cannot be mistaken for an oscillating one.
	bot.exempt_from_culling(600.0)
	bot.lod_far_multiplier = lod_mult
	if bound_m > 0.0:
		# Re-ask often enough that the robot never outruns its own cached heading.
		bot.nav_think_interval = minf(bot.nav_think_interval,
			bound_m / maxf(bot.move_speed, 0.1) / maxf(lod_mult, 0.01))
	await process_frame
	bot.move_to(TO)

	var t := 0.0
	var samples: Array = []
	while t < 7.0:
		await physics_frame
		t += STEP
		var to_goal: Vector3 = TO - bot.global_position
		to_goal.y = 0.0
		var flat: Vector3 = bot.velocity
		flat.y = 0.0
		var heading := 0.0
		if flat.length() > 0.2 and to_goal.length() > 0.01:
			heading = flat.normalized().dot(to_goal.normalized())
		samples.append({"t": t, "d": to_goal.length(), "h": heading, "v": flat.length()})

	# Skip the first two seconds: a fresh order is granted full rate briefly
	# (mark_watched), so the throttle only shows itself after that.
	var settled: Array = []
	for s in samples:
		if s["t"] >= 2.0:
			settled.append(s)
	var flips := 0
	var last_sign := 0
	for s in settled:
		var sign_now: int = 1 if s["h"] > 0.3 else (-1 if s["h"] < -0.3 else 0)
		if sign_now != 0 and last_sign != 0 and sign_now != last_sign:
			flips += 1
		if sign_now != 0:
			last_sign = sign_now
	var span: float = settled[settled.size() - 1]["t"] - settled[0]["t"]
	var dmin := 9999.0
	var dmax := 0.0
	for s in settled:
		dmin = minf(dmin, s["d"])
		dmax = maxf(dmax, s["d"])
	var net: float = settled[0]["d"] - settled[settled.size() - 1]["d"]
	var vsum := 0.0
	for s in settled:
		vsum += s["v"]

	print("")
	print("%s   nav interval=%.3fs  speed=%.1f m/s  -> %.1f m travelled per query" % [
		label.to_upper(), bot.nav_think_interval * bot.lod_scale(), bot.move_speed,
		bot.move_speed * bot.nav_think_interval * bot.lod_scale()])
	print("  distance %.1f m -> %.1f m   NET CLOSED %.1f m in %.1fs" % [
		settled[0]["d"], settled[settled.size() - 1]["d"], net, span])
	print("  swung between %.1f and %.1f m (amplitude %.1f m)" % [dmin, dmax, dmax - dmin])
	print("  heading reversed %d time(s)  ->  period %s" % [
		flips, "%.2fs" % (2.0 * span / float(flips)) if flips > 0 else "never reversed"])
	print("  average speed %.1f m/s  (it is not standing still)" % (vsum / float(settled.size())))
	bot.queue_free()
	await process_frame


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null
