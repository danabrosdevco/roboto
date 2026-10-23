extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# A LINE'S SPEC REACHES EVERY ROBOT ON IT, AND NOTHING OFF IT.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_line_specs.gd
#
# The gate on step 2 of docs/briefs/MARK_SYSTEM_SPEC.md.
#
# WHAT THIS IS REALLY GUARDING. apply_line_spec is a BULK WRITE over the
# roster, which is the cheap way to build this (spec §1) and also the way that
# can quietly damage robots it was never meant to touch. A loop with the wrong
# condition rewrites the whole squad; one with the right condition and the
# wrong fields leaves half a loadout behind. Neither errors, and both look
# like the upgrade simply not working.
#
# So every check here comes in a pair: the thing that should have changed, and
# the thing beside it that should not have.
#
# IT WRITES NO SAVE — the state is built in memory and never asked to persist.
# ─────────────────────────────────────────────

const _Pricing := preload("res://Campaign/pricing.gd")
const CAT := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat = load(CAT)
	if cat == null:
		_check("the catalogue loads", false, CAT)
		_done()
		return

	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(100000)
	# Lines must be open before anything can be recruited. Gating has its own
	# tests; this one is about what a spec does once a line is running.
	for frame in cat.chassis:
		if frame != null and frame.purchasable:
			state.unlock_chassis(frame)

	var rover: ChassisDefinition = cat.chassis_def(&"rover")
	var walker: ChassisDefinition = cat.chassis_def(&"walker")
	if rover == null or walker == null:
		_check("the rover and walker lines exist", false)
		_done()
		return

	# ── A FLEET, AND A CONTROL GROUP ──────────
	var rovers: Array = []
	for i in 3:
		rovers.append(state.recruit(rover))
	var walkers: Array = []
	for i in 2:
		walkers.append(state.recruit(walker))
	_check("(setup) three rovers and two walkers", rovers.size() == 3 and walkers.size() == 2
		and not rovers.has(null) and not walkers.has(null))
	if rovers.has(null) or walkers.has(null):
		_done()
		return

	# ── MK 0 IS WHAT THE FRAME SAYS ───────────
	# Including the rule recruit() is explicit about: a second mount ships
	# EMPTY. A Walker comes with its autocannon and no coax, and Mk 0 has to
	# agree or every new Walker starts holding a gun nobody gave it.
	_check("a new rover carries the frame's starting weapon",
		rovers[0].weapon_ids[0] == rover.starting_weapon_id,
		str(rovers[0].weapon_ids))
	_check("...and a walker's second mount is still empty",
		walkers[0].weapon_ids.size() >= 2 and walkers[0].weapon_ids[1] == &"",
		str(walkers[0].weapon_ids))

	# ── ADOPTING A MARK ───────────────────────
	var before_walker: Array = Array(walkers[0].weapon_ids).duplicate()
	var rover_hp_before: int = int(rovers[0].max_health)
	state.line_marks[&"rover"] = 1
	var touched := state.apply_line_spec(&"rover")
	var mk1 = rover.mark_spec(1)

	_check("adopting Mk 1 rewrites every rover", touched == 3, "%d" % touched)
	var all_armed := true
	for r in rovers:
		if r.weapon_ids[0] != mk1.weapon_ids[0]:
			all_armed = false
	_check("...all three of them, not just the first", all_armed,
		str(rovers.map(func(r): return String(r.weapon_ids[0]))))
	_check("...and the stat bonus reached them",
		int(rovers[0].max_health) == rover_hp_before + mk1.health_bonus,
		"%d -> %d, mark gives %+d" % [rover_hp_before, int(rovers[0].max_health), mk1.health_bonus])

	# THE CONTROL GROUP. The walkers were never on this line.
	_check("...and the walkers were not touched",
		Array(walkers[0].weapon_ids) == before_walker, str(walkers[0].weapon_ids))

	# ── THE COAX ARRIVES AS A LINE DECISION ───
	# The thing recruit() refuses to hand a single robot, bought once for the
	# whole line instead. This is the move the system makes, in one check.
	state.line_marks[&"walker"] = 1
	state.apply_line_spec(&"walker")
	var w1 = walker.mark_spec(1)
	_check("a walker line at Mk 1 fills the second mount",
		walkers[0].weapon_ids.size() >= 2 and walkers[0].weapon_ids[1] == w1.weapon_ids[1],
		str(walkers[0].weapon_ids))
	_check("...on both walkers", walkers[1].weapon_ids[1] == w1.weapon_ids[1])

	# ── A NEW UNIT ARRIVES AT SPEC ────────────
	var late := state.recruit(rover)
	_check("a rover built after the upgrade arrives at Mk 1",
		late != null and late.weapon_ids[0] == mk1.weapon_ids[0],
		str(late.weapon_ids) if late != null else "null")

	# ── THE MODULE IS LINE-WIDE TOO ───────────
	state.line_modules[&"rover"] = &"armor_plating"
	state.apply_line_spec(&"rover")
	var plated := true
	for r in rovers:
		if not r.module_ids.has(&"armor_plating"):
			plated = false
	_check("a line module reaches every rover", plated,
		str(rovers[0].module_ids))
	_check("...and not the walkers",
		not walkers[0].module_ids.has(&"armor_plating"), str(walkers[0].module_ids))

	# ONE MODULE, NOT A COLLECTION. Adopting a second replaces the first —
	# a line has one keystone, and a bulk write that appended would stack them.
	state.line_modules[&"rover"] = &"optics"
	state.apply_line_spec(&"rover")
	var only_one: bool = rovers[0].module_ids.count(&"optics") == 1 \
		and not rovers[0].module_ids.has(&"armor_plating")
	_check("...and a second module replaces the first rather than stacking",
		only_one, str(rovers[0].module_ids))

	# ── BENCHED ROBOTS ARE STILL ON THE LINE ──
	# A revision is the factory changing what it builds. Skipping the bench
	# would make a robot's spec depend on where it was standing when you paid.
	rovers[2].benched = true
	state.line_marks[&"rover"] = 2
	state.apply_line_spec(&"rover")
	var mk2 = rover.mark_spec(2)
	_check("a benched rover is revised with the rest",
		rovers[2].weapon_ids[0] == mk2.weapon_ids[0], str(rovers[2].weapon_ids))

	# ── CLAMPING ──────────────────────────────
	# A save naming a mark a retuned chassis no longer authors must not ask
	# for it. mark_of clamps rather than letting mark_spec return null.
	state.line_marks[&"rover"] = 99
	_check("a mark beyond what the frame authors is clamped",
		state.mark_of(&"rover") == rover.top_mark(), "%d" % state.mark_of(&"rover"))
	_check("...and applying it still works",
		state.apply_line_spec(&"rover") == 4, "rewrote %d" % state.apply_line_spec(&"rover"))

	# ── IT SURVIVES A SAVE ────────────────────
	var round_trip := CampaignState.from_dict(state.to_dict())
	_check("line marks survive a save and reload",
		int(round_trip.line_marks.get(&"rover", 0)) == 99
			or int(round_trip.line_marks.get("rover", 0)) == 99,
		str(round_trip.line_marks))
	_check("...and so does the module",
		StringName(round_trip.line_modules.get(&"rover", round_trip.line_modules.get("rover", &"")))
			== &"optics", str(round_trip.line_modules))

	await _adoption(cat)
	_done()


## ── BUYING A MARK AND A MODULE ──────────────────────────────────────────────
##
## A fresh state, because the one above has been poked at directly — line_marks
## written by hand — and the whole point here is that the PAID path does the
## same work and leaves the money right.
func _adoption(cat) -> void:
	print("")
	var s := CampaignState.new()
	s.armoury = Armoury.new()
	s.catalogue = cat
	s.award(100000)
	var rover: ChassisDefinition = cat.chassis_def(&"rover")
	var walker: ChassisDefinition = cat.chassis_def(&"walker")

	# ── A SHUT LINE CANNOT BE ADVANCED ────────
	# Before anything else, because a gate that only the UI enforces is not a
	# gate: anything else calling adopt_mark would walk straight past it.
	_check("a shut line refuses a mark", not s.adopt_mark(rover))
	_check("...and takes no money for refusing", s.available() == 100000,
		"%d" % s.available())

	s.unlock_chassis(rover)
	s.unlock_chassis(walker)
	for item in cat.items_of_kind(ItemDefinition.Kind.MODULE):
		s.unlock_item(item)
	var after_unlocks := s.available()
	var r1 := s.recruit(rover)
	var r2 := s.recruit(rover)
	_check("(setup) two rovers on an open line", r1 != null and r2 != null)
	if r1 == null or r2 == null:
		return

	# ── PAYING FOR MK 1 ───────────────────────
	var purse := s.available()
	var price := _Pricing.mark_buy(rover, 1)
	_check("adopting Mk 1 succeeds", s.adopt_mark(rover))
	_check("...and costs exactly what the table says",
		s.available() == purse - price, "%d -> %d, price %d" % [purse, s.available(), price])
	_check("...and the line now builds Mk 1", s.mark_of(&"rover") == 1)
	_check("...and both rovers were revised",
		r1.weapon_ids[0] == rover.mark_spec(1).weapon_ids[0]
		and r2.weapon_ids[0] == rover.mark_spec(1).weapon_ids[0])
	_invariant(s, "after Mk 1")

	# ── AND IT ONLY HAPPENS ONCE PER TIER ─────
	# A second Mk 1 would be a second allocation under the same key and a
	# second deduction for a thing the line already has.
	var held := s.available()
	s.adopt_mark(rover)
	_check("advancing again moves to Mk 2, not Mk 1 twice", s.mark_of(&"rover") == 2)
	_check("...at Mk 2's price", s.available() == held - _Pricing.mark_buy(rover, 2),
		"%d -> %d" % [held, s.available()])
	_check("there is nothing above what the frame authors",
		not s.adopt_mark(rover) and s.mark_of(&"rover") == rover.top_mark())
	_invariant(s, "at the top of the rail")

	# ── THE MODULE ────────────────────────────
	var plating: ItemDefinition = cat.item(&"armor_plating")
	var servos: ItemDefinition = cat.item(&"overclock_servos")
	var before_mod := s.available()
	_check("a rover refuses Overclock Servos", not s.adopt_module(rover, servos),
		"a frame that drives has nothing to overclock")
	_check("...and is not charged for the refusal", s.available() == before_mod)
	_check("a rover adopts Armour Plating", s.adopt_module(rover, plating))
	_check("...at the module price",
		s.available() == before_mod - _Pricing.module_buy(rover),
		"%d -> %d" % [before_mod, s.available()])
	_check("...and it reached both rovers",
		r1.module_ids.has(&"armor_plating") and r2.module_ids.has(&"armor_plating"))
	_check("...and the walker line did not get one",
		s.module_of(&"walker") == &"", str(s.module_of(&"walker")))

	# IRREVERSIBLE. The one decision the system asks for stays made.
	var settled := s.available()
	_check("the module cannot be swapped", not s.adopt_module(rover, cat.item(&"optics")))
	_check("...and trying costs nothing", s.available() == settled)
	_invariant(s, "after the module")

	# ── A MODULE STILL HAS TO BE RESEARCHED ───
	var fresh := CampaignState.new()
	fresh.armoury = Armoury.new()
	fresh.catalogue = cat
	fresh.award(100000)
	fresh.unlock_chassis(rover)
	_check("an unresearched module cannot be adopted",
		not fresh.adopt_module(rover, plating),
		"opening a line buys the frame, not every module that fits it")

	# ── THE MONEY ADDS UP ACROSS A WHOLE RUN ──
	# test_ledger's own invariant, run here too because this is the first
	# system to write allocation keys it does not own.
	_check("every line purchase is in the ledger",
		s.allocations.has(CampaignState.mark_key(&"rover", 1))
		and s.allocations.has(CampaignState.mark_key(&"rover", 2))
		and s.allocations.has(CampaignState.module_key(&"rover")),
		str(s.allocations.keys()))
	_check("...and spending equals what was earned minus them",
		s.available() == s.earned - _spent(s), "available %d" % s.available())
	_check("(context) unlocks came out of the same purse", after_unlocks < 100000)


func _spent(s: CampaignState) -> int:
	var total := 0
	for cost in s.allocations.values():
		total += int(cost)
	return total


func _invariant(s: CampaignState, label: String) -> void:
	_check("%s: available == earned - allocations" % label,
		s.available() == s.earned - _spent(s),
		"available=%d earned=%d allocated=%d" % [s.available(), s.earned, _spent(s)])


func _done() -> void:
	print("")
	print("PASS" if _fails == 0 else "FAIL  %d check(s) failed" % _fails)
	quit(0 if _fails == 0 else 1)
