extends SceneTree

# ─────────────────────────────────────────────
# IS THE TRAINING CORE ACTUALLY ON THE FLOOR, AND CAN THE SQUAD REACH IT?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_arena_cores.gd
#
# The proving ground was rebuilt larger by tools/build_proving.gd on 2026-10-13
# and the two training captures were still placed against the OLD arena — at
# Godot z 30 and 37, which in the new map is the enemy blockhouse, not floor.
# They now sit on the bay's bunker floor.
#
# PLACING SOMETHING IS NOT THE SAME AS IT BEING THERE. Three separate things
# have to hold and only one of them is visible in the scene file:
#
#   1. there is ground under it, at the height it was placed at
#   2. the navmesh covers it, or the squad can be ordered to it and will not go
#   3. nothing built is standing in the 3.4 m pad it puts down
#
# This reads the `place` exports straight off the level and checks all three
# against the baked map, so the numbers in the .tscn are tested rather than
# believed. It loads nothing campaign-side and writes nothing.
# ─────────────────────────────────────────────

const PAD := 3.4         ## TrainingCore's pad, so the clearance it needs
const REACH := 6.0       ## how far off the navmesh is still "on" it

var _fail := 0


func _init() -> void:
	Engine.max_fps = 60   # a --script run has no frame cap and starves physics
	var level = load("res://maps/proving_level.tscn").instantiate()
	root.add_child(level)
	for _i in 90:
		await physics_frame

	var map: RID = level.get_node("NavigationRegion3D").get_navigation_map()
	var space := root.world_3d.direct_space_state

	for name in ["TrainingCore", "TrainingBunker"]:
		var n = level.get_node_or_null(name)
		if n == null:
			_bad("%s is not in the level at all" % name)
			continue
		var at: Vector3 = n.place
		print("── %s  place %v" % [name, at])

		# EXCLUDE THE CORE'S OWN BODIES. The first run of this cast down from
		# 12 m and hit the 4.2 m pillar the core had just built, reported "no
		# floor" and nearly moved a placement that was correct.
		var skip: Array[RID] = []
		for b in _bodies(n):
			skip.append(b.get_rid())

		# 1 · GROUND. Cast from 12 m up; the floor must be within half a metre
		# of where the node was placed, or it is hanging or buried.
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, 12.0, 0.0), at - Vector3(0.0, 4.0, 0.0))
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_bad("  no ground under it — it would stand in the air")
		else:
			var drop: float = at.y - hit.position.y
			_ok("  ground at y %.2f, %.2f m under the pad" % [hit.position.y, drop],
				absf(drop) <= 0.6)

		# 2 · THE NAVMESH. The squad walks on the bake, not the floor.
		var on := NavigationServer3D.map_get_closest_point(map, at)
		_ok("  navmesh %.2f m away, at %v" % [at.distance_to(on), on],
			at.distance_to(on) <= REACH)

		# 3 · THE PAD IS CLEAR. Four corners of the 3.4 m pad: each needs the
		# same floor. A corner on a block means the pad clips into it.
		var half := PAD * 0.5
		var clear := true
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := at + Vector3(sx * half, 0.0, sz * half)
				var cq := PhysicsRayQueryParameters3D.create(
					c + Vector3(0.0, 12.0, 0.0), c - Vector3(0.0, 4.0, 0.0))
				cq.exclude = skip
				var ch := space.intersect_ray(cq)
				if ch.is_empty() or absf(ch.position.y - at.y) > 0.6:
					clear = false
		_ok("  all four pad corners sit on the same floor", clear)

	# 4 · A ROUTE FROM THE SPAWN. The whole exercise is walking to it.
	var spawn: Vector3 = level.get_node("SpawnPoint").global_position
	for name in ["TrainingCore", "TrainingBunker"]:
		var n = level.get_node_or_null(name)
		if n == null:
			continue
		var path := NavigationServer3D.map_get_path(map, spawn, n.place, true)
		var ends_near: bool = path.size() > 1 and path[-1].distance_to(n.place) <= REACH
		_ok("a path from the spawn reaches %s (%d hops)" % [name, path.size()], ends_near)

	# 5 · THE BAY EXIT. Arena 2 extracts in the bay rather than walking 46 m
	# back to the blockhouse, so there is a second LevelExit down there and it
	# has to stand on floor like everything else.
	var exits := {"LevelExit": "the blockhouse", "BayExit": "the bay"}
	for name in exits:
		var e = level.get_node_or_null(name)
		if e == null:
			_bad("%s (%s) is not in the level" % [name, exits[name]])
			continue
		var at: Vector3 = e.position
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, 14.0, 0.0), at - Vector3(0.0, 6.0, 0.0))
		var h := space.intersect_ray(q)
		_ok("%s stands on ground (%s)" % [name, exits[name]],
			not h.is_empty() and absf(h.position.y - at.y) <= 1.2)
		var on := NavigationServer3D.map_get_closest_point(map, at)
		_ok("  ...and the squad can walk to it (%.2f m off the bake)"
			% at.distance_to(on), at.distance_to(on) <= REACH)

	# 6 · THE EXIT DOES NOT STAND IN THE BUNKER. Both are in the same 30 m
	# bay; an exit volume overlapping the bunker's pad would extract the player
	# the moment they walked up to take it, which ends the exercise early and
	# looks like the bunker doing it.
	var bay = level.get_node_or_null("BayExit")
	var bunker = level.get_node_or_null("TrainingBunker")
	if bay != null and bunker != null:
		var gap: float = absf(bay.position.z - bunker.place.z)
		# half the exit's 4 m volume, plus half the 3.4 m pad
		var need: float = 2.0 + PAD * 0.5
		_ok("the bay exit clears the bunker pad: %.1f m apart, needs %.1f"
			% [gap, need], gap >= need)

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


func _ok(what: String, good: bool) -> void:
	print("%s  %s" % ["PASS" if good else "FAIL", what])
	if not good:
		_fail += 1


func _bad(what: String) -> void:
	print("FAIL  %s" % what)
	_fail += 1


## Every static body under a node, so a cast can ignore the thing it is testing.
func _bodies(n: Node) -> Array:
	var out := []
	if n is StaticBody3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_bodies(c))
	return out
