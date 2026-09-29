extends SceneTree

# ─────────────────────────────────────────────
# NAV HILLFORT — bake maps/hillfort_level.tscn's navmesh, write it back into the
# scene, and then ask the two questions a climb map lives or dies on.
#
#   godot --path . --script res://tools/probe_nav_hillfort.gd
#   BAKE=0 godot --path . --script res://tools/probe_nav_hillfort.gd
#
# NOT headless: a bake without a renderer comes back with nothing in it.
#
# QUESTION ONE, can the squad get to the top. Walk from the spawn to every
# station and report how far it got. A station with no route is a dead map.
#
# QUESTION TWO, and this is the one that matters, DOES THE STAIR MEAN ANYTHING.
# Two consecutive landings are 44 m apart across the face and 303 m apart along
# the flight that joins them. If the navmesh walk between them comes back near
# 44 m, the face is walkable, the switchbacks are scenery, and every bot on the
# map will beeline straight up the mountain. "There is navmesh on the summit"
# is not the claim being made here — the claim is that the only way to it is
# the way it was built.
#
# The same shape of test as the dropped bridge on the Mutaha copy: reachability
# cannot answer it, because both ends are reachable either way. Only the
# DISTANCE between them can.
# ─────────────────────────────────────────────

var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/hillfort_level.tscn"
var rebake := OS.get_environment("BAKE") != "0"

## Must match STATIONS in probe_build_hillfort.gd: name, x, z, y. KEEP IT IN STEP
## — this went stale when the Shoulder moved and the probe spent a run walking
## to where that station used to be, reporting a 40 m climb that was not there.
const STATIONS: Array = [
	["Trailhead", 0.0, 430.0, 0.0],
	["Cistern", -170.0, 258.0, 10.0],
	["Pillars", 150.0, 140.0, 34.0],
	["Gate", -140.0, 34.0, 46.0],
	["Terrace", 140.0, -46.0, 76.0],
	["Shoulder", -205.0, -46.0, 62.0],
	["Summit", 30.0, -270.0, 132.0],
]

## Standing places round the hill, all the same distance out from the summit.
## Far enough out to be below the plateau, close enough that a walk up is a
## walk and not a cross-country trek.
const RING_R := 130.0
## Just outside the curtain wall. The ring is 120 x 96 and 3.2 m thick, so 68 m
## from the middle clears its longest side and is still on the plateau.
const OUTSIDE_WALL := 68.0
const RING: Array = [
	["north", 0.0], ["east", 90.0], ["south", 180.0], ["west", 270.0],
	["north-east", 45.0], ["south-west", 225.0],
]

## Walking to the summit and covering more than this many times the straight-
## line distance means the ground turned the squad back — which on this map is
## a defect, not a feature.
## When the steep ring still existed it showed 3-5x from every bearing but the
## ramp. So a wall reads WAY over this; anything between 1 and 2 is the path
## rounding a wrinkle, not being turned back.
const DETOUR := 2.0

var map: RID


func _initialize() -> void:
	await process_frame
	if rebake and not await _bake():
		quit(1)
		return
	# BAKE_ONLY: bake the navmesh, write it into the scene, stop. The station
	# and ring tests below are about maps/hillfort_level.tscn and mean nothing on
	# any other level — but the bake and the write-back are level-agnostic, and
	# any level whose NavigationMesh is a sub-resource needs them after its
	# terrain moves. terrain_bake.gd --navmesh cannot save an embedded one.
	if OS.get_environment("BAKE_ONLY") != "":
		quit()
		return
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
	print("   %s — %d navmesh vertices, %d polygons" % [level_path.get_file(),
			region.navigation_mesh.get_vertices().size(),
			region.navigation_mesh.get_polygon_count()])
	map = region.get_navigation_map()
	var spawn: Node3D = level.get_node("SpawnPoint")
	var from := NavigationServer3D.map_get_closest_point(map, spawn.global_position)
	print("   spawn (%.0f, %.0f, %.0f) snaps to (%.1f, %.1f, %.1f)" % [
			spawn.global_position.x, spawn.global_position.y, spawn.global_position.z,
			from.x, from.y, from.z])

	print("")
	print("   FROM THE SPAWN")
	print("   %-12s %-10s %9s %9s %8s" % ["station", "state", "walked", "climbed", "offset"])
	var cut := 0
	for s: Array in STATIONS:
		var mark := Vector3(float(s[1]), float(s[3]), float(s[2]))
		var r := _walk(from, mark)
		if not bool(r[0]):
			cut += 1
		print("   %-12s %-10s %8.0fm %8.0fm %7.1fm" % [s[0],
				"reached" if r[0] else "CUT OFF", r[1], r[3] - from.y, r[2]])

	print("")
	print("   HOW OPEN IS THE SUMMIT — onto the plateau from all round the hill")
	print("   The steep ring under the summit is GONE on purpose: it read as a")
	print("   crater with a fort in it. The hill is now walkable from every side,")
	print("   so every one of these should come back near 1.0x, and anything a")
	print("   long way over is a piece of hillside that has quietly become a")
	print("   cliff. Stopping the squad walking in is a WALL's job now, not the")
	print("   ground's — so this measures that the ground is NOT doing it.")
	print("   TWO WALKS PER BEARING, and they answer different questions. Up to")
	print("   the foot of the wall should be OPEN everywhere, because the ground")
	print("   is not supposed to be doing any gating. Through to the middle of")
	print("   the fort should be a long way round on every bearing but the gate's")
	print("   — that is the wall doing the job the terrain used to.")
	print("   %-14s %9s %9s %7s %9s %7s" % [
			"from", "direct", "to wall", "ratio", "to middle", "ratio"])
	var summit: Array = STATIONS[STATIONS.size() - 1]
	var top := Vector3(float(summit[1]), float(summit[3]), float(summit[2]))
	var loose := 0
	var sealed := 0
	for r: Array in RING:
		var a := deg_to_rad(float(r[1]))
		var at := Vector3(top.x + sin(a) * RING_R, 0.0, top.z - cos(a) * RING_R)
		var foot := Vector3(top.x + sin(a) * OUTSIDE_WALL, top.y,
				top.z - cos(a) * OUTSIDE_WALL)
		var start := NavigationServer3D.map_get_closest_point(map, at)
		var direct := Vector2(top.x - start.x, top.z - start.z).length()
		var to_foot := _walk(start, foot)
		var to_mid := _walk(start, top)
		var gap := Vector2(foot.x - start.x, foot.z - start.z).length()
		var ground: float = float(to_foot[1]) / maxf(gap, 1.0)
		var through: float = float(to_mid[1]) / maxf(direct, 1.0)
		var note := ""
		if not bool(to_foot[0]):
			note = "   CUT OFF short of the wall"
			loose += 1
		elif ground > DETOUR:
			note = "   GROUND DETOUR — the hillside is not walkable here"
			loose += 1
		# Against the GROUND ratio, not a flat number: a bearing where the hill
		# already costs 1.6x has not been sealed by the wall just because the
		# walk through to the middle costs 2.0x.
		elif through > ground * 1.4:
			note = "   the wall holds"
			sealed += 1
		else:
			note = "   straight in — the gate is on this side"
		print("   %-14s %8.0fm %8.0fm %6.1fx %8.0fm %6.1fx%s" % [
				r[0], direct, float(to_foot[1]), ground, float(to_mid[1]), through, note])

	print("")
	print("   %d station(s) cut off, %d side(s) of the HILL that turn the squad back;" % [
			cut, loose])
	print("   the WALL holds on %d of %d bearings" % [sealed, RING.size()])
	quit()


## [reached, metres walked, how far the mesh is from the mark, end height]
func _walk(from: Vector3, to: Vector3) -> Array:
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var route := NavigationServer3D.map_get_path(map, from, b, true)
	var walked := 0.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
	var end: Vector3 = route[route.size() - 1] if route.size() > 0 else from
	var miss: float = end.distance_to(b) if route.size() > 0 else 999.0
	return [miss < 4.0, walked, Vector2(b.x - to.x, b.z - to.z).length(), b.y]


## Bake the region and write the result into the scene text. Replaces ONLY the
## two data lines inside the NavigationMesh sub-resource.
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
	var t0 := Time.get_ticks_msec()
	region.bake_navigation_mesh(false)
	for _i in 20:
		await physics_frame
	var mesh := region.navigation_mesh
	var verts := mesh.get_vertices()
	print("   baked %d vertices, %d polygons in %.1f s" % [
			verts.size(), mesh.get_polygon_count(), (Time.get_ticks_msec() - t0) / 1000.0])
	if verts.size() < 500:
		print("FAIL  that is far too few — is this running with a display?")
		return false
	var ok := _write_back(verts, mesh)
	level.queue_free()
	await process_frame
	return ok


func _write_back(verts: PackedVector3Array, mesh: NavigationMesh) -> bool:
	var polys: Array = []
	for i in mesh.get_polygon_count():
		polys.append(mesh.get_polygon(i))
	var v_line := "vertices = " + var_to_str(verts).replace("\n", "").replace("&", "")
	var p_line := "polygons = " + var_to_str(polys).replace("\n", "").replace("&", "")
	var text := FileAccess.get_file_as_string(level_path)
	if text == "":
		print("FAIL  could not read %s" % level_path)
		return false
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
