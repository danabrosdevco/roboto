extends SceneTree

# ─────────────────────────────────────────────
# RECLAIMER — the tracked repair and salvage frame drives like something on
# tracks, reaches its squadmates with the arm, grinds enemy wrecks down for
# resources, drops everything for a squadmate, and backs off from an enemy
# that gets close.
#
# Two rifles and a Reclaimer in the open valley. Robots are knocked down by
# hand and wrecks laid in front of it; these read back what it chose to do and
# how long it took. Where it ends up standing is only read where that IS the
# decision (a turn on the spot, the drum on a wreck).
#
# Boots the real world with autosave off: it reads the save on this machine and
# never writes it.
# ─────────────────────────────────────────────

const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const RECLAIMER := "res://Character/characters/ai/vehicle_reclaimer.tscn"

var _fails := 0
var _mgr: AIManager
var _level: Node
var _recl: Soldier
var _fought := false   # the Reclaimer was ever in COMBAT
# What the waits below measure as they go. A Dictionary, because a lambda gets
# a copy of a local variable: anything it counted into one was lost.
var _seen := {}


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


func _spawn(path: String, at: Vector3, faction: int) -> Soldier:
	var s: Soldier = load(path).instantiate()
	s.faction = faction
	s.always_active = true
	_level.add_child(s)
	s.global_position = at
	_mgr.register_enemy(s)
	return s


# A hostile that stands where it is put and cannot hurt anyone: a live enemy
# for the Reclaimer to react to, without a firefight in the test.
func _harmless(s: Soldier) -> void:
	if s.weapon != null:
		s.weapon.hide()
	s.weapon = null
	s.equipment_slots = [] as Array[AIEquipmentSlot]
	s.max_health = 4000
	s.health = 4000
	s.max_hold_time = 0.0
	s.hold_still()


func _tick() -> void:
	await physics_frame
	if _recl.ai_state == Enemy.AIState.COMBAT:
		_fought = true


# Game seconds until `done` holds, or -1 after `limit`.
func _until(done: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		await _tick()
		t += 1.0 / 60.0
		if done.call():
			return t
	return -1.0


func _wait(seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await _tick()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _init() -> void:
	await process_frame
	var cat: ItemCatalogue = load(CATALOGUE)

	# ── THE FRAME ────────────────────────────────
	var frame := cat.chassis_def(&"reclaimer")
	_check("the Reclaimer is in the catalogue: two seats, no gun slot, a welder built in",
		frame != null and frame.purchasable and frame.supply == 2 and frame.weapon_slots == 0
		and frame.built_in == "WELDER" and frame.scene != null)
	_check("...and it is not a vehicle to the squad: it rides with the infantry",
		frame != null and not frame.vehicle)

	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	var unlocked_by := cm.missions.filter(func(m): return m != null and m.unlocks.has(&"reclaimer"))
	_check("...unlocked by Valley Assault", unlocked_by.size() == 1 and unlocked_by[0].id == &"valley_4_assault")

	var player: Node3D = _find(root, "Player")
	_level = player.get_parent()
	_mgr = _find(root, "AIManager")
	var valley = load("res://maps/valley_level.tscn").instantiate()
	_level.add_child(valley)
	for _i in 20:
		await physics_frame
	var space := player.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)
	var nav_map: RID = player.get_world_3d().navigation_map
	var on_nav := func(x: float, z: float) -> Vector3:
		return NavigationServer3D.map_get_closest_point(nav_map, ground_at.call(x, z))
	player.global_position = ground_at.call(290.0, 160.0) + Vector3.UP

	# ── THE SQUAD ────────────────────────────────
	var ada := _spawn(RIFLE, on_nav.call(300.0, 62.0) + Vector3.UP, Enums.Factions.ALLIED)
	var bo := _spawn(RIFLE, on_nav.call(304.0, 62.0) + Vector3.UP, Enums.Factions.ALLIED)
	_recl = _spawn(RECLAIMER, on_nav.call(302.0, 70.0) + Vector3.UP * 0.42, Enums.Factions.ALLIED)
	var squad: Squad = load("res://Managers/AI/squad.tscn").instantiate()
	squad.callsign = "SALVAGE"
	squad.squad_members = [ada, bo, _recl] as Array[Soldier]
	_level.add_child(squad)
	await _wait(1.0)
	_check("(setup) a Reclaimer stands up with the squad, out of combat, with no gun",
		_recl.alive and _recl.weapon == null and _recl.ai_state != Enemy.AIState.COMBAT and _recl.squad == squad)

	# ── TRACKS ───────────────────────────────────
	# Sent somewhere behind it, it turns on the spot before it drives: a
	# tracked hull does not swing round in a loop the way the rover does.
	var start: Vector3 = _recl.global_position
	var yaw0: float = _recl.rotation.y
	var behind: Vector3 = on_nav.call(start.x + _recl.global_transform.basis.z.x * 9.0,
		start.z + _recl.global_transform.basis.z.z * 9.0)
	_recl.move_to(behind)
	await _wait(0.6)
	var turned := absf(angle_difference(yaw0, _recl.rotation.y))
	_check("sent somewhere behind it, it turns on the spot first", rad_to_deg(turned) > 40.0
		and _flat(start, _recl.global_position) < 0.35,
		"turned %.0f deg, moved %.2fm" % [rad_to_deg(turned), _flat(start, _recl.global_position)])
	_seen["slip"] = 0.0
	_seen["drove"] = 0.0
	var arrived := await _until(func():
		var fwd: Vector3 = _recl._hull_forward()
		var v := Vector3(_recl.velocity.x, 0.0, _recl.velocity.z)
		_seen["slip"] = maxf(_seen["slip"], absf(v.dot(fwd.cross(Vector3.UP))))
		_seen["drove"] = maxf(_seen["drove"], v.length())
		return _recl.movement_state == Enemy.MovementState.NONE, 10.0)
	_check("...then drives there and stops", arrived > 0.0 and _flat(_recl.global_position, behind) <= _recl.arrival_radius + 0.3,
		"after %.1fs, %.2fm off" % [arrived, _flat(_recl.global_position, behind)])
	_check("...and never slides sideways on the way", _seen["drove"] > 2.0 and _seen["slip"] < 0.05,
		"%.3f m/s sideways at up to %.1f m/s" % [_seen["slip"], _seen["drove"]])

	# ── THE ARM ──────────────────────────────────
	var stow_el := deg_to_rad(_recl.stow_elbow_degrees)
	ada.apply_damage(99999, null)
	await _tick()
	_check("(setup) a rifle knocked down", ada.downed)
	_seen["tip"] = INF
	_seen["el"] = 0.0
	var hp0 := ada.health
	var up_in := await _until(func():
		if _seen["tip"] == INF and ada.health > hp0:
			_seen["tip"] = _recl.weld_tip.global_position.distance_to(_recl._weld_point(ada))
			_seen["el"] = _recl._el
		return not ada.downed, 25.0)
	print("      stood back up after %.1fs" % up_in)
	_check("it drives over and welds a downed squadmate back up", up_in > 0.0 and ada.alive and _recl.revives == 1,
		"up after %.1f, revives %d" % [up_in, _recl.revives])
	_check("...with the arm: nothing is welded until the torch is on it", _seen["tip"] <= 0.5,
		"torch %.2fm off when welding began" % _seen["tip"])
	_check("...the boom unfolded out of its stowed fold to get there", _seen["el"] < 0.0 and stow_el > 0.0,
		"elbow %.0f deg" % rad_to_deg(_seen["el"]))
	ada.health = ada.max_health
	await _until(func(): return _recl._patient == null, 6.0)
	await _wait(2.5)
	_check("with nobody to fix, the arm folds back up", absf(_recl._el - stow_el) < 0.05
		and absf(_recl._sh - deg_to_rad(_recl.stow_shoulder_degrees)) < 0.05 and absf(_recl._yaw) < 0.05,
		"sh %.0f el %.0f yaw %.0f" % [rad_to_deg(_recl._sh), rad_to_deg(_recl._el), rad_to_deg(_recl._yaw)])

	# ── A WRECK ──────────────────────────────────
	var ahead := func(metres: float, side: float) -> Vector3:
		var fwd: Vector3 = _recl._hull_forward()
		var p: Vector3 = _recl.global_position + fwd * metres + fwd.cross(Vector3.UP) * side
		return on_nav.call(p.x, p.z) + Vector3.UP
	var wreck := _spawn(RIFLE, ahead.call(9.0, 2.0), Enums.Factions.ENEMY)
	wreck.apply_damage(99999, null)
	var to_grind := await _until(func(): return _recl._grinding, 12.0)
	_check("with nobody to fix, it drives its drum onto an enemy wreck", to_grind > 0.0
		and _recl._front_gap(wreck) <= _recl.grind_reach and _recl.movement_state == Enemy.MovementState.NONE,
		"after %.1fs, gap %.2f" % [to_grind, _recl._front_gap(wreck)])
	var need: float = _recl._grind_need
	var ground_in := await _until(func(): return not wreck.downed, 15.0)
	print("      ground down in %.1fs (channel %.1fs)" % [ground_in, need])
	_check("...and grinds it for five to ten seconds", need >= 5.0 and need <= 10.0
		and ground_in >= need - 0.1 and ground_in <= need + 0.5, "%.1fs for a %.1fs channel" % [ground_in, need])
	_check("...until it is gone", not wreck.downed and not wreck.alive and not wreck.visible_pieces[0].visible)
	_check("...for what the wreck was worth", _recl.salvaged == wreck.bits and _recl.wrecks_ground == 1,
		"%d for a wreck worth %d" % [_recl.salvaged, wreck.bits])
	_check("...paid to nobody outside a mission", cm.salvage_this_mission == 0, str(cm.salvage_this_mission))

	# ── A SQUADMATE FIRST ────────────────────────
	# On a mission this time, so the salvage is counted.
	cm.in_mission = true
	var wreck2 := _spawn(RIFLE, ahead.call(9.0, -2.0), Enums.Factions.ENEMY)
	wreck2.apply_damage(99999, null)
	var to_grind2 := await _until(func(): return _recl._grinding, 12.0)
	_check("(setup) on to the next wreck", to_grind2 > 0.0, "not grinding after 12s")
	_seen["ground"] = 0.0
	var need2: float = _recl._grind_need
	for _i in 120:
		await _tick()
		if _recl._grinding and _recl._wreck == wreck2:
			_seen["ground"] += 1.0 / 60.0
	bo.apply_damage(99999, null)
	_check("a downed squadmate is never a wreck to grind", not _recl._salvageable(bo))
	var dropped := await _until(func(): return not _recl._grinding and _recl._patient == bo, 1.0)
	_check("a squadmate going down stops the grinding at once", dropped >= 0.0, "still grinding after 1s")
	_check("...and the wreck keeps what was ground", float(_recl._progress.get(wreck2.get_instance_id(), 0.0)) >= 1.5,
		str(_recl._progress))
	var back := await _until(func():
		if _recl._grinding and _recl._wreck == wreck2:
			_seen["ground"] += 1.0 / 60.0
		if not bo.downed and bo.health < bo.max_health:
			bo.health = bo.max_health   # stood up: topped up, so the wreck is next
		return not wreck2.downed, 40.0)
	print("      squadmate up and the wreck finished after %.1fs more; %.1fs ground of %.1fs" % [back, _seen["ground"], need2])
	_check("...back to it afterwards, finishing it from where it left off", back > 0.0 and not wreck2.downed
		and absf(_seen["ground"] - need2) < 0.5, "%.1fs ground for a %.1fs channel" % [_seen["ground"], need2])
	_check("on a mission, the campaign holds the salvage for extraction", cm.salvage_this_mission == wreck2.bits,
		"%d for a wreck worth %d" % [cm.salvage_this_mission, wreck2.bits])
	cm.in_mission = false
	cm.salvage_this_mission = 0

	# ── AN ENEMY CLOSE ───────────────────────────
	var wreck3 := _spawn(RIFLE, ahead.call(9.0, 0.0), Enums.Factions.ENEMY)
	wreck3.apply_damage(99999, null)
	var to_grind3 := await _until(func(): return _recl._grinding, 12.0)
	_check("(setup) on to a third wreck", to_grind3 > 0.0, "not grinding after 12s")
	# Far off first: 30 metres away, a live enemy is the squad's business.
	var far_at: Vector3 = _recl.global_position - _recl._hull_forward() * 30.0
	var far := _spawn(RIFLE, on_nav.call(far_at.x, far_at.z) + Vector3.UP, Enums.Factions.ENEMY)
	_harmless(far)
	await _wait(1.0)
	_check("an enemy thirty metres off does not stop the grinding", _recl._grinding and _recl._wreck == wreck3)
	var near_at: Vector3 = _recl.global_position - _recl._hull_forward() * 6.0
	var near := _spawn(RIFLE, on_nav.call(near_at.x, near_at.z) + Vector3.UP, Enums.Factions.ENEMY)
	_harmless(near)
	var near_from := _flat(_recl.global_position, near.global_position)
	var off_it := await _until(func(): return not _recl._grinding and _recl._wreck == null, 1.0)
	_check("one six metres off: it drops the wreck", off_it >= 0.0)
	var backing := await _until(func():
		var g: Vector3 = _recl._walk_goal
		return g != Vector3.INF and _flat(g, near.global_position) > near_from + 3.0, 2.0)
	_check("...and backs off away from it", backing >= 0.0 and _recl._keeping_back())
	_check("...keeping the progress on the wreck", float(_recl._progress.get(wreck3.get_instance_id(), 0.0)) > 0.0)
	near.apply_damage(99999, null)
	far.apply_damage(99999, null)

	# ── THE DRUM BITES ───────────────────────────
	# Parked first: still backing off from the last one, it would have turned
	# away from anything put in front of it before its first bite.
	await _until(func(): return _recl.movement_state == Enemy.MovementState.NONE and _recl._live_threat() == null, 10.0)
	await _wait(0.5)
	var bite_at: Vector3 = _recl.global_position + _recl._hull_forward() * (_recl.drum_reach + 0.5)
	var biter := _spawn(RIFLE, on_nav.call(bite_at.x, bite_at.z) + Vector3.UP, Enums.Factions.ENEMY)
	_harmless(biter)
	var turn0: float = _recl._drum_turn
	var whole: int = biter.health
	# WHAT IT COSTS THE ENEMY, not which flag was set on the frame we looked.
	# _biting is true only while the drum is actually in contact, and the
	# reclaimer scans and rolls on timers, so sampling that flag caught it
	# about two runs in three — passing alone and failing in the suite with no
	# code change, which is a flaky test rather than a flaky drum. Losing
	# health to the thing in front of it is the behaviour either way.
	var bit := await _until(func(): return biter.health < whole, 6.0)
	_check("an enemy right in front of the drum gets chewed",
		bit >= 0.0 and _recl._drum_turn != turn0,
		"%d -> %d hp after %.1fs" % [whole, biter.health, bit])
	biter.apply_damage(99999, null)
	_check("through all of it, the Reclaimer never joined a fight", not _fought)

	# ── KNOCKED OUT ──────────────────────────────
	# The wrecks left about taken away first: brought back with them there, it
	# goes straight back to grinding with its beacon flashing, which is right
	# but not what this looks at.
	for w in [wreck3, near, far, biter]:
		if w.downed:
			w.destroy()
	await _until(func(): return _recl._wreck == null and not _recl._grinding, 3.0)
	await _wait(1.0)
	var rig_y: float = _recl.rig.position.y
	_recl.apply_damage(99999, null)
	await _wait(0.5)
	_check("knocked out, it settles on its tracks with the beacon out", _recl.downed
		and _recl.rig.position.y < rig_y - 0.03 and not _recl.beacon.visible)
	# revive() stands it up at half health, which is under patch_below: with
	# nobody else to see to, it welds its own plating. Last in the queue, but
	# it is the one robot in the squad that can.
	_recl.apply_healing(int(_recl.max_health * 0.51), null)
	var hp_then: int = _recl.health
	var self_fix := await _until(func(): return _recl._patient == _recl and _recl.health > hp_then, 8.0)
	_check("brought back hurt with nobody else to fix, it welds itself", self_fix > 0.0,
		"patient %s, %d/%d hp" % [_recl._patient.name if _recl._patient != null else "none",
		_recl.health, _recl.max_health])
	_recl.health = _recl.max_health
	await _until(func(): return _recl._patient == null, 4.0)
	await _wait(2.0)
	_check("...and once it is whole, the arm folds up again", _recl.alive
		and absf(_recl._el - stow_el) < 0.05 and _recl.beacon.visible,
		"el %.0f, welding %s, patient %s" % [rad_to_deg(_recl._el), _recl._welding,
		_recl._patient.name if _recl._patient != null else "none"])

	# Left standing for the engine to clear on the way out, as test_mechanic
	# does: freeing them here had the process crash on exit under test.sh's pipe.
	await create_timer(1.5).timeout
	for _i in 5:
		await physics_frame
	print("")
	print("ALL RECLAIMER CHECKS PASS" if _fails == 0 else "%d RECLAIMER CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
