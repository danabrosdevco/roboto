extends SceneTree

# ─────────────────────────────────────────────
# THE BASTION
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_bastion.gd
#
# WHAT IS WORTH GUARDING HERE is the hardening field, and specifically the
# STAMP design in ai.gd. The field is the only mechanic in the game that raises
# somebody else's signal_resistance, and every obvious way of writing it leaves
# a robot permanently hardened in silence:
#
#   * mutate-on-entry / divide-on-exit: two overlapping Bastions double it and
#     only one divides back, and one that dies mid-effect never divides back at
#     all;
#   * recompute-per-tick-on-the-receiver: a receiver frozen by the distance
#     cull has its _physics_process switched off, so it cannot recompute and
#     keeps what it was last given, forever.
#
# So the two assertions that matter most are "it lapses after the Bastion
# dies" and "it is still correct on a CULLED receiver, and still lapses". The
# second is the one that distinguishes this design from the one the design doc
# proposed, and the one the whole of ai.gd's addition exists for.
#
# After that: ALLY MEANS SAME FACTION. are_hostile(HOME, SWARM) is false by
# design, so a "not hostile" filter would harden Swarm, Argus and NEUTRAL too —
# a Bastion making somebody else's army tougher, with nothing warning.
#
# AND ai.gd IS THE BASE OF EVERY ROBOT AND THE PLAYER. The two lines this
# frame changed are in the suppression and EMP-lock paths, so the real
# regression evidence for this frame is the WHOLE of tools/test.sh — this
# suite plus test_signal.gd green — not this suite alone.
# ─────────────────────────────────────────────

const BASTION := "res://Character/characters/ai/bastion.tscn"
const SOLDIER := "res://Character/characters/ai/soldier_rifle.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_bastion.tres"
const BULWARK_CHASSIS := "res://Campaign/chassis/chassis_bulwark.tres"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const HEAVY_MG := "res://Campaign/items/item_heavy_mg.tres"
const PROJECTOR := "res://Campaign/items/item_shield_projector.tres"
const _KillKinds := preload("res://Campaign/kill_kinds.gd")

var _fails: int = 0


func _init() -> void:
	await _test_hostility()
	await _test_the_chassis_is_registered()
	await _test_it_is_not_in_the_player_catalogue()
	await _test_the_gun_fits_and_keeps_fitting()
	await _test_the_scene()
	await _test_a_weapon_points_forward()
	await _test_planted_versus_walking()
	await _test_it_refuses_orders_while_planted()
	await _test_the_field_picks_its_side()
	await _test_the_field_does_not_stack()
	await _test_the_field_lapses()
	await _test_the_field_survives_a_culled_receiver()
	await _test_suppression_lands_less_hard()
	await _test_the_eye_and_lenses_keep_their_own_colour()

	print("")
	if _fails == 0:
		print("ALL BASTION CHECKS PASS")
	else:
		print("BASTION FAILURES: %d" % _fails)
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


func _note(label: String, cond: bool, detail: String) -> void:
	print("%s  %s%s" % ["PASS" if cond else "TODO", label, "" if cond else ("  " + detail)])


func _spawn(path: String, at: Vector3 = Vector3.ZERO, faction: int = Enums.Factions.HOME,
		ticking: bool = false) -> Node:
	var body: Node = load(path).instantiate()
	body.faction = faction
	root.add_child(body)
	(body as Node3D).global_position = at
	body.set_physics_process(ticking)
	body.set_process(false)
	# _ready is deferred in a --script run, and Enemy.initialize() awaits an
	# IDLE frame before setting frame_waited. Pump both or the frame is inert.
	for _i in 4:
		await physics_frame
		await process_frame
	return body


# ─────────────────────────────────────────────
func _test_hostility() -> void:
	print("── Home Command is a faction that can be fought ──")
	_ok("hostile to the player, outbound",
		Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.HOME))
	_ok("hostile to the player, inbound",
		Enums.are_hostile(Enums.Factions.HOME, Enums.Factions.PLAYER))
	_ok("hostile to the player's squad, both ways",
		Enums.are_hostile(Enums.Factions.ALLIED, Enums.Factions.HOME)
		and Enums.are_hostile(Enums.Factions.HOME, Enums.Factions.ALLIED))
	# THE FIELD'S "SAME FACTION, NOT NOT-HOSTILE" FILTER DEPENDS ON THIS BEING
	# FALSE. Asserted here so the day somebody makes the enemy factions
	# mutually hostile, this test says why it matters.
	_ok("NOT hostile to the Swarm or Argus",
		not Enums.are_hostile(Enums.Factions.HOME, Enums.Factions.SWARM)
		and not Enums.are_hostile(Enums.Factions.HOME, Enums.Factions.ARGUS))


func _test_the_chassis_is_registered() -> void:
	print("")
	print("── registered ──")
	var frame := load(CHASSIS) as ChassisDefinition
	_ok("chassis_bastion.tres loads", frame != null)
	if frame == null:
		return
	_ok("id is bastion", frame.id == &"bastion", str(frame.id))
	_ok("supply 3", frame.supply == 3, str(frame.supply))
	_ok("cost 0", frame.cost == 0)
	_ok("not purchasable", frame.purchasable == false)
	_ok("one weapon slot", frame.weapon_slots == 1, str(frame.weapon_slots))
	_ok("it deploys with the heavy MG", frame.starting_weapon_id == &"heavy_mg",
		str(frame.starting_weapon_id))
	# enemy.gd computes hull_spoils_aim from `turret` being non-null, and
	# chassis turret = true is what restricts the slot to whitelisted guns.
	_ok("turret flag true", frame.turret == true)
	# FRAME_ANATOMY §6.12: giving a one-mount frame a coax pool warns per body
	# per mission. The model has exactly one WeaponMount.
	_ok("no coax", frame.coax_weapon_id == &"", str(frame.coax_weapon_id))
	_ok("sensor range 60", is_equal_approx(frame.base_sensor_range, 60.0))
	_note("in KillKinds.FRAMES", _KillKinds.FRAMES.has(&"bastion"),
		"add &\"bastion\": \"%s\" to kill_kinds.gd" % CHASSIS)


func _test_it_is_not_in_the_player_catalogue() -> void:
	print("")
	print("── and deliberately NOT buyable ──")
	var cat = load(CATALOGUE)
	_ok("the catalogue loads", cat != null)
	if cat == null:
		return
	var chassis_present := false
	for c in cat.chassis:
		if c != null and c.id == &"bastion":
			chassis_present = true
	var item_present := false
	for i in cat.items:
		if i != null and i.id == &"shield_projector":
			item_present = true
	_ok("no bastion entry in the player catalogue", not chassis_present)
	_ok("no shield_projector entry either", not item_present)


# THE BULWARK'S BUG, CAUGHT AT THE POINT IT WOULD BE INTRODUCED.
# ChassisDefinition.takes() refuses heavy_mg twice over for a turret = true
# frame unless the frame's id is in the item's chassis_whitelist — while
# starting_weapon_id bypasses takes() entirely. So the frame deploys armed and
# can never be refitted, and nothing warns.
func _test_the_gun_fits_and_keeps_fitting() -> void:
	print("")
	print("── the gun fits, and keeps fitting ──")
	var frame := load(CHASSIS) as ChassisDefinition
	var mg := load(HEAVY_MG) as ItemDefinition
	var proj := load(PROJECTOR) as ItemDefinition
	_ok("item_heavy_mg.tres loads", mg != null)
	if frame == null or mg == null:
		return
	_ok("the Bastion takes the heavy MG", frame.takes(mg),
		"add &\"bastion\" to item_heavy_mg.tres's chassis_whitelist")
	# The family sweep: the Bulwark has the identical hole and the same line
	# closes both.
	var bulwark := load(BULWARK_CHASSIS) as ChassisDefinition
	_ok("and so does the Bulwark, which had the same hole",
		bulwark != null and bulwark.takes(mg))
	_ok("item_shield_projector.tres loads", proj != null)
	if proj == null:
		return
	# NOT the repair lance's mistake: that is kind = 0 with no ai_scene and
	# usable_by_ai = false, so fits_ai() is false and no robot can carry it.
	_ok("the projector is actually fittable by a robot", proj.fits_ai())
	_ok("the Bastion takes the projector", frame.takes(proj))
	_ok("and nothing else does",
		proj.chassis_whitelist.size() == 1 and proj.chassis_whitelist[0] == &"bastion",
		str(proj.chassis_whitelist))
	_ok("it is not in the shop", proj.in_shop == false)
	_ok("it does no damage", proj.weapon_damage == 0)


func _test_the_scene() -> void:
	print("")
	print("── the scene ──")
	var body = await _spawn(BASTION)
	_ok("the script is bastion.gd",
		body.get_script().resource_path == "res://Character/characters/ai/bastion.gd")
	_ok("it is a Soldier", body is Soldier)
	_ok("in the enemies group", body.is_in_group("enemies"))
	_ok("in the signal group", body.is_in_group(AI.SIGNAL_GROUP))
	# A null turret means enemy.gd:2893's hull_spoils_aim never lets it settle
	# its aim while moving.
	_ok("the turret node is non-null", body.turret != null)
	_ok("the gun pivot is non-null", body.gun_pivot != null)
	# THE LIVE DEFECT THE BRIEF NAMES. An empty combat array means
	# roll_combat_action returns, so _commit_burst is never called and
	# _burst_left stays 0: the frame still shoots, slowly, in single shots,
	# which reads as a feel problem rather than a bug. On a 14-26 round burst
	# gun that is most of what the weapon is.
	_ok("AllowedCombatOptions is [1, 2] — AIM and FIRE, never MOVE",
		body.AllowedCombatOptions == [1, 2], str(body.AllowedCombatOptions))
	# Empty is correct HERE because MOVE is off the combat array, so
	# _pick_movement_option is unreachable from the combat timer; the walking
	# half of its life is driven by squad orders.
	_ok("AllowedMovementOptions is empty, deliberately",
		body.AllowedMovementOptions.is_empty(), str(body.AllowedMovementOptions))
	_ok("both arrays are typed int",
		body.AllowedCombatOptions.get_typed_builtin() == TYPE_INT
		and body.AllowedMovementOptions.get_typed_builtin() == TYPE_INT)
	# The hardening frame is itself hardened. On the scene, because
	# ChassisDefinition has no signal field.
	_ok("signal_resistance 2.0 on the scene", is_equal_approx(body.signal_resistance, 2.0),
		str(body.signal_resistance))
	# Slower than the Walker's 55 and the Bulwark's 42: flanking a hardpoint is
	# the counter and it should be a real one.
	_ok("turret traverse 34 degrees", is_equal_approx(body.turret_traverse_degrees, 34.0))
	_ok("takes no cover", body.takes_cover() == false)
	_ok("visible_pieces non-empty", not body.visible_pieces.is_empty())
	_ok("particle_effects_die non-empty", not body.particle_effects_die.is_empty())
	_ok("particle_effects_hit non-empty", not body.particle_effects_hit.is_empty())
	body.free()


# build_bastion.gd records that the Bulwark's first build had this sign
# backwards: the gun fitted, elevated, tracked and fired directly BEHIND the
# frame, and nothing warned.
func _test_a_weapon_points_forward() -> void:
	print("")
	print("── a fitted weapon points where the turret does ──")
	var body = await _spawn(BASTION)
	var mount = body.weapon_mount
	_ok("the mount exists", mount != null)
	if mount == null:
		body.free()
		return
	_ok("the mount rides the gun pivot", body.gun_pivot.is_ancestor_of(mount))
	var gun: Node = load("res://Character/weapon/ai-wep_heavy_mg.tscn").instantiate()
	mount.add_child(gun)
	await process_frame
	await physics_frame
	# Checked against the BODY's forward rather than a number, so the test
	# still means something if the convention changes.
	var muzzle: Vector3 = (mount as Node3D).global_transform.basis.x.normalized()
	var fwd: Vector3 = -(body as Node3D).global_transform.basis.z.normalized()
	_ok("a fitted weapon points where the frame is facing",
		muzzle.dot(fwd) > 0.9, "dot %.3f" % muzzle.dot(fwd))
	body.free()
	await process_frame


func _test_planted_versus_walking() -> void:
	print("")
	print("── planted and walking are two different objects ──")
	var body = await _spawn(BASTION)
	# SCENE VALUES BEAT SCRIPT DEFAULTS, and the scene IS the planted state.
	_ok("it is born planted", body.stance == body.Stance.PLANTED, str(body.stance))
	_ok("and born stationary", is_equal_approx(body.move_speed, 0.0), str(body.move_speed))
	_ok("the canopy is lit while planted",
		body._lens_material != null and body._lens_material.emission_energy_multiplier > 0.0)
	var ram: Node3D = body.get_node("Rig/Outriggers/OutriggerF/Ram")
	var planted_lean: float = ram.rotation.x
	_ok("the front outrigger is leaning in, 28 degrees",
		is_equal_approx(rad_to_deg(planted_lean), 28.0), "%.1f deg" % rad_to_deg(planted_lean))
	_ok("all four rams and both skirts were collected",
		body._rams.size() == 4 and body._skirts.size() == 2,
		"%d rams, %d skirts" % [body._rams.size(), body._skirts.size()])
	# The brackets are HULL and hang off the container rather than the hinges
	# precisely so the stow cannot catch them.
	var bracket: Node3D = body.get_node("Rig/Skirts/BracketL")
	var bracket_before: Vector3 = bracket.rotation

	body._set_stance_pose(0.0)   # fully stowed, without waiting out the tween
	_ok("stowed, the outrigger folds flat", is_equal_approx(ram.rotation.x, 0.0),
		"%.3f" % ram.rotation.x)
	_ok("stowed, the mast lies down",
		is_equal_approx(body._mast.rotation.x, body.MAST_STOWED_X),
		"%.3f" % body._mast.rotation.x)
	# A STOW HAS TO DRIVE BOTH THE MAST AND THE CANOPY or the hoop ends up on
	# edge: the canopy counter-rotates to keep it level.
	_ok("and the canopy counter-rotates to keep the hoop level",
		is_equal_approx(body._canopy.rotation.x, -body.MAST_STOWED_X),
		"%.3f" % body._canopy.rotation.x)
	_ok("stowed, each apron swings up against the flank",
		absf(rad_to_deg(body._skirts[0].rotation.z)) > 70.0,
		"%.1f deg" % rad_to_deg(body._skirts[0].rotation.z))
	_ok("and the brackets did not move, because they are hull",
		bracket.rotation.is_equal_approx(bracket_before))

	body._set_stance_pose(1.0)   # and back
	_ok("replanting restores the lean exactly",
		is_equal_approx(ram.rotation.x, planted_lean), "%.3f" % ram.rotation.x)
	body.free()


# Without these a planted hardpoint is walked off its position by its own
# squad with its outriggers in the ground. Both are needed: perform_action(MOVE)
# reaches move_to directly without passing through order_move_to.
func _test_it_refuses_orders_while_planted() -> void:
	print("")
	print("── a planted Bastion refuses to be sent anywhere ──")
	var body = await _spawn(BASTION, Vector3.ZERO, Enums.Factions.HOME, true)
	var where: Vector3 = body.global_position
	body.order_move_to(Vector3(0, 0, 60), true)
	body.move_to(Vector3(0, 0, 60))
	for _i in 30:
		await physics_frame
	_ok("it has not moved", body.global_position.distance_to(where) < 0.5,
		"moved %.2f m" % body.global_position.distance_to(where))
	_ok("and it is still planted", body.stance == body.Stance.PLANTED)
	# enter_cover_seeking is belt-and-braces with the inherited
	# takes_cover() = false.
	body.enter_cover_seeking()
	_ok("asked to find cover, it stays where it is",
		body.soldier_state == body.SoldierState.NONE)
	body.free()


func _test_the_field_picks_its_side() -> void:
	print("")
	print("── the field hardens its OWN SIDE, and only inside the canopy ──")
	var bast = await _spawn(BASTION, Vector3.ZERO, Enums.Factions.HOME, true)
	var ally = await _spawn(SOLDIER, Vector3(5, 0, 0), Enums.Factions.HOME)
	var far = await _spawn(SOLDIER, Vector3(25, 0, 0), Enums.Factions.HOME)
	var swarm = await _spawn(SOLDIER, Vector3(0, 0, 5), Enums.Factions.SWARM)
	var neutral = await _spawn(SOLDIER, Vector3(0, 0, -5), Enums.Factions.NEUTRAL)
	bast._field_timer = 0.0
	for _i in 10:
		await physics_frame
	_ok("a same-faction neighbour inside the canopy is hardened",
		ally.effective_signal_resistance() > ally.signal_resistance,
		"%.2f vs %.2f" % [ally.effective_signal_resistance(), ally.signal_resistance])
	_ok("and by exactly field_bonus, additively",
		is_equal_approx(ally.effective_signal_resistance(),
			ally.signal_resistance + bast.field_bonus))
	_ok("one at 25 m is not", is_equal_approx(far.effective_signal_resistance(),
		far.signal_resistance))
	# §4.4's trap. are_hostile(HOME, SWARM) is FALSE, so a "not hostile" filter
	# would have hardened both of these.
	_ok("A SWARM NEIGHBOUR AT 5 m IS NOT HARDENED",
		is_equal_approx(swarm.effective_signal_resistance(), swarm.signal_resistance),
		"a 'not hostile' filter would harden somebody else's army")
	_ok("nor is a NEUTRAL one",
		is_equal_approx(neutral.effective_signal_resistance(), neutral.signal_resistance))
	_ok("and the Bastion does not harden itself on top of its own 2.0",
		is_equal_approx(bast.effective_signal_resistance(), bast.signal_resistance))
	bast.free(); ally.free(); far.free(); swarm.free(); neutral.free()


# MAX, NOT SUM. The design doc's own ceiling argument ("not a fight, a wall")
# is unenforceable under a sum.
func _test_the_field_does_not_stack() -> void:
	print("")
	print("── two overlapping Bastions are not twice as good as one ──")
	var a = await _spawn(BASTION, Vector3(100, 0, 0), Enums.Factions.HOME, true)
	var b = await _spawn(BASTION, Vector3(104, 0, 0), Enums.Factions.HOME, true)
	var ally = await _spawn(SOLDIER, Vector3(102, 0, 0), Enums.Factions.HOME)
	a._field_timer = 0.0
	b._field_timer = 0.0
	for _i in 10:
		await physics_frame
	_ok("the bonus is MAX, not SUM",
		is_equal_approx(ally.effective_signal_resistance(),
			ally.signal_resistance + a.field_bonus),
		"%.2f, expected %.2f" % [ally.effective_signal_resistance(),
			ally.signal_resistance + a.field_bonus])
	a.free(); b.free(); ally.free()


# THE FRAGILE CASE THE DESIGN DOC NAMES, and the reason for the expiry. Needs
# real elapsed TIME, not just frames — the expiry is on Time.get_ticks_msec.
func _test_the_field_lapses() -> void:
	print("")
	print("── and it comes off cleanly when the Bastion dies ──")
	var bast = await _spawn(BASTION, Vector3(200, 0, 0), Enums.Factions.HOME, true)
	var ally = await _spawn(SOLDIER, Vector3(203, 0, 0), Enums.Factions.HOME)
	bast._field_timer = 0.0
	for _i in 10:
		await physics_frame
	_ok("hardened to start with", ally.effective_signal_resistance() > ally.signal_resistance)
	var lit_before: bool = bast._lens_material.emission_energy_multiplier > 0.0
	bast.die()
	# The VISUAL has to go out in the same frame, or a dead Bastion still looks
	# like it is projecting. The stamp is allowed to lapse on its own clock.
	_ok("the canopy goes dark the frame it dies",
		lit_before and is_equal_approx(bast._lens_material.emission_energy_multiplier, 0.0))
	_ok("and the plant tween is dead, so nothing drives a freed node",
		bast._plant_tween == null)
	var waited := 0
	while waited < 240 and ally.effective_signal_resistance() > ally.signal_resistance:
		await physics_frame
		waited += 1
	_ok("the stamp lapses within a second or so",
		is_equal_approx(ally.effective_signal_resistance(), ally.signal_resistance),
		"still hardened after %d frames" % waited)
	bast.free(); ally.free()


# THE ASSERTION THAT DISTINGUISHES THE STAMP FROM A PER-TICK RECOMPUTE. A
# recompute would have to run on the receiver, and a culled receiver's tick is
# off — so it would keep whatever it was last given, forever.
func _test_the_field_survives_a_culled_receiver() -> void:
	print("")
	print("── and it is still right when the RECEIVER is frozen ──")
	var bast = await _spawn(BASTION, Vector3(300, 0, 0), Enums.Factions.HOME, true)
	var ally = await _spawn(SOLDIER, Vector3(303, 0, 0), Enums.Factions.HOME)
	bast._field_timer = 0.0
	for _i in 10:
		await physics_frame
	_ok("hardened to start with", ally.effective_signal_resistance() > ally.signal_resistance)
	# The receiver's tick goes off. Nothing on it can recompute anything now.
	ally.set_physics_process(false)
	ally.cull_frozen = true
	_ok("a frozen receiver still reads its bonus correctly",
		is_equal_approx(ally.effective_signal_resistance(),
			ally.signal_resistance + bast.field_bonus))
	bast.die()
	var waited := 0
	while waited < 240 and ally.effective_signal_resistance() > ally.signal_resistance:
		await physics_frame
		waited += 1
	_ok("and it STILL lapses, with the receiver's tick off",
		is_equal_approx(ally.effective_signal_resistance(), ally.signal_resistance),
		"still hardened after %d frames — this is the permanent-hardening bug" % waited)
	bast.free(); ally.free()


# ai.gd's TWO CHANGED LINES, END TO END. Asserting the accessor alone would
# pass with receive_signal_damage still dividing by the raw export.
func _test_suppression_lands_less_hard() -> void:
	print("")
	print("── suppression actually lands less hard ──")
	var soft = await _spawn(SOLDIER, Vector3(400, 0, 0), Enums.Factions.HOME)
	var bare = await _spawn(SOLDIER, Vector3(404, 0, 0), Enums.Factions.HOME)
	soft.add_hardening(0.6, 5.0)
	var soft_before: float = soft.signal_integrity
	var bare_before: float = bare.signal_integrity
	soft.receive_signal_damage(0.2)
	bare.receive_signal_damage(0.2)
	var soft_drop: float = soft_before - soft.signal_integrity
	var bare_drop: float = bare_before - bare.signal_integrity
	_ok("the hardened robot loses less signal", soft_drop < bare_drop,
		"%.4f vs %.4f" % [soft_drop, bare_drop])
	# lock_signal divides by the same figure: standing in the canopy shortens
	# an EMP lock as well as softening the hit.
	soft._signal_locked_t = 0.0
	bare._signal_locked_t = 0.0
	soft.lock_signal(4.0)
	bare.lock_signal(4.0)
	_ok("and an EMP lock is shorter on it", soft._signal_locked_t < bare._signal_locked_t,
		"%.2f vs %.2f" % [soft._signal_locked_t, bare._signal_locked_t])
	soft.free(); bare.free()


func _test_the_eye_and_lenses_keep_their_own_colour() -> void:
	print("")
	print("── the eye and the four canopy lenses keep their own material ──")
	var body = await _spawn(BASTION, Vector3(500, 0, 0))
	var livery: FactionLivery = null
	for child in body.get_children():
		if child is FactionLivery:
			livery = child
	_ok("the frame has a FactionLivery", livery != null)
	if livery == null:
		body.free()
		return
	var paths := ["Rig/Turret/Eye", "Rig/Mast/Canopy/Lenses/Lens0",
		"Rig/Mast/Canopy/Lenses/Lens1", "Rig/Mast/Canopy/Lenses/Lens2",
		"Rig/Mast/Canopy/Lenses/Lens3"]
	var nodes: Array[MeshInstance3D] = []
	var before: Array = []
	for p in paths:
		var n := body.get_node_or_null(p) as MeshInstance3D
		if n == null:
			continue
		nodes.append(n)
		before.append(n.material_override)
	_ok("the eye and all four lenses resolve", nodes.size() == 5, "found %d" % nodes.size())
	var listed := false
	for p in livery.pieces:
		if p in nodes:
			listed = true
	_ok("none of them is in the livery pieces array", not listed)
	livery.apply(Enums.Factions.HOME)
	var kept := true
	for i in nodes.size():
		if nodes[i].material_override != before[i]:
			kept = false
	# build_bastion.gd records that the Bulwark's eye ended up faction-coloured
	# despite being left off a list that was never there.
	_ok("all five kept their own material through apply()", kept)
	body.free()
