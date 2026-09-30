extends SceneTree

# ─────────────────────────────────────────────
# SCATTER TESTS
#
# A scatter layer does not use its props' own collision. It draws them as
# MultiMeshes and gives each one a cylinder of `collision_radius`, and that
# cylinder is what the navmesh bake sees. So a layer can quietly put a 1.8 m
# collider round a knee-high stone, and every one of them punches a hole in
# the navmesh with a fan of triangles round it. That is what scatter_boulders
# did: it spread prop_boulder_a, 1.1 m across, shrank it to 0.7 of that, and
# wrapped it in a 0.9 m radius cylinder 2.5 m tall.
#
# The rule here: a layer's collider has to FIT INSIDE the smallest thing the
# layer spreads, at the smallest scale it spreads it. A collider bigger than
# its prop is a wall round nothing.
#
# A layer that spreads ground detail should have no collider at all. That is
# not something a test can judge, so it only checks the sizes; the judgement
# is in docs/BLOCKS.md.
# ─────────────────────────────────────────────

const DIR := "res://maps/blocks/scatter"
## How much of the prop's own half-width the cylinder may take up. Under 1.0
## because a prop's widest point is rarely at the ground.
const FIT := 0.75
const WATCHDOG_S := 120

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s" % WATCHDOG_S)
		quit(2))
	await process_frame
	var files := Array(DirAccess.get_files_at(DIR)).filter(
			func(f: String) -> bool: return f.ends_with(".tres"))
	files.sort()
	_check("there are scatter layers in %s" % DIR, not files.is_empty())
	for f: String in files:
		_layer(DIR.path_join(f))
	print("")
	print("ALL SCATTER CHECKS PASS" if _fails == 0 else "%d SCATTER CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _layer(path: String) -> void:
	var layer = load(path)
	if layer == null:
		_check("%s loads" % path.get_file(), false, "load() returned null")
		return
	var name := path.get_file().get_basename()
	var radius: float = layer.collision_radius
	if radius <= 0.0:
		return   # spreads detail, collides with nothing — the quiet good case
	var min_scale: float = layer.min_scale
	var narrowest := 1e9
	var narrowest_name := "-"
	for packed: PackedScene in layer.scenes:
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		var box := _footprint(node)
		node.free()
		# The average of the two sides, not the narrow one: a jersey barrier is
		# long and thin, and no cylinder can fit across it.
		var w: float = (box.x + box.y) * 0.5
		if w > 0.0 and w < narrowest:
			narrowest = w
			narrowest_name = packed.resource_path.get_file().get_basename()
	if narrowest > 1e8:
		_check("%s: its scenes have geometry to measure" % name, false)
		return
	var allowed: float = narrowest * 0.5 * min_scale / FIT
	_check("%s: its %.2f m collider fits the smallest thing it spreads" % [name, radius],
			radius <= allowed,
			"%s is %.2f m across and is scattered down to %.0f%%, which allows %.2f m" % [
					narrowest_name, narrowest, min_scale * 100.0, allowed])


## How wide the prop is on the ground, from its collision if it has any and its
## meshes if it does not — a layer draws the mesh either way.
func _footprint(node: Node3D) -> Vector2:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var piece := mi.transform * mi.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	if first:
		return Vector2.ZERO
	return Vector2(box.size.x, box.size.z)
