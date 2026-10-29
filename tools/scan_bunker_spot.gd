extends SceneTree

# ─────────────────────────────────────────────
# FIND A SPOT THE ENTRANCE FITS, near a marker that it does not.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/scan_bunker_spot.gd -- causeway
#
# probe_bunker_clear.gd says a bunker is buried. This says where to put it
# instead: it walks a grid round the marker, and for each candidate repeats the
# same three measurements — ground to stand the sill on, a clear doorway, and
# an unobstructed approach out of the front of it.
#
# IT REPORTS AN OFFSET, not a position, because that is what site_slice takes.
# A typed world coordinate is correct until somebody moves the marker it was
# copied from and then it is silently wrong; an offset moves with it.
#
# Nothing is written. Read the answer and put it in the map's own *_slice.gd.
# ─────────────────────────────────────────────

# THE SITES ARE DERIVED, NOT TYPED (backlog H14). The table that used to be
# here named the retired maps/hillfort_level.tscn, so an offset scanned for
# "hillfort" would have been typed into a slice the game never loads.
const Sites := preload("res://tools/_live_sites.gd")

const APPROACH := 10.0
const HALF := 3.0
const CHEST := 1.6
const STEP := 4.0
const REACH := 24.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var args := OS.get_cmdline_user_args()
	var want := String(args[0]) if args.size() > 0 else "causeway"
	var labels: Array = []
	var pick: Dictionary = {}
	for s in Sites.sites():
		labels.append(s.label)
		if s.label == want:
			pick = s
	if pick.is_empty():
		print("FAIL  '%s' is not one of %s" % [want, str(labels)])
		quit(1)
		return
	if pick.node == "":
		print("FAIL  %s carries no slice node, so there is no bunker to scan round." % pick.level)
		quit(1)
		return
	await _scan(want, pick.level, pick.node)
	quit()


func _scan(label: String, level_path: String, node_name: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 70:
		await physics_frame
	var slice = level.get_node_or_null(NodePath(node_name))
	var bunker = slice.get_node_or_null(^"SiteBunker") if slice != null else null
	if bunker == null:
		print("FAIL  %s built no bunker" % label)
		return

	var space := root.world_3d.direct_space_state
	var basis: Basis = (bunker as Node3D).global_transform.basis
	var fwd: Vector3 = basis.z.normalized()
	var side: Vector3 = basis.x.normalized()
	# The marker, which is where the offset is measured FROM.
	var origin: Vector3 = (bunker as Node3D).global_position - slice.bunker_offset
	var skip: Array[RID] = []
	for b in _bodies(bunker):
		skip.append(b.get_rid())

	print("── %s — scanning %.0f m round the marker at %v" % [label, REACH, origin])
	var best := Vector3.ZERO
	var best_d := 1.0e9
	var found := 0
	var x := -REACH
	while x <= REACH:
		var z := -REACH
		while z <= REACH:
			var off := side * x + fwd * z
			if _fits(space, origin + off, fwd, side, skip):
				found += 1
				var d: float = off.length()
				if d < best_d:
					best_d = d
					best = off
			z += STEP
		x += STEP

	if found == 0:
		print("     NOTHING FITS within %.0f m. The marker is the wrong place for a 9 m door — pick another." % REACH)
		return
	print("     %d candidate(s); nearest is %.1f m away" % [found, best_d])
	print("     bunker_offset = Vector3(%.1f, %.1f, %.1f)" % [best.x, best.y, best.z])


## The same three questions probe_bunker_clear.gd asks, at a candidate spot.
func _fits(space: PhysicsDirectSpaceState3D, at: Vector3, fwd: Vector3, side: Vector3, skip: Array[RID]) -> bool:
	# Ground to stand on, within a couple of metres of the marker's height.
	var qd := PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, 20.0, 0.0), at - Vector3(0.0, 8.0, 0.0))
	qd.exclude = skip
	var down := space.intersect_ray(qd)
	if down.is_empty():
		return false
	if absf(down.position.y - at.y) > 2.0:
		return false
	# The doorway, side to side.
	var a: Vector3 = at - side * (HALF + 1.0) + Vector3(0.0, CHEST, 0.0)
	var qt := PhysicsRayQueryParameters3D.create(a, a + side * (HALF * 2.0 + 2.0))
	qt.exclude = skip
	if not space.intersect_ray(qt).is_empty():
		return false
	# The approach, three lines out of the front.
	for s in [-HALF, 0.0, HALF]:
		var from: Vector3 = at + side * s + Vector3(0.0, CHEST, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * APPROACH)
		q.exclude = skip
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _bodies(n: Node) -> Array:
	var out: Array = []
	if n is CollisionObject3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_bodies(c))
	return out
