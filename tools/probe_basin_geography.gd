extends SceneTree

# Where everything on Valley Basin actually IS. The defence was authored by
# picking tag names that sounded right — the garrison ended up in the trenches,
# far from where the attackers came in. Measure first.

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var lvl: Node = load("res://maps/valley_basin_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 90:
		await physics_frame

	var pts: Array = []
	_scan(lvl, pts)
	pts.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	print("")
	print("%-28s %-30s %s" % ["tag", "position", "node"])
	print("-".repeat(86))
	for p in pts:
		print("%-28s %-30s %s" % [p[0], str(p[1].round()), p[2]])

	print("")
	print("CORES (what a defence is fought over):")
	var slice = lvl.get_node_or_null(^"BasinSlice")
	if slice != null:
		for c in slice.cores:
			print("  %-22s %s" % [c.get_parent().name, str(c.get_parent().global_position.round())])
		var b = slice.get_node_or_null(^"BasinBunker")
		if b != null:
			print("  %-22s %s" % ["BUNKER", str(b.global_position.round())])
	quit(0)


func _scan(n: Node, out: Array) -> void:
	if "tag" in n and String(n.tag) != "" and n is Node3D:
		out.append([String(n.tag), (n as Node3D).global_position, n.get_class()])
	for c in n.get_children():
		_scan(c, out)
