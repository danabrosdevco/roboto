extends SceneTree

# ─────────────────────────────────────────────
# CRATER ESCAPE — can the squad get OUT of every crater on a map.
#
#   godot --path . --script res://tools/probe_crater_escape.gd
#   LEVEL=res://maps/coastal-road_level.tscn godot --path . --script res://tools/probe_crater_escape.gd
#   PIECE=CraterRim godot --path . --script res://tools/probe_crater_escape.gd
#
# NOT headless: it reads the level's baked navmesh, and the terrain has to
# build its collision for the queries to mean anything.
#
# WHY THIS EXISTS. feature_crater_rim lays eleven heaved slabs in a ring at
# 5.6 m, each 0.6 to 1.2 m tall. move_and_slide has NO STEP-UP and the bots
# step over 0.45 m, so every one of those is a wall — and eleven of them at
# 3.8 m long round a 35 m circumference is a CLOSED ring. Walk in and you stay
# in. It is invisible on a map that is otherwise fine, because there is
# navmesh on both sides of the lip and a reach test only asks whether the far
# side is reachable, which it is — the long way round.
#
# So this asks the only question that finds it: from the middle of the crater,
# how far is it to a point just outside the rim.
# ─────────────────────────────────────────────

var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/valley_basin_level.tscn"
var piece := OS.get_environment("PIECE") if OS.get_environment("PIECE") != "" else "CraterRim"

## How far out "outside" is: past the 5.6 m ring and its scattered slabs.
const OUT_R := 16.0
## Walking further than this many times the straight line means the rim turned
## the squad back. A clear crater comes out near 1.0.
const TRAPPED := 3.0
## How finely the ground is walked outward. Coarser than this and a 1 m slab
## averages out into a ramp that is not there.
const STEP := 0.25
## Bearings tried. A single gap in the ring is a way out, so this has to be
## fine enough to find one: 11 slabs means 11 joints to look between.
const BEARINGS := 72
## Steeper than this and move_and_slide will not climb it, whatever the
## navmesh thinks. Godot's CharacterBody3D floor_max_angle default.
const WALKABLE := 45.0

var map: RID


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
	for _i in 40:
		await physics_frame
	var region: NavigationRegion3D = level.get_node_or_null("NavigationRegion3D")
	if region == null or region.navigation_mesh == null \
			or region.navigation_mesh.get_vertices().size() < 500:
		print("FAIL  %s has no baked navmesh to walk — bake it first." % level_path.get_file())
		quit(1)
		return
	map = region.get_navigation_map()
	var space := level.get_world_3d().direct_space_state

	var found: Array = []
	_collect(level, found)
	if found.is_empty():
		print("   %s: no node named %s* in it" % [level_path.get_file(), piece])
		quit()
		return
	print("   %s — %d %s piece(s), out to %.0f m" % [
			level_path.get_file(), found.size(), piece, OUT_R])
	print("   %-24s %8s %9s  %s" % ["piece", "navmesh", "steepest", "verdict"])
	var trapped := 0
	for node: Node3D in found:
		var at := node.global_position
		var inside := NavigationServer3D.map_get_closest_point(map, at)
		var nav_ok := false
		for i in 8:
			var a := TAU * i / 8.0
			var b := NavigationServer3D.map_get_closest_point(map,
					at + Vector3(cos(a) * OUT_R, 0.0, sin(a) * OUT_R))
			var route := NavigationServer3D.map_get_path(map, inside, b, true)
			if route.size() >= 2 and (route[route.size() - 1] as Vector3).distance_to(b) <= 3.0:
				var walked := 0.0
				for k in route.size() - 1:
					walked += route[k].distance_to(route[k + 1])
				if walked / maxf(Vector2(b.x - inside.x, b.z - inside.z).length(), 1.0) <= TRAPPED:
					nav_ok = true
		# THE ONE THAT MATTERS. The navmesh bridges a 1 m slab happily — it
		# fills a 0.5 m climb and smooths what is left — but a player is a
		# CharacterBody3D and move_and_slide HAS NO STEP-UP: a face steeper
		# than floor_max_angle is a wall at any height. So walk the collision
		# surface out along each bearing and find the steepest rise on the
		# gentlest bearing. That is the number the human hit.
		var gentlest := 90.0
		var gentlest_at := 0.0
		for i in BEARINGS:
			var a := TAU * i / float(BEARINGS)
			var dir := Vector3(cos(a), 0.0, sin(a))
			var worst := 0.0
			var prev := _ground(space, at)
			var d := STEP
			while d <= OUT_R:
				var h := _ground(space, at + dir * d)
				if not is_inf(h) and not is_inf(prev):
					worst = maxf(worst, rad_to_deg(atan2(h - prev, STEP)))
				prev = h
				d += STEP
			if worst < gentlest:
				gentlest = worst
				gentlest_at = rad_to_deg(a)
		var note := "   out"
		if gentlest > WALKABLE:
			note = "   WALLED IN — steepest rise %.0f° on the gentlest bearing (%.0f°)" % [
					gentlest, gentlest_at]
			trapped += 1
		elif not nav_ok:
			note = "   navmesh says no, ground says yes — check the bake"
			trapped += 1
		print("   %-24s %8s %8.0f° %6s%s" % [node.name,
				"nav ok" if nav_ok else "nav CUT", gentlest, "", note])
	print("   %d of %d crater(s) a body cannot walk out of" % [trapped, found.size()])
	quit()


## Height of the collision surface under `at`, or INF if there is none.
func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, at.y + 30.0, at.z), Vector3(at.x, at.y - 30.0, at.z))
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit.has("position") else INF


func _collect(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D and str(c.name).begins_with(piece):
			out.append(c)
		_collect(c, out)
