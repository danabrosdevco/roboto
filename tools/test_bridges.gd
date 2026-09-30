extends SceneTree

# ─────────────────────────────────────────────
# BRIDGE TESTS
#
# A bridge the squad cannot walk onto is a wall across the river, and nothing
# says so until someone orders a squad over it and it goes the long way round
# or stands still. It takes very little: long_bridge.map's ramps stop 0.5 m
# above its origin, so on flat ground at that height they end in a lip twice
# what the navmesh will climb.
#
# Each prefab in maps/blocks/bridges/ is baked into a navmesh on two banks
# with a river between them under the middle of the span: once with the
# banks at the prefab's origin, and once LOW_BANK lower, the depth the ramps
# are built to reach below the origin. The squad has to walk from well off
# each end onto the middle of the deck; on a divided deck, onto each side of
# it. And no raised patch of navmesh on a bridge may be out of its reach: the
# baker sees surfaces, not solids, so a pier's top under a tall cap once baked
# as a floor sealed inside the cap.
# ─────────────────────────────────────────────

const DIR := "res://maps/blocks/bridges"
const LOW_BANK := -0.45
## The river between the banks: the middle part of the bridge's length. Every
## bridge's ramps and approaches together take up less than 60% of it.
const RIVER_SHARE := 0.4
## A script error inside a check ends that coroutine without reaching quit(),
## and a headless SceneTree then idles for ever. The watchdog makes that loud.
const WATCHDOG_S := 300

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s — a check probably crashed (see SCRIPT ERROR above)" % WATCHDOG_S)
		quit(2))
	await process_frame
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
	files.sort()
	_check("there are bridge prefabs in %s" % DIR, not files.is_empty())
	for f: String in files:
		for bank: float in [0.0, LOW_BANK]:
			await _cross(DIR.path_join(f), bank)
	print("")
	print("ALL BRIDGE CHECKS PASS" if _fails == 0 else "%d BRIDGE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Bakes the bridge at `path` between two banks `bank` up, with the river
## under the middle of it, and walks onto the deck from each end.
func _cross(path: String, bank: float) -> void:
	var name := path.get_file().get_basename()
	var packed := load(path) as PackedScene
	if packed == null:
		_check("%s loads" % name, false, "load(%s) returned null" % path)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	var region := NavigationRegion3D.new()
	# The levels' agent: see NavigationMesh_mutaha in maps/mutaha_level.tscn.
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.region_min_size = 8.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh = nm
	stage.add_child(region)
	var bridge := packed.instantiate() as Node3D
	region.add_child(bridge)
	var box := _footprint(bridge)
	if box.size == Vector3.ZERO:
		_check("%s has collision to walk on" % name, false, "no convex collision shapes in it")
		root.remove_child(stage)
		stage.free()
		return
	# Two banks, one off each end, meeting the river a fifth of the way in.
	var half := box.size.z * 0.5
	var river := box.size.z * RIVER_SHARE * 0.5
	for dir: float in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(box.size.x + 60.0, 1.0, half - river + 30.0)
		shape.shape = b
		body.add_child(shape)
		body.position = Vector3(box.get_center().x, bank - 0.5, dir * (river + (half - river + 30.0) * 0.5))
		region.add_child(body)
	region.bake_navigation_mesh(false)
	for _i in 3:
		await physics_frame
	var map := region.get_navigation_map()
	var label := "%s, banks %+.2f m" % [name, bank]
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(box.get_center().x, bank, -(half + 20.0)))
	var finish := NavigationServer3D.map_get_closest_point(map, Vector3(box.get_center().x, bank, half + 20.0))
	var decks := _deck_targets(map, box, bank)
	if decks.is_empty():
		_check("%s: a walkable deck over the river" % label, false, "no navmesh under probes over the middle of the span")
	for target: Vector3 in decks:
		var worst := 0.0
		var detail := ""
		for from: Vector3 in [start, finish]:
			var route := NavigationServer3D.map_get_path(map, from, target, true)
			var end: Vector3 = route[route.size() - 1] if route.size() > 0 else from
			var miss := end.distance_to(target)
			worst = maxf(worst, miss)
			detail += "  from the %s end: %d points, ends %.1f m from the deck" % ["-Z" if from.z < 0.0 else "+Z", route.size(), miss]
		_check("%s: onto the deck %.2f m up at (%.1f, %.1f) from both ends" % [label, target.y - bank, target.x, target.z], worst < 1.0, detail)
	# Nothing raised on the bridge that the squad cannot get to: a patch of
	# navmesh it cannot reach is a place an order can snap to and never arrive.
	# (A pier's top under a tall cap baked as one, inside the cap.)
	var stranded: Array = []
	var verts := nm.get_vertices()
	for i in nm.get_polygon_count():
		var idx := nm.get_polygon(i)
		var c := Vector3.ZERO
		for v in idx:
			c += verts[v]
		c /= idx.size()
		if c.y < bank + 0.75 or not _over(box, c):
			continue   # down on a bank, or off the bridge
		var route := NavigationServer3D.map_get_path(map, start, c, true)
		if route.size() == 0 or route[route.size() - 1].distance_to(c) > 1.0:
			stranded.append(c.snapped(Vector3(0.1, 0.1, 0.1)))
	_check("%s: every walkable surface on it can be reached" % label, stranded.is_empty(),
			"%d stranded polygon(s), e.g. at %s" % [stranded.size(), str(stranded.slice(0, 3))])
	root.remove_child(stage)
	stage.free()
	await process_frame


## Where to stand on the deck: the navmesh under probes held above the middle
## of the span, a quarter of the way out each side of the centreline. On a
## divided deck, as a highway's is by its median, that is one each side; a
## probe with no deck under it (over a shell hole) finds nothing.
func _deck_targets(map: RID, box: AABB, bank: float) -> Array:
	var out: Array = []
	var d := clampf(box.size.x / 8.0, 0.5, 3.0)
	for side: float in [-1.0, 1.0]:
		var probe := Vector3(box.get_center().x + side * d, box.end.y + 2.0, box.get_center().z)
		var p := NavigationServer3D.map_get_closest_point(map, probe)
		if Vector2(p.x - probe.x, p.z - probe.z).length() < 1.5 and p.y > bank + 0.5:
			out.append(p)
	return out


## Whether p lies over the bridge's footprint.
func _over(box: AABB, p: Vector3) -> bool:
	return p.x >= box.position.x and p.x <= box.end.x and p.z >= box.position.z and p.z <= box.end.z


## The world box round every convex collision shape in `n`.
func _footprint(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if not (cs.shape is ConvexPolygonShape3D):
			continue
		var xf := Transform3D.IDENTITY
		var node: Node = cs
		while node != n:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		for q: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
			var p := xf * q
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box
