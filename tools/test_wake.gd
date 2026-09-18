extends SceneTree

# ─────────────────────────────────────────────
# WAKE ON DAMAGE — a robot shot from outside its activation distance must
# respond, and so must its squad.
#
# Player hitscan reaches 250m; a chaser's activation distance is 75m. Between
# the two, distance culling returned from the robot's physics tick before any
# movement ran, so it took the damage and died standing still — "drilled from
# range and they don't move". This pins that down, plus the control case: a
# robot that is NOT shot at that range must stay culled, or the fix has quietly
# switched distance culling off for everyone.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _chaser(level: Node, mgr: Node, at: Vector3) -> Soldier:
	var c: Soldier = load("res://Character/characters/ai/enemy_chaser.tscn").instantiate()
	c.faction = Enums.Factions.ENEMY
	c.always_active = true   # what every valley spec sets, and never stopped this
	level.add_child(c)
	c.global_position = at
	if mgr != null:
		mgr.register_enemy(c)
	return c


func _init() -> void:
	await process_frame
	# Autosave off: this reads the save on this machine but must never write it.
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var mgr := _find(root, "AIManager")

	# ON OPEN GROUND. 150m out from homebase is off the edge of its floor, so a
	# robot there simply FALLS — which reads as movement and made the culled
	# control look awake. The valley is where this range actually happens.
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 20:
		await physics_frame
	var space := player.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float) -> Vector3:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z)))
		return (hit.position + Vector3.UP * 1.0) if hit else Vector3(x, -9.0, z)
	player.global_position = ground_at.call(290.0, 160.0)

	# 150m out: inside hitscan range, twice the chaser's activation distance.
	var base: Vector3 = ground_at.call(290.0, 10.0)
	var shot := _chaser(level, mgr, base)
	var mate := _chaser(level, mgr, ground_at.call(293.0, 10.0))
	var control := _chaser(level, mgr, ground_at.call(330.0, 10.0))

	var squad := Squad.new()
	squad.callsign = "TESTPACK"
	squad.squad_members = [shot, mate] as Array[Soldier]
	level.add_child(squad)
	for _i in 30:
		await physics_frame

	var p_shot := shot.global_position
	var p_mate := mate.global_position
	var p_ctrl := control.global_position

	shot.apply_damage(5, player)
	for _i in 180:
		await physics_frame

	var flat := func(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()
	var moved_shot: float = flat.call(shot.global_position, p_shot)
	var moved_mate: float = flat.call(mate.global_position, p_mate)
	var moved_ctrl: float = flat.call(control.global_position, p_ctrl)
	print("      moved in 3s — shot %.1fm, squadmate %.1fm, control %.1fm" % [moved_shot, moved_mate, moved_ctrl])

	_check("the robot you shot responds", moved_shot > 5.0, "%.1fm" % moved_shot)
	_check("...and so does its squad", moved_mate > 5.0, "%.1fm" % moved_mate)
	_check("an unshot robot at the same range stays culled", moved_ctrl < 0.5, "%.1fm" % moved_ctrl)
	_check("...and closes on whoever shot it",
		shot.global_position.distance_to(player.global_position) < p_shot.distance_to(player.global_position))

	# ── A GARRISONED HOPPER, SHOT UP CLOSE ──────
	# The same scene the Hatchling canister throws, and those charged fine. On a
	# garrison post it stood still at 10m: DEFEND switches defensive_mode on,
	# which re-rolled every MOVE into AIM/FIRE, and the 9m combat leash dragged
	# it back to its post whenever it did get going.
	for r in [shot, mate, control]:
		if mgr != null:
			mgr.deregister_enemy(r)
		r.queue_free()
	var post: Vector3 = ground_at.call(200.0, 120.0)
	var hopper: Soldier = load("res://Character/characters/ai/enemy_nest-chaser.tscn").instantiate()
	hopper.faction = Enums.Factions.ENEMY
	level.add_child(hopper)
	hopper.global_position = post
	if mgr != null:
		mgr.register_enemy(hopper)
	var guard := Squad.new()
	guard.callsign = "GARRISON"
	guard.squad_members = [hopper] as Array[Soldier]
	level.add_child(guard)
	# Player well out of sight while it takes up the post.
	player.global_position = ground_at.call(200.0, 40.0)
	for _i in 10:
		await physics_frame
	guard.set_objective(Squad.SquadObjective.DEFEND, post, true)
	for _i in 240:
		await physics_frame
	_check("(setup) the hopper is dug in on its post", hopper.defensive_mode,
		"defensive_mode=%s state=%s" % [hopper.defensive_mode, hopper.ai_state])

	var stand: Vector3 = hopper.global_position + Vector3(10.0, 0.0, 0.0)
	player.global_position = ground_at.call(stand.x, stand.z)
	await physics_frame
	var d0: float = flat.call(hopper.global_position, player.global_position)
	hopper.apply_damage(5, player)
	for _i in 180:
		await physics_frame
	var d1: float = flat.call(hopper.global_position, player.global_position)
	print("      garrisoned hopper: %.1fm away when shot, %.1fm after 3s" % [d0, d1])
	_check("a garrisoned hopper shot from 10m comes for you", d1 < d0 - 5.0 or d1 < 2.5,
		"%.1fm -> %.1fm" % [d0, d1])

	# ...AND WHEN IT DIES IT SETTLES, RATHER THAN SINKING OUT OF SIGHT. The sink
	# was a flat 0.7m, tuned on 2m frames; a 1m hopper went almost entirely
	# through the deck. It now scales with body height: 0.35m for a hopper.
	hopper.apply_damage(9999, player)
	for _i in 240:
		await physics_frame
	var sunk: float = hopper._settle_rest_y - hopper.global_position.y
	print("      dead hopper sank %.2fm (a 2m frame sinks 0.70m)" % sunk)
	_check("a dead hopper sinks in proportion to its size", sunk > 0.25 and sunk < 0.45, "%.2fm" % sunk)

	# ── ONE THAT FALLS OUT OF THE WORLD ─────────
	# Nothing used to catch this: it fell forever, still alive, and held an
	# arena's EliminateObjective at 7/8 with nothing left standing.
	var lost := _chaser(level, mgr, Vector3(5000.0, 0.0, 5000.0))
	for _i in 420:
		await physics_frame
	_check("a robot that falls out of the level counts as down", not lost.alive,
		"y=%.0f vy=%.0f" % [lost.global_position.y, lost.velocity.y])

	print("")
	print("ALL WAKE CHECKS PASS" if _fails == 0 else "%d WAKE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
