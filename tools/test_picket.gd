extends SceneTree

# ─────────────────────────────────────────────
# THE PICKET
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_picket.gd
#
# WHAT IS WORTH GUARDING HERE is not the model and not the damage. It is four
# things, none of which would error if it broke:
#
#   * THE CANT'S SIGN. PodCant carries +54 degrees about +X (picket.tscn:423)
#     and walker.gd:224 ASSIGNS gun_pivot.rotation.x on top of it, clamped
#     between gun_min/max_pitch_degrees. The two ADD, so the launcher's real
#     band is 42 to 89 degrees and the pack CANNOT point at the ground. That is
#     the approved silhouette (docs/integration/PICKET.md, amendment of
#     2026-10-10) and it is asserted here rather than left to be rediscovered —
#     three of the frame's five first-round concepts had this sign wrong
#     (build_picket.gd:103-108), and a negative cant points a six-tube launcher
#     at the floor with nothing complaining.
#
#   * ONE FITTABLE GUN, ON PURPOSE. turret = true plus a whitelist of exactly
#     [&"picket"] is the mechanism, and it is also trap 6.2 — see the long
#     comment on _test_the_whitelist_does_its_job.
#
#   * THE TWO NUMBERS THAT ARE THE FRAME. Reach (95 m) and acquisition (75 m
#     sensor). NOT damage: there is no size-discrimination mechanism in
#     AIWeapon, so the design doc's "lethal against a 90-hull target, poor
#     against a 400-hull one" cannot be tested and is not tested.
#
#   * THE Allowed*Options ARRAYS, as ints. They shipped empty AND typed
#     Array[AIEquipmentSlot], which makes roll_combat_action return at
#     enemy.gd:3053 — no MOVE, no committed burst, no aim stance. On a launcher
#     that is supposed to ripple, "fires slowly in single shots" reads as a
#     feel problem rather than as a bug. tools/check_frame.gd does not check
#     these, so they are checked here.
#
# The geometry is deliberately NOT asserted — sizes are judged by looking, and
# tools/check_frame.gd prints the measured W/H/L.
# ─────────────────────────────────────────────

const PICKET := "res://Character/characters/ai/picket.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_picket.tres"
const ROCKETS := "res://Campaign/items/item_rocket_pods.tres"
const WEAPON := "res://Character/weapon/ai-wep_rocket_pods.tscn"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const ROVER := "res://Campaign/chassis/chassis_rover.tres"
const WALKER := "res://Campaign/chassis/chassis_walker.tres"
const HEAVY_MG := "res://Campaign/items/item_heavy_mg.tres"
const NANITE := "res://Campaign/items/item_nanite_reboot.tres"
## The mission that gates the frame. required_rank on a chassis is inert —
## recruit() never reads it (campaign_state.gd:739-764) — so an `unlocks` entry
## is the only real gate (campaign.gd:1068-1082).
## By path, not by class_name: a class_name is not resolvable in a standalone
## --check-only parse until the editor rescans, and the rescan must not be run
## with the editor open. tools/test_lance_frame.gd:55 does the same.
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

const UNLOCK_MISSION := "res://Campaign/missions/mission_coast_1_road.tres"

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_the_weapon_is_a_launcher()
	await _test_the_whitelist_does_its_job()
	await _test_the_frame_is_wired()
	await _test_the_launcher_points_at_the_sky()
	await _test_it_walks()
	await _test_a_fitted_launcher_follows_the_turret()

	print("")
	if _fails == 0:
		print("ALL PICKET CHECKS PASS")
	else:
		print("PICKET FAILURES: %d" % _fails)
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
	body.set_physics_process(false)
	body.set_process(false)
	return body


# ─────────────────────────────────────────────
func _test_the_chassis_is_registered() -> void:
	var def = load(CHASSIS)
	_ok("the chassis definition loads", def != null)
	if def == null:
		return
	_ok("...and names itself picket", def.id == &"picket", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	_ok("...and is purchasable", bool(def.purchasable))
	# SUPPLY TWO IS ASSERTED, because supply_of() returns 1 for a frame the
	# catalogue does not carry (campaign_state.gd:315-317). A missing catalogue
	# entry is therefore invisible except as a Picket that costs one seat
	# instead of two — which is exactly the bug this line catches.
	_ok("...and costs two supply", int(def.supply) == 2, "%d" % int(def.supply))
	_ok("...one weapon slot", int(def.weapon_slots) == 1, "%d" % int(def.weapon_slots))
	# NO COAX. picket.tscn:171's node_paths list has no coax_mount, so
	# equip_coax_scene would warn and drop, once per body per mission
	# (enemy.gd:77-81).
	_ok("...and no coax, because there is no second mount",
			String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	# THE PAIR THAT DEFINES THE FRAME: a whitelisted turret on legs. drives =
	# false is what lets it take leg kit a Rover cannot (chassis_definition.gd:89).
	_ok("...it is a turret frame", bool(def.turret))
	_ok("...and it walks rather than drives", not bool(def.drives))
	_ok("...and musters with ARMOR", bool(def.vehicle))
	_ok("...and issues the rocket pods",
			def.starting_weapon_id == &"rocket_pods", str(def.starting_weapon_id))

	var body := _spawn(PICKET)
	await process_frame
	# THE DEFINITION AND THE SCENE MUST AGREE. For a squad-spawned body the
	# definition wins (squad_spawner.gd:348-350); for a hand-placed or lab body
	# it may not be applied at all. They disagreed on both of these when the
	# frame was generated — scene 170 hull / 45 sensor against the design doc's
	# 140 / 75 — so the agreement IS the assertion.
	_ok("hull is 140 on the definition", int(def.base_health) == 140,
			"%d" % int(def.base_health))
	_ok("...and 140 in the scene too", int(body.health) == 140, "%d" % int(body.health))
	_ok("sensor range is 75 on the definition", is_equal_approx(float(def.base_sensor_range), 75.0),
			"%.1f" % float(def.base_sensor_range))
	_ok("...and 75 in the scene too", is_equal_approx(float(body.sensor_range), 75.0),
			"%.1f" % float(body.sensor_range))
	# AS A PRODUCT, not as two numbers. base_speed is a MULTIPLIER on the
	# scene's move_speed (soldier_record.gd:254 -> squad_spawner.gd:349), and
	# the Lance's generator pre-applied its multiplier into the scene as well,
	# which double-counted it. Asserting the product means that bug cannot be
	# imported here whichever side someone edits.
	var real_speed: float = float(def.base_speed) * float(body.move_speed)
	_ok("a squad Picket walks at about 4.05 m/s", absf(real_speed - 4.05) < 0.2,
			"%.2f = %.2f x %.2f" % [real_speed, float(def.base_speed), float(body.move_speed)])
	body.free()
	await process_frame

	# REGISTRATION IN THE SHARED FILES. These are the coordinator's to apply, so
	# a failure here is "not registered yet", not "broken" — but it has to fail,
	# because every one of them is silent.
	var cat = load(CATALOGUE)
	_ok("the live catalogue loads", cat != null)
	if cat != null:
		var frames: Array = []
		for c in cat.chassis:
			if c != null:
				frames.append(String(c.id))
		_ok("...and carries the frame", frames.has("picket"), str(frames))
		# ITEM 6b, which FRAME_ANATOMY.md section 1.3 does not list.
		# _fit_loadout resolves the gun via cat.item(id) and `continue`s on null
		# (squad_spawner.gd:304-306), so a Picket recruited with
		# starting_weapon_id = &"rocket_pods" and no catalogue item deploys
		# UNARMED and nothing warns.
		var gun = cat.item(&"rocket_pods")
		_ok("...and the launcher, or the frame deploys unarmed in silence", gun != null)
		if gun != null:
			# in_shop is required by test_ledger.gd:818-831 for anything a
			# mission unlocks: an unlock the armoury will not sell fails the build.
			_ok("...and the launcher is on sale, as an unlock requires", bool(gun.in_shop))

	_ok("KillKinds knows the frame", _KillKinds.FRAMES.has(&"picket"),
			"without it the debrief prints a raw id and bakes no icon")
	_ok("...and resolves it to a definition", _KillKinds.frame_of(&"picket") != null)

	if ResourceLoader.exists(UNLOCK_MISSION):
		var m = load(UNLOCK_MISSION)
		var un: Array = []
		for u in m.unlocks:
			un.append(String(u))
		_ok("the frame is gated behind a mission, since required_rank is inert",
				un.has("picket"), "coast_1 unlocks %s" % str(un))
		_ok("...and so is its launcher", un.has("rocket_pods"), str(un))


# ─────────────────────────────────────────────
func _test_the_weapon_is_a_launcher() -> void:
	var item = load(ROCKETS)
	_ok("the launcher item loads", item != null)
	if item == null:
		return
	_ok("...and is a WEAPON", int(item.kind) == 0, "%d" % int(item.kind))
	_ok("...and a squadmate can carry it", item.fits_ai())
	_ok("...and has an AI scene", item.ai_scene != null)
	_ok("...and no player viewmodel", item.player_scene == null)

	var w = load(WEAPON).instantiate()
	_ok("the weapon scene is an AIWeapon", w is AIWeapon)
	# NO SUBCLASS. The fifth set of exports on the indirect-fire family, after
	# the mortar, the grenade launcher, the turret GL and the cluster.
	# FRAME_ANATOMY.md section 3.4: a .tres plus ai_weapon_grenade_launcher.gd
	# is enough for anything that lobs a charge. If this ever becomes a bespoke
	# script, the reason belongs in a comment next to this line.
	_ok("...on the shared indirect-fire script, not a bespoke one",
			w is AIWeaponGrenadeLauncher, w.get_script().resource_path)
	if not (w is AIWeaponGrenadeLauncher):
		w.free()
		return
	# IT FIRES SOMETHING. check_damage() on this script warns and returns with
	# no grenade_scene — the launcher then cycles, makes noise, and nothing
	# comes out (ai_weapon_grenade_launcher.gd:66-68).
	_ok("...and it has a round to fire", w.grenade_scene != null)
	_ok("...which it launches from the ground, on an arc", float(w.lob_speed) > 0.0,
			"lob_speed %.1f" % float(w.lob_speed))
	_ok("...on the steep root, to match a launcher canted 54 degrees",
			bool(w.high_arc))
	_ok("...bursting where it lands rather than rolling on", bool(w.impact_fused))
	_ok("...as a PROJECTILE, not hitscan",
			int(w.weapon_type) == int(Enums.AIWeaponTypes.PROJECTILE),
			"%d" % int(w.weapon_type))

	# THE TWO NUMBERS THAT ARE THE FRAME. Reach and acquisition are the counter;
	# damage is not, and there is no mechanism in AIWeapon that discriminates by
	# target size, so no test here pretends there is.
	_ok("it reaches 95 m, which is one of the frame's two real edges",
			is_equal_approx(float(w.max_effective_range), 95.0),
			"%.1f" % float(w.max_effective_range))
	# AND IT CANNOT REACH ITS OWN FEET. On the high arc a round fired at
	# something ten metres off goes nearly straight up and comes nearly
	# straight back down; ai-wep_cluster.tscn carries the same comment. The
	# brief's 0.0 was written for a hitscan burst and is wrong for a rocket.
	_ok("...and holds its fire up close, because the round comes back down",
			float(w.min_effective_range) >= 12.0,
			"%.1f" % float(w.min_effective_range))
	# THE ROUND IS NOT INSTANT, which is what PATIENT targeting reasons about:
	# pick something that will still be there when it lands. Without a
	# projectile_speed, flight_time() is zero and PATIENT has nothing to hold on
	# to (ai_weapon.gd:720-721, 785).
	_ok("...and the round takes time to arrive", float(w.projectile_speed) > 0.0,
			"%.1f m/s" % float(w.projectile_speed))
	_ok("...so the launcher picks its own target and sticks with it",
			int(w.targeting) == 1 and float(w.target_hold_seconds) >= 4.0,
			"targeting %d, hold %.1f s" % [int(w.targeting), float(w.target_hold_seconds)])
	# A BATTERY RIPPLES. 0 defers to the body's burst_min = 2 / burst_max = 5
	# (picket.tscn:234-235), which is not wrong, but the rhythm belongs to the
	# weapon here — six tubes.
	_ok("...and ripples rather than taps", int(w.burst_min) >= 2 and int(w.burst_max) >= 4,
			"%d-%d" % [int(w.burst_min), int(w.burst_max)])
	# DAMAGE MUST NOT RISE WITH RANGE. The default min_damage is 18
	# (ai_weapon.gd:16) and calculate_damage lerps base -> min, so a launcher
	# left on the defaults against a low base_damage gets STRONGER further out.
	_ok("...and damage does not grow with range",
			w.calculate_damage(95.0) <= w.calculate_damage(10.0),
			"%d at 95 m vs %d at 10 m" % [w.calculate_damage(95.0), w.calculate_damage(10.0)])
	# A LAUNCHER'S DAMAGE IS ON THE ROUND, not on the launcher. shot_damage()
	# reads the round and applies this weapon's overrides, so this is what the
	# shop card will print.
	var dmg: Dictionary = w.shot_damage()
	_ok("...and the round it actually arrives with is worth something",
			int(dmg.get("total", 0)) > 0, str(dmg))
	w.free()


# ─────────────────────────────────────────────
func _test_the_whitelist_does_its_job() -> void:
	var picket = load(CHASSIS)
	var rover = load(ROVER)
	var walker = load(WALKER)
	var rockets = load(ROCKETS)
	var mg = load(HEAVY_MG)
	var nanite = load(NANITE)
	if picket == null or rockets == null:
		_ok("the chassis and the launcher both load", false)
		return

	_ok("the whitelist names the Picket and nothing else",
			rockets.chassis_whitelist.size() == 1 and rockets.chassis_whitelist.has(&"picket"),
			str(rockets.chassis_whitelist))
	_ok("...so the launcher fits the Picket", picket.takes(rockets))
	if rover != null:
		_ok("...and not a Rover", not rover.takes(rockets))
	if walker != null:
		_ok("...and not a Walker", not walker.takes(rockets))

	# TRAP 6.2, PINNED. ChassisDefinition.takes() refuses a WEAPON on a frame
	# with turret = true unless the item names that frame in chassis_whitelist
	# (chassis_definition.gd:91) — and recruit() writes starting_weapon_id
	# straight into weapon_ids[0] WITHOUT asking takes()
	# (campaign_state.gd:750-751). That is how the Bulwark came to be armable
	# exactly once: it deploys with a heavy_mg it can never be refitted with,
	# and nothing warns.
	#
	# So this line is not "the Picket cannot have a heavy MG" as an oversight.
	# It is the frame shipping with ONE fittable gun ON PURPOSE, and the
	# whitelist above is what keeps the launcher off a Rover for free. Do not
	# "fix" this by clearing the whitelist — an EMPTY whitelist does not satisfy
	# the turret rule either, so that would make the frame unarmable instead.
	if mg != null:
		_ok("a gun that does not name the frame is refused by the turret rule",
				not picket.takes(mg))
	# AND THE NON-OBVIOUS ADVANTAGE OVER A ROVER: drives = false, so leg kit
	# fits. Nothing else in the project states this about the Picket.
	if nanite != null:
		_ok("leg kit fits, because it walks", picket.takes(nanite))
		if rover != null:
			_ok("...which the Rover cannot take", not rover.takes(nanite))


# ─────────────────────────────────────────────
func _test_the_frame_is_wired() -> void:
	var b := _spawn(PICKET)
	await process_frame
	# EVERY NODE-PATH EXPORT. walker.gd and enemy.gd between them resolve
	# thirteen, and a missed one is silent — bark in particular has no symptom
	# at all beyond a robot that never speaks.
	for prop in ["rig", "hip_left", "knee_left", "hip_right", "knee_right",
			"foot_left", "foot_right", "turret", "gun_pivot", "nav_agent",
			"weapon_mount", "bark", "detection"]:
		_ok("%s resolved" % prop, b.get(prop) != null)

	_ok("it is in the \"enemies\" group", b.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it", b.is_in_group(AI.SIGNAL_GROUP))

	# IT PARKS, IT DOES NOT TAKE COVER (walker.gd:251). Squad splits its members
	# on this (squad.gd:554-555): a Picket sent to infantry cover points would
	# park on top of them, and a gun platform in a crouch spot is not cover.
	_ok("it parks rather than taking cover", not b.takes_cover())

	# THE ARRAYS tools/check_frame.gd DOES NOT CHECK. Empty makes
	# roll_combat_action return at enemy.gd:3053 — see the header. And the TYPE
	# is as much the bug as the emptiness: these shipped as
	# Array[AIEquipmentSlot], which is where the "Cannot assign contents of
	# Array[Object] to Array[int]" pair on load came from.
	var mv = b.get("AllowedMovementOptions")
	var cb = b.get("AllowedCombatOptions")
	_ok("movement options are ADVANCE and REPOSITION",
			(mv as Array) == [0, 1], str(mv))
	_ok("...typed as ints, not as objects",
			(mv as Array).get_typed_builtin() == TYPE_INT,
			"typed %d" % (mv as Array).get_typed_builtin())
	_ok("combat options are MOVE, AIM and FIRE",
			(cb as Array) == [0, 1, 2], str(cb))
	_ok("...typed as ints, not as objects",
			(cb as Array).get_typed_builtin() == TYPE_INT,
			"typed %d" % (cb as Array).get_typed_builtin())

	# A BOUND, NOT AN EQUALITY: retuning the traverse is free, but "it silently
	# went back to the Walker's 55" fails. 38 puts it just under the Bulwark's
	# 42, which is the precedent for a frame meant to be flanked.
	_ok("the traverse is slow enough that flanking it is the counter",
			float(b.turret_traverse_degrees) <= 42.0,
			"%.0f deg/s" % float(b.turret_traverse_degrees))
	# ...and the elevation rate has to beat the traverse, or the launcher is
	# still climbing when the bearing has arrived.
	_ok("...and the launcher elevates faster than the turret traverses",
			float(b.gun_elevation_degrees) > float(b.turret_traverse_degrees),
			"%.0f vs %.0f deg/s" % [float(b.gun_elevation_degrees),
					float(b.turret_traverse_degrees)])

	# THE TYPED ARRAYS THAT PAINT THE FRAME. Empty, FactionLivery walks its
	# whole parent and paints the eye (test_bulwark.gd:185-210 is the comment).
	var liv = b.get_node_or_null("FactionLivery")
	var eye = b.find_child("Eye", true, false)
	_ok("the frame has an eye", eye != null)
	_ok("...and a livery that names its pieces", liv != null and liv.pieces.size() > 0)
	if liv != null and eye != null:
		# THE EYE IS NOT FACTION KIT. One offset eye identifies every robot in
		# the game; an eye that changes colour per side stops identifying anything.
		_ok("...and the eye is not one of them", not liv.pieces.has(eye))
	_ok("death effects are wired", (b.get("particle_effects_die") as Array).size() > 0)
	_ok("hit effects are wired", (b.get("particle_effects_hit") as Array).size() > 0)
	_ok("visible_pieces is wired", (b.get("visible_pieces") as Array).size() > 0)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_launcher_points_at_the_sky() -> void:
	# THE ASSERTION ONLY THIS FRAME NEEDS.
	#
	# PodCant (picket.tscn:423) carries +54 degrees about +X, BELOW the hinge
	# walker.gd:224 drives. A rotation about +X maps -Z to (0, sin, -cos), so a
	# NEGATIVE angle would aim the muzzle at the floor on the one frame in the
	# roster whose reason to exist is shooting upward — and three of five
	# first-round concepts got exactly that wrong (build_picket.gd:103-108).
	#
	# The cant lives on a CHILD of gun_pivot and not on the pivot itself
	# because walker.gd:224 ASSIGNS rotation.x every frame, clamped: a 54-degree
	# rest pose built into the pivot would be flattened on the first frame of
	# combat. So the parentage is checked by walking up the tree, not by name.
	var b := _spawn(PICKET, Vector3(400, 0, 400))
	await process_frame
	var pivot = b.get("gun_pivot")
	var mount = b.get("weapon_mount")
	var cant = b.find_child("PodCant", true, false)
	_ok("the cant node exists", cant != null)
	if pivot == null or mount == null or cant == null:
		_ok("the pivot, the mount and the cant all resolved", false)
		b.free()
		return
	var n: Node = cant
	var under: bool = false
	while n != null:
		if n == pivot:
			under = true
			break
		n = n.get_parent()
	_ok("...below the hinge, so the aiming clamp cannot flatten the rest pose", under)
	_ok("...and the mount rides the cant", cant.is_ancestor_of(mount))

	# THE BAND, ASSERTED AS A DECISION. The amendment of 2026-10-10 keeps
	# 42 to 89 degrees: the launcher CANNOT be made to point at a ground target,
	# at any range, ever. It still HITS one — a launched round solves its own
	# arc and lands where it was aimed regardless of how the model points — but
	# the pack visibly stays up. That is the approved silhouette for a frame
	# that only ever fires indirect, and it is recorded here so the next reader
	# finds a choice rather than a discovery.
	for probe in [["at rest", 0.0, 54.0], ["fully depressed", float(b.gun_min_pitch_degrees), 42.0],
			["fully elevated", float(b.gun_max_pitch_degrees), 89.0]]:
		(pivot as Node3D).rotation.x = deg_to_rad(float(probe[1]))
		await process_frame
		# A weapon's bore is its own +X, and the mount is yawed +PI/2 to put
		# that along the assembly's -Z — so the muzzle direction a fitted gun
		# would fire along is the mount's +X.
		var bore: Vector3 = (mount as Node3D).global_transform.basis.x.normalized()
		var elev: float = rad_to_deg(asin(clampf(bore.y, -1.0, 1.0)))
		_ok("the launcher sits at about %.0f degrees %s" % [float(probe[2]), str(probe[0])],
				absf(elev - float(probe[2])) < 2.0, "%.1f deg" % elev)
	# ...and the floor of that band is still well above the horizon, which is
	# the whole claim: nothing it fires is flat.
	(pivot as Node3D).rotation.x = deg_to_rad(float(b.gun_min_pitch_degrees))
	await process_frame
	var low: Vector3 = (mount as Node3D).global_transform.basis.x.normalized()
	_ok("...so even at full depression the bore is above the horizon", low.y > 0.6,
			"bore.y %.3f" % low.y)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_it_walks() -> void:
	# The gait is Walker's and is driven by how far the body MOVED, so posing it
	# means moving it and ticking. A frame whose rig paths are wrong does not
	# error — it slides around the level like a chess piece.
	var b := _spawn(PICKET, Vector3.ZERO)
	await process_frame
	var knee = b.get("knee_left")
	if knee == null:
		_ok("the left knee resolved", false)
		b.free()
		return
	var rest: Vector3 = (knee as Node3D).rotation
	var moved: bool = false
	for i in 40:
		(b as Node3D).global_position += Vector3(0, 0, -0.35)
		b._tick_gait(1.0 / 60.0)
		if not (knee as Node3D).rotation.is_equal_approx(rest):
			moved = true
	_ok("the gait bends the knee when the frame walks", moved)
	for i in 90:
		b._tick_gait(1.0 / 60.0)
	_ok("...and it settles when the frame stops",
			(knee as Node3D).rotation.is_equal_approx(rest),
			"%s vs rest %s" % [str((knee as Node3D).rotation), str(rest)])
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_a_fitted_launcher_follows_the_turret() -> void:
	var b := _spawn(PICKET, Vector3(600, 0, 600))
	await process_frame
	var mount = b.get("weapon_mount")
	var turret = b.get("turret")
	if mount == null or turret == null:
		_ok("the mount and the turret resolved", false)
		b.free()
		return
	_ok("the mount turns with the turret", turret.is_ancestor_of(mount))
	# WeaponMount yaw is +PI/2, NOT -PI/2. Read off the Walker's matrix it looks
	# like a quarter turn either way; it is not, and the Bulwark fired backwards
	# for it. Also checked by tools/check_frame.gd — cheap to repeat.
	_ok("...and is yawed +90 degrees, which is what turns a weapon's +X onto -Z",
			absf((mount as Node3D).rotation.y - PI * 0.5) < 0.01,
			"%.1f deg" % rad_to_deg((mount as Node3D).rotation.y))

	b.equip_weapon_scene(load(WEAPON))
	await process_frame
	await physics_frame
	_ok("the launcher fits the mount", b.weapon != null and b.weapon is AIWeapon)
	if b.weapon == null:
		b.free()
		return
	_ok("...and its muzzle resolved, or the rounds spawn at the weapon's origin",
			b.weapon.muzzle_origin != null)

	# PROJECTED FLAT, and that is the point. The 54-degree cant means the raw
	# bore and the turret's forward can NEVER agree, so a test that compares
	# them unprojected fails and looks like a mount-yaw bug. Flat, they must
	# agree: the launcher points where the turret is pointed, and the elevation
	# is a separate axis.
	var bore: Vector3 = (b.weapon as Node3D).global_transform.basis.x
	bore.y = 0.0
	var fwd: Vector3 = b._turret_forward()
	_ok("...and it points where the turret is pointed, in plan",
			bore.normalized().dot(fwd.normalized()) > 0.9,
			"dot %.3f" % bore.normalized().dot(fwd.normalized()))
	# AND THE MUZZLE IS OUTSIDE THE FRAME. The pack is 1.375 m long on a mount
	# at the breech plane, so it overhangs the 0.78 m cradle rails — which is
	# the read build_picket.gd:242-246 intended. A muzzle inside the hull
	# capsule means the pack was built backwards along its own axis.
	var muzzle: Vector3 = (b.weapon.muzzle_origin as Node3D).global_position
	var flat: float = Vector2(muzzle.x - (b as Node3D).global_position.x,
			muzzle.z - (b as Node3D).global_position.z).length()
	_ok("...with its muzzle clear of the hull, not inside it", flat > 0.8,
			"%.2f m out from the body axis" % flat)
	b.free()
	await process_frame
