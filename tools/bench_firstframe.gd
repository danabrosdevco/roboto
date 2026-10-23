extends SceneTree
# WHICH PART of a robot's first physics frame costs 8.9 ms. Bisected by standing
# up the same wave under different conditions and timing frame +0.
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")

var _level: Node = null
var _mgr: Node = null
var _centre: Vector3 = Vector3.ZERO

func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _wave(n: int, active: bool, register: bool, order: bool, strip_csg: bool = false, bake: bool = false) -> float:
	var made: Array = []
	for _i in n:
		var b: Node = _CsgBake.make(load(RIFLE)) if bake else load(RIFLE).instantiate()
		if strip_csg:
			for c in b.get_children():
				if c is CSGShape3D:
					b.remove_child(c)
					c.free()
		b.faction = Enums.Factions.ENEMY
		b.always_active = active
		_level.add_child(b)
		(b as Node3D).global_position = _centre + Vector3(randf_range(-25, 25), 1, randf_range(-25, 25))
		if register and _mgr != null and _mgr.has_method("register_enemy"):
			_mgr.register_enemy(b)
		if order:
			b.move_to(_centre)
		made.append(b)
	var t0 := Time.get_ticks_usec()
	await physics_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	# Let it settle, then clear up so the next condition starts from the same place.
	for _i in 20:
		await physics_frame
	for b in made:
		if is_instance_valid(b):
			b.free()
	for _i in 20:
		await physics_frame
	return ms

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	_level = player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/pittsburgh_level.tscn").instantiate())
	for _i in 40:
		await physics_frame
	_centre = NavigationServer3D.map_get_closest_point(
		player.get_world_3d().navigation_map, Vector3(300, 0, 250))

	seed(20261001)
	print("")
	print("FIRST-FRAME COST OF A 40-ROBOT WAVE — Three Rivers")
	print("  %-46s %8.1f ms" % ["everything (active, registered, ordered)",
		await _wave(40, true, true, true)])
	print("  %-46s %8.1f ms" % ["...without the move order",
		await _wave(40, true, true, false)])
	print("  %-46s %8.1f ms" % ["...without registering with AIManager",
		await _wave(40, true, false, true)])
	print("  %-46s %8.1f ms" % ["...not always_active (distance culling on)",
		await _wave(40, false, true, true)])
	print("  %-46s %8.1f ms" % ["in the tree only: no register, no order, culled",
		await _wave(40, false, false, false)])
	print("")
	print("  %-46s %8.1f ms" % ["SAME WAVE WITH THE CSGMesh3D NODES REMOVED",
		await _wave(40, true, true, true, true)])
	print("  %-46s %8.1f ms" % ["SAME WAVE BUILT THROUGH CsgBake.make()",
		await _wave(40, true, true, true, false, true)])
	print("")
	print("  for scale, a 4-robot wave with everything:")
	print("  %-46s %8.1f ms" % ["4 robots", await _wave(4, true, true, true)])
	quit(0)
