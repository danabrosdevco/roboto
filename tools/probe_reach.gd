extends SceneTree
# With the river carved out, can the squad still GET to everything? Removing the
# bed is only correct if the crossings actually connect the banks.
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	for map in ["pittsburgh", "salient"]:
		var packed := load("res://maps/%s_level.tscn" % map) as PackedScene
		if packed == null:
			continue
		var level: Node3D = packed.instantiate()
		root.add_child(level)
		for _i in 30:
			await physics_frame
		var region: NavigationRegion3D = _first(level, "NavigationRegion3D")
		if region == null:
			print("  %s: no navigation region" % map)
			level.free(); continue
		var map_rid := region.get_navigation_map()
		var spawn: Vector3 = Vector3.ZERO
		for n in _all(level):
			if n.get_class() == "Node3D" and String(n.name).contains("Spawn") and n is Node3D:
				spawn = (n as Node3D).global_position
				break
		var from := NavigationServer3D.map_get_closest_point(map_rid, spawn)
		print("")
		print("  %s — reachability from %s" % [map, str(from.snapped(Vector3.ONE))])
		for n in _all(level):
			var id = n.get("id")
			if id == null or String(id) == "":
				continue
			var to := NavigationServer3D.map_get_closest_point(map_rid, (n as Node3D).global_position)
			var path := NavigationServer3D.map_get_path(map_rid, from, to, true)
			var ok: bool = path.size() > 1 and path[path.size() - 1].distance_to(to) < 6.0
			print("     %-26s %s   (%d hops, ends %.1f m away)" % [String(id),
				"reachable" if ok else "UNREACHABLE", path.size(),
				path[path.size() - 1].distance_to(to) if path.size() > 0 else -1.0])
		level.free()
		for _i in 6:
			await physics_frame
	quit(0)

func _first(n: Node, cls: String) -> Node:
	for c in _all(n):
		if c.is_class(cls):
			return c
	return null

func _all(n: Node) -> Array:
	var out: Array = [n]
	var i := 0
	while i < out.size():
		for c in (out[i] as Node).get_children():
			out.append(c)
		i += 1
	return out
