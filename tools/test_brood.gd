extends SceneTree

# ─────────────────────────────────────────────
# THE BROODCARRIER
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_brood.gd
#
# WHAT IS WORTH GUARDING HERE is not the model and not the flight — the
# Spotter's suite covers the flight model this frame inherits. It is the four
# things that make it a mobile producer rather than a flying hull, all four of
# which are invisible in a headless run and none of which would error:
#
#   * THE OFFSPRING INHERIT THE CARRIER'S FACTION. Asserted against the LITERAL
#     value, not against `parent.faction`, because the obvious wrong version
#     (hardcoding ENEMY) would pass a parent==child comparison.
#   * THE TWO CAPS. A concurrency cap AND a lifetime cap, and the lifetime cap
#     is the whole difference between this frame and the Nest: without it the
#     fight has no end state the player can produce.
#   * IT DOES NOT PRODUCE BEFORE THE FIGHT STARTS. Without that gate it empties
#     its bay into an empty map before the squad arrives.
#   * THE BAY EMPTIES. Nine pods is the player's only readout of how much is
#     left, and `visible = false` on the wrong node is silent.
#
# Geometry is deliberately NOT asserted. Shapes are judged by looking at them.
# ─────────────────────────────────────────────

const BROOD := "res://Character/characters/ai/brood.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_brood.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const HOPPER := "res://Campaign/chassis/chassis_hopper.tres"
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

var _fails: int = 0


func _init() -> void:
	await _test_hostility()
	await _test_the_chassis_is_registered()
	await _test_it_is_not_in_the_player_catalogue()
	await _test_it_never_fires()
	await _test_it_waits_for_the_fight()
	await _test_the_caps()
	await _test_the_offspring()
	await _test_the_bay_empties()
	await _test_the_ocelli_keep_their_own_colour()

	print("")
	if _fails == 0:
		print("ALL BROODCARRIER CHECKS PASS")
	else:
		print("BROODCARRIER FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


## Something true that nothing can be done about from inside this lane. Printed
## rather than failed, so the suite stays a gate instead of permanent noise.
func _note(label: String, cond: bool, detail: String) -> void:
	print("%s  %s%s" % ["PASS" if cond else "TODO", label, "" if cond else ("  " + detail)])


func _spawn(path: String, at: Vector3 = Vector3.ZERO) -> Node:
	var body: Node = load(path).instantiate()
	root.add_child(body)
	(body as Node3D).global_position = at
	# _ready is deferred until the tree ticks in a --script run, AND
	# Enemy.initialize() awaits an IDLE frame before it sets frame_waited --
	# which every per-tick gate in enemy.gd is behind. So both kinds of frame
	# have to be pumped here or the frame sits inert and the test reads as a
	# behaviour failure.
	for _i in 4:
		await physics_frame
		await process_frame
	return body


# ─────────────────────────────────────────────
# TASK ZERO, BOTH DIRECTIONS. They fail differently: outbound-false makes the
# frame untargetable, inbound-false makes it refuse its own shot through
# ai_weapon._is_friendly -> friendly_in_line.
func _test_hostility() -> void:
	print("── the Swarm is a faction that can be fought ──")
	_ok("hostile to the player, outbound",
		Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.SWARM))
	_ok("hostile to the player, inbound",
		Enums.are_hostile(Enums.Factions.SWARM, Enums.Factions.PLAYER))
	_ok("hostile to the player's squad, both ways",
		Enums.are_hostile(Enums.Factions.ALLIED, Enums.Factions.SWARM)
		and Enums.are_hostile(Enums.Factions.SWARM, Enums.Factions.ALLIED))


func _test_the_chassis_is_registered() -> void:
	print("")
	print("── registered ──")
	var frame := load(CHASSIS) as ChassisDefinition
	_ok("chassis_brood.tres loads as a ChassisDefinition", frame != null)
	if frame == null:
		return
	_ok("id is brood", frame.id == &"brood", str(frame.id))
	_ok("supply 2", frame.supply == 2, str(frame.supply))
	_ok("cost 0", frame.cost == 0, str(frame.cost))
	# MANDATORY, not cosmetic: test_ledger.gd asserts that a catalogue frame no
	# mission unlocks is on sale from minute one.
	_ok("not purchasable", frame.purchasable == false)
	_ok("no weapon slots", frame.weapon_slots == 0, str(frame.weapon_slots))
	# THE §2 TRAP: _issue_weapon is NOT gated on weapon_slots, only on
	# starting_weapon_id != &"". A non-empty id arms a weapon_slots = 0 frame.
	_ok("no starting weapon", frame.starting_weapon_id == &"", str(frame.starting_weapon_id))
	_ok("sensor range 70", is_equal_approx(frame.base_sensor_range, 70.0))
	_ok("scene points at brood.tscn", frame.scene != null and frame.scene.resource_path == BROOD)
	_note("in KillKinds.FRAMES", _KillKinds.FRAMES.has(&"brood"),
		"add &\"brood\": \"%s\" to kill_kinds.gd — the debrief prints a raw id with no icon without it" % CHASSIS)


func _test_it_is_not_in_the_player_catalogue() -> void:
	print("")
	print("── and deliberately NOT buyable ──")
	var cat = load(CATALOGUE)
	_ok("the catalogue loads", cat != null)
	if cat == null:
		return
	var present := false
	for c in cat.chassis:
		if c != null and c.id == &"brood":
			present = true
	_ok("no brood entry in the player catalogue", not present)


func _test_it_never_fires() -> void:
	print("")
	print("── it carries nothing, and the mount stays empty ──")
	var body = await _spawn(BROOD)
	_ok("the weapon mount exists", body.weapon_mount != null)
	# STRONGER AND CHEAPER than driving the weapon machine: an empty mount is
	# the starting_weapon_id trap caught directly.
	_ok("nothing is on the mount",
		body.weapon_mount != null and body.weapon_mount.get_child_count() == 0)
	_ok("no weapon", body.weapon == null)
	_ok("in the enemies group", body.is_in_group("enemies"))
	_ok("in the signal group", body.is_in_group(AI.SIGNAL_GROUP))
	# Inherited from SpotterDrone, and the reason a flyer is not re-ordered
	# every frame by its squad.
	_ok("in the air group", body.is_in_group("air"))
	_ok("takes no cover", body.takes_cover() == false)
	_ok("visible_pieces non-empty", not body.visible_pieces.is_empty())
	_ok("particle_effects_die non-empty", not body.particle_effects_die.is_empty())
	_ok("particle_effects_hit non-empty", not body.particle_effects_hit.is_empty())
	# BOTH EMPTY ON PURPOSE — see the header of brood_carrier.gd. What is
	# asserted is the TYPE, which the generator got wrong.
	_ok("AllowedCombatOptions is empty and typed int",
		body.AllowedCombatOptions.is_empty()
		and body.AllowedCombatOptions.get_typed_builtin() == TYPE_INT)
	_ok("AllowedMovementOptions is empty and typed int",
		body.AllowedMovementOptions.is_empty()
		and body.AllowedMovementOptions.get_typed_builtin() == TYPE_INT)
	body.queue_free()


func _test_it_waits_for_the_fight() -> void:
	print("")
	print("── it holds its bay shut until something starts ──")
	var body = await _spawn(BROOD, Vector3(0, 40, 0))
	body.first_release_seconds = 0.2
	body.release_min_seconds = 0.2
	body.release_max_seconds = 0.2
	# _next_release was already seeded from the SCENE's first_release_seconds
	# in _ready, so writing the export afterwards does not shorten the first
	# countdown. Reset the live timer too, or the test just waits four seconds.
	body._next_release = body.first_release_seconds
	_ok("nine pods to start with", body.pods_left() == 9, str(body.pods_left()))
	_ok("a brood frame was resolved", body.brood.size() >= 1)
	for _i in 60:
		await physics_frame
	_ok("nothing released with no fight on", body.released == 0, str(body.released))
	var target = await _spawn(BROOD, Vector3(0, 40, 20))
	body.trigger_combat(target)
	for _i in 60:
		await physics_frame
	_ok("it releases once the fight is on", body.released >= 1, str(body.released))
	body.queue_free()
	target.queue_free()


func _test_the_caps() -> void:
	print("")
	print("── the two caps, and the lifetime one is the frame ──")
	var body = await _spawn(BROOD, Vector3(200, 40, 0))
	var target = await _spawn(BROOD, Vector3(200, 40, 20))
	body.first_release_seconds = 0.1
	body.release_min_seconds = 0.1
	body.release_max_seconds = 0.1
	# _next_release was already seeded from the SCENE's first_release_seconds
	# in _ready, so writing the export afterwards does not shorten the first
	# countdown. Reset the live timer too, or the test just waits four seconds.
	body._next_release = body.first_release_seconds
	# THE TWO CAPS HAVE TO BE TESTED SEPARATELY, and finding that out is worth
	# a comment: with max_alive = 2 and offspring that nothing kills, the
	# CONCURRENCY cap blocks production forever and the LIFETIME cap can never
	# be reached. A single test asserting both reads as the lifetime cap being
	# broken when it is actually the concurrency cap working.
	body.max_alive = 2
	body.total_pods = 9
	body.trigger_combat(target)
	var peak: int = 0
	for _i in 240:
		await physics_frame
		peak = maxi(peak, body._mine.size())
	_ok("never more than max_alive in the field at once", peak <= 2, "peaked at %d" % peak)
	_ok("and it stopped there rather than at the lifetime cap",
		body.released == 2 and body.pods_left() == 7, "released %d" % body.released)
	for child in body._mine:
		if child != null and is_instance_valid(child):
			child.queue_free()
	body.queue_free()
	target.queue_free()

	# The lifetime cap, with the concurrency cap out of the way.
	var solo = await _spawn(BROOD, Vector3(300, 40, 0))
	var solo_target = await _spawn(BROOD, Vector3(300, 40, 20))
	solo.first_release_seconds = 0.1
	solo.release_min_seconds = 0.1
	solo.release_max_seconds = 0.1
	solo._next_release = solo.first_release_seconds
	solo.max_alive = 99
	solo.total_pods = 3
	solo.trigger_combat(solo_target)
	for _i in 240:
		await physics_frame
	_ok("exactly total_pods were ever produced", solo.released == 3, str(solo.released))
	_ok("pods_left reads zero", solo.pods_left() == 0, str(solo.pods_left()))
	for child in solo._mine:
		if child != null and is_instance_valid(child):
			child.queue_free()
	solo.queue_free()
	solo_target.queue_free()


func _test_the_offspring() -> void:
	print("")
	print("── the offspring ──")
	var body = await _spawn(BROOD, Vector3(400, 40, 0))
	var target = await _spawn(BROOD, Vector3(400, 40, 20))
	# THE LITERAL VALUE, NOT body.faction. `child.faction == parent.faction`
	# would pass while the parent was still ENEMY, which is exactly the bug.
	body.faction = Enums.Factions.SWARM
	body.first_release_seconds = 0.1
	body.release_min_seconds = 0.1
	body.release_max_seconds = 0.1
	# _next_release was already seeded from the SCENE's first_release_seconds
	# in _ready, so writing the export afterwards does not shorten the first
	# countdown. Reset the live timer too, or the test just waits four seconds.
	body._next_release = body.first_release_seconds
	body.trigger_combat(target)
	for _i in 60:
		await physics_frame
	_ok("something came out", body.released >= 1, str(body.released))
	if body._mine.is_empty():
		body.queue_free()
		target.queue_free()
		return
	var child = body._mine[0]
	_ok("the offspring is SWARM, not ENEMY", child.faction == Enums.Factions.SWARM,
		"got %s" % Enums.Factions.keys()[child.faction])
	_ok("the offspring is in the enemies group", child.is_in_group("enemies"))
	_ok("the offspring is in the signal group", child.is_in_group(AI.SIGNAL_GROUP))
	# PROVES THE chassis_id META. Without it the body would be identified by
	# its scene basename and would need a KillKinds.SCENES entry, which is a
	# shared registry.
	_ok("the offspring is counted as its real frame",
		_KillKinds.kind_of(child) == &"leaper",
		"got %s" % _KillKinds.kind_of(child))
	_ok("the offspring has the carrier's health from the frame",
		child.max_health == (load(HOPPER) as ChassisDefinition).base_health,
		str(child.max_health))
	for c in body._mine:
		if c != null and is_instance_valid(c):
			c.queue_free()
	body.queue_free()
	target.queue_free()


func _test_the_bay_empties() -> void:
	print("")
	print("── the bay empties from the bottom, which is the only clock ──")
	var body = await _spawn(BROOD, Vector3(600, 40, 0))
	var target = await _spawn(BROOD, Vector3(600, 40, 20))
	_ok("the bay resolved", body.bay != null)
	if body.bay == null:
		body.queue_free()
		target.queue_free()
		return
	var all_shown := true
	for n in range(1, 10):
		var pod := body.bay.get_node_or_null("Pod%d" % n) as Node3D
		if pod == null or not pod.visible:
			all_shown = false
	_ok("all nine pods are present and visible to start with", all_shown)
	body.first_release_seconds = 0.1
	body.release_min_seconds = 0.1
	body.release_max_seconds = 0.1
	# _next_release was already seeded from the SCENE's first_release_seconds
	# in _ready, so writing the export afterwards does not shorten the first
	# countdown. Reset the live timer too, or the test just waits four seconds.
	body._next_release = body.first_release_seconds
	body.max_alive = 9
	body.total_pods = 3
	body.trigger_combat(target)
	for _i in 150:
		await physics_frame
	var emptied := 0
	var remaining := 0
	for n in range(1, 10):
		var pod := body.bay.get_node_or_null("Pod%d" % n) as Node3D
		if pod == null:
			continue
		if n <= body.released:
			if not pod.visible:
				emptied += 1
		elif pod.visible:
			remaining += 1
	_ok("the pods that were used are hidden", emptied == body.released,
		"%d hidden of %d used" % [emptied, body.released])
	_ok("the rest are still showing", remaining == 9 - body.released,
		"%d showing" % remaining)
	for c in body._mine:
		if c != null and is_instance_valid(c):
			c.queue_free()
	body.queue_free()
	target.queue_free()


# The five ocelli are NOT in the FactionLivery pieces array and must survive
# apply(). build_brood.gd does that exclusion by hand because there is no node
# named `Eye` for check_frame.gd's "EYE EXCLUDED" assertion to find — so this
# is the only thing protecting it.
func _test_the_ocelli_keep_their_own_colour() -> void:
	print("")
	print("── the ocelli keep their own material ──")
	var body = await _spawn(BROOD, Vector3(800, 40, 0))
	var livery: FactionLivery = null
	for child in body.get_children():
		if child is FactionLivery:
			livery = child
	_ok("the frame has a FactionLivery", livery != null)
	if livery == null:
		body.queue_free()
		return
	var before: Array = []
	var ocelli: Array[MeshInstance3D] = []
	for i in range(1, 6):
		var o := body.get_node_or_null("Rig/SensorCluster/Ocellus%d" % i) as MeshInstance3D
		if o == null:
			continue
		ocelli.append(o)
		before.append(o.material_override)
	_ok("all five ocelli resolve", ocelli.size() == 5, "found %d" % ocelli.size())
	var listed := false
	for p in livery.pieces:
		if p in ocelli:
			listed = true
	_ok("no ocellus is in the livery pieces array", not listed)
	livery.apply(Enums.Factions.SWARM)
	var kept := true
	for i in ocelli.size():
		if ocelli[i].material_override != before[i]:
			kept = false
	_ok("every ocellus kept its own material through apply()", kept)
	body.queue_free()
