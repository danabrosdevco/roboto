extends SceneTree

# ─────────────────────────────────────────────
# BRUSH OVERLAP — which brushes of a block actually interpenetrate.
#
#   PIECES=landmarks/landmark_relay_dish godot --path . --script res://tools/probe_brush_overlap.gd
#   FOLDER=features godot --path . --script res://tools/probe_brush_overlap.gd
#
# NOT headless: it uses the physics server to do the intersecting.
#
# WHY NOT AABBs. Half the interesting geometry in this library is tilted — a
# dish is 48 panels on a paraboloid, a tipped slab is a tipped slab — and their
# bounding boxes overlap each other wholesale while the solids never touch. An
# AABB test on the relay dish reports almost every pair and is worthless.
#
# So each brush's convex hull goes into its own StaticBody and the engine is
# asked what it hits. The hulls are SHRUNK about their own centroid first,
# because brushes are supposed to share faces: a wall butted against a wall is
# the whole idea, and only a hull that reaches INSIDE another by more than the
# shrink is reported. That threshold is the difference between "it touches" and
# "there are two solids in the same place", which is what z-fights in game.
# ─────────────────────────────────────────────

## How far each hull is pulled in before testing, as a share of its own size.
## 4% of a 3 m wall segment is 12 cm — under that, call it a butt joint.
const SHRINK := 0.96
## Pairs to print before summarising.
const SHOW := 24


func _initialize() -> void:
	await process_frame
	var names: Array = []
	if OS.get_environment("PIECES") != "":
		for n in OS.get_environment("PIECES").split(",", false):
			names.append(n.strip_edges())
	elif OS.get_environment("FOLDER") != "":
		var dir := "res://maps/blocks/%s" % OS.get_environment("FOLDER")
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				names.append("%s/%s" % [OS.get_environment("FOLDER"), f.get_basename()])
		names.sort()
	if names.is_empty():
		print("usage: PIECES=family/piece,... or FOLDER=family")
		quit(2)
		return
	print("   %-38s %7s %9s %s" % ["piece", "brushes", "overlaps", "worst pair"])
	var total := 0
	for n: String in names:
		total += await _check(n)
	print("   %d overlapping brush pair(s) across %d piece(s)" % [total, names.size()])
	quit()


func _check(piece_name: String) -> int:
	var packed := load("res://maps/blocks/%s.tscn" % piece_name) as PackedScene
	if packed == null:
		print("   %-38s could not load" % piece_name)
		return 0
	var world := Node3D.new()
	root.add_child(world)
	var piece := packed.instantiate() as Node3D
	world.add_child(piece)
	await process_frame

	# One body per brush, so the engine can be asked about them one at a time.
	var bodies: Array = []
	for c in piece.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.shape == null or not (cs.shape is ConvexPolygonShape3D):
			continue
		var pts := (cs.shape as ConvexPolygonShape3D).points
		if pts.size() < 4:
			continue
		var mid := Vector3.ZERO
		for p in pts:
			mid += p
		mid /= pts.size()
		var small := PackedVector3Array()
		for p in pts:
			small.append(mid + (p - mid) * SHRINK)
		var shape := ConvexPolygonShape3D.new()
		shape.points = small
		var body := StaticBody3D.new()
		var holder := CollisionShape3D.new()
		holder.shape = shape
		body.add_child(holder)
		world.add_child(body)
		body.global_transform = cs.global_transform
		bodies.append(body)
	for _i in 4:
		await physics_frame

	var space := world.get_world_3d().direct_space_state
	var hits := 0
	var worst := ""
	var shown := 0
	var seen := {}
	for i in bodies.size():
		var body: StaticBody3D = bodies[i]
		var cs := body.get_child(0) as CollisionShape3D
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.exclude = [body.get_rid()]
		q.collide_with_areas = false
		for r in space.intersect_shape(q, 32):
			var other: Object = r.get("collider")
			if other == null:
				continue
			var j := bodies.find(other)
			if j < 0 or j == i:
				continue
			var key := "%d-%d" % [mini(i, j), maxi(i, j)]
			if seen.has(key):
				continue
			seen[key] = true
			hits += 1
			if worst == "":
				worst = "brush %d and %d" % [i, j]
			if shown < SHOW and OS.get_environment("VERBOSE") != "":
				print("       brush %3d and %3d, near %s" % [i, j,
						cs.global_transform.origin.round()])
				shown += 1
	print("   %-38s %7d %9d %s" % [piece_name, bodies.size(), hits, worst])
	world.queue_free()
	await process_frame
	return hits
