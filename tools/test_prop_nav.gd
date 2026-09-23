extends SceneTree

# ─────────────────────────────────────────────
# TEST PROP NAV — what does a prop actually do to a navmesh?
#
#   godot --path . --script res://tools/test_prop_nav.gd
#
# NOT headless: it bakes and raycasts, which need a real renderer to have
# built the collision. It opens a window for a few seconds.
# ─────────────────────────────────────────────
#
#
# Two complaints to measure, not guess at: the rubble pile grows navmesh over
# the top of it that nothing can climb onto, and things get stuck on the jersey
# barrier instead of walking round it. So: stand the prop on a flat 24 m floor,
# bake with a LEVEL's settings, and report
#
#   * how much walkable area ended up ABOVE the floor (navmesh on the prop),
#   * how wide the hole it carves in the floor is against its own footprint
#     (too narrow and an agent wider than the bake radius clips the corner),
#   * and whether a walk across it goes round or straight through.
#
#   PROPS="prop_rubble_pile,..."  [RADIUS=0.6]  [MINREGION=8]
#
# A prop is WRONG if it has any area "on top": that is navmesh standing on the
# prop, and a squad sent to it either cannot get there or gets there and
# cannot leave. A prop is SUSPECT if its carve is much less than its footprint
# plus twice the agent radius, which means the mesh is running over its skirt.
const PROP := "res://maps/blocks/props/%s.tscn"
const HALF := 12.0

var region: NavigationRegion3D


func _initialize() -> void:
	await process_frame
	var radius := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 0.5
	var names := OS.get_environment("PROPS").split(",") if OS.get_environment("PROPS") != "" else _all_props()
	print("   agent radius %.2f m, climb 0.25 m, slope 45 deg, cell 0.25 m, region_min_size %s" % [radius, OS.get_environment("MINREGION") if OS.get_environment("MINREGION") != "" else "2"])
	print("   %-24s %8s %8s %9s %7s  %s" % ["prop", "on top", "carve", "footprint", "walk", "highest"])
	for n: String in names:
		await _measure(n.strip_edges(), radius)
	quit()


func _measure(prop_name: String, radius: float) -> void:
	var world := Node3D.new()
	root.add_child(world)
	region = NavigationRegion3D.new()
	world.add_child(region)
	var nm := NavigationMesh.new()
	nm.agent_radius = radius
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.region_min_size = float(OS.get_environment("MINREGION")) if OS.get_environment("MINREGION") != "" else 2.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.filter_baking_aabb = AABB(Vector3(-HALF, -4.0, -HALF), Vector3(HALF * 2.0, 20.0, HALF * 2.0))
	region.navigation_mesh = nm

	# A flat floor to stand it on.
	var floor_body := StaticBody3D.new()
	region.add_child(floor_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(cs)

	var packed := load(PROP % prop_name) as PackedScene
	if packed == null:
		print("   %-24s could not load" % prop_name)
		world.queue_free()
		return
	var prop := packed.instantiate() as Node3D
	region.add_child(prop)
	for _i in 8:
		await physics_frame
	var foot := _footprint(prop)
	region.bake_navigation_mesh(false)
	for _i in 4:
		await physics_frame

	# Walkable area above the floor: navmesh sitting ON the prop.
	var baked := region.navigation_mesh
	var verts := baked.get_vertices()
	# Recast puts the mesh a cell height above the surface it walks, so "on the
	# prop" is measured against where the FLOOR came out, not against zero.
	var floor_y := INF
	for p in baked.get_polygon_count():
		var poly := baked.get_polygon(p)
		var m := 0.0
		for i in poly.size():
			m += verts[poly[i]].y
		floor_y = minf(floor_y, m / poly.size())
	var above := 0.0
	var total := 0.0
	var high := floor_y
	for p in baked.get_polygon_count():
		var poly := baked.get_polygon(p)
		var a := 0.0
		var mean_y := 0.0
		for i in range(1, poly.size() - 1):
			var v0 := verts[poly[0]]
			var v1 := verts[poly[i]]
			var v2 := verts[poly[i + 1]]
			a += absf((v1.x - v0.x) * (v2.z - v0.z) - (v2.x - v0.x) * (v1.z - v0.z)) * 0.5
		for i in poly.size():
			mean_y += verts[poly[i]].y
		mean_y /= poly.size()
		total += a
		if mean_y > floor_y + 0.4:
			above += a
			high = maxf(high, mean_y)

	# How wide is the hole it punches in the floor, across the prop's short
	# axis? Sample the navmesh along a line through the middle.
	var map := region.get_navigation_map()
	var gap := 0.0
	for i in 241:
		var x: float = -6.0 + i * 0.05
		var p := Vector3(x, 0.0, 0.0)
		var near := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(near.x - p.x, near.z - p.z).length() > 0.2:
			gap += 0.05

	# And does a walk across it go round, or is it simply not in the way?
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(-8.0, 0.0, 0.0))
	var to := NavigationServer3D.map_get_closest_point(map, Vector3(8.0, 0.0, 0.0))
	var route := NavigationServer3D.map_get_path(map, from, to, true)
	var walked := 0.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
	print("   %-24s %6.1f m2 %6.2f m %6.2f m  %5.1f m  up to %.1f m" % [
			prop_name, above, gap, foot, walked, high - floor_y])
	world.queue_free()
	await process_frame


## The prop's own width across x, from its collision shapes.
func _footprint(prop: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for cs in prop.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (cs as CollisionShape3D).shape
		if shape == null:
			continue
		var aabb := shape.get_debug_mesh().get_aabb()
		var t := (cs as CollisionShape3D).global_transform
		for i in 8:
			var corner := aabb.get_endpoint(i)
			var w := t * corner
			lo = minf(lo, w.x)
			hi = maxf(hi, w.x)
	return hi - lo if hi > lo else 0.0


## Every prop in the folder, so the default run is a sweep.
func _all_props() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://maps/blocks/props"):
		if f.ends_with(".tscn"):
			out.append(f.get_basename())
	return out
