extends SceneTree
# ─────────────────────────────────────────────
# DOES THE WALKER'S AUTOCANNON EVER FIRE?
#
# Reported: the Walker only ever uses the heavy MG. The frame carries two guns —
# the autocannon is slot 0, the MAIN gun, fitted on recruit from
# chassis_walker.starting_weapon_id; the MG is slot 1, the coax, bought
# separately. The main gun drives the combat state machine and fires through
# Enemy.fire(); the coax has no decisions and fires from Enemy._tick_coax
# whenever the turret is already on target.
#
# Counts rounds actually leaving each by watching magazine_current, which fire()
# decrements, so neither gun can claim a shot it did not take.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_walker_guns.gd
# ─────────────────────────────────────────────

func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/appendix/valley_level.tscn").instantiate())
	for _i in 180:
		await physics_frame
	var mgr: Node = _find(root, "AIManager")
	var cm: Node = world.get_node("CampaignManager")
	var cat = cm.catalogue

	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(300, 300, 250), Vector3(300, -300, 250))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var ground: Vector3 = hit.position if hit else Vector3(300, -9, 250)

	var w: Node3D = load("res://Character/characters/ai/walker.tscn").instantiate()
	w.faction = Enums.Factions.ENEMY
	level.add_child(w)
	w.global_position = ground + Vector3.UP
	if mgr != null:
		mgr.register_enemy(w)
	await process_frame
	# Exactly what a recruited Walker carries: autocannon in the main mount,
	# machine gun in the coax (chassis_walker's own starting_weapon_id and
	# coax_weapon_id).
	w.equip_weapon_scene(cat.item(&"autocannon").ai_scene)
	w.equip_coax_scene(cat.item(&"machine_gun").ai_scene)
	await process_frame
	print("  main = %s   coax = %s" % [
		w.weapon.name if w.weapon != null else "NONE",
		w.coax.name if w.coax != null else "NONE"])

	# A target it can see, well inside both bands.
	# ON THE MOVE, which is the case that was broken: a stationary Walker always
	# settled and fired fine.
	var foe: Node3D = load("res://Character/characters/ai/soldier_rifle.tscn").instantiate()
	foe.faction = Enums.Factions.ALLIED
	foe.max_health = 100000
	foe.health = 100000
	level.add_child(foe)
	foe.global_position = ground + Vector3(28, 1, 0)
	if mgr != null:
		mgr.register_enemy(foe)
	await process_frame
	w.trigger_combat(foe)
	if OS.get_cmdline_user_args().has("--moving"):
		w.order_move_to(ground + Vector3(-60, 0, 40), true, true)
		print("  (walker ordered to move while engaging)")

	var main_shots := 0
	var coax_shots := 0
	var main_prev: int = w.weapon.magazine_current
	var coax_prev: int = w.coax.magazine_current
	for f in 3600:                       # 60 s
		await physics_frame
		if OS.get_cmdline_user_args().has("--moving") and f % 600 == 0:
			w.order_move_to(ground + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60)), true, true)
		if w.weapon != null:
			var m: int = w.weapon.magazine_current
			if m < main_prev:
				main_shots += main_prev - m
			main_prev = m
		if w.coax != null:
			var c: int = w.coax.magazine_current
			if c < coax_prev:
				coax_shots += coax_prev - c
			coax_prev = c
	print("  over 60s:  autocannon fired %d rounds,  coax MG fired %d rounds" % [main_shots, coax_shots])
	print("  walker state=%s  target=%s  los=%s  dist=%.1f m" % [
		str(w.ai_state), "yes" if w.combat_target != null else "no",
		str(w.get("_has_los")), w.global_position.distance_to(foe.global_position)])
	quit(0)
