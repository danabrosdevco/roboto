extends SceneTree

# ─────────────────────────────────────────────
# THE BULWARK
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_bulwark.gd
#
# WHAT IS WORTH GUARDING HERE is not the model. It is the two things that make
# this frame different from a slow Walker, both of which are invisible in a
# headless run and neither of which would error if it broke:
#
#   * THE TORSO IS THE TURRET. `turret` points at the torso rather than a head,
#     which is what makes the shield swing round to face whatever the mech is
#     aiming at. Repoint it at a head node and nothing errors — the gun still
#     tracks, the frame still fights, and the shield just quietly stops
#     covering the direction the shooting is coming from.
#
#   * SIGNAL RESISTANCE. Standing in the lane is the whole job, and the frame
#     only survives it because suppression is divided before it lands. That
#     number lives in the scene, where an editor could clear it by accident.
#
# The geometry is deliberately NOT asserted. Shapes are judged by looking at
# them, and a test that pins box sizes only makes the model harder to tune.
# ─────────────────────────────────────────────

const BULWARK := "res://Character/characters/ai/bulwark.tscn"
const WALKER := "res://Character/characters/ai/walker.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_bulwark.tres"

var _fails: int = 0


func _init() -> void:
	await _test_the_chassis_is_registered()
	await _test_the_torso_is_the_turret()
	await _test_it_stands_in_the_lane()
	await _test_it_walks()
	await _test_the_eye_keeps_its_own_colour()
	await _test_a_weapon_fits_the_arm()
	await _test_the_arm_aims_without_the_torso()
	await _test_the_gun_arm_walks()
	await _test_the_shield_stops_rounds()

	print("")
	if _fails == 0:
		print("ALL BULWARK CHECKS PASS")
	else:
		print("BULWARK FAILURES: %d" % _fails)
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
	_ok("...and names itself bulwark", def.id == &"bulwark", str(def.id))
	_ok("...and carries a scene", def.scene != null)
	# ONE WEAPON AND NO COAX. The Walker's two mounts are its identity; if this
	# frame quietly grew a coax it would be a Walker with a shield bolted on
	# and there would be no reason to field the Walker at all.
	_ok("...one weapon slot, not the Walker's two", int(def.weapon_slots) == 1,
			"%d" % int(def.weapon_slots))
	_ok("...and no coax", String(def.coax_weapon_id) == "", str(def.coax_weapon_id))
	_ok("...slower than the Walker", float(def.base_speed) < 1.0,
			"%.2f" % float(def.base_speed))
	# It is in the catalogue, which is what actually puts it in the shop.
	var cat = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var ids: Array = []
	for c in cat.chassis:
		ids.append(String(c.id))
	_ok("...and the catalogue carries it", ids.has("bulwark"), str(ids))


func _test_the_torso_is_the_turret() -> void:
	var b := _spawn(BULWARK)
	await process_frame
	var turret = b.get("turret")
	var shield = b.get("shield")
	_ok("the frame has a turret node", turret != null)
	_ok("...and a shield", shield != null)
	if turret == null or shield == null:
		b.free()
		return
	# THE ASSERTION THAT MATTERS. The shield has to be a DESCENDANT of whatever
	# `turret` points at, or traversing to a target leaves the shield pointing
	# wherever it was. Checked by walking up the tree rather than by comparing
	# node names, so renaming anything cannot quietly satisfy it.
	var n: Node = shield
	var under: bool = false
	while n != null:
		if n == turret:
			under = true
			break
		n = n.get_parent()
	_ok("...and the shield turns with the turret", under,
			"shield is not under %s" % str(turret))
	# The gun arm too, or the weapon would not traverse with the body.
	var mount = b.get("weapon_mount")
	_ok("...as does the weapon mount", mount != null and turret.is_ancestor_of(mount))
	_ok("it does not take cover, because it is cover", not b.takes_cover())
	# IN THE GROUP EVERY HOSTILE SWEEP USES. Missed on the first build, because
	# add_to_group is not persistent by default and so the group never reached
	# the saved scene. Nothing anywhere errors: the frame walks, aims and
	# shoots, and is simply invisible to AIManager, to EMP and to every hostile
	# lookup in the game.
	_ok("...and it is in the \"enemies\" group", b.is_in_group("enemies"))
	_ok("...and in the signal group, so EMP can find it",
			b.is_in_group(AI.SIGNAL_GROUP))
	b.free()
	await process_frame


func _test_it_stands_in_the_lane() -> void:
	# The resistance has to actually divide incoming suppression, measured
	# against a Walker taking the identical hit — a number that is set but not
	# consulted would pass any check of the number alone.
	var b := _spawn(BULWARK, Vector3.ZERO)
	var w := _spawn(WALKER, Vector3(40, 0, 0))
	await process_frame
	_ok("the Bulwark resists signal damage", float(b.signal_resistance) > 1.0,
			"%.2f" % float(b.signal_resistance))

	b.receive_signal_damage(0.5)
	w.receive_signal_damage(0.5)
	var lost_b: float = 1.0 - b.signal_integrity
	var lost_w: float = 1.0 - w.signal_integrity
	_ok("...and takes less of it than a Walker from the same hit",
			lost_b < lost_w, "%.3f vs %.3f" % [lost_b, lost_w])
	_ok("...by its resistance, not by some other amount",
			absf(lost_b - (0.5 / float(b.signal_resistance))) < 0.001,
			"%.4f" % lost_b)
	b.free()
	w.free()
	await process_frame


func _test_it_walks() -> void:
	# The gait is Walker's and is driven by how far the body MOVED, so posing
	# it means moving it and ticking. If the legs never leave their rest pose
	# the frame slides around the level like a chess piece.
	var b := _spawn(BULWARK, Vector3.ZERO)
	await process_frame
	var knee = b.get("knee_left")
	_ok("the left knee resolved", knee != null)
	if knee == null:
		b.free()
		return
	var rest: Vector3 = (knee as Node3D).rotation
	var moved: bool = false
	for i in 40:
		(b as Node3D).global_position += Vector3(0, 0, -0.35)
		b._tick_gait(1.0 / 60.0)
		if not (knee as Node3D).rotation.is_equal_approx(rest):
			moved = true
	_ok("...and the gait bends it when the frame walks", moved)
	# ...and settles again when it stops, or a halted mech keeps marching.
	for i in 90:
		b._tick_gait(1.0 / 60.0)
	_ok("...and it settles when the frame stops",
			(knee as Node3D).rotation.is_equal_approx(rest),
			"%s vs rest %s" % [str((knee as Node3D).rotation), str(rest)])
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_eye_keeps_its_own_colour() -> void:
	# THE EYE IS NOT FACTION KIT. Every robot in this game is identified by one
	# offset eye, and an eye that turns blue for one side and red for the other
	# stops being an identifying feature.
	#
	# IT WENT WRONG IN A WAY NOTHING REPORTED. The scene's exported arrays are
	# typed — pieces is Array[Node3D], particle_effects_die is
	# Array[ParticleEffect] — and assigning an UNTYPED array to one saves as
	# `[]` with no error. FactionLivery then falls back to walking its whole
	# parent, which paints every mesh on the frame including the eye. So these
	# assertions are about the arrays being POPULATED as much as about colour:
	# empty is the failure mode, and empty looks like nothing at all.
	var b := _spawn(BULWARK)
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
	# ...and the rest of the frame really did get painted, or the assertion
	# above would pass on a livery that does nothing at all.
	var hull = b.find_child("Hull", true, false)
	_ok("...while the hull did take the faction coat",
			hull != null and hull.material_override is ShaderMaterial)

	# The other three typed arrays, same failure mode, same silence.
	_ok("death effects are wired", (b.get("particle_effects_die") as Array).size() > 0)
	_ok("hit effects are wired", (b.get("particle_effects_hit") as Array).size() > 0)
	_ok("visible_pieces is wired", (b.get("visible_pieces") as Array).size() > 0)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_a_weapon_fits_the_arm() -> void:
	# The arm is wired as a turret today — see the long note at the bottom of
	# bulwark.gd about why that is temporary. While it IS one, a weapon has to
	# actually fit it and point the same way it would on any other frame, or
	# the chassis ships with a gun aiming into its own shoulder.
	var b := _spawn(BULWARK)
	await process_frame
	var mount = b.get("weapon_mount")
	var pivot = b.get("gun_pivot")
	_ok("the arm has a weapon mount", mount != null)
	_ok("...and a gun pivot", pivot != null)
	if mount == null or pivot == null:
		b.free()
		return
	# The mount must be a DESCENDANT of the pivot, or elevating the gun moves
	# the pivot and leaves the weapon behind.
	_ok("...and the mount rides the pivot", pivot.is_ancestor_of(mount))

	var gun: Node = load("res://Character/weapon/ai-wep_heavy_mg.tscn").instantiate()
	mount.add_child(gun)
	await process_frame
	await physics_frame
	# WHICH WAY IT POINTS. The Walker's WeaponMount is yawed -90 degrees so a
	# weapon's own +X muzzle axis ends up along the body's -Z; matching that is
	# the whole reason this frame's mount carries the same rotation. Checked
	# against the BODY's forward rather than against a number, so the test
	# still means something if the convention ever changes.
	var muzzle: Vector3 = (mount as Node3D).global_transform.basis.x.normalized()
	var fwd: Vector3 = -(b as Node3D).global_transform.basis.z.normalized()
	_ok("...and a fitted weapon points where the frame is facing",
			muzzle.dot(fwd) > 0.9, "dot %.3f" % muzzle.dot(fwd))
	# ...and it is out in front of the chest, not inside it.
	var muzzle_z: float = (mount as Node3D).global_position.z
	_ok("...from in front of the torso, not inside it", muzzle_z < -0.9,
			"mount z = %.2f" % muzzle_z)
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_arm_aims_without_the_torso() -> void:
	# THE WHOLE FRAME IN ONE TEST. A Bulwark that swings its torso to engage is
	# a Walker with a shield in the wrong place, and nothing on screen would
	# say so — the gun still bears, the target still dies, the squad behind it
	# just quietly loses its cover.
	var b := _spawn(BULWARK)
	await process_frame
	var arm = b.get("arm_yaw")
	var torso = b.get("turret")
	_ok("the arm has a yaw joint of its own", arm != null)
	if arm == null or torso == null:
		b.free()
		return

	# A target 25 degrees off the nose: inside the arm's cone, so the torso
	# must not move at all.
	var cone: float = float(b.arm_yaw_cone_degrees)
	_ok("...with a cone worth having", cone >= 20.0, "%.0f deg" % cone)
	b.ai_state = b.AIState.COMBAT
	var ang := deg_to_rad(cone * 0.6)
	b.weapon_target = Vector3(sin(ang) * 30.0, 0.0, -cos(ang) * 30.0)
	var torso_before: float = torso.rotation.y
	# THE BODY IS HELD, which is the case the arm exists for.
	#
	# Left free, a stationary frame simply turns its whole body to face the
	# target and the arm has nothing to cover — and the shield turns anyway,
	# because it hangs off the torso which hangs off the body. The arm only
	# buys anything while the body is pointed somewhere else: walking under
	# orders, strafing, giving ground. Pinning the rotation here simulates that
	# and is the only way this assertion is about the arm at all.
	var held: float = (b as Node3D).rotation.y
	for i in 120:
		b._update_facing(1.0 / 60.0)
		(b as Node3D).rotation.y = held
		b._pose_arms(1.0 / 60.0)
	_ok("a target inside the cone is taken by the arm",
			absf(arm.rotation.y) > deg_to_rad(cone * 0.4),
			"arm at %.1f deg" % rad_to_deg(arm.rotation.y))
	_ok("...and the torso does not move, so the shield stays put",
			absf(torso.rotation.y - torso_before) < deg_to_rad(1.0),
			"torso moved %.2f deg" % rad_to_deg(torso.rotation.y - torso_before))
	# ...and the gun really is bearing, which is what lets it fire.
	_ok("...and the gun is on target", b._weapon_on_target())

	# Now a target well outside the cone: the torso has to come round.
	var wide := deg_to_rad(cone + 45.0)
	b.weapon_target = Vector3(sin(wide) * 30.0, 0.0, -cos(wide) * 30.0)
	for i in 300:
		b._update_facing(1.0 / 60.0)
		(b as Node3D).rotation.y = held
		b._pose_arms(1.0 / 60.0)
	_ok("a target outside the cone does bring the torso round",
			absf(torso.rotation.y - torso_before) > deg_to_rad(10.0),
			"torso moved %.1f deg" % rad_to_deg(torso.rotation.y - torso_before))
	_ok("...and the arm stays within its own cone",
			arm.rotation.y >= -deg_to_rad(cone) - 0.01
			and arm.rotation.y <= deg_to_rad(float(b.arm_yaw_across_degrees)) + 0.01,
			"arm at %.1f deg" % rad_to_deg(arm.rotation.y))

	# WHERE THE GUN POINTS must be the arm, or the frame refuses to fire
	# whenever the arm bears and the torso does not — which is most of the
	# time it is doing its job.
	var arm_fwd: Vector3 = -(arm as Node3D).global_transform.basis.z
	arm_fwd.y = 0.0
	_ok("_turret_forward follows the arm, not the torso",
			b._turret_forward().normalized().dot(arm_fwd.normalized()) > 0.99)
	b.free()
	await process_frame


func _test_the_gun_arm_walks() -> void:
	# The gun arm was the one limb that did not move when the frame walked,
	# because the aiming code owned it outright. Out of combat it should swing
	# with the stride like any other limb.
	var b := _spawn(BULWARK)
	await process_frame
	var pivot = b.get("gun_pivot")
	if pivot == null:
		_ok("the gun pivot resolved", false)
		b.free()
		return
	var rest: float = (pivot as Node3D).rotation.x
	var swung: bool = false
	for i in 60:
		(b as Node3D).global_position += Vector3(0, 0, -0.35)
		b._tick_gait(1.0 / 60.0)
		if absf((pivot as Node3D).rotation.x - rest) > deg_to_rad(2.0):
			swung = true
	_ok("the gun arm swings with the stride when not aiming", swung,
			"pivot at %.1f deg" % rad_to_deg((pivot as Node3D).rotation.x))
	b.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_the_shield_stops_rounds() -> void:
	# THE SHIELD USED TO STOP NOTHING, which made the chassis a Walker with
	# more health. Measured at the time: a shot at the plate's centre passed
	# through it and hit the body capsule behind, and a shot at its outer half
	# — which reaches past the 0.95 m capsule — hit nothing at all.
	# WELL CLEAR OF THE ORIGIN. Every other test here spawns at Vector3.ZERO,
	# and this one fires a ray through the world — so a frame leaked by an
	# earlier test would sit on top of this one and its shield would be what
	# the ray hits. That is exactly what happened the first time: the own-gun
	# check failed against a shield belonging to a body that should have been
	# freed, and the geometry was innocent.
	var b := _spawn(BULWARK, Vector3(300, 0, 300))
	await process_frame
	await physics_frame
	await physics_frame
	var shield = b.find_child("Shield", true, false)
	_ok("the frame still has a shield mesh", shield != null)
	if shield == null:
		b.free()
		return
	var aabb: AABB = (shield as VisualInstance3D).global_transform \
			* (shield as VisualInstance3D).get_aabb()
	var ss := (b as Node3D).get_world_3d().direct_space_state

	# Rounds come from in front. Both the middle of the plate and its outboard
	# edge, because the edge is the half that used to miss entirely.
	for probe in [["the middle of the plate", aabb.position.x + aabb.size.x * 0.5],
			["its outboard edge", aabb.position.x + 0.18]]:
		var t := Vector3(float(probe[1]), aabb.position.y + aabb.size.y * 0.5, aabb.position.z)
		var q := PhysicsRayQueryParameters3D.create(
				Vector3(t.x, t.y, t.z - 12.0), t + Vector3(0, 0, 4.0))
		var r = ss.intersect_ray(q)
		var hit_name: String = "" if not r else str(r.collider.name)
		_ok("a round at %s stops on the shield" % str(probe[0]),
				hit_name == "ShieldBlocker", "hit %s" % ("nothing" if hit_name == "" else hit_name))

	# ...and it blocks ROUNDS ONLY. On a layer nothing else tests, so the plate
	# cannot shove a squadmate aside or wedge the frame in a doorway.
	var blocker = b.find_child("ShieldBlocker", true, false)
	_ok("the blocker collides with nothing itself",
			blocker != null and int(blocker.collision_mask) == 0)
	_ok("...and sits on a layer movement does not test",
			blocker != null and (int(blocker.collision_layer) & 0x0F) == 0,
			"layer %d" % (0 if blocker == null else int(blocker.collision_layer)))

	# IT MUST NOT SHOOT ITS OWN SHIELD. The gun arm swings 40 degrees across
	# the body, and the shield is on that side.
	# THE ACROSS LIMIT, which is the one that can clip the plate. Warm the
	# physics server first: the first query after a body moves is what flushes
	# its shapes into place, and a cold query here reported "clear" against a
	# transform that was not there yet — a false negative that cost an hour.
	ss.intersect_ray(PhysicsRayQueryParameters3D.create(
			(b as Node3D).global_position + Vector3(0, 1, -20),
			(b as Node3D).global_position + Vector3(0, 1, 20)))
	b.arm_yaw.rotation.y = deg_to_rad(float(b.arm_yaw_across_degrees))
	await physics_frame
	await physics_frame
	var wm = b.get("weapon_mount")
	var muzzle: Vector3 = (wm as Node3D).global_position
	var dir: Vector3 = (wm as Node3D).global_transform.basis.x.normalized()
	var own = ss.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * 40.0))
	var blk = b.find_child("ShieldBlocker", true, false)
	var detail := ""
	if not own.is_empty():
		detail = "hits %s at %s, own=%s, muzzle %s" % [str(own.collider.name),
				str((own.position as Vector3).snapped(Vector3(0.1, 0.1, 0.1))),
				str(own.collider == blk), str(muzzle.snapped(Vector3(0.1, 0.1, 0.1)))]
	_ok("...and the gun does not hit its own shield at full crossover",
			own.is_empty(), detail)
	b.free()
	await process_frame
