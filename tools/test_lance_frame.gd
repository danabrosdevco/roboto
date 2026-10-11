extends SceneTree

# ─────────────────────────────────────────────
# THE LANCE — the frame, not the weapon.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_lance_frame.gd
#
# NOT tools/test_lance.gd. That file exists and is the melee REPAIR LANCE
# weapon suite ("THE LANCE HAS TO CONNECT"). Overwriting it would delete a
# shipped suite and tools/test.sh would still print PASS.
#
# WHAT IS WORTH GUARDING HERE are the four things that make this a Lance rather
# than a small Rover, none of which errors if it breaks:
#
#   * turret = false ON THE DEFINITION. The frame's identity as data. Flip it
#     and ChassisDefinition.takes() starts applying the whitelist rule, which
#     means every weapon in the game would have to name the Lance — and the
#     frame inherits the Bulwark's hole: armable exactly once, then
#     un-refittable forever.
#
#   * turret != null IN THE SCENE. The opposite, and the obvious
#     "simplification" for a turretless frame. `hull_spoils_aim`
#     (enemy.gd:2895) is excused by a node property NAMED turret being
#     non-null, not by the definition's flag, so clearing it means a moving
#     Lance never settles its aim and never leaves WeaponState.AIM.
#
#   * THE SPEED IS ON THE SCENE, NOT ON THE DEFINITION. base_speed is a
#     MULTIPLIER (soldier_record.gd:254 -> squad_spawner.gd:349). The design
#     doc's 1.35 was already baked into move_speed = 9.45 by the generator, so
#     putting 1.35 on the definition as well gives 12.76 m/s. Asserted as a
#     PRODUCT so the double count cannot come back when someone "corrects" the
#     definition against the design doc.
#
#   * THE Allowed*Options ARRAYS. Empty is the failure mode and empty looks
#     like nothing: roll_combat_action returns at enemy.gd:3053 on an empty
#     combat array, so _commit_burst and _enter_aim_stance never run and the
#     frame moves only when its squad tells it to. check_frame.gd does not
#     check these.
#
# The geometry is deliberately NOT asserted — test_bulwark.gd:22-23: shapes are
# judged by looking at them, and a test that pins box sizes only makes the
# model harder to tune. Measurement belongs in tools/check_frame.gd.
# ─────────────────────────────────────────────

const LANCE := "res://Character/characters/ai/lance.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_lance.tres"
const ROVER_CHASSIS := "res://Campaign/chassis/chassis_rover.tres"
const CANNON := "res://Campaign/items/item_light_cannon.tres"
const NANITE := "res://Campaign/items/item_nanite_reboot.tres"
const M4 := "res://Campaign/items/item_m4.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const CANNON_SCENE := "res://Character/weapon/ai-wep_light_cannon.tscn"
# kill_kinds.gd declares no class_name and is not an autoload, so it has to be
# preloaded. bake_icons.gd:22 and test_quadcopter.gd:25 do the same.
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_the_weapon()
	await _test_the_frame_is_wired()
	await _test_the_eye_keeps_its_own_colour()
	await _test_a_weapon_fits_the_nose()
	await _test_the_aim_settles_moving_and_still()
	await _test_a_parked_lance_comes_round()

	print("")
	if _fails == 0:
		print("ALL LANCE FRAME CHECKS PASS")
	else:
		print("LANCE FRAME FAILURES: %d" % _fails)
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
	_ok("...and names itself lance", def.id == &"lance", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	_ok("...one weapon slot", int(def.weapon_slots) == 1, "%d" % int(def.weapon_slots))
	_ok("...and no coax", String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	# THE FRAME'S IDENTITY AS DATA. See the header.
	_ok("...and it has NO TURRET", bool(def.turret) == false)
	_ok("...it drives", bool(def.drives))
	_ok("...and musters with the armour", bool(def.vehicle))
	_ok("...it is the cheapest seat on the sheet", int(def.supply) == 1,
			"%d" % int(def.supply))
	_ok("...and it is on sale", bool(def.purchasable))
	_ok("...issued with the light cannon",
			def.starting_weapon_id == &"light_cannon", str(def.starting_weapon_id))

	# THE SPEED, AS A PRODUCT. See the header: 1.0 here and 9.45 on the scene,
	# or 1.35 here and 12.76 m/s in the game.
	_ok("base_speed is neutral, not the design doc's 1.35",
			absf(float(def.base_speed) - 1.0) < 0.001, "%.2f" % float(def.base_speed))
	var body := _spawn(LANCE)
	await process_frame
	var scene_speed: float = float(body.get("move_speed"))
	var product: float = float(def.base_speed) * scene_speed
	_ok("...and frame x scene lands between 9 and 10 m/s",
			product > 9.0 and product < 10.0,
			"%.2f x %.2f = %.2f" % [float(def.base_speed), scene_speed, product])
	body.free()
	await process_frame

	# IN THE CATALOGUE, which is what actually puts it in the shop — and the
	# WEAPON too, which FRAME_ANATOMY.md's buyable checklist does not list:
	# _fit_loadout resolves the gun with cat.item(id) and `continue`s on null
	# (squad_spawner.gd:304-306), so a Lance whose gun is missing from the
	# catalogue deploys UNARMED and nothing warns.
	var cat = load(CATALOGUE)
	var frames: Array = []
	for c in cat.chassis:
		frames.append(String(c.id) if c != null else "<null>")
	_ok("...and the catalogue carries the frame", frames.has("lance"), str(frames))
	var items: Array = []
	for it in cat.items:
		items.append(String(it.id) if it != null else "<null>")
	_ok("...and the catalogue carries its gun, or it deploys unarmed",
			items.has("light_cannon"), str(items))

	# The debrief, the roster glyph and the icon bake all go through this.
	_ok("KillKinds knows the frame", _KillKinds.FRAMES.has(&"lance"))
	_ok("...and resolves it to a definition", _KillKinds.frame_of(&"lance") != null)


# ─────────────────────────────────────────────
func _test_the_weapon() -> void:
	var gun = load(CANNON)
	_ok("the light cannon loads", gun != null)
	if gun == null:
		return
	_ok("...and is a weapon", int(gun.kind) == 0, "%d" % int(gun.kind))
	_ok("...a robot can carry it", gun.fits_ai())
	_ok("...and it goes on something that drives", bool(gun.fits_vehicles))
	_ok("...and it has an AI scene", gun.ai_scene != null)

	var frame = load(CHASSIS)
	_ok("the Lance takes it", frame.takes(gun))
	# THE DESIGN'S LOAD-BEARING EXCLUSION. A cheap vehicle that self-revives
	# makes the robot on foot pointless, and the `drives` refusal is the whole
	# of what keeps nanites off it.
	_ok("...and refuses nanites, because it drives", not frame.takes(load(NANITE)))
	_ok("...and refuses a rifle off the rack", not frame.takes(load(M4)))
	# AND IT CANNOT LEAK ONTO THE ROVER, which is the frame the Lance exists to
	# be cheaper than. The Rover is turret = true and the gun's whitelist does
	# not name it.
	_ok("...and the Rover cannot mount it", not load(ROVER_CHASSIS).takes(gun))

	var w: Node = load(CANNON_SCENE).instantiate()
	root.add_child(w)
	await process_frame
	# SINGLE SHOT IS ON THE WEAPON. Left at 0, burst_min/burst_max defer to the
	# body's 2-5 (lance.tscn, _commit_burst at enemy.gd:3959-3971), which on a
	# 1.6 s cycle is an eight-second burst.
	_ok("the cannon fires one round at a time", int(w.burst_min) == 1
			and int(w.burst_max) == 1,
			"%d-%d" % [int(w.burst_min), int(w.burst_max)])
	_ok("...and it is hitscan, not melee", int(w.weapon_type) == 1,
			"%d" % int(w.weapon_type))
	# min_damage AND damage_falloff_start ARE THE FIELDS THE DESIGN DOC FORGOT.
	# Left at the defaults (18 / 20 m) an 85 m gun loses most of its damage
	# inside its own range band and the "hits hard for the supply" promise is
	# gone by 60 m.
	_ok("...and it still hurts at the end of its reach",
			w.calculate_damage(85.0) >= 30,
			"%d at 85 m" % int(w.calculate_damage(85.0)))
	_ok("...and it can shoot something on top of it",
			float(w.min_effective_range) <= 0.0)
	w.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_frame_is_wired() -> void:
	var b := _spawn(LANCE)
	await process_frame

	# IN THE GROUP EVERY HOSTILE SWEEP USES, and in the one EMP uses.
	# add_to_group is not persistent by default, so a group added in code never
	# reaches the saved scene and nothing anywhere errors.
	_ok("the frame is in the \"enemies\" group", b.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it",
			b.is_in_group(AI.SIGNAL_GROUP))
	_ok("...and it does not take cover, because it is cover", not b.takes_cover())

	for pair in [["rig", b.get("rig")], ["turret", b.get("turret")],
			["gun_pivot", b.get("gun_pivot")], ["nav_agent", b.get("nav_agent")],
			["weapon_mount", b.get("weapon_mount")], ["bark", b.get("bark")],
			["detection", b.get("detection")]]:
		_ok("...%s resolved" % str(pair[0]), pair[1] != null)

	# THE STUB TURRET MUST STAY A STUB, AND MUST STAY WIRED. Both halves, with
	# the reason, because each one is a plausible tidy-up that breaks the frame
	# in a different direction. See the header.
	_ok("the stub turret is still wired, so a moving Lance can settle its aim",
			b.get("turret") != null)
	_ok("...and still traverses nothing, so it is not a turret frame",
			absf(float(b.get("turret_traverse_degrees"))) < 0.001,
			"%.2f deg/s" % float(b.get("turret_traverse_degrees")))

	# THE THREE WHEELS AND THEIR STEER WEIGHTS. rover.gd:195-196 warns when the
	# sizes disagree and the castor silently stops steering.
	var wheels: Array = b.get("wheels")
	var steer: Array = b.get("wheel_steer")
	_ok("it has three wheels", wheels.size() == 3, "%d" % wheels.size())
	_ok("...each with a steer weight", wheels.size() == steer.size(),
			"%d wheels, %d weights" % [wheels.size(), steer.size()])

	# THE Allowed*Options ARRAYS, which check_frame.gd does not check. Both the
	# CONTENTS and the TYPE: a typed array handed an untyped one packs as [] in
	# silence, and [] is the single biggest live defect in this batch of frames.
	var mv: Array = b.get("AllowedMovementOptions")
	var cb: Array = b.get("AllowedCombatOptions")
	_ok("it is allowed to advance, fall back and chase",
			Array(mv) == [0, 2, 4], str(mv))
	_ok("...and to move, aim and fire", Array(cb) == [0, 1, 2], str(cb))
	_ok("...and the movement array is really Array[int]",
			mv.get_typed_builtin() == TYPE_INT, "%d" % mv.get_typed_builtin())
	_ok("...and the combat array is too",
			cb.get_typed_builtin() == TYPE_INT, "%d" % cb.get_typed_builtin())

	_ok("death effects are wired", (b.get("particle_effects_die") as Array).size() > 0)
	_ok("hit effects are wired", (b.get("particle_effects_hit") as Array).size() > 0)
	_ok("visible_pieces is wired", (b.get("visible_pieces") as Array).size() > 0)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_eye_keeps_its_own_colour() -> void:
	# THE EYE IS NOT FACTION KIT. Every robot in this game is identified by one
	# offset eye, and an eye that turns blue for one side and red for the other
	# stops being an identifying feature. The failure mode is the typed-array
	# one again: FactionLivery.pieces is typed, an untyped assignment saves as
	# [], and the livery then falls back to walking the whole frame and paints
	# the eye with everything else. So this is about the array being POPULATED
	# as much as about colour.
	var b := _spawn(LANCE)
	await process_frame
	var liv = b.get_node_or_null("FactionLivery")
	var eye = b.find_child("Eye", true, false)
	_ok("the frame has an eye", eye != null)
	_ok("...and a livery", liv != null)
	if eye == null or liv == null:
		b.free()
		return
	_ok("the livery names its pieces explicitly", liv.pieces.size() > 0,
			"%d — empty means it walks the whole frame instead" % liv.pieces.size())
	_ok("...and the eye is not one of them", not liv.pieces.has(eye))

	liv.apply(Enums.Factions.ENEMY)
	await process_frame
	var m = eye.material_override
	_ok("...so a repaint leaves the eye alone",
			m != null and m is StandardMaterial3D,
			"eye wears %s" % ("null" if m == null else m.get_class()))
	var hull = b.find_child("Hull", true, false)
	_ok("...while the hull did take the faction coat",
			hull != null and hull.material_override is ShaderMaterial)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_a_weapon_fits_the_nose() -> void:
	var b := _spawn(LANCE)
	await process_frame
	var mount = b.get("weapon_mount")
	var pivot = b.get("gun_pivot")
	if mount == null or pivot == null:
		_ok("the nose has a mount and a pivot", false)
		b.free()
		return
	# The mount must ride the pivot, or elevating the gun leaves it behind.
	_ok("the mount rides the gun pivot", pivot.is_ancestor_of(mount))
	# THE MOUNT YAW. check_frame.gd asserts this too; duplicating it is cheap
	# and the Bulwark fired backwards for want of it. A weapon's muzzle is its
	# own +X, so every frame's WeaponMount is yawed +PI/2 to put that on the
	# body's -Z.
	_ok("...and is yawed +90 degrees, so a gun points where the hull does",
			absf((mount as Node3D).rotation.y - PI * 0.5) < 0.01,
			"%.1f deg" % rad_to_deg((mount as Node3D).rotation.y))

	b.equip_weapon_scene(load(CANNON_SCENE))
	await process_frame
	await physics_frame
	var gun = b.get("weapon")
	_ok("...and the cannon fits it", gun != null)
	if gun != null:
		# A WEAPON'S MUZZLE IS ITS OWN +X — ai-wep_*.tscn put their Muzzle node
		# at local +X, which is the whole reason the mount is yawed. Checked
		# against the BODY's forward rather than a number, so the assertion
		# still means something if the convention ever changes.
		var muzzle: Vector3 = (gun as Node3D).global_transform.basis.x.normalized()
		var fwd: Vector3 = -(b as Node3D).global_transform.basis.z.normalized()
		_ok("...pointing where the frame is facing", muzzle.dot(fwd) > 0.9,
				"dot %.3f" % muzzle.dot(fwd))
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_aim_settles_moving_and_still() -> void:
	# THE STUB TURRET'S WHOLE PURPOSE, asserted both ways so the behaviour is a
	# DECISION and not an accident. `hull_spoils_aim` (enemy.gd:2895) is excused
	# by the node property being non-null, so a Lance settles its aim while
	# driving — which is what makes a frame that aims by driving possible at
	# all. If someone clears `turret`, this is the test that says what broke.
	# THE MARKER IS AT 200 m, PAST THE CANNON'S 85 m REACH, ON PURPOSE. The
	# settle timer accumulates at the top of handle_weapon_logic on LOS alone,
	# while the AIM branch below returns early on `dist > max_range` — so the
	# frame builds its sight picture for the full three seconds and never
	# reaches FIRE, which would call fire() and run a real hitscan into the
	# level against the marker body. Reaching FIRE is measured separately,
	# below, by breaking the moment the state flips.
	for moving in [false, true]:
		var z: float = 600.0 if not moving else 700.0
		var b := _spawn(LANCE, Vector3(600, 0, z))
		var mark := _spawn(LANCE, Vector3(600, 0, z - 200.0))
		await process_frame
		b.equip_weapon_scene(load(CANNON_SCENE))
		b.ai_state = b.AIState.COMBAT
		b.combat_target = mark
		b.weapon_target = (mark as Node3D).global_position
		if moving:
			b.velocity = Vector3(0, 0, -6.0)
			_ok("...and the frame counts as moving", b._is_moving())
		for _i in 180:
			b.set("_has_los", true)
			b.handle_weapon_logic(1.0 / 60.0)
			b._update_facing(1.0 / 60.0)
		var tracking: float = float(b.get("_aim_tracking"))
		_ok("a %s Lance settles its aim" % ("moving" if moving else "stationary"),
				tracking > 1.0, "_aim_tracking %.2f" % tracking)
		b.free()
		mark.free()
		await process_frame

	# ...and a settled Lance actually gets to pull the trigger. Thirty metres,
	# dead ahead, so it is inside both the range band and the 6 degree cone.
	var s := _spawn(LANCE, Vector3(900, 0, 900))
	var t := _spawn(LANCE, Vector3(900, 0, 870))
	await process_frame
	s.equip_weapon_scene(load(CANNON_SCENE))
	s.ai_state = s.AIState.COMBAT
	s.combat_target = t
	s.weapon_target = (t as Node3D).global_position
	var reached_fire: bool = false
	for _i in 180:
		s.set("_has_los", true)
		s.handle_weapon_logic(1.0 / 60.0)
		if int(s.weapon_state) == s.WeaponState.FIRE:
			reached_fire = true
			break
	_ok("...and a stationary Lance gets as far as WeaponState.FIRE", reached_fire,
			"weapon_state %d, _aim_tracking %.2f"
			% [int(s.weapon_state), float(s.get("_aim_tracking"))])
	s.free()
	t.free()
	await process_frame


func _test_a_parked_lance_comes_round() -> void:
	# THE WHOLE JUSTIFICATION FOR lance.gd IN ONE TEST.
	#
	# rover.gd's _update_facing takes the turret branch and never calls super(),
	# so Enemy._update_facing — the only thing that writes rotation.y from a
	# bearing — never runs; and with turret_traverse_degrees = 0.0 the stub
	# cannot rotate either. The hull's one other source of yaw is driven by
	# distance travelled, which parked is zero. Without lance.gd a stationary
	# Lance can only ever shoot what is already inside six degrees of its nose.
	#
	# IF THIS PASSES WITHOUT lance.gd, THE FILE IS NOT NEEDED. Say so and
	# delete it.
	var b := _spawn(LANCE, Vector3(800, 0, 800))
	var mark := _spawn(LANCE, Vector3(830, 0, 800))   # 90 degrees off the nose
	await process_frame
	b.equip_weapon_scene(load(CANNON_SCENE))
	b.ai_state = b.AIState.COMBAT
	b.combat_target = mark
	b.weapon_target = (mark as Node3D).global_position
	b.movement_state = b.MovementState.NONE
	var before: float = (b as Node3D).rotation.y
	_ok("the frame has a hull slew of its own", b.get("hull_slew_degrees") != null)
	for _i in 180:   # three seconds
		b._update_facing(1.0 / 60.0)
	var turned: float = absf(rad_to_deg((b as Node3D).rotation.y - before))
	_ok("a parked Lance brings its hull round onto a target off its nose",
			turned > 30.0, "turned %.1f deg in 3 s" % turned)
	_ok("...and ends with the gun bearing", b._weapon_on_target())
	# AND SLOWLY ENOUGH TO STILL BE FLANKABLE. Getting alongside it is the
	# counter the frame is balanced around; a hull that snaps round is a turret
	# with extra steps.
	_ok("...without snapping round like a turret",
			float(b.get("hull_slew_degrees")) <= 60.0,
			"%.0f deg/s" % float(b.get("hull_slew_degrees")))
	b.free()
	mark.free()
	await process_frame
