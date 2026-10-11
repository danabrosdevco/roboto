extends RefCounted
class_name ConceptKit

# ─────────────────────────────────────────────
# THE SHARED CONCEPT VOCABULARY.
#
# Lifted verbatim out of tools/mockup_frames.gd so that concept builders for
# different frames can be written in separate files and still draw the same
# machine. Everything here is the WALKER's own geometry, read out of
# walker.tscn — a chamfered hull with a sloped glacis and a cut tail, a turret
# ring, a box head with its cheek and brow sliced off, ONE eye offset left, a
# whip antenna, and boxy hip/thigh/shin/foot limbs.
#
# Static, so a builder file needs no instance and no inheritance. Concept
# builders are plain functions taking a Node3D root.
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")

## The Walker, measured. Nothing here should drift without a reason: these are
## what make a new frame look issued rather than found.
const W_HULL := Vector3(1.5, 0.9, 1.75)
const W_TURRET := Vector3(1.18, 0.6, 1.3)
const W_EYE_R := 0.17
const W_RING_R := 0.54
const W_THIGH := Vector3(0.34, 0.74, 0.4)
const W_SHIN := Vector3(0.26, 0.86, 0.3)
const W_FOOT := Vector3(0.4, 0.15, 0.86)
const DEG := PI / 180.0

## `size` is the uncut block; the cuts take material OFF it, so a hull quoted
## at 2.4 long is shorter than that once the nose and tail are sliced.
static func hull(to: Node, size: Vector3, at: Vector3) -> Node3D:
	var hull := _Parts.box(to, size, at)
	hull.name = "Hull"
	# Sloped glacis, taken off the front.
	var g := _Parts.box(hull, Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.8),
			Vector3(0, -size.y * 0.72, -size.z * 0.62), Vector3(-30.0 * _Parts.DEG, 0, 0))
	g.operation = CSGShape3D.OPERATION_SUBTRACTION
	# Cut-back tail.
	var t := _Parts.box(hull, Vector3(size.x * 1.4, size.y * 1.2, size.z * 0.6),
			Vector3(0, -size.y * 0.68, size.z * 0.64), Vector3(20.0 * _Parts.DEG, 0, 0))
	t.operation = CSGShape3D.OPERATION_SUBTRACTION
	# Shoulder bevels down both flanks — the walker's, scaled.
	for s in [-1.0, 1.0]:
		var b := _Parts.box(hull, Vector3(size.x * 0.7, size.y * 0.8, size.z * 1.4),
				Vector3(s * size.x * 0.68, size.y * 0.66, 0), Vector3(0, 0, s * 30.0 * _Parts.DEG))
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	return hull


## Turret ring, turret, eye, antenna and a stub gun. `scale_f` keeps the whole
## head in proportion on the bigger and smaller frames without redrawing it.
static func head(to: Node, at: Vector3, scale_f: float = 1.0) -> Node3D:
	_Parts.cyl(to, W_RING_R * scale_f, 0.12 * scale_f, at)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = at + Vector3(0, 0.19 * scale_f, 0)
	to.add_child(turret)
	var body := _Parts.box(turret, W_TURRET * scale_f, Vector3.ZERO)
	body.name = "TurretBody"
	# Cheek and brow, cut exactly as the walker's are.
	var cheek := _Parts.box(body, Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, -0.44, -0.86) * scale_f, Vector3(-35.0 * _Parts.DEG, 0, 0))
	cheek.operation = CSGShape3D.OPERATION_SUBTRACTION
	var brow := _Parts.box(body, Vector3(W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, 0.5, -0.78) * scale_f, Vector3(25.0 * _Parts.DEG, 0, 0))
	brow.operation = CSGShape3D.OPERATION_SUBTRACTION
	# ONE EYE, off-centre. The asymmetry is the walker's single most
	# recognisable feature and the cheapest thing to carry over.
	_Parts.sphere(turret, W_EYE_R * scale_f,
			Vector3(-0.34, 0.14, -0.66) * scale_f, Vector3(1, 0.82, 1))
	_Parts.box(turret, Vector3(0.03, 0.85, 0.03) * scale_f,
			Vector3(-0.5, 0.68, 0.48) * scale_f)
	# THE MANTLET SWALLOWS THE EYE, AT EVERY SCALE. The eye is at x -0.34*s and
	# the mantlet box below spans -0.45*s..0.05*s in x, -0.75*s..-0.49*s in z
	# and -0.16*s..0.20*s in y — and the eye's centre (-0.34, 0.14, -0.66)*s is
	# inside all three. Scaling cannot fix it: both terms scale together.
	#
	# It is invisible on the Walker because at scale 1.0 the head is 1.18 wide
	# and the eye still stands proud of the plate. Below about 0.8 it does not:
	# the Kite's pod at 0.6 had its gun-port ring passing 5.2 cm THROUGH the
	# eye, measured, and build_kite.gd fixes it by mirroring the whole gun to
	# starboard so the eye keeps the canonical Walker offset and the two sit on
	# opposite cheeks.
	#
	# Left as drawn here, because the concept sheets were selected from this
	# geometry. Any new frame calling head() below ~0.8 inherits the fault and
	# should mirror the gun the same way.
	# Mantlet and barrel.
	_Parts.box(turret, Vector3(0.5, 0.36, 0.26) * scale_f, Vector3(-0.2, 0.02, -0.62) * scale_f)
	_Parts.cyl(turret, 0.075 * scale_f, 1.5 * scale_f,
			Vector3(-0.2, 0.02, -1.35) * scale_f, Vector3(90.0 * _Parts.DEG, 0, 0))
	return turret


## One leg. `splay` swings it out sideways from the hip, `reach` forward or
## back, and `digitigrade` decides whether the knee breaks forward over a short
## foot (a dog) or the limb drops straight to a flat pad (an elephant).
static func leg(to: Node, hip: Vector3, thigh_len: float, shin_len: float,
		splay: float, reach: float, digitigrade: bool, thick: float = 1.0) -> void:
	var leg := Node3D.new()
	leg.position = hip
	leg.rotation = Vector3(reach * _Parts.DEG, 0, splay * _Parts.DEG)
	to.add_child(leg)
	_Parts.sphere(leg, 0.19 * thick, Vector3.ZERO)
	var knee_drop := -thigh_len
	if digitigrade:
		# Thigh angles back, shin angles forward, foot flat and long: the
		# walker's own leg, which is what makes these read as its relatives.
		_Parts.box(leg, Vector3(W_THIGH.x * thick, thigh_len, W_THIGH.z * thick),
				Vector3(0, knee_drop * 0.5, thigh_len * 0.18), Vector3(15.0 * _Parts.DEG, 0, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, knee_drop, thigh_len * 0.38)
		leg.add_child(knee)
		_Parts.sphere(knee, 0.15 * thick, Vector3.ZERO)
		_Parts.box(knee, Vector3(W_SHIN.x * thick, shin_len, W_SHIN.z * thick),
				Vector3(0, -shin_len * 0.5, -shin_len * 0.2), Vector3(-15.0 * _Parts.DEG, 0, 0))
		_Parts.box(knee, Vector3(W_FOOT.x * thick, W_FOOT.y, W_FOOT.z),
				Vector3(0, -shin_len - 0.06, -shin_len * 0.42 - 0.18))
	else:
		# A pillar: straight down, pad at the bottom. Reads as load-bearing
		# rather than quick, which is the whole difference between the Dray
		# and the Hound at the same size.
		_Parts.box(leg, Vector3(W_THIGH.x * 1.25 * thick, thigh_len, W_THIGH.z * 1.25 * thick),
				Vector3(0, knee_drop * 0.5, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, knee_drop, 0)
		leg.add_child(knee)
		_Parts.ring(knee, 0.05 * thick, 0.2 * thick, Vector3.ZERO)
		_Parts.box(knee, Vector3(W_SHIN.x * 1.3 * thick, shin_len, W_SHIN.z * 1.3 * thick),
				Vector3(0, -shin_len * 0.5, 0))
		_Parts.cyl(knee, 0.26 * thick, 0.14, Vector3(0, -shin_len - 0.05, 0))


## ONE ARM. Shoulder ball, upper arm, elbow, forearm, and whatever the hand is.
##
## MOUNTED ON THE SHOULDER BEVEL, outboard and high, where the walker's hull is
## already chamfered away. `droop` swings it down from horizontal, `out` swings
## it away from the body, and `fore` swings it forward — three angles rather
## than a pose, so a variant can hold a gun level or let a hand hang.
static func arm(to: Node, shoulder: Vector3, upper_len: float, fore_len: float,
		droop: float, out_ang: float, fore_ang: float, thick: float = 1.0,
		hand: String = "none") -> Node3D:
	var arm := Node3D.new()
	arm.position = shoulder
	arm.rotation = Vector3(fore_ang * _Parts.DEG, 0, out_ang * _Parts.DEG)
	to.add_child(arm)
	_Parts.sphere(arm, 0.26 * thick, Vector3.ZERO)
	_Parts.box(arm, Vector3(0.36 * thick, upper_len, 0.36 * thick),
			Vector3(0, -upper_len * 0.5, 0))
	var elbow := Node3D.new()
	elbow.position = Vector3(0, -upper_len, 0)
	elbow.rotation = Vector3(droop * _Parts.DEG, 0, 0)
	arm.add_child(elbow)
	_Parts.sphere(elbow, 0.19 * thick, Vector3.ZERO)
	_Parts.box(elbow, Vector3(0.3 * thick, fore_len, 0.3 * thick),
			Vector3(0, -fore_len * 0.5, 0))
	var wrist := Node3D.new()
	wrist.position = Vector3(0, -fore_len, 0)
	elbow.add_child(wrist)
	match hand:
		"gun":
			# A weapon hardpoint, not a fist. The point of the Lancer is that
			# this is a MOUNT and the catalogue decides what sits on it.
			#
			# ALONG THE FOREARM, not along the wrist's -Z. The first pass put
			# the barrel on local -Z, forgetting that `droop` has already
			# rotated this frame — so with the forearm levelled forward, -Z
			# pointed at the sky and the Lancer held two guns straight up.
			# Continuing down -Y means the barrel follows the limb wherever
			# the arm is posed, which is what a hardpoint does.
			_Parts.box(wrist, Vector3(0.34, 0.42, 0.34) * thick, Vector3(0, -0.16, 0))
			_Parts.cyl(wrist, 0.08 * thick, 1.4, Vector3(0, -1.05, 0))
		"claw":
			# Two opposed jaws. Reads as a grab at any size, which a hand with
			# fingers does not once it is forty pixels tall.
			_Parts.box(wrist, Vector3(0.42, 0.26, 0.34) * thick, Vector3(0, -0.14, 0))
			for s in [-1.0, 1.0]:
				_Parts.wedge(wrist, 0.5, 0.16, 0.14, 0.2,
						Vector3(s * 0.16, -0.5, 0),
						Vector3(90.0 * _Parts.DEG, 0, s * 18.0 * _Parts.DEG))
		"tool":
			# A short multi-tool stub: a cylinder and a lamp, which is what the
			# Reclaimer's language already uses for "this one works".
			_Parts.cyl(wrist, 0.13 * thick, 0.46, Vector3(0, -0.24, 0))
			_Parts.box(wrist, Vector3(0.18, 0.1, 0.06), Vector3(0, -0.46, -0.12))
	return wrist


## The tower shield, which is the Bulwark's entire reason to exist. A slab with
## a rolled rim and a vision slot cut through it, carried on the forearm rather
## than held — a shield a machine has to grip is a shield it cannot shoot past.
static func tower_shield(to: Node, counter_droop: float) -> void:
	# STOOD BACK UP. The shield hangs off the wrist, and the wrist carries the
	# forearm's droop — so built straight into it the slab came out lying flat,
	# a paddle held out sideways rather than a wall held in front. Undoing the
	# droop here keeps it vertical in the world however the arm is posed.
	var mount := Node3D.new()
	mount.rotation = Vector3(-counter_droop * _Parts.DEG, 0, 0)
	to.add_child(mount)
	var face := _Parts.plate(mount, 1.3, 2.0, 0.14, 0.28, Vector3(0, -0.45, -0.34))
	face.name = "Shield"
	var slot := _Parts.box(face, Vector3(0.64, 0.13, 0.5), Vector3(-0.12, 0.66, 0.07))
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.studs(mount, 4, Vector3(-0.44, -1.32, -0.42), Vector3(0.29, 0, 0), 0.045)


# ─────────────────────────────────────────────
# THE FOUR, PLUS THE WALKER TO MEASURE THEM AGAINST
# ─────────────────────────────────────────────



## A bare transform, for hanging a canted assembly off.
static func node_at(to: Node, at: Vector3, euler: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation = euler
	to.add_child(n)
	return n


## A wheel, lying on its side where a wheel goes.
static func wheel(to: Node, at: Vector3, r: float = 0.35, w: float = 0.26) -> void:
	_Parts.cyl(to, r, w, at, Vector3(0, 0, PI * 0.5))


## Four wheels on a hull of the given half-extents.
static func wheels(to: Node, half_w: float, half_l: float, y: float,
		r: float = 0.35) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			wheel(to, Vector3(sx * half_w, y, sz * half_l), r)


## A rotor: a hub and `blades` thin bars, lying flat. The reading of "this
## flies" in one shape.
static func rotor(to: Node, at: Vector3, r: float, blades: int = 4) -> void:
	_Parts.cyl(to, 0.13, 0.18, at)
	for i in blades:
		var a := TAU * float(i) / float(blades)
		_Parts.box(to, Vector3(r, 0.035, 0.1),
				at + Vector3(cos(a) * r * 0.5, 0.05, sin(a) * r * 0.5),
				Vector3(0, -a, 0))


## A boom: a segmented articulated arm, for anything that reaches.
static func boom(to: Node, at: Vector3, len_a: float, len_b: float,
		lift: float, bend: float) -> Node3D:
	var base := node_at(to, at, Vector3(lift * DEG, 0, 0))
	_Parts.cyl(base, 0.16, 0.22, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_Parts.box(base, Vector3(0.22, 0.22, len_a), Vector3(0, 0, -len_a * 0.5))
	var elbow := node_at(base, Vector3(0, 0, -len_a), Vector3(bend * DEG, 0, 0))
	_Parts.sphere(elbow, 0.14, Vector3.ZERO)
	_Parts.box(elbow, Vector3(0.18, 0.18, len_b), Vector3(0, 0, -len_b * 0.5))
	return node_at(elbow, Vector3(0, 0, -len_b), Vector3.ZERO)
