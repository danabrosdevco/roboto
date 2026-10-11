extends SceneTree

# ─────────────────────────────────────────────
# PROBE PATH BETWEEN — can the squad get from here to there, on the baked mesh?
#
#   LEVEL=res://maps/causeway_level.tscn FROM="-340,0,0" TO="-290,5,0" \
#       godot --path . --script res://tools/probe_path_between.gd
#
#   POINTS="-340,0,0;-330,0,0;-324,0,0;-312,2.5,0;-300,5,0"   walk a line of them
#
# probe_nav_reach answers the same question for a whole level, but it needs a
# SpawnPoint and it samples a grid. When somebody says "they can't get onto the
# first ramp", the useful question is narrower: is there mesh AT that point, and
# does a path from the ground reach it.
#
# Two different failures look identical from the game: no mesh on the ramp at
# all (it baked as a wall), or mesh on the ramp that is an island (it baked but
# did not join the shore). This tells them apart — "snapped N m" is how far the
# query had to move to find any mesh, and a path length far longer than the
# straight line means joined but the long way round.
# ─────────────────────────────────────────────

## Further than this from the query point and there is effectively no mesh there.
const OFF_MESH := 2.0


func _initialize() -> void:
	var path := OS.get_environment("LEVEL")
	if path == "":
		print("FAIL  set LEVEL to a level scene")
		quit(2)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s did not load" % path)
		quit(1)
		return
	var root := packed.instantiate()
	if root == null:
		print("FAIL  %s did not instantiate" % path)
		quit(1)
		return
	get_root().add_child(root)
	await process_frame
	await process_frame

	var regions := root.find_children("*", "NavigationRegion3D", true, false)
	if regions.is_empty():
		print("FAIL  %s has no NavigationRegion3D — nothing to path on" % path)
		quit(1)
		return
	var map: RID = (regions[0] as NavigationRegion3D).get_navigation_map()

	var pts: Array = []
	if OS.get_environment("POINTS") != "":
		for s: String in OS.get_environment("POINTS").split(";"):
			pts.append(_vec(s))
	else:
		pts.append(_vec(OS.get_environment("FROM")))
		pts.append(_vec(OS.get_environment("TO")))
	if pts.size() < 2:
		print("FAIL  give FROM and TO, or POINTS with at least two")
		quit(2)
		return

	print("\n   %s" % path.get_file())
	print("   is there mesh at each point?")
	var snapped: Array = []
	for p: Vector3 in pts:
		var on := NavigationServer3D.map_get_closest_point(map, p)
		var d := p.distance_to(on)
		snapped.append(on)
		var verdict := "  NO MESH HERE" if d > OFF_MESH else ""
		print("   (%7.1f %5.1f %7.1f)  nearest mesh %6.2f m away  -> (%7.1f %5.1f %7.1f)%s" % [
				p.x, p.y, p.z, d, on.x, on.y, on.z, verdict])

	print("\n   can it walk between them?")
	var bad := 0
	for i in range(1, pts.size()):
		var a: Vector3 = snapped[i - 1]
		var b: Vector3 = snapped[i]
		var line := NavigationServer3D.map_get_path(map, a, b, true)
		var straight := a.distance_to(b)
		if line.size() < 2:
			print("   %d -> %d   NO PATH (%.0f m apart)" % [i - 1, i, straight])
			bad += 1
			continue
		var walk := 0.0
		for j in range(1, line.size()):
			walk += line[j - 1].distance_to(line[j])
		# A path that ends short of where it was asked for is Godot's way of
		# saying the two points are on separate islands: it returns the best it
		# can reach rather than failing outright.
		var short := line[line.size() - 1].distance_to(b)
		var note := ""
		if short > OFF_MESH:
			note = "   STOPS %.0f m SHORT — separate islands" % short
			bad += 1
		elif straight > 0.1 and walk / straight > 3.0:
			note = "   the long way round"
		print("   %d -> %d   %6.0f m walk / %6.0f m direct  x%.2f%s" % [
				i - 1, i, walk, straight, walk / maxf(straight, 0.001), note])

	if bad > 0:
		print("\nPATH FAIL — %d leg(s) do not connect" % bad)
		quit(1)
		return
	print("\nPATH OK")
	quit()


func _vec(s: String) -> Vector3:
	var p := s.strip_edges().split(",")
	if p.size() != 3:
		push_warning("probe_path_between: '%s' is not x,y,z — skipped" % s)
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
