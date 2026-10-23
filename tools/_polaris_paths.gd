extends SceneTree

# CAN THE REINFORCEMENTS ACTUALLY GET THERE? Every reserve on Polaris resolves
# its post_tag, which only proves the tag exists. This asks the navmesh whether
# a squad put down at each spawn can walk to the post it is ordered to take.
#
# A path that comes back as a straight two-point hop between points far apart is
# the navmesh saying "no route", not "an easy route".

const MISSION := "res://Campaign/missions/mission_polaris_1_siege.tres"
const LEVEL := "res://maps/polaris_level.tscn"

func _init() -> void:
	await process_frame
	var m = load(MISSION)
	var lvl: Node = load(LEVEL).instantiate()
	root.add_child(lvl)
	for _i in 60:
		await physics_frame

	var region: NavigationRegion3D = _region(lvl)
	if region == null:
		print("NO NavigationRegion3D in the level"); quit(1); return
	var nav_map := region.get_navigation_map()
	print("navmesh polygons: %d" % (region.navigation_mesh.get_polygon_count() if region.navigation_mesh != null else -1))

	var points: Dictionary = {}
	_collect(lvl, points)

	var bad := 0
	var checked := 0
	for spec in m.enemy_force:
		if spec == null or spec.posture != EnemySquadSpec.Posture.RESERVE:
			continue
		if not points.has(spec.spawn_tag) or not points.has(spec.post_tag):
			continue
		checked += 1
		var from: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, points[spec.spawn_tag])
		var to: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, points[spec.post_tag])
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
		var direct: float = from.distance_to(to)
		var walked := 0.0
		for i in range(1, path.size()):
			walked += path[i - 1].distance_to(path[i])
		# The end of the path has to actually be the destination. A blocked
		# query returns the nearest it could get to, which looks like a path.
		var arrives: bool = path.size() >= 2 and path[path.size() - 1].distance_to(to) < 6.0
		var snap: float = points[spec.spawn_tag].distance_to(from)
		if not arrives:
			bad += 1
		print("  %-12s %-20s -> %-20s  direct %6.1fm  walked %7.1fm  %s%s" % [
			spec.callsign, spec.spawn_tag, spec.post_tag, direct, walked,
			"ARRIVES" if arrives else "*** CANNOT REACH ***",
			"   (spawn %.1fm off the navmesh)" % snap if snap > 4.0 else ""])
	print("checked %d reserve squads, %d cannot reach their post" % [checked, bad])
	quit(0)

func _region(n: Node) -> NavigationRegion3D:
	if n is NavigationRegion3D:
		return n
	for c in n.get_children():
		var r := _region(c)
		if r != null:
			return r
	return null

func _collect(n: Node, out: Dictionary) -> void:
	if n.is_in_group("squad_objective_points") and "tag" in n:
		out[StringName(str(n.get("tag")))] = (n as Node3D).global_position
	for c in n.get_children():
		_collect(c, out)
