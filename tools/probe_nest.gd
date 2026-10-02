extends SceneTree
# ─────────────────────────────────────────────
# WHAT GOES UP AT A HIVE?
#
# Reported as "hives shooting randomly up into the air". The nest has no weapon
# node and no starting_weapon_id, so it cannot fire; and it is bolted down by
# move_along_nav, which zeroes velocity.x and velocity.z — BUT NOT velocity.y.
# So the two candidates are the nest itself climbing, and the bodies it hatches
# being flung. This watches both.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_nest.gd
# ─────────────────────────────────────────────
const NEST := "res://Character/characters/ai/enemy_nest.tscn"

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
	for _i in 100:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var mgr: Node = _find(root, "AIManager")
	level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(300, 300, 250), Vector3(300, -300, 250))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var ground: Vector3 = hit.position if hit else Vector3(300, -9, 250)

	var nest: Node3D = load(NEST).instantiate()
	nest.faction = Enums.Factions.ENEMY
	# Hatch immediately and often, so 40s is a lot of hatches rather than two.
	nest.first_hatch_seconds = 1.0
	nest.hatch_min_seconds = 1.5
	nest.hatch_max_seconds = 2.0
	nest.max_alive = 12
	level.add_child(nest)
	nest.global_position = ground + Vector3.UP * 1.2
	if mgr != null and mgr.has_method("register_enemy"):
		mgr.register_enemy(nest)

	# Something to fight, or it never opens the hatch.
	var foe: Node3D = load("res://Character/characters/ai/soldier_rifle.tscn").instantiate()
	foe.faction = Enums.Factions.ALLIED
	level.add_child(foe)
	foe.global_position = ground + Vector3(14, 1, 0)
	if mgr != null and mgr.has_method("register_enemy"):
		mgr.register_enemy(foe)
	nest.trigger_combat(foe)

	var y0: float = nest.global_position.y
	var worst_nest_rise := 0.0
	var worst_nest_vy := 0.0
	var born: Array[Node3D] = []
	nest.hatched_body.connect(func(b: Node3D) -> void: born.append(b))
	var worst_hatch := {}

	for f in 2400:                      # 40s at 60Hz
		await physics_frame
		var rise: float = nest.global_position.y - y0
		if rise > worst_nest_rise + 0.25:
			print("  f%-5d NEST rose %6.2f m   vy %6.2f  on_floor=%s" % [
				f, rise, nest.velocity.y, str(nest.is_on_floor())])
		worst_nest_rise = maxf(worst_nest_rise, rise)
		worst_nest_vy = maxf(worst_nest_vy, nest.velocity.y)
		for b in born:
			if b == null or not is_instance_valid(b):
				continue
			var h: float = b.global_position.y - y0
			var prev: float = worst_hatch.get(b.get_instance_id(), -99.0)
			if h > prev:
				worst_hatch[b.get_instance_id()] = h
				if h > 3.0 and h > prev + 1.0:
					print("  f%-5d %s is %5.2f m above the nest   vy %6.2f" % [
						f, b.name, h, b.velocity.y])

	print("")
	print("  nest rose at most %.2f m, worst upward velocity %.2f m/s" % [
		worst_nest_rise, worst_nest_vy])
	var peak := 0.0
	for k in worst_hatch:
		peak = maxf(peak, worst_hatch[k])
	print("  %d hatched; the highest any of them got was %.2f m above the nest" % [
		worst_hatch.size(), peak])
	quit(0)
