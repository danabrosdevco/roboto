extends SceneTree

# ─────────────────────────────────────────────
# SMOKE BLOCKS SIGHT AND NOTHING ELSE.
#
# The whole item lives or dies on that sentence. Every AI sight test in this
# project is a raycast, and so is every bullet — so the obvious implementation,
# a volume with a collider, produces a wall you can see through instead of
# smoke you cannot. That failure would not look like a bug in play: it would
# look like the smoke grenade being very good.
#
# So this checks both halves against the same two points:
#   1. Enemy.is_path_clear, the one function every sight question goes through,
#      goes false when smoke sits between them.
#   2. A physics ray over the identical segment still finds nothing, which is
#      what says a round would pass.
#
# And then that sight comes back, because a cloud that never lifts is terrain.
# ─────────────────────────────────────────────

const SMOKE := "res://Character/weapon/smoke_volume.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

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
	var mgr = _find(root, "AIManager")
	level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 20:
		await physics_frame

	var space := player.get_world_3d().direct_space_state
	var ground := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	player.global_position = (ground.call(290.0, 210.0) as Vector3) + Vector3.UP
	for _i in 20:
		await physics_frame

	# Two points with nothing between them, well clear of the terrain.
	var a: Vector3 = (ground.call(300.0, 160.0) as Vector3) + Vector3.UP * 1.4
	var b: Vector3 = (ground.call(300.0, 140.0) as Vector3) + Vector3.UP * 1.4
	var watcher: Node = load(RIFLE).instantiate()
	watcher.faction = Enums.Factions.ENEMY
	watcher.always_active = true
	level.add_child(watcher)
	(watcher as Node3D).global_position = a
	if mgr != null and mgr.has_method("register_enemy"):
		mgr.register_enemy(watcher)
	for _i in 10:
		await physics_frame

	_check("(setup) the two points can see each other to begin with",
		watcher.is_path_clear(a, b), "something is already in the way")

	# ── SMOKE GOES UP BETWEEN THEM ───────────────
	var cloud: Node3D = load(SMOKE).instantiate()
	level.add_child(cloud)
	cloud.global_position = (a + b) * 0.5
	# Past grow_seconds, so the cloud is at full size rather than the puff it
	# starts as — a half-grown cloud blocking is not the claim being tested.
	for _i in 100:
		await physics_frame

	_check("smoke blocks the sight line", not watcher.is_path_clear(a, b))

	# THE OTHER HALF. Same segment, a raw physics ray: if smoke were a body
	# this finds it, and a bullet would stop in the cloud.
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [(watcher as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	_check("...and a round still goes straight through it", hit.is_empty(),
		"a ray hit %s inside the cloud" % (str(hit.get("collider")) if not hit.is_empty() else ""))

	_check("...and it is only blocking where it actually is",
		watcher.is_path_clear(a + Vector3(40, 0, 0), b + Vector3(40, 0, 0)),
		"a cloud 40m away blinded them")

	# ── AND IT LIFTS ─────────────────────────────
	cloud.duration = cloud.fade_seconds + 0.2
	cloud._age = 0.0
	var lifted := false
	for _i in 600:
		await physics_frame
		if not is_instance_valid(cloud):
			lifted = true
			break
	_check("the cloud expires", lifted)
	for _i in 5:
		await physics_frame
	_check("...and sight comes back with it", watcher.is_path_clear(a, b))

	if is_instance_valid(watcher):
		watcher.queue_free()
	await physics_frame

	print("")
	print("SMOKE FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL SMOKE CHECKS PASS")
	quit(1 if _fails > 0 else 0)
