extends RefCounted

# ─────────────────────────────────────────────
# ISLANDS OUT OF THE NAVMESH
#
# Walkable ground nobody can walk to is not free — it is the most expensive
# thing in the game. A path request to an unreachable polygon does not fail
# fast: Recast's A* expands until it has exhausted every polygon it can reach
# before admitting there is no route. Measured on Three Rivers, 38k polygons:
#
#     a real path, 800 m across the map ..........   342 ms
#     a path to the cut-off island, 70 m away ....  1,095 ms
#     the same island, asked from 800 m away .....  1,090 ms
#
# Distance is cheap. Impossibility costs a second, every time anything asks —
# a squad ordered onto it, a robot acquiring a target standing on it, a spawn
# snapping to it. That is the 1,068 ms frame in the Ohio works fight.
#
# The bake cannot prevent this. `region_min_size` culls small regions while
# Recast runs, but the island is often made AFTER the bake: water_navmesh.gd
# carves the river beds at load, and every bank and mid-stream island it
# severs becomes exactly this. So the carve is where the sweeping belongs —
# right after it, at load, on whatever the level actually ended up with.
#
# What survives is what the squad can reach on foot from where it lands.
# Flying units never touch the navmesh, and neither does the player, so
# nothing else is affected by the ground going away.
# ─────────────────────────────────────────────

## Anything less than this share of the walkable area reaching the spawn means
## the spawn is the odd one out — a point stranded on a ledge, or a level whose
## start sits on its own platform. Stripping everything else would delete the
## map, so the pass refuses and says so instead.
const MIN_KEPT_SHARE := 0.5


## Drops every navmesh polygon in `region` that cannot be walked to from
## `from`, and returns what went: {"dropped": int, "area": float, "kept": int}.
## The mesh is duplicated rather than edited, because a navmesh embedded in a
## scene is shared by every instance of it (the same reason water_navmesh.gd
## duplicates).
static func strip(region: NavigationRegion3D, from: Vector3) -> Dictionary:
	var nothing := {"dropped": 0, "area": 0.0, "kept": 0}
	if region == null:
		return nothing
	var mesh := region.navigation_mesh
	if mesh == null:
		return nothing
	var verts := mesh.get_vertices()
	var count := mesh.get_polygon_count()
	if verts.is_empty() or count == 0:
		return nothing

	# ── Which polygons touch which ──
	# A SHARED EDGE, not a shared vertex. Detour walks from one polygon to the
	# next across an edge they both own; two that meet at a single corner are
	# no more connected than two that do not touch at all. Grouping by vertex
	# instead quietly keeps those corner-touching pockets, and a pocket is the
	# worst thing to keep — the East Ford garrison on Mutaha stood in one and
	# every four-metre path it asked for cost 500 ms.
	#
	# This holds because every level in the project bakes into a single region;
	# a second region would join across an edge-connection margin instead, with
	# no shared indices, and this pass would wrongly strip it.
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	var by_edge := {}
	for i in count:
		var poly := mesh.get_polygon(i)
		for k in poly.size():
			var v0: int = poly[k]
			var v1: int = poly[(k + 1) % poly.size()]
			var key := (mini(v0, v1) << 32) | maxi(v0, v1)
			if by_edge.has(key):
				var other: int = by_edge[key]
				var a := _root(other, parent)
				var b := _root(i, parent)
				if a != b:
					parent[b] = a
			else:
				by_edge[key] = i

	# ── Which component the squad lands on ──
	var seed_local: Vector3 = region.to_local(from)
	var home := -1
	var home_gap := INF
	var areas := {}
	for i in count:
		var poly := mesh.get_polygon(i)
		var mid := Vector3.ZERO
		var area := 0.0
		for k in range(1, poly.size() - 1):
			var a: Vector3 = verts[poly[0]]
			var b: Vector3 = verts[poly[k]]
			var c: Vector3 = verts[poly[k + 1]]
			area += (b - a).cross(c - a).length() * 0.5
		for v in poly:
			mid += verts[v]
		mid /= float(poly.size())
		var r := _root(i, parent)
		areas[r] = float(areas.get(r, 0.0)) + area
		var gap := Vector2(mid.x - seed_local.x, mid.z - seed_local.z).length()
		if gap < home_gap:
			home_gap = gap
			home = r
	if home < 0:
		return nothing

	var total := 0.0
	for r in areas:
		total += float(areas[r])
	var kept_area := float(areas.get(home, 0.0))
	if total <= 0.0 or kept_area / total < MIN_KEPT_SHARE:
		push_warning(("navmesh_islands: %s left only %.0f m2 of %.0f reachable from the spawn, " +
			"so the sweep was refused — the spawn point is probably off on its own.") % [
				region.name, kept_area, total])
		return nothing

	# ── Sweep ──
	var kept := mesh.duplicate() as NavigationMesh
	kept.clear_polygons()
	kept.set_vertices(verts)
	var dropped := 0
	for i in count:
		if _root(i, parent) == home:
			kept.add_polygon(mesh.get_polygon(i))
		else:
			dropped += 1
	if dropped == 0:
		return nothing
	region.navigation_mesh = kept
	return {"dropped": dropped, "area": total - kept_area, "kept": count - dropped}


static func _root(i: int, parent: PackedInt32Array) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	while parent[i] != r:
		var next := parent[i]
		parent[i] = r
		i = next
	return r
