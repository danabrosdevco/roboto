extends SceneTree

# ─────────────────────────────────────────────
# WHAT DOES A NAV QUERY ACTUALLY COST, AND WHEN?
#
# Two questions, one probe.
#
# FOR THE STEERING FIX: is get_current_navigation_path() cheap? If it hands back
# the already-computed path without re-resolving, a robot can walk its own
# polyline every frame for free and steering stops depending on query rate.
#
# FOR THE "ONLY RE-QUERY ON CHANGE" IDEA: the throttled _tick_nav does NOT set a
# new destination — set_target_position is only called on real events (a new
# order, a chase refresh, stuck recovery). So the 0.6 s tick is asking "where
# next along the path I already have". If that is cheap, then the expensive work
# already only happens on change and the idea is mostly already true; if it is
# expensive, there is real money in it.
#
# Times each call separately, every frame, and flags the frame after a
# destination change so the recompute spike can be seen against the baseline.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/georgetown_level.tscn"
const FROM := Vector3(-34.0, -7.5, 132.0)
const TO := Vector3(-200.0, -8.0, 152.0)
const ELSEWHERE := Vector3(-94.0, -7.5, 132.0)


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

	var bot = load("res://Character/characters/ai/enemy_chaser.tscn").instantiate()
	w.current_level.add_child(bot)
	await process_frame
	bot.global_position = FROM
	bot.faction = Enums.Factions.ENEMY
	bot.ai_manager = w.ai_manager
	bot.player = w.player
	bot.exempt_from_culling(600.0)
	await process_frame
	bot.move_to(TO)

	var agent: NavigationAgent3D = bot.nav_agent
	var path_us: Array = []
	var fin_us: Array = []
	var next_us: Array = []
	var after_change: Array = []
	var changed_on := 120

	for f in 240:
		await physics_frame
		if f == changed_on:
			agent.set_target_position(ELSEWHERE)
		var t0 := Time.get_ticks_usec()
		var p: PackedVector3Array = agent.get_current_navigation_path()
		var t1 := Time.get_ticks_usec()
		var fin: bool = agent.is_navigation_finished()
		var t2 := Time.get_ticks_usec()
		var nxt: Vector3 = agent.get_next_path_position()
		var t3 := Time.get_ticks_usec()
		if f > 20:
			if f >= changed_on and f <= changed_on + 2:
				after_change.append([f - changed_on, t1 - t0, t2 - t1, t3 - t2, p.size()])
			else:
				path_us.append(t1 - t0)
				fin_us.append(t2 - t1)
				next_us.append(t3 - t2)

	print("")
	print("STEADY STATE (destination unchanged), %d frames:" % path_us.size())
	print("  get_current_navigation_path()   avg %6.1f us   max %5d us" % [_avg(path_us), _max(path_us)])
	print("  is_navigation_finished()        avg %6.1f us   max %5d us" % [_avg(fin_us), _max(fin_us)])
	print("  get_next_path_position()        avg %6.1f us   max %5d us" % [_avg(next_us), _max(next_us)])
	print("")
	print("THE FRAME THE DESTINATION CHANGED, and the two after:")
	for r in after_change:
		print("  +%d frame   path %5d us   finished %5d us   next %5d us   (%d points)" % [
			r[0], r[1], r[2], r[3], r[4]])
	print("")
	print("path length now %d points" % agent.get_current_navigation_path().size())
	quit(0)


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _max(a: Array) -> int:
	var m := 0
	for v in a:
		m = maxi(m, int(v))
	return m


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null
