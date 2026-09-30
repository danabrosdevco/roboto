extends Soldier
class_name Walker

# ─────────────────────────────────────────────
# WALKER — the first frame that carries two guns.
#
# WHAT IT IS FOR. Not hit points. A Walker's real edge over a Rover is that it
# WALKS: `ChassisDefinition.takes()` only refuses infantry kit when `drives` is
# true, so a frame with `drives = false` can take leg kit a rover cannot —
# Nanite Reboot is `fits_vehicles = false`, and a self-reviving 320-hull gun
# platform is a different object from a rover that stays where it falls. It is
# still `vehicle = true`, so it musters with ARMOR.
#
# THE TWO MOUNTS ARE MAIN AND COAX, not two guns making their own decisions.
# The plumbing is in Enemy (`coax`, `coax_mount`, `_tick_coax`); this frame is
# just the first one with somewhere to put the second gun. The main gun owns
# target selection, the sight picture, bursts and reloads exactly as any other
# robot's does. The coax rides its bearing.
#
# IT IS A TURRET ON LEGS. Movement is ordinary Soldier movement — it walks the
# navmesh like infantry, and deliberately does NOT use the Rover's bicycle
# model, which exists to stop a wheeled hull sliding sideways and has nothing
# to say about legs. What it borrows from the Rover is the TURRET: the gun
# traverses at a fixed rate and will not fire until it is on target, so
# getting around it faster than `turret_traverse_degrees` remains the counter.
# Both guns share that bearing, so flanking beats both at once.
#
# THE IDENTITY IS THE FIT, not the frame. Autocannon makes it anti-armour,
# Heavy MG makes it a suppression platform, mortar makes it indirect. Same 320
# hull, three jobs, and the coax covers whatever gets close while the main gun
# is doing the job you bought it for.
# ─────────────────────────────────────────────

@export_group("Rig")
## The whole model, so the gait can bob it.
@export var rig: Node3D
@export var hip_left: Node3D
@export var knee_left: Node3D
@export var hip_right: Node3D
@export var knee_right: Node3D
@export var foot_left: Node3D
@export var foot_right: Node3D
## Metres of ground per complete two-step cycle. Too short and it scurries;
## too long and the feet skate.
@export var stride_length: float = 3.4
## Degrees the hip swings either side of neutral.
@export var hip_swing_degrees: float = 26.0
## Degrees the hip swings OUT TO THE SIDE when it sidesteps. Smaller than the
## forward swing on purpose: a sidestep is a shuffle, not a stride.
@export var side_swing_degrees: float = 15.0
## Extra knee bend at the top of the lift, degrees.
@export var knee_bend_degrees: float = 30.0
## How far the body rises and falls over a stride, metres.
@export var body_bob: float = 0.07
## The gait unwinds to standing over this long once it stops.
@export var settle_seconds: float = 0.35

@export_group("Turret")
## The yawing part. Everything the gun is bolted to hangs off this.
@export var turret: Node3D
## The elevating part, under the turret.
@export var gun_pivot: Node3D
## Degrees per second of traverse. THE COUNTER-PLAY LIVES IN THIS NUMBER: slow
## enough that a chaser can get around the side faster than the gun follows.
@export var turret_traverse_degrees: float = 55.0
@export var gun_elevation_degrees: float = 40.0
@export var gun_min_pitch_degrees: float = -12.0
@export var gun_max_pitch_degrees: float = 35.0
## How far off the bearing still counts as on target. Both guns use it, because
## both are on the same mount.
@export var fire_cone_degrees: float = 7.0


var _gait: float = 0.0
var _gait_amount: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _rig_rest_y: float = 0.0
# Which way the last real fore-aft travel was going, and how this frame's travel
# splits between striding and sidestepping. Held between frames on purpose: a
# move that is almost all sideways must not keep re-deciding which way the
# stride runs, or the legs stutter.
var _way: float = 1.0
var _ahead_share: float = 1.0
var _across_share: float = 0.0
var _across_way: float = 0.0


func _ready() -> void:
	super()
	if turret == null:
		push_warning("%s has no turret assigned, so it will aim by turning its whole body like infantry." % name)
	if hip_left == null or hip_right == null:
		push_warning("%s has no hip pivots assigned, so its legs will not move and it will slide." % name)
	_last_pos = global_position
	if rig != null:
		_rig_rest_y = rig.position.y


# ─────────────────────────────────────────────
# THE WALK
# ─────────────────────────────────────────────
# DRIVEN BY GROUND COVERED, NOT BY A CLOCK. The cycle advances by how far the
# body actually moved this frame, which is the same input the Rover's wheels
# use (rover.gd:_tick_rig) and for the same reason: a gait on a timer keeps
# striding when the walker is stopped against a wall, and drifts out of phase
# with the ground the moment anything slows it down — a slope, a shove, being
# ordered to a point it has almost reached. Tie it to distance and the feet
# stay planted at the speed the legs are moving whatever the cause.
#
# `_gait_amount` fades the whole cycle out when it stops, so a parked Walker
# settles to standing instead of freezing mid-stride with one leg in the air.
func _physics_process(delta: float) -> void:
	super(delta)
	_tick_gait(delta)


func _tick_gait(delta: float) -> void:
	if hip_left == null or hip_right == null:
		return   # warned about in _ready; nothing to pose
	var moved := global_position - _last_pos
	_last_pos = global_position
	var flat := Vector3(moved.x, 0.0, moved.z)
	var travelled := flat.length()

	# Downed or dead: no gait at all, and let it settle flat.
	var walking: bool = travelled > 0.002 and alive and not downed
	if walking:
		# WHICH WAY IT IS GOING, not only how far. A Walker in combat faces its
		# target and moves wherever the fight sends it, so the body's heading and
		# its travel routinely disagree — and a stride cycle that only knows the
		# distance plays the same forward march for a backpedal and for a
		# sidestep, feet scuffing the wrong way across the ground. Split the
		# travel into the body's own frame and let each direction pose its own
		# step. A rover never needed this: wheels turn the same way whatever the
		# hull is doing.
		var local := global_transform.basis.inverse() * flat
		var ahead := -local.z    # + forward: Godot faces -Z
		var across := local.x    # + to its right
		# BACKWARDS RUNS THE CYCLE IN REVERSE, which is all a reverse step is:
		# the hips swing the other way round and the knee bends on the other half
		# of the stride. Only re-decide when fore-aft motion is a real share of
		# the travel, so a sidestep with a hair of drift in it does not flicker
		# the whole gait back and forth.
		if absf(ahead) > travelled * 0.25:
			_way = -1.0 if ahead < 0.0 else 1.0
		_gait += (travelled / maxf(stride_length, 0.1)) * TAU * _way
		# The two shares are the sides of a right triangle over its hypotenuse,
		# so they square-sum to 1 and cross over smoothly as it turns from
		# walking into strafing.
		_ahead_share = absf(ahead) / travelled
		_across_share = absf(across) / travelled
		if absf(across) > travelled * 0.25:
			_across_way = signf(across)
		_gait_amount = minf(1.0, _gait_amount + delta / maxf(settle_seconds, 0.05))
	else:
		_gait_amount = maxf(0.0, _gait_amount - delta / maxf(settle_seconds, 0.05))

	var swing := deg_to_rad(hip_swing_degrees) * _gait_amount * _ahead_share
	var bend := deg_to_rad(knee_bend_degrees) * _gait_amount
	var side := deg_to_rad(side_swing_degrees) * _gait_amount * _across_share * _across_way
	_pose_leg(hip_left, knee_left, foot_left, _gait, swing, bend, side)
	_pose_leg(hip_right, knee_right, foot_right, _gait + PI, swing, bend, side)

	# Two footfalls per cycle, so the body rises and falls twice as fast as the
	# legs swing. Without it the walk reads as a puppet sliding on a rail.
	if rig != null:
		rig.position.y = _rig_rest_y + sin(_gait * 2.0) * body_bob * _gait_amount


# One leg, posed off its own phase. The knee only ever bends one way — a leg
# that hyperextends backwards is the thing that makes a walk cycle look broken.
func _pose_leg(hip: Node3D, knee: Node3D, foot: Node3D, phase: float, swing: float,
		bend: float, side: float) -> void:
	if hip == null:
		return
	hip.rotation.x = sin(phase) * swing
	var knee_x := 0.0
	if knee != null:
		# Bends through the forward half of the stride, straight on the plant.
		knee_x = -maxf(0.0, sin(phase + PI * 0.5)) * bend
		knee.rotation.x = knee_x
	# A SIDESTEP IS A SHUFFLE, NOT A SCISSOR. Both legs only ever displace
	# TOWARDS the travel, one after the other: the leading foot reaches out, the
	# trailing one closes up behind it. Posed on a plain sine the way the stride
	# is, one leg would go out while the other went the opposite way, and a
	# machine strafing right would read as standing there doing the splits.
	var hip_z := (sin(phase) * 0.5 + 0.5) * side
	hip.rotation.z = hip_z
	# THE SOLE STAYS FLAT. Left to inherit the hip and the knee, the foot dangles
	# off the end of the leg like a pointed toe, which is the one thing that makes
	# a walk cycle read as a puppet on strings. Countering both joints keeps it
	# parallel to the ground through the whole stride — and countering the
	# sidestep too, so it plants flat rather than landing on its outside edge.
	if foot != null:
		foot.rotation.x = -(hip.rotation.x + knee_x)
		foot.rotation.z = -hip_z


# ─────────────────────────────────────────────
# TURRET — the Rover's pattern, on legs.
# ─────────────────────────────────────────────
# The body walks wherever the navmesh is taking it; the turret is what points
# at things. Without the split, a walker under a move order would have to face
# its destination to shoot, which is exactly the behaviour a turret exists to
# avoid.
func _update_facing(delta: float) -> void:
	if turret == null:
		super(delta)   # warned about in _ready
		return
	# The body still turns the ordinary way — it is walking, and legs point
	# where they are going.
	super(delta)
	var face := _desired_facing()
	if face != Vector3.ZERO:
		var local := global_transform.basis.inverse() * face
		var want_yaw := atan2(-local.x, -local.z)
		turret.rotation.y = rotate_toward(turret.rotation.y, want_yaw,
			deg_to_rad(turret_traverse_degrees) * delta)
	if gun_pivot != null:
		var want_pitch := 0.0
		if ai_state == AIState.COMBAT and weapon_target != Vector3.ZERO:
			var to := weapon_target - gun_pivot.global_position
			want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		want_pitch = clampf(want_pitch, deg_to_rad(gun_min_pitch_degrees), deg_to_rad(gun_max_pitch_degrees))
		gun_pivot.rotation.x = rotate_toward(gun_pivot.rotation.x, want_pitch,
			deg_to_rad(gun_elevation_degrees) * delta)


func _turret_forward() -> Vector3:
	var f := -(turret.global_transform.basis.z if turret != null else global_transform.basis.z)
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else -global_transform.basis.z


# Firing while the turret is still swinging is what makes one read as fake, and
# it is also what would remove the counter: if it could shoot mid-traverse,
# getting around the side would buy nothing. The coax asks this same question
# (Enemy._tick_coax) because both guns are on this one mount.
func _weapon_on_target() -> bool:
	if turret == null:
		return true
	var to := weapon_target - global_position
	to.y = 0.0
	if to.length_squared() < 0.25:
		return true   # on top of it: any bearing is as good as another
	return rad_to_deg(_turret_forward().angle_to(to.normalized())) <= fire_cone_degrees


# It parks, it does not take cover. A cover point is a crouch behind a wall,
# and this is three metres of gun platform — the same call the Rover makes.
func takes_cover() -> bool:
	return false
