extends SceneTree
# What does standing one robot up actually cost, and which part of it?
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
	var mgr: Node = _find(root, "AIManager")
	level.add_child(load("res://maps/pittsburgh_level.tscn").instantiate())
	for _i in 40:
		await physics_frame
	var nmap: RID = player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))

	var packed := load(RIFLE) as PackedScene
	var reps := 40

	# 1. instantiate() only — building the node tree, no tree entry.
	var made: Array = []
	var t0 := Time.get_ticks_usec()
	for _i in reps:
		made.append(packed.instantiate())
	var t_inst := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0

	# 2. add_child() — _ready, CSG rebuilds, physics and nav registration.
	t0 = Time.get_ticks_usec()
	for n in made:
		level.add_child(n)
	var t_add := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0

	# 3. placing and registering them.
	t0 = Time.get_ticks_usec()
	for n in made:
		(n as Node3D).global_position = centre + Vector3(randf_range(-20, 20), 1, randf_range(-20, 20))
		if mgr != null and mgr.has_method("register_enemy"):
			mgr.register_enemy(n)
	var t_reg := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0

	# 4. the first move order.
	t0 = Time.get_ticks_usec()
	for n in made:
		n.move_to(centre)
	var t_move := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0

	print("")
	print("SPAWN COST — soldier_rifle, %d of them, on Three Rivers" % reps)
	print("  instantiate()                %7.3f ms each   (%6.1f ms for %d)" % [t_inst, t_inst * reps, reps])
	print("  add_child()                  %7.3f ms each   (%6.1f ms for %d)" % [t_add, t_add * reps, reps])
	print("  position + register_enemy    %7.3f ms each   (%6.1f ms for %d)" % [t_reg, t_reg * reps, reps])
	print("  first move_to()              %7.3f ms each   (%6.1f ms for %d)" % [t_move, t_move * reps, reps])
	print("  ──")
	print("  TOTAL                        %7.3f ms each   (%6.1f ms for %d)" % [
		t_inst + t_add + t_reg + t_move, (t_inst + t_add + t_reg + t_move) * reps, reps])

	# What is IN the scene that costs this much to build?
	var counts := {}
	var probe: Node = packed.instantiate()
	var stack: Array = [probe]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var k := n.get_class()
		counts[k] = int(counts.get(k, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	probe.free()
	# THE FRAMES AFTER. Standing them up is cheap; what costs is every one of them
	# running its FIRST _physics_process on the same tick — first target search,
	# first path resolution, first combat roll, all 40 at once.
	print("")
	print("  the frames after the wave lands:")
	for i in 8:
		var f0 := Time.get_ticks_usec()
		await physics_frame
		print("     frame +%d  %7.1f ms" % [i, float(Time.get_ticks_usec() - f0) / 1000.0])

	print("")
	print("  what the scene is made of:")
	var keys: Array = counts.keys()
	keys.sort()
	for k in keys:
		print("     %-26s %d" % [k, counts[k]])
	quit(0)
