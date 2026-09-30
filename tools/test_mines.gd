extends SceneTree

# ─────────────────────────────────────────────
# MINES ONLY EVER ANSWER TO THE OTHER SIDE.
#
# This is the one property the item cannot ship without. The squad pathfinds on
# its own: it will walk over anything you put down, and you will not be able to
# stop it. A mine that goes off under a friendly is not a balance problem, it
# is an item nobody ever places again — so the faction gate is the feature, and
# a silent regression in it would look exactly like bad luck.
#
# Three things, in the order they would break:
#   1. It does not arm the instant it lands. You get a window to walk away.
#   2. An armed player mine ignores an ally standing on top of it.
#   3. The same mine, same spot, kills an enemy that steps on it.
#
# Check 3 exists so that 2 cannot pass by the mine simply being broken — an
# inert mine ignores allies beautifully.
# ─────────────────────────────────────────────

const MINE := "res://Character/weapon/mines/mine_heavy.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fails := 0
var _level: Node = null
var _mgr: Node = null
var _ground: Callable
var _player: Node3D = null


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
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 20:
		await physics_frame
	var space := _player.get_world_3d().direct_space_state
	_ground = func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	# Well away from the mine, or the player IS the hostile that sets it off.
	_player.global_position = (_ground.call(290.0, 210.0) as Vector3) + Vector3.UP
	for _i in 20:
		await physics_frame

	await _run()
	await _test_settle()
	await _test_parenting()

	print("")
	print("MINE FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL MINE CHECKS PASS")
	quit(1 if _fails > 0 else 0)


func _spawn_body(at: Vector3, faction: int) -> Node:
	var body: Node = load(RIFLE).instantiate()
	body.faction = faction
	body.always_active = true
	_level.add_child(body)
	(body as Node3D).global_position = at
	if _mgr != null and _mgr.has_method("register_enemy"):
		_mgr.register_enemy(body)
	return body


func _lay_mine(at: Vector3) -> Node:
	var mine: Node = load(MINE).instantiate()
	# setup() before the tree, the contract every projectile here uses: the
	# faction gate reads _thrower, so a mine that entered first is a mine with
	# no side.
	mine.setup(_player)
	_level.add_child(mine)
	(mine as Node3D).global_position = at
	return mine


func _run() -> void:
	var spot: Vector3 = (_ground.call(300.0, 150.0) as Vector3) + Vector3.UP * 0.3
	var mine: Node = _lay_mine(spot)
	for _i in 3:
		await physics_frame
	_check("a mine does not arm the moment it lands", not mine._armed)

	# ── AN ALLY STANDS ON IT ─────────────────────
	var ally: Node = _spawn_body(spot + Vector3(0.3, 1.0, 0.0), Enums.Factions.ALLIED)
	for _i in 180:
		await physics_frame
	_check("(setup) it armed while the ally stood on it", mine._armed)
	_check("an armed player mine ignores an ally on top of it",
		is_instance_valid(mine) and not mine._exploded,
		"it went off under its own side")
	if is_instance_valid(ally):
		ally.queue_free()
	await physics_frame

	# ── AN ENEMY STANDS ON IT ────────────────────
	if not is_instance_valid(mine) or mine._exploded:
		_check("(setup) the mine survived to meet an enemy", false)
		return
	var enemy: Node = _spawn_body(spot + Vector3(0.3, 1.0, 0.0), Enums.Factions.ENEMY)
	var before: int = enemy.health
	var went_off := false
	for _i in 120:
		await physics_frame
		if not is_instance_valid(mine) or mine._exploded:
			went_off = true
			break
	_check("...and the same mine goes off under an enemy", went_off)
	for _i in 20:
		await physics_frame
	_check("...and the enemy lost health for it",
		not is_instance_valid(enemy) or enemy.health < before,
		"%d -> %s" % [before, str(enemy.health) if is_instance_valid(enemy) else "dead"])
	if is_instance_valid(enemy):
		enemy.queue_free()
	await physics_frame


# ── AND THEY STOP MOVING ─────────────────────
# Scattered submines are thrown hard and bounce; area denial that is still
# rolling is not denying the ground you threw it at. This lays one with a hard
# sideways shove and checks it comes to rest and then stays exactly there.
func _test_settle() -> void:
	var spot: Vector3 = (_ground.call(320.0, 150.0) as Vector3) + Vector3.UP * 1.2
	var mine: Node = load("res://Character/weapon/mines/mine_cluster_submine.tscn").instantiate()
	mine.setup(_player)
	_level.add_child(mine)
	(mine as Node3D).global_position = spot
	(mine as RigidBody3D).linear_velocity = Vector3(6.0, 1.5, 3.0)
	for _i in 4:
		await physics_frame
	_check("(setup) a scattered submine starts moving",
		(mine as RigidBody3D).linear_velocity.length() > 1.0)

	var settled := false
	for _i in 420:
		await physics_frame
		if mine._settled:
			settled = true
			break
	_check("a submine settles instead of rolling forever", settled,
		"still loose after 7s at %.2f m/s" % (mine as RigidBody3D).linear_velocity.length())
	if not settled:
		return
	_check("...and it froze on the ground, not in the air", mine._bounce_count > 0)
	var where: Vector3 = (mine as Node3D).global_position
	for _i in 120:
		await physics_frame
	_check("...and it stays exactly where it stopped",
		(mine as Node3D).global_position.distance_to(where) < 0.01,
		"drifted %.3fm" % (mine as Node3D).global_position.distance_to(where))
	if is_instance_valid(mine):
		mine.queue_free()
	await physics_frame


# ── AND THEY DIE WITH THE MISSION ────────────
# Thrown kit used to be parented to `player.world`, which is the persistent
# node that LEVELS ARE LOADED INTO — the player is a sibling of the level, not
# a child of it. Anything spawned there outlives the mission: a Drone Carrier
# Pack thrown in the depot left two Divers flying after the next level loaded.
# World.current_level is what gets freed, so that is what ordnance must hang on.
func _test_parenting() -> void:
	var loadout = _player.get("loadout")
	var world = _player.get("world")
	_check("(setup) the player is a SIBLING of the level, not inside it",
		world != null and _player.get_parent() == world,
		"the whole bug rests on this")
	if world == null:
		return
	var lvl = world.get("current_level")
	_check("(setup) the world knows which level is loaded", lvl != null)
	if lvl == null or loadout == null:
		return
	# Ask any held item where it would put something. level_node() is the one
	# answer every thrown, fired and launched thing now uses.
	# Items are parented to the camera, not the loadout node, so this walks
	# the player rather than assuming where the loadout keeps them.
	var item = _first_with_level_node(_player)
	_check("(setup) found a held item to ask", item != null)
	if item == null:
		return
	_check("thrown kit is parented to the level, not the world",
		item.level_node() == lvl,
		"got %s, wanted %s" % [str(item.level_node()), str(lvl)])


func _first_with_level_node(n: Node) -> Node:
	if n.has_method("level_node"):
		return n
	for c in n.get_children():
		var f := _first_with_level_node(c)
		if f != null:
			return f
	return null
