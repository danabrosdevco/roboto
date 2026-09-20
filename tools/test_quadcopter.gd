extends SceneTree

# ─────────────────────────────────────────────
# QUADCOPTER BOMBER TESTS
#
# Two things that were both invisible until someone played a mission and told
# us, and both cheap to hold onto here.
#
# 1. SHOT DOWN, IT FLIES ITS WRECK INTO THE GROUND. enter_downed() zeroes
#    velocity, which is right for something standing on the ground and turned a
#    drone doing 27 m/s into a brick that dropped straight down the instant it
#    died. The crash keeps most of its speed now, so the check is that a
#    quadcopter killed in level flight lands well AHEAD of where it was hit.
#
# 2. THE KILL IS FILED UNDER A FRAME THAT EXISTS. The debrief tallies kills by
#    `chassis_id`, and the drone's chassis lost its id — it came back as the
#    ChassisDefinition script's own default, `light`, which is not a kind the
#    kill table knows. The kill stopped appearing on the mission-complete
#    screen. The last check here walks EVERY chassis, because the way that id
#    was lost (an open editor rewriting a resource when a new property arrived)
#    can hit any of them, and it is silent.
# ─────────────────────────────────────────────

const HELI := "res://Character/characters/ai/enemy_helicopter.tscn"
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
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


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _init() -> void:
	await process_frame
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var mgr = _find(root, "AIManager")
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 20:
		await physics_frame
	var space := player.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	player.global_position = ground_at.call(290.0, 210.0) + Vector3.UP
	for _i in 20:
		await physics_frame

	# ── SHOT DOWN IN LEVEL FLIGHT ────────────────
	var drone: Enemy = load(HELI).instantiate()
	drone.faction = Enums.Factions.ENEMY
	drone.always_active = true
	level.add_child(drone)
	var start: Vector3 = ground_at.call(300.0, 150.0) + Vector3.UP * 14.0
	drone.global_position = start
	if mgr != null:
		mgr.register_enemy(drone)
	for _i in 10:
		await physics_frame
	# Flying, not hovering: the crash has to have something to carry.
	var heading := Vector3(0.0, 0.0, -1.0)
	drone.velocity = heading * drone.run_speed
	await physics_frame
	var speed_at_death: float = _flat(drone.velocity).length()
	var hit_at: Vector3 = drone.global_position
	_check("(setup) a quadcopter doing %.0f m/s at %.0fm up" % [speed_at_death, start.y - ground_at.call(300.0, 150.0).y],
		speed_at_death > 10.0, "%.1f m/s" % speed_at_death)

	drone.apply_damage(99999, player)
	var lowest := INF
	for _i in 300:
		await physics_frame
		lowest = minf(lowest, drone.global_position.y)
		if not drone._crashing:
			break
	var carried: float = _flat(drone.global_position - hit_at).length()
	var fell: float = hit_at.y - drone.global_position.y
	print("      crashed %.1fm ahead of where it was hit, %.1fm down" % [carried, fell])
	_check("shot down, it carries its momentum into the ground", carried > 8.0,
		"%.1fm ahead" % carried)
	_check("...still going the way it was flying", carried < 60.0 and fell > 4.0,
		"%.1fm ahead, %.1fm down" % [carried, fell])
	_check("...and it is down, not hanging in the air", drone.downed and not drone._crashing)

	# ── THE KILL IS FILED SOMEWHERE REAL ─────────
	var kind := _KillKinds.kind_of(drone)
	var frame := _KillKinds.frame_of(kind)
	_check("the kill is filed under a kind the table knows", frame != null,
		"kind '%s'" % str(kind))
	_check("...which reads as the quadcopter bomber, not a chassis id",
		frame != null and frame.display_name == "Quadcopter Bomber",
		frame.display_name if frame != null else "no frame")
	_check("...and the player is credited with it by kind",
		int(player.kills_by_kind.get(kind, 0)) == 1 and player.confirmed_kills >= 1,
		str(player.kills_by_kind))

	# A drone the mission spawner built carries its frame as meta, which is the
	# path the debrief actually takes in a real game. Never added to the tree:
	# kind_of() reads the scene path and the meta, neither of which needs a
	# live node, and a robot spawned and freed in the same breath takes the
	# process down on the way out (see tools/test_wake.gd).
	var spawned: Enemy = load(HELI).instantiate()
	spawned.set_meta(&"chassis_id", load("res://Campaign/chassis/chassis_helicopter.tres").id)
	_check("...by the same kind when the spawner stamped its frame on it",
		_KillKinds.kind_of(spawned) == kind, str(_KillKinds.kind_of(spawned)))
	spawned.free()

	# ── NO CHASSIS FILES ITS KILLS NOWHERE ───────
	# The guard against how this broke: a chassis whose id is not a kind is a
	# frame whose kills land in a bucket with no name and no icon.
	var orphans: Array = []
	for file in DirAccess.get_files_at("res://Campaign/chassis"):
		if not file.ends_with(".tres"):
			continue
		var def: ChassisDefinition = load("res://Campaign/chassis/" + file)
		if def == null:
			continue
		if not _KillKinds.FRAMES.has(def.id):
			orphans.append("%s -> '%s'" % [file, str(def.id)])
	_check("every chassis id is a kill kind the debrief can draw", orphans.is_empty(),
		", ".join(orphans))

	print("")
	print("ALL QUADCOPTER CHECKS PASS" if _fails == 0 else "%d QUADCOPTER CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
