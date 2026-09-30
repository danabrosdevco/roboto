extends SceneTree
# Scratch: measure blocks before placing them. Overlapping two pieces is the
# easiest way to make a level look broken, and the docs round the numbers.
#
#   PIECES=fortifications/fort_hesco_wall,props/prop_jersey_barrier \
#     godot --headless --path . --script res://tools/probe_block_size.gd
#
# Prints the visual AABB and the collision AABB in metres, both in the piece's
# own space, so a placement can be spaced off the real footprint.


func _initialize() -> void:
	await process_frame
	var names := OS.get_environment("PIECES").split(",", false)
	print("   %-38s %-24s %-24s" % ["piece", "visual  x / y / z", "collision  x / y / z"])
	for n: String in names:
		var path := "res://maps/blocks/%s.tscn" % n.strip_edges()
		var packed := load(path) as PackedScene
		if packed == null:
			print("   %-38s could not load" % n)
			continue
		var piece := packed.instantiate() as Node3D
		root.add_child(piece)
		await process_frame
		var vis := _aabb(piece, "VisualInstance3D")
		var col := _aabb(piece, "CollisionShape3D")
		print("   %-38s %-24s %-24s  origin at y=%.2f" % [n.strip_edges(),
				_fmt(vis), _fmt(col), -col.position.y if col.size != Vector3.ZERO else 0.0])
		piece.free()
	quit()


func _aabb(root_node: Node3D, klass: String) -> AABB:
	var out := AABB()
	var first := true
	for c in root_node.find_children("*", klass, true, false):
		var box := AABB()
		if c is VisualInstance3D:
			box = (c as VisualInstance3D).get_aabb()
		else:
			var shape: Shape3D = (c as CollisionShape3D).shape
			if shape == null:
				continue
			box = shape.get_debug_mesh().get_aabb()
		var t: Transform3D = (c as Node3D).global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in 8:
			var w := t * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		var one := AABB(lo, hi - lo)
		out = one if first else out.merge(one)
		first = false
	return out


func _fmt(a: AABB) -> String:
	if a.size == Vector3.ZERO:
		return "-"
	return "%.1f x %.1f x %.1f" % [a.size.x, a.size.y, a.size.z]
