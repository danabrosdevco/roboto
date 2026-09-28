extends SceneTree

# ─────────────────────────────────────────────
# TEST BLOCK REACH — every deck a piece grows navmesh on, and whether the squad
# can get to it from the ground.
#
#   godot --path . --script res://tools/test_block_reach.gd
#   FOLDER=estates godot --path . --script res://tools/test_block_reach.gd
#
# NOT headless: it bakes against real collision, which needs a renderer.
#
# WHY THIS AND NOT test_block_steps.gd. That one finds a riser a body cannot
# climb. This finds the other failure: a deck that is perfectly walkable once
# you are on it and has no route up. The case that forced it was a gallery
# block whose ramp ran DIRECTLY UNDER the gallery it climbed to — 3 m of
# headroom at the bottom, none at the top, so Recast ate the top of the ramp
# and left a 68 m walkway you could see and not reach. From inside the editor
# it looks fine; the navmesh is the only thing that says otherwise.
#
# HOW. Bake the piece on a flat floor, then bucket every navmesh polygon by
# height. Any bucket above FLOOR_CLEAR with more than MIN_AREA in it is a deck
# somebody meant to stand on. Path to the middle of each from open ground.
# A deck that cannot be reached is either a ramp that wants moving or a deck
# that was never meant to be climbed — the piece's own comment says which, and
# this test only reports.
# ─────────────────────────────────────────────

## Heights are bucketed this coarsely: a deck is flat, a ramp is not.
const BUCKET := 0.75
## Below this is the ground the piece stands on, not a deck.
const FLOOR_CLEAR := 1.2
## A bucket smaller than this is a kerb or a parapet top, not somewhere to be.
const MIN_AREA := 12.0
## The path has to end this near the mark to count as arriving.
const NEAR := 3.0
## A polygon with less than this above it is not a deck, whatever the baker
## says. Recast merges coincident faces, so a slab with a solid mass sitting
## exactly on it comes out as walkable floor with the whole inside of that mass
## reading as open air above — every roof a tower stands on, every buried band.
## Nothing can stand in 0 m of headroom, so nothing there is a deck.
const HEADROOM := 1.9

var nav_map: RID


func _initialize() -> void:
	await process_frame
	var families: Array = []
	if OS.get_environment("FOLDER") != "":
		families = [OS.get_environment("FOLDER")]
	else:
		for d in DirAccess.get_directories_at("res://maps/blocks"):
			if d != "autosave":
				families.append(d)
		families.sort()
	print("   a deck is %.2f m of height bucket with over %.0f m2 in it, above %.1f m" % [
			BUCKET, MIN_AREA, FLOOR_CLEAR])
	var bad := 0
	for fam: String in families:
		var dir := "res://maps/blocks/%s" % fam
		var names: Array = []
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				names.append(f.get_basename())
		names.sort()
		for n: String in names:
			bad += await _check(dir, n)
	print("   %d piece(s) with a deck the squad cannot reach" % bad)
	quit()


func _check(dir: String, piece_name: String) -> int:
	var packed := load(dir.path_join(piece_name + ".tscn")) as PackedScene
	if packed == null:
		return 0
	var world := Node3D.new()
	root.add_child(world)
	var region := NavigationRegion3D.new()
	world.add_child(region)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.6
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.region_min_size = 4.0
	# STATIC COLLIDERS, not mesh instances. A brush prefab's visual mesh is a
	# hollow box, so Recast reads the inside of every building as a room and
	# lays a floor on the top of every slab in it — the first run of this called
	# all sixteen pieces broken and listed five 670 m2 decks inside a solid
	# block. The collision shapes are convex hulls and fill.
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.filter_baking_aabb = AABB(Vector3(-90.0, -6.0, -90.0), Vector3(180.0, 60.0, 180.0))
	region.navigation_mesh = nm
	var floor_body := StaticBody3D.new()
	region.add_child(floor_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(180.0, 1.0, 180.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(cs)
	var piece := packed.instantiate() as Node3D
	region.add_child(piece)
	for _i in 6:
		await physics_frame
	region.bake_navigation_mesh(false)
	for _i in 8:
		await physics_frame
	nav_map = region.get_navigation_map()
	var space := world.get_world_3d().direct_space_state
	var mesh: NavigationMesh = region.navigation_mesh
	var verts := mesh.get_vertices()

	# Bucket the polygons by height, keeping each bucket's area and its biggest
	# polygon's middle to aim at.
	var decks := {}
	for i in mesh.get_polygon_count():
		var poly := mesh.get_polygon(i)
		if poly.size() < 3:
			continue
		var mid := Vector3.ZERO
		for idx in poly:
			mid += verts[idx]
		mid /= poly.size()
		var area := 0.0
		for k in range(1, poly.size() - 1):
			area += _tri_area(verts[poly[0]], verts[poly[k]], verts[poly[k + 1]])
		if mid.y < FLOOR_CLEAR:
			continue
		var up := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 0.25,
				mid + Vector3.UP * (HEADROOM + 0.25))
		# hit_from_inside, or the ray starting inside the mass that is sitting on
		# this slab reports nothing and the phantom deck survives the filter.
		up.hit_from_inside = true
		if space.intersect_ray(up).has("position"):
			continue
		var key := int(roundf(mid.y / BUCKET))
		var row: Array = decks.get(key, [0.0, 0.0, Vector3.ZERO])
		row[0] += area
		if area > row[1]:
			row[1] = area
			row[2] = mid
		decks[key] = row

	# Stand on open ground off the corner of the piece and walk to each.
	var from := NavigationServer3D.map_get_closest_point(nav_map, Vector3(72.0, 0.0, 72.0))
	var keys: Array = decks.keys()
	keys.sort()
	var lost: Array = []
	for key: int in keys:
		var row: Array = decks[key]
		if float(row[0]) < MIN_AREA and OS.get_environment("VERBOSE") == "":
			continue
		var to: Vector3 = row[2]
		var b := NavigationServer3D.map_get_closest_point(nav_map, to)
		var route := NavigationServer3D.map_get_path(nav_map, from, b, true)
		var miss: float = (route[route.size() - 1] as Vector3).distance_to(b) if route.size() > 0 else 999.0
		if OS.get_environment("VERBOSE") != "":
			var stop: Vector3 = route[route.size() - 1] if route.size() > 0 else Vector3.ZERO
			print("      %-4s %5.1f m %6.0f m2 at (%6.1f,%6.1f)  path stops at (%6.1f,%6.1f,%6.1f)" % [
					"ok" if miss < NEAR else "CUT", to.y, row[0], to.x, to.z, stop.x, stop.y, stop.z])
		if miss >= NEAR:
			lost.append("%.1f m deck %.0f m2 at (%.0f, %.0f)" % [to.y, row[0], to.x, to.z])
	world.queue_free()
	await process_frame
	if lost.is_empty():
		return 0
	print("   %-34s %s" % ["%s/%s" % [dir.get_file(), piece_name], ", ".join(lost)])
	return 1


func _tri_area(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b - a).cross(c - a).length() * 0.5
