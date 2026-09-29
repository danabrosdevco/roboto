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
		["BERET", func(b):
			cyl(b, 0.38, 0.12, Vector3(-0.06, 1.02, 0.02), Vector3(14 * DEG, 0, 0))
			sphere(b, 0.07, Vector3(-0.06, 1.11, 0.02))],
		# THE HEAD IS THE TOP OF A CAPSULE, not a sphere on a neck, so a cap has
		# to follow that dome: the hemisphere is centred at y 0.5 with radius
		# 0.5, which means a flat-bottomed cylinder sat on top leaves a gap in
		# the middle and clips at the rim. A slightly larger dome, a band round
		# it where the body is 0.45 across, and a peak off the front.
		["PEAKED CAP", func(b):
			sphere(b, 0.53, Vector3(0, 0.52, 0), Vector3(1.0, 0.94, 1.0))
			ring(b, 0.47, 0.56, Vector3(0, 0.70, 0), Vector3(PI * 0.5, 0, 0))
			plate(b, 0.62, 0.34, 0.045, 0.13, Vector3(0, 0.70, -0.54), Vector3(72 * DEG, 0, 0))
			plate(b, 0.10, 0.10, 0.03, 0.035, Vector3(0, 0.88, -0.45), Vector3(20 * DEG, 0, 0))],
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

	# ── SHOULDER YOKE: a bar across the top of the chest, overhanging both
	# sides. This is the shelf. Without it a pauldron has nothing to rest on and
	# ends up standing on its edge looking like a wing.
	plate(b, 0.92, 0.20, 0.34, 0.07, Vector3(0, 0.40, 0.17), Vector3(PI * 0.5, 0, 0))
	for side in [1.0, -1.0]:
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
static func armor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.17, 0.19)
	m.roughness = 0.42
	m.metallic = 0.75
	return m


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
