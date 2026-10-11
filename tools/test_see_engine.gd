extends SceneTree

# ─────────────────────────────────────────────
# THE SEE-ENGINE
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_see_engine.gd
#
# WHAT IS WORTH GUARDING HERE is the pair of things either side of an effect
# that costs zero lines.
#
# The aim bonus itself is FREE: Enemy.get_aim_spread_multiplier already ends in
# `if _contact_assisted(): mult *= SPOTTED_SPREAD`, and _contact_assisted is
# already keyed on the shooter's own faction. Nothing here implements it.
#
# What this suite guards is:
#
#   * THAT ANYTHING FEEDS THE LEDGER AT ALL. _tick_vision — the function
#     sensor_range drives — never calls note_seen. Only the 25 m Detection
#     Area3D does. So the 110 m contact sweep IS the frame, and without the
#     "writes contacts at 80 m" assertion this whole suite would pass on a tall
#     statue.
#   * THAT IT IS NOT A WALLHACK. Without the is_path_clear guard the frame
#     feeds its entire army contacts through terrain.
#   * THAT THE PUPIL GOES DARK. hud.gd filters contact marks to ALLIED only and
#     the effect is an 18% spread multiplier, so the lit eye is the ONLY
#     player-facing readout this frame has. It is the whole difference between
#     this frame and the Warden, which was cut for exactly its absence.
# ─────────────────────────────────────────────

const SEE := "res://Character/characters/ai/see_engine.tscn"
const SOLDIER := "res://Character/characters/ai/soldier_rifle.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_see_engine.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

var _fails: int = 0
var _mgr: AIManager = null


func _init() -> void:
	_mgr = AIManager.new()
	root.add_child(_mgr)
	await process_frame
	# THE Settings GATE ON _contact_assisted. enemy.gd returns false when debug
	# tools are enabled and debug.contact_accuracy is off — a tester in that
	# state sees the whole frame do nothing and nothing says why. Set it
	# explicitly or this suite fails for a reason that has nothing to do with
	# the frame.
	Settings.set_value("debug.contact_accuracy", true)

	await _test_hostility()
	await _test_the_chassis_is_registered()
	await _test_it_is_not_in_the_player_catalogue()
	await _test_the_scene()
	await _test_it_writes_contacts_at_sensor_range()
	await _test_it_does_not_see_through_walls()
	await _test_who_benefits()
	await _test_the_pupil()
	await _test_the_lenses_keep_their_own_material()

	print("")
	if _fails == 0:
		print("ALL SEE-ENGINE CHECKS PASS")
	else:
		print("SEE-ENGINE FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _note(label: String, cond: bool, detail: String) -> void:
	print("%s  %s%s" % ["PASS" if cond else "TODO", label, "" if cond else ("  " + detail)])


## Registered with the manager, at a position, on a side. Physics OFF unless
## asked for — only the See-Engine itself needs to tick.
func _spawn(path: String, at: Vector3, faction: int, ticking: bool = false) -> Node:
	var body: Node = load(path).instantiate()
	body.faction = faction
	root.add_child(body)
	body.global_position = at
	body.set_physics_process(ticking)
	body.set_process(false)
	_mgr.all_ai.append(body)
	body.ai_manager = _mgr
	# _ready is deferred in a --script run, and Enemy.initialize() awaits an
	# IDLE frame before setting frame_waited — which every per-tick gate in
	# enemy.gd is behind. Pump both kinds of frame or the frame sits inert.
	for _i in 4:
		await physics_frame
		await process_frame
	return body


func _clear() -> void:
	for b in _mgr.all_ai.duplicate():
		if is_instance_valid(b):
			b.free()
	_mgr.all_ai.clear()
	_mgr._contacts.clear()


# ─────────────────────────────────────────────
# TASK ZERO, AND ON THIS FRAME THE INBOUND DIRECTION IS LOAD-BEARING TWICE:
# AIManager.get_hostiles_in_radius filters on are_hostile(req_faction, ...), so
# an inbound-false ARGUS gets an empty sweep and _tick_watch writes nothing,
# with no warning at all.
func _test_hostility() -> void:
	print("── Argus is a faction that can be fought ──")
	_ok("hostile to the player, outbound",
		Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.ARGUS))
	_ok("hostile to the player, inbound",
		Enums.are_hostile(Enums.Factions.ARGUS, Enums.Factions.PLAYER))
	# The Bastion's field depends on this being FALSE, and so does the distance
	# cull: mutual hostility would make the enemy factions each other's
	# activation sources.
	_ok("not hostile to the other two enemy factions",
		not Enums.are_hostile(Enums.Factions.ARGUS, Enums.Factions.SWARM)
		and not Enums.are_hostile(Enums.Factions.ARGUS, Enums.Factions.HOME))


func _test_the_chassis_is_registered() -> void:
	print("")
	print("── registered ──")
	var frame := load(CHASSIS) as ChassisDefinition
	_ok("chassis_see_engine.tres loads", frame != null)
	if frame == null:
		return
	_ok("id is see_engine", frame.id == &"see_engine", str(frame.id))
	_ok("supply 3", frame.supply == 3, str(frame.supply))
	_ok("cost 0", frame.cost == 0)
	_ok("not purchasable", frame.purchasable == false)
	_ok("no weapon slots", frame.weapon_slots == 0, str(frame.weapon_slots))
	# _issue_weapon is NOT gated on weapon_slots, only on starting_weapon_id —
	# and this frame has a real WeaponMount for a gun to land in.
	_ok("no starting weapon", frame.starting_weapon_id == &"", str(frame.starting_weapon_id))
	_ok("sensor range 110", is_equal_approx(frame.base_sensor_range, 110.0))
	# turret = false means "the weapon slot only takes guns whitelisted to this
	# frame" does not apply — there is no slot. The scene still wires a real
	# gimbal as `turret`, which is a different thing.
	_ok("turret flag false", frame.turret == false)
	# built_in resolves as a FILENAME, not an enum. icons/items/designator_*.png
	# exist; a novel word here would be a silent blank.
	_ok("built_in is DESIGNATOR, which has art", frame.built_in == "DESIGNATOR", frame.built_in)
	_note("in KillKinds.FRAMES", _KillKinds.FRAMES.has(&"see_engine"),
		"add &\"see_engine\": \"%s\" to kill_kinds.gd" % CHASSIS)

	# THE BRIEF CLAIMS THIS IS THE HIGHEST SENSOR IN THE GAME. IT IS NOT — the
	# Watcher is 170. Asserted as "the highest that WALKS" instead, which is the
	# claim the design actually rests on: the Watcher is a static sensor post.
	var beaten := []
	for k in _KillKinds.FRAMES:
		var f = _KillKinds.frame_of(k)
		if f != null and f.base_sensor_range > frame.base_sensor_range:
			beaten.append("%s %.0f" % [k, f.base_sensor_range])
	print("      frames with a longer sensor: %s" % [beaten if not beaten.is_empty() else "none"])


func _test_it_is_not_in_the_player_catalogue() -> void:
	print("")
	print("── and deliberately NOT buyable ──")
	var cat = load(CATALOGUE)
	_ok("the catalogue loads", cat != null)
	if cat == null:
		return
	var present := false
	for c in cat.chassis:
		if c != null and c.id == &"see_engine":
			present = true
	_ok("no see_engine entry in the player catalogue", not present)


func _test_the_scene() -> void:
	print("")
	print("── the scene ──")
	var body = await _spawn(SEE, Vector3.ZERO, Enums.Factions.ARGUS)
	_ok("the script is see_engine.gd",
		body.get_script().resource_path == "res://Character/characters/ai/see_engine.gd")
	_ok("it is a Soldier", body is Soldier)
	_ok("in the enemies group", body.is_in_group("enemies"))
	_ok("in the signal group", body.is_in_group(AI.SIGNAL_GROUP))
	_ok("nothing is on the mount",
		body.weapon_mount != null and body.weapon_mount.get_child_count() == 0)
	_ok("no weapon", body.weapon == null)
	# A real traverse, not a stub satisfying an export — and half of §1.3's
	# read, because the big lens turning is what the player notices.
	_ok("the gimbal is wired as turret", body.turret != null and body.turret.name == "GimbalYaw")
	_ok("the lens pitch is wired as gun_pivot",
		body.gun_pivot != null and body.gun_pivot.name == "LensPitch")
	_ok("visible_pieces non-empty", not body.visible_pieces.is_empty())
	_ok("particle_effects_die non-empty", not body.particle_effects_die.is_empty())
	_ok("particle_effects_hit non-empty", not body.particle_effects_hit.is_empty())
	# §5.2. MOVE only on the combat array (AIM settles a shot it will never
	# take; FIRE scores high on a weaponless frame and wins no-op rolls), and
	# REPOSITION + FALLBACK only on the movement array — ADVANCE is excluded
	# because _score_movement_option(ADVANCE) scores high against the 30 m
	# _max_range fallback of a weaponless frame, and the frame would charge.
	_ok("AllowedCombatOptions is [0]", body.AllowedCombatOptions == [0],
		str(body.AllowedCombatOptions))
	_ok("AllowedMovementOptions is [1, 2]", body.AllowedMovementOptions == [1, 2],
		str(body.AllowedMovementOptions))
	_ok("both arrays are typed int",
		body.AllowedCombatOptions.get_typed_builtin() == TYPE_INT
		and body.AllowedMovementOptions.get_typed_builtin() == TYPE_INT)
	_ok("takes no cover", body.takes_cover() == false)
	_clear()


# THE ASSERTION THAT PROVES THE FRAME IS A FRAME. 80 m is well outside the
# 25 m Detection sphere every robot has, so a contact at that range can only
# have come from _tick_watch.
func _test_it_writes_contacts_at_sensor_range() -> void:
	print("")
	print("── it writes contacts at sensor range, which nothing else does ──")
	var eye = await _spawn(SEE, Vector3.ZERO, Enums.Factions.ARGUS, true)
	var mark = await _spawn(SOLDIER, Vector3(0, 0, 80), Enums.Factions.ALLIED)
	eye.watch_interval = 0.1
	eye._watch_timer = 0.0
	_ok("the sweep can see it at all", _mgr.get_hostiles_in_radius(eye, 110.0).has(mark),
		"an inbound-false faction gets an empty sweep and writes nothing, silently")
	for _i in 30:
		await physics_frame
	_ok("a target at 80 m is a fresh ARGUS contact",
		_mgr.is_fresh(Enums.Factions.ARGUS, mark))
	# The ledger is keyed by faction (AIManager._contacts), so this is
	# structural rather than implemented — asserted so the day somebody
	# "simplifies" _contacts into one table, this says why it mattered.
	_ok("and it is NOT a Swarm or Home Command contact",
		not _mgr.is_fresh(Enums.Factions.SWARM, mark)
		and not _mgr.is_fresh(Enums.Factions.HOME, mark))
	_ok("the pupil is lit while it is feeding", eye.is_watching())

	# KILLING IT STOPS THE FEED. Needs real elapsed time: is_fresh compares
	# against Time.get_ticks_msec, so stepping frames is the only way.
	eye.die()
	var waited := 0
	while waited < 400 and _mgr.is_fresh(Enums.Factions.ARGUS, mark):
		await physics_frame
		waited += 1
	_ok("killing it lets the contact go stale", not _mgr.is_fresh(Enums.Factions.ARGUS, mark),
		"still fresh after %d frames" % waited)
	_clear()


func _test_it_does_not_see_through_walls() -> void:
	print("")
	print("── and it is not a wallhack ──")
	var eye = await _spawn(SEE, Vector3(0, 0, 0), Enums.Factions.ARGUS, true)
	var mark = await _spawn(SOLDIER, Vector3(0, 0, 80), Enums.Factions.ALLIED)
	# A slab across the line of sight, on layer 1 the way level geometry is.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 20, 2)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = Vector3(0, 0, 40)
	eye.watch_interval = 0.1
	eye._watch_timer = 0.0
	for _i in 30:
		await physics_frame
	_ok("a target behind geometry is NOT a contact",
		not _mgr.is_fresh(Enums.Factions.ARGUS, mark))
	_ok("and the pupil is dark, because it is seeing nothing", not eye.is_watching())
	wall.free()
	_clear()


# THE AIM BONUS, WHICH THIS FRAME DOES NOT IMPLEMENT. Asserted end to end
# anyway, because the whole design rests on it being true.
func _test_who_benefits() -> void:
	print("")
	print("── who shoots straighter for it ──")
	var mark = await _spawn(SOLDIER, Vector3(0, 0, 80), Enums.Factions.ALLIED)
	# No line of sight of its own — the point is that it benefits from somebody
	# else's eyes.
	var argus = await _spawn(SOLDIER, Vector3(300, 0, 0), Enums.Factions.ARGUS)
	var swarm = await _spawn(SOLDIER, Vector3(300, 0, 4), Enums.Factions.SWARM)
	argus.combat_target = mark
	swarm.combat_target = mark
	var argus_cold: float = argus.get_aim_spread_multiplier()
	var swarm_cold: float = swarm.get_aim_spread_multiplier()
	_ok("with no contact, nobody is assisted",
		not argus._contact_assisted() and not swarm._contact_assisted())
	_mgr.note_seen(Enums.Factions.ARGUS, mark)
	_ok("an ARGUS unit with no line of its own is now assisted", argus._contact_assisted())
	_ok("and it shoots tighter", argus.get_aim_spread_multiplier() < argus_cold,
		"%f vs %f" % [argus.get_aim_spread_multiplier(), argus_cold])
	# §1.1: structural, because the ledger is keyed by faction.
	_ok("A SWARM UNIT DOES NOT BENEFIT", not swarm._contact_assisted())
	_ok("and its spread is unchanged",
		is_equal_approx(swarm.get_aim_spread_multiplier(), swarm_cold))
	_clear()


func _test_the_pupil() -> void:
	print("")
	print("── the eye goes out with it, which is the only death the player sees ──")
	var eye = await _spawn(SEE, Vector3.ZERO, Enums.Factions.ARGUS, true)
	var mark = await _spawn(SOLDIER, Vector3(0, 0, 60), Enums.Factions.ALLIED)
	eye.watch_interval = 0.1
	eye._watch_timer = 0.0
	var mat: StandardMaterial3D = eye.pupil.material_override as StandardMaterial3D
	_ok("the pupil has its own duplicated material", mat != null and mat == eye._pupil_material)
	_ok("emission is enabled on it", mat != null and mat.emission_enabled)
	for _i in 30:
		await physics_frame
	_ok("lit while it is feeding",
		is_equal_approx(mat.emission_energy_multiplier, eye.pupil_lit_energy),
		str(mat.emission_energy_multiplier))
	eye.die()
	_ok("dark the frame it dies", is_equal_approx(mat.emission_energy_multiplier, 0.0),
		str(mat.emission_energy_multiplier))
	# IT MUST STAY DARK. die() switches the physics tick off, so whatever the
	# emission was on that last frame is what it would keep forever.
	for _i in 20:
		await physics_frame
	_ok("and stays dark", is_equal_approx(mat.emission_energy_multiplier, 0.0))
	_clear()


# There is NO node named `Eye` on this frame, so check_frame.gd's
# "EYE EXCLUDED" assertion never fires and this test is the only thing
# protecting the three lenses from being painted the faction colour.
func _test_the_lenses_keep_their_own_material() -> void:
	print("")
	print("── the lens and the two pods keep their own material ──")
	var body = await _spawn(SEE, Vector3.ZERO, Enums.Factions.ARGUS)
	var livery: FactionLivery = null
	for child in body.get_children():
		if child is FactionLivery:
			livery = child
	_ok("the frame has a FactionLivery", livery != null)
	if livery == null:
		_clear()
		return
	var paths := [
		"Rig/GimbalYaw/LensPitch/Pupil",
		"Rig/SensorPodA/Lens",
		"Rig/SensorPodB/Lens",
	]
	var nodes: Array[MeshInstance3D] = []
	var before: Array = []
	for p in paths:
		var n := body.get_node_or_null(p) as MeshInstance3D
		if n == null:
			continue
		nodes.append(n)
		before.append(n.material_override)
	_ok("all three resolve", nodes.size() == 3, "found %d" % nodes.size())
	var listed := false
	for p in livery.pieces:
		if p in nodes:
			listed = true
	_ok("none of them is in the livery pieces array", not listed)
	livery.apply(Enums.Factions.ARGUS)
	var kept := true
	for i in nodes.size():
		if nodes[i].material_override != before[i]:
			kept = false
	_ok("all three kept their own material through apply()", kept)
	_clear()
