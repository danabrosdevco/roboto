extends "res://Character/characters/ai/rover.gd"

# ─────────────────────────────────────────────
# LANCE — the frame that aims by pointing itself.
#
# BY PATH, NOT `extends Rover`. rover.gd has never declared a class_name and
# the reason is written at rover.gd:468-470 — adding a global class an open
# editor has not indexed yet is how you take the whole front end down.
# reclaimer.gd:1 is the shipped precedent for this form. Do not add a
# class_name to rover.gd to tidy this up.
#
# ── WHY THIS FILE EXISTS AT ALL ──
#
# Everything else the frame does it already has: Ackermann steering, reverse,
# whisker blocking, pack spacing, suspension, the wreck pose, takes_cover() =
# false, the widened slot tolerance and formation width, and a blocked path
# answered by reversing out instead of stepping sideways. None of that is
# written here and none of it should be.
#
# What is written here is one function, because of a defect that only this
# frame has, and it comes out of two decisions that are each individually
# right:
#
#   1. THE STUB TURRET IS REQUIRED. lance.tscn wires turret = Rig/Turret with
#      turret_traverse_degrees = 0.0. It looks like something to delete on a
#      frame with no turret — and deleting it silently re-arms
#      `hull_spoils_aim` (enemy.gd:2895), which is excused by a node property
#      literally NAMED `turret` being non-null and not by
#      ChassisDefinition.turret. With it null, _aim_tracking decays every time
#      the frame moves and the gun never leaves WeaponState.AIM. That is the
#      bug that cost the Walker its main gun; see the long comment at
#      enemy.gd:2880-2894.
#
#   2. rover.gd's _update_facing TAKES THE TURRET BRANCH AND NEVER CALLS
#      super(). rover.gd:597-600 only calls super(delta) when turret IS null.
#      So Enemy._update_facing (enemy.gd:2779-2788) — the only thing in the
#      game that writes rotation.y from a desired bearing — never runs on this
#      frame, and with zero traverse the stub cannot rotate either. The hull's
#      one remaining source of yaw is rover.gd:333,
#      `rotation.y += _rolled / wheelbase * tan(_steer)`, which is driven by
#      DISTANCE TRAVELLED. Parked, _rolled is zero.
#
# Together: a stationary Lance never changes facing, ever, and with
# fire_cone_degrees = 6.0 it can only shoot whatever happens to be inside six
# degrees of its nose. walker.gd:206-212 takes the turret branch AND calls
# super() on the way through — "the body still turns the ordinary way." The
# Rover deliberately does not, because a six-wheeled hull belongs to the
# driving. A trike with two driven wheels and a castor can pivot on the spot,
# so the Lance is the one frame on rover.gd for which the Walker's answer is
# the right one.
# ─────────────────────────────────────────────


## Degrees per second the hull turns ON THE SPOT. Far slower than
## rotation_speed (7.0 in lance.tscn, which is a lerp rate rather than a rate
## in degrees): turning the hull IS this frame's aiming, so it has to be slow
## enough that getting alongside it still beats it. That is the Rover's
## counter — flank it faster than its turret traverses — kept, on a frame with
## no turret to flank.
##
## BALANCE DIAL, AND THE HUMAN'S NUMBER. 90 is roughly the Rover's traverse
## (turret_traverse_degrees = 95.0) and makes the Lance about as quick to come
## round as a Rover's turret, which arguably deletes the counter. 50 is the
## shipped value, from the 45-60 band; it cannot be judged headless.
@export var hull_slew_degrees: float = 50.0


# Call super(delta) FIRST so the stub turret (a no-op at zero traverse) and the
# gun elevation keep working exactly as they do on a Rover, then add the hull
# slew that the turret branch suppressed.
func _update_facing(delta: float) -> void:
	super(delta)
	# DRIVING: rover.gd:333 owns the yaw. Gating on NONE is what keeps this
	# from fighting the bicycle model — two things writing rotation.y in the
	# same frame is a hull that crabs sideways down a straight road.
	if movement_state != MovementState.NONE:
		return
	var face := _desired_facing()   # enemy.gd:2794 — target, else look, else last move
	if face == Vector3.ZERO:
		return   # nothing to look at and never moved: keep the facing it has
	rotation.y = rotate_toward(rotation.y, atan2(-face.x, -face.z),
			deg_to_rad(hull_slew_degrees) * delta)
