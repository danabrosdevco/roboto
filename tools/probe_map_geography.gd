extends SceneTree

# ─────────────────────────────────────────────
# WHERE EVERYTHING ON EVERY MAP ACTUALLY IS.
#
# The Valley Basin defence was authored by picking tag names that SOUNDED
# right — trench_n, trench_s, tower all read as defensive and all sit 250 m
# from where the attackers come in. The garrison spent the whole fight alone at
# the wrong end of the map.
#
# So before any of the other eight get the same treatment: measure. This prints
# every anchor tag, its position, the extent of the playable area and the
# capture points, for one map or all of them.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_map_geography.gd
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_map_geography.gd -- pittsburgh
# ─────────────────────────────────────────────

const MAPS := ["hillfort", "valley_basin", "coastal-road", "salient",
	"pittsburgh", "heliostat", "polaris", "causeway", "georgetown"]


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var want: Array = [String(args[0])] if args.size() > 0 else MAPS
	for m in want:
		await _survey(String(m))
	quit(0)


func _survey(name: String) -> void:
	var path := "res://maps/%s_level.tscn" % name
	if not ResourceLoader.exists(path):
		print("\n== %s ==  (no level scene)" % name.to_upper())
		return
	var lvl: Node = load(path).instantiate()
	root.add_child(lvl)
	for _i in 60:
		await physics_frame

	var pts: Array = []
	var caps: Array = []
	var spawns: Array = []
	_scan(lvl, pts, caps, spawns)
	pts.sort_custom(func(a, b): return String(a[0]) < String(b[0]))

	# The extent of the tagged area: how big the fight actually is.
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for p in pts:
		lo = lo.min(p[1])
		hi = hi.max(p[1])

	print("")
	print("== %s ==  %d tags, %d capture points, %d squad spawns" % [
		name.to_upper(), pts.size(), caps.size(), spawns.size()])
	if pts.is_empty():
		print("   NO ANCHOR TAGS AT ALL — cannot host a generated force or sit on the board.")
		lvl.queue_free()
		await process_frame
		return
	print("   extent  x %.0f..%.0f   z %.0f..%.0f   (%.0f x %.0f m)" % [
		lo.x, hi.x, lo.z, hi.z, hi.x - lo.x, hi.z - lo.z])
	# ENTRIES are what a connection can be made of: the map's own edges.
	var entries: Array = []
	for p in pts:
		var t: String = String(p[0])
		if t.contains("_in") or t.contains("exit") or t.contains("jumpoff") \
				or t.contains("trailhead") or t.contains("pass") or t.contains("beach"):
			entries.append(p)
	print("   ENTRIES (%d) — candidate connections:" % entries.size())
	for e in entries:
		print("      %-26s %s" % [e[0], str(e[1].round())])
	print("   posts:")
	for p in pts:
		if not entries.has(p):
			print("      %-26s %s" % [p[0], str(p[1].round())])
	if not caps.is_empty():
		print("   CAPTURE POINTS already authored:")
		for c in caps:
			print("      %-26s %s" % [c[0], str(c[1].round())])
	lvl.queue_free()
	await process_frame


func _scan(n: Node, pts: Array, caps: Array, spawns: Array) -> void:
	if n is Node3D:
		if "tag" in n and String(n.tag) != "":
			pts.append([String(n.tag), (n as Node3D).global_position])
		if n is MissionObjective and n.get("id") != null and String(n.id) != "":
			caps.append([String(n.id), (n as Node3D).global_position])
		if n.is_in_group("squad_spawn_points"):
			spawns.append([n.name, (n as Node3D).global_position])
	for c in n.get_children():
		_scan(c, pts, caps, spawns)
