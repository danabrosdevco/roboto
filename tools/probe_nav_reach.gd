extends SceneTree

# ─────────────────────────────────────────────
# CAN THE SQUAD ACTUALLY GET THERE?
#
#   LEVEL=res://maps/georgetown_level.tscn godot --path . \
#       --script res://tools/probe_nav_reach.gd
#
# NOT headless: a level with no renderer has no navmesh worth asking about,
# and this reads the one baked into the scene.
#
# WHY THIS EXISTS. move_and_slide has no step-up of its own, so a robot walks
# up anything under enemy.gd's step_height of 0.45 m and ANY vertical face
# above that is a wall wanting a ramp. A map built in terraces lives or dies
# on whether the stairs and ramps between them actually connect — and the way
# that fails is silent. The navmesh bakes, the level loads, every bench has
# navmesh on it, and the squad simply never goes anywhere because the bench it
# is standing on is an island.
#
# So this asks three things, in order of how badly each one hurts:
#
#   1. HOW MUCH OF THE MAP IS ONE PIECE. Sample a grid over the site, snap
#      each point to the navmesh, and path to it from the spawn. The number
#      that matters is the share that comes back reachable; islands are the
#      defect and they do not announce themselves.
#   2. IS EVERY OBJECTIVE REACHABLE. An objective on an island is a mission
#      that cannot be completed and nothing says so until someone plays it.
#   3. WHAT DID IT COST. Path length against straight-line distance. A ratio
#      near 1 on a terraced map means the squad is walking THROUGH the
#      terraces rather than round to a stair, which means a wall somewhere is
#      climbable and was not meant to be.
#
# It changes nothing. Bake first with:
#   BAKE_ONLY=1 LEVEL=... godot --path . --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

## How far a path end may be from the point asked for and still count as
## arrived. Godot returns the closest reachable point rather than failing, so
## this threshold IS the reachability test.
const ARRIVED := 6.0
## Grid pitch for the coverage sweep.
const STEP := 16.0
## A sample further than this from any navmesh is not a hole in the map, it is
## off the edge of it, and is not counted either way.
const ON_MESH := 3.0

var map: RID


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn godot --path . --script res://tools/probe_nav_reach.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var region: NavigationRegion3D = level.get_node_or_null("NavigationRegion3D")
	if region == null:
		print("FAIL  %s has no NavigationRegion3D" % level_path.get_file())
		quit(1)
		return
	var nav := region.navigation_mesh
	print("   %s — %d vertices, %d polygons" % [level_path.get_file(),
			nav.get_vertices().size(), nav.get_polygon_count()])
	if nav.get_polygon_count() == 0:
		print("FAIL  the navmesh in the scene is empty — bake it first")
		quit(1)
		return
	map = region.get_navigation_map()
	var spawn: Node3D = level.get_node_or_null("SpawnPoint")
	if spawn == null:
		print("FAIL  %s has no SpawnPoint" % level_path.get_file())
		quit(1)
		return
	var from := _snap(spawn.global_position)
	print("   spawn at %s" % _s(from))

	var fails := 0
	fails += _coverage(nav, from)
	fails += _objectives(level, from)
	print("REACH %s" % ("PASS" if fails == 0 else "FAIL — %d problem(s)" % fails))
	quit(1 if fails > 0 else 0)


func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, p)


func _s(p: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [p.x, p.y, p.z]


## Path from `from` to `to`, and where it actually ended up.
func _walk(from: Vector3, to: Vector3) -> Dictionary:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return {"ok": false, "end": from, "len": 0.0}
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var end: Vector3 = path[path.size() - 1]
	return {"ok": end.distance_to(to) <= ARRIVED, "end": end, "len": total}


## THE ONE THAT MATTERS. Sweep a grid over the navmesh's own bounds, keep the
## samples that are actually on it, and path to each from the spawn. Anything
## that will not path is on an island.
func _coverage(nav: NavigationMesh, from: Vector3) -> int:
	var verts := nav.get_vertices()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v: Vector3 in verts:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	var on := 0
	var reached := 0
	var stranded: Array = []
	# Keep off the outer edge. The last row of samples sits exactly on the rim
	# of the ground slabs, where the baker has already eroded the walkable
	# area away by the agent radius — they come back unreachable on every map
	# and they are the edge of the world, not an island in it.
	lo += Vector3(STEP, 0.0, STEP)
	hi -= Vector3(STEP, 0.0, STEP)
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			var want := Vector3(x, (lo.y + hi.y) * 0.5, z)
			var p := _snap(want)
			# Only count a sample that is really standing on the mesh: the
			# closest point to somewhere off the edge is the edge itself, and
			# counting those would call the map 100% reachable every time.
			if Vector2(p.x - x, p.z - z).length() <= ON_MESH:
				on += 1
				if _walk(from, p).ok:
					reached += 1
				elif stranded.size() < 8:
					stranded.append(p)
			z += STEP
		x += STEP
	if on == 0:
		print("   FAIL  no sample landed on the navmesh at all")
		return 1
	var share := 100.0 * reached / float(on)
	print("   coverage: %d of %d samples reachable from the spawn — %.1f%%" % [reached, on, share])
	for p: Vector3 in stranded:
		print("      stranded near %s" % _s(p))
	# WHAT COUNTS AS A FAILURE HERE. Flat roofs bake as walkable and most have
	# no way up, so a map with buildings on it never reads 100% — and chasing
	# that number means either giving every roof a stair or stopping roofs
	# baking at all, and neither is worth it. An unreachable ROOF is not a
	# broken map; an unreachable OBJECTIVE is, and that is what fails below.
	# This only fires when the ground itself has come apart.
	if share < 70.0:
		print("   FAIL  only %.1f%% of the walkable map is reachable — the ground is in pieces" % share)
		return 1
	if share < 95.0:
		print("   note: the rest should be roofs — check the stranded list for any at ground height")
	return 0


## Every objective anchor, and what the walk to it cost.
func _objectives(level: Node3D, from: Vector3) -> int:
	var holder := level.get_node_or_null("NavigationRegion3D/Objectives")
	if holder == null:
		print("   (no Objectives group — skipping)")
		return 0
	var bad := 0
	for o in holder.get_children():
		var want: Vector3 = (o as Node3D).global_position
		var p := _snap(want)
		var off := want.distance_to(p)
		var r := _walk(from, p)
		var direct := from.distance_to(p)
		var ratio: float = r.len / direct if direct > 0.5 else 1.0
		var note := ""
		if not r.ok:
			note = "  UNREACHABLE, got to %s" % _s(r.end)
			bad += 1
		elif off > 4.0:
			# The anchor is in the air or inside something. Not fatal — the
			# squad walks to the nearest floor — but it is worth saying,
			# because an objective that snaps 10 m away is in a wall.
			note = "  (anchor is %.1f m off the mesh)" % off
		print("   %-16s %6.0f m walk / %5.0f m direct  x%.2f%s" % [o.name, r.len, direct, ratio, note])
	return bad
