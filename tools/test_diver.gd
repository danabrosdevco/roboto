extends SceneTree

# ─────────────────────────────────────────────
# THE DIVER ACTUALLY FLIES THE RUN IT IS DOCUMENTED TO FLY.
#
# diver.gd was written, left unwired, and sat untouched long enough that
# nothing in the project referenced it. Everything it claims in its header is
# therefore unproven — and the claims are the whole reason the frame exists, so
# they are what this pins.
#
#  1. THE WARNING BEAT. It climbs for climb_seconds and chooses nobody while it
#     does. That pause is the player's only chance to react, and it is the
#     first thing that would be lost to a well-meaning "why wait?" edit.
#
#  2. IT PICKS BY WORTH, NOT BY DISTANCE. Every other AI in this game takes the
#     nearest visible body. This one scores chassis cost first, so it must fly
#     PAST a free rifleman at 15m to reach a 320-cost Walker at 60m. If that
#     ever silently reverts to nearest-first, the frame becomes a worse
#     Hatchling and nothing in the game would say so.
#
#  3. IT COMMITS. Once diving it keeps the target it chose; re-shopping every
#     frame makes it wander between two bodies and hit neither.
#
#  4. IT GOES OFF ON CONTACT, and the thing it hit loses health.
#
#  5. OUT OF TIME IT DROPS, IT DOES NOT DETONATE. A charge that explodes on a
#     timer wherever it happens to be is a mine nobody placed.
#
# Boots the real world and the valley for ground and navigation, the same way
# test_quadcopter.gd does, with autosave off so the campaign save is untouched.
# ─────────────────────────────────────────────

const DIVER := "res://Character/characters/ai/diver.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"

var _fails := 0
var _level: Node = null
var _mgr: Node = null
var _ground: Callable


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
	_level = player.get_parent()
	_mgr = _find(root, "AIManager")
	_level.add_child(load("res://maps/appendix/valley_level.tscn").instantiate())
	for _i in 20:
		await physics_frame

	var space := player.get_world_3d().direct_space_state
	_ground = func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	player.global_position = (_ground.call(290.0, 210.0) as Vector3) + Vector3.UP
	for _i in 20:
		await physics_frame

	await _test_climb_then_choose()
	await _test_expiry()

	print("")
	print("DIVER FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL DIVER CHECKS PASS")
	quit(1 if _fails > 0 else 0)


func _spawn(path: String, at: Vector3, faction: int) -> Node:
	var body: Node = load(path).instantiate()
	body.faction = faction
	body.always_active = true
	_level.add_child(body)
	(body as Node3D).global_position = at
	if _mgr != null and _mgr.has_method("register_enemy"):
		_mgr.register_enemy(body)
	return body


# ── THE RUN ──────────────────────────────────
func _test_climb_then_choose() -> void:
	var origin: Vector3 = _ground.call(300.0, 150.0)
	# Free rifleman, close. 320-cost Walker, four times further away.
	var rifle := _spawn(RIFLE, (_ground.call(300.0, 135.0) as Vector3) + Vector3.UP, Enums.Factions.ENEMY)
	var walker := _spawn(WALKER, (_ground.call(300.0, 90.0) as Vector3) + Vector3.UP, Enums.Factions.ENEMY)
	for _i in 10:
		await physics_frame

	var diver: Node = _spawn(DIVER, origin + Vector3.UP * 1.5, Enums.Factions.PLAYER)
	for _i in 5:
		await physics_frame
	var launch_y: float = (diver as Node3D).global_position.y

	_check("(setup) a free rifleman at %.0fm and a %d-cost walker at %.0fm" % [
		origin.distance_to((rifle as Node3D).global_position),
		320, origin.distance_to((walker as Node3D).global_position)],
		rifle != null and walker != null)

	# Half a climb in: still climbing, still nobody chosen.
	var half := int((diver.climb_seconds * 0.5) * 60.0)
	for _i in half:
		await physics_frame
	_check("half way through the climb it is still climbing", diver.phase == 0,
		"phase %d, wanted CLIMB" % diver.phase)
	_check("...and has chosen nobody yet", diver._target == null)
	var mid_y: float = (diver as Node3D).global_position.y
	_check("...and it has gained height", mid_y > launch_y + 1.0,
		"%.1fm gained" % (mid_y - launch_y))

	# Let it choose.
	var chose: Node = null
	for _i in 420:
		await physics_frame
		if diver._target != null:
			chose = diver._target
			break
	_check("it picks a target once the climb is over", chose != null)
	_check("...and it is the WALKER, not the closer free rifleman", chose == walker,
		"chose %s" % (chose.name if chose != null else "nothing"))

	# Commitment: the target it dives is the target it keeps.
	var kept := true
	for _i in 60:
		await physics_frame
		if diver.phase == 3:
			break
		if diver._target != chose and diver._target != null:
			kept = false
			break
	_check("...and it keeps it while diving", kept)

	var before: int = walker.health
	for _i in 900:
		await physics_frame
		if diver.phase == 3:
			break
	_check("it reaches the walker and goes off", diver.phase == 3,
		"phase %d after 15s" % diver.phase)
	for _i in 20:
		await physics_frame
	_check("...and the walker lost health for it", walker.health < before,
		"%d -> %d" % [before, walker.health])

	for n in [rifle, walker, diver]:
		if is_instance_valid(n):
			n.queue_free()
	await physics_frame


# ── OUT OF TIME ──────────────────────────────
func _test_expiry() -> void:
	var origin: Vector3 = _ground.call(500.0, 500.0)
	var diver: Node = _spawn(DIVER, origin + Vector3.UP * 1.5, Enums.Factions.PLAYER)
	# Shortened from 30s so the suite does not spend half a minute proving a
	# timer. It is the mechanism being checked, not the tuned number.
	diver.lifetime = 2.0
	var ditched := false
	for _i in 240:
		await physics_frame
		# 4 is DITCH, 3 is SPENT. Either means the clock did its job; which one
		# it is caught in depends on how far it had to fall.
		if not is_instance_valid(diver) or diver.phase == 4 or diver.phase == 3:
			ditched = true
			break
	_check("with nothing in reach its time runs out", ditched, "still flying after 4s")

	# SAMPLED EVERY FRAME, not read at the end. An explosion clears itself up
	# within a second, so a child count taken after the dust settles finds the
	# level exactly as it was and reports that nothing ever happened.
	# BY IDENTITY, not by counting. The drone frees itself on the same frame the
	# blast is added, so the level's child COUNT is unchanged either way — one node
	# out, one node in — and a count test reports that nothing happened at all.
	var known: Dictionary = {}
	for c in _level.get_children():
		known[c] = true
	var saw_blast := false
	for _i in 300:
		await physics_frame
		for c in _level.get_children():
			if not known.has(c) and c != diver:
				saw_blast = true
	# IT LEAVES NOTHING. Enemy.destroy() only hides the body, and the rotor loop
	# is an autoplaying AudioStreamPlayer3D on it — a spent Diver used to buzz
	# from where it died for the rest of the mission.
	_check("...and the drone is gone, not just hidden", not is_instance_valid(diver))
	# IT GOES OFF ON THE DIRT, rather than evaporating in mid-air. It used to
	# simply drop, on the reasoning that a charge detonating on a timer wherever
	# it happens to be is a mine nobody placed — which is true, and is why it
	# flies DOWN first. What it must not do is disappear: a drone the player
	# paid for has to be accounted for, seen and heard.
	_check("...and it went off on the ground rather than being dropped", saw_blast)

	# ── SHOT DOWN LEAVES NOTHING EITHER ──────────
	# Every other way a Diver ends goes through Enemy.destroy(), which hides the
	# body and disables the colliders and then LEAVES THE NODE in the level for
	# the rest of the mission. Invisible, inert and permanent, one per drone.
	var second: Node = _spawn(DIVER, origin + Vector3.UP * 1.5, Enums.Factions.PLAYER)
	for _i in 4:
		await physics_frame
	second.destroy()
	for _i in 5:
		await physics_frame
	_check("a Diver that is destroyed rather than detonating also leaves nothing",
		not is_instance_valid(second))
