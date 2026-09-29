extends SceneTree

# ─────────────────────────────────────────────
# PATH WALK — walk the collision surface along a level's TerrainPath curves and
# say where a body would be stopped.
#
#   LEVEL=res://maps/valley_basin_level.tscn godot --path . --script res://tools/probe_path_walk.gd
#   LEVEL=... PATHS=TrenchWest,RoadEast godot --path . --script res://tools/probe_path_walk.gd
#
# NOT headless: it raycasts against real collision.
#
# WHY THE CURVE AND NOT A STRAIGHT LINE. A trench or a road meanders, and the
# straight line between two pieces of its dressing leaves it and climbs the
# bank — two runs of this were thrown away learning that. The path's own curve
# is the centreline by definition.
#
# WHY COLLISION AND NOT THE NAVMESH. move_and_slide has NO STEP-UP: a face
# steeper than floor_max_angle stops a player at any height, while the navmesh
# fills a climb up to agent_max_climb and reports the route fine. Everything
# this has found so far was invisible to a navmesh test — a 0.30 m lip on a
# duckboard deck laid slightly proud of the trench floor it was lining, which
# in play is a post in the floor you cannot walk over.
#
# IT FLAGS DELIBERATE OBSTACLES TOO, and it should: a checkpoint barrier, a
# rubble pile and a queue of vehicles all stop a body on the centreline of
# Coast Road, and all three are meant to. This is a LOOK HERE tool, not a
# pass/fail one — the collider name is usually enough to tell a barrier from
# a bug, and a road is wider than the line this walks.
#
# It names the COLLIDER under each step, which is what turns "something blocks
# the trench" into "Revet04's deck".
# ─────────────────────────────────────────────

var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/valley_basin_level.tscn"

## How finely the surface is sampled. Coarser and a 0.3 m lip averages into a
## ramp that is not there.
const STEP := 0.25
## Steeper than this and move_and_slide will not climb it.
const WALKABLE := 45.0


func _initialize() -> void:
	await process_frame
	var packed := ResourceLoader.load(level_path, "PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 30:
		await physics_frame
	var space := level.get_world_3d().direct_space_state

	var wanted: Array = []
	if OS.get_environment("PATHS") != "":
		for s in OS.get_environment("PATHS").split(",", false):
			wanted.append(s.strip_edges())
	var paths: Array = []
	for n in level.find_children("*", "Path3D", true, false):
		var p := n as Path3D
		if p.curve == null or p.curve.point_count < 2:
			continue
		if wanted.is_empty() or str(p.name) in wanted:
			paths.append(p)
	if paths.is_empty():
		print("   %s: no Path3D with a curve in it" % level_path.get_file())
		quit()
		return
	print("   %s — walking %d path(s) at %.2f m, flagging rises over %.0f°" % [
			level_path.get_file(), paths.size(), STEP, WALKABLE])
	var total := 0
	for p: Path3D in paths:
		total += _walk(space, p)
	print("   %d step(s) a body cannot climb, across %d path(s)" % [total, paths.size()])
	quit()


func _walk(space: PhysicsDirectSpaceState3D, p: Path3D) -> int:
	var pts := p.curve.tessellate(5, 2.0)
	var prev := INF
	var along := 0.0
	var bad := 0
	for i in pts.size() - 1:
		var a: Vector3 = p.global_transform * pts[i]
		var b: Vector3 = p.global_transform * pts[i + 1]
		var n: int = maxi(int(a.distance_to(b) / STEP), 1)
		for k in n:
			var q := a.lerp(b, float(k) / n)
			var r := PhysicsRayQueryParameters3D.create(
					Vector3(q.x, q.y + 12.0, q.z), Vector3(q.x, q.y - 12.0, q.z))
			var hit := space.intersect_ray(r)
			var h: float = float(hit["position"].y) if hit.has("position") else INF
			if not is_inf(h) and not is_inf(prev):
				var rise := rad_to_deg(atan2(h - prev, STEP))
				if rise > WALKABLE:
					bad += 1
					var who := "the terrain"
					if hit.has("collider") and hit["collider"] != null:
						who = str((hit["collider"] as Node).get_path())
						who = who.get_slice("NavigationRegion3D/", 1)
					print("     %-16s %6.1f m  (%7.1f,%7.1f) %4.0f°  +%.2f m  %s" % [
							p.name, along, q.x, q.z, rise, h - prev, who])
			prev = h
			along += STEP
	if bad == 0:
		print("     %-16s clear over %.0f m" % [p.name, along])
	return bad
