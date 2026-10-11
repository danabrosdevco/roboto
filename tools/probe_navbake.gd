extends SceneTree
# ─────────────────────────────────────────────
# WHAT WOULD A COARSER NAVMESH BAKE BUY ON QAMAREEN?
#
# map_get_closest_point walks every polygon in the map, and Qamareen's mesh is
# 33,160 of them — which is the 0.745 ms a query, against 0.025 ms on the
# proving ground. cell_size is the lever: it is the voxel the mesh is built
# from, so doubling it cuts the polygon count roughly fourfold.
#
# NOTHING IS SAVED. This bakes into memory to put a number on the trade before
# anyone touches a level file.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_navbake.gd
# ─────────────────────────────────────────────

func _all(n: Node, cls: String, out: Array) -> void:
	if n.get_class() == cls:
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)


func _time_queries(map: RID) -> float:
	var t0 := Time.get_ticks_usec()
	for i in 200:
		NavigationServer3D.map_get_closest_point(map,
			Vector3(randf_range(-400, 400), 0, randf_range(-400, 400)))
	return float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var lvl: Node = load("res://maps/mutaha_wip_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 180:
		await physics_frame

	var regions: Array = []
	_all(lvl, "NavigationRegion3D", regions)
	if regions.is_empty():
		print("  NO NavigationRegion3D"); quit(1); return
	var region: NavigationRegion3D = regions[0]
	var nm: NavigationMesh = region.navigation_mesh
	var map := region.get_navigation_map()

	print("")
	print("  AS BAKED   cell_size %.3f   %d polygons   query %.3f ms" % [
		nm.cell_size, nm.get_polygon_count(), _time_queries(map)])

	for cs in [0.4, 0.5, 0.75]:
		var copy: NavigationMesh = nm.duplicate(true)
		copy.cell_size = cs
		# agent_radius has to stay reachable from the cell grid, or the bake
		# erodes the whole mesh away.
		copy.agent_radius = maxf(nm.agent_radius, cs)
		region.navigation_mesh = copy
		region.bake_navigation_mesh(false)
		for _i in 120:
			await physics_frame
		print("  cell %.2f   agent_r %.2f   %d polygons   query %.3f ms" % [
			cs, copy.agent_radius, copy.get_polygon_count(), _time_queries(map)])
	print("")
	print("  (nothing written — this was a memory-only bake)")
	quit(0)
