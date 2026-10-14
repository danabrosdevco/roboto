extends SceneTree

# ─────────────────────────────────────────────
# THE DRAYMAN
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_drayman.gd
#
# WHAT IS WORTH GUARDING HERE, in order of what it would cost to lose:
#
#   * THE FRAME CAN NEVER HOLD A GUN. starting_weapon_id is empty and
#     turret = false, and the only thing keeping a weapon off the mount is that
#     every vehicle-legal gun in the catalogue names other frames in its
#     chassis_whitelist. A future vehicle gun with an EMPTY whitelist would fit
#     a supply truck silently, so the refusal is asserted across the whole
#     catalogue rather than against a list of ids.
#
#   * THE ONE JOB WORKS, AND IS FINITE. AIEquipmentSlot.restore() is the only
#     way a spent charge ever comes back; `loads` is the only thing stopping an
#     infinite resupply frame, which would be a non-decision.
#
#   * ALLOWED*OPTIONS ARE Array[int] AND NON-EMPTY. The generated scene shipped
#     `Array[ExtResource(...)]([])` for both, which makes roll_combat_action
#     return at enemy.gd:3053 and never errors. check_frame.gd does not look at
#     these. Contents are asserted, not just emptiness, so the defect cannot
#     come back as a different wrong value.
#
#   * SQUAD AMMUNITION IS STILL INFINITE. The frame's design doc was built on
#     refilling magazines, which does not exist. If someone later adds a reserve
#     to ai_weapon.gd, the last test here fails ON PURPOSE and this frame's
#     brief gets reopened.
#
# The geometry is deliberately NOT asserted. Shapes are judged by looking at
# them; build_drayman.gd owns the model and check_frame.gd owns the wiring.
# ─────────────────────────────────────────────

const DRAYMAN := "res://Character/characters/ai/drayman.tscn"
const CUSTOMER := "res://Character/characters/ai/soldier_chassis.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_drayman.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const _KillKinds := preload("res://Campaign/kill_kinds.gd")
const M4 := "res://Character/weapon/ai-wep_m4.tscn"

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_no_gun_ever_fits()
	await _test_the_scene_is_wired()
	await _test_it_never_enters_a_firing_state()
	await _test_restore_puts_a_charge_back()
	await _test_it_restocks_a_squadmate_in_reach()
	await _test_it_refuses_the_full_and_runs_out()
	await _test_squad_ammunition_is_still_infinite()

	print("")
	if _fails == 0:
		print("ALL DRAYMAN CHECKS PASS")
	else:
		print("DRAYMAN FAILURES: %d" % _fails)
	# EXIT CODE, NOT JUST A PRINTED COUNT. test.sh:120 keys the whole run on
	# PIPESTATUS alone, so a suite that prints FAILURES and quits 0 is reported
	# inside ALL SUITES PASS. test_ledger.gd and test_livery.gd get this right
	# and test_signal.gd and test_bulwark.gd do not; this is the right half.
	quit(1 if _fails > 0 else 0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _spawn(path: String, at: Vector3 = Vector3.ZERO) -> Node:
	var body: Node = load(path).instantiate()
	root.add_child(body)
	(body as Node3D).global_position = at
	# The job is driven by hand below. _physics_process would also run Rover's
	# steering against a world with no navmesh in it.
	body.set_physics_process(false)
	body.set_process(false)
	return body


## A slot with `n` of something, spent down to `left`. equipment_scene is left
## null on purpose: nothing in the restock path instantiates it, and a test that
## needed a real grenade scene to assert a counter would be testing the grenade.
func _slot(n: int, left: int, label: String = "SMOKE") -> AIEquipmentSlot:
	var s := AIEquipmentSlot.new()
	s.quantity = n
	s.label = label
	s.initialize()
	for i in (n - left):
		s.consume()
	return s


# ─────────────────────────────────────────────
func _test_the_chassis_is_registered() -> void:
	var def = load(CHASSIS)
	_ok("the chassis definition loads", def != null)
	if def == null:
		return
	_ok("...and names itself drayman", def.id == &"drayman", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	_ok("...and is purchasable, or recruit() refuses it", bool(def.purchasable))
	# ONE WEAPON SLOT, PERMANENTLY EMPTY. starting_weapon_id is written straight
	# into weapon_ids[0] by recruit() without consulting takes(), and
	# _issue_weapon arms a body on a non-empty id regardless of weapon_slots —
	# so empty is the only value that keeps a gun off a supply truck.
	_ok("...one weapon slot, for the boom", int(def.weapon_slots) == 1,
			"%d" % int(def.weapon_slots))
	_ok("...and NOTHING in it to start with", String(def.starting_weapon_id) == "",
			str(def.starting_weapon_id))
	_ok("...and no coax", String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	_ok("...the boom is the built-in", String(def.built_in) == "ARM", String(def.built_in))
	# base_speed IS A MULTIPLIER, not a speed. The scene already carries
	# move_speed = 6.65, which is the Rover's 7.0 x 0.95; a 0.95 here would
	# multiply it AGAIN at squad_spawner.gd:349 and give 6.32. The scene owns
	# the speed, so this must be 1.0.
	_ok("...base_speed is 1.0, so the scene's move_speed is not multiplied twice",
			absf(float(def.base_speed) - 1.0) < 0.001, "%.2f" % float(def.base_speed))
	# A SUPPORT VEHICLE TRAVELS WITH WHAT IT SUPPORTS. `vehicle` is which team
	# it joins (campaign_state._is_vehicle) and it drives Squad.vehicles_only
	# and armor_follow_distance. The Reclaimer — the same frame with a welder
	# instead of crates — sets vehicle = false with drives = true for exactly
	# this reason: its customers are the infantry.
	_ok("...it joins the infantry team, not ARMOR", not bool(def.vehicle))
	_ok("...and it drives, so leg kit is refused", bool(def.drives))
	# MORE EQUIPMENT THAN ANYTHING ELSE IN THE GAME (the previous maximum was
	# two). restore() is slot-for-slot, so these are NOT a mirror of what it can
	# refill — they are the frame's own cargo, and the only way an unarmed truck
	# contributes to a firefight at all.
	_ok("...and it carries more kit than any other frame", int(def.equipment_slots) >= 4,
			"%d" % int(def.equipment_slots))

	# IN THE CATALOGUE, which is what actually puts it in the shop — and what
	# stops SoldierRecord.recompute_stats falling back to class defaults and
	# CampaignState.supply_of returning 1.
	var cat = load(CATALOGUE)
	var ids: Array = []
	if cat != null:
		for c in cat.chassis:
			if c != null:
				ids.append(String(c.id))
	_ok("...and the catalogue carries it", ids.has("drayman"), str(ids))
	# IN KILL_KINDS, or the debrief prints a raw id, the roster glyph is blank
	# and bake_icons.gd never bakes it a picture.
	_ok("...and KillKinds knows the frame", _KillKinds.FRAMES.has(&"drayman"))
	_ok("...and can resolve it to a definition", _KillKinds.frame_of(&"drayman") != null)


# ─────────────────────────────────────────────
func _test_no_gun_ever_fits() -> void:
	var def = load(CHASSIS)
	var cat = load(CATALOGUE)
	if def == null or cat == null:
		_ok("the chassis and catalogue both load", false)
		return
	# ACROSS THE WHOLE CATALOGUE, not against the five vehicle guns that exist
	# today. turret = false means the slot is NOT whitelist-gated, so the only
	# thing refusing a gun is each gun's own chassis_whitelist — and a future
	# vehicle weapon authored with an empty whitelist would fit this frame in
	# silence. This is the assertion that locks that choice.
	var fitted: Array[String] = []
	for item in cat.items:
		if item == null or int(item.kind) != int(ItemDefinition.Kind.WEAPON):
			continue
		if def.takes(item):
			fitted.append(String(item.id))
	_ok("no weapon in the catalogue fits the Drayman", fitted.is_empty(),
			"fits: " + ", ".join(fitted))


# ─────────────────────────────────────────────
func _test_the_scene_is_wired() -> void:
	var b := _spawn(DRAYMAN)
	await process_frame
	# Both groups, because add_to_group's second argument defaults to false and
	# a scene saved without it is invisible to AIManager, to EMP and to every
	# hostile sweep, with nothing anywhere complaining.
	_ok("the frame is in the \"enemies\" group", b.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it", b.is_in_group(AI.SIGNAL_GROUP))
	_ok("...and it runs drayman.gd", b.has_method("loads_left"),
			b.get_script().resource_path if b.get_script() != null else "no script")

	# THE MOUNT IS AUTHORED, NOT BUILT AT RUNTIME. reclaimer.gd is the one frame
	# in the game that builds its own mount inside equip_weapon_scene, and
	# build_drayman.gd decided in writing not to inherit that contract. Walked
	# up the tree rather than compared by name, so renaming cannot satisfy it.
	var mount = b.get("weapon_mount")
	_ok("the boom carries an authored weapon mount", mount != null)
	var wrist := b.find_child("Wrist", true, false)
	_ok("...and the frame has a wrist", wrist != null)
	if mount != null and wrist != null:
		var n: Node = mount
		var under := false
		while n != null:
			if n == wrist:
				under = true
				break
			n = n.get_parent()
		_ok("...and the mount hangs off the wrist", under,
				"mount is not under %s" % str(wrist.get_path()))
	_ok("...and nothing is fitted to it", b.weapon == null)

	# THE TWO ARRAYS THAT SHIPPED EMPTY AND MISTYPED. Contents AND type: an
	# untyped array assigned to a typed export saves as [] in silence, and an
	# empty AllowedCombatOptions makes roll_combat_action return before it ever
	# reaches perform_action.
	var mv = b.get("AllowedMovementOptions")
	var cb = b.get("AllowedCombatOptions")
	_ok("AllowedMovementOptions is ADVANCE and FALLBACK",
			mv != null and (mv as Array) == [0, 2], str(mv))
	_ok("...and is typed Array[int], not Array[Object]",
			mv != null and (mv as Array).get_typed_builtin() == TYPE_INT,
			"typed builtin %d" % [(mv as Array).get_typed_builtin() if mv != null else -1])
	_ok("AllowedCombatOptions is MOVE and nothing else",
			cb != null and (cb as Array) == [0], str(cb))
	_ok("...and is typed Array[int] too",
			cb != null and (cb as Array).get_typed_builtin() == TYPE_INT,
			"typed builtin %d" % [(cb as Array).get_typed_builtin() if cb != null else -1])

	# IT WALKS AT THE BACK. formation_trail is the whole of why the Mechanic
	# stops being the first thing every fight finds; a truck wants at least as
	# much. Zero is the generated default, which is a supply frame in the front
	# rank.
	_ok("it forms up behind the squad", float(b.formation_trail) >= 6.0,
			"%.1f m" % float(b.formation_trail))
	_ok("...and it is not aggressive", not bool(b.aggressive))
	# Rover already answers both of these; asserted because a 3.3 m truck being
	# sent to a rifleman's cover point is invisible until you watch it happen.
	_ok("...and it does not take cover", not b.takes_cover())

	# THE EYE IS NOT FACTION KIT, and an empty livery `pieces` is worse than no
	# livery: FactionLivery falls back to walking its whole parent and paints
	# every mesh on the frame, the eye included.
	var liv = b.get_node_or_null("FactionLivery")
	var eye = b.find_child("Eye", true, false)
	_ok("the frame has a livery", liv != null)
	_ok("...and an eye", eye != null)
	if liv != null and eye != null:
		_ok("...the livery names its pieces explicitly", liv.pieces.size() > 0,
				"%d — empty means it walks the whole frame instead" % liv.pieces.size())
		_ok("...and the eye is not one of them", not liv.pieces.has(eye))
		liv.apply(Enums.Factions.ENEMY)
		await process_frame
		var m = eye.material_override
		_ok("...so a repaint leaves the eye alone", m != null and m is StandardMaterial3D,
				"eye wears %s" % ("null" if m == null else m.get_class()))
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_never_enters_a_firing_state() -> void:
	# handle_weapon_logic is `pass` and _weapon_on_target() is false. Driven
	# with a live hostile sitting in reach and a weapon_target set, which is
	# every condition Enemy's IDLE -> AIM -> FIRE machine needs.
	var b := _spawn(DRAYMAN, Vector3(200, 0, 200))
	var foe := _spawn(CUSTOMER, Vector3(205, 0, 200))
	await process_frame
	foe.faction = Enums.Factions.ENEMY
	b.ai_state = b.AIState.COMBAT
	b.combat_target = foe
	b.weapon_target = (foe as Node3D).global_position
	var left_idle := false
	for i in 120:
		b.handle_weapon_logic(1.0 / 60.0)
		if b.weapon_state != b.WeaponState.IDLE:
			left_idle = true
	_ok("the frame never leaves weapon IDLE", not left_idle, str(b.weapon_state))
	_ok("...and never reads as on target", not b._weapon_on_target())
	# The combat dice must still be ALIVE (the arrays are non-empty) and still
	# refuse to drive a truck at a rifleman while it has work in hand.
	b._customer = foe
	var before: Vector3 = b.movement_target
	b.perform_action(b.CombatOptions.MOVE)
	_ok("...and MOVE is refused while it has a customer",
			b.movement_target == before, str(b.movement_target))
	b._customer = null
	b.free()
	foe.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_restore_puts_a_charge_back() -> void:
	# THE ONE PIECE OF SHARED API THIS FRAME NEEDED. Before it, AIEquipmentSlot
	# had initialize(), has_uses(), consume() and remaining() and no way back at
	# all: the only code in the project that refilled one was a test reaching
	# into _quantity_remaining.
	var s := _slot(3, 0)
	_ok("a spent slot has nothing left", s.remaining() == 0 and not s.has_uses())
	s.restore()
	_ok("...restore() gives one back", s.remaining() == 1 and s.has_uses(),
			"%d" % s.remaining())
	s.restore(5)
	# CLAMPED TO quantity. A slot holding more than it was built with reads as a
	# negative spend everywhere that draws remaining against quantity.
	_ok("...and it never exceeds the quantity it was built with",
			s.remaining() == 3, "%d of %d" % [s.remaining(), s.quantity])
	s.restore(-4)
	_ok("...and a negative restore takes nothing away", s.remaining() == 3,
			"%d" % s.remaining())
	# SLOT-FOR-SLOT, NOT BY ITEM ID — which is what decides whether a Drayman
	# must carry smoke to refill smoke. item_id is EMPTY on every slot authored
	# by hand in a .tres (the enemy garrisons get theirs that way), so an
	# id-matched restore would silently refuse exactly those.
	var anon := _slot(2, 0)
	anon.item_id = &""
	anon.restore()
	_ok("...and a slot with no item_id is restored just the same",
			anon.remaining() == 1, "%d" % anon.remaining())
	# Two robots must not share a count. SoldierRecord.apply_to duplicates the
	# resources for this reason; restore() must not have reintroduced a shared
	# path.
	var a := _slot(2, 0)
	var dup := a.duplicate() as AIEquipmentSlot
	dup.initialize()
	dup.restore()
	_ok("...and restoring a duplicate does not refill the original",
			a.remaining() == 0, "%d" % a.remaining())


# ─────────────────────────────────────────────
func _test_it_restocks_a_squadmate_in_reach() -> void:
	var b := _spawn(DRAYMAN, Vector3(400, 0, 400))
	var mate := _spawn(CUSTOMER, Vector3(402, 0, 400))
	await process_frame
	await physics_frame
	mate.faction = b.faction   # same side, or _driest_slot refuses them
	var slots: Array[AIEquipmentSlot] = [_slot(2, 0)]
	mate.equipment_slots = slots

	# Picked by polling: nothing in the game ever REQUESTS resupply.
	# AIEquipment.EquipmentContext has no "I am low" field.
	b._choose_customer()
	_ok("it picks the squadmate that has spent its kit", b._customer == mate,
			"picked %s" % ("nobody" if b._customer == null else str(b._customer.name)))
	_ok("...and the slot it means", b._slot_index == 0, "%d" % b._slot_index)

	# Channelled, not instant: hand_over_seconds standing still beside them.
	var before: int = b.loads_left()
	for i in 10:
		b._hand_over(0.05, false)
	_ok("...and a charge does not arrive instantly", slots[0].remaining() == 0,
			"%d after 0.5 s" % slots[0].remaining())
	for i in 200:
		b._hand_over(0.05, false)
	_ok("...but it does arrive", slots[0].remaining() >= 1, "%d" % slots[0].remaining())
	_ok("...and one load came off the bed", b.loads_left() == before - 1,
			"%d, was %d" % [b.loads_left(), before])
	_ok("...and the frame counted it", int(b.restocked) >= 1, "%d" % int(b.restocked))

	# OUT OF REACH IT DOES NOT. Same robot, moved past hand_reach: the hand-over
	# must not complete from across the map, which is the whole reason the frame
	# has to drive anywhere.
	slots[0] = _slot(2, 0)
	mate.equipment_slots = slots
	(mate as Node3D).global_position = Vector3(440, 0, 400)
	await physics_frame
	b._set_customer(mate, 0)
	for i in 200:
		b._hand_over(0.05, false)
	_ok("...and a squadmate out of reach gets nothing", slots[0].remaining() == 0,
			"%d" % slots[0].remaining())
	b.free()
	mate.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_refuses_the_full_and_runs_out() -> void:
	var b := _spawn(DRAYMAN, Vector3(600, 0, 600))
	var mate := _spawn(CUSTOMER, Vector3(602, 0, 600))
	await process_frame
	await physics_frame
	mate.faction = b.faction
	# NOBODY IS SHORT. A load spent on a full slot is a load wasted, and the
	# frame carries a countable number of them.
	var full: Array[AIEquipmentSlot] = [_slot(2, 2)]
	mate.equipment_slots = full
	b._choose_customer()
	_ok("it refuses a squadmate who is already full", b._customer == null,
			"picked %s" % ("nobody" if b._customer == null else str(b._customer.name)))
	_ok("...and spends nothing on them", b.loads_left() == int(b.loads),
			"%d of %d" % [b.loads_left(), int(b.loads)])

	# CAPACITY IS FINITE, and it is finite because an infinite resupply frame is
	# not a decision — you would simply always bring one.
	var spent: Array[AIEquipmentSlot] = [_slot(40, 0)]
	mate.equipment_slots = spent
	var guard := 0
	while b.loads_left() > 0 and guard < 400:
		guard += 1
		b._choose_customer()
		for i in 200:
			b._hand_over(0.05, false)
	_ok("the bed empties after `loads` hand-overs", b.loads_left() == 0,
			"%d left after %d trips" % [b.loads_left(), guard])
	_ok("...having handed over exactly that many", int(b.restocked) == int(b.loads),
			"%d for %d loads" % [int(b.restocked), int(b.loads)])
	# AND THE REFUSAL IS OBSERVABLE. A Drayman that has silently stopped working
	# is the most expensive bug shape in this project, so being empty is both a
	# readable number and a warning (pushed once, not once per think tick).
	b._choose_customer()
	_ok("...and an empty Drayman takes nobody on", b._customer == null)
	_ok("...and said so", bool(b._warned_empty))
	b.free()
	mate.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_squad_ammunition_is_still_infinite() -> void:
	# THE DEAD PREMISE, AS AN ASSERTION. docs/frames/DRAYMAN.md built this whole
	# frame on refilling squadmates' magazines. AIWeapon._finish_reload() ends
	# with magazine_current = magazine_size — there is no reserve, no pool and
	# no subtraction anywhere in ai_weapon.gd, and AmmoPool/AmmoStock are
	# reached only from player code. So an ammunition Drayman would have had no
	# observable effect and check.sh would have passed on it.
	#
	# IF THIS TEST EVER FAILS, somebody has given AIWeapon a reserve — and this
	# frame's brief should be reopened on purpose, because the gap it was
	# written for would finally exist.
	var w: Node = load(M4).instantiate()
	root.add_child(w)
	await process_frame
	var size: int = int(w.magazine_size)
	w.magazine_current = 0
	w._finish_reload()
	_ok("an AI reload is a free refill, with no Drayman anywhere near it",
			int(w.magazine_current) == size, "%d of %d" % [int(w.magazine_current), size])
	_ok("...and the weapon holds no reserve to feed",
			not ("ammo_reserve" in w) and not ("reserve" in w))
	w.free()
	await process_frame
