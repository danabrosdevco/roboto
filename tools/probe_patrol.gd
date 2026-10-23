extends SceneTree
# ─────────────────────────────────────────────
# DO PATROL SQUADS ACTUALLY WALK THEIR ROUTE?
#
# Reported as "I don't know if I've ever seen a squad properly patrol". The data
# all looks right — four PatrolPaths with four points each, posture 0, route_tag
# resolving — so this watches a real one for a minute and says how far it got.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_patrol.gd
# ─────────────────────────────────────────────

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


func _init() -> void:
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
		if m != null and str(m.id) == "mutaha_2_city":
			mission = m
	if mission == null:
		print("  NO MISSION"); quit(1); return
	cm.state.selected_mission_id = mission.id
	var w := _find(root, "World")
	w.load_next_level(mission.level_scene, true)
	for _i in 420:
		await physics_frame

	var squads: Array = []
	_all(root, "Squad", squads)
	var patrols: Array = []
	for s in squads:
		if s.get("objective") == 3 or str(s.get("patrol_route")) != "<Object#null>":
			if s.get("patrol_route") != null:
				patrols.append(s)
	print("  %d squads in the level, %d of them on a patrol route" % [squads.size(), patrols.size()])
	if patrols.is_empty():
		print("  NOTHING IS PATROLLING"); quit(0); return

	var watch: Array = []
	for s in patrols:
		watch.append({"s": s, "start": s.get_center(), "prev": s.get_center(),
			"dist": 0.0, "i0": int(s.get("patrol_index")), "imax": int(s.get("patrol_index"))})
	# Two minutes of simulated patrolling.
	for f in 7200:
		await physics_frame
		if f % 60 != 0:
			continue
		for e in watch:
			var c: Vector3 = e["s"].get_center()
			e["dist"] += (c - (e["prev"] as Vector3)).length()
			e["prev"] = c
			e["imax"] = maxi(e["imax"], int(e["s"].get("patrol_index")))

	print("")
	for e in watch:
		var s = e["s"]
		var legs: int = int(s.get("patrol_index"))
		print("  %-16s walked %6.1f m in 120s · now at point %d (started %d) · objective=%s ctx=%s" % [
			str(s.callsign), e["dist"], legs, e["i0"], str(s.get("objective")), str(s.get("context"))])
	quit(0)
