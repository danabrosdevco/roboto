extends RefCounted

# ─────────────────────────────────────────────
# KIT SHAPES — one definition of what each fitting looks like, used by both the
# line-art sheet (mockup_kit.gd) and the in-game screenshots (mockup_shots.gd).
#
# These are mock-ups, not final art, but they are no longer crude: the first
# pass hung flat rectangles off a capsule and every one of them read as a flat
# rectangle. Two rules came out of looking at that sheet, and everything here
# follows them.
#
#   1. BREAK THE OUTLINE. A fitting flush against the body disappears into the
#      silhouette however big it is. Belt items have to stand off to the side.
#   2. NOTHING IS A PLAIN BOX. Real armour is chamfered, pressed and bolted;
#      a slab with square corners reads as a placeholder because it is one.
#      _plate() extrudes a chamfered profile, which costs nothing and is the
#      single biggest difference between "programmer art" and "art".
#
# The body is a 2 m capsule, radius 0.5, centred on the origin. Front is -Z,
# right is +X, the top of the head is y = +1. The three-quarter view used for
# icons looks at the FRONT RIGHT, so that is the side things go on.
# ─────────────────────────────────────────────


# ─────────────────────────────────────────────
# SHAPES
# ─────────────────────────────────────────────

## A chamfered slab: a rectangle with its corners cut, extruded. This is the
## workhorse — armour, pouches, hatches, brims. `bevel` is how much is taken off
## each corner; at 0 it is a plain box again.
static func plate(to: Node, w: float, h: float, depth: float, bevel: float,
		at: Vector3, euler: Vector3 = Vector3.ZERO) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	var x := w * 0.5
	var y := h * 0.5
	var b: float = minf(bevel, minf(x, y) * 0.9)
	p.polygon = PackedVector2Array([
		Vector2(-x + b, -y), Vector2(x - b, -y), Vector2(x, -y + b), Vector2(x, y - b),
		Vector2(x - b, y), Vector2(-x + b, y), Vector2(-x, y - b), Vector2(-x, -y + b)])
	p.depth = depth
	p.position = at
	p.rotation = euler
	to.add_child(p)
	return p


## A slab that tapers front to back, for anything that should read as SHAPED
## rather than stuck on: shoulder guards, glacis plates.
static func wedge(to: Node, w: float, h: float, depth: float, taper: float,
		at: Vector3, euler: Vector3 = Vector3.ZERO) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	var x := w * 0.5
	var y := h * 0.5
	p.polygon = PackedVector2Array([
		Vector2(-x, -y), Vector2(x, -y + taper), Vector2(x, y - taper), Vector2(-x, y)])
	p.depth = depth
	p.position = at
	p.rotation = euler
	to.add_child(p)
	return p


static func box(to: Node, size: Vector3, at: Vector3, euler: Vector3 = Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = at
	b.rotation = euler
	to.add_child(b)
	return b


static func cyl(to: Node, radius: float, height: float, at: Vector3,
		euler: Vector3 = Vector3.ZERO, cone: bool = false, sides: int = 12) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.sides = sides
	c.cone = cone
	c.position = at
	c.rotation = euler
	to.add_child(c)
	return c


static func ring(to: Node, inner: float, outer: float, at: Vector3,
		euler: Vector3 = Vector3.ZERO) -> CSGTorus3D:
	var t := CSGTorus3D.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.sides = 16
	t.ring_sides = 6
	t.position = at
	t.rotation = euler
	to.add_child(t)
	return t


static func sphere(to: Node, radius: float, at: Vector3, squash: Vector3 = Vector3.ONE) -> CSGSphere3D:
	var s := CSGSphere3D.new()
	s.radius = radius
	s.radial_segments = 14
	s.rings = 7
	s.position = at
	s.scale = squash
	to.add_child(s)
	return s


## Bolt heads in a row, which is what makes a plate look BOLTED ON rather than
## floating a centimetre off the hull.
static func studs(to: Node, count: int, from: Vector3, step: Vector3, radius: float = 0.028) -> void:
	for i in count:
		var s := cyl(to, radius, radius * 1.4, from + step * float(i), Vector3(PI * 0.5, 0, 0), false, 6)
		s.name = "Stud%d" % i


const DEG := PI / 180.0


# ─────────────────────────────────────────────
# THE KIT
# ─────────────────────────────────────────────
static func kit_list() -> Array:
	return [
		["STOCK", func(_b): pass],

		# Placed against the body's REAL surface: the capsule is a cylinder of
		# radius 0.5 between y -0.5 and +0.5, and a hemisphere above that, so a
		# plate at chest height sits at z -0.55 and the same plate at shoulder
		# height has to come inboard or it floats. Guessing at this produced
		# armour hovering a hand's width off the hull.
		["ARMOR PLATING", func(b):
			plate(b, 0.74, 0.62, 0.09, 0.16, Vector3(0, 0.08, -0.55))
			plate(b, 0.54, 0.26, 0.07, 0.10, Vector3(0, 0.40, -0.55))
			studs(b, 4, Vector3(-0.27, 0.40, -0.60), Vector3(0.18, 0, 0))
			for side in [1.0, -1.0]:
				plate(b, 0.30, 0.46, 0.16, 0.10, Vector3(0.40 * side, 0.50, -0.04),
					Vector3(PI * 0.5, 0, -13 * DEG * side))
			plate(b, 0.58, 0.26, 0.08, 0.09, Vector3(0, -0.34, -0.55))],
		# A real dish on a mast with a feed horn on a stalk, so it does not read
		# as a lollipop.
		["SENSOR RELAY", func(b):
			cyl(b, 0.045, 0.80, Vector3(0.30, 1.30, 0.14))
			plate(b, 0.20, 0.14, 0.06, 0.05, Vector3(0.30, 0.98, 0.14))
			cyl(b, 0.28, 0.10, Vector3(0.30, 1.72, 0.14), Vector3(40 * DEG, 0, 0), true)
			cyl(b, 0.035, 0.22, Vector3(0.30, 1.62, 0.02), Vector3(40 * DEG, 0, 0))
			sphere(b, 0.05, Vector3(0.30, 1.56, -0.06))],

		# Webbing that goes ROUND the body and over the shoulder, with a hard
		# case on the hip. The strap is a thin plate so it catches the light.
		["UTILITY HARNESS", func(b):
			ring(b, 0.49, 0.60, Vector3(0, 0.10, 0), Vector3(PI * 0.5, 0, 0))
			plate(b, 0.11, 0.66, 0.05, 0.035, Vector3(0.20, 0.24, -0.60), Vector3(0, 0, 26 * DEG))
			plate(b, 0.26, 0.30, 0.20, 0.06, Vector3(0.50, -0.06, -0.26))
			studs(b, 2, Vector3(0.50, 0.02, -0.38), Vector3(0, -0.14, 0))
			plate(b, 0.22, 0.24, 0.16, 0.05, Vector3(0.46, -0.06, 0.20))],

		# Grenades in a CHEST RACK, standing off the body so they break the
		# outline. On the belt they were two dots lost inside the silhouette.
		["FRAG", func(b):
			plate(b, 0.40, 0.18, 0.07, 0.05, Vector3(0.30, -0.10, -0.56), Vector3(0, -28 * DEG, 0))
			for i in 3:
				var at := Vector3(0.40 - i * 0.14, -0.26, -0.40 - i * 0.07)
				cyl(b, 0.075, 0.24, at)
				ring(b, 0.075, 0.105, at + Vector3(0, 0.05, 0), Vector3(PI * 0.5, 0, 0))
				cyl(b, 0.05, 0.05, at + Vector3(0, 0.14, 0))],

		# One canister, fatter, with fins and a live band — it should read as
		# the ODD one on the rack, not as a third frag.
		["EMP", func(b):
			plate(b, 0.30, 0.18, 0.07, 0.05, Vector3(0.34, -0.10, -0.54), Vector3(0, -28 * DEG, 0))
			cyl(b, 0.11, 0.30, Vector3(0.34, -0.26, -0.40), Vector3.ZERO, false, 8)
			ring(b, 0.11, 0.17, Vector3(0.34, -0.20, -0.40), Vector3(PI * 0.5, 0, 0))
			ring(b, 0.11, 0.17, Vector3(0.34, -0.32, -0.40), Vector3(PI * 0.5, 0, 0))
			cyl(b, 0.04, 0.09, Vector3(0.34, -0.44, -0.40))],

		# Ribbed canister in a cradle, slung high on the side where the outline
		# is clear. The ribs are what say "pressure vessel" instead of "tube".
		["HATCHLING", func(b):
			cyl(b, 0.21, 0.62, Vector3(0.44, 0.16, 0.30), Vector3(0, 0, 8 * DEG), false, 10)
			for i in 3:
				ring(b, 0.21, 0.25, Vector3(0.44, -0.02 + i * 0.18, 0.30), Vector3(PI * 0.5, 0, 0))
			cyl(b, 0.08, 0.14, Vector3(0.46, 0.52, 0.30))
			plate(b, 0.12, 0.34, 0.26, 0.04, Vector3(0.32, 0.16, 0.30))],

		# Deliberately minor: a cell in a chamfered cradle with one slot for the
		# charge light. You should have to look for it.
		["NANITE REBOOT", func(b):
			plate(b, 0.22, 0.30, 0.14, 0.06, Vector3(0.44, 0.34, 0.26))
			plate(b, 0.07, 0.19, 0.04, 0.02, Vector3(0.53, 0.34, 0.26))
			studs(b, 2, Vector3(0.44, 0.46, 0.19), Vector3(0, -0.24, 0))],

		# A tool head, not a bag: a stubby arm with a two-jaw clamp and a spool
		# of wire behind it. Mechanical, as asked.
		["REPAIR KIT", func(b):
			plate(b, 0.16, 0.16, 0.40, 0.05, Vector3(0.54, -0.10, 0.10))
			wedge(b, 0.10, 0.26, 0.12, 0.10, Vector3(0.54, -0.01, 0.34), Vector3(26 * DEG, 0, 0))
			wedge(b, 0.10, 0.26, 0.12, 0.10, Vector3(0.54, -0.23, 0.34), Vector3(-26 * DEG, 0, 0))
			cyl(b, 0.13, 0.13, Vector3(0.54, -0.10, -0.16), Vector3(0, 0, PI * 0.5), false, 10)
			ring(b, 0.07, 0.13, Vector3(0.54, -0.10, -0.16), Vector3(0, 0, PI * 0.5))],

		# A drum and a belt of individual rounds climbing into the receiver. The
		# rounds are the point: this is the module that spends them.
		["CYCLIC FEED", func(b):
			cyl(b, 0.19, 0.20, Vector3(0.46, -0.06, 0.02), Vector3(0, 0, PI * 0.5), false, 10)
			ring(b, 0.10, 0.19, Vector3(0.46, -0.06, 0.02), Vector3(0, 0, PI * 0.5))
			for i in 7:
				box(b, Vector3(0.055, 0.10, 0.055),
					Vector3(0.50, 0.04 + i * 0.045, -0.10 - i * 0.055), Vector3(36 * DEG, 0, 0))],

		# Pistons at the joints, not hoops round the waist. The first pass drew
		# two rings that read as a second silhouette rather than as machinery.
		["OVERCLOCK SERVOS", func(b):
			for side in [1.0, -1.0]:
				cyl(b, 0.10, 0.30, Vector3(0.46 * side, 0.34, -0.10), Vector3(0, 0, 18 * DEG * side))
				cyl(b, 0.06, 0.22, Vector3(0.46 * side, 0.14, -0.10), Vector3(0, 0, 18 * DEG * side))
				ring(b, 0.10, 0.145, Vector3(0.46 * side, 0.46, -0.10), Vector3(0, 0, PI * 0.5))
				cyl(b, 0.09, 0.26, Vector3(0.40 * side, -0.50, -0.06), Vector3(0, 0, -10 * DEG * side))
				ring(b, 0.09, 0.13, Vector3(0.40 * side, -0.36, -0.06), Vector3(0, 0, PI * 0.5))],

		# A blade antenna — a flat fin, the way a hardened set really is, rather
		# than a whip that would snap off the first time it was shot at.
		["HARDENED UPLINK", func(b):
			plate(b, 0.10, 0.52, 0.05, 0.10, Vector3(0.28, 1.16, 0.08), Vector3(0, 0, -8 * DEG))
			plate(b, 0.20, 0.13, 0.16, 0.05, Vector3(0.28, 0.96, 0.08))
			studs(b, 2, Vector3(0.28, 0.96, 0.00), Vector3(0.10, 0, 0))],
	]


# ─────────────────────────────────────────────
# THE HATS — the promotion tell.
# ─────────────────────────────────────────────
static func hat_list() -> Array:
	return [
		["BARE", func(_b): pass],
		# All cloth, so all camo.
		["BERET", func(b):
			as_fabric(cyl(b, 0.38, 0.12, Vector3(-0.06, 1.02, 0.02), Vector3(14 * DEG, 0, 0)))
			sphere(b, 0.07, Vector3(-0.06, 1.11, 0.02))],
		# THE HEAD IS THE TOP OF A CAPSULE, not a sphere on a neck, so a cap has
		# to follow that dome: the hemisphere is centred at y 0.5 with radius
		# 0.5, which means a flat-bottomed cylinder sat on top leaves a gap in
		# the middle and clips at the rim. A slightly larger dome, a band round
		# it where the body is 0.45 across, and a peak off the front.
		# CROWN AND PEAK BOTH IN CAMO — a covered cap, where the peak is cloth
		# over a stiffener rather than bare patent leather. Only the band and the
		# badge stay hard, which is what keeps it reading as a cap and not a hood.
		# IT MUST CLEAR THE EYE. The crown was a full sphere r 0.53 centred at
		# y 0.52, so its lower half ran from y 0.022 upward and passed straight
		# through the sensor pod, which tops out at y 0.583 and stands proud to
		# z -0.604. A sphere sleeved over the whole head will always do that.
		#
		# A cap instead: squashed, raised, and stopped above the pod. Centre
		# y 0.90 with a 0.55 vertical squash bottoms the crown at 0.658, clear of
		# the eye by 0.075, and tops it at 1.142 — just over the head's own 1.0.
		# The band goes at y 0.80, because that is the height where the capsule
		# is 0.40 across and a rim only reads as a rim if it meets the head.
		["PEAKED CAP", func(b):
			as_fabric(sphere(b, 0.44, Vector3(0, 0.90, 0), Vector3(1.0, 0.55, 1.0)))
			ring(b, 0.40, 0.47, Vector3(0, 0.80, 0))
			as_fabric(plate(b, 0.52, 0.30, 0.045, 0.11, Vector3(0, 0.78, -0.47), Vector3(72 * DEG, 0, 0)))
			plate(b, 0.09, 0.09, 0.03, 0.03, Vector3(0, 0.95, -0.38), Vector3(20 * DEG, 0, 0))],
		["HELMET", func(b):
			sphere(b, 0.42, Vector3(0, 0.94, 0), Vector3(1.0, 0.78, 1.0))
			ring(b, 0.40, 0.45, Vector3(0, 0.95, 0), Vector3(PI * 0.5, 0, 0))],
		["CRESTED HELMET", func(b):
			sphere(b, 0.42, Vector3(0, 0.94, 0), Vector3(1.0, 0.78, 1.0))
			plate(b, 0.62, 0.26, 0.05, 0.10, Vector3(0, 1.20, 0), Vector3(0, PI * 0.5, 0))],
		["HARD HAT", func(b):
			sphere(b, 0.34, Vector3(0, 0.98, 0), Vector3(1.0, 0.82, 1.0))
			plate(b, 0.14, 0.34, 0.05, 0.03, Vector3(0, 1.16, 0), Vector3(0, PI * 0.5, 0))
			ring(b, 0.32, 0.50, Vector3(0, 0.98, 0), Vector3(PI * 0.5, 0, 0))],
		["STOVEPIPE", func(b):
			cyl(b, 0.27, 0.58, Vector3(0, 1.26, 0), Vector3.ZERO, false, 16)
			ring(b, 0.26, 0.32, Vector3(0, 1.06, 0), Vector3(PI * 0.5, 0, 0))
			cyl(b, 0.45, 0.06, Vector3(0, 0.99, 0), Vector3.ZERO, false, 16)],
		["BICORNE", func(b):
			cyl(b, 0.34, 0.40, Vector3(-0.24, 1.12, 0), Vector3(0, 0, 30 * DEG), true)
			cyl(b, 0.34, 0.40, Vector3(0.24, 1.12, 0), Vector3(0, 0, -30 * DEG), true)
			ring(b, 0.30, 0.38, Vector3(0, 1.00, 0), Vector3(PI * 0.5, 0, 0))],
		["ANTENNA CROWN", func(b):
			ring(b, 0.30, 0.44, Vector3(0, 1.00, 0), Vector3(PI * 0.5, 0, 0))
			for a in [0.0, 120.0, 240.0]:
				var r: float = a * DEG
				cyl(b, 0.03, 0.42, Vector3(sin(r) * 0.28, 1.22, cos(r) * 0.28))],
		["CAMPAIGN HAT", func(b):
			cyl(b, 0.50, 0.30, Vector3(0, 1.08, 0), Vector3.ZERO, true, 16)
			ring(b, 0.44, 0.56, Vector3(0, 0.96, 0), Vector3(PI * 0.5, 0, 0))],
		["LAUREL", func(b):
			ring(b, 0.32, 0.46, Vector3(0, 1.26, 0), Vector3(PI * 0.5, 0, 0))],
	]


# ─────────────────────────────────────────────
# RANK — the promotion ladder, assembled.
# ─────────────────────────────────────────────
# SoldierRecord carries six ranks and the squad manager already prints them as
# chevrons; nothing shows them in the world. Six map onto three forms at two
# apiece, so the tier is `rank / 2` and no new save field is needed.
#
# THE CAPSULE HAS NO SHOULDERS AND NO HEAD, which leaves exactly two places to
# put anything: cap the dome, or widen the waist. They fail in opposite views —
# a cap is invisible head-on and pads are invisible in profile — so the ladder
# uses both, and the pads are what carries from Veteran upward.
#
# PADS ARE A YOKE, NOT TWO PLATES, on purpose. `ARMOR PLATING` in kit_list
# already bolts a plate to each shoulder, so a rank mark built the same way is
# ambiguous: you could not tell a Veteran from a Regular wearing armour. A strap
# that crosses the crown is a shape no fitting in the kit makes, so it can only
# mean one thing.
#
# Everything here is seated with wrapped_plate and tile rather than placed by
# eye, because the shoulder is where the capsule stops being a cylinder and
# becomes a dome — a flat plate pinned there touches along one line and lifts
# off at both ends.


## The pair of shoulder pads. Carried by every form above Regular.
##
## SHAPED LIKE REAL PLATE, after three attempts that were not. The first
## wrapped flat tiles to the hull and vanished into the silhouette; the second
## and third built flaring slabs that read, in the photograph, as wings. A
## pauldron is neither: it is a rounded cap over the shoulder point with a
## stack of horizontal lames hanging below it, and the lames FOLLOW the body.
##
## Only the dome stands proud. That is the whole silhouette change, and it is
## enough, because it sits above the shoulder line where nothing else on this
## frame competes.
static func shoulder_pads(to: Node) -> void:
	for side in [1.0, -1.0]:
		# A CUPPED DOME WITH LAMES HANGING OFF IT, which is what a real pauldron
		# is and what the last three attempts were not. Those built the pad as
		# flat plates flaring up and outward, and the render was unambiguous:
		# they read as wings. A pauldron does the opposite — it CAPS the
		# shoulder point with a rounded dome and then hangs a stack of
		# horizontal lames DOWN the arm, each one following the body rather
		# than escaping it.
		#
		# So the silhouette break is the dome, and it is the only part that
		# stands proud. Everything below it hugs.
		#
		# The dome is squashed and pushed slightly forward, because a shoulder
		# point is not on the robot's beam — it is forward of it, where the arm
		# would hang.
		# MEASURED OFF soldier_chassis.tscn, not estimated. The body is a default
		# CapsuleMesh — radius 0.5, height 2.0 — so its crown is a hemisphere
		# centred (0, 0.5, 0), and the sensor pod is a 0.2 x 0.6 capsule at
		# (-0.02, 0.283, -0.404), which puts the EYE at y -0.017 to 0.583 and
		# standing proud to z -0.604.
		#
		# This dome was radius 0.40 at x 0.36, which spans x -0.04 to 0.76: the
		# two pads met across the centreline and sheeted the whole crown, and
		# they sat at y 0.52 — the same height as the cap. Photographed from the
		# side it read as one helmet, not two shoulders.
		#
		# A FACETED COP, NOT A BALL. This was a squashed CSGSphere, and a sphere
		# has no edge anywhere on it — smooth-shaded it melted into the capsule
		# and read as a growth rather than as armour. Armour reads BECAUSE of its
		# edges: the flange where the plate ends, the steps between tiers, the
		# spine down the middle. None of that survives on a sphere.
		#
		# It is built along an axis leaning 40 degrees above horizontal out of the
		# shoulder, from four parts that each do one job:
		#
		#   FLANGE  a near-flat octagonal disc, 0.70 across and 0.04 thick. This
		#           is the hard outer lip, and it is the single piece doing the
		#           most work — it is what gives the pad an END.
		#   SHELL   one lopped eight-sided cone tapering 0.64 to 0.29 over 0.20.
		#           NOT a stack of tiers: the first attempt stepped four drums up
		#           the axis and photographed as a pile of washers, because steps
		#           seen side-on are a coin stack and not a dome.
		#   BOSS    a small hex cap closing the shell's top face. It used to sit
		#           at 0.30 along the axis while the shell ended at 0.235, so it
		#           floated four centimetres clear of the pad — one of the loose
		#           parts in the render. It sits ON the shell now.
		#   RIVETS  three on the flange, where it would really be strapped.
		#
		# THERE WAS A KEEL, a bar across the crown running fore and aft and proud
		# at both ends, on the argument that an eight-sided cone without one is
		# just a nut. Cut: photographed it read as a rectangular bar stuck to the
		# shoulder and nothing more. If the crown ever does need breaking up it
		# should be a shape that belongs to the cone, not a box laid over it.
		var lean: float = 50.0 * DEG                       # measured off vertical
		var axis := Vector3(sin(lean) * side, cos(lean), 0.0)
		var rot := Vector3(0, 0, -lean * side)
		var bas := Basis(Vector3(0, 0, 1), -lean * side)
		var root := Vector3(0.44 * side, 0.30, -0.02)
		# Clearances measured the same way as the sphere's were: the flange's
		# inboard lip lands at x 0.215 against the eye's outer edge at 0.18, and
		# its top at y 0.568 against the cap's rim at 0.658.
		as_plate(frustum(to, 0.70, 0.70, 0.040, 0.92, root, bas, 8))
		as_plate(frustum(to, 0.64, 0.64, 0.200, 0.45, root + axis * 0.035, bas, 8))
		# Seated so it overlaps the shell's top face at 0.235 rather than hovering
		# over it.
		as_plate(cyl(to, 0.07, 0.05, root + axis * 0.245, rot, false, 6))
		var fore := Vector3(0, 0, -1.0)
		var across: Vector3 = axis.cross(fore)
		for k in 3:
			var a: float = (float(k) - 1.0) * 0.62
			var at: Vector3 = root + axis * 0.035 \
					+ (fore * cos(a) + across * sin(a)) * 0.29
			as_plate(cyl(to, 0.026, 0.045, at, rot, false, 6))
		# NO RIM TORUS. There was a ring here reading the dome's lower edge as a
		# rolled lip, and it was right while the pads were untextured — but
		# pauldron_plate paints that roll in and holds it out of the faction
		# colour, so the modelled one became a second, competing edge: a band
		# round each pad. The texture now does the job the geometry stood in for.

		# THE LAMES, WRAPPED NOT FLAT. wrapped_plate cuts each band out of a
		# cylinder of the hull's own radius, so the bands curve round the body
		# the way the steel ones curve round an arm. This is the same helper the
		# first attempt was rejected for using — it was the wrong tool for a
		# mark meant to break the outline, and it is exactly the right one for
		# armour meant to follow it.
		#
		# Four bands, narrowing as they descend, with a gap between each so the
		# overlap reads. The lowest is the roll-edged cuff.
		var drops: Array = [[0.20, 0.74], [0.06, 0.70], [-0.08, 0.64], [-0.22, 0.56]]
		var first_lame: int = to.get_child_count()
		for row: Array in drops:
			wrapped_plate(to, 90.0 * side, row[0], row[1], 0.145, 0.06, 4)
		# wrapped_plate adds its facets straight to the parent and returns
		# nothing, so the lames get tagged by range instead of inline. The
		# grain in pauldron_lame runs along them, which is the direction
		# rolled steel is actually finished in.
		for i in range(first_lame, to.get_child_count()):
			as_lame(to.get_child(i))
		# Two rivets at the pivot, where the lames would actually be strapped.
		studs(to, 2, Vector3(0.50 * side, 0.21, -0.20), Vector3(0, 0, 0.30), 0.026)
# ─────────────────────────────────────────────
# VETERAN KIT FOR THE VEHICLE FRAMES
# ─────────────────────────────────────────────
# Same three rules the soldier's pauldrons cost eight renders to learn:
#
#   1. ARMOUR FOLLOWS THE BODY. The versions that escaped it read as wings.
#      Every plate below runs along a hull line that is already there.
#   2. ONE PIECE BREAKS THE SILHOUETTE, and it is chosen where that frame has
#      clear air — the rover's screens stand off the flanks, the walker's cops
#      sit on its knees, the reclaimer's load stands above its deck.
#   3. SOMETHING IS CLOTH. The camo on the soldier's cap carried further at
#      squad distance than any geometry did, so each vehicle gets a fabric
#      piece in the same material. On a vehicle that is a lashed roll, which is
#      also what every real one carries.
#
# Positions are read off the scenes, not guessed: all three frames face -Z, the
# rover's hull sits at y -0.22 and is 1.5 x 0.62 x 3.2, the walker's at y 0.3
# with its turret ring at 0.76, the reclaimer's deck at y 0.29.


## ROVER — slat screens, a bolted glacis, and a roll on the bustle.
##
## SLAT ARMOUR IS THE WHOLE IDEA. Standing bar screens over the flanks are the
## most legible "this one has been shot at and modified" mark any wheeled
## vehicle carries, they are cheap geometry, and they run along the hull line
## rather than away from it. The rover already ships with an antenna, so the
## mast is spent as a tell and this is what is left.
static func rover_veteran(to: Node) -> void:
	# APPLIQUÉ ON THE HULL, NOT RAILINGS ON THE FENDER.
	#
	# This was a slat screen: two rails and eight uprights standing at x 0.86 on
	# the fender deck. The hull side is at x 0.75 and the fender at 0.9, so the
	# screen stood a hand's width OFF the vehicle with daylight behind it, and
	# photographed it read as a guardrail round a boat deck.
	#
	# The shipped vehicles are not made of bars. Every one of them is a BoxMesh
	# with rotated CSGBox subtractions cutting the chamfers — Glacis, Tail,
	# BellyL, BellyR on this hull, Face on its turret. So the armour is bevelled
	# slabs lying ON the hull flank, which is both the right idiom and what
	# appliqué actually is.
	for side in [1.0, -1.0]:
		var out: Vector3 = Vector3(0, PI * 0.5 * side, 0)
		# Main flank plate, hard against the hull side at 0.75 and 0.07 proud.
		plate(to, 2.46, 0.42, 0.07, 0.11, Vector3(0.75 * side, -0.20, 0.06), out)
		# A second, shorter course above it, stepped in — spaced armour reads as
		# layers, and one slab the full height reads as a thicker hull.
		plate(to, 1.54, 0.20, 0.06, 0.06, Vector3(0.75 * side, 0.02, 0.28), out)
		studs(to, 5, Vector3(0.80 * side, -0.33, -0.86), Vector3(0, 0, 0.46), 0.03)
		# Turret cheeks, hugging it at 0.48 rather than flanking it in mid-air.
		plate(to, 0.92, 0.24, 0.06, 0.07, Vector3(0.48 * side, 0.36, 0.24), out)
	# Bolted appliqué across the nose, under the glacis.
	plate(to, 1.18, 0.38, 0.09, 0.09, Vector3(0, -0.20, -1.64))
	studs(to, 4, Vector3(-0.42, -0.06, -1.70), Vector3(0.28, 0, 0))
	# Jerrycans on the rear deck.
	for i in 3:
		box(to, Vector3(0.18, 0.34, 0.12), Vector3(-0.30 + i * 0.30, 0.10, 1.34))
	# THE CLOTH: a rolled cam net lashed across the turret bustle.
	as_fabric(cyl(to, 0.15, 0.86, Vector3(0, 0.33, 0.62), Vector3(0, 0, PI * 0.5), false, 10))


## WALKER — knee cops, shin greaves and hip skirts.
##
## THE KNEES ARE THE POINT, and they are the same vocabulary as the soldier's
## pauldron reused on a different joint: a cupped dome with a rolled rim, and
## plate hanging below it. A legged frame takes its hits on the legs, and the
## knee of a three-metre walker is at the head height of everything shooting at
## it from a doorway.
##
## PARENTED TO THE LEG NODES, not placed in hull space. KneeL and ShinL are real
## nodes under the rig, so armour added to them rides the walk cycle instead of
## hanging in the air beside a moving leg.
static func walker_veteran(to: Node) -> void:
	# ON THE BONES, NOT ON THE JOINT. The first pass hung the cop on the KneeL
	# node, and photographed it came out sitting on the foot — the rig's rest
	# pose puts that pivot much lower down the leg than the node list suggests.
	# ThighL and ShinL are long bones whose origins are at their TOPS, so
	# measuring down from those is reliable where measuring from a pivot is not.
	for side: String in ["L", "R"]:
		var thigh := to.find_child("Thigh" + side, true, false)
		if thigh != null:
			plate(thigh, 0.36, 0.50, 0.30, 0.09, Vector3(0, -0.22, 0.02))
			studs(thigh, 2, Vector3(0, -0.06, -0.16), Vector3(0, -0.30, 0), 0.026)
		else:
			push_warning("mockup_parts: walker has no Thigh%s to armour" % side)
		var shin := to.find_child("Shin" + side, true, false)
		if shin != null:
			# The cop, at the top of the shin, which IS the knee.
			sphere(shin, 0.25, Vector3(0, 0.08, 0.06), Vector3(1.0, 0.80, 1.10))
			ring(shin, 0.19, 0.26, Vector3(0, -0.02, 0.06))
			# The greave below it.
			plate(shin, 0.34, 0.44, 0.28, 0.08, Vector3(0, -0.30, -0.06))
	# Skirts over the hip pivots, hung off the hull sides.
	for side in [1.0, -1.0]:
		plate(to, 0.12, 0.46, 1.40, 0.08, Vector3(0.84 * side, 0.04, 0.05))
		studs(to, 3, Vector3(0.90 * side, 0.22, -0.44), Vector3(0, 0, 0.46), 0.028)
	# Bolted cheek plates either side of the turret face.
	for side in [1.0, -1.0]:
		plate(to, 0.09, 0.30, 0.44, 0.05, Vector3(0.52 * side, 1.00, -0.42))
	# THE CLOTH: a roll lashed across the turret bustle, same as the rover's.
	as_fabric(cyl(to, 0.14, 0.78, Vector3(0, 1.06, 0.52), Vector3(0, 0, PI * 0.5), false, 10))


## RECLAIMER — a working load, and the one thing a recovery vehicle always has.
##
## IT ALREADY HAS A BEACON (BeaconPost and Beacon, on the engine deck), which
## kills the obvious idea. What it does not have is a LOAD, and a recovery
## vehicle's veterancy is exactly that: spare track links bolted to the nose,
## a roadwheel and a coiled tow cable on the deck, and a grille over the cab
## glass. Track links hung on the glacis are the oldest field modification
## there is and they read instantly as a vehicle that works under fire.
static func reclaimer_veteran(to: Node) -> void:
	# Spare track links across the nose. Slightly uneven on purpose: a bolted
	# row of identical blocks reads as a radiator.
	for i in 6:
		var y: float = 0.08 + (0.03 if i % 2 == 0 else 0.0)
		box(to, Vector3(0.17, 0.13, 0.10), Vector3(-0.47 + i * 0.19, y, -1.18))
	# Grille over the cab visor.
	for i in 4:
		box(to, Vector3(0.025, 0.26, 0.025), Vector3(-0.44 + i * 0.09, 0.42, -0.72))
	box(to, Vector3(0.40, 0.03, 0.04), Vector3(-0.30, 0.55, -0.72))
	# THE LOAD STANDS UP OFF THE DECK. The first pass laid it flat at y 0.40
	# and the whole lot sank into the deck clutter the frame already carries —
	# an engine, three grilles, two gas bottles and a crane. Everything here is
	# raised, and each piece is on its own part of the bed so they read as
	# separate objects rather than as one lumpy pile.
	# Spare roadwheel, stood on edge against the crane post.
	cyl(to, 0.28, 0.12, Vector3(0.40, 0.62, 0.30), Vector3(0, 0, PI * 0.5), false, 12)
	# Coiled tow cable, portside.
	ring(to, 0.18, 0.31, Vector3(-0.30, 0.52, 0.40))
	# Tool locker, forward on the bed.
	plate(to, 0.48, 0.30, 0.36, 0.06, Vector3(0.28, 0.56, -0.14))
	studs(to, 3, Vector3(0.10, 0.60, -0.14), Vector3(0, 0, 0.14), 0.024)
	# THE CLOTH: a tarp roll lashed the length of the starboard rail, opposite
	# the cable so the two do not stack.
	as_fabric(cyl(to, 0.14, 1.50, Vector3(0.64, 0.50, 0.20), Vector3(PI * 0.5, 0, 0), false, 10))


# ─────────────────────────────────────────────
# HEADGEAR FOR THE VEHICLE FRAMES
# ─────────────────────────────────────────────
# One real hat per frame, chosen for that frame rather than shared, on the
# argument that a Rover is not an officer in the same way a Walker is.
#
# EVERY HEIGHT BELOW IS MEASURED, not estimated. The chamfers on these turrets
# are CSG SUBTRACTIONS (operation = 2 on Brow, Cheek, Face, Glacis), which means
# the mesh sizes in the scene are the UNCUT block and the real roof is smaller
# than the numbers suggest. Measured through the subtractions:
#
#   rover      turret body 0.96 x 0.36 x 1.20 at (0, 0.37, 0.20); Face cuts the
#              front, so the flat roof is y 0.55 from about z -0.10 back to 0.80
#   walker     turret body 1.18 x 0.60 x 1.30 at (0, 0.95, 0); Brow cuts the
#              front-top, so the flat roof is y 1.25 from z -0.29 back to 0.65
#   reclaimer  cab 0.34 x 0.24 x 0.44 at (-0.30, 0.38, -0.44), roof y 0.50
#
# Placed in rig space and added to the root, which is what rover_veteran and the
# rest already do. A shipping version should hang these off the Turret node so
# they traverse with it; for a still that makes no difference.


# THE FOUR RULES, learned the expensive way across six rejected builds:
#
#   1. OVERHANG. The brim must be wider than the roof it sits on. Flush is
#      invisible — the eye reads one taller turret, not a hat.
#   2. TILT. Ten to fifteen degrees off the hull axis. Nothing on a working
#      vehicle sits askew, so a thing that does reads instantly as PLACED.
#   3. CURVE. These hulls are entirely flats and chamfers. Matching that idiom
#      was right for armour and wrong here: chamfered boxes on a chamfered box
#      are more vehicle. The contrast is what makes a hat read as worn.
#   4. ONE MASS for the crown. Stacking courses to fake a dome photographed as
#      a pile of books. Parts the REAL hat has — band, peak, plume, cords — are
#      not a violation of this; they are what makes it legible.
#   5. BUILD THE ACTUAL ARTICLE, from the parts it has, named as those parts.
#      Working from the silhouette gave five rounded lumps differing only in
#      height.
#
# AND THE SIXTH, which this pass is: NOTHING MAY CROSS AN EYE. Each of these
# frames has one, they are small, and a hat brim lands on them by default
# because a brim is exactly as wide as a face. Measured:
#
#   walker     Rig/Turret/Eye, SphereMesh r 0.17 h 0.28 at (-0.34, 1.09, -0.66)
#              -> y 0.95..1.23, x -0.51..-0.17, z -0.83..-0.49
#   rover      Rig/Turret/Sensor, capsule r 0.10 h 0.36 laid across X, at
#              (0.3, 0.59, 0.03) -> stands 0.14 PROUD of its own roof
#   reclaimer  Rig/Visor at (-0.30, 0.42, -0.67), top y 0.455
#
# Roof heights, measured through the CSG subtractions because the mesh sizes in
# the scenes are the uncut block:
#   rover      turret 0.96 x 0.36 x 1.20 at (0, 0.37, 0.20), roof y 0.55
#   walker     turret 1.18 x 0.60 x 1.30 at (0, 0.95, 0),    roof y 1.25
#   reclaimer  cab    0.34 x 0.24 x 0.44 at (-0.30, 0.38, -0.44), roof y 0.50


## A forward cock, as an axis and a matching euler. Rotating about X by -lean
## takes +Y to (0, cos, -sin), which tips the crown toward the bow.
static func _cock(lean_deg: float) -> Array:
	var a: float = lean_deg * DEG
	return [Vector3(0, cos(a), -sin(a)), Vector3(-a, 0, 0)]


## ROVER — a beret.
##
## SITED ROUND THE SENSOR, which stands 0.14 proud of the roof at starboard
## forward and which the last build ran straight through. The crown is rolled
## +13 about Z so it leans to PORT: the droop falls on the port side and the
## starboard side rides UP, over the sensor. A real beret is pulled to the right
## with the badge over the left eye; this is the mirror of that, because the
## sensor is on the right and clearance beats correctness.
static func rover_beret(to: Node) -> void:
	var rot := Vector3(7 * DEG, 0, 13 * DEG)
	ring(to, 0.30, 0.37, Vector3(-0.03, 0.66, 0.34))
	# THE FOLD — the lip where the wool is pulled over the leather and turns
	# under. Without it the crown melts into the band and it is a pebble.
	as_wool(cyl(to, 0.47, 0.03, Vector3(-0.05, 0.70, 0.34), rot, false, 18))
	var crown := sphere(to, 0.46, Vector3(-0.08, 0.75, 0.34), Vector3(1.0, 0.27, 0.94))
	crown.rotation = rot
	as_wool(crown)
	# The droop, to port and well aft of the sensor.
	as_wool(sphere(to, 0.22, Vector3(-0.40, 0.62, 0.40), Vector3(1.0, 0.50, 0.88)))
	as_wool(cyl(to, 0.02, 0.045, Vector3(-0.10, 0.83, 0.34), rot, false, 6))
	# Flash and badge to starboard forward, clear of the sensor in z.
	as_wool(plate(to, 0.20, 0.22, 0.03, 0.05, Vector3(0.21, 0.71, -0.14), rot))
	as_plate(plate(to, 0.12, 0.16, 0.05, 0.03, Vector3(0.21, 0.71, -0.18), rot))


## ROVER — a shako, rebuilt.
##
## The last one was a squat drum with a ball on a stick and it read as a bin
## with a lollipop. Three changes: TALLER AND NARROWER (0.33 rising to 0.37 over
## 0.74, where it was 0.36/0.40 over 0.62), the pompom-on-a-mast replaced with a
## proper tapered plume rising straight off the false top, and the festoon hoop
## dropped — at this scale it read as a ring someone had left on it.
##
## Pushed to z 0.32 so the body clears the sensor at (0.3, *, 0.03).
static func rover_shako(to: Node) -> void:
	var c: Array = _cock(7.0)
	var axis: Vector3 = c[0]
	var rot: Vector3 = c[1]
	var base := Vector3(0, 0.55, 0.32)
	as_wool(cyl(to, 0.33, 0.40, base + axis * 0.20, rot, false, 14))
	as_wool(cyl(to, 0.37, 0.36, base + axis * 0.56, rot, false, 14))
	as_plate(cyl(to, 0.43, 0.05, base + axis * 0.76, rot, false, 14))
	# THE FRONT PLATE, which is what a shako IS seen head-on. Big and bright.
	as_plate(plate(to, 0.46, 0.52, 0.05, 0.10, Vector3(0, 0.96, -0.08),
			Vector3(-6 * DEG, 0, 0)))
	as_plate(plate(to, 0.66, 0.26, 0.05, 0.09, Vector3(0, 0.64, -0.22),
			Vector3(76 * DEG, 0, 0)))
	# One tapered plume off the false top. No mast, no ball.
	as_plate(cyl(to, 0.085, 0.52, base + axis * 1.06 + Vector3(-0.04, 0, -0.06),
			Vector3(-5 * DEG, 0, 6 * DEG), true, 8))
	for s in [1.0, -1.0]:
		as_plate(cyl(to, 0.05, 0.03, base + axis * 0.30 + Vector3(0.33 * s, 0, 0),
				Vector3(0, 0, PI * 0.5), false, 8))


## WALKER — a Tarleton.
##
## THE PEAK BINDING IS GONE and the peak itself has moved up to y 1.33, because
## the Eye tops out at 1.23 and both were crossing it — the binding was a bright
## chrome bar sitting exactly at eye height, which is the white bar in the
## render. The peak now starts above the eye and never reaches down past it.
##
## THE ROACH IS METAL. It reads as a polished comb rather than fur, which suits
## a robot wearing a cavalry helmet better than fur would.
static func walker_tarleton(to: Node) -> void:
	var skull := sphere(to, 0.68, Vector3(0, 1.24, 0.12), Vector3(1.0, 0.62, 0.94))
	skull.rotation = Vector3(-7 * DEG, 0, 0)
	as_plate(skull)
	as_wool(ring(to, 0.60, 0.77, Vector3(0, 1.29, 0.12)))
	# 1.32 long against 0.92 tall — a real roach is about half again as long as
	# it is tall, and a 1:1 version reads as a fin.
	as_plate(sphere(to, 1.0, Vector3(0, 1.68, 0.06), Vector3(0.11, 0.46, 0.66)))
	# Peak: shallower, higher, and stopping at y 1.26 against the eye's 1.23.
	as_plate(plate(to, 0.88, 0.30, 0.05, 0.12, Vector3(0, 1.33, -0.80),
			Vector3(72 * DEG, 0, 0)))
	as_plate(cyl(to, 0.08, 0.44, Vector3(-0.58, 1.74, -0.20),
			Vector3(0, 0, 11 * DEG), true, 8))
	as_plate(cyl(to, 0.11, 0.05, Vector3(-0.60, 1.46, -0.20),
			Vector3(0, 0, PI * 0.5), false, 10))


## WALKER — a peaked cap. THE PEAK IS GONE at your call, which makes this
## strictly a field cap rather than a service cap; the crown rake, the band, the
## chin cord on its two buttons and the badge are what now carry it. Say the
## word and a slimmer peak goes back on.
##
## The crown is rotated +11 about X — leaning BACK so its front edge lifts, the
## opposite sign to every other hat here and the thing that separates a service
## cap from a bowler.
static func walker_peaked_cap(to: Node) -> void:
	as_plate(cyl(to, 0.62, 0.17, Vector3(0, 1.33, 0.10), Vector3.ZERO, false, 16))
	var crown := sphere(to, 0.76, Vector3(0, 1.49, 0.14), Vector3(1.0, 0.32, 0.92))
	crown.rotation = Vector3(11 * DEG, 0, 0)
	as_wool(crown)
	# Chin cord on two buttons. Held at z -0.60 and y 1.31, above the eye's
	# 1.23 ceiling.
	as_plate(cyl(to, 0.022, 0.92, Vector3(0, 1.33, -0.60),
			Vector3(0, 0, PI * 0.5), false, 6))
	for s in [1.0, -1.0]:
		as_plate(cyl(to, 0.05, 0.035, Vector3(0.46 * s, 1.33, -0.58),
				Vector3(0, 0, PI * 0.5), false, 8))
	as_plate(plate(to, 0.17, 0.20, 0.05, 0.04, Vector3(0, 1.38, -0.58),
			Vector3(-14 * DEG, 0, 0)))


## WALKER — a bearskin. The chrome headband is gone; a real one has no visible
## band, the fur runs straight down to the head. Wants bearskin_fur, briefed in
## docs/briefs/BEARSKIN_FUR.md and not built yet.
static func walker_bearskin(to: Node) -> void:
	var c: Array = _cock(5.0)
	var axis: Vector3 = c[0]
	var rot: Vector3 = c[1]
	var base := Vector3(0, 1.22, 0.10)
	as_fur(cyl(to, 0.56, 0.96, base + axis * 0.48, rot, false, 16))
	# Crown cap WIDER than the column — the bulge near the top is what stops it
	# reading as a chimney.
	as_fur(sphere(to, 0.63, base + axis * 1.00, Vector3(1.0, 0.56, 1.0)))
	# Chin chain across the turret face, its buttons ON the chain line.
	as_plate(cyl(to, 0.026, 1.12, Vector3(0, 1.20, -0.46),
			Vector3(0, 0, PI * 0.5), false, 6))
	for s in [1.0, -1.0]:
		as_plate(cyl(to, 0.042, 0.035, Vector3(0.55 * s, 1.20, -0.46),
				Vector3(0, 0, PI * 0.5), false, 8))
	as_plate(cyl(to, 0.09, 0.50, Vector3(-0.52, 2.08, -0.28),
			Vector3(0, 0, 9 * DEG), true, 8))


## RECLAIMER — a hard hat, raised 0.10 clear of Rig/Visor.
static func reclaimer_hardhat(to: Node) -> void:
	var c: Array = _cock(11.0)
	var axis: Vector3 = c[0]
	var rot: Vector3 = c[1]
	var base := Vector3(-0.30, 0.60, -0.44)
	as_hivis(sphere(to, 0.27, base + axis * 0.03, Vector3(1.0, 0.72, 1.10)))
	as_hivis(cyl(to, 0.32, 0.025, base, rot, false, 16))
	as_hivis(plate(to, 0.40, 0.21, 0.03, 0.06, Vector3(-0.30, 0.59, -0.74),
			Vector3(78 * DEG, 0, 0)))
	as_hivis(plate(to, 0.06, 0.07, 0.48, 0.02, Vector3(-0.30, 0.77, -0.68)))


## RECLAIMER — a flat cap, with the detail the shape was missing: a swell at the
## back where the crown is fullest, a stiff peak sewn to the crown's front edge
## rather than standing off it, a seam across the crown, and the button.
static func reclaimer_flatcap(to: Node) -> void:
	var c: Array = _cock(14.0)
	var axis: Vector3 = c[0]
	var rot: Vector3 = c[1]
	var base := Vector3(-0.30, 0.59, -0.46)
	var crown := sphere(to, 0.27, base + axis * 0.04, Vector3(1.0, 0.40, 1.04))
	crown.rotation = rot
	as_wool(crown)
	# THE SWELL. A flat cap is fullest at the back and the fabric gathers there;
	# a single even dome is a skullcap.
	as_wool(sphere(to, 0.20, base + Vector3(0, -0.01, 0.16), Vector3(1.0, 0.46, 0.84)))
	# Peak, set shallow and close because on a flat cap it is sewn to the crown
	# rather than standing off it.
	as_wool(plate(to, 0.36, 0.22, 0.035, 0.07, Vector3(-0.30, 0.60, -0.73),
			Vector3(86 * DEG, 0, 0)))
	# The seam across the crown, and the button at the centre.
	as_wool(cyl(to, 0.018, 0.44, base + axis * 0.10 + Vector3(0, 0, 0.02),
			Vector3(0, 0, PI * 0.5), false, 6))
	as_wool(cyl(to, 0.045, 0.025, base + axis * 0.13 + Vector3(0, 0, 0.04),
			rot, false, 8))


## Every hat on every frame, one close shot each. Mode: `trials`.
static func vehicle_hat_trials() -> Array:
	return [
		["rover", "rover_beret", func(b): rover_beret(b)],
		["rover", "rover_shako", func(b): rover_shako(b)],
		["walker", "walker_tarleton", func(b): walker_tarleton(b)],
		["walker", "walker_peaked_cap", func(b): walker_peaked_cap(b)],
		["walker", "walker_bearskin", func(b): walker_bearskin(b)],
		["reclaimer", "reclaimer_hardhat", func(b): reclaimer_hardhat(b)],
		["reclaimer", "reclaimer_flatcap", func(b): reclaimer_flatcap(b)],
	]


## The vehicle veteran forms, as [frame key, label, builder]. The frame key is
## the one tools/mockup_shots.gd's FRAMES table uses.
static func vehicle_rank_list() -> Array:
	return [
		["rover", "ROVER BASE", func(_b): pass],
		["rover", "ROVER VETERAN", func(b): rover_veteran(b)],
		["walker", "WALKER BASE", func(_b): pass],
		["walker", "WALKER VETERAN", func(b): walker_veteran(b)],
		["reclaimer", "RECLAIMER BASE", func(_b): pass],
		["reclaimer", "RECLAIMER VETERAN", func(b): reclaimer_veteran(b)],
	]


## The officer forms: the veteran kit with that frame's hat on top. Paired
## veteran-against-officer rather than bare-against-officer, so the shot answers
## the only question worth asking — what does the HAT add to kit already signed
## off, not what does all of it add at once.
static func vehicle_hat_list() -> Array:
	return [
		["rover", "ROVER VETERAN", func(b): rover_veteran(b)],
		["rover", "ROVER OFFICER", func(b):
			rover_veteran(b)
			rover_beret(b)],
		["walker", "WALKER VETERAN", func(b): walker_veteran(b)],
		["walker", "WALKER OFFICER", func(b):
			walker_veteran(b)
			walker_tarleton(b)],
		["reclaimer", "RECLAIMER VETERAN", func(b): reclaimer_veteran(b)],
		["reclaimer", "RECLAIMER OFFICER", func(b):
			reclaimer_veteran(b)
			reclaimer_hardhat(b)],
	]


## One builder out of hat_list by name, so the cap on a Lieutenant is the SAME
## cap the hat sheet shows and not a second copy that drifts from it.
static func hat(wanted: String) -> Callable:
	for entry in hat_list():
		if String(entry[0]) == wanted:
			return entry[1]
	push_warning("mockup_parts: no hat called '%s'" % wanted)
	return func(_b): pass


## The three forms, in the order a robot earns them.
static func rank_list() -> Array:
	return [
		["FORM 00 REGULAR", func(_b): pass],
		# NO HEADGEAR AT VETERAN. The first pass put a strap over the crown to
		# make the pads a yoke; photographed, it read as a carry handle on top
		# of the robot and nothing else. Bare, padded, padded-and-capped is a
		# cleaner ladder and each rung is legible on its own.
		["FORM 01 VETERAN", func(b):
			shoulder_pads(b)],
		["FORM 02 LIEUTENANT", func(b):
			shoulder_pads(b)
			hat("PEAKED CAP").call(b)],
	]


# ─────────────────────────────────────────────
# AN ANATOMICAL DRONE SOLDIER
# ─────────────────────────────────────────────
# Built from nothing, here, in code. It does NOT touch soldier_chassis.tscn —
# that scene and everything using it are untouched, and this only ever appears
# in a mock-up render.
#
# WHY IT EXISTS. The shipped soldier is a featureless capsule: no head, no
# neck, no shoulder line, no waist. There is nowhere on it a hat or a pauldron
# belongs, so every fitting hung off it reads as a barnacle on an egg — which
# is exactly what the first two mock-up passes produced. The fix is not better
# hats, it is a body with LANDMARKS. This one has four, and each exists to
# carry something:
#
#   NECK        a gap between head and shoulders  -> hats sit here
#   SHOULDER YOKE  a bar overhanging the chest    -> pauldrons have a shelf
#   WAIST       a pinch between chest and hips    -> a belt reads as a belt
#   GLACIS      a flat angled chest face          -> plate has somewhere to go
#
# It keeps the shipped proportions — 2 m tall, about 1 m across, origin at the
# middle — so it drops into the same collision capsule.
#
# NO LEGS, DELIBERATELY. Soldier has no gait code (the Walker is the only frame
# that animates its legs), so legs here would skate across the ground. The
# lower body is an armoured column instead, which reads as a machine that
# glides. Legs become possible the day Soldier gets a gait.

const BODY_TINT := Color(0.42, 0.55, 0.62)
const KIT_TINT := Color(0.20, 0.23, 0.26)


static func _metal(tint: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	return m


## Fitted kit is NOT faction-painted. It is bought hardware bolted to a hull,
## and painting it the same blue as the hull is what made the armour vanish
## into the body in the last pass. Dark gunmetal reads as separate at a glance.
static func kit_material() -> StandardMaterial3D:
	return _metal(KIT_TINT, 0.55, 0.65)


static func body_material() -> StandardMaterial3D:
	return _metal(BODY_TINT, 0.70, 0.35)


## The drone, plus the node a weapon should hang on.
static func drone_body() -> Node3D:
	var b := Node3D.new()
	b.name = "DroneSoldier"

	# ── HIPS: a wide, chamfered base. Widest at the bottom so it reads planted.
	plate(b, 0.64, 0.50, 0.46, 0.13, Vector3(0, -0.72, 0.23), Vector3(PI * 0.5, 0, 0))
	plate(b, 0.52, 0.30, 0.40, 0.10, Vector3(0, -0.45, 0.20), Vector3(PI * 0.5, 0, 0))

	# ── WAIST: the pinch. Narrow on purpose — this is the belt line, and a belt
	# only reads as a belt if there is a narrowing for it to sit in.
	cyl(b, 0.23, 0.26, Vector3(0, -0.30, 0), Vector3.ZERO, false, 10)

	# ── CHEST: a tapered block with a flat angled front, so plate has a face to
	# sit on rather than a curve to float off.
	plate(b, 0.58, 0.62, 0.40, 0.12, Vector3(0, 0.06, 0.20), Vector3(PI * 0.5, 0, 0))
	wedge(b, 0.54, 0.34, 0.30, 0.12, Vector3(0, 0.12, -0.24), Vector3(14 * DEG, 0, 0))

	# ── SHOULDER BRACKETS, ONE PER SIDE, NOTHING CROSSING THE MIDDLE.
	#
	# This was a single 0.92 m bar spanning the whole chest and overhanging both
	# sides, put there as a shelf: the early flat-plate pauldrons stood on their
	# edge without it and read as wings. THAT WARNING STILL HOLDS — if a pad is
	# ever flat again it will need the shelf back.
	#
	# But the pad that survived is a cupped dome, and a dome 0.80 across sat on
	# a shoulder at x 0.36 overlaps the joint on its own; it never needed the
	# shelf. What the bar did instead was run visibly over and between the two
	# pads, which is a band across the chest nobody asked for. So it is two
	# short brackets now, each reaching from the chest side out to its own
	# shoulder and no further.
	for side in [1.0, -1.0]:
		plate(b, 0.24, 0.20, 0.34, 0.06, Vector3(0.35 * side, 0.40, 0.17), Vector3(PI * 0.5, 0, 0))
		cyl(b, 0.13, 0.16, Vector3(0.44 * side, 0.38, 0), Vector3(0, 0, PI * 0.5), false, 10)
		# Upper arm, hanging from the yoke.
		cyl(b, 0.09, 0.42, Vector3(0.44 * side, 0.14, -0.02), Vector3(0, 0, 7 * DEG * side), false, 8)
		cyl(b, 0.085, 0.30, Vector3(0.46 * side, -0.16, -0.10), Vector3(16 * DEG, 0, 0), false, 8)

	# ── NECK: the gap. Everything above this is the head, and a hat goes on it.
	cyl(b, 0.11, 0.16, Vector3(0, 0.56, 0), Vector3.ZERO, false, 8)

	# ── HEAD: a chamfered block with a visor slot and a sensor, so there is a
	# FRONT to the robot. The capsule had no facing at all beyond one small
	# blister, which is half of why nothing hung on it looked deliberate.
	plate(b, 0.40, 0.30, 0.34, 0.09, Vector3(0, 0.78, 0.17), Vector3(PI * 0.5, 0, 0))
	plate(b, 0.34, 0.11, 0.05, 0.03, Vector3(0, 0.80, -0.19))
	cyl(b, 0.045, 0.06, Vector3(0.10, 0.80, -0.21), Vector3(PI * 0.5, 0, 0), false, 8)
	# A small cowl over the visor, which gives the head a brow — the thing that
	# makes a box read as looking at you.
	wedge(b, 0.42, 0.12, 0.16, 0.06, Vector3(0, 0.90, -0.12), Vector3(28 * DEG, 0, 0))

	var mat := body_material()
	for child in b.get_children():
		if child is CSGShape3D:
			(child as CSGShape3D).material = mat
	return b


## Where a weapon hangs on the drone: the right hand, at the end of the arm.
static func drone_mount(b: Node3D) -> Node3D:
	var m := Node3D.new()
	m.name = "WeaponMount"
	m.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.36, 0.36, 0.36)),
		Vector3(0.50, -0.26, -0.20))
	b.add_child(m)
	return m


# ─────────────────────────────────────────────
# KIT FOR THE DRONE BODY
# ─────────────────────────────────────────────
# A SECOND set, because kit is sized to the body it hangs on and the capsule's
# set is useless here — dropped straight onto the drone, the capsule's peaked
# cap is a sphere bigger than the robot's whole head. That is the clearest
# possible argument for doing the body first: with real anatomy the fittings
# get SMALL and specific, because they have something to be small against.
#
# The landmarks these hook onto, from drone_body():
#   head top      y 0.93, about 0.40 across
#   neck          y 0.48 to 0.64
#   shoulder yoke y 0.40, out to x 0.46, z -0.17 to 0.17
#   glacis        the angled chest face, around y 0.10, z -0.28
#   waist         y -0.30, only 0.23 across
static func drone_hat_list() -> Array:
	return [
		["BARE", func(_b): pass],
		# Sits ON the head, overhangs it slightly, peak off the brow. About a
		# tenth the volume of the version built for the capsule.
		["PEAKED CAP", func(b):
			plate(b, 0.46, 0.38, 0.13, 0.07, Vector3(0, 1.00, 0.19), Vector3(PI * 0.5, 0, 0))
			plate(b, 0.48, 0.40, 0.05, 0.08, Vector3(0, 0.94, 0.20), Vector3(PI * 0.5, 0, 0))
			plate(b, 0.42, 0.20, 0.035, 0.07, Vector3(0, 0.96, -0.29), Vector3(74 * DEG, 0, 0))
			plate(b, 0.07, 0.07, 0.025, 0.025, Vector3(0, 1.04, -0.20), Vector3(12 * DEG, 0, 0))],
		["BERET", func(b):
			plate(b, 0.44, 0.36, 0.09, 0.14, Vector3(-0.04, 0.99, 0.18), Vector3(PI * 0.5, 0, 10 * DEG))
			cyl(b, 0.03, 0.07, Vector3(-0.16, 1.05, 0))],
		["HELMET", func(b):
			sphere(b, 0.26, Vector3(0, 0.82, -0.01), Vector3(1.0, 0.95, 1.1))
			plate(b, 0.30, 0.10, 0.04, 0.03, Vector3(0, 0.96, 0), Vector3(0, PI * 0.5, 0))],
	]


static func drone_kit_list() -> Array:
	return [
		["STOCK", func(_b): pass],
		# Plate on the glacis, pauldrons RESTING ON THE YOKE, skirt on the hips.
		# Every one of them has a surface to sit on now, which is the whole
		# reason the body came first.
		["ARMOR PLATING", func(b):
			plate(b, 0.52, 0.46, 0.07, 0.11, Vector3(0, 0.08, -0.31), Vector3(12 * DEG, 0, 0))
			studs(b, 3, Vector3(-0.16, 0.26, -0.36), Vector3(0.16, 0, 0))
			for side in [1.0, -1.0]:
				plate(b, 0.26, 0.34, 0.15, 0.08, Vector3(0.47 * side, 0.50, 0.07),
					Vector3(PI * 0.5, 0, -14 * DEG * side))
			plate(b, 0.56, 0.22, 0.30, 0.08, Vector3(0, -0.52, 0.15), Vector3(PI * 0.5, 0, 0))],
		# A short mast off the shoulder, not a lamp post: the dish clears the
		# head by a head's height and no more.
		["SENSOR RELAY", func(b):
			plate(b, 0.14, 0.13, 0.10, 0.04, Vector3(-0.34, 0.48, 0.05))
			cyl(b, 0.028, 0.46, Vector3(-0.34, 0.72, 0.05))
			cyl(b, 0.17, 0.06, Vector3(-0.34, 0.98, 0.05), Vector3(38 * DEG, 0, 0), true)
			cyl(b, 0.02, 0.12, Vector3(-0.34, 0.92, -0.03), Vector3(38 * DEG, 0, 0))],
		# A belt at the waist — which only works because there IS a waist.
		["UTILITY HARNESS", func(b):
			ring(b, 0.23, 0.31, Vector3(0, -0.30, 0), Vector3(PI * 0.5, 0, 0))
			plate(b, 0.09, 0.44, 0.04, 0.03, Vector3(0.13, 0.02, -0.28), Vector3(0, 0, 20 * DEG))
			plate(b, 0.17, 0.16, 0.11, 0.04, Vector3(0.30, -0.30, -0.10))
			plate(b, 0.15, 0.14, 0.10, 0.04, Vector3(0.28, -0.30, 0.14))],
		["FRAG", func(b):
			ring(b, 0.23, 0.31, Vector3(0, -0.30, 0), Vector3(PI * 0.5, 0, 0))
			for i in 2:
				var at := Vector3(0.20 - i * 0.17, -0.34, -0.24 - i * 0.05)
				cyl(b, 0.055, 0.17, at, Vector3.ZERO, false, 8)
				ring(b, 0.055, 0.075, at + Vector3(0, 0.04, 0), Vector3(PI * 0.5, 0, 0))],
	]


# ─────────────────────────────────────────────
# APPLIQUÉ TILES — the shape language for kit on a CAPSULE body.
# ─────────────────────────────────────────────
# Everything above this line was built as boxes, and boxes are wrong here: the
# body is a smooth curved capsule, so a slab stuck on it reads as a crate
# balanced against an egg. What fits a curve is a low tapered TILE — wide where
# it meets the hull, narrowing to a smaller flat face, like an emerald cut
# upside down. Several of those laid round the curve read as armour; one big
# box never will.
#
# Two rules, both learned the hard way:
#   FLAT. Thickness is the smallest dimension, always. If a fitting is as deep
#   as it is wide it is a box again whatever its profile.
#   TANGENT. Each tile is seated on the hull and turned to face straight out of
#   it, so the run of tiles follows the body instead of cutting across it.

## A low tapered plate: wide base, smaller flat face, sloped sides. Built by
## truncating a cone rather than stacking two plates, so the sides really are
## sloped and catch the light as a bevel should.
##
## `sides` picks the outline. 4 gives a RECTANGULAR plate, which is what armour
## wants — an eight-sided one reads as a stud the moment it is small. The cone
## is spun by half a segment so a flat, not a corner, faces front.
static func frustum(to: Node, w: float, d: float, thick: float, face: float,
		at: Vector3, basis: Basis = Basis.IDENTITY, sides: int = 4) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	var f: float = clampf(face, 0.05, 0.95)
	# Radius falls to zero over `tall`; cutting at `thick` leaves a face of
	# `face` times the base.
	var tall: float = thick / (1.0 - f)
	var cone := CSGCylinder3D.new()
	cone.radius = 0.5
	cone.height = tall
	cone.cone = true
	cone.sides = sides
	cone.position = Vector3(0, tall * 0.5, 0)
	cone.rotation.y = PI / float(sides)
	# A 4-sided cone is a diamond across its own axes, so the plate's width and
	# depth land on the diagonal unless the scale is widened to match.
	var diag: float = 1.0 / cos(PI / float(sides)) if sides == 4 else 1.0
	c.add_child(cone)
	var lop := CSGBox3D.new()
	lop.operation = CSGShape3D.OPERATION_SUBTRACTION
	lop.size = Vector3(4.0, tall, 4.0)
	lop.position = Vector3(0, thick + tall * 0.5, 0)
	c.add_child(lop)
	c.scale = Vector3(w * diag, 1.0, d * diag)
	c.position = at
	c.basis = basis * c.basis
	to.add_child(c)
	return c


## Where a point on the capsule's surface is, and which way is OUT of it there.
## The body is a cylinder of radius 0.5 between y -0.5 and 0.5, capped by
## hemispheres — so above the shoulder the surface pulls in, and a tile placed
## by eye at that height floats.
static func hull_seat(yaw_deg: float, y: float, lift: float = 0.0) -> Array:
	var yaw: float = yaw_deg * DEG
	var r := 0.5
	var cy := y
	if absf(y) > 0.5:
		var dy: float = absf(y) - 0.5
		r = sqrt(maxf(0.25 - dy * dy, 0.0001))
		cy = y
	var flat := Vector3(sin(yaw), 0.0, -cos(yaw))
	var normal := flat
	if absf(y) > 0.5:
		# On the dome the outward direction tips upward as well.
		var centre := Vector3(0, 0.5 * signf(y), 0)
		normal = (Vector3(flat.x * r, cy, flat.z * r) - centre).normalized()
	var pos := Vector3(flat.x * r, cy, flat.z * r) + normal * lift
	return [pos, _seat_basis(normal)]


static func _seat_basis(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var side := Vector3.UP.cross(up)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	return Basis(side, up, up.cross(side).normalized())


## One tile, seated on the hull and facing out of it.
static func tile(to: Node, yaw_deg: float, y: float, w: float, d: float,
		thick: float, face: float = 0.62) -> CSGCombiner3D:
	var seat := hull_seat(yaw_deg, y, -thick * 0.25)
	return frustum(to, w, d, thick, face, seat[0], seat[1])


# ─────────────────────────────────────────────
# MATERIALS — kit is NOT faction-painted.
# ─────────────────────────────────────────────
## CLOTH, NOT METAL. Anything soft — a cap crown, a beret, a cloth epaulette
## board — takes this instead of armor_material, and tags itself with the
## "fabric" meta so the shot rig's repaint leaves it alone.
##
## It is the pack's own camo_fabric.tres, not a new material: tools/make_textures.gd
## built that one deliberately under 0.22 luminance, because the faction shader
## starts painting at 0.24 and a disruptive pattern that turns flat faction
## orange is not camo any more. Rolling a fresh material here would lose that.
## HOW MANY TIMES THE CAMO TILE REPEATS ACROSS A PIECE. The pack's tile is
## drawn with four to six blobs across it, sized for a sleeve seen at 1152x648
## — on something as small as a cap crown, one repeat puts a single blob over
## the whole thing and it reads as a stain rather than as a pattern. Five
## repeats gets the blobs down to a believable size on a 0.5 m crown.
const FABRIC_TILING := 5.0

static var _fabric: Material = null

static func fabric_material() -> Material:
	if _fabric != null:
		return _fabric
	var src := load("res://textures/PSX_Textures/camo_fabric.tres") as BaseMaterial3D
	if src == null:
		push_warning("mockup_parts: camo_fabric.tres missing, cloth will render untextured")
		_fabric = _metal(Color(0.26, 0.26, 0.22), 0.95, 0.0)
		return _fabric
	# DUPLICATED, NEVER EDITED IN PLACE. camo_fabric.tres is a shared pack
	# resource; the tiling wanted here is a property of these small mock-up
	# pieces and not of the texture, so it goes on a copy.
	var m := src.duplicate() as BaseMaterial3D
	m.uv1_scale = Vector3(FABRIC_TILING, FABRIC_TILING, 1.0)
	_fabric = m
	return _fabric


## Marks a piece as cloth. Returns it, so it can wrap a shape call inline.
static func as_fabric(n: Node) -> Node:
	n.set_meta("fabric", true)
	return n


## PLATE STEEL, for the pauldrons. TERRAIN built this to the brief in
## docs/briefs/PLATE_TEXTURE.md — horizontal brushed grain, a highlight band
## across the upper third, rolled edges and rivets held out of the faction paint
## by the mask. It is the reason the pads could lose their modelled rim: the roll
## is painted in now, so a torus round the dome was a second competing edge.
##
## THREE VARIANTS SHIPPED and only the base one is wired here — pauldron_plate,
## pauldron_plate_worn (after a campaign) and pauldron_plate_dress (braided).
## Swapping between them by rank or by missions survived is a decision to make,
## not a default to assume.
##
## TILING IS NOT ONE NUMBER, because the dome and the lames are not one shape.
##
## A CSGSphere is unwrapped spherically, 0..1 pole to pole, so a vertical repeat
## stacks the texture's highlight band up the dome — seven repeats turned it into
## liquorice stripes in the first render. One repeat vertically puts that band
## once across the upper third, which is where the brief wanted it; the repeats
## go round the circumference instead, where they read as grain.
##
## The lames are small frustums with metric-ish UVs and their own texture, so
## they are tiled separately below.
const PLATE_TILING := Vector3(3.0, 1.0, 1.0)
const LAME_TILING := Vector3(1.0, 1.0, 1.0)

static var _plate: Material = null
static var _lame: Material = null

static func plate_material() -> Material:
	if _plate != null:
		return _plate
	_plate = _plate_from("pauldron_plate", PLATE_TILING)
	return _plate


## The lames get their own texture — TERRAIN shipped pauldron_lame alongside the
## plate, cut for a band 0.145 m tall rather than for a dome.
static func lame_material() -> Material:
	if _lame != null:
		return _lame
	_lame = _plate_from("pauldron_lame", LAME_TILING)
	return _lame


static func _plate_from(name: String, tiling: Vector3) -> Material:
	var src := load("res://textures/PSX_Textures/%s.tres" % name) as BaseMaterial3D
	if src == null:
		push_warning("mockup_parts: %s.tres missing, pads fall back to flat armour" % name)
		return armor_material()
	# DUPLICATED, NEVER EDITED IN PLACE — same reason as the cloth above. The
	# .tres is a shared pack resource and the tiling is a property of these
	# small pieces, not of the texture.
	var m := src.duplicate() as BaseMaterial3D
	m.uv1_scale = tiling
	m.roughness = 0.45
	m.metallic = 0.70
	return m


## Marks a piece as plate steel. Returns it, so it can wrap a shape call inline.
static func as_plate(n: Node) -> Node:
	n.set_meta("plate", true)
	return n


## Marks a piece as a lame band.
static func as_lame(n: Node) -> Node:
	n.set_meta("lame", true)
	return n


static func armor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.17, 0.19)
	m.roughness = 0.42
	m.metallic = 0.75
	return m


## WOOL, for headgear — the beret crown, the Tarleton's turban and crest.
##
## NOT CAMO. Camo is a disruptive pattern whose whole job is to break up a shape
## so it cannot be read, which is the exact opposite of what a rank mark is for;
## on the beret it also sits at mean 0.130, so it photographed as a dark lump.
## Dress wool is plain, dense and slightly warmer than the steel beside it.
##
## The texture is briefed in docs/briefs/BERET_WOOL.md and does not exist yet.
## This resolves it by name and falls back loudly, so the moment it lands the
## kit picks it up with no further change here.
const WOOL_TILING := Vector3(2.0, 2.0, 1.0)

static var _wool: Material = null

static func wool_material() -> Material:
	if _wool != null:
		return _wool
	var src := load("res://textures/PSX_Textures/beret_wool.tres") as BaseMaterial3D
	if src == null:
		push_warning("mockup_parts: beret_wool.tres not built yet (see " \
				+ "docs/briefs/BERET_WOOL.md) — headgear renders in flat wool")
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.17, 0.19, 0.17)
		f.roughness = 0.96
		f.metallic = 0.0
		_wool = f
		return _wool
	var m := src.duplicate() as BaseMaterial3D
	m.uv1_scale = WOOL_TILING
	_wool = m
	return _wool


## Marks a piece as dress wool. Returns it, so it can wrap a shape call inline.
static func as_wool(n: Node) -> Node:
	n.set_meta("wool", true)
	return n


## FUR, for the bearskin and nothing else so far. A separate entry from wool
## because the two are not the same surface at any distance: wool is flat and
## dense, fur is deep and broken, and the bearskin is the single largest piece
## of cloth in the game at 1.6 m of column on a three-metre frame. Briefed in
## docs/briefs/BEARSKIN_FUR.md and NOT BUILT YET — this resolves it by name and
## falls back loudly, so it picks up the moment the texture lands.
const FUR_TILING := Vector3(3.0, 3.0, 1.0)

static var _fur: Material = null

static func fur_material() -> Material:
	if _fur != null:
		return _fur
	var src := load("res://textures/PSX_Textures/bearskin_fur.tres") as BaseMaterial3D
	if src == null:
		push_warning("mockup_parts: bearskin_fur.tres not built yet (see " \
				+ "docs/briefs/BEARSKIN_FUR.md) — the bearskin renders in flat fur")
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.11, 0.11, 0.12)
		f.roughness = 1.0
		f.metallic = 0.0
		_fur = f
		return _fur
	var m := src.duplicate() as BaseMaterial3D
	m.uv1_scale = FUR_TILING
	_fur = m
	return _fur


## Marks a piece as fur. Returns it, so it can wrap a shape call inline.
static func as_fur(n: Node) -> Node:
	n.set_meta("fur", true)
	return n


## HI-VIS, for the Reclaimer's hard hat and nothing else. Deliberately the one
## bright thing in a kit that is otherwise steel and camo — a works vehicle is
## supposed to be seen, which is the opposite of everything else here. Barely
## metallic, because a hard hat is plastic.
static func hivis_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.30, 0.03)
	m.roughness = 0.62
	m.metallic = 0.05
	return m


## Marks a piece as hi-vis. Returns it, so it can wrap a shape call inline.
static func as_hivis(n: Node) -> Node:
	n.set_meta("hivis", true)
	return n


static func gear_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.26, 0.17)
	m.roughness = 0.70
	m.metallic = 0.25
	return m


# ─────────────────────────────────────────────
# KIT FOR THE CAPSULE, IN THE TILE LANGUAGE
# ─────────────────────────────────────────────
static func capsule_kit_list() -> Array:
	return [
		["STOCK", func(_b): pass],

		# A dish on a slim mast, standing on its own mounting pad. The pad is
		# what makes a mast look bolted on rather than grown out of the hull.
		["SENSOR RELAY", func(b):
			var seat := _pad(b, 46.0, 0.50, 0.28, 0.26)
			var up: Vector3 = (seat[1] as Basis).y
			var at: Vector3 = seat[0]
			cyl(b, 0.026, 0.50, at + up * 0.06 + Vector3(0, 0.22, 0))
			cyl(b, 0.19, 0.045, at + up * 0.06 + Vector3(0, 0.50, 0), Vector3(34 * DEG, 0, 0), true)
			cyl(b, 0.018, 0.13, at + up * 0.06 + Vector3(0, 0.44, -0.07), Vector3(34 * DEG, 0, 0))],

		# A belt of flat segments round the waist with two hard cases on it. No
		# shoulder strap: the capsule has no shoulder to loop one over.
		["UTILITY HARNESS", func(b):
			for a in [-70.0, -23.0, 23.0, 70.0, 117.0, -117.0]:
				tile(b, a, -0.10, 0.36, 0.17, 0.030, 0.88)
			_case(b, 54.0, -0.30, 0.26, 0.22, 0.12)
			_case(b, -54.0, -0.30, 0.22, 0.20, 0.10)],

		# Two grenades lying ALONG the hull in a cradle, not standing off it.
		["FRAG", func(b):
			for a in [26.0, 62.0]:
				var seat := _pad(b, a, -0.26, 0.30, 0.24)
				var up: Vector3 = (seat[1] as Basis).y
				var c := cyl(b, 0.072, 0.25, (seat[0] as Vector3) + up * 0.085, Vector3.ZERO, false, 8)
				c.basis = (seat[1] as Basis) * Basis(Vector3.RIGHT, PI * 0.5)
				var r := ring(b, 0.072, 0.098, (seat[0] as Vector3) + up * 0.085, Vector3.ZERO)
				r.basis = (seat[1] as Basis) * Basis(Vector3.RIGHT, PI * 0.5)],

		# One fatter canister with two bands, so it reads as the ODD one on the
		# rack rather than a third frag.
		["EMP", func(b):
			var seat := _pad(b, 44.0, -0.26, 0.34, 0.28)
			var up: Vector3 = (seat[1] as Basis).y
			var at: Vector3 = (seat[0] as Vector3) + up * 0.10
			var c := cyl(b, 0.10, 0.30, at, Vector3.ZERO, false, 8)
			c.basis = (seat[1] as Basis) * Basis(Vector3.RIGHT, PI * 0.5)
			for off in [-0.08, 0.08]:
				var r := ring(b, 0.10, 0.135, at + (seat[1] as Basis).x * off, Vector3.ZERO)
				r.basis = (seat[1] as Basis) * Basis(Vector3.RIGHT, PI * 0.5)],

		# A ribbed pressure vessel in a cradle, slung high where the outline is
		# clear. The ribs are what say canister rather than tube.
		["HATCHLING", func(b):
			var seat := _pad(b, 72.0, 0.10, 0.30, 0.60)
			var up: Vector3 = (seat[1] as Basis).y
			var at: Vector3 = (seat[0] as Vector3) + up * 0.15
			cyl(b, 0.14, 0.54, at, Vector3.ZERO, false, 10)
			for dy in [-0.16, 0.0, 0.16]:
				ring(b, 0.14, 0.175, at + Vector3(0, dy, 0), Vector3(PI * 0.5, 0, 0))
			cyl(b, 0.05, 0.10, at + Vector3(0, 0.31, 0))],

		# Deliberately quiet: one flat cell on a pad, with a slot for the charge
		# light. You should have to look for it.
		["NANITE REBOOT", func(b):
			var seat := _pad(b, -50.0, 0.22, 0.28, 0.34)
			var up: Vector3 = (seat[1] as Basis).y
			frustum(b, 0.15, 0.24, 0.05, 0.74, (seat[0] as Vector3) + up * 0.02, seat[1])],

		# A tool head, not a bag: a stubby arm with a two-jaw clamp and a spool
		# of wire behind it.
		["REPAIR KIT", func(b):
			var seat := _pad(b, 84.0, -0.14, 0.26, 0.30)
			var bs: Basis = seat[1]
			var at: Vector3 = seat[0]
			var arm := cyl(b, 0.055, 0.34, at + bs.y * 0.17, Vector3.ZERO, false, 8)
			arm.basis = bs * Basis(Vector3.RIGHT, PI * 0.5)
			for s in [1.0, -1.0]:
				var jaw := frustum(b, 0.07, 0.19, 0.05, 0.70,
					at + bs.y * 0.30 + bs.z * (0.06 * s), bs)
				jaw.rotation.z += deg_to_rad(22.0 * s)
			var spool := cyl(b, 0.10, 0.09, at + bs.y * 0.05, Vector3.ZERO, false, 10)
			spool.basis = bs * Basis(Vector3.RIGHT, PI * 0.5)],

		# A drum of belted rounds climbing toward the gun. The rounds are the
		# point: this is the module that decides you would rather spend them.
		["CYCLIC FEED", func(b):
			var seat := _pad(b, 62.0, -0.04, 0.30, 0.30)
			var bs: Basis = seat[1]
			var at: Vector3 = seat[0]
			var drum := cyl(b, 0.14, 0.13, at + bs.y * 0.08, Vector3.ZERO, false, 10)
			drum.basis = bs * Basis(Vector3.RIGHT, PI * 0.5)
			var rim := ring(b, 0.08, 0.14, at + bs.y * 0.08, Vector3.ZERO)
			rim.basis = bs * Basis(Vector3.RIGHT, PI * 0.5)
			for i in 6:
				box(b, Vector3(0.045, 0.085, 0.045),
					at + bs.y * (0.10 + i * 0.012) + bs.x * (0.10 + i * 0.055)
						+ Vector3(0, 0.05 + i * 0.035, 0))],

		# No joints on a capsule to expose, so this is COOLING instead: a stack
		# of heat-sink fins down the flank. Overclocking something is a thermal
		# problem before it is anything else, and fins read as that instantly.
		["OVERCLOCK SERVOS", func(b):
			for a in [96.0, -96.0]:
				var seat := _pad(b, a, 0.04, 0.24, 0.62)
				var bs: Basis = seat[1]
				for i in 6:
					frustum(b, 0.20, 0.045, 0.085, 0.55,
						(seat[0] as Vector3) + bs.y * 0.03 + Vector3(0, -0.22 + i * 0.088, 0), bs)],

		# A blade antenna — a flat fin, the way a hardened set really is, rather
		# than a whip that would snap off the first time it was shot at.
		["HARDENED UPLINK", func(b):
			var seat := _pad(b, -34.0, 0.56, 0.24, 0.20)
			var bs: Basis = seat[1]
			var blade := frustum(b, 0.055, 0.44, 0.07, 0.30,
				(seat[0] as Vector3) + bs.y * 0.04 + Vector3(0, 0.22, 0), bs)
			blade.rotation.z += deg_to_rad(6.0)],
	]


## A low mounting pad on the hull, and the seat it sits on, so a fitting has
## something to stand on instead of sprouting out of the paintwork.
static func _pad(to: Node, yaw_deg: float, y: float, w: float, h: float) -> Array:
	var seat := hull_seat(yaw_deg, y, -0.008)
	frustum(to, w, h, 0.032, 0.88, seat[0], seat[1])
	return seat


## A hard case sitting on the belt line.
static func _case(to: Node, yaw_deg: float, y: float, w: float, h: float, thick: float) -> void:
	var seat := hull_seat(yaw_deg, y, 0.0)
	frustum(to, w, h, thick, 0.80, seat[0], seat[1])

# ─────────────────────────────────────────────
# SHELL PLATES — armour that actually wraps.
# ─────────────────────────────────────────────
# A tile seated tangent to the hull only touches it along one line: the middle
# sits on the surface and the edges lift off it, which is why the flat plates
# read as stuck-on rather than fitted. A plate that wraps has to BE a piece of
# a cylinder.
#
# So it is cut out of one. A shell — a fat cylinder with a thinner one
# subtracted from it — intersected with a chamfered rectangle extruded through
# the front. What comes out is a plate with the hull's exact curvature across
# its whole width and the tapered emerald-cut outline, which the flat version
# had and is worth keeping.
#
# The dome at the top of the capsule is a sphere, not a cylinder, so plates up
# there are cut from a spherical shell by the same method. Cutting a dome plate
# out of a cylinder leaves it floating at the top edge.

## One wrapped plate. `w` and `h` are the plate's size across and up; `thick`
## is how far it stands off the hull; `bevel` is the corner cut.
static func shell_plate(to: Node, yaw_deg: float, y: float, w: float, h: float,
		thick: float = 0.045, bevel: float = 0.10, dome: bool = false) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	var r_in := 0.495
	var r_out := r_in + thick
	if dome:
		var outer := CSGSphere3D.new()
		outer.radius = r_out
		outer.radial_segments = 28
		outer.rings = 14
		c.add_child(outer)
		var inner := CSGSphere3D.new()
		inner.radius = r_in
		inner.radial_segments = 28
		inner.rings = 14
		inner.operation = CSGShape3D.OPERATION_SUBTRACTION
		c.add_child(inner)
		c.position = Vector3(0, 0.5, 0)
	else:
		var outer := CSGCylinder3D.new()
		outer.radius = r_out
		outer.height = 2.4
		outer.sides = 40
		c.add_child(outer)
		var inner := CSGCylinder3D.new()
		inner.radius = r_in
		inner.height = 2.5
		inner.sides = 40
		inner.operation = CSGShape3D.OPERATION_SUBTRACTION
		c.add_child(inner)
		c.position = Vector3.ZERO

	# The cookie cutter: the plate's outline, pushed through the shell from the
	# front. Everything outside it is discarded.
	var cut := CSGPolygon3D.new()
	var x := w * 0.5
	var yy := h * 0.5
	var bv: float = minf(bevel, minf(x, yy) * 0.8)
	cut.polygon = PackedVector2Array([
		Vector2(-x + bv, -yy), Vector2(x - bv, -yy), Vector2(x, -yy + bv), Vector2(x, yy - bv),
		Vector2(x - bv, yy), Vector2(-x + bv, yy), Vector2(-x, yy - bv), Vector2(-x, -yy + bv)])
	cut.depth = 1.2
	cut.operation = CSGShape3D.OPERATION_INTERSECTION
	cut.position = Vector3(0, (y - 0.5) if dome else y, -1.0)
	c.add_child(cut)
	c.rotation.y = yaw_deg * DEG
	to.add_child(c)
	return c


# ─────────────────────────────────────────────
# RUST — procedural, so it needs no texture asset.
# ─────────────────────────────────────────────
# Flat matte colour is what made the plates read as plastic. Armour on a robot
# that has been in the field is pitted and oxidised, and the hull it is bolted
# to is already weathered, so an untextured plate stands out as the one clean
# thing on a dirty machine.
static func _rust_texture(seed_value: int, frequency: float, ramp: Gradient) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([stops[0], stops[1]])
	for i in range(2, stops.size(), 2):
		g.add_point(float(stops[i]), stops[i + 1])
	return g


## Rusted steel: pitted dark metal with oxide breaking through it. RUST IS THE
## MINORITY, not the base coat — a ramp that spends most of its range on orange
## comes out looking like varnished wood, and at a low noise frequency the
## streaks run long enough to look like grain. Fine mottling, mostly steel,
## oxide in the pits.
static func rust_material(tint: Color = Color(0.40, 0.20, 0.11)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _rust_texture(7, 0.055, _ramp([
		Color(0.085, 0.090, 0.095), Color(0.26, 0.24, 0.22),
		0.52, Color(0.13, 0.13, 0.13),
		0.72, tint,
		0.86, Color(0.30, 0.17, 0.11)]))
	m.roughness_texture = _rust_texture(11, 0.075, _ramp([
		Color(0.45, 0.45, 0.45), Color(1.0, 1.0, 1.0)]))
	m.roughness = 1.0
	m.metallic = 0.60
	m.metallic_specular = 0.30
	m.uv1_scale = Vector3(1.1, 1.1, 1.1)
	m.uv1_triplanar = true
	return m


## A plate that FOLLOWS THE HULL, built from a few narrow tangent facets laid
## side by side rather than one flat slab.
##
## The honest version of this is a segment cut from a cylindrical shell, and
## that is what was tried first: a fat cylinder, a thinner one subtracted, the
## outline intersected through the front. Godot's CSG returned an empty mesh
## for it — the combiner's AABB came back zero with every child's own AABB
## correct — so rather than fight the boolean, the curve is approximated.
##
## Faceting suits this game anyway: the seams between facets read as panel
## lines on a pressed plate, and everything else here is low-poly already.
static func wrapped_plate(to: Node, yaw_deg: float, y: float, w: float, h: float,
		thick: float = 0.06, facets: int = 3) -> void:
	var r := 0.5
	var arc: float = w / r                      # radians the whole plate covers
	var step: float = arc / float(facets)
	var seg: float = r * step * 1.06            # facet width, overlapped slightly
	for i in facets:
		var offset: float = (float(i) - (float(facets) - 1.0) * 0.5) * step
		var a: float = yaw_deg * DEG + offset
		var seat := hull_seat(rad_to_deg(a), y, -thick * 0.2)
		# The end facets are the ones that would lift off the hull, so they get
		# the bevel; the middle of a plate has no edge to soften.

		frustum(to, seg, h, thick, 0.88 if facets > 1 else 0.86, seat[0], seat[1])
