extends RefCounted

# ─────────────────────────────────────────────
# THE TICK, PLACED — the state change, in one place, so two callers cannot
# disagree about it.
#
#   const TickPlaced := preload("res://tools/tick_placed.gd")
#   TickPlaced.seat(tick)
#   tick.global_position = dock_marker.global_position + TickPlaced.LIFT
#
# ─────────────────────────────────────────────
# WHERE THESE NUMBERS COME FROM, AND WHY THEY ARE NOT GUESSED
#
# tools/build_tick.gd's header, section "THE PLACEMENT — exactly what has to
# move, and by how much", is the contract the scene was built to. It is a
# DESCRIPTION OF A STATE CHANGE WITH NO CODE BEHIND IT: nothing in the project
# references tick.tscn, there is no placement script, and holdable_core.gd
# lands a procedurally-built placeholder pod (capture_tap.gd) instead. So this
# file is that contract compiled, nothing more — eight rotations, one slide and
# one translation, with the generator's own values:
#
#   Thigh   rotation.x  +46 -> -22 deg    the hinge that answers core size
#   Shin    rotation.x -148 -> -62 deg    the folded Z breaks into a clamp
#   FanTower  position.y 1.50 -> 0.76     the lift assembly telescopes down
#   Boom    rotation.x    0 -> -48 deg    the droop, all three the same
#
# THE SCENE SHIPS IN THE FLIGHT POSE, so anything that wants the placed one has
# to do this. If the geometry is ever re-posed, build_tick.gd is the source and
# this follows it.
#
# LIFT IS THE TRANSLATION AND IT IS MEASURED FROM THE BARB TIPS. The frame's
# origin is the drum centre and the generator seats the barbs at y 0 with the
# drum 2.00 m above them, so the contact point plus LIFT puts the barbs on the
# pad. Nothing else needs solving, at any core size.
# ─────────────────────────────────────────────

const LIFT := Vector3(0.0, 2.00, 0.0)
const THIGH_DEG := -22.0
const SHIN_DEG := -62.0
const TOWER_Y := 0.76
const BOOM_DEG := -48.0


## Drives a tick.tscn instance from the flight pose into the placed one.
## Returns the number of joints it actually moved, so a caller can tell the
## difference between "posed" and "silently did nothing because the scene was
## restructured".
static func seat(tick: Node3D) -> int:
	var moved := 0
	for i in range(1, 5):
		var thigh := tick.get_node_or_null(NodePath("Rig/Legs/Leg%d/Thigh" % i)) as Node3D
		if thigh == null:
			# Every early return warns. A missing joint means the TICK is being
			# photographed or measured in the FLIGHT pose while the caller
			# believes it is clamped, which is the one failure that looks fine.
			push_warning("tick_placed: no Rig/Legs/Leg%d/Thigh — the tick stays in its flight pose" % i)
			continue
		thigh.rotation.x = deg_to_rad(THIGH_DEG)
		moved += 1
		var shin := thigh.get_node_or_null(^"Shin") as Node3D
		if shin == null:
			push_warning("tick_placed: no Shin under Leg%d — that leg stays folded" % i)
			continue
		shin.rotation.x = deg_to_rad(SHIN_DEG)
		moved += 1
	var tower := tick.get_node_or_null(^"Rig/FanTower") as Node3D
	if tower == null:
		push_warning("tick_placed: no Rig/FanTower — the lift assembly stays up and the drone reads as still flying")
		return moved
	tower.position.y = TOWER_Y
	moved += 1
	for i in range(1, 4):
		var boom := tower.get_node_or_null(NodePath("Rotor%d/Boom" % i)) as Node3D
		if boom == null:
			push_warning("tick_placed: no Rotor%d/Boom — that rotor stays level" % i)
			continue
		boom.rotation.x = deg_to_rad(BOOM_DEG)
		moved += 1
	return moved
