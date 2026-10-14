extends SceneTree
# Two questions that decide how to kill the CSG spawn cost:
#   1. Does get_meshes() hand back a mesh we can actually reuse?
#   2. Does a POOLED robot — kept in the tree, hidden, re-shown — avoid the
#      rebuild, or does it pay again?
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/pittsburgh_level.tscn").instantiate())
	for _i in 40:
		await physics_frame
	var centre := Vector3(300, 2, 250)

	# ── 1. IS THE BAKED MESH USABLE? ─────────────
	var one: Node3D = load(RIFLE).instantiate()
	level.add_child(one)
	one.global_position = centre
	for _i in 6:
		await physics_frame
	print("")
	print("BAKED MESH FROM get_meshes()")
	for c in one.get_children():
		if c is CSGShape3D:
			var csg := c as CSGShape3D
			var m: Array = csg.get_meshes()
			if m.size() < 2 or m[1] == null:
				print("  %-14s get_meshes() gave nothing" % csg.name)
				continue
			var mesh: Mesh = m[1]
			print("  %-14s surfaces %d, aabb %s" % [csg.name, mesh.get_surface_count(), str(mesh.get_aabb().size)])
			print("  %-14s csg aabb %s   material_override %s" % ["", str(csg.get_aabb().size),
				"set" if csg.material_override != null else "none"])
	one.free()
	for _i in 10:
		await physics_frame

	# ── 2. DOES A POOLED ROBOT PAY AGAIN? ────────
	print("")
	print("POOLING — 40 robots, kept in the tree")
	var pool: Array = []
	for _i in 40:
		var b: Node3D = load(RIFLE).instantiate()
		b.faction = Enums.Factions.ENEMY
		level.add_child(b)
		b.global_position = centre + Vector3(randf_range(-25, 25), 1, randf_range(-25, 25))
		pool.append(b)
	var t0 := Time.get_ticks_usec()
	await physics_frame
	print("  first frame, freshly added          %7.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	for _i in 30:
		await physics_frame

	# Retire them the way a pool would: hide and stop processing, stay in tree.
	for b in pool:
		b.visible = false
		b.set_physics_process(false)
		b.process_mode = Node.PROCESS_MODE_DISABLED
	for _i in 20:
		await physics_frame
	# Bring them back.
	for b in pool:
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.set_physics_process(true)
		b.visible = true
		b.global_position = centre + Vector3(randf_range(-25, 25), 1, randf_range(-25, 25))
	t0 = Time.get_ticks_usec()
	await physics_frame
	print("  re-shown from the pool              %7.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))

	# And removing from the tree then re-adding, which is what a naive pool does.
	for b in pool:
		level.remove_child(b)
	for _i in 10:
		await physics_frame
	for b in pool:
		level.add_child(b)
	t0 = Time.get_ticks_usec()
	await physics_frame
	print("  removed from the tree and re-added  %7.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	quit(0)
