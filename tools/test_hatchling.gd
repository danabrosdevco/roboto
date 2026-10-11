extends SceneTree

# ─────────────────────────────────────────────
# THE HATCHLING IS DEPLOYED, NOT THROWN.
#
# It used to run AIGrenade with its canister swapped in for the grenade, so it
# inherited a grenade's conditions: a target standing still, or clustered, or
# behind cover, at four to thirty metres. A squad carrying hatchlings would
# stand in a fight and never open one, and nothing said so — the slot simply
# never emptied.
#
# AIDeploy asks the only question a hatchling cares about: is there anything
# nearby for the units to go and find. These pin that, and in particular pin the
# two things that WOULD have stopped the old one:
#
#   * no combat target at all, and it still opens
#   * a target closer than a grenade's minimum throw, and it still opens
#
# Plus the two refusals that keep a squad from emptying its pockets into one
# skirmish: nothing in range, and a squadmate having just spent something.
#
# Builds the equipment directly rather than booting a mission. Nothing is
# written; no world, no save.
# ─────────────────────────────────────────────

const AI_HATCHLING := "res://Character/weapon/hatchling/ai_hatchling.tscn"
## By path: ai_deploy.gd deliberately has no class_name (see its header).
const DEPLOY_SCRIPT := "res://Character/characters/ai/equipment/ai_deploy.gd"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fails := 0


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-56s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-56s got %s, wanted %s" % [label, str(got), str(want)])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var kit = load(AI_HATCHLING).instantiate()
	root.add_child(kit)
	var script_path := "" if kit.get_script() == null else str(kit.get_script().resource_path)
	_check("the hatchling's AI scene is an AIDeploy, not a grenade",
		script_path, DEPLOY_SCRIPT)
	if script_path != DEPLOY_SCRIPT:
		print("FAIL — nothing else can be checked")
		quit(1)
		return
	_check("it carries a canister to open", kit.canister_scene != null, true)

	# A thrower and something to find, both registered so the manager can see
	# them — an unregistered hostile is invisible to get_hostiles_in_radius and
	# every check below would pass for the wrong reason.
	var mgr := AIManager.new()
	root.add_child(mgr)
	var thrower: Node3D = load(RIFLE).instantiate()
	root.add_child(thrower)
	thrower.faction = Enums.Factions.ALLIED
	thrower.global_position = Vector3.ZERO
	var foe: Node3D = load(RIFLE).instantiate()
	root.add_child(foe)
	foe.faction = Enums.Factions.ENEMY
	foe.global_position = Vector3(12, 0, 0)
	if mgr.has_method("register_enemy"):
		mgr.register_enemy(thrower)
		mgr.register_enemy(foe)
	thrower.ai_manager = mgr
	for _i in 4:
		await process_frame

	var ctx := AIEquipment.EquipmentContext.new()
	ctx.owner_ai = thrower
	ctx.combat_target = null          # THE POINT: no target at all
	ctx.target_position = thrower.global_position
	ctx.threat_bearing = Vector3(1, 0, 0)
	ctx.squad_last_equipment_ms = 0

	print("WITH SOMETHING NEARBY AND NO TARGET")
	_check("opens with no combat target — a grenade would have refused",
		kit.can_use(ctx), true)

	print("AT A RANGE A GRENADE REFUSES")
	foe.global_position = Vector3(2.0, 0, 0)   # inside min_throw_distance (4 m)
	for _i in 2:
		await process_frame
	_check("opens with a hostile at 2 m", kit.can_use(ctx), true)

	print("REFUSALS")
	foe.global_position = Vector3(400, 0, 0)
	for _i in 2:
		await process_frame
	_check("nothing within release_radius, so it holds", kit.can_use(ctx), false)

	foe.global_position = Vector3(12, 0, 0)
	for _i in 2:
		await process_frame
	ctx.squad_last_equipment_ms = Time.get_ticks_msec()
	_check("a squadmate just spent something, so it holds",
		kit.can_use(ctx), false)
	ctx.squad_last_equipment_ms = Time.get_ticks_msec() - 20000
	_check("...and opens again once that has aged out", kit.can_use(ctx), true)

	print("IT ACTUALLY PUTS SOMETHING IN THE WORLD")
	var before := root.get_child_count()
	kit.execute(ctx)
	await process_frame
	_check("execute() added a canister to the scene", root.get_child_count() > before, true)

	if _fails == 0:
		print("ALL HATCHLING CHECKS PASS")
	else:
		print("HATCHLING FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
