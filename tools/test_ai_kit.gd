extends SceneTree

# ─────────────────────────────────────────────
# THE REST OF THE KIT, NOW THAT THE SQUAD CAN ACTUALLY USE IT.
#
# Smoke, the Drone Carrier Pack and both mines shipped with usable_by_ai = false
# and no ai_scene at all. That is a quiet failure in two places at once: the
# squad page greyed the row with "YOU ONLY", and squad_spawner skipped the slot
# on any save where one had been fitted anyway — so the item existed, cost
# supply, and never appeared in a mission.
#
# What is pinned here is the DECISION in each case, because the decision is the
# whole item. Three of the four could have been pointed at ai_grenade.tscn in a
# single line and would then have been "AI-usable" while never once being used:
# a grenade wants a target that is stationary, clustered and behind cover, and
# none of these four want anything of the sort.
#
# So each block below pins the reason the item opens AND at least one refusal
# that the grenade's conditions would have got wrong.
#
# Builds the equipment directly rather than booting a mission. Nothing is
# written; no world, no save.
# ─────────────────────────────────────────────

const AI_SMOKE := "res://Character/weapon/ai_smoke.tscn"
const AI_DRONE_PACK := "res://Character/weapon/drone_pack/ai_drone_pack.tscn"
const AI_MINE_CLUSTER := "res://Character/weapon/mines/ai_mine_cluster.tscn"
const AI_MINE_HEAVY := "res://Character/weapon/mines/ai_mine_heavy.tscn"

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"

## Squad.SquadObjective, which is not visible from a SceneTree script.
const OBJ_NONE := 0
const OBJ_ADVANCE := 1
const OBJ_DEFEND := 2
const OBJ_WITHDRAW := 3

var _fails := 0
var _mgr: Node = null
var _owner: Node3D = null


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-58s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-58s got %s, wanted %s" % [label, str(got), str(want)])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	_mgr = AIManager.new()
	root.add_child(_mgr)
	_owner = load(RIFLE).instantiate()
	root.add_child(_owner)
	_owner.faction = Enums.Factions.ALLIED
	_owner.global_position = Vector3.ZERO
	if _mgr.has_method("register_enemy"):
		_mgr.register_enemy(_owner)
	_owner.ai_manager = _mgr
	for _i in 4:
		await process_frame

	await _catalogue_checks()
	await _smoke_checks()
	await _mine_checks()
	await _drone_pack_checks()

	if _fails == 0:
		print("ALL AI KIT CHECKS PASS")
	else:
		print("AI KIT FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


## A fresh context with nothing happening. Every block starts from this and sets
## only the fields its rule reads, so a check that passes for the wrong reason
## (a leftover field from the previous case) cannot hide.
func _ctx() -> AIEquipment.EquipmentContext:
	var c := AIEquipment.EquipmentContext.new()
	c.owner_ai = _owner
	c.combat_target = null
	c.target_position = _owner.global_position
	c.squad_last_equipment_ms = 0
	c.under_fire_seconds = AIEquipment.NEVER_HIT
	c.squad_objective = OBJ_NONE
	return c


# ─────────────────────────────────────────────
# THE ITEMS SAY THEY ARE USABLE
#
# fits_ai() is two conditions and the items failed BOTH, so flipping one flag
# would have looked right on the card and still never spawned.
# ─────────────────────────────────────────────
func _catalogue_checks() -> void:
	print("THE CATALOGUE")
	for id_value in ["smoke", "drone_pack", "mine_cluster", "mine_heavy"]:
		var item: ItemDefinition = load("res://Campaign/items/item_%s.tres" % id_value)
		_check("%s has an AI scene" % id_value, item.ai_scene != null, true)
		_check("%s fits a squadmate" % id_value, item.fits_ai(), true)
		# The other half of "ensure I can equip it": squad_page greys a row
		# whose carrier_tag says one side only, and these four are for both.
		_check("%s still fits the player too" % id_value, item.fits_player(), true)
		_check("%s reads as neither-side-only" % id_value, item.carrier_tag(), "")
	await process_frame


# ─────────────────────────────────────────────
# SMOKE
# ─────────────────────────────────────────────
func _smoke_checks() -> void:
	print("SMOKE — THREE REASONS AND NO FOURTH")
	var kit = load(AI_SMOKE).instantiate()
	root.add_child(kit)

	# Something to be screened from, 30 m out and in the open.
	var foe: Node3D = load(RIFLE).instantiate()
	root.add_child(foe)
	foe.faction = Enums.Factions.ENEMY
	foe.global_position = Vector3(30, 0, 0)
	if _mgr.has_method("register_enemy"):
		_mgr.register_enemy(foe)
	for _i in 2:
		await process_frame

	var c := _ctx()
	c.threat_position = foe.global_position
	c.threat_bearing = Vector3(1, 0, 0)
	c.threat_actor = foe

	# NOBODY IS SHOOTING. All three reasons are reasons to stop being shot, so
	# this is the refusal that stops a squad fogging the map on contact.
	c.squad_objective = OBJ_WITHDRAW
	_check("holds while nothing is hitting us", kit.can_use(c), false)

	# 1 — breaking contact. The order is the signal; no health check needed.
	c.under_fire_seconds = 0.5
	_check("throws on WITHDRAW under fire", kit.can_use(c), true)

	# ...and the same robot, same damage, with no order to leave.
	c.squad_objective = OBJ_DEFEND
	_check("holds on DEFEND under fire — not a reason on its own",
		kit.can_use(c), false)

	# 2 — a casualty within reach. Worth a canister whatever else is happening,
	# and the one case where the cloud goes on the mate rather than the threat.
	var mate := Node3D.new()
	root.add_child(mate)
	mate.global_position = Vector3(0, 0, 6)
	c.downed_friendly = mate
	_check("throws for a downed squadmate 6 m away", kit.can_use(c), true)
	_check("the cloud goes ON the casualty, not toward the threat",
		kit._screen_point(c).is_equal_approx(mate.global_position), true)
	mate.global_position = Vector3(0, 0, 40)   # somebody else's casualty
	_check("holds for one 40 m away", kit.can_use(c), false)
	c.downed_friendly = null

	# 3 — crossing open ground, and losing. Needs the third clause, which the
	# other two do not: an advancing robot that smokes every incoming round
	# empties its pouches in the first half-minute of a mission.
	c.squad_objective = OBJ_ADVANCE
	_owner.health = _owner.max_health
	_check("holds while advancing, hit, but healthy and alone",
		kit.can_use(c), false)
	_owner.health = int(_owner.max_health * 0.4)
	_check("throws while advancing, hit and down to 40% hull",
		kit.can_use(c), true)

	# WHY THAT ONE NEEDED FIXING, pinned so it cannot come back. A ray cast at
	# a body's own position stops inside its collider, so the obvious spelling
	# of "can they see me" answers no in an empty field and this whole branch
	# was dead. Excluding the threat is what makes it a sight test.
	_check("a ray into the threat's own collider reads as blocked",
		_owner.is_path_clear(_owner.global_position + Vector3.UP * 0.8,
			foe.global_position), false)
	_check("...and reads clear once the threat is excluded",
		_owner.is_path_clear(_owner.global_position + Vector3.UP * 0.8,
			foe.global_position, foe), true)

	# ...but not across a street it is not actually exposed on.
	foe.global_position = Vector3(8, 0, 0)
	c.threat_position = foe.global_position
	for _i in 2:
		await process_frame
	_check("holds at 8 m — that is a firefight, not a crossing",
		kit.can_use(c), false)
	foe.global_position = Vector3(30, 0, 0)
	c.threat_position = foe.global_position
	for _i in 2:
		await process_frame

	# The squad spacing. One cloud covers a fireteam; the second adds nothing.
	c.squad_last_equipment_ms = Time.get_ticks_msec()
	_check("holds right after a squadmate threw something", kit.can_use(c), false)
	c.squad_last_equipment_ms = Time.get_ticks_msec() - 20000
	_check("...and throws again once that has aged out", kit.can_use(c), true)

	# WHERE IT LANDS. Across the sightline, not at our feet and not in their lap.
	var mark: Vector3 = kit._screen_point(c)
	var reach: float = _owner.global_position.distance_to(mark)
	_check("the cloud lands short of the threat", reach < 30.0, true)
	_check("...and clear of our own feet", reach >= kit.min_screen_metres, true)
	_check("...on the line between us", mark.normalized().is_equal_approx(Vector3(1, 0, 0)), true)

	var before := root.get_child_count()
	kit.execute(c)
	await process_frame
	_check("execute() put a canister in the world", root.get_child_count() > before, true)

	_owner.health = _owner.max_health
	foe.queue_free()
	mate.queue_free()
	kit.queue_free()
	await process_frame


# ─────────────────────────────────────────────
# MINES
# ─────────────────────────────────────────────
func _mine_checks() -> void:
	print("MINES — LAID BEFORE THEY ARRIVE, NOT WHEN THEY DO")
	var kit = load(AI_MINE_CLUSTER).instantiate()
	root.add_child(kit)

	var foe: Node3D = load(RIFLE).instantiate()
	root.add_child(foe)
	foe.faction = Enums.Factions.ENEMY
	foe.global_position = Vector3(0, 0, 25)
	if _mgr.has_method("register_enemy"):
		_mgr.register_enemy(foe)
	for _i in 2:
		await process_frame

	var c := _ctx()
	c.squad_objective = OBJ_DEFEND
	c.threat_position = foe.global_position
	c.threat_bearing = Vector3(0, 0, 1)

	_check("lays one holding ground with contact 25 m out", kit.can_use(c), true)

	# A garrison robot is in no squad and reports NONE. Excluding it would have
	# meant only the player's own squad ever laid a mine.
	c.squad_objective = OBJ_NONE
	_check("a garrison robot in no squad lays one too", kit.can_use(c), true)

	# THE RULE THAT MATTERS. Mine.arm_seconds is 1.5, so a mine laid at contact
	# range is inert for the whole exchange it was laid for.
	c.squad_objective = OBJ_DEFEND
	c.threat_position = Vector3(0, 0, 6)
	_check("holds with them 6 m away — too late, shoot instead",
		kit.can_use(c), false)
	c.threat_position = foe.global_position

	# Nothing located: no bearing, so no ground worth denying.
	c.threat_bearing = Vector3.ZERO
	_check("holds with nothing located — a mine needs an approach",
		kit.can_use(c), false)
	c.threat_bearing = Vector3(0, 0, 1)

	# A robot moving onto an objective will be standing past its own mine.
	c.squad_objective = OBJ_ADVANCE
	_check("holds while advancing", kit.can_use(c), false)
	c.squad_objective = OBJ_WITHDRAW
	_check("lays one while breaking contact", kit.can_use(c), true)

	c.squad_last_equipment_ms = Time.get_ticks_msec()
	_check("holds right after a squadmate laid one", kit.can_use(c), false)
	c.squad_last_equipment_ms = 0

	# ON THE APPROACH, between us and them — never past what it is meant to
	# catch, and never between our own feet.
	var before := root.get_child_count()
	kit.execute(c)
	await process_frame
	_check("execute() put a mine in the world", root.get_child_count() > before, true)
	var laid := _newest_child(before)
	_check("the mine landed, or is heading, toward the threat",
		laid != null and laid.linear_velocity.z > 0.0, true)
	# Load-bearing: Mine._faction() reads the thrower, and an unset one defaults
	# to the PLAYER's side — an enemy-laid mine would hunt its own garrison.
	_check("setup() ran, so the mine knows whose it is",
		laid != null and laid.get("_thrower") == _owner, true)

	# The heavy mine is the same script with a tighter window.
	var heavy = load(AI_MINE_HEAVY).instantiate()
	root.add_child(heavy)
	_check("the heavy mine runs the same decision",
		heavy.get_script() == kit.get_script(), true)
	_check("...and accepts closer contact than the cluster",
		heavy.min_contact_metres < kit.min_contact_metres, true)
	_check("...and is laid nearer in", heavy.place_metres < kit.place_metres, true)

	foe.queue_free()
	heavy.queue_free()
	kit.queue_free()
	await process_frame


func _newest_child(before: int) -> Node:
	var kids := root.get_children()
	for i in range(kids.size() - 1, -1, -1):
		if kids[i] is RigidBody3D:
			return kids[i]
	return null


# ─────────────────────────────────────────────
# DRONE CARRIER PACK
# ─────────────────────────────────────────────
func _drone_pack_checks() -> void:
	print("DRONE CARRIER PACK — IT WAITS FOR ARMOUR")
	var kit = load(AI_DRONE_PACK).instantiate()
	root.add_child(kit)
	_check("it is a deploy, not a throw",
		str(kit.get_script().resource_path),
		"res://Character/characters/ai/equipment/ai_deploy.gd")

	# Two rifle troopers: enough bodies, nothing worth 95 supply and two Divers.
	var grunts: Array = []
	for i in 2:
		var g: Node3D = load(RIFLE).instantiate()
		root.add_child(g)
		g.faction = Enums.Factions.ENEMY
		g.global_position = Vector3(14 + i * 2, 0, 0)
		if _mgr.has_method("register_enemy"):
			_mgr.register_enemy(g)
		grunts.append(g)
	for _i in 3:
		await process_frame

	var c := _ctx()
	c.threat_bearing = Vector3(1, 0, 0)
	_check("holds for two rifle troopers — a worse trade than the rifle",
		kit.can_use(c), false)

	# A Walker at 320 hull is what the pack is for.
	var walker: Node3D = load(WALKER).instantiate()
	root.add_child(walker)
	walker.faction = Enums.Factions.ENEMY
	walker.global_position = Vector3(20, 0, 0)
	if _mgr.has_method("register_enemy"):
		_mgr.register_enemy(walker)
	for _i in 3:
		await process_frame
	_check("opens for a Walker", kit.can_use(c), true)

	# It does not need a combat target, which is the point of AIDeploy and the
	# condition a grenade would have failed.
	_check("...with no combat target at all", c.combat_target == null, true)

	# And the hatchling must not have picked up this rule: min_target_health
	# defaults to 0, so the cheap swarm still opens for anything.
	var hatch = load("res://Character/weapon/hatchling/ai_hatchling.tscn").instantiate()
	root.add_child(hatch)
	_check("the hatchling has no hull bar", hatch.min_target_health, 0.0)
	walker.queue_free()
	for _i in 3:
		await process_frame
	_check("...so it still opens for rifle troopers alone", hatch.can_use(c), true)

	for g in grunts:
		g.queue_free()
	hatch.queue_free()
	kit.queue_free()
	await process_frame
