extends SceneTree

# ─────────────────────────────────────────────
# PROBE PIECE BOUNDS — where a placed piece actually is.
#
#   SCENE=res://maps/causeway_art.tscn MATCH=Ramp,Span \
#       godot --path . --script res://tools/probe_piece_bounds.gd
#
# For arguing about placement. The level builders rotate pieces through
# FuncGodot's axis mapping — Quake (x, y, z) becomes Godot (y, z, x) — and a
# block that is not centred on its own origin lands somewhere that is genuinely
# hard to work out on paper. Two people reasoning about it get two answers.
#
# So measure. This prints the world AABB of every matching node's collision,
# which is the thing the physics and the navmesh baker actually see.
# ─────────────────────────────────────────────


func _initialize() -> void:
	var path := OS.get_environment("SCENE")
	if path == "":
		print("FAIL  set SCENE to a .tscn")
		quit(2)
		return
	var filters: Array = []
	if OS.get_environment("MATCH") != "":
		filters = OS.get_environment("MATCH").split(",")

	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s did not load" % path)
		quit(1)
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		print("FAIL  %s is not a Node3D" % path)
		quit(1)
		return
	get_root().add_child(root)
	await process_frame

	print("\n   %s" % path)
	print("   %-22s %9s %9s   %9s %9s   %8s %8s" % [
			"node", "x min", "x max", "z min", "z max", "y min", "y max"])
	var rows: Array = []
	for n: Node3D in root.find_children("*", "Node3D", true, false):
		if not filters.is_empty():
			var keep := false
			for k: String in filters:
				if String(n.name).contains(k):
					keep = true
					break
			if not keep:
				continue
		var box := _bounds(n)
		if box.size.length() < 0.01:
			continue
		rows.append({"n": String(n.name), "b": box})
	rows.sort_custom(func(a, b): return a.b.position.x < b.b.position.x)
	for r: Dictionary in rows:
		var b: AABB = r.b
		print("   %-22s %9.1f %9.1f   %9.1f %9.1f   %8.2f %8.2f" % [
				r.n, b.position.x, b.end.x, b.position.z, b.end.z, b.position.y, b.end.y])
	# Neighbours in x, so a gap or an interpenetration along the run is obvious
	# without doing the arithmetic in your head.
	print("\n   gap (+) or overlap (-) between consecutive pieces along x:")
	for i in range(1, rows.size()):
		var prev: AABB = rows[i - 1].b
		var cur: AABB = rows[i].b
		var d := cur.position.x - prev.end.x
		var flag := "  OVERLAP" if d < -0.01 else ("  gap" if d > 0.01 else "  touching")
		print("   %-22s -> %-22s %7.2f m%s" % [rows[i - 1].n, rows[i].n, d, flag])
	print("\nPIECE BOUNDS DONE")
	quit()


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var dbg := cs.shape.get_debug_mesh()
		if dbg == null:
			continue
		var b := cs.global_transform * dbg.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
