extends SceneTree
# Two robots overlapping. How far do they actually travel, and how fast?
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
	for _i in 100:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var mgr: Node = _find(root, "AIManager")
	level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	var space := player.get_world_3d().direct_space_state
	var ground := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)

	for overlap in [0.0, 0.25, 0.6]:
		var at := (ground.call(300.0, 250.0) as Vector3) + Vector3.UP
		var a: Node3D = load(RIFLE).instantiate()
		var b: Node3D = load(RIFLE).instantiate()
		a.faction = Enums.Factions.ENEMY
		b.faction = Enums.Factions.ALLIED
		level.add_child(a)
		level.add_child(b)
		# Overlapping by `overlap` of a body width, which is what two robots
		# walking into each other produce for a frame.
		a.global_position = at
		b.global_position = at + Vector3(maxf(0.01, 1.0 - overlap), 0, 0)
		if mgr != null and mgr.has_method("register_enemy"):
			mgr.register_enemy(a)
			mgr.register_enemy(b)
		var a0: Vector3 = a.global_position
		var b0: Vector3 = b.global_position
		var worst_speed := 0.0
		var prev_a: Vector3 = a.global_position
		for f in 300:
			await physics_frame
			var sp := Vector2(a.velocity.x, a.velocity.z).length()
			var step := Vector2(a.global_position.x - prev_a.x, a.global_position.z - prev_a.z).length()
			prev_a = a.global_position
			if sp > worst_speed and sp > 8.0:
				print("     f%-4d A speed %6.2f  step %5.3f m  state=%s  touching=%s  giveway=%.2f" % [
					f, sp, step, str(a.movement_state),
					str(a.get("_touching") != null), a.get("_give_way_t")])
			worst_speed = maxf(worst_speed, sp)
			worst_speed = maxf(worst_speed, Vector2(b.velocity.x, b.velocity.z).length())
		var da := Vector2(a.global_position.x - a0.x, a.global_position.z - a0.z).length()
		var db := Vector2(b.global_position.x - b0.x, b.global_position.z - b0.z).length()
		print("  overlap %.2f m -> after 5s A moved %6.2f m, B moved %6.2f m, worst speed %5.2f m/s" % [
			overlap, da, db, worst_speed])
		a.free()
		b.free()
		for _i in 10:
			await physics_frame
	quit(0)
