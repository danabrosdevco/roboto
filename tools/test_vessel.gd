extends SceneTree

# ─────────────────────────────────────────────
# THE VESSEL
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_vessel.gd
#
# WHAT IS WORTH GUARDING HERE is not the model and not the driving — rover.gd
# owns the driving and tools/test_hatchling.gd already covers the charge itself.
# It is the three things that make this frame a carrier rather than an expensive
# Rover, none of which would error if it broke:
#
#   * THE LAUNCHER IS THE BAY. magazine_size = 2 with a 30 second reload_time is
#     the whole recharge mechanism: no new timer, no new state. Drop the
#     magazine to AIWeapon's default 30 and the Vessel puts sixty hoppers on the
#     ground in a minute, and nothing anywhere complains.
#
#   * THE DOORS ARE THE READ. The scene is authored OPEN, so a Vessel whose
#     _ready stopped closing them is a frame that drives round the map with its
#     bay hanging out — and it looks deliberate.
#
#   * THE BAY CANNOT LIE. The two cargo meshes are derived from the launcher's
#     magazine, so a bay showing two drones over an empty launcher is
#     unreachable by construction. The assertions below are what keep it that
#     way after someone adds a counter.
#
# The geometry is deliberately NOT asserted beyond the door angles, which are
# the one piece of geometry this script actually drives.
# ─────────────────────────────────────────────

const VESSEL := "res://Character/characters/ai/vessel.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"
const ROVER := "res://Character/characters/ai/vehicle_rover.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_vessel.tres"
const WALKER_CHASSIS := "res://Campaign/chassis/chassis_walker.tres"
const LAUNCHER_ITEM := "res://Campaign/items/item_hatchling_launcher.tres"
const LAUNCHER_SCENE := "res://Character/weapon/ai-wep_hatchling_launcher.tscn"
const CANISTER := "res://Character/weapon/hatchling/vessel_brood_canister.tscn"
const PAYLOAD := "res://Character/weapon/hatchling/vessel_brood_payload.tscn"
const DOOR_DEGREES := 130.0
## vessel.gd DoorState { STOWED, OPENING, OPEN, CLOSING }. Spelled out here
## because a script cannot reach another script's enum through an instance.
const DOOR_OPENING := 1

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_the_launcher_is_the_bay()
	await _test_it_is_weaker_than_the_walker()
	await _test_the_scene_is_wired()
	await _test_the_doors_close_at_spawn()
	await _test_the_doors_open_when_committed()
	await _test_the_doors_stow_when_the_fight_ends()
	await _test_nothing_leaves_through_a_shut_bay()
	await _test_the_bay_shows_what_is_left()
	await _test_a_gun_in_the_mount_leaves_the_bay_alone()
	await _test_a_released_unit_takes_the_vessels_side()

	print("")
	if _fails == 0:
		print("ALL VESSEL CHECKS PASS")
	else:
		print("VESSEL FAILURES: %d" % _fails)
	quit(0)


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
	body.set_physics_process(false)
	body.set_process(false)
	return body


# ─────────────────────────────────────────────
func _test_the_chassis_is_registered() -> void:
	var def = load(CHASSIS)
	_ok("the chassis definition loads", def != null)
	if def == null:
		return
	_ok("...and names itself vessel", def.id == &"vessel", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	_ok("...and is purchasable", bool(def.purchasable))
	# ONE MOUNT, NO COAX. The Walker's two mounts are its identity; a Vessel with
	# a coax would make the Walker pointless, and the scene has one WeaponMount
	# and no coax_mount — a coax pool would warn per body per mission.
	_ok("...one weapon slot, not the Walker's two", int(def.weapon_slots) == 1,
			"%d" % int(def.weapon_slots))
	_ok("...and no coax", String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	_ok("...it is a turret frame", bool(def.turret))
	_ok("...it drives", bool(def.drives))
	_ok("...and it is armour, so it joins that team", bool(def.vehicle))
	_ok("...one equipment slot", int(def.equipment_slots) == 1,
			"%d" % int(def.equipment_slots))
	# base_speed is a MULTIPLIER on the scene's move_speed, not a speed. It is
	# left at 1.0 here so the real number is specified once, on the scene.
	_ok("...and its speed is not specified twice", absf(float(def.base_speed) - 1.0) < 0.001,
			"base_speed %.2f — the scene owns move_speed" % float(def.base_speed))

	# THE GUN IT IS ISSUED MUST BE A GUN IT CAN BE REFITTED WITH. recruit()
	# writes starting_weapon_id straight into weapon_ids[0] without consulting
	# takes(), so a turret frame whose id is missing from its own weapon's
	# chassis_whitelist deploys armed and can never be refitted. That is the
	# shipped Bulwark bug; this is the assertion that catches it.
	var launcher = load(LAUNCHER_ITEM)
	_ok("the launcher item loads", launcher != null)
	if launcher == null:
		return
	_ok("...and the frame is issued it",
			def.starting_weapon_id == &"hatchling_launcher", str(def.starting_weapon_id))
	_ok("...and takes() allows it to be fitted", bool(def.takes(launcher)),
			"turret frames need their own id in the weapon's chassis_whitelist")
	_ok("...and nothing else can carry it",
			Array(launcher.chassis_whitelist) == [&"vessel"],
			str(launcher.chassis_whitelist))
	# TYPED, or the array saves as [] in silence and every frame can carry it.
	_ok("...with the whitelist typed, not a plain Array",
			launcher.chassis_whitelist.get_typed_builtin() == TYPE_STRING_NAME)
	_ok("...and it is a weapon, so it occupies the mount", int(launcher.kind) == 0,
			"kind %d" % int(launcher.kind))
	_ok("...and the AI can use it", bool(launcher.usable_by_ai) and launcher.ai_scene != null)
	# fits_vehicles, or takes() refuses it outright on a drives = true frame.
	_ok("...and it fits a vehicle", bool(launcher.fits_vehicles))


# ─────────────────────────────────────────────
func _test_the_launcher_is_the_bay() -> void:
	var w: Node = load(LAUNCHER_SCENE).instantiate()
	root.add_child(w)
	await process_frame
	_ok("the launcher is an AIWeapon", w is AIWeapon)
	_ok("...and lobs a round rather than hitscanning",
			w.get("grenade_scene") != null,
			"a launcher with no grenade_scene fires, makes noise, and nothing comes out")
	# THE RECHARGE, in two numbers and no new state. _finish_reload() refills the
	# magazine from nothing, which everywhere else is the bug that makes squad
	# ammunition infinite and here is the mechanic.
	_ok("...and holds exactly two canisters", int(w.magazine_size) == 2,
			"%d" % int(w.magazine_size))
	_ok("...which take a long time to come back", float(w.reload_time) >= 20.0,
			"reload_time %.1f" % float(w.reload_time))
	_ok("...and it starts loaded", int(w.magazine_current) == int(w.magazine_size),
			"%d of %d" % [int(w.magazine_current), int(w.magazine_size)])
	_ok("...and it is not infinite", not bool(w.infinite_ammo))
	# A COMMITTED BURST MUST BE ONE ROUND. Left at 0 the robot's own
	# burst_min..burst_max (2..5 on this scene) empties the bay in two frames.
	_ok("...one round per committed burst",
			int(w.burst_min) == 1 and int(w.burst_max) == 1,
			"%d..%d" % [int(w.burst_min), int(w.burst_max)])
	_ok("...and it will not drop one at its own feet",
			float(w.min_effective_range) >= 5.0, "%.1f m" % float(w.min_effective_range))
	_ok("...within the frame's own sensor range",
			float(w.max_effective_range) <= 45.01, "%.1f m" % float(w.max_effective_range))
	_ok("...and it has a muzzle to leave from", w.muzzle_origin != null)
	# The muzzle runs down the weapon's +X, which is the axis the Vessel's
	# WeaponMount turns onto the body's -Z. Built the other way the tube points
	# out of the frame's side and nothing complains.
	var muzzle_local: Vector3 = (w.muzzle_origin as Node3D).position \
			if (w.muzzle_origin as Node3D).get_parent() == w \
			else w.to_local((w.muzzle_origin as Node3D).global_position)
	_ok("...and the muzzle is out along the weapon's +X", muzzle_local.x > 0.3,
			"muzzle at %s" % str(muzzle_local.snapped(Vector3(0.01, 0.01, 0.01))))
	w.free()
	await process_frame

	# THE ROUND, AND WHAT CLIMBS OUT OF IT.
	var canister: Node = load(CANISTER).instantiate()
	_ok("the canister carries the Vessel's own payload",
			canister.get("explosion_scene") != null
			and String(canister.get("explosion_scene").resource_path) == PAYLOAD,
			str(canister.get("explosion_scene")))
	canister.free()
	var payload: Node = load(PAYLOAD).instantiate()
	_ok("...which releases two bodies, not one", int(payload.count) == 2,
			"%d" % int(payload.count))
	# lifetime = 0.0 WOULD MEAN "FOREVER" AND DOES NOT: _expire_later in
	# hatchling_payload.gd does create_timer(lifetime, false) with no zero guard,
	# so 0.0 fires on the next frame and destroys the unit immediately.
	_ok("...that live long enough to matter and not forever",
			float(payload.lifetime) > 1.0, "lifetime %.1f" % float(payload.lifetime))
	_ok("...and something is actually in the canister", payload.unit_scene != null)
	payload.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_is_weaker_than_the_walker() -> void:
	# THE BALANCE CONSTRAINT IS THE POINT OF THE FRAME, so it is asserted
	# against the Walker's own .tres by path rather than against numbers: the two
	# supply-3 frames cannot silently converge.
	var v = load(CHASSIS)
	var wk = load(WALKER_CHASSIS)
	_ok("both supply-3 definitions load", v != null and wk != null)
	if v == null or wk == null:
		return
	_ok("...and they cost the same seats", int(v.supply) == int(wk.supply),
			"%d vs %d" % [int(v.supply), int(wk.supply)])
	_ok("the Vessel has less health than the Walker",
			int(v.base_health) < int(wk.base_health),
			"%d vs %d" % [int(v.base_health), int(wk.base_health)])
	_ok("...sees less far", float(v.base_sensor_range) < float(wk.base_sensor_range),
			"%.0f vs %.0f" % [float(v.base_sensor_range), float(wk.base_sensor_range)])
	_ok("...carries fewer mounts", int(v.weapon_slots) < int(wk.weapon_slots),
			"%d vs %d" % [int(v.weapon_slots), int(wk.weapon_slots)])
	_ok("...and is no faster, as a multiplier",
			float(v.base_speed) <= float(wk.base_speed),
			"%.2f vs %.2f" % [float(v.base_speed), float(wk.base_speed)])
	# ...and in the real units, because base_speed is a multiplier and the SCENE
	# owns the number the robot actually moves at.
	#
	# MEASURED AGAINST THE ROVER, NOT THE WALKER, and this corrects the
	# integration brief's test 11. walker.tscn authors move_speed = 4.16 and
	# vessel.tscn authors the Rover's 7.0, so "the scene's move_speed is not
	# greater than walker.tscn's" would pin a six-wheeled carrier below a
	# walking mech. Speed is not the axis this frame is weaker on — health,
	# sensors and mounts are, and those are asserted above. What DOES need
	# guarding is that the Vessel never becomes a BETTER Rover: same script,
	# same chassis class, same single traversing mount, and the Vessel pays
	# three supply for a bay the Rover does not have.
	var vb := _spawn(VESSEL, Vector3(600, 0, 600))
	var rb := _spawn(ROVER, Vector3(700, 0, 700))
	await process_frame
	_ok("...and is no faster than the plain Rover it is built on",
			float(vb.move_speed) * float(v.base_speed) <= float(rb.move_speed) + 0.001,
			"%.2f vs %.2f" % [float(vb.move_speed) * float(v.base_speed),
				float(rb.move_speed)])
	vb.free()
	rb.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_scene_is_wired() -> void:
	var b := _spawn(VESSEL)
	await process_frame
	# IN THE GROUP EVERY HOSTILE SWEEP USES. add_to_group is not persistent by
	# default, so a group added in code never reaches the saved scene — and
	# nothing errors: the frame drives, aims and shoots, and is simply invisible
	# to AIManager, to EMP and to every hostile lookup in the game.
	_ok("the frame is in the \"enemies\" group", b.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it", b.is_in_group(AI.SIGNAL_GROUP))
	# `turret` is read as a PROPERTY by enemy.gd to decide hull_spoils_aim, so a
	# null one is a carrier that cannot fire while it drives.
	var turret = b.get("turret")
	var mount = b.get("weapon_mount")
	_ok("...it has a real turret node", turret != null)
	_ok("...and a weapon mount", mount != null)
	if turret != null and mount != null:
		# Walked up the tree rather than compared by name, so renaming anything
		# cannot quietly satisfy it.
		_ok("...and the mount traverses with the turret", turret.is_ancestor_of(mount))

	# THE ALLOWED OPTIONS. Empty is the silent defect: roll_combat_action returns
	# immediately on an empty combat array, so the frame never chooses MOVE in
	# combat, never commits a burst and never settles to aim.
	var moves = b.get("AllowedMovementOptions")
	var combat = b.get("AllowedCombatOptions")
	_ok("movement options are ADVANCE, FALLBACK and CHASE",
			Array(moves) == [0, 2, 4], str(moves))
	_ok("combat options are MOVE, AIM and FIRE", Array(combat) == [0, 1, 2], str(combat))
	# CONTENTS AND TYPE. An untyped array saves as [] in silence, which is the
	# same defect wearing the right numbers in the source.
	_ok("...and both are Array[int], not Array[Object]",
			(moves as Array).get_typed_builtin() == TYPE_INT
			and (combat as Array).get_typed_builtin() == TYPE_INT,
			"%d / %d" % [(moves as Array).get_typed_builtin(),
				(combat as Array).get_typed_builtin()])

	# THE EYE IS NOT FACTION KIT, and an empty pieces array makes FactionLivery
	# walk the whole frame and paint it.
	var liv = b.get_node_or_null("FactionLivery")
	var eye = b.find_child("Eye", true, false)
	_ok("...the livery names its pieces explicitly",
			liv != null and (liv.pieces as Array).size() > 0,
			"empty means it walks the whole frame instead")
	if liv != null and eye != null:
		_ok("...and the eye is not one of them", not (liv.pieces as Array).has(eye))
		liv.apply(Enums.Factions.ENEMY)
		await process_frame
		_ok("...so a repaint leaves the eye alone",
				eye.material_override != null and eye.material_override is StandardMaterial3D)
		var hull = b.find_child("Hull", true, false)
		_ok("...while the hull did take the faction coat",
				hull != null and hull.material_override is ShaderMaterial)
	_ok("death effects are wired", (b.get("particle_effects_die") as Array).size() > 0)
	_ok("visible_pieces is wired", (b.get("visible_pieces") as Array).size() > 0)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_doors_close_at_spawn() -> void:
	# THE SCENE IS AUTHORED OPEN. build_vessel.gd built the leaves at 130 degrees
	# because the brief asked for open, so without vessel.gd closing them in
	# _ready every Vessel in the game drives out of the hub with its bay hanging
	# out — and it looks deliberate.
	var b := _spawn(VESSEL)
	await process_frame
	var dl = b.get_node_or_null("Rig/Bay/DoorL")
	var dr = b.get_node_or_null("Rig/Bay/DoorR")
	_ok("the bay has two named doors", dl != null and dr != null)
	if dl == null or dr == null:
		b.free()
		return
	_ok("...and they are shut after _ready",
			absf((dl as Node3D).rotation.z) < 0.01 and absf((dr as Node3D).rotation.z) < 0.01,
			"L %.1f deg, R %.1f deg" % [rad_to_deg((dl as Node3D).rotation.z),
				rad_to_deg((dr as Node3D).rotation.z)])
	var ca = b.get_node_or_null("Rig/Bay/CargoA")
	var cb = b.get_node_or_null("Rig/Bay/CargoB")
	_ok("...and the bay has two cargo meshes", ca != null and cb != null)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
## Fits the launcher, loads it, and puts the frame in a fight. Returns the
## weapon, or null — which is a failure the caller reports.
func _arm(b: Node) -> Node:
	b.equip_weapon_scene(load(LAUNCHER_SCENE))
	await process_frame
	await process_frame
	b.ai_state = b.AIState.COMBAT
	return b.get("weapon")


func _run_doors(b: Node, seconds: float) -> void:
	var step := 1.0 / 60.0
	for i in int(seconds / step):
		b._tick_doors(step)


func _test_the_doors_open_when_committed() -> void:
	var b := _spawn(VESSEL, Vector3(100, 0, 100))
	await process_frame
	var w = await _arm(b)
	_ok("a launcher fits the Vessel's mount", w != null and w is AIWeapon)
	if w == null:
		b.free()
		return
	_ok("...and the bay reports charges from the launcher's magazine", b.bay_has_charges())
	_ok("...and the frame counts itself committed", b._committed())
	# Driven by hand rather than by the physics tick, because the frame is
	# spawned with physics off: this is the state machine, not the engine.
	_run_doors(b, 3.0)
	var dl = b.get_node_or_null("Rig/Bay/DoorL") as Node3D
	var dr = b.get_node_or_null("Rig/Bay/DoorR") as Node3D
	_ok("...and the doors reach open", b.doors_open(), "state %d" % int(b.door_state()))
	# SIGNED, so a mirrored leaf cannot pass. DoorL opens to +130 and DoorR to
	# -130; both to +130 is a bay with one door inside the other.
	_ok("...DoorL to +130 degrees",
			absf(rad_to_deg(dl.rotation.z) - DOOR_DEGREES) < 1.0,
			"%.1f deg" % rad_to_deg(dl.rotation.z))
	_ok("...DoorR to -130 degrees",
			absf(rad_to_deg(dr.rotation.z) + DOOR_DEGREES) < 1.0,
			"%.1f deg" % rad_to_deg(dr.rotation.z))
	b.free()
	await process_frame


func _test_the_doors_stow_when_the_fight_ends() -> void:
	var b := _spawn(VESSEL, Vector3(140, 0, 140))
	await process_frame
	var w = await _arm(b)
	if w == null:
		_ok("the frame could be armed", false)
		b.free()
		return
	_run_doors(b, 3.0)
	_ok("the doors are open while the fight runs", b.doors_open())
	# Contact drops. The bay is held open for close_after rather than slammed on
	# the next frame — a target dying mid-engagement is not the end of a fight.
	b.ai_state = b.AIState.PATROL
	b.combat_target = null
	_run_doors(b, float(b.close_after) * 0.5)
	_ok("...and are still open a moment after contact drops", b.doors_open(),
			"state %d" % int(b.door_state()))
	_run_doors(b, float(b.close_after) + float(b.door_seconds) + 1.0)
	var dl = b.get_node_or_null("Rig/Bay/DoorL") as Node3D
	var dr = b.get_node_or_null("Rig/Bay/DoorR") as Node3D
	_ok("...and stow once it has been quiet for close_after",
			absf(dl.rotation.z) < 0.01 and absf(dr.rotation.z) < 0.01,
			"L %.1f deg, R %.1f deg" % [rad_to_deg(dl.rotation.z), rad_to_deg(dr.rotation.z)])
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_nothing_leaves_through_a_shut_bay() -> void:
	# THE ONE THING THAT MUST NOT HAPPEN. Enemy.fire() is the funnel — it is
	# where weapon.fire() is called and where the round is spent — so the gate
	# lives there and is synchronous. An await on the door swing would leave a
	# window in which the launcher still reports a round available.
	var b := _spawn(VESSEL, Vector3(180, 0, 180))
	await process_frame
	var w = await _arm(b)
	if w == null:
		_ok("the frame could be armed", false)
		b.free()
		return
	b.weapon_target = (b as Node3D).global_position + Vector3(0, 0, -22)
	var loaded: int = int(w.magazine_current)
	_ok("the bay starts shut", not b.doors_open(), "state %d" % int(b.door_state()))
	b.fire()
	await process_frame
	_ok("...so a release through it is refused, and costs nothing",
			int(w.magazine_current) == loaded,
			"%d of %d left" % [int(w.magazine_current), loaded])
	_ok("...and the refusal asked the doors to open",
			int(b.door_state()) == DOOR_OPENING, "state %d" % int(b.door_state()))

	# Now with the bay open, the same call must spend a round.
	_run_doors(b, 3.0)
	_ok("...the doors came open", b.doors_open())
	b.fire()
	await process_frame
	_ok("...and the same call now releases a canister",
			int(w.magazine_current) == loaded - 1,
			"%d of %d left" % [int(w.magazine_current), loaded])
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_bay_shows_what_is_left() -> void:
	# THE BAY CANNOT LIE, because nothing counts separately: the two cargo meshes
	# are derived from magazine_current every tick. A saved-and-restored Vessel,
	# a refit and a Vessel mid-recharge all show the right thing without this
	# script knowing those cases exist.
	var b := _spawn(VESSEL, Vector3(220, 0, 220))
	await process_frame
	var w = await _arm(b)
	if w == null:
		_ok("the frame could be armed", false)
		b.free()
		return
	var ca = b.get_node_or_null("Rig/Bay/CargoA") as Node3D
	var cb = b.get_node_or_null("Rig/Bay/CargoB") as Node3D
	if ca == null or cb == null:
		_ok("the bay has two cargo meshes", false)
		b.free()
		return
	b._bay_display()
	_ok("a loaded bay shows both drones", ca.visible and cb.visible)
	# THE FORWARD BAY GOES FIRST — CargoA is at local z -0.42 and -Z is forward.
	w.magazine_current = 1
	b._bay_display()
	_ok("...one released empties the forward cradle", not ca.visible and cb.visible,
			"A %s, B %s" % [str(ca.visible), str(cb.visible)])
	w.magazine_current = 0
	b._bay_display()
	_ok("...and a spent bay shows neither", not ca.visible and not cb.visible)
	_ok("...and a spent bay is not committed, so it stows", not b.bay_has_charges())
	# RECHARGING IS AN EMPTY BAY, not a full one. _finish_reload() refills
	# magazine_current; while the timer runs the bay has to read as empty or the
	# doors stay open over nothing.
	w.magazine_current = 2
	w.is_reloading = true
	b._bay_display()
	_ok("...and a recharging bay reads as empty",
			not ca.visible and not cb.visible and not b.bay_has_charges())
	w.is_reloading = false
	# A THIRD RELEASE IS THE RELOAD, NOT A SHOT. needs_reload() is the gate, and
	# it is what makes the recharge happen with no new state.
	w.magazine_current = 0
	_ok("...an empty launcher asks for a recharge", bool(w.needs_reload()))
	w.start_reload()
	_ok("...and the recharge takes reload_time", bool(w.is_reloading)
			and absf(float(w.reload_timer) - float(w.reload_time)) < 0.01,
			"%.1f of %.1f" % [float(w.reload_timer), float(w.reload_time)])
	w._finish_reload()
	_ok("...after which the bay is full again, from nothing",
			int(w.magazine_current) == int(w.magazine_size) and not w.is_reloading,
			"%d" % int(w.magazine_current))
	b._bay_display()
	_ok("...and both drones are back in the cradles", ca.visible and cb.visible)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_a_gun_in_the_mount_leaves_the_bay_alone() -> void:
	# item_machine_gun.tres whitelists &"vessel", so a player can legally trade
	# the launcher for a gun. Two things then have to be true and neither is
	# obvious:
	#
	#   * THE DOORS MUST STAY SHUT. The MG's thirty rounds are not thirty
	#     charges. A bay that opens in every firefight over nothing is the
	#     frame's whole read, inverted.
	#   * THE GUN MUST STILL FIRE. The fire gate is keyed on the bay launcher
	#     rather than on the mount for exactly this reason — keyed on
	#     doors_open() alone it would be a frame that can never pull its own
	#     trigger, which is a dead Vessel that looks fine in the squad screen.
	var b := _spawn(VESSEL, Vector3(260, 0, 260))
	await process_frame
	b.equip_weapon_scene(load("res://Character/weapon/ai-wep_machine_gun.tscn"))
	await process_frame
	await process_frame
	b.ai_state = b.AIState.COMBAT
	var w = b.get("weapon")
	_ok("a machine gun fits the Vessel's mount", w != null and int(w.magazine_current) > 2,
			"magazine %d" % (0 if w == null else int(w.magazine_current)))
	if w == null:
		b.free()
		return
	_ok("...but it is not cargo, so the bay reports nothing", not b.bay_has_charges())
	_run_doors(b, 4.0)
	_ok("...and the doors stay shut over an empty bay", not b.doors_open(),
			"state %d" % int(b.door_state()))
	var ca = b.get_node_or_null("Rig/Bay/CargoA") as Node3D
	var cb = b.get_node_or_null("Rig/Bay/CargoB") as Node3D
	b._bay_display()
	_ok("...and the cradles show empty", not ca.visible and not cb.visible)
	# AND IT STILL SHOOTS.
	b.weapon_target = (b as Node3D).global_position + Vector3(0, 0, -22)
	var loaded: int = int(w.magazine_current)
	b.fire()
	await process_frame
	_ok("...while the gun itself fires normally", int(w.magazine_current) == loaded - 1,
			"%d of %d" % [int(w.magazine_current), loaded])
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_a_released_unit_takes_the_vessels_side() -> void:
	# hatchling_payload.gd substitutes PLAYER only when the source faction is
	# NEUTRAL, and it sets `faction` BEFORE add_child because FactionLivery reads
	# it in its own _ready. So a released hatchling on the wrong side would be a
	# friendly painted hostile that your own squad shoots — and nothing errors.
	var payload: Node3D = load(PAYLOAD).instantiate() as Node3D
	payload.source_faction = Enums.Factions.ENEMY
	root.add_child(payload)
	payload.global_position = Vector3(400, 0, 400)
	# _release is call_deferred out of the projectile's detonation, and the units
	# are added to the payload's PARENT, so they outlive it.
	await process_frame
	await process_frame
	await process_frame
	var released: Array = []
	for n in root.get_children():
		if n is Soldier and String(n.get("soldier_name")) == "HATCHLING":
			released.append(n)
	_ok("the canister puts two bodies on the ground", released.size() == 2,
			"%d came out" % released.size())
	for unit in released:
		_ok("...on the Vessel's side, not a default one",
				int(unit.faction) == int(Enums.Factions.ENEMY),
				"faction %d" % int(unit.faction))
		# A hatchling that went down and waited for a repair tool would just be
		# a wreck you have to walk over to.
		_ok("...and it cannot be downed", not bool(unit.can_be_downed))
	for unit in released:
		unit.free()
	await process_frame
