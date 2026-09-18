extends SceneTree

# ─────────────────────────────────────────────
# DRONE SIM — flies two bomber drones at a target on open valley ground and
# reports what they actually did: phase timeline, bombs dropped vs detonated,
# how close the pair came to each other, and where the bombs landed against
# both the target and the bombsight's own prediction.
#
# Built while reworking the drone, where it caught four bugs in a row that
# read identically from the outside ("the bombs miss"): a steering loop that
# could not turn, stick-mates detonating each other on release, a release
# window with no upper bound, and — the one that wasted the most time — a
# test run at homebase, whose walls caught the bombs mid-flight.
#
# Run it on OPEN GROUND. The numbers mean nothing indoors.
#
#   godot --headless --path . --script tools/drone_sim.gd
# ─────────────────────────────────────────────

const NAMES := ["LOITER", "APPROACH", "RUN", "EXTEND"]

func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null: return f
	return null

func _init() -> void:
	await process_frame
	root.add_child(load("res://Env/world.tscn").instantiate())
	for _i in 120:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	player.set("max_health", 999999); player.set("health", 999999)
	var level: Node = player.get_parent()
	# OPEN GROUND. Every earlier run of this was at homebase, whose walls caught
	# the bombs mid-flight and made the drone look 20m inaccurate. Test where the
	# drones actually fight.
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 20:
		await physics_frame
	var probe := PhysicsRayQueryParameters3D.create(Vector3(290, 200, 160), Vector3(290, -200, 160))
	var hit := player.get_world_3d().direct_space_state.intersect_ray(probe)
	var ground_y: float = hit.position.y if hit else -10.0
	player.global_position = Vector3(290, ground_y + 1.0, 160)
	print("target on open valley ground at %s" % str(player.global_position.round()))
	var aim_mgr := _find(root, "AIManager")

	var scene := load("res://Character/characters/ai/enemy_helicopter.tscn")
	var drones: Array = []
	for i in 2:
		var d = scene.instantiate()
		level.add_child(d)
		if aim_mgr != null: aim_mgr.register_enemy(d)
		d.player = player
		d.always_active = true
		# Spawned only 3m apart — the spacing a two-drone reserve really gets.
		d.global_position = player.global_position + Vector3(70 + i * 3, 0, -40)
		drones.append(d)
	for _i in 3:
		await physics_frame
	for d in drones:
		d.combat_target = player
		d.ai_state = Enemy.AIState.COMBAT

	var last_phase := [-1, -1]
	var min_sep := 9999.0
	var tracked := {}
	var done := {}
	var fuse_log: Array[String] = []
	var pred_log: Array[String] = []
	var pred_of := {}
	var pred_err: Array[String] = []
	var aim_of := {}
	var vs_aim: Array[float] = []
	var downed_logged := [false, false]
	var min_sep_flying := 9999.0
	var impacts: Array[float] = []
	var dropped := 0
	var t := 0.0
	while t < 30.0:
		await physics_frame
		t += 1.0 / 60.0
		for i in drones.size():
			var d = drones[i]
			if not is_instance_valid(d): continue
			var ph: int = d.get("_phase")
			if d.downed and not downed_logged[i]:
				downed_logged[i] = true
				print("  t=%5.2f  drone%d  SHOT DOWN" % [t, i])
			if ph != last_phase[i]:
				print("  t=%5.2f  drone%d  %-8s" % [t, i, NAMES[ph]])
				last_phase[i] = ph
		min_sep = minf(min_sep, drones[0].global_position.distance_to(drones[1].global_position))
		if t > 2.0:
			min_sep_flying = minf(min_sep_flying, drones[0].global_position.distance_to(drones[1].global_position))
		for c in level.get_children():
			if c is RigidBody3D and c.has_method("setup") and not tracked.has(c) and not done.has(c):
				tracked[c] = c.global_position
				dropped += 1
				var nd = drones[0] if (not is_instance_valid(drones[1]) or (is_instance_valid(drones[0]) and drones[0].global_position.distance_to(c.global_position) < drones[1].global_position.distance_to(c.global_position))) else drones[1]
				aim_of[c] = nd.get("_aim")
				if pred_log.size() < 5:
					var pi: Vector3 = nd.call("_predicted_impact")
					pred_of[c] = pi
					pred_log.append("rel_v=%s drone_v=%s  pred_impact_vs_aim=%.1fm" % [str(c.linear_velocity.round()), str(nd.velocity.round()), Vector2(pi.x - nd.get("_aim").x, pi.z - nd.get("_aim").z).length()])
		for g in tracked.keys():
			if not is_instance_valid(g):
				var p: Vector3 = tracked[g]
				impacts.append(Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length())
				vs_aim.append(Vector2(p.x - aim_of[g].x, p.z - aim_of[g].z).length())
				tracked.erase(g)
				done[g] = true
			elif g.freeze:
				if fuse_log.size() < 6:
					fuse_log.append("fuse=%.2fs bounces=%d contact_monitor=%s" % [g.get("_fuse_timer"), g.get("_bounce_count"), str(g.contact_monitor)])
				var p2: Vector3 = g.global_position
				impacts.append(Vector2(p2.x - player.global_position.x, p2.z - player.global_position.z).length())
				vs_aim.append(Vector2(p2.x - aim_of[g].x, p2.z - aim_of[g].z).length())
				if pred_of.has(g):
					pred_err.append("actual vs predicted impact: %.1fm   (actual y=%.1f, aim y=%.1f)" % [Vector2(p2.x - pred_of[g].x, p2.z - pred_of[g].z).length(), p2.y, aim_of[g].y])
				tracked.erase(g)
				done[g] = true
			else:
				tracked[g] = g.global_position

	print("")
	print("dropped %d, detonated %d" % [dropped, impacts.size()])
	print("closest the drones came to each other: %.1fm at spawn, %.1fm once flying" % [min_sep, min_sep_flying])
	if not impacts.is_empty():
		impacts.sort()
		var s := 0.0
		var within5 := 0
		var within10 := 0
		for v in impacts:
			s += v
			if v <= 5.0: within5 += 1
			if v <= 10.0: within10 += 1
		print("impact distance from target: median %.1fm  mean %.1fm  best %.1fm" % [
			impacts[impacts.size() / 2], s / impacts.size(), impacts[0]])
		print("  within 5m: %d/%d    within 10m: %d/%d" % [within5, impacts.size(), within10, impacts.size()])
	if not vs_aim.is_empty():
		vs_aim.sort()
		var w5 := 0
		for v in vs_aim:
			if v <= 5.0: w5 += 1
		print("vs the drone's own aim point: median %.1fm  best %.1fm  within 5m %d/%d" % [vs_aim[vs_aim.size() / 2], vs_aim[0], w5, vs_aim.size()])
	for l in pred_log:
		print("  release: " + l)
	for l in pred_err:
		print("  " + l)
	for l in fuse_log:
		print("  detonated: " + l)
	print("DRONE DIAG DONE")
	quit()
