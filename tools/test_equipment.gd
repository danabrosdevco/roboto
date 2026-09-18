extends SceneTree

# ─────────────────────────────────────────────
# EQUIPMENT & MODULES — does each item actually DO the thing it says?
#
# Loads the real world, the real catalogue and the real scenes, then exercises
# each of the five items end to end. A text-level check can confirm a .tres
# parses; it cannot confirm an EMP freezes anything, that a hatchling climbs
# out on your side rather than theirs, or that a module fitted to yourself
# changes your body — which is exactly the bug that had been sitting in the
# armour plating unnoticed.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _spawn(level: Node, mgr: Node, player: Node3D, faction: int, at: Vector3) -> Soldier:
	var s: Soldier = load("res://Character/characters/ai/soldier_shotgun.tscn").instantiate()
	s.faction = faction
	s.always_active = true
	level.add_child(s)
	s.global_position = at
	if mgr != null:
		mgr.register_enemy(s)
	return s


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
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")

	# ── CATALOGUE ────────────────────────────────
	for id in [&"overclock_servos", &"hardened_uplink", &"nanite_reboot", &"emp", &"hatchling"]:
		_check("catalogue has %s" % id, cat.item(id) != null)
	_check("uplink is squad-only and says so",
		not cat.item(&"hardened_uplink").fits_player() and cat.item(&"hardened_uplink").carrier_tag() == "[SQUAD]")
	_check("emp and hatchling fit both sides",
		cat.item(&"emp").fits_player() and cat.item(&"emp").fits_ai()
		and cat.item(&"hatchling").fits_player() and cat.item(&"hatchling").fits_ai())
	print("      uplink reads: %s" % cat.item(&"hardened_uplink").effect_summary())
	print("      nanites read: %s" % cat.item(&"nanite_reboot").effect_summary())

	# ── MODULES ON A SQUADMATE ──────────────────
	var rec := SoldierRecord.new()
	rec.chassis_id = &"soldier"
	rec.module_ids = [&"overclock_servos", &"hardened_uplink"] as Array[StringName]
	rec.recompute_stats(cat)
	_check("overclock folds into speed", is_equal_approx(rec.effective_speed, 1.2), str(rec.effective_speed))
	_check("uplink folds into resistance", is_equal_approx(rec.effective_signal_resistance_bonus, 1.0))
	var rec2 := SoldierRecord.new()
	rec2.chassis_id = &"soldier"
	rec2.module_ids = [&"nanite_reboot"] as Array[StringName]
	rec2.recompute_stats(cat)
	_check("nanites fold into self-revive", is_equal_approx(rec2.effective_self_revive, 10.0))

	# ── MODULES ON THE PLAYER ────────────────────
	# The body's own health, not whatever this machine's save has fitted to it.
	var base_max: int = player._base_max_health if player._base_max_health >= 0 else int(player.max_health)
	# 100, with a third of every hit taken. world.tscn once carried a 500
	# override on the player instance that quietly outranked the player scene.
	_check("the player's body is 100 HP", base_max == 100, str(base_max))
	var prec := SoldierRecord.new()
	prec.chassis_id = &"soldier"
	prec.module_ids = [&"armor_plating", &"overclock_servos"] as Array[StringName]
	player._apply_module_stats(prec, cat)
	_check("armour plating reaches the player's body",
		int(player.max_health) == base_max + 25, "%d -> %d" % [base_max, int(player.max_health)])
	_check("overclock reaches the player's legs", is_equal_approx(player._speed_mult, 1.2))
	prec.module_ids = [&"hardened_uplink"] as Array[StringName]
	player._apply_module_stats(prec, cat)
	_check("a squad-only module does nothing on the player",
		int(player.max_health) == base_max and is_equal_approx(player._speed_mult, 1.0))

	# ── THE PLAYER TAKES A THIRD OF EVERY HIT ────
	player.health = player.max_health
	player._damage_carry = 0.0
	var hp_before: int = int(player.health)
	player.apply_damage(30, null)
	_check("a 30-damage hit costs the player 10", hp_before - int(player.health) == 10,
		"%d -> %d" % [hp_before, int(player.health)])
	hp_before = int(player.health)
	for _i in 3:
		player.apply_damage(1, null)
	_check("...and three 1-damage chips still cost 1 between them", hp_before - int(player.health) == 1,
		"%d -> %d" % [hp_before, int(player.health)])
	player.health = player.max_health

	# ── REPAIR TOOL, BUILT IN ON 3 ───────────────
	# It changes the game completely if you don't have one, so it is no longer a
	# fitting you can forget: it replaced the knife as the permanent item.
	var tool: PlayerEquipment = player.loadout.item_for_slot(2)
	_check("key 3 is the repair tool, built in", tool is PlayerRepairTool, str(tool))
	# The loadout opens on the only thing that exists before the record builds
	# your guns — the permanent tool — and used to keep holding it.
	_check("you spawn holding your gun, not the repair tool",
		player.loadout.primary == null or player.loadout.current == player.loadout.primary,
		"holding %s" % str(player.loadout.current))
	_check("...and the knife is gone", _find(player, "PlayerMelee") == null)
	_check("the repair tool can no longer be fitted to the player", not cat.item(&"repair_tool").fits_player())
	_check("...nor bought: squads use the Field Repair Kit", not cat.item(&"repair_tool").in_shop)
	player.loadout.equip_slot(2)
	for _i in 3:
		await physics_frame
	_check("pressing 3 draws it", player.loadout.current == tool, str(player.loadout.current))
	# Standing against the robot you are fixing trips the obstruction ray.
	tool.update_view(0.016, 0.0, true, false)
	_check("...and it stays up when something is right in front of you", not tool.is_obstructed)
	player.loadout.equip_slot(0)
	for _i in 3:
		await physics_frame

	# ── SELF-REVIVE ──────────────────────────────
	var nano := _spawn(level, mgr, player, Enums.Factions.PLAYER, player.global_position + Vector3(8, 0, 0))
	nano.self_revive_seconds = 0.4
	await physics_frame
	nano.enter_downed()
	_check("nanite soldier goes down", nano.downed)
	for _i in 40:
		await physics_frame
	_check("...and gets itself back up", not nano.downed and nano.alive)
	nano.enter_downed()
	for _i in 40:
		await physics_frame
	_check("...but only once per deployment", nano.downed)

	# ── EMP ──────────────────────────────────────
	var ground := player.global_position + Vector3(0, 0, 30)
	var near := _spawn(level, mgr, player, Enums.Factions.ENEMY, ground)
	var mid := _spawn(level, mgr, player, Enums.Factions.ENEMY, ground + Vector3(6, 0, 0))
	var far := _spawn(level, mgr, player, Enums.Factions.ENEMY, ground + Vector3(20, 0, 0))
	var hard := _spawn(level, mgr, player, Enums.Factions.ENEMY, ground + Vector3(0, 0, 1))
	hard.signal_resistance = 2.0   # a Hardened Uplink's worth
	var ally := _spawn(level, mgr, player, Enums.Factions.PLAYER, ground + Vector3(-1, 0, 0))
	await physics_frame
	var blast: EmpBlast = load("res://Character/weapon/emp/emp_blast.tscn").instantiate()
	blast.source_faction = Enums.Factions.PLAYER
	level.add_child(blast)
	blast.global_position = ground
	await physics_frame
	_check("EMP freezes the centre (E-KILL)", near.get_signal_state() == Enemy.SignalState.EKILL,
		"signal=%.2f" % near.signal_integrity)
	_check("EMP disrupts mid-range without freezing",
		mid.get_signal_state() != Enemy.SignalState.CLEAN and mid.get_signal_state() != Enemy.SignalState.EKILL,
		"signal=%.2f" % mid.signal_integrity)
	_check("EMP leaves out-of-range robots alone", is_equal_approx(far.signal_integrity, 1.0))
	_check("Hardened Uplink survives a direct hit", hard.get_signal_state() != Enemy.SignalState.EKILL,
		"signal=%.2f" % hard.signal_integrity)
	_check("your own squad is only clipped", ally.signal_integrity > 0.6, "signal=%.2f" % ally.signal_integrity)
	# The lock is the whole stun. Without it this was back up in 0.13s.
	for _i in 90:
		await physics_frame
	_check("...and stays frozen after 1.5s (recovery locked)",
		near.get_signal_state() == Enemy.SignalState.EKILL, "signal=%.2f" % near.signal_integrity)

	# ── EMP VS A DRONE ───────────────────────────
	var drone: Soldier = load("res://Character/characters/ai/enemy_helicopter.tscn").instantiate()
	level.add_child(drone)
	if mgr != null:
		mgr.register_enemy(drone)
	drone.global_position = ground + Vector3(40, 16, 0)
	for _i in 5:
		await physics_frame
	drone.receive_signal_damage(2.0)
	for _i in 3:
		await physics_frame
	_check("an EMP'd drone drops out of the sky rather than hanging there", drone.downed)

	# ── HATCHLING ────────────────────────────────
	var prey := _spawn(level, mgr, player, Enums.Factions.ENEMY, player.global_position + Vector3(-25, 0, 10))
	await physics_frame
	var before := 0
	for n in level.get_children():
		if n is Soldier and str(n.soldier_name) == "HATCHLING":
			before += 1
	var payload: HatchlingPayload = load("res://Character/weapon/hatchling/hatchling_payload.tscn").instantiate()
	payload.source_faction = Enums.Factions.PLAYER
	payload.source_actor = player
	payload.lifetime = 1.0
	level.add_child(payload)
	payload.global_position = player.global_position + Vector3(-12, 0.5, 10)
	for _i in 4:
		await physics_frame
	var pup: Soldier = null
	for n in level.get_children():
		if n is Soldier and str(n.soldier_name) == "HATCHLING":
			pup = n
	_check("a hatchling climbs out", pup != null and before == 0)
	if pup != null:
		_check("...on the thrower's side", pup.faction == Enums.Factions.PLAYER)
		_check("...registered, so it can actually move", pup.player != null)
		_check("...already sicced on the nearest hostile", pup.combat_target == prey,
			"target=%s" % str(pup.combat_target))
		# The hatchling expires in seconds and has no record — a kill left on it
		# was a kill nobody got. It belongs to whoever threw the canister.
		var kills_before: int = player.confirmed_kills
		prey.apply_damage(9999, pup)
		_check("...and its kills are credited to whoever threw it",
			player.confirmed_kills == kills_before + 1 and pup.confirmed_kills == 0,
			"player %d -> %d, hatchling %d" % [kills_before, player.confirmed_kills, pup.confirmed_kills])
		for _i in 80:
			await physics_frame
		_check("...and shuts down when its time is up", not is_instance_valid(pup) or not pup.alive)

	# ── TWO OF THE SAME THROWN ITEM, TWICE THE CARRY ──
	# Two frag slots used to share one pouch: the second slot was just a second
	# key for the same three grenades.
	var pool: AmmoPool = player.ammo
	var per_frag: int = 0
	for stock in pool.starting_ammo:
		if stock != null and stock.ammo_type == &"grenade":
			per_frag = stock.capacity
	var kit := SoldierRecord.new()
	kit.chassis_id = &"soldier"
	kit.weapon_ids = [&"shotgun"] as Array[StringName]
	kit.equipment_ids = [&"frag"] as Array[StringName]
	player.loadout.apply_record(kit, cat)
	pool.refill_all()
	_check("one frag slot carries one load", pool.get_capacity(&"grenade") == per_frag
		and pool.get_count(&"grenade") == per_frag, "%d/%d" % [pool.get_count(&"grenade"), pool.get_capacity(&"grenade")])
	kit.equipment_ids = [&"frag", &"frag", &"hatchling"] as Array[StringName]
	player.loadout.apply_record(kit, cat)
	_check("two frag slots carry twice as many — and the second brings its own",
		pool.get_capacity(&"grenade") == per_frag * 2 and pool.get_count(&"grenade") == per_frag * 2,
		"%d/%d" % [pool.get_count(&"grenade"), pool.get_capacity(&"grenade")])
	kit.equipment_ids = [&"frag"] as Array[StringName]
	player.loadout.apply_record(kit, cat)
	_check("...and unfitting one trims back to a single load",
		pool.get_capacity(&"grenade") == per_frag and pool.get_count(&"grenade") == per_frag,
		"%d/%d" % [pool.get_count(&"grenade"), pool.get_capacity(&"grenade")])

	print("")
	print("ALL EQUIPMENT CHECKS PASS" if _fails == 0 else "%d EQUIPMENT CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
