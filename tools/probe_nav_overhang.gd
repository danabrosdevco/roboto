extends SceneTree

# ─────────────────────────────────────────────
# DOES THE NAVMESH HANG OVER NOTHING?
#
# The claim to test: on Qamareen the walkable polygon edge may sit up to 1.25 m
# off the real walkable surface, so on a bridge deck with a river either side the
# navmesh overhangs the water and an agent following it walks off.
#
# That is a measurement, not an argument. For every bridge in the level this
# samples a grid across the deck, asks the navigation map for the nearest
# navigable point, and fires a short ray DOWNWARD from it. A navmesh point with
# no collider under it is a point the navmesh offers and the world does not.
#
# BRIDGES ARE FOUND BY NODE, not by coordinates typed into this file. An earlier
# probe of mine used a hardcoded point that turned out to be 200 m from any
# bridge, and the conclusion I drew from it was worthless. The level says where
# its bridges are.
#
# A CONTROL IS REQUIRED TO BELIEVE THE RESULT. Open ground away from any water
# must report ~0% overhang; if it does not, the probe is measuring its own bugs
# and the bridge figures mean nothing.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_nav_overhang.gd [-- <level.tscn>]
# ─────────────────────────────────────────────

const DEFAULT_LEVEL := "res://maps/mutaha_wip_level.tscn"
## How far below a navmesh point we will accept finding the world. Half a metre
## is generous: a deck the agent is standing on is directly underfoot.
const FLOOR_REACH := 1.2
## Step across the deck. Finer than the 0.5 m cell so quantisation shows up.
const STEP := 0.25
## How far out from the deck edge to keep looking, so an overhang is measured
## rather than merely detected.
const MARGIN := 3.0

var _space: PhysicsDirectSpaceState3D
var _map: RID


func _all(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)


## The world-space box a node's visible geometry occupies.
func _bounds(n: Node3D) -> AABB:
	var meshes: Array = []
	_all(n, "MeshInstance3D", meshes)
	var box := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var world := mi.global_transform * mi.mesh.get_aabb()
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	return box


## True when something solid is within FLOOR_REACH below `p`.
func _floor_under(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * FLOOR_REACH)
	q.collide_with_areas = false
	return not _space.intersect_ray(q).is_empty()


## Samples a box and returns [navmesh points found, of those how many had no
## floor]. Points are snapped to the navmesh first: this asks "where will the
## agent be sent", not "what is in this box".
func _sweep(box: AABB, label: String) -> Array:
	var seen := {}
	var on_nav := 0
	var hanging := 0
	var worst := 0.0
	var height_err := 0.0
	var height_max := 0.0
	var height_n := 0
	var lo := box.position - Vector3(MARGIN, 0, MARGIN)
	var hi := box.end + Vector3(MARGIN, 0, MARGIN)
	var y: float = box.position.y + box.size.y * 0.5
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			var ask := Vector3(x, y, z)
			var got := NavigationServer3D.map_get_closest_point(_map, ask)
			# Only count points the map actually put near where we asked —
			# otherwise a query off the end of the world snaps back to the
			# middle of the level and is counted as if it were on the bridge.
			if got.distance_to(ask) < 2.0:
				var key := "%d,%d,%d" % [roundi(got.x * 4), roundi(got.y * 4), roundi(got.z * 4)]
				if not seen.has(key):
					seen[key] = true
					on_nav += 1
					var drop := _drop_to_world(got)
					if not _floor_under(got):
						hanging += 1
						worst = maxf(worst, drop)
					elif drop < 90.0:
						# HOW FAR THE NAVMESH IS FROM THE FLOOR IT DESCRIBES. This is
						# the detail-mesh question: with height sampled every 16 m, a
						# ramp meeting a flat deck has its height interpolated across
						# the break, and an agent is walked up or down a step that is
						# not there.
						height_err += absf(drop)
						height_n += 1
						height_max = maxf(height_max, absf(drop))
			z += STEP
		x += STEP
	var pct := (100.0 * float(hanging) / float(on_nav)) if on_nav > 0 else 0.0
	print("  %-22s %5d navmesh point(s), %4d with nothing under them (%5.1f%%)%s" % [
		label, on_nav, hanging, pct,
		"  worst drop %.1f m" % worst if worst > 0.0 else ""])
	if height_n > 0:
		print("  %-22s navmesh sits %.2f m off the floor on average, %.2f m at worst" % [
			"", height_err / float(height_n), height_max])
	return [on_nav, hanging]


## How far down the real world is from a hanging point, for scale. 99 means
## nothing was found within 40 m, which on a bridge means open air over water.
func _drop_to_world(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * 40.0)
	q.collide_with_areas = false
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return p.y - (hit.position as Vector3).y


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	var level_path: String = args[0] if args.size() > 0 else DEFAULT_LEVEL
	await process_frame

	var packed = load(level_path)
	if packed == null:
		printerr("probe_nav_overhang: cannot load %s" % level_path)
		quit(1)
		return
	var level = packed.instantiate()
	root.add_child(level)
	# Regions sync on the server's own schedule; a query before that answers
	# from an empty map and everything reads as 0% overhang.
	for _i in 30:
		await physics_frame

	var regions: Array = []
	_all(level, "NavigationRegion3D", regions)
	if regions.is_empty():
		printerr("probe_nav_overhang: %s has no NavigationRegion3D, so there is nothing to measure." % level_path)
		quit(1)
		return
	var region := regions[0] as NavigationRegion3D
	_map = region.get_navigation_map()
	_space = (level as Node3D).get_world_3d().direct_space_state

	var mesh := region.navigation_mesh
	print("%s" % level_path)
	print("  bake: cell_size %.2f, agent_radius %.2f, edge_max_error %.2f (= %.2f m), detail_sample_distance %.1f (= %.1f m)" % [
		mesh.cell_size, mesh.agent_radius, mesh.edge_max_error,
		mesh.edge_max_error * mesh.cell_size, mesh.detail_sample_distance,
		mesh.detail_sample_distance * mesh.cell_size])
	print("  map cell size %.2f%s" % [NavigationServer3D.map_get_cell_size(_map),
		"" if is_equal_approx(NavigationServer3D.map_get_cell_size(_map), mesh.cell_size)
		else "  <-- MISMATCH with the bake"])
	print("")

	var bridges: Array = []
	var holder: Node = level.find_child("Bridges", true, false)
	if holder != null:
		for b in holder.get_children():
			bridges.append(b)
	if bridges.is_empty():
		# EVERY EMPTY RESULT SAYS WHY. A probe that finds nothing and prints a
		# clean sheet is worse than one that fails.
		printerr("probe_nav_overhang: no Bridges node in %s — nothing was measured." % level_path)
		quit(1)
		return

	print("BRIDGES")
	var total := 0
	var total_hanging := 0
	for b in bridges:
		var box := _bounds(b as Node3D)
		if box.size == Vector3.ZERO:
			print("  %-22s no visible geometry, skipped" % b.name)
			continue
		var r := _sweep(box, str(b.name))
		total += int(r[0])
		total_hanging += int(r[1])
	print("  ── %d of %d navmesh points over nothing (%.1f%%)" % [total_hanging, total,
		100.0 * float(total_hanging) / float(maxi(total, 1))])

	# THE CONTROL. Open ground, away from the river: whatever this reports is
	# the probe's own noise floor, and the bridge figures are only worth reading
	# against it.
	print("")
	print("CONTROL — open ground, no water")
	var spawn: Node = level.find_child("PlayerSpawn", true, false)
	var at: Vector3 = (spawn as Node3D).global_position if spawn is Node3D else Vector3.ZERO
	_sweep(AABB(at - Vector3(8, 1, 8), Vector3(16, 2, 16)), "near spawn")
	quit(0)
