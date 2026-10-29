extends SceneTree
# BUCKET: kit

# ─────────────────────────────────────────────
# EVERY AMMO STOCK ACTUALLY CARRIES ITS NUMBERS.
#
# A .tres applies its properties in FILE ORDER. Put `script = ...` after the
# values and Godot sets ammo_type/amount/capacity on a bare Resource, which has
# no such properties, and silently drops all three — the stock loads with an
# empty type and AmmoPool.reset() skips it, because skipping empty types is
# correct. Four stocks shipped that way and the symptom was "no ammo at all".
#
# NOTHING ELSE CATCHES THIS. check.sh passes: the file is valid, the load
# succeeds, the resource exists. Only reading the values back finds it.
#
# The second half boots the real player and asks the pool, because a stock that
# loads fine but was never added to test_character.tscn's starting_ammo is the
# same symptom from a different cause.
# ─────────────────────────────────────────────

const DIR := "res://Character/equipment/ammo"

var _fails := 0


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


## ammo_type -> how many fitted items draw on it, counting EQUIPMENT slots only.
##
## THE SLOT IS WHAT EXCLUDES GUNS, which is the same rule
## EquipmentLoadout._scale_thrown_capacity runs on — but this reads the live
## nodes rather than asking the loadout, so it is an independent observation of
## what is in the player's hands and not a restatement of the pool's own books.
##
## `ammo_type` is NOT on PlayerEquipment — it is declared on the subclasses — so
## this has to ask `in` rather than cast. And ItemDefinition.ammo_type is a
## decoy here: item_frag.tres leaves it &"" while item_smoke.tres sets it, so
## the record cannot answer this question and the scene has to.
func _fitted_thrown(player: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [player]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is PlayerEquipment) or n.is_queued_for_deletion():
			continue
		if n.slot != PlayerEquipment.Slot.EQUIPMENT:
			continue
		if not ("ammo_type" in n):
			continue
		var t: StringName = n.ammo_type
		if t == &"":
			continue
		out[t] = int(out.get(t, 0)) + 1
	return out


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var types: Array = []
	## Types that only exist while the player carries the item that uses them.
	var carried: Dictionary = {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		_check("the ammo folder exists", false, DIR)
		quit(1)
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var stock = load("%s/%s" % [DIR, f])
		var t = stock.get("ammo_type") if stock != null else null
		var a = stock.get("amount") if stock != null else null
		var cap = stock.get("capacity") if stock != null else null
		var ok: bool = t != null and String(t) != "" and int(a) > 0 and int(cap) > 0
		_check("%s carries its values" % f, ok,
			"type=%s amount=%s — properties set before `script =` are discarded" % [str(t), str(a)])
		if ok:
			types.append(t)
			if bool(stock.get("requires_carrier")):
				carried[t] = true

	# ── AND THE PLAYER IS ACTUALLY HOLDING THEM ──
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node = _find(root, "Player")
	var pool: Node = player.get_node_or_null("AmmoPool") if player != null else null
	_check("the player has an AmmoPool", pool != null)
	if pool == null:
		_report()
		return
	# A GUN CALIBRE IS A RESERVE; A THROWN ITEM IS NOT.
	#
	# A rifle calibre is there whether or not the rifle is in your hands. A frag,
	# an EMP, a mine, the drone pack — those only exist because you are carrying
	# the thing that throws them, and the pool used to hand out a full load of all
	# of them to a player carrying none. Both halves are asserted: the reserve
	# that should be there, and the pouch that should be empty.
	#
	# WHICH POUCHES ARE EMPTY IS NO LONGER A CONSTANT, and that is what the
	# check below reads off the loadout rather than assuming.
	#
	# Until 2026-10-23 this asserted a FLAT ZERO for every `requires_carrier`
	# type — a new campaign fitted nothing, so nothing thrown had a carrier.
	# `Campaign._carry_issued()` (added that day, commit aa2eaa51) changed the
	# rule: the Ancient Rifle and the Frag are ISSUED — cost 0 in
	# software_tree.gd's CARRY, always loaded, never in the ledger, cannot be
	# unloaded — and a new campaign now starts with both IN HAND, so mission one
	# does not open with an empty grenade slot. `grenade` therefore has one
	# carrier from the first frame and four in the pool is CORRECT. The flat
	# zero was red on correct behaviour for a day (K21).
	#
	# So the rule asserted now is the one that was always meant: the pool agrees
	# with what is in your hands. Zero carriers ⇒ zero reserve; a carrier fitted
	# ⇒ a reserve. That still catches the original bug (a pouch of something you
	# cannot throw) AND its inverse, which also shipped once — see
	# AmmoPool._carriers_of, where a type scaled to zero read back as one and
	# fitting a frag then gave you no frags.
	#
	# NOTHING WAS LOST BY ADAPTING THIS. The unfitted case is still pinned, in
	# the place that can actually set up for it: test_equipment's
	# _test_carrier_required_ammo applies a record with an EMPTY equipment_ids
	# and asserts 0 grenades, 0 capacity, then fits one, then two, then none
	# again. Here the campaign decides the loadout, so "nothing fitted" is not a
	# state this suite can arrange. And test_induction (bucket campaign) asserts
	# "the issued Frag is in your hands too" off the record — so the rule this
	# check used to contradict is itself under test on both sides.
	var fitted := _fitted_thrown(player)
	# PIN THE ISSUED FRAG ITSELF. Without this, a change that stopped issuing it
	# would make every branch below take the zero-carrier path and the suite
	# would go green having quietly stopped testing the interesting case.
	_check("the issued Frag is in hand, so grenade has a carrier",
		int(fitted.get(&"grenade", 0)) > 0,
		"Campaign._carry_issued puts frag in an equipment slot; fitted=%s" % str(fitted))
	for t in types:
		if carried.has(t):
			var carriers: int = int(fitted.get(t, 0))
			if carriers > 0:
				_check("...and starts with %s, whose item IS fitted" % t,
					pool.get_count(t) > 0,
					"%d in the pool with %d carrier(s) fitted" % [pool.get_count(t), carriers])
			else:
				_check("...and does NOT start with %s, which needs its item carried" % t,
					pool.get_count(t) == 0,
					"%d in the pool with nothing fitted" % pool.get_count(t))
		else:
			_check("...and starts with %s" % t, pool.get_count(t) > 0,
				"not in test_character.tscn's starting_ammo")
	_report()


func _report() -> void:
	print("")
	print("AMMO FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL AMMO CHECKS PASS")
	quit(1 if _fails > 0 else 0)
