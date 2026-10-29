extends SceneTree

# ─────────────────────────────────────────────
# IS THE WAY DOWN ACTUALLY OPEN, OR IS IT IN A BANK OF EARTH?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_bunker_clear.gd
#
# The entrance is raised at a marker, and a marker is only a POSITION — nothing
# about it promises 9 m of clear ground in front of a 9 m door. The Causeway's
# CW_Bunker is a post inside an authored sandbag redoubt, so the kit came up
# half inside the berm with the opening blocked. A screenshot found that; every
# structural probe passed it, because the entrance WAS built, it did have a
# terminal, a dock and working doors, and all of that is true of a door you
# cannot walk through.
#
# So this measures the thing those probes could not see:
#
#   THE APPROACH   can you walk at the door from the front
#   THE THRESHOLD  is the opening itself clear
#   THE SINK       is the lintel above ground, or is the whole thing buried
#
# The mouth faces +Z in the kit's own space, so every cast below is taken in
# the host's basis rather than in world axes — a bunker on a rotated marker
# would otherwise be measured sideways.
# ─────────────────────────────────────────────

# THE SITES ARE DERIVED, NOT TYPED (backlog H14). The table that used to be
# here named the retired maps/hillfort_level.tscn and had never heard of
# maps/hillfort_wip_level.tscn, which is the Hillfort the campaign deploys — so
# the bunker this measured was not the bunker in the game.
const Sites := preload("res://tools/_live_sites.gd")

## How far in front of the door a squad needs to be able to stand.
const APPROACH := 10.0
## Half the door's width, near enough — three casts across it.
const HALF := 3.0
## Chest height on the approach, and inside the opening.
const CHEST := 1.6

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var skipped := Sites.sim_levels()
	if not skipped.is_empty():
		print("sim arenas, not sites, skipped: %s" % ", ".join(skipped))
	print("site         approach        threshold   lintel   verdict")
	for s in Sites.sites():
		await _one(s.label, s.level, s.node)
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, level_path: String, node_name: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 70:
		await physics_frame

	# An empty name is _live_sites saying this level carries no slice script —
	# reported below rather than dropped from the table.
	var slice = level.get_node_or_null(NodePath(node_name)) if node_name != "" else null
	var bunker = slice.get_node_or_null(^"SiteBunker") if slice != null else null
	if bunker == null:
		print("%-12s FAIL — no bunker built" % label)
		_fails += 1
		level.queue_free()
		await process_frame
		return

	var space := root.world_3d.direct_space_state
	var at: Vector3 = (bunker as Node3D).global_position
	var fwd: Vector3 = (bunker as Node3D).global_transform.basis.z.normalized()
	var side: Vector3 = (bunker as Node3D).global_transform.basis.x.normalized()

	# EXCLUDE THE BUNKER'S OWN BODIES, or every cast stops on its own jamb.
	var skip: Array[RID] = []
	for b in _bodies(bunker):
		skip.append(b.get_rid())

	# 1 · THE APPROACH. Three lines out of the door at chest height.
	var blocked := 0.0
	for s in [-HALF, 0.0, HALF]:
		var from: Vector3 = at + side * s + Vector3(0.0, CHEST, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * APPROACH)
		q.exclude = skip
		var h := space.intersect_ray(q)
		if not h.is_empty():
			blocked = maxf(blocked, APPROACH - from.distance_to(h.position))
	var approach_ok: bool = blocked <= 0.01

	# 2 · THE THRESHOLD. Straight across the opening, side to side — if the
	# doorway is packed with earth this is what finds it.
	var a: Vector3 = at - side * (HALF + 1.0) + Vector3(0.0, CHEST, 0.0)
	var qt := PhysicsRayQueryParameters3D.create(a, a + side * (HALF * 2.0 + 2.0))
	qt.exclude = skip
	var thr := space.intersect_ray(qt)
	var threshold_ok: bool = thr.is_empty()

	# 3 · THE SINK. Ground level right at the mouth against the lintel height.
	var qd := PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, 30.0, 0.0), at - Vector3(0.0, 6.0, 0.0))
	qd.exclude = skip
	var down := space.intersect_ray(qd)
	var sunk: float = (down.position.y - at.y) if not down.is_empty() else 0.0
	var lintel_ok: bool = sunk < 2.0

	var bad: Array = []
	if not approach_ok:
		bad.append("approach blocked %.1f m out" % blocked)
	if not threshold_ok:
		bad.append("doorway obstructed")
	if not lintel_ok:
		bad.append("buried %.1f m" % sunk)

	print("%-12s %-15s %-11s %-8s %s" % [
		label,
		"clear" if approach_ok else "BLOCKED %.1fm" % blocked,
		"clear" if threshold_ok else "OBSTRUCTED",
		"ok" if lintel_ok else "+%.1fm" % sunk,
		"ok" if bad.is_empty() else "FAIL: " + str(bad)])
	if not bad.is_empty():
		_fails += 1
	level.queue_free()
	await process_frame


func _bodies(n: Node) -> Array:
	var out: Array = []
	if n is CollisionObject3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_bodies(c))
	return out
