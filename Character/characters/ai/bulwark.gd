extends Walker
class_name Bulwark

# ─────────────────────────────────────────────
# BULWARK — the frame that walks INTO fire.
#
# WHAT IT IS FOR, and it is not hit points. Suppression is measured along a
# round's flight path now, not at its impact, so every shot aimed at anything
# behind this frame passes CLOSE TO IT on the way — and a near miss costs
# signal. A Bulwark in front of a squad is standing in the lane, and the lane
# is where suppression lives. Armour would not do this: armour is health, and
# this is about geometry.
#
# THE CHASSIS PAYS FOR IT WITH signal_resistance, set in the scene rather than
# here, which divides both the suppression it takes and the length of any EMP
# lock. Everything else on the frame is ordinary: it is slower than a Walker,
# carries one weapon instead of two, and has no coax.
#
# THE TORSO IS THE TURRET. Walker already traverses `turret` in yaw and pitches
# `gun_pivot`, and both exports are node paths — so pointing `turret` at the
# TORSO rather than at a head makes the whole upper body rotate, arms and
# shield with it, and the inherited aiming code needs no changes at all. That
# is also the correct behaviour: a shield that does not follow where the mech
# is looking is a shield in the wrong place.
#
# WHY IT EXTENDS WALKER rather than Soldier. The gait, the turret traverse, the
# facing split and the fire cone are all Walker's and all generic — they talk
# to hip/knee/foot and turret/gun_pivot node paths and care nothing about how
# many arms the thing has. Everything below is additive.
# ─────────────────────────────────────────────

@export_group("Arms")
## The shield arm's shoulder. Swung gently against the stride so the frame
## reads as walking rather than sliding; see _pose_arms.
@export var shoulder_shield: Node3D
## The shield itself, so a future damage state can shed it.
@export var shield: Node3D
## The head. A turret-SHAPED head, not a head turret — it does not rotate on
## its own, the torso traverses and this rides it. Exported because it is
## where a hat mounts and where a destroyed-sensor state would show.
@export var head: Node3D

## How far the shield arm swings against the stride, in degrees.
##
## SMALL ON PURPOSE. A braced shield that swings like a marching arm stops
## reading as braced, and this frame's whole silhouette is the shield being
## held still while the legs do the work. Four degrees is enough to say the
## arm is attached to something that is walking.
@export var shield_arm_swing_degrees: float = 4.0

## Extra forward lean while moving, in degrees. A frame pushing a wall of steel
## into gunfire leans on it.
@export var brace_lean_degrees: float = 5.0

var _shield_rest: Vector3 = Vector3.ZERO
var _torso_rest: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	if shoulder_shield != null:
		_shield_rest = shoulder_shield.rotation
	# EVERY EARLY RETURN WARNS. A Bulwark with no shield node is a Bulwark that
	# silently became an ordinary Walker with one gun, which is worse than one
	# that says so.
	if shield == null:
		push_warning("Bulwark '%s': no shield assigned, so it is just a slow Walker." % name)


func _tick_gait(delta: float) -> void:
	super(delta)
	_pose_arms(delta)


## The shield arm rides the stride, and the torso leans into it.
##
## OFF `turret.rotation.x`, NOT the rig's. Walker bobs the rig vertically for
## footfalls and that is a position, not a rotation, so leaning here cannot
## fight it. Leaning the TORSO rather than the whole body also keeps the legs
## vertical, which is what stops a lean looking like a fall.
func _pose_arms(delta: float) -> void:
	if shoulder_shield != null:
		# Opposite phase to the left leg, which is what an arm does.
		var swing := deg_to_rad(shield_arm_swing_degrees) * _gait_amount
		shoulder_shield.rotation = _shield_rest + Vector3(-sin(_gait) * swing, 0.0, 0.0)
	if turret != null:
		# Pitch is the TORSO's lean. Yaw is the aiming code's and is not
		# touched here — writing both from one place is how the gun would
		# never settle on target.
		turret.rotation.x = deg_to_rad(brace_lean_degrees) * _gait_amount

	# ── THE GUN ARM: marching and aiming, blended ──
	#
	# This is the thing the first build could not do. The arm was the aiming
	# code's alone, so it was the one limb that did not move when the frame
	# walked and the whole mech read as stiff. Now the march swing and the aim
	# are separate values blended by _aim_weight, so a Bulwark crossing open
	# ground swings its gun arm like a leg and settles it onto the target as
	# it comes into contact — rather than snapping between the two.
	#
	# IN PHASE WITH THE LEFT LEG and therefore opposite the shield arm, which
	# is how anything with four limbs walks.
	if arm_yaw != null:
		var march := sin(_gait) * deg_to_rad(gun_arm_swing_degrees) * _gait_amount
		var aimed := _aim_weight
		# Yaw is aim-only: an arm that swings SIDEWAYS as it marches looks
		# like it is losing its grip on the gun. The stride goes into pitch.
		arm_yaw.rotation.y = move_toward(arm_yaw.rotation.y, _arm_yaw_aim * aimed,
				deg_to_rad(arm_traverse_degrees) * delta)
	if gun_pivot != null:
		var march_pitch := sin(_gait) * deg_to_rad(gun_arm_swing_degrees) * _gait_amount
		var want: float = lerpf(march_pitch, _arm_pitch_aim, _aim_weight)
		gun_pivot.rotation.x = move_toward(gun_pivot.rotation.x, want,
				deg_to_rad(maxf(gun_elevation_degrees, arm_traverse_degrees)) * delta)


## It does not take cover. The whole frame is cover.
##
## Walker returns false here already, but relying on that would make this
## frame's defining behaviour an accident of its parent: a Bulwark that ducked
## into a doorway would be leaving the squad it is shielding in the open, and
## that has to be stated where somebody reading this file can see it.
func takes_cover() -> bool:
	return false


# ─────────────────────────────────────────────
# THE ARM AIMS ITSELF. THE TORSO ONLY FOLLOWS WHEN IT HAS TO.
#
# To the catalogue this is an ordinary turret frame: one weapon slot, fitted to
# WeaponMount, `turret = true`. None of the weapon plumbing knows anything has
# changed, which is the point — the behaviour is different, the contract is not.
#
# WHAT IS DIFFERENT. Walker yaws its whole turret to bear, and on this chassis
# the shield hangs off that turret: traversing to engage a flanker would swing
# the wall away from whatever it was covering. So the yaw is SPLIT.
#
#   ArmYaw    fast, within arm_yaw_cone_degrees of straight ahead. Swings the
#             limb alone, so the shield does not move.
#   Torso     slow, and only wound up when the target is outside that cone —
#             and then only far enough to bring it back inside.
#
# The result is the thing the frame is for: it can hold the shield toward the
# threat and shoot at something else, up to forty degrees off. Push past that
# and the whole body has to come round, slowly, which is the counter.
#
# WHAT HAD TO BE OVERRIDDEN, and why the base class could not just be reused.
# Walker's `_turret_forward` returns the TURRET's bearing, and
# `_weapon_on_target` compares that against the target to decide whether to
# fire. On this frame the gun is not on the turret — it is a metre out on a
# limb with a joint of its own — so inheriting either one means a Bulwark that
# refuses to fire whenever its arm is bearing and its torso is not, which is
# most of the time it is doing its job.
#
# WHAT THIS DOES NOT DO, found by testing it rather than by reasoning about
# it. The arm is independent of the TORSO, not of the BODY. A stationary
# Bulwark still turns its whole body to face a target — that is Soldier's
# facing and it is right for a frame that walks — and the shield, hanging off
# the torso which hangs off the body, goes round with it. So the split yaw
# buys exactly nothing while the frame is standing still and shooting.
#
# It buys everything while the body is pointed somewhere else: advancing under
# orders, strafing, giving ground. That is also when a shield matters most, so
# the feature is live precisely when it is needed — but anyone expecting a
# planted Bulwark to hold its shield on one bearing and shoot off to the side
# will not get it, and the thing to change for that is _desired_facing, not
# anything in this file.
#
# STILL TRUE, AND STILL A COMPROMISE: the muzzle is not at the pivot. Elevating
# swings the barrel through an arc rather than rotating it in place, so at very
# close range the round leaves from a few tens of centimetres off where a
# turret's would. Accepted — fixing it means solving for the shoulder and elbow
# together, and nothing in the game measures muzzle origin that precisely.
# ─────────────────────────────────────────────

## The arm's own yaw joint. Null falls back to Walker's behaviour entirely,
## which is a working frame with a worse shield — so this warns rather than
## breaking.
@export var arm_yaw: Node3D

## How far off the torso's facing the arm can bear on its own, AWAY from the
## shield — the frame's right, the open side.
@export var arm_yaw_cone_degrees: float = 40.0
## ...and how far it can bear ACROSS the shield, which is much less.
##
## THIS IS A MEASURED LIMIT, NOT A FEEL ONE. The plate is carried inboard so
## it covers the centreline, and the muzzle crosses that same line when the
## arm swings left: at 40 degrees across, the gun's own raycast stops on its
## own shield 0.23 m out. Swept with the physics server warmed, 30 is clear
## and 40 is not, so this sits at 28 with margin.
##
## It is also just true of a thing holding a tower shield, and it gives the
## frame a real asymmetry — the shield side is the slow side, and flanking it
## there means waiting for the whole body to come round.
## How fast the arm swings. Much quicker than a turret ring: it is an arm.
@export var arm_yaw_across_degrees: float = 28.0
@export var arm_traverse_degrees: float = 150.0
## How far the gun arm swings with the stride when it is NOT aiming, and how
## fast it blends between marching and aiming.
@export var gun_arm_swing_degrees: float = 13.0
@export var aim_blend_seconds: float = 0.25

## 0 marching, 1 aiming. Blended so the arm does not snap between the two.
var _aim_weight: float = 0.0
## The aim the last update wanted, kept so the march swing can be added on top
## without the two fighting over the same property.
var _arm_yaw_aim: float = 0.0
var _arm_pitch_aim: float = 0.0


func _update_facing(delta: float) -> void:
	if arm_yaw == null or turret == null:
		super(delta)   # warned about in _ready
		return
	# The legs still turn the ordinary way. Soldier's facing, not Walker's —
	# Walker's would also drive the turret, which is exactly what is being
	# replaced here.
	_body_facing(delta)

	var engaging: bool = ai_state == AIState.COMBAT and weapon_target != Vector3.ZERO
	_aim_weight = clampf(_aim_weight + (delta / maxf(aim_blend_seconds, 0.02))
			* (1.0 if engaging else -1.0), 0.0, 1.0)

	var face := _desired_facing()
	# WHAT THE ARM AIMS AT IS THE WEAPON'S TARGET, not _desired_facing().
	#
	# Those are two different questions and the first build conflated them.
	# _desired_facing is where the BODY wants to look — it keys off
	# combat_target, and it has its own rules about fighting withdrawals and
	# looking where you are going. The arm does not care about any of that: it
	# points at the thing the gun is shooting at, and the torso's facing is
	# just the frame it measures that against.
	var bearing := 0.0
	var have_bearing := false
	if engaging:
		var to_t: Vector3 = weapon_target - turret.global_position
		to_t.y = 0.0
		if to_t.length_squared() > 0.0001:
			var local: Vector3 = turret.global_transform.basis.inverse() * to_t
			bearing = atan2(-local.x, -local.z)
			have_bearing = true
	elif face != Vector3.ZERO:
		var local2: Vector3 = turret.global_transform.basis.inverse() * face
		bearing = atan2(-local2.x, -local2.z)
		have_bearing = true

	if have_bearing:
		# ASYMMETRIC. Positive yaw swings the gun toward the shield, which it
		# can only do so far before the muzzle is behind its own plate.
		var open_side := deg_to_rad(arm_yaw_cone_degrees)
		var across := deg_to_rad(arm_yaw_across_degrees)
		# Out of combat the arm does not hold a bearing at all — it marches.
		_arm_yaw_aim = clampf(bearing, -open_side, across) if engaging else 0.0
		# THE TORSO ONLY MAKES UP THE DIFFERENCE. Inside the cone it does not
		# move at all, which is what keeps the shield where it was put.
		var overshoot: float = bearing - clampf(bearing, -open_side, across)
		if absf(overshoot) > 0.001:
			turret.rotation.y = rotate_toward(turret.rotation.y,
					turret.rotation.y + overshoot,
					deg_to_rad(turret_traverse_degrees) * delta)

	# Pitch is the ARM's, measured from the elbow to the target. Stored rather
	# than applied: _pose_arms owns the joint, because it has to blend this
	# against the march swing and two writers would fight over it every frame.
	if gun_pivot != null:
		var want_pitch := 0.0
		if engaging:
			var to: Vector3 = weapon_target - gun_pivot.global_position
			want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		_arm_pitch_aim = clampf(want_pitch, deg_to_rad(gun_min_pitch_degrees),
				deg_to_rad(gun_max_pitch_degrees))



## WHERE THE GUN POINTS, which on this frame is the arm and not the turret.
func _turret_forward() -> Vector3:
	var from: Node3D = arm_yaw if arm_yaw != null else turret
	if from == null:
		return -global_transform.basis.z
	var f := -from.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else -global_transform.basis.z


## Soldier's body turn, reached past Walker's override.
##
## Walker._update_facing calls super() for the legs and then drives the turret;
## this frame wants the first half and not the second, and GDScript has no way
## to say "grandparent's version". Duplicating the one call is less fragile
## than restructuring Walker for a single subclass.
func _body_facing(delta: float) -> void:
	var keep_turret: Node3D = turret
	turret = null          # makes Walker's override take its own early path
	super._update_facing(delta)
	turret = keep_turret
