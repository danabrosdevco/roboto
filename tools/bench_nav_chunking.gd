extends SceneTree

# ─────────────────────────────────────────────
# DOES CHUNKING THE NAVMESH MAKE QUERIES CHEAPER?
#
# The received wisdom is "split your navmesh into sections". That is worth
# testing rather than believing, because it only pays if it reduces the work the
# query actually does — and map_get_closest_point walks the POLYGONS IN THE MAP,
# not the regions. Splitting one region into eight, all enabled on the same map,
# changes the bookkeeping and not the polygon count.
#
# So three arrangements, timed on Qamareen's real baked mesh:
#
#   ONE REGION        as shipped. The baseline.
#   EIGHT REGIONS     the same polygons, split into eight regions on the same
#                     map, all enabled. This is "chunking" as usually described.
#   ONE SMALL REGION  only the polygons within R metres of the query point —
#                     what chunking gets you ONLY IF the far chunks are disabled
#                     or unloaded.
#
# If eight regions costs the same as one, chunking on its own buys nothing and
# the win everybody is describing is really "having fewer polygons loaded".
#
# The mesh is not re-baked: polygons are read off the shipped bake and
# redistributed, so this measures the real level and nothing is written.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/bench_nav_chunking.gd
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
## Queries per timing run. Enough that one slow frame cannot colour the result.
const SAMPLES := 400


func _all(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)


## A NavigationMesh holding only `want` polygons of `src`, with its vertex list
## rebuilt so nothing dangles.
func _subset(src: NavigationMesh, want: PackedInt32Array) -> NavigationMesh:
	var verts := src.get_vertices()
	var out := NavigationMesh.new()
	out.cell_size = src.cell_size
	out.cell_height = src.cell_height
	var keep := PackedVector3Array()
	var remap := {}
	var polys: Array = []
	for pi in want:
		var poly := src.get_polygon(pi)
		var mapped := PackedInt32Array()
		for idx in poly:
			if not remap.has(idx):
				remap[idx] = keep.size()
				keep.append(verts[idx])
			mapped.append(remap[idx])
		polys.append(mapped)
	out.set_vertices(keep)
	for p in polys:
		out.add_polygon(p)
	return out


func _centroid(src: NavigationMesh, pi: int) -> Vector3:
	var verts := src.get_vertices()
	var poly := src.get_polygon(pi)
	var sum := Vector3.ZERO
	for idx in poly:
		sum += verts[idx]
	return sum / float(maxi(poly.size(), 1))


## Average microseconds for one map_get_closest_point, asked around `at`.
func _time(map: RID, at: Vector3) -> float:
	# One throwaway pass: the first query after a sync warms whatever the server
	# caches, and timing that instead of the steady state flatters nothing.
	for i in 20:
		NavigationServer3D.map_get_closest_point(map, at + Vector3(i * 0.3, 0, 0))
	var t0 := Time.get_ticks_usec()
	for i in SAMPLES:
		var jitter := Vector3(sin(i) * 25.0, 0.0, cos(i) * 25.0)
		NavigationServer3D.map_get_closest_point(map, at + jitter)
	return float(Time.get_ticks_usec() - t0) / float(SAMPLES)


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var level = load(LEVEL).instantiate()
	root.add_child(level)
	for _i in 30:
		await physics_frame

	var regions: Array = []
	_all(level, "NavigationRegion3D", regions)
	if regions.is_empty():
		printerr("bench_nav_chunking: %s has no NavigationRegion3D." % LEVEL)
		quit(1)
		return
	var region := regions[0] as NavigationRegion3D
	var src := region.navigation_mesh
	var map := region.get_navigation_map()
	var total := src.get_polygon_count()

	# Somewhere with navmesh under it, so every arrangement is asked the same
	# question from the same place.
	var at := _centroid(src, total / 2)

	print("Qamareen — %d polygons, cell_size %.2f" % [total, src.cell_size])
	print("one query = NavigationServer3D.map_get_closest_point, averaged over %d" % SAMPLES)
	print("")

	var base := _time(map, at)
	print("  ONE REGION, as shipped          %6d polys   %7.1f us" % [total, base])

	# EIGHT REGIONS, same map, all enabled. Polygons are dealt out round-robin so
	# each region is a real slice rather than a contiguous lump — the arrangement
	# is what is under test, not the shape of the slices.
	var buckets: Array = []
	for i in 8:
		buckets.append(PackedInt32Array())
	for pi in total:
		buckets[pi % 8].append(pi)
	region.enabled = false
	var extra: Array[NavigationRegion3D] = []
	for b in buckets:
		var r := NavigationRegion3D.new()
		r.navigation_mesh = _subset(src, b)
		level.add_child(r)
		extra.append(r)
	for _i in 30:
		await physics_frame
	var split := _time(map, at)
	print("  EIGHT REGIONS, all enabled      %6d polys   %7.1f us   %+.0f%%" % [
		total, split, 100.0 * (split / maxf(base, 0.001) - 1.0)])

	# ONE SMALL REGION: what you get if the far chunks are NOT in the map.
	for r in extra:
		r.queue_free()
	for _i in 10:
		await physics_frame
	print("")
	print("  only the polygons within R of the query — chunking WITH unloading:")
	for radius in [400.0, 200.0, 100.0, 50.0]:
		var near := PackedInt32Array()
		for pi in total:
			if _centroid(src, pi).distance_to(at) <= radius:
				near.append(pi)
		if near.is_empty():
			continue
		var small := NavigationRegion3D.new()
		small.navigation_mesh = _subset(src, near)
		level.add_child(small)
		for _i in 30:
			await physics_frame
		var t := _time(map, at)
		print("  R = %4.0f m                      %6d polys   %7.1f us   %+.0f%%" % [
			radius, near.size(), t, 100.0 * (t / maxf(base, 0.001) - 1.0)])
		small.queue_free()
		for _i in 10:
			await physics_frame
	quit(0)
