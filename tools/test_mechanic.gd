extends SceneTree

# ─────────────────────────────────────────────
# MECHANIC — the repair frame goes to whoever needs it, in the right order,
# welds them back, and stays out of the fight.
#
# A squad of two rifles, a rover and a Mechanic in the open valley. Robots are
# knocked down or shot up by hand, and the Mechanic is left to get on with it:
# these read back who it went to first, whether they got up, and where it stood
# while there was shooting. Nothing here is tuning.
#
# Boots the real world with autosave off: it reads the save on this machine and
# never writes it.
# ─────────────────────────────────────────────

const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const ROVER := "res://Character/characters/ai/vehicle_rover.tscn"
const MECHANIC := "res://Character/characters/ai/mechanic_chassis.tscn"

var _fails := 0
var _mgr: AIManager
var _level: Node


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


func _frac(e: Enemy) -> float:
	return float(e.health) / float(maxi(1, e.max_health))


# Game seconds until `done` holds, or -1 after `limit`. Records every patient
# the Mechanic takes on along the way, in order.
func _until(done: Callable, limit: float, mech: Soldier, seen: Array) -> float:
	var t := 0.0
	while t < limit:
		await physics_frame
		t += 1.0 / 60.0
		var p = mech._patient
		if p != null and (seen.is_empty() or seen[-1] != p):
			seen.append(p)
		if done.call():
			return t
	return -1.0


func _init() -> void:
	await process_frame
	var cat: ItemCatalogue = load(CATALOGUE)

	# ── THE FRAME ────────────────────────────────
	var frame := cat.chassis_def(&"mechanic")
	_check("the Mechanic is in the catalogue: one seat, no gun slot, a welder built in",
		frame != null and frame.purchasable and frame.supply == 1 and frame.weapon_slots == 0
		and frame.built_in == "WELDER" and not frame.vehicle)

	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	var unlocked_by := cm.missions.filter(func(m): return m != null and m.unlocks.has(&"mechanic"))
	# Unlocked by the last arena op, on its own: it arrives before the valley
	# does, so the first mission with a real squad can already take a medic.
	_check("...unlocked by clearing the arena, one operation before the valley",
		unlocked_by.size() == 1 and unlocked_by[0].id == &"arena_4_pack_hunt",
		str(unlocked_by.map(func(m): return str(m.id))))

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
	var rover := _spawn(ROVER, on_nav.call(310.0, 66.0) + Vector3.UP * 0.9, Enums.Factions.ALLIED)
	rover.equip_weapon_scene(cat.item(&"machine_gun").ai_scene)
	var mech := _spawn(MECHANIC, on_nav.call(302.0, 70.0) + Vector3.UP, Enums.Factions.ALLIED)
	var squad: Squad = load("res://Managers/AI/squad.tscn").instantiate()
	squad.callsign = "FIXERS"
	squad.squad_members = [ada, bo, rover, mech] as Array[Soldier]
	_level.add_child(squad)
	for _i in 60:
		await physics_frame
	_check("(setup) a Mechanic stands up with the squad, out of combat, with no gun",
		mech.alive and mech.weapon == null and mech.ai_state != Enemy.AIState.COMBAT and mech.squad == squad)

	# ── A DOWNED SQUADMATE ───────────────────────
	var seen: Array = []
	ada.apply_damage(99999, null)
	await physics_frame
	_check("(setup) a rifle knocked down", ada.downed)
	var up_in := await _until(func(): return not ada.downed, 25.0, mech, seen)
	print("      stood back up after %.1fs; the Mechanic went to %s" % [up_in, seen.map(func(p): return p.name)])
	_check("the Mechanic walks over and welds a downed squadmate back up", up_in > 0.0 and ada.alive
		and mech.revives == 1, "up after %.1f, revives %d" % [up_in, mech.revives])
	_check("...standing over it to do it", mech.global_position.distance_to(ada.global_position) < 3.2,
		"%.1fm away" % mech.global_position.distance_to(ada.global_position))
	_check("...and the log credits it", mech.repaired > 0)
	# And it survives the mission: the body is thrown away at extraction, so a
	# revive only counts for anything once the record has taken it.
	var sheet := SoldierRecord.new()
	sheet.max_health = mech.max_health
	sheet.read_from(mech)
	_check("...and it goes home on the record as a career revive",
		sheet.revives == 1 and mech.revives == 0,
		"record %d, body %d" % [sheet.revives, mech.revives])

	# ── DOWN BEFORE DAMAGED ──────────────────────
	# Topped up first, so only these two need anything.
	ada.health = ada.max_health
	for _i in 30:
		await physics_frame
	seen.clear()
	rover.apply_damage(int(rover.max_health * 0.5), null)
	bo.apply_damage(99999, null)
	var both := await _until(func(): return not bo.downed and _frac(rover) >= mech.patch_to, 40.0, mech, seen)
	print("      order of work: %s, done after %.1fs" % [seen.map(func(p): return p.name), both])
	_check("a squadmate down comes before a vehicle that is only damaged", seen.size() >= 2
		and seen[0] == bo and seen.has(rover), str(seen.map(func(p): return p.name)))
	_check("...then the rover is welded back to nearly full", both > 0.0 and _frac(rover) >= mech.patch_to,
		"rover at %.2f" % _frac(rover))

	# ── VEHICLES BEFORE INFANTRY ─────────────────
	# Bo stood up at half health and is next in line: topped up, so the two
	# below are all there is.
	for _i in 30:
		await physics_frame
	bo.health = bo.max_health
	await _until(func(): return mech._patient == null, 5.0, mech, [])
	seen.clear()
	ada.apply_damage(int(ada.max_health * 0.55), null)
	rover.apply_damage(int(rover.max_health * 0.35), null)
	await _until(func(): return _frac(ada) >= mech.patch_to and _frac(rover) >= mech.patch_to, 40.0, mech, seen)
	_check("of two only damaged, the vehicle is first", seen.size() >= 1 and seen[0] == rover,
		str(seen.map(func(p): return p.name)))
	_check("...and both end up patched", _frac(ada) >= mech.patch_to and _frac(rover) >= mech.patch_to,
		"%.2f / %.2f" % [_frac(ada), _frac(rover)])
	for _i in 20:
		await physics_frame
	_check("with nothing left to fix it stops welding", mech._patient == null and not mech._welding
		and (mech.weld_loop == null or not mech.weld_loop.playing))

	# ── TRAILING ─────────────────────────────────
	# Sent somewhere as a squad, it is sent to the back of the line, not into
	# it: in the lab, walking in level with the rifles got it shot first. Read
	# off where each is SENT — once there, robots on an advance with nothing to
	# fight drift about on their own, which says nothing about the formation.
	var out_there: Vector3 = on_nav.call(305.0, 38.0)
	squad.set_objective(Squad.SquadObjective.ADVANCE, out_there, true)
	await physics_frame
	var way := out_there - Vector3(305.0, out_there.y, 66.0)
	way.y = 0.0
	way = way.normalized()
	var mech_to := (mech.movement_target - out_there).dot(way)
	var rifles_to := ((ada.movement_target - out_there).dot(way) + (bo.movement_target - out_there).dot(way)) / 2.0
	print("      sent out: the rifles to %.1fm of the point, the Mechanic to %.1fm short of it" % [-rifles_to, -mech_to])
	_check("sent out with its squad, it is sent to the back of the line", mech_to < rifles_to - 4.0,
		"%.1f vs %.1f" % [mech_to, rifles_to])
	for _i in 60 * 3:
		await physics_frame
	squad.set_objective(Squad.SquadObjective.NONE, squad.get_center(), true)

	# Following, it settles in its place at the back and stops there. Trailing
	# used to be a nudge on each move order, which the follow formation's
	# every-frame slot check took for a robot out of place: re-ordered, every
	# frame, for as long as the squad followed.
	var far_away := player.global_position
	player.global_position = on_nav.call(305.0, 20.0) + Vector3.UP
	squad.follow(player)
	for _i in 60 * 8:
		await physics_frame
	var settled := 0
	for _i in 60:
		await physics_frame
		if mech.movement_state == Enemy.MovementState.NONE:
			settled += 1
	_check("following, it settles at the back of the formation instead of re-pathing",
		settled > 50, "idle %d of 60 frames, mv %d" % [settled, mech.movement_state])
	squad.set_objective(Squad.SquadObjective.NONE, squad.get_center(), true)
	player.global_position = far_away
	for _i in 30:
		await physics_frame

	# ── NOT SINGLED OUT ──────────────────────────
	# Placed off the squad, wherever the checks above have walked it.
	var here := squad.get_center()
	var foe := _spawn(RIFLE, on_nav.call(here.x, here.z + 38.0) + Vector3.UP, Enums.Factions.ENEMY)
	foe.max_health = 4000
	foe.health = 4000
	# A rifle at 12m and the Mechanic at 13m. Placed by hand for one query each,
	# then put back.
	var keep := [ada.global_position, mech.global_position]
	var fp := foe.global_position
	ada.global_position = fp + Vector3(12.0, 0.0, 0.0)
	mech.global_position = fp + Vector3(-13.0, 0.0, 0.0)
	var plain_pick = _mgr.get_nearest_hostile(foe)
	mech.target_priority = 1.15
	var weighted_pick = _mgr.get_nearest_hostile(foe)
	mech.target_priority = 1.0
	ada.global_position = keep[0]
	mech.global_position = keep[1]
	_check("the enemy does not single the Mechanic out: it shoots the nearer rifle", plain_pick == ada,
		str(plain_pick.name if plain_pick != null else null))
	_check("...though target_priority, turned up, would make it the pick", weighted_pick == mech,
		str(weighted_pick.name if weighted_pick != null else null))

	# ── A FIGHT ──────────────────────────────────
	# The hostile walks in shooting. The squad fights; the Mechanic does not,
	# and keeps behind its squad from whatever it is fighting.
	foe.move_to(on_nav.call(here.x + 2.0, here.z + 18.0))
	var in_combat := false
	var behind := 0
	var samples := 0
	var rallied := false
	var t := 0.0
	while t < 10.0:
		await physics_frame
		t += 1.0 / 60.0
		if mech.ai_state == Enemy.AIState.COMBAT:
			in_combat = true
		# Kept topped up, so it has nobody to fix and where it stands is its own
		# choice. With the enemy no longer aiming for it, it spent real fights
		# welding, and a check of where it waited never got a look in.
		for s in [ada, bo, rover, mech]:
			if s.alive:
				s.health = s.max_health
		if squad.context == Squad.SquadContext.ENGAGED:
			rallied = true
		# Only while it is free and standing: welding someone is where it should
		# be. What is read is where it has CHOSEN to stand. Where it is standing
		# lags that by however far the rifles bounded since, and in a fight they
		# bound a lot; the choice is the behaviour under test.
		if rallied and t > 4.0 and foe.alive and mech.alive and mech._patient == null:
			samples += 1
			var fnow := foe.global_position
			var line := squad.line_center()
			var goal: Vector3 = mech._walk_goal
			if mech._keeping_back() and goal != Vector3.INF \
					and Vector2(goal.x - fnow.x, goal.z - fnow.z).length() > Vector2(line.x - fnow.x, line.z - fnow.z).length() + 4.0:
				behind += 1
	print("      in the fight: set on a spot behind its squad in %d of %d looks" % [behind, samples])
	_check("the squad rallies on contact", rallied)
	_check("...the Mechanic never joins the fight", not in_combat)
	_check("...and keeps behind its squad while it goes on", samples > 0 and behind > samples * 0.8,
		"%d of %d" % [behind, samples])

	# Left standing for the engine to clear on the way out, as test_vehicle does:
	# freeing them here had the process crash on exit under test.sh's pipe
	# (a shutdown quirk, not the code under test). The wait lets the last
	# sounds and bark timers finish first.
	await create_timer(1.5).timeout
	for _i in 5:
		await physics_frame
	print("")
	print("ALL MECHANIC CHECKS PASS" if _fails == 0 else "%d MECHANIC CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
