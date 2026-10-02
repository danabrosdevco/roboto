extends SceneTree
# How expensive is one navigation query on Qamareen's mesh?
# map_get_closest_point walks every polygon in the map, so its cost scales with
# the SIZE OF THE LEVEL, not with how many robots are asking.

func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	for row in [["mutaha_wip_level (Qamareen)", "res://maps/mutaha_wip_level.tscn"],
				["proving_level (small)", "res://maps/proving_level.tscn"]]:
		var lv: Node = load(row[1]).instantiate()
		level.add_child(lv)
		for _i in 180:
			await physics_frame
		var map := player.get_world_3d().navigation_map
		var polys := 0
		for r in NavigationServer3D.map_get_regions(map):
			polys += NavigationServer3D.region_get_connections_count(r)
		var t0 := Time.get_ticks_usec()
		for i in 200:
			NavigationServer3D.map_get_closest_point(map, Vector3(randf_range(-300, 300), 0, randf_range(-300, 300)))
		var us := float(Time.get_ticks_usec() - t0) / 200.0
		print("  %-30s closest_point %6.3f ms   (%d region edges)" % [row[0], us / 1000.0, polys])
		lv.queue_free()
		for _i in 30:
			await physics_frame
	quit(0)
