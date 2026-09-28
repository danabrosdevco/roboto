extends SceneTree

# ─────────────────────────────────────────────
# NAV MUTAHA WIP — rebake the temporary copy's navmesh and walk it.
#
#   godot --path . --script res://tools/probe_nav_mutaha_wip.gd
#
# NOT headless: the navmesh parses mesh instances, and a bake without a
# renderer comes back with nothing in it.
#
# The navmesh is a sub-resource inside the .tscn, so terrain_bake.gd cannot save
# it — it bakes and then says so. This writes the two lines back into the scene
# text instead: `vertices =` and `polygons =` INSIDE the NavigationMesh
# sub-resource only. The bridges' ArrayOccluder3D sub-resources have their own
# `vertices =` lines, and rewriting one of those would silently break a bridge.
#
# Then it walks. "There is navmesh" is not "you can get there": the point of
# taking the island's south span out is that a route disappears, and the point
# of the new crossing is that another appears. Neither claim means anything
# until something paths from the spawn and reports how far it got.
# ─────────────────────────────────────────────

## LEVEL=res://... to walk another level; BAKE=0 to walk the one on disk as it is.
var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/mutaha_wip_level.tscn"
var rebake := OS.get_environment("BAKE") != "0"
const SPAWN := Vector3(91.5, 0.82, 420.0)

## Marks to walk to. Reached means the path ends within 3 m of the mark.
const MARKS: Array = [
	["the east plain", Vector3(120.0, 0.0, 250.0), true],
	["the east bank town", Vector3(180.0, 0.0, 40.0), true],
	["the east bridgehead", Vector3(60.0, 0.0, 20.0), true],
	["the island, mid", Vector3(-30.0, 0.0, -20.0), true],
	["the island, north tip", Vector3(-50.0, 0.0, -196.0), true],
	["the west bridgehead", Vector3(-160.0, 0.0, -50.0), true],
	["the west bank town", Vector3(-270.0, 0.0, -20.0), true],
	["the new crossing, east end", Vector3(-70.0, 0.0, 316.0), true],
	["the new crossing, west end", Vector3(-145.0, 0.0, 316.0), true],
	["the new quarter, south", Vector3(-229.0, 0.0, 211.0), true],
	["the new quarter, north", Vector3(-311.0, 0.0, 112.0), true],
	["the quay, facing the island", Vector3(-160.0, 0.0, 180.0), true],
	["the factory, island south tip", Vector3(-48.0, 0.0, 167.0), true],
	["the old south bridgehead, plain side", Vector3(12.0, 0.0, 195.0), true],
]

## The one thing the dropped span is supposed to change: how far it is from the
## plain, at the old bridgehead, to the island 40 m away across the channel.
## Both ends have navmesh either way — the question is whether there is still a
## line between them, and a mark that only asks "is it reachable" cannot tell,
## because the island is reachable the long way round.
const FORD_FROM := Vector3(12.0, 0.0, 195.0)
const FORD_TO := Vector3(-4.0, 0.0, 152.0)

var map: RID


func _initialize() -> void:
	await process_frame
	if rebake and not await _bake():
		quit(1)
		return

	# FRESH, from disk, after the write. GeneratedTerrain takes the river beds
	# back out of the navmesh in its _ready (water_navmesh.gd), and a bake done
	# after that has paved them again — which is how the first run of this probe
	# came back saying the squad could walk the channel the bridge used to span.
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
	print("   walking %s, %d navmesh vertices after the river came out" % [
			level_path.get_file(), region.navigation_mesh.get_vertices().size()])
	map = region.get_navigation_map()
	var from := NavigationServer3D.map_get_closest_point(map, SPAWN)
	print("   spawn (%.0f, %.0f) snaps to (%.1f, %.1f, %.1f)" % [SPAWN.x, SPAWN.z, from.x, from.y, from.z])
	var wrong := 0
	for m: Array in MARKS:
		var r := _walk(from, m[1])
		var ok: bool = r[0]
		var tag := "reached" if ok else "CUT OFF"
		if ok != bool(m[2]):
			tag = "!! " + tag
			wrong += 1
		print("   %-38s %-10s %6.0f m walked, mesh %4.1f m from the mark" % [m[0], tag, r[1], r[2]])
	var ford := _walk(NavigationServer3D.map_get_closest_point(map, FORD_FROM), FORD_TO)
	print("   old south crossing: %.0f m round from the plain to the island %.0f m away" % [
			ford[1], Vector2(FORD_FROM.x - FORD_TO.x, FORD_FROM.z - FORD_TO.z).length()])
	print("   %s" % ("every route is as intended" if wrong == 0
			else "%d route(s) NOT as intended" % wrong))
	quit()


## Replace the navmesh's two data lines in the scene text, and nothing else.
func _write_back(verts: PackedVector3Array, mesh: NavigationMesh) -> bool:
	var polys: Array = []
	for i in mesh.get_polygon_count():
		polys.append(mesh.get_polygon(i))
	var v_line := "vertices = " + var_to_str(verts).replace("\n", "").replace("&", "")
	var p_line := "polygons = " + var_to_str(polys).replace("\n", "").replace("&", "")
	var f := FileAccess.open(level_path, FileAccess.READ)
	if f == null:
		print("FAIL  could not read %s" % level_path)
		return false
	var text := f.get_as_text()
	f.close()
	var out: PackedStringArray = []
	var inside := false
	var wrote_v := false
	var wrote_p := false
	for line in text.split("\n"):
		if line.begins_with("[sub_resource"):
			inside = line.contains("type=\"NavigationMesh\"")
		elif line.begins_with("[") and not line.begins_with("[\""):
			inside = false
		if inside and line.begins_with("vertices ="):
			out.append(v_line)
			wrote_v = true
			continue
		if inside and line.begins_with("polygons ="):
			out.append(p_line)
			wrote_p = true
			continue
		out.append(line)
	if not (wrote_v and wrote_p):
		print("FAIL  did not find both data lines inside the NavigationMesh sub-resource")
		return false
	var w := FileAccess.open(level_path, FileAccess.WRITE)
	if w == null:
		print("FAIL  could not write %s" % level_path)
		return false
	w.store_string("\n".join(out))
	w.close()
	print("   wrote the navmesh back into %s" % level_path.get_file())
	return true


## [reached, metres walked, how far the mesh is from the mark]
func _walk(from: Vector3, to: Vector3) -> Array:
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var route := NavigationServer3D.map_get_path(map, from, b, true)
	var walked := 0.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
	var miss: float = (route[route.size() - 1] as Vector3).distance_to(b) if route.size() > 0 else 999.0
	return [miss < 3.0, walked, Vector2(b.x - to.x, b.z - to.z).length()]


## Bake the region and write the result into the scene text. Returns false and
## says why if the bake came back empty.
func _bake() -> bool:
	var packed := ResourceLoader.load(level_path, "PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		return false
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 30:
		await physics_frame
	var region: NavigationRegion3D = level.get_node("NavigationRegion3D")
	var mesh: NavigationMesh = region.navigation_mesh
	print("   baking %s: radius %.2f, climb %.2f, region_min_size %.0f" % [
			level_path.get_file(), mesh.agent_radius, mesh.agent_max_climb, mesh.region_min_size])
	var was := mesh.get_vertices().size()
	region.bake_navigation_mesh(false)
	for _i in 60:
		await physics_frame
	mesh = region.navigation_mesh
	var verts := mesh.get_vertices()
	print("   %d vertices (was %d), %d polygons" % [verts.size(), was, mesh.get_polygon_count()])
	if verts.size() < 1000:
		print("FAIL  the bake came back nearly empty — run this with a display, not --headless")
		return false
	var ok := _write_back(verts, mesh)
	level.free()
	return ok
