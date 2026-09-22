extends SceneTree

# ─────────────────────────────────────────────
# MORTAR — the Reclaimer's boom takes a 60mm tube in place of the welder, and
# shells what its SQUAD can see without ever seeing it itself.
#
# A squad of two on the open valley floor, deployed through the real spawner
# from records, the way a mission does it: a Reclaimer carrying the mortar and
# a rifle to spot for it. One enemy 55m from the Reclaimer, behind a wall from
# where it stands, and in plain view of the rifle. These read back what fits
# where, whether it fires over the wall off the rifle's sighting, whether the
# rounds come down on the target, that it holds fire with a friendly
# danger-close and picks up again once they move off, that it no longer welds,
# and that it still grinds wrecks.
#
# Bodies are pinned where the checks need them: this is about what the tube
# decides, not where anyone walks.
#
# Boots the real world with autosave off: it reads the save on this machine and
# never writes it.
# ─────────────────────────────────────────────

const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const SITE := Vector3(290, -11, 220)   # open, flat valley floor
const HUGE := 9000000

var _fails := 0
var _rec: Soldier       # the Reclaimer
var _spotter: Soldier
var _enemy: Soldier
var _rec_at: Vector3
var _spot_at: Vector3
var _enemy_at: Vector3


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


# A HAIR ABOVE the surface, where move_and_slide rests a body. Pinned exactly on
# it, the sight ray (aimed at the target's origin, its feet) ends in the ground
# and nobody sees anybody.
func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at - Vector3.UP * 80.0)
	var hit := space.intersect_ray(q)
	return (hit.position if hit else at) + Vector3.UP * 0.05


# Holds everyone where the checks put them for `frames`, the rifle kept on the
# target, and counts the rounds that leave the tube.
func _hold(frames: int) -> int:
	var fired := 0
	var last: int = _rec.weapon._last_fired_ms
	for f in frames:
		_rec.global_position = _rec_at
		_spotter.global_position = _spot_at
		_enemy.global_position = _enemy_at
		if f % 60 == 0 and _enemy.alive:
			_spotter.trigger_combat(_enemy)
		await physics_frame
		if _rec.weapon._last_fired_ms != last:
			last = _rec.weapon._last_fired_ms
			fired += 1
	return fired


func _init() -> void:
	await process_frame
	var cat: ItemCatalogue = load(CATALOGUE)

	# ── WHAT FITS WHERE ──────────────────────────
	var frame := cat.chassis_def(&"reclaimer")
	var mortar := cat.item(&"mortar")
	_check("the Reclaimer has one slot, and its welder stands in when it is empty",
		frame != null and frame.weapon_slots == 1 and frame.weapon_replaces_built_in and frame.built_in == "WELDER")
	_check("the mortar is in the catalogue, for the squad and not for you",
		mortar != null and mortar.kind == ItemDefinition.Kind.WEAPON and mortar.fits_ai() and not mortar.fits_player())
	_check("the mortar goes on the Reclaimer", frame != null and frame.takes(mortar))
	_check("...and on nothing else",
		not cat.chassis_def(&"soldier").takes(mortar) and not cat.chassis_def(&"rover").takes(mortar)
		and not cat.chassis_def(&"mechanic").takes(mortar))
	_check("...and nothing else goes on the Reclaimer: not a rifle, not the Rover's guns",
		not frame.takes(cat.item(&"m4")) and not frame.takes(cat.item(&"shotgun"))
		and not frame.takes(cat.item(&"machine_gun")) and not frame.takes(cat.item(&"grenade_launcher")))

	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	var unlocked_by := cm.missions.filter(func(m): return m != null and m.unlocks.has(&"mortar"))
	_check("unlocked with the Reclaimer, by Valley Assault",
		unlocked_by.size() == 1 and unlocked_by[0].id == &"valley_4_assault" and unlocked_by[0].unlocks.has(&"reclaimer"))

	# A Reclaimer saved before its boom had a slot has nothing to fit the tube
	# into until loading grows it one.
	var old := SoldierRecord.new()
	old.chassis_id = &"reclaimer"
	old.weapon_ids = [] as Array[StringName]
	cm._grow_weapon_slots(old)
	_check("a Reclaimer from an older save gets its slot on load, empty",
		old.weapon_ids.size() == 1 and old.weapon_ids[0] == &"", str(old.weapon_ids))

	# ── THE SQUAD ────────────────────────────────
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var ai: AIManager = _find(root, "AIManager")
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 60:
		await physics_frame
	var space := player.get_world_3d().direct_space_state
	# The base's own squad out, so nobody else is spotting or in the way.
	for squad in cm.spawner.squads:
		for m in squad.squad_members:
			if m != null and is_instance_valid(m):
				ai.deregister_enemy(m)
				m.queue_free()
	cm.spawner.clear()
	for _i in 5:
		await physics_frame

	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(99999)
	var tube_rec := state.recruit(frame)
	tube_rec.benched = false
	tube_rec.weapon_ids[0] = &"mortar"
	var spot_rec := state.recruit(cat.chassis_def(&"soldier"))
	spot_rec.benched = false
	spot_rec.weapon_ids[0] = &"m4"
	cm.spawner.spawn_mode = SquadSpawner.SpawnMode.PLAYER
	cm.spawner.deploy_into(level, [tube_rec, spot_rec] as Array[SoldierRecord])
	for _i in 20:
		await physics_frame
	for squad in cm.spawner.squads:
		squad.objective = Squad.SquadObjective.DEFEND
		for m in squad.squad_members:
			if m == null or not is_instance_valid(m):
				continue
			if String(m.get_script().resource_path).ends_with("reclaimer.gd"):
				_rec = m
			else:
				_spotter = m
	_check("(setup) both deployed", _rec != null and _spotter != null)
	if _rec == null or _spotter == null:
		quit(1)
		return

	_check("deployed, the Reclaimer carries the mortar", _rec.weapon != null
		and String(_rec.weapon.scene_file_path).ends_with("ai-wep_mortar.tscn"), str(_rec.weapon))
	_check("...on the end of the boom, where the welder was", _rec.weapon != null
		and _rec.weapon.get_parent() != null and _rec.weapon.get_parent().get_parent() == _rec.wrist)
	var head = _rec.wrist.get_node_or_null("Head")
	_check("...and the welding head is gone", head != null and not head.visible)

	# ── SPOTTER FIRE ─────────────────────────────
	# A WALL between the Reclaimer and the target, and the rifle out past the
	# end of it. On open ground this proves nothing: the squad hands its target
	# round, the valley floor is flat, and the Reclaimer can see it for itself.
	# Behind a wall it cannot, whatever it is told — which is what a mortar is
	# for. The round's arc is up near 25m by the time it passes the wall.
	var base := _ground(space, SITE)
	var wall := StaticBody3D.new()
	var slab := CollisionShape3D.new()
	slab.shape = BoxShape3D.new()
	(slab.shape as BoxShape3D).size = Vector3(1.0, 4.0, 8.0)
	wall.add_child(slab)
	valley.add_child(wall)
	wall.global_position = base + Vector3(10, 2, 0)
	_rec_at = base
	_enemy_at = _ground(space, base + Vector3(55, 0, 0))
	_spot_at = _ground(space, base + Vector3(25, 0, 12))
	player.global_position = base + Vector3(-25, 1, 0)   # well clear of the shells
	_enemy = cat.chassis_def(&"soldier").scene.instantiate()
	valley.add_child(_enemy)
	_enemy.faction = Enums.Factions.ENEMY
	_enemy.global_position = _enemy_at
	ai.register_enemy(_enemy)
	await physics_frame
	# Unarmed, and too tough to die: a target, not a firefight.
	if _enemy.weapon != null:
		_enemy.weapon.queue_free()
		_enemy.weapon = null
	_enemy.max_health = HUGE
	_enemy.health = HUGE
	for b in [_rec, _spotter]:
		b.max_health = HUGE
		b.health = HUGE
	# A spotter, not a shooter: every point of damage on the target is the tube's.
	_spotter.weapon.base_damage = 0
	_spotter.weapon.min_damage = 0

	var saw_it := false
	var fired := 0
	var last: int = _rec.weapon._last_fired_ms
	for f in 900:
		_rec.global_position = _rec_at
		_spotter.global_position = _spot_at
		_enemy.global_position = _enemy_at
		if f % 60 == 0:
			_spotter.trigger_combat(_enemy)
		await physics_frame
		if _rec.combat_target == _enemy and _rec._has_los:
			saw_it = true
		if _rec.weapon._last_fired_ms != last:
			last = _rec.weapon._last_fired_ms
			fired += 1
	_check("(setup) the rifle has the target in its sights", _spotter._has_los and _spotter.combat_target == _enemy)
	_check("the Reclaimer never saw the target: the wall is in the way",
		not saw_it and not _rec.is_path_clear(_rec.global_position + Vector3.UP * 0.8, _enemy.global_position, _enemy))
	_check("...and shelled it anyway, off the rifle's sighting: a round every few seconds",
		fired >= 3, "%d rounds in 15s" % fired)
	# The last rounds are still in the air when the window closes: six seconds up and down.
	for _i in 420:
		_enemy.global_position = _enemy_at
		await physics_frame
	# EVERY round, not some. Coming down this steep this fast, a round without
	# continuous collision went through the valley floor between two physics
	# ticks about half the time — no contact, no bang, gone.
	var dealt := HUGE - _enemy.health
	_check("...and every round comes down on it", dealt >= 70 * fired, "%d damage off %d rounds" % [dealt, fired])

	# ── DANGER CLOSE ─────────────────────────────
	_spot_at = _ground(space, _enemy_at + Vector3(-5, 0, 0))
	await _hold(60)   # anything already laid on goes before the rifle gets there
	var close := await _hold(480)
	_check("with the rifle five metres from the target, it holds fire", close == 0,
		"%d rounds danger-close" % close)
	_spot_at = _ground(space, base + Vector3(25, 0, 12))
	var resumed := await _hold(420)
	_check("...and picks up again once the rifle moves off", resumed >= 1, "nothing in 7s")

	# ── NO WELDING ───────────────────────────────
	_spotter.max_health = 60
	_spotter.health = 20
	_spot_at = _rec_at + Vector3(2.0, 0, 0)
	_enemy.queue_free()   # nothing to shoot: the lull
	for _i in 300:
		_rec.global_position = _rec_at
		_spotter.global_position = _spot_at
		await physics_frame
	_check("armed, it does not weld a hurt squadmate beside it", _rec._patient == null and _spotter.health <= 20,
		"patient %s, rifle at %d" % [str(_rec._patient), _spotter.health])

	# ── NOTHING IN THE AIR ───────────────────────
	# A drone in range and in the rifle's sights, and nothing else to shoot at:
	# the tube stays down. Held where it is put, with its guns off.
	var drone: Soldier = load("res://Campaign/chassis/chassis_helicopter.tres").scene.instantiate()
	valley.add_child(drone)
	drone.faction = Enums.Factions.ENEMY
	var drone_at := base + Vector3(55, 22, 20)
	drone.global_position = drone_at
	ai.register_enemy(drone)
	await physics_frame
	if drone.weapon != null:
		drone.weapon.queue_free()
		drone.weapon = null
	drone.max_health = HUGE
	drone.health = HUGE
	_spot_at = _ground(space, base + Vector3(25, 0, 12))
	var at_drone := 0
	var saw_drone := false
	last = _rec.weapon._last_fired_ms
	for f in 420:
		_rec.global_position = _rec_at
		_spotter.global_position = _spot_at
		drone.global_position = drone_at
		if f % 60 == 0:
			_spotter.trigger_combat(drone)
		await physics_frame
		if _spotter.combat_target == drone and _spotter._has_los:
			saw_drone = true
		if _rec.weapon._last_fired_ms != last:
			last = _rec.weapon._last_fired_ms
			at_drone += 1
	_check("(setup) the rifle has a drone in its sights, in the tube's range", saw_drone)
	_check("the mortar never shells a drone", at_drone == 0, "%d rounds at it" % at_drone)
	drone.queue_free()
	_spot_at = _rec_at + Vector3(2.0, 0, 0)   # back beside it: the squad's line is what a wreck is judged from

	# ── STILL GRINDS ─────────────────────────────
	var wreck: Soldier = cat.chassis_def(&"soldier").scene.instantiate()
	valley.add_child(wreck)
	wreck.faction = Enums.Factions.ENEMY
	wreck.global_position = _ground(space, _rec_at + Vector3(0, 0, 8))
	ai.register_enemy(wreck)
	for _i in 60:
		await physics_frame
	wreck.apply_damage(99999, player)
	var took := false
	for _i in 900:
		_spotter.global_position = _spot_at
		await physics_frame
		if _rec._wreck == wreck:
			took = true
			break
	_check("with nothing to shell, it still goes for a wreck", took,
		"downed %s, salvageable %s" % [str(wreck.downed), str(_rec._salvageable(wreck))] if is_instance_valid(wreck) else "wreck gone")

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
