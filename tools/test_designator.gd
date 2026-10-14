extends SceneTree

# ─────────────────────────────────────────────
# "SMOKE THERE" — the ordered-equipment path.
#
# The squad will now use smoke, mines and drone packs on its own judgement, but
# judgement is not command: the moment you want a cloud is the moment you have
# decided to cross a street, and no can_use() rule can know that. The designator
# is the missing verb, and this pins the half of it that is not interaction.
#
# WHAT IS ACTUALLY WORTH PINNING HERE is not "does a canister appear". It is the
# three ways this fails quietly:
#
#   1. The order lands SOMEWHERE ELSE. Every execute() in the kit computes its
#      own placement — smoke at 60% toward the threat, a mine on the approach —
#      and an ordered use has to override that with the point the player chose.
#      A cloud 60% of the way to a threat the player was not even pointing at is
#      indistinguishable from the order being ignored.
#
#   2. can_use() IS STILL CONSULTED. If it is, the order works only in the
#      situations the AI would have acted in anyway, which is exactly the
#      situations where the order is not needed. Smoke's own rule refuses unless
#      the robot is under fire, so a context with nothing happening is the test:
#      the autonomous path must refuse and the ordered path must not.
#
#   3. THE SQUAD SPENDS EVERYTHING. Four robots answering one point is four
#      canisters on a seven metre gap, and four clouds on one spot is one cloud.
#
# Builds squads and robots directly. Nothing is written; no world, no save.
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const AI_SMOKE := "res://Character/weapon/ai_smoke.tscn"
const AI_DRONE_PACK := "res://Character/weapon/drone_pack/ai_drone_pack.tscn"

const SMOKE_ID := &"smoke"
const PACK_ID := &"drone_pack"

var _fails := 0
var _mgr: Node = null


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
	await process_frame

	await _slot_checks()
	await _override_checks()
	await _refusal_checks()
	await _allocation_checks()

	if _fails == 0:
		print("ALL DESIGNATOR CHECKS PASS")
	else:
		print("DESIGNATOR FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


## A robot carrying `count` of the item behind `scene_path`.
func _robot(at: Vector3, item_id: StringName, scene_path: String, count: int) -> Node3D:
	var who: Node3D = load(RIFLE).instantiate()
	var slot := AIEquipmentSlot.new()
	slot.equipment_scene = load(scene_path)
	slot.quantity = count
	slot.item_id = item_id
	slot.label = String(item_id).to_upper()
	who.equipment_slots = [slot] as Array[AIEquipmentSlot]
	root.add_child(who)
	who.faction = Enums.Factions.ALLIED
	who.global_position = at
	who.ai_manager = _mgr
	if _mgr.has_method("register_enemy"):
		_mgr.register_enemy(who)
	return who


# ─────────────────────────────────────────────
# THE SLOT KNOWS WHAT IT IS
#
# Both of these were unset by squad_spawner, and both are read downstream: the
# squad HUD printed the literal word "EQUIPMENT" for every spend, and nothing
# could turn a slot back into an icon.
# ─────────────────────────────────────────────
func _slot_checks() -> void:
	print("THE SLOT KNOWS WHICH ITEM IT IS")
	var who := _robot(Vector3.ZERO, SMOKE_ID, AI_SMOKE, 2)
	await process_frame
	_check("the slot can be found by item id", who.equipment_slot_for(SMOKE_ID), 0)
	_check("...and an item it does not carry comes back -1",
		who.equipment_slot_for(&"mine_heavy"), -1)
	_check("it can answer an order for it", who.can_answer_equipment_order(SMOKE_ID), true)
	who.queue_free()
	await process_frame


# ─────────────────────────────────────────────
# THE ORDER OVERRIDES THE EQUIPMENT'S OWN AIM
# ─────────────────────────────────────────────
func _override_checks() -> void:
	print("AN ORDER PUTS IT WHERE THE PLAYER POINTED")
	var who := _robot(Vector3.ZERO, SMOKE_ID, AI_SMOKE, 2)
	await process_frame

	# THE POINT OF THE WHOLE FEATURE: nothing is happening. Nobody is shooting
	# this robot, it is in no squad, it has no target — so smoke's own rule
	# refuses, and the order must not.
	var kit = load(AI_SMOKE).instantiate()
	root.add_child(kit)
	var idle := AIEquipment.EquipmentContext.new()
	idle.owner_ai = who
	idle.target_position = who.global_position
	_check("smoke refuses this situation on its own judgement",
		kit.can_use(idle), false)
	kit.queue_free()

	var mark := Vector3(14, 0, 3)
	var before := _bodies()
	var refusal: String = who.order_use_equipment(SMOKE_ID, mark, true)
	await process_frame
	_check("...and the order goes through anyway", refusal, "")
	var thrown := _newest_rigidbody(before)
	_check("a canister was thrown", thrown != null, true)
	# It is in the AIR, so it is not AT the mark yet — what is pinned is that it
	# was aimed at the mark rather than at smoke's own 60%-toward-the-threat
	# choice, which with no threat at all would have been the robot's own feet.
	_check("it is travelling toward the mark, not sitting on our feet",
		thrown != null and thrown.linear_velocity.length() > 1.0, true)
	if thrown != null:
		var flat := Vector3(thrown.linear_velocity.x, 0.0, thrown.linear_velocity.z).normalized()
		var want := Vector3(mark.x, 0.0, mark.z).normalized()
		_check("...and along the right bearing", flat.dot(want) > 0.95, true)

	# THE ACCOUNTING. One order, one canister — spending the slot, setting the
	# cooldown and logging the timestamp all live in one function precisely so
	# an ordered use cannot skip one of them.
	_check("the slot was spent", who.equipment_slots[0].remaining(), 1)
	_check("...and it is on cooldown, so a second order is refused now",
		who.order_use_equipment(SMOKE_ID, mark, true), "reloading")

	who.queue_free()
	await process_frame


# ─────────────────────────────────────────────
# IT SAYS WHY IT REFUSES
#
# A key that does nothing is worse than a key that says no, and these strings
# are what reaches the player's screen.
# ─────────────────────────────────────────────
func _refusal_checks() -> void:
	print("EVERY REFUSAL HAS A REASON")
	var who := _robot(Vector3.ZERO, SMOKE_ID, AI_SMOKE, 1)
	await process_frame

	_check("out of throw range", who.order_use_equipment(SMOKE_ID, Vector3(90, 0, 0), true),
		"too far")
	_check("an item nobody is carrying",
		who.order_use_equipment(&"mine_cluster", Vector3(10, 0, 0), true), "not carried")

	# Spend the only one, clear the cooldown, and ask again: "none left" and
	# "reloading" are different answers and the player does different things
	# about them.
	_check("the one it has goes", who.order_use_equipment(SMOKE_ID, Vector3(10, 0, 0), true), "")
	await process_frame
	who._equipment_cooldowns[0] = 0.0
	_check("...and then it is out, which is not the same as reloading",
		who.order_use_equipment(SMOKE_ID, Vector3(10, 0, 0), true), "none left")

	who.downed = true
	_check("a downed robot answers nothing",
		who.can_answer_equipment_order(SMOKE_ID), false)

	who.queue_free()
	await process_frame


# ─────────────────────────────────────────────
# THE SQUAD DECIDES HOW MANY
# ─────────────────────────────────────────────
func _allocation_checks() -> void:
	print("THE SQUAD ALLOCATES — NOT EVERYONE WHO HAS ONE")
	var squad := Squad.new()
	root.add_child(squad)
	squad.player_commandable = true
	var crew: Array = []
	for i in 4:
		crew.append(_robot(Vector3(float(i) * 3.0, 0, 0), SMOKE_ID, AI_SMOKE, 2))
	squad.squad_members.assign(crew)
	for c in crew:
		c.squad = squad
	await process_frame

	var mark := Vector3(10, 0, 18)
	_check("all four are counted as able to answer",
		squad.equipment_holders(SMOKE_ID, mark).size(), 4)

	var result: Dictionary = squad.receive_player_equipment_order(SMOKE_ID, mark, true)
	await process_frame
	# ONE POINT IS ONE CLOUD. Four canisters on a seven metre gap leaves nothing
	# for the disengage that actually needs them, and four clouds on one spot is
	# one cloud.
	_check("one point spends exactly one canister", int(result["spent"]), 1)
	_check("...out of the four that could have", int(result["asked"]), 4)

	var left := 0
	for c in crew:
		left += c.equipment_slots[0].remaining()
	_check("the squad still has seven canisters", left, 7)

	# A FRONTAGE asks for more. This is the primitive a line of mines will share.
	for c in crew:
		c._equipment_cooldowns[0] = 0.0
	var wide: Dictionary = squad.receive_player_equipment_order(SMOKE_ID, mark, true, 18.0)
	await process_frame
	_check("eighteen metres of frontage spends three", int(wide["spent"]), 3)

	# NOBODY CARRYING is its own answer, and it is the one the player will see
	# most often before they have been to the armoury.
	var empty := Squad.new()
	root.add_child(empty)
	var bare := _robot(Vector3(0, 0, 40), PACK_ID, AI_DRONE_PACK, 1)
	empty.squad_members.assign([bare])
	bare.squad = empty
	await process_frame
	var none: Dictionary = empty.receive_player_equipment_order(SMOKE_ID, mark, true)
	_check("a squad with no smoke says so", str(none["reason"]), "nobody carrying")

	# A CONFIRM MODE HAS NO POINT TO MISS. The pack releases units that climb
	# and pick their own target, so an order for one is "open it" — and it must
	# not be refused for being 40 m from a mark it does not use.
	var pack: Dictionary = empty.receive_player_equipment_order(PACK_ID, mark, false)
	await process_frame
	_check("the drone pack opens without a point, at any range",
		int(pack["spent"]), 1)

	for c in crew:
		c.queue_free()
	bare.queue_free()
	squad.queue_free()
	empty.queue_free()
	await process_frame


func _bodies() -> Array:
	var out: Array = []
	for n in root.get_children():
		if n is RigidBody3D:
			out.append(n)
	return out


func _newest_rigidbody(before: Array) -> RigidBody3D:
	for n in root.get_children():
		if n is RigidBody3D and not before.has(n):
			return n
	return null
