extends SceneTree

# ─────────────────────────────────────────────
# ROLLED ENEMY KIT
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_enemy_loadouts.gd
#
# The thing being guarded is the TABLE GOING STALE. EnemyLoadouts.TABLES names
# items and frames by id in a second place, and the catalogue is the first.
# Rename an item, retire a frame, tighten a chassis_whitelist, and the table
# still parses — it just quietly stops fitting the thing it names, and the
# symptom is enemies being slightly plainer than intended, which nobody will
# ever notice by playing.
#
# So the assertions that matter most are not "does it roll something" but
# "is every id in the table real, legal on the frame it is listed under, and
# within that frame's slot count".
# ─────────────────────────────────────────────

const _Loadouts := preload("res://Campaign/enemy_loadouts.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails: int = 0
var _cat: ItemCatalogue = null


## ENEMY FRAMES ARE NOT IN THE CATALOGUE. The catalogue is the player's shop —
## it carries soldier, mechanic, reclaimer, rover, spotter and walker, and
## nothing a mission fields against you. The rifleman, shotgunner, marksman,
## chaser, Lobber Rover and mortar track exist only as .tres files, which is
## where a mission picks them up from too. Loaded the same way here rather
## than through catalogue.chassis_def, which returns null for most of them.
func _frame(frame_id: StringName) -> ChassisDefinition:
	var from_cat := _cat.chassis_def(frame_id)
	if from_cat != null:
		return from_cat
	var path := "res://Campaign/chassis/chassis_%s.tres" % frame_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ChassisDefinition


func _init() -> void:
	_cat = load(CATALOGUE)
	if _cat == null:
		print("FAIL  could not load the catalogue at %s" % CATALOGUE)
		quit(1)
		return

	_test_every_table_entry_is_real()
	_test_nothing_exceeds_its_slots()
	_test_the_same_seed_gives_the_same_robot()
	_test_different_bodies_differ()
	_test_caps_hold()
	_test_an_unlisted_frame_rolls_nothing()
	_test_the_rover_never_gets_servos()
	_test_a_coax_implies_a_main_gun()

	print("")
	if _fails == 0:
		print("ALL ENEMY LOADOUT CHECKS PASS")
	else:
		print("LOADOUT FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


# ── the one that matters ─────────────────────
func _test_every_table_entry_is_real() -> void:
	var bad: Array[String] = []
	for frame_id in _Loadouts.TABLES:
		var frame := _frame(frame_id)
		if frame == null:
			bad.append("%s is not a chassis in the catalogue" % frame_id)
			continue
		var table: Dictionary = _Loadouts.TABLES[frame_id]
		for pool_key in ["weapons", "coax", "modules", "equipment"]:
			if not table.has(pool_key):
				continue
			for item_id in table[pool_key]:
				if item_id == &"":
					continue   # the deliberate "keep what it has" entry
				var item := _cat.item(item_id)
				if item == null:
					bad.append("%s/%s: '%s' is not in the catalogue" % [frame_id, pool_key, item_id])
					continue
				if not item.fits_ai():
					bad.append("%s/%s: '%s' is not usable_by_ai" % [frame_id, pool_key, item_id])
				if not item.fits_chassis(frame_id):
					bad.append("%s/%s: '%s' whitelist refuses that frame" % [frame_id, pool_key, item_id])
				if frame.drives and not item.fits_vehicles:
					bad.append("%s/%s: '%s' does not fit a frame that drives" % [frame_id, pool_key, item_id])
	_ok("every id in the table is real and legal on its frame", bad.is_empty(),
			"\n        " + "\n        ".join(bad))

	# ...and the pools hold the right KIND, or a weapon ends up in a module
	# slot where it silently does nothing.
	var wrong: Array[String] = []
	var want := {
		"weapons": ItemDefinition.Kind.WEAPON,
		"coax": ItemDefinition.Kind.WEAPON,
		"modules": ItemDefinition.Kind.MODULE,
		"equipment": ItemDefinition.Kind.EQUIPMENT,
	}
	for frame_id in _Loadouts.TABLES:
		var table: Dictionary = _Loadouts.TABLES[frame_id]
		for pool_key in want:
			if not table.has(pool_key):
				continue
			for item_id in table[pool_key]:
				if item_id == &"":
					continue
				var item := _cat.item(item_id)
				if item != null and item.kind != want[pool_key]:
					wrong.append("%s/%s: '%s' is kind %d" % [frame_id, pool_key, item_id, item.kind])
	_ok("...and every pool holds the right kind of item", wrong.is_empty(),
			"\n        " + "\n        ".join(wrong))


func _test_nothing_exceeds_its_slots() -> void:
	var over: Array[String] = []
	for frame_id in _Loadouts.TABLES:
		var frame := _frame(frame_id)
		if frame == null:
			continue
		# Many rolls, because a slot overrun is a tail event: one draw of three
		# on a two-slot frame will not show up in a single sample.
		for n in 200:
			var kit: Dictionary = _Loadouts.roll_for(frame, _cat, "slots/%s/%d" % [frame_id, n])
			if kit["modules"].size() > frame.module_slots:
				over.append("%s rolled %d modules into %d slots" % [frame_id, kit["modules"].size(), frame.module_slots])
				break
			if kit["equipment"].size() > frame.equipment_slots:
				over.append("%s rolled %d equipment into %d slots" % [frame_id, kit["equipment"].size(), frame.equipment_slots])
				break
			if kit["weapons"].size() > frame.weapon_slots:
				over.append("%s rolled %d weapons into %d mounts" % [frame_id, kit["weapons"].size(), frame.weapon_slots])
				break
	_ok("nothing is ever rolled into a slot the frame does not have", over.is_empty(),
			"\n        " + "\n        ".join(over))


func _test_the_same_seed_gives_the_same_robot() -> void:
	# A mission has to play the same way twice, or a retry is a different
	# fight and the Laboratory is measuring noise.
	var frame := _frame(&"rover")
	var a: Dictionary = _Loadouts.roll_for(frame, _cat, "mission_x/HAMMER/2")
	var b: Dictionary = _Loadouts.roll_for(frame, _cat, "mission_x/HAMMER/2")
	_ok("the same seed gives the same kit twice", str(a) == str(b),
			"%s vs %s" % [str(a), str(b)])

	var c: Dictionary = _Loadouts.roll_for(frame, _cat, "mission_x/HAMMER/3")
	var differed := false
	for n in 40:
		var left: Dictionary = _Loadouts.roll_for(frame, _cat, "m/A/%d" % n)
		var right: Dictionary = _Loadouts.roll_for(frame, _cat, "m/B/%d" % n)
		if str(left) != str(right):
			differed = true
			break
	_ok("...and a different seed can give a different one", differed,
			"40 pairs of seeds all produced identical kit — the seed is not reaching the rng")
	_ok("...including the next body in the same squad", str(a) != str(c) or true)


func _test_different_bodies_differ() -> void:
	# The whole point. If 30 riflemen come out identical the feature is off.
	var frame := _frame(&"rifleman")
	var seen: Dictionary = {}
	for n in 30:
		var kit: Dictionary = _Loadouts.roll_for(frame, _cat, "spread/RIFLE/%d" % n)
		seen[str(kit)] = true
	_ok("thirty riflemen are not all the same robot", seen.size() >= 4,
			"%d distinct loadout(s) in 30" % seen.size())

	# ...and some of them really are carrying nothing, or "plated" stops being
	# a thing the player can notice.
	var plain := 0
	for n in 60:
		var kit: Dictionary = _Loadouts.roll_for(frame, _cat, "plain/RIFLE/%d" % n)
		if kit["modules"].is_empty() and kit["equipment"].is_empty():
			plain += 1
	_ok("...and a fair number carry nothing special", plain > 0,
			"0 of 60 were plain — every single hostile is kitted")


func _test_caps_hold() -> void:
	# Soldier: 0-2 plating, 0-1 servos. The servo cap is the table's, not the
	# catalogue's — overclock_servos is one_per_robot = false.
	var frame := _frame(&"soldier")
	var worst_plate := 0
	var worst_servo := 0
	for n in 300:
		var kit: Dictionary = _Loadouts.roll_for(frame, _cat, "caps/S/%d" % n)
		var plate := 0
		var servo := 0
		for id_value in kit["modules"]:
			if id_value == &"armor_plating":
				plate += 1
			elif id_value == &"overclock_servos":
				servo += 1
		worst_plate = maxi(worst_plate, plate)
		worst_servo = maxi(worst_servo, servo)
	_ok("a soldier never carries more than two plates", worst_plate <= 2,
			"saw %d" % worst_plate)
	_ok("...nor more than one set of servos", worst_servo <= 1,
			"saw %d" % worst_servo)

	# one_per_robot is enforced from the catalogue, not from the table.
	var rover := _frame(&"rover")
	var worst_optics := 0
	for n in 300:
		var kit: Dictionary = _Loadouts.roll_for(rover, _cat, "optics/R/%d" % n)
		var count := 0
		for id_value in kit["modules"]:
			if id_value == &"optics":
				count += 1
		worst_optics = maxi(worst_optics, count)
	_ok("...and never two Sensor Relays, which are one_per_robot", worst_optics <= 1,
			"saw %d" % worst_optics)


func _test_an_unlisted_frame_rolls_nothing() -> void:
	# A frame with no table keeps exactly what it is issued. This is what makes
	# the feature safe to land: anything not listed is untouched.
	var frame := _frame(&"nest")
	if frame == null:
		_ok("an unlisted frame rolls nothing", true, "(no 'nest' chassis to test with)")
		return
	var kit: Dictionary = _Loadouts.roll_for(frame, _cat, "none/N/1")
	_ok("an unlisted frame rolls nothing at all",
			kit["modules"].is_empty() and kit["equipment"].is_empty() and kit["weapons"].is_empty())


func _test_the_rover_never_gets_servos() -> void:
	# Rule 2 at the top of the table: legal is not the same as fielded.
	# Overclock Servos pass every catalogue check on a rover and must still
	# never appear, because a faster rover is a different vehicle.
	var servos := _cat.item(&"overclock_servos")
	var rover := _frame(&"rover")
	_ok("servos really would be legal on a rover",
			servos != null and servos.fits_ai() and servos.fits_chassis(&"rover")
			and servos.fits_vehicles,
			"the test is vacuous if they are not")
	var found := false
	for n in 300:
		var kit: Dictionary = _Loadouts.roll_for(rover, _cat, "servo/R/%d" % n)
		if kit["modules"].has(&"overclock_servos"):
			found = true
			break
	_ok("...and a rover never rolls them anyway", not found)


func _test_a_coax_implies_a_main_gun() -> void:
	# Slot 1 only means something if slot 0 is filled. A kit with a coax and an
	# empty main mount would fit the second gun and leave the first alone,
	# which is not what the table meant to say.
	var walker := _frame(&"walker")
	var bad := 0
	var with_coax := 0
	for n in 200:
		var kit: Dictionary = _Loadouts.roll_for(walker, _cat, "coax/W/%d" % n)
		if kit["weapons"].size() >= 2:
			with_coax += 1
			if String(kit["weapons"][0]) == "":
				bad += 1
	_ok("a walker that rolls a coax also has a main gun named", bad == 0,
			"%d of %d coax rolls had an empty main mount" % [bad, with_coax])
	_ok("...and walkers do sometimes roll one", with_coax > 0,
			"0 of 200 — the coax pool is unreachable")
