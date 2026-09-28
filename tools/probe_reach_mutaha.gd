extends SceneTree

# ─────────────────────────────────────────────
# REACH — walk from the spawn to every objective anchor in a level and say how
# far it is, so a mission can be written against places the squad can actually
# get to.
#
#   godot --path . --script res://tools/probe_reach_mutaha.gd
#   LEVEL=res://maps/mutaha_level.tscn godot --path . --script res://tools/probe_reach_mutaha.gd
#
# NOT headless: the terrain's collision and meshes have to exist.
#
# It covers every SquadObjectivePoint under EnemySquadObjs, every patrol point,
# and every capture or eliminate objective hanging off the root. Missions
# reference these by TAG, so the tag is printed beside each one: that list is
# the vocabulary a mission may use on this map.
#
# LOAD IT FRESH AND LET _READY RUN. GeneratedTerrain takes the river beds back
# out of the navmesh when the level enters the tree, and a reach report taken
# before that says the squad can wade the Mutaha.
# ─────────────────────────────────────────────

var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/mutaha_wip_level.tscn"

var map: RID


func _initialize() -> void:
	await process_frame
	var packed := ResourceLoader.load(level_path, "PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var region: NavigationRegion3D = level.get_node("NavigationRegion3D")
	map = region.get_navigation_map()
	var spawn: Node3D = level.get_node("SpawnPoint")
	var from := NavigationServer3D.map_get_closest_point(map, spawn.global_position)
	print("   %s — from the spawn at (%.0f, %.0f)" % [level_path.get_file(),
			spawn.global_position.x, spawn.global_position.z])
	print("   %-24s %-26s %-9s %8s %7s" % ["node", "tag", "state", "walked", "offset"])

	var rows: Array = []
	var squads: Node = level.get_node_or_null("EnemySquadObjs")
	if squads != null:
		for c in squads.get_children():
			var node := c as Node3D
			if node == null:
				continue
			if "tag" in node:
				rows.append([node.name, str(node.tag), node.global_position])
			for gc in node.get_children():
				var g := gc as Node3D
				if g != null and g.get_class() == "Node3D" and not ("tag" in g):
					rows.append(["  " + str(node.name) + "/" + str(g.name), "(patrol)", g.global_position])
	for c in level.get_children():
		var node := c as Node3D
		if node != null and ("id" in node) and not (node is NavigationRegion3D):
			rows.append([node.name, str(node.id), node.global_position])

	var cut := 0
	var worst := 0.0
	for r: Array in rows:
		var res := _walk(from, r[2])
		if not bool(res[0]):
			cut += 1
		worst = maxf(worst, float(res[1]))
		print("   %-24s %-26s %-9s %7.0f m %6.1f m" % [r[0], r[1],
				"reached" if res[0] else "CUT OFF", res[1], res[2]])
	print("   %d anchor(s), %d cut off, longest walk %.0f m" % [rows.size(), cut, worst])
	quit()


## [reached, metres walked, how far the mesh is from the mark]
func _walk(from: Vector3, to: Vector3) -> Array:
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var route := NavigationServer3D.map_get_path(map, from, b, true)
	var walked := 0.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
	var miss: float = (route[route.size() - 1] as Vector3).distance_to(b) if route.size() > 0 else 999.0
	return [miss < 3.0, walked, Vector2(b.x - to.x, b.z - to.z).length()]
