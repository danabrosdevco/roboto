extends RefCounted
class_name ConceptsB

# ─────────────────────────────────────────────
# CONCEPT BUILDERS — BATCH B
#
# Three frames, four options each, built from the Walker's own vocabulary in
# concept_kit.gd so that a new chassis looks ISSUED rather than imported. Every
# builder is a plain static function taking the root the renderer hands it; it
# adds CSG children and returns. Nothing here renders, measures or touches the
# tree — that is mockup_frames.gd's job.
#
#   WARDEN   supply 2, hull 160. The first EMITTER: a mast projecting a jamming
#            field. The only non-lethal frame in the game, so nothing on any of
#            the four may resemble a barrel.
#   DRAYMAN  supply 2, hull 170. Reclaimer lineage, resupplies ammunition from
#            an articulated arm. Must read as CARRYING A LOAD and as having
#            REACH, and must not read as a gun truck.
#   VESSEL   supply 3, hull 260. A carrier for two Hatchlings — a friendly,
#            mobile Nest. Must read as CONTAINING something, and is deliberately
#            the biggest thing in the batch.
#
# THE FOUR OPTIONS PER FRAME ARE FOUR ANSWERS, not four proportions. Where two
# options would have differed only in size, one of them was given a different
# locomotion and a different proposition instead — each Vessel walks, rolls,
# tracks or stands on pillars, and each one opens in a different direction.
# ─────────────────────────────────────────────

const K := preload("res://tools/concept_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")


# ─────────────────────────────────────────────
# SHARED PIECES
#
# Three private helpers, underscore-prefixed the way mockup_parts.gd's own
# internals are. They exist because each is needed by five to nine builders and
# a copied silhouette that drifts between options is worse than no option: the
# sheet then compares two accidents instead of two proposals.
# ─────────────────────────────────────────────


## K.head WITHOUT THE GUN. The kit head carries a mantlet and a 1.5 m barrel,
## which is exactly right for a Walker relative and exactly wrong for the frame
## whose whole proposition is that it cannot hurt anyone — and nearly as wrong
## for a supply vehicle that must not read as a gun truck.
##
## Everything that makes the Walker's head recognisable is kept: the turret
## ring, the cheek and brow cuts, the single eye offset LEFT, the whip antenna.
## In place of the mantlet there is a sensor cowl, and it sits on the RIGHT
## (+x) because the eye is on the left and nothing may cross an eye.
static func _blind_head(to: Node, at: Vector3, scale_f: float = 1.0) -> Node3D:
	_Parts.cyl(to, K.W_RING_R * scale_f, 0.12 * scale_f, at)
	var head := K.node_at(to, at + Vector3(0, 0.19 * scale_f, 0), Vector3.ZERO)
	head.name = "BlindHead"
	var body := _Parts.box(head, K.W_TURRET * scale_f, Vector3.ZERO)
	body.name = "HeadBody"
	# Cheek and brow, cut exactly as the Walker's are. The cutters are 1.3x the
	# block they slice because anything tighter leaves a sliver of uncut face.
	var cheek := _Parts.box(body, Vector3(K.W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, -0.44, -0.86) * scale_f, Vector3(-35.0 * K.DEG, 0, 0))
	cheek.operation = CSGShape3D.OPERATION_SUBTRACTION
	var brow := _Parts.box(body, Vector3(K.W_TURRET.x * 1.3, 0.7, 0.7) * scale_f,
			Vector3(0, 0.5, -0.78) * scale_f, Vector3(25.0 * K.DEG, 0, 0))
	brow.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.sphere(head, K.W_EYE_R * scale_f,
			Vector3(-0.34, 0.14, -0.66) * scale_f, Vector3(1, 0.82, 1))
	_Parts.box(head, Vector3(0.03, 0.85, 0.03) * scale_f,
			Vector3(-0.5, 0.68, 0.48) * scale_f)
	# The cowl, offset right and standing proud of the face so it breaks the
	# outline rather than sinking into the brow cut.
	_Parts.plate(head, 0.46 * scale_f, 0.3 * scale_f, 0.2 * scale_f, 0.07 * scale_f,
			Vector3(0.2, 0.0, -0.78) * scale_f)
	return head


## A Hatchling, as cargo. Small on purpose — about 0.9 m across against a 2.7 m
## carrier hull — because the whole proposition is that the Vessel adds BODIES,
## and a drone drawn big enough to be comfortable reads as a second vehicle
## bolted on rather than as a thing that came out of the bay.
##
## Two rotors rather than four: at this size four discs overlap into one blob,
## and the kit's rotor() already draws a hub and bars that say "this flies" in
## one shape.
static func _hatchling(to: Node, at: Vector3, yaw: float = 0.0) -> Node3D:
	var d := K.node_at(to, at, Vector3(0, yaw * K.DEG, 0))
	d.name = "Hatchling"
	# Body: chamfered, extruded DOWNWARD. plate() lays its polygon in local XY
	# and extrudes along local +Z, and a PI/2 rotation about X sends that +Z to
	# world -Y — so the quoted width is X, the height is Z, and the depth is the
	# drop. Placed at the top of its own thickness so it hangs under the rotors.
	_Parts.plate(d, 0.42, 0.5, 0.2, 0.08, Vector3(0, 0.1, 0), Vector3(PI * 0.5, 0, 0))
	for s: float in [-1.0, 1.0]:
		_Parts.box(d, Vector3(0.2, 0.07, 0.07), Vector3(s * 0.14, 0.14, 0))
		K.rotor(d, Vector3(s * 0.24, 0.16, 0), 0.19, 2)
		# Skids, which are what makes it read as a thing that LANDS.
		_Parts.box(d, Vector3(0.05, 0.14, 0.42), Vector3(s * 0.15, -0.17, 0))
	_Parts.sphere(d, 0.07, Vector3(0, 0.0, -0.26))
	return d


## A block of ammunition crates. The lid band is the whole trick: a bare
## chamfered box repeated twelve times reads as masonry, and one thin lip per
## crate is what separates the stack into countable objects.
static func _crates(to: Node, at: Vector3, cols: int, rows: int, deep: int) -> void:
	for ix in cols:
		for iy in rows:
			for iz in deep:
				var p := at + Vector3(
						(float(ix) - float(cols - 1) * 0.5) * 0.6,
						float(iy) * 0.42,
						(float(iz) - float(deep - 1) * 0.5) * 0.56)
				_Parts.plate(to, 0.54, 0.5, 0.38, 0.07,
						p + Vector3(0, 0.38, 0), Vector3(PI * 0.5, 0, 0))
				_Parts.plate(to, 0.58, 0.54, 0.05, 0.05,
						p + Vector3(0, 0.42, 0), Vector3(PI * 0.5, 0, 0))


# ─────────────────────────────────────────────
# WARDEN — FOUR OPTIONS
#
# The silhouette has to say "this PROJECTS something", and it has to say it
# without a single straight tube pointing at the horizon. Four different answers
# to where the field goes: over everyone from above, through a hoop in one
# direction, in a bubble it has to walk into, or out of an array it deploys.
# ─────────────────────────────────────────────


## A. MAST — the field comes from ABOVE. A three-stage telescoping mast with a
## crowned head and six ribs canting down and out, so the squad fights under an
## umbrella it carries. The tallest frame in the game by a clear margin, which
## is itself the gameplay statement: everything in the radius is covered.
##
## RISK: a mast on a chassis is one bad render away from a radio van. The base
## coil and the ribbed crown are what pay for it — a comms mast has neither, and
## an emitter needs both. A second risk is honest: it is top-heavy and fragile
## and should look it.
static func warden_a(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.5, 1.0, 1.7), Vector3(0, 0.45, 0))
	# Head low and forward, so the mast — not the head — owns the top.
	_blind_head(root_node, Vector3(0, 0.95, -0.2), 0.55)
	for sx: float in [-1.0, 1.0]:
		K.leg(root_node, Vector3(sx * 0.68, -0.1, 0), 0.78, 0.9, -sx * 4.0, 0.0, true)
	# Three stages, each starting where the last ends. Quoting a single 3.3 m
	# cylinder would have been one line, and would have read as a flagpole.
	_Parts.cyl(root_node, 0.17, 1.3, Vector3(0, 1.6, 0.3), Vector3.ZERO, false, 10)
	_Parts.cyl(root_node, 0.125, 1.1, Vector3(0, 2.8, 0.3), Vector3.ZERO, false, 10)
	_Parts.cyl(root_node, 0.09, 0.9, Vector3(0, 3.8, 0.3), Vector3.ZERO, false, 10)
	# THE COIL at the base of the mast. Flat torii round a vertical column is the
	# correct orientation for ring() — it is already flat and needs no rotation.
	for i in 3:
		_Parts.ring(root_node, 0.17, 0.33, Vector3(0, 1.1 + float(i) * 0.26, 0.3))
	_Parts.sphere(root_node, 0.18, Vector3(0.3, 1.25, 0.3))
	# The crown: two stepped rings and a terminal bead.
	_Parts.ring(root_node, 0.09, 0.55, Vector3(0, 4.25, 0.3))
	_Parts.ring(root_node, 0.07, 0.38, Vector3(0, 4.44, 0.3))
	_Parts.sphere(root_node, 0.16, Vector3(0, 4.6, 0.3))
	# SIX RIBS, DOWN AND OUT. Each rib lives in its own yawed node so only one
	# rotation is ever composed by hand; hanging a rod off a rotated parent's
	# local axis is the mistake this project makes most often. Inside the yawed
	# node, local -Z is outward, and a +125 degree tilt about X takes the
	# cylinder's +Y axis to (0, -0.57, -0.82): down and outward together.
	for i in 6:
		var a := TAU * float(i) / 6.0
		var rib := K.node_at(root_node, Vector3(0, 4.25, 0.3), Vector3(0, -a, 0))
		_Parts.cyl(rib, 0.05, 1.0, Vector3(0, -0.29, -0.59), Vector3(125.0 * K.DEG, 0, 0))
		_Parts.sphere(rib, 0.09, Vector3(0, -0.57, -1.0))


## B. HOOP — the field has a DIRECTION. One enormous ring carried on a forward-
## raked yoke, with a second, smaller ring behind it: the squad is told where
## the jamming is going by where the hoop is pointed. Nothing else in the roster
## is a circle, so it reads at any distance.
##
## THE RING IS STOOD UP ON PURPOSE. ring() is a CSGTorus3D that already lies
## flat, and rotating one by PI/2 "to lay it down" is a mistake this project has
## made repeatedly — it stands it into an arch. Here the arch IS the design: a
## doorway you fire a field through. The comment exists so the next reader does
## not helpfully "fix" it.
##
## RISK: edge-on a vertical ring is a bar. The inner ring, the cross-brace and
## the yoke are there so the profile view still has something to read, and it is
## still the weakest angle of the four.
static func warden_b(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.6, 0.95, 1.9), Vector3(0, 0.5, 0))
	# Head set AFT, behind the hoop, so the eye looks out through it and nothing
	# ever crosses it.
	_blind_head(root_node, Vector3(0, 1.0, 0.42), 0.5)
	for sx: float in [-1.0, 1.0]:
		K.leg(root_node, Vector3(sx * 0.7, -0.08, 0), 0.72, 0.84, -sx * 5.0, 0.0, true)
		# The yoke, raked forward so the hoop leads the machine.
		_Parts.box(root_node, Vector3(0.2, 1.6, 0.24),
				Vector3(sx * 0.62, 1.25, -0.3), Vector3(-14.0 * K.DEG, 0, 0))
		_Parts.studs(root_node, 3, Vector3(sx * 0.73, 0.65, -0.18), Vector3(0, 0.26, 0), 0.035)
	_Parts.ring(root_node, 0.11, 1.05, Vector3(0, 1.95, -0.78), Vector3(PI * 0.5, 0, 0))
	_Parts.ring(root_node, 0.08, 0.72, Vector3(0, 1.95, -0.4), Vector3(PI * 0.5, 0, 0))
	# The feed: a cross brace and a bead at the focus. Without it the hoop is a
	# wheel, and a wheel on the front of a vehicle means something else entirely.
	_Parts.box(root_node, Vector3(0.09, 1.95, 0.09), Vector3(0, 1.95, -0.78))
	_Parts.box(root_node, Vector3(1.95, 0.09, 0.09), Vector3(0, 1.95, -0.78))
	_Parts.sphere(root_node, 0.22, Vector3(0, 1.95, -0.78))
	_Parts.cyl(root_node, 0.07, 0.5, Vector3(0, 1.95, -0.55), Vector3(PI * 0.5, 0, 0))


## C. COIL — the field is a BUBBLE, and it is short. Squat, six-wheeled, with a
## stacked coil and a terminal where a turret would be: this one has to drive
## into the enemy to do anything, which is a genuinely different order to give
## than A or B. The only wheeled Warden, so it also reads as the fast one.
##
## RISK: a coil stack on a flat deck reads as a generator or a piece of base
## scenery. The chamfered hull, the head out front and the earthing rods at the
## corners are what keep it a vehicle rather than a building.
static func warden_c(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(2.1, 0.9, 2.9), Vector3(0, 0.55, 0))
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			K.wheel(root_node, Vector3(sx * 1.02, 0.18, -1.0 + float(i) * 1.0), 0.42, 0.3)
	_blind_head(root_node, Vector3(0, 1.02, -1.15), 0.48)
	# Four coaxial coils, narrowing upward. Flat, which is ring()'s own
	# orientation and the right one for a vertical core.
	var radii := [1.0, 0.86, 0.7, 0.52]
	for i in radii.size():
		var r: float = radii[i]
		_Parts.ring(root_node, r - 0.12, r, Vector3(0, 1.15 + float(i) * 0.27, 0.1))
	_Parts.cyl(root_node, 0.2, 1.4, Vector3(0, 1.55, 0.1), Vector3.ZERO, false, 10)
	_Parts.sphere(root_node, 0.3, Vector3(0, 2.3, 0.1))
	# Earthing rods at the deck corners, leaning in toward the terminal. They are
	# the only pieces that break the outline sideways, which a stack of rings on
	# a flat deck badly needs.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_Parts.cyl(root_node, 0.055, 1.4, Vector3(sx * 0.84, 1.7, sz * 1.15),
					Vector3(0, 0, sx * 10.0 * K.DEG), false, 8)
			_Parts.sphere(root_node, 0.1, Vector3(sx * 0.72, 2.4, sz * 1.15))


## D. ARRAY — the field is DEPLOYED. A cage aerial of four raked masts and three
## crossbar frames, over a small hull on pillar legs braced by outriggers. The
## proposition is that it stops and sets up: the one Warden that reads as an
## emplacement you move between fights rather than a unit you manoeuvre.
##
## PILLAR LEGS, NOT THE WALKER'S. digitigrade = false gives the load-bearing
## column, which is the difference between a thing that walks and a thing that
## has planted itself — and the planting is the whole option.
##
## RISK: thin bars disappear at squad distance and the cage can read as
## scaffolding. If it survives the render it needs thicker stock, not more of it.
static func warden_d(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.35, 0.85, 1.6), Vector3(0, 0.78, 0))
	_blind_head(root_node, Vector3(0, 1.22, -0.72), 0.5)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# SPLAY SIGN, derived rather than copied. leg() applies splay as a
			# rotation about Z, and rotating +Y about +Z carries it toward -X —
			# so a POSITIVE splay leans the right-hand leg inward. Outward wants
			# the negative, which is the opposite of what reads naturally.
			K.leg(root_node, Vector3(sx * 0.55, 0.38, sz * 0.5), 0.52, 0.56,
					-sx * 12.0, 0.0, false, 1.15)
			# The outrigger: a strut down and out to a pad on the ground.
			_Parts.cyl(root_node, 0.06, 1.1, Vector3(sx * 0.95, 0.15, sz * 0.95),
					Vector3(sz * 24.0 * K.DEG, 0, -sx * 24.0 * K.DEG), false, 8)
			_Parts.plate(root_node, 0.34, 0.34, 0.09, 0.08,
					Vector3(sx * 1.25, -0.42, sz * 1.25), Vector3(PI * 0.5, 0, 0))
			# Masts, raked outward in X only. Leaning in two axes at once is how
			# a corner post ends up somewhere nobody intended; one axis is enough
			# to open the cage.
			_Parts.cyl(root_node, 0.065, 2.2, Vector3(sx * 0.69, 2.28, sz * 0.62),
					Vector3(0, 0, -sx * 10.0 * K.DEG), false, 8)
			_Parts.sphere(root_node, 0.1, Vector3(sx * 0.88, 3.35, sz * 0.62))
	# Three crossbar frames. The half-width at each height is the mast's rake
	# solved for that height, not a guess — a bar that misses its post is the
	# single most obvious error a cage can have.
	for i in 3:
		var y := 1.75 + float(i) * 0.68
		var hw: float = 0.5 + (y - 1.18) * 0.176
		for sz: float in [-1.0, 1.0]:
			_Parts.box(root_node, Vector3(hw * 2.0, 0.05, 0.05), Vector3(0, y, sz * 0.62))
		for sx: float in [-1.0, 1.0]:
			_Parts.box(root_node, Vector3(0.05, 0.05, 1.24), Vector3(sx * hw, y, 0))
	_Parts.ring(root_node, 0.1, 0.42, Vector3(0, 3.45, 0))
	_Parts.sphere(root_node, 0.14, Vector3(0, 3.6, 0))


# ─────────────────────────────────────────────
# DRAYMAN — FOUR OPTIONS
#
# Two things must be legible before anything else: it is CARRYING something,
# and it can HAND IT OVER. The load is drawn as countable objects — crates with
# lids, upright cases, a belt of individual rounds — because a smooth container
# reads as fuel, and fuel is a different vehicle.
#
# Nothing here uses K.head: the kit head's stub barrel is the one detail that
# would turn a supply vehicle into a gun truck, which is the brief's single
# explicit prohibition.
# ─────────────────────────────────────────────


## A. FLATBED — the straight answer and the Reclaimer's closest relative. Six
## wheels, a railed deck stacked with crates, and a knuckle boom on a slew ring
## that swings a crate out over the flank to whoever is standing there.
##
## THE BOOM REACHES OUT, NOT FORWARD. Slewed over the nose the grab and its load
## passed straight across the cab's eye, which is the one thing that may never
## happen; out to the front quarter it breaks the outline just as hard and hands
## the crate to a squad walking beside the vehicle, which is the actual fiction.
##
## RISK: this is the option most likely to read as "the Reclaimer again". The
## crate stack and the railed deck are the whole difference, and if the render
## says they are not enough, B or D is the answer rather than a bigger boom.
static func drayman_a(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.75, 0.85, 3.3), Vector3(0, 0.68, 0))
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			K.wheel(root_node, Vector3(sx * 0.95, 0.22, -1.2 + float(i) * 1.2), 0.42, 0.28)
	_blind_head(root_node, Vector3(0, 1.14, -1.15), 0.56)
	# Deck and rails. The rails stand proud of the load so the stack reads as
	# being held in rather than piled on.
	_Parts.plate(root_node, 1.6, 2.2, 0.12, 0.08, Vector3(0, 1.2, 0.42), Vector3(PI * 0.5, 0, 0))
	for sx: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.09, 0.34, 2.2), Vector3(sx * 0.8, 1.33, 0.42))
		_Parts.studs(root_node, 4, Vector3(sx * 0.86, 1.2, -0.5), Vector3(0, 0, 0.6), 0.032)
	_crates(root_node, Vector3(0, 1.18, 0.5), 2, 2, 3)
	# Slew ring on the front quarter, and the boom that stands on it.
	_Parts.cyl(root_node, 0.3, 0.14, Vector3(0.3, 1.2, 0.3), Vector3.ZERO, false, 12)
	var slew := K.node_at(root_node, Vector3(0.3, 1.3, 0.3), Vector3(0, -45.0 * K.DEG, 0))
	var tip := K.boom(slew, Vector3.ZERO, 1.4, 1.1, 36.0, -70.0)
	# THE LOAD HANGS LEVEL. The tip inherits lift + bend, so a crate parented
	# straight to it comes out tilted 34 degrees — the same error that once had
	# the Bulwark's tower shield lying flat like a paddle. Undoing the sum here
	# keeps the crate upright whatever the boom is posed to.
	var hang := K.node_at(tip, Vector3.ZERO, Vector3(34.0 * K.DEG, 0, 0))
	_Parts.box(hang, Vector3(0.36, 0.26, 0.36), Vector3(0, -0.14, 0))
	for s: float in [-1.0, 1.0]:
		_Parts.wedge(hang, 0.46, 0.16, 0.14, 0.2, Vector3(s * 0.2, -0.42, 0),
				Vector3(PI * 0.5, 0, s * 16.0 * K.DEG))
	_crates(hang, Vector3(0, -0.95, 0), 1, 1, 1)


## B. HOPPER — bulk, not boxes. A ribbed silo with an open rim bulking over the
## hull, funnelling into the vehicle, and a short chute boom that swings out to
## the side and spills a belt of rounds at knee height. The one option that says
## the supply is MEASURED OUT rather than handed over, which is a different
## resupply rule if the design ever wants one.
##
## THE BELT IS DOING THE WORK. A drum on a chassis is a cement mixer or a
## tanker; individual rounds falling out of the chute mouth is the only cue in
## the whole kit that says AMMUNITION without a weapon attached to it.
##
## RISK: the silhouette is dominated by one smooth mass. The ribs and the open
## rim fight that, and if the render still says "tanker" the drum needs to lose
## height rather than gain detail.
static func drayman_b(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.9, 0.95, 2.9), Vector3(0, 0.72, 0))
	K.wheels(root_node, 1.02, 1.05, 0.26, 0.5)
	_blind_head(root_node, Vector3(0, 1.18, -1.12), 0.56)
	# The funnel: a cone inverted so its point goes INTO the hull. cone = true
	# tapers toward local +Y, so a PI rotation about X is what turns a spike into
	# a hopper throat.
	_Parts.cyl(root_node, 0.9, 0.5, Vector3(0, 1.2, 0), Vector3(PI, 0, 0), true, 14)
	_Parts.cyl(root_node, 0.92, 1.0, Vector3(0, 1.92, 0), Vector3.ZERO, false, 14)
	for i in 3:
		_Parts.ring(root_node, 0.92, 1.02, Vector3(0, 1.6 + float(i) * 0.32, 0))
	_Parts.ring(root_node, 0.78, 0.94, Vector3(0, 2.42, 0))
	_Parts.studs(root_node, 4, Vector3(-0.42, 2.44, -0.84), Vector3(0.28, 0, 0), 0.04)
	# THE CHUTE, SWUNG OUT TO THE RIGHT. boom() builds along its own -Z, so the
	# reach direction is set by yawing the node it hangs from: -90 degrees about
	# Y maps -Z onto +X. Doing it this way means the boom's own lift and bend
	# angles still mean what they say.
	var slew := K.node_at(root_node, Vector3(0.92, 1.05, -0.35), Vector3(0, -PI * 0.5, 0))
	var tip := K.boom(slew, Vector3.ZERO, 0.85, 0.7, -8.0, -34.0)
	var mouth := K.node_at(tip, Vector3.ZERO, Vector3(42.0 * K.DEG, 0, 0))
	_Parts.plate(mouth, 0.5, 0.44, 0.3, 0.1, Vector3(0, -0.2, 0), Vector3(PI * 0.5, 0, 0))
	# Rounds falling out of it, each one its own object.
	for i in 6:
		_Parts.box(mouth, Vector3(0.07, 0.13, 0.07),
				Vector3(0.0, -0.46 - float(i) * 0.16, -0.04 - float(i) * 0.05),
				Vector3(float(i) * 7.0 * K.DEG, 0, 0))


## C. PANNIER — a pack animal. A narrow spine on four legs with a tall crate
## pannier slung outside each flank, a ribbed belt drum lashed along the top,
## and ONE handover arm on the right. The only legged Drayman, so it is also the
## only one that can follow the squad onto ground a wheel cannot take.
##
## ASYMMETRY ON PURPOSE. A second arm would have balanced it and cost the whole
## read: one arm says this machine turns toward you and gives you something.
##
## RISK: legs plus boxes is close to the Bulwark's footprint from the front, and
## panniers can read as applique armour. The open lids and the belt drum are
## what keep it logistics; if they do not carry, the fix is a crate standing on
## top of the spine where the outline is clear.
static func drayman_c(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.0, 0.95, 2.4), Vector3(0, 1.25, 0))
	_blind_head(root_node, Vector3(0, 1.76, -1.0), 0.52)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# REACH SIGN: leg() applies reach about X, and a positive X rotation
			# carries +Y toward -Z, which is forward. The front legs are at
			# sz = -1, so -sz * 12 puts them forward and the rear pair back — a
			# stagger, which is what stops four identical legs reading as a table.
			K.leg(root_node, Vector3(sx * 0.46, 0.85, sz * 0.82), 0.8, 0.9,
					-sx * 8.0, -sz * 12.0, true, 1.1)
		# The pannier. plate() extrudes along its own +Z, which a yaw of s * PI/2
		# sends outboard on each side — a fixed +PI/2 would have buried the left
		# one inside the spine.
		_Parts.plate(root_node, 1.9, 1.1, 0.42, 0.1, Vector3(sx * 0.5, 1.3, 0),
				Vector3(0, sx * PI * 0.5, 0))
		for i in 3:
			_Parts.plate(root_node, 0.5, 0.26, 0.1, 0.05,
					Vector3(sx * 0.94, 1.78, -0.6 + float(i) * 0.6),
					Vector3(0, PI * 0.5, 0))
		_Parts.studs(root_node, 3, Vector3(sx * 0.94, 0.9, -0.6), Vector3(0, 0, 0.6), 0.035)
		# A belt drum lying along Z. Ringing a Z-axis cylinder is the one case
		# where a torus is correctly STOOD UP: PI/2 about X puts it in the XY
		# plane, square to the drum.
		_Parts.cyl(root_node, 0.2, 1.5, Vector3(sx * 0.78, 1.98, 0),
				Vector3(PI * 0.5, 0, 0), false, 10)
		for i in 3:
			_Parts.ring(root_node, 0.2, 0.25, Vector3(sx * 0.78, 1.98, -0.5 + float(i) * 0.5),
					Vector3(PI * 0.5, 0, 0))
	# THE ARM, RIGHT SIDE ONLY. out_ang is a rotation about Z, and a NEGATIVE
	# angle is what swings the right arm outboard — the mirror of what the sign
	# looks like it should be.
	var wrist := K.arm(root_node, Vector3(0.62, 1.68, -0.5), 0.58, 0.6,
			62.0, -20.0, -10.0, 0.95, "claw")
	_crates(wrist, Vector3(0, -0.85, 0), 1, 1, 1)


## D. TRAILER — the reach is a RAIL, not an arm. A short tractor towing a rack
## of upright cases under an overhead gantry whose beam cantilevers well past
## the flank, with a trolley and a crate hanging off the end of it. The only
## option where the resupply point is somewhere the vehicle does not have to go,
## and the only articulated thing in the game.
##
## THE CASES ARE BLUNT ON PURPOSE. A rack of upright rounds with pointed noses
## is a missile truck, which is the exact failure the brief forbids; flat tops,
## a lifting eye and a band at the base make them cases rather than warheads.
##
## RISK: two bodies may read as two units, and an articulated hull is the one
## shape here with a real engineering cost — the navmesh has no notion of a
## trailer and this would have to fake it. Worth asking before it is modelled.
static func drayman_d(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(1.7, 0.85, 1.9), Vector3(0, 0.68, 0))
	K.wheels(root_node, 0.92, 0.62, 0.22, 0.42)
	_blind_head(root_node, Vector3(0, 1.12, -0.62), 0.54)
	# Drawbar and pin — the join has to be visible or the two halves read as one
	# badly proportioned hull.
	_Parts.box(root_node, Vector3(0.2, 0.16, 0.8), Vector3(0, 0.52, 1.2))
	_Parts.cyl(root_node, 0.13, 0.3, Vector3(0, 0.62, 1.5), Vector3.ZERO, false, 10)
	K.hull(root_node, Vector3(1.8, 0.6, 1.7), Vector3(0, 0.72, 2.45))
	for sx: float in [-1.0, 1.0]:
		K.wheel(root_node, Vector3(sx * 0.96, 0.22, 2.1), 0.42, 0.26)
		K.wheel(root_node, Vector3(sx * 0.96, 0.22, 2.95), 0.42, 0.26)
	_Parts.plate(root_node, 1.7, 1.7, 0.1, 0.08, Vector3(0, 1.05, 2.45), Vector3(PI * 0.5, 0, 0))
	# The rack: six cases standing on the bed.
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			var at := Vector3(sx * 0.42, 1.42, 1.95 + float(i) * 0.45)
			_Parts.cyl(root_node, 0.13, 0.78, at, Vector3.ZERO, false, 10)
			_Parts.ring(root_node, 0.13, 0.17, at + Vector3(0, -0.3, 0))
			_Parts.ring(root_node, 0.04, 0.08, at + Vector3(0, 0.42, 0))
	# The gantry: two A-frames and a beam that overhangs the right flank by more
	# than a metre. The overhang is the reach, and it has to clear the hull or
	# the whole idea vanishes into the silhouette.
	for sz: float in [1.85, 3.1]:
		for sx: float in [-1.0, 1.0]:
			_Parts.box(root_node, Vector3(0.12, 1.5, 0.12), Vector3(sx * 0.72, 1.8, sz),
					Vector3(0, 0, sx * 10.0 * K.DEG))
		_Parts.box(root_node, Vector3(1.4, 0.12, 0.14), Vector3(0, 2.52, sz))
	_Parts.box(root_node, Vector3(2.9, 0.14, 0.16), Vector3(0.85, 2.6, 2.45))
	_Parts.box(root_node, Vector3(0.32, 0.24, 0.34), Vector3(1.7, 2.42, 2.45))
	_Parts.cyl(root_node, 0.03, 0.6, Vector3(1.7, 2.04, 2.45), Vector3.ZERO, false, 6)
	_crates(root_node, Vector3(1.7, 1.3, 2.45), 1, 1, 1)


# ─────────────────────────────────────────────
# VESSEL — FOUR OPTIONS
#
# It must read as CONTAINING something, and the four options open in four
# directions — upward, astern, outboard, and forward out of a Nest's own hatch —
# on four different sets of running gear, so no two are the same drawing at a
# different size. Three of the four carry visible Hatchlings; B is deliberately
# the one that has already launched, as the control on whether an empty bay
# still reads.
#
# It is the biggest frame in the batch by volume on purpose. It is NOT the
# hardest-hitting: every one of these carries at most the kit's smallest head,
# because the proposition is bodies on the field rather than damage.
# ─────────────────────────────────────────────


## A. DORSAL BAY — the doors are the silhouette. Two clamshells standing open
## off a six-wheeled hull, both Hatchlings sitting in cradles with their rotors
## clear of the coaming. The most legible of the four at a glance: it is a box
## with the lid off and two drones in it.
##
## THE DRONES SIT FORE AND AFT, not side by side. Two 0.9 m rotor spans will not
## fit across a 1.75 m bay without overlapping into one shape, and two drones
## that read as one drone is the whole proposition lost to a layout error.
##
## RISK: a hull with a hole in the roof is also an APC. The cradles and the open
## doors have to carry it; if they do not, the doors should go further over.
static func vessel_a(root_node: Node3D) -> void:
	var hull := K.hull(root_node, Vector3(2.7, 1.3, 4.0), Vector3(0, 1.0, 0))
	hull.name = "Hull"
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			K.wheel(root_node, Vector3(sx * 1.42, 0.3, -1.4 + float(i) * 1.4), 0.58, 0.34)
	K.head(root_node, Vector3(0, 1.7, -1.5), 0.58)
	# The bay: a coaming on the deck, hollowed by a cutter that is taller than
	# the walls it opens. A cutter the same height leaves a skin across the top.
	var coaming := _Parts.box(root_node, Vector3(2.15, 0.6, 2.5), Vector3(0, 1.85, 0.35))
	coaming.name = "Coaming"
	var well := _Parts.box(coaming, Vector3(1.78, 0.8, 2.15), Vector3(0, 0.12, 0))
	well.operation = CSGShape3D.OPERATION_SUBTRACTION
	for s: float in [-1.0, 1.0]:
		# HINGE SIGN, worked out rather than guessed: a rotation about Z carries
		# +X toward +Y, so s * 72 degrees lifts each leaf up and outward from its
		# own sill. The opposite sign drops both doors onto the wheels.
		var hinge := K.node_at(root_node, Vector3(s * 1.05, 2.12, 0.35),
				Vector3(0, 0, s * 72.0 * K.DEG))
		_Parts.plate(hinge, 2.45, 1.1, 0.1, 0.12, Vector3(s * 0.55, 0, 0),
				Vector3(0, PI * 0.5, 0))
		_Parts.studs(hinge, 4, Vector3(s * 0.25, 0.09, -0.9), Vector3(0, 0, 0.6), 0.035)
	for i in 2:
		var at := Vector3(0, 2.02, -0.42 + float(i) * 1.5)
		# Cradle first, drone on top of it, so the drone is never floating.
		_Parts.plate(root_node, 0.7, 0.6, 0.12, 0.07, at + Vector3(0, -0.12, 0),
				Vector3(PI * 0.5, 0, 0))
		for s: float in [-1.0, 1.0]:
			_Parts.wedge(root_node, 0.3, 0.26, 0.5, 0.1, Vector3(s * 0.3, at.y, at.z),
					Vector3(0, PI * 0.5, s * 14.0 * K.DEG))
		_hatchling(root_node, at + Vector3(0, 0.06, 0))


## B. STERN RAMP — it opens BACKWARDS, and it is empty. A tracked hull with the
## tail cut out, a ramp down to the ground, ribs and two bare cradles visible
## inside, and a lifting gantry over the opening. The control case: if an empty
## hangar still says "two things live in here", the carrier does not have to be
## drawn with its cargo on it every time it appears.
##
## RISK: that is also the failure mode. If the render reads as a recovery
## vehicle or a troop carrier, the answer is that the Vessel always shows its
## drones, and A, C and D are the shortlist.
static func vessel_b(root_node: Node3D) -> void:
	var hull := K.hull(root_node, Vector3(2.8, 1.5, 3.6), Vector3(0, 1.3, 0))
	hull.name = "Hull"
	# The bay, cut clean through the tail. Positions on a hull child are in the
	# hull's own space, so this is 0.2 below and 1.1 behind its centre.
	var bay := _Parts.box(hull, Vector3(1.9, 1.15, 2.6), Vector3(0, -0.2, 1.1))
	bay.operation = CSGShape3D.OPERATION_SUBTRACTION
	for sx: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.52, 0.78, 3.3), Vector3(sx * 1.3, 0.44, 0))
		for i in 5:
			K.wheel(root_node, Vector3(sx * 1.3, 0.34, -1.3 + float(i) * 0.65), 0.32, 0.56)
	K.head(root_node, Vector3(0, 2.12, -1.0), 0.56)
	# THE RAMP. Under a node rotated about X, local +Z goes down and aft, so the
	# hinge angle and the leaf length together decide where the lip lands: 34
	# degrees over 1.0 m drops 0.56 from a sill at 0.55 and sets the lip on the
	# ground. Guessing either one puts the ramp through the floor.
	var hinge := K.node_at(root_node, Vector3(0, 0.56, 1.8), Vector3(34.0 * K.DEG, 0, 0))
	_Parts.plate(hinge, 1.8, 1.0, 0.12, 0.1, Vector3(0, 0.06, 0.5), Vector3(PI * 0.5, 0, 0))
	for s: float in [-1.0, 1.0]:
		_Parts.box(hinge, Vector3(0.1, 0.2, 1.0), Vector3(s * 0.85, 0.12, 0.5))
	# Interior: roof ribs, floor rails and two empty cradles. The ribs are what
	# make the hole read as a room rather than as damage.
	for i in 4:
		_Parts.box(root_node, Vector3(1.8, 0.09, 0.1), Vector3(0, 1.62, 0.1 + float(i) * 0.5))
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.13, 0.09, 2.0), Vector3(s * 0.56, 0.6, 0.95))
	for i in 2:
		var at := Vector3(0, 0.7, 0.45 + float(i) * 0.95)
		_Parts.plate(root_node, 0.7, 0.55, 0.1, 0.07, at, Vector3(PI * 0.5, 0, 0))
		for s: float in [-1.0, 1.0]:
			_Parts.wedge(root_node, 0.28, 0.24, 0.46, 0.09,
					Vector3(s * 0.3, at.y + 0.1, at.z), Vector3(0, PI * 0.5, s * 14.0 * K.DEG))
	# Gantry over the opening — the piece that breaks the outline astern, where a
	# flat tail would otherwise end the silhouette dead.
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.14, 1.0, 0.14), Vector3(s * 0.95, 2.4, 1.7))
	_Parts.box(root_node, Vector3(2.1, 0.14, 0.16), Vector3(0, 2.86, 1.7))
	_Parts.cyl(root_node, 0.035, 0.5, Vector3(0, 2.55, 1.7), Vector3.ZERO, false, 6)
	_Parts.sphere(root_node, 0.12, Vector3(-0.6, 2.2, -1.5))


## C. SIDE PODS — it opens OUTBOARD, and it walks. The heaviest legged frame in
## the game: a hull on four thick digitigrade legs with a long pod hinged along
## each flank, swung out, a Hatchling sitting on each opened pod ready to lift.
## Legs are the gameplay argument as much as the look — a carrier that can take
## the ground the squad takes is a carrier that is with them when it matters.
##
## RISK: it is the widest thing in the batch when open, which is a real cost on
## levels built around gaps and gates — and the one measurement a render will
## not tell you. Worth checking against a doorway before it goes further.
static func vessel_c(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(2.2, 1.5, 3.0), Vector3(0, 1.45, 0))
	K.head(root_node, Vector3(0, 2.26, -0.8), 0.6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			K.leg(root_node, Vector3(sx * 0.98, 0.55, sz * 1.0), 1.0, 1.1,
					-sx * 6.0, -sz * 6.0, true, 1.5)
		# The pod hangs off a hinge at its FORWARD edge and swings aft-outward.
		# Yawing by s * 24 degrees carries the pod's local +Z (its length) out to
		# each side; everything inside the hinge is then placed in pod space, so
		# the mirroring is handled by the one signed angle rather than by hand.
		var hinge := K.node_at(root_node, Vector3(sx * 1.08, 1.5, -1.25),
				Vector3(0, sx * 24.0 * K.DEG, 0))
		_Parts.plate(hinge, 1.7, 1.1, 0.5, 0.12, Vector3(sx * 0.25, 0, 0.85),
				Vector3(0, sx * PI * 0.5, 0))
		_Parts.studs(hinge, 4, Vector3(sx * 0.5, 0.42, 0.25), Vector3(0, 0, 0.42), 0.038)
		# The drone stands ON the opened pod, not outboard of it: outboard it
		# pushed the frame past four metres wide for no extra read.
		_Parts.box(hinge, Vector3(0.7, 0.1, 0.8), Vector3(sx * 0.3, 0.6, 0.85))
		_hatchling(hinge, Vector3(sx * 0.3, 0.72, 0.85))
	# Deck rail and beacon, so the roof is not a blank between the two pods.
	_Parts.box(root_node, Vector3(1.4, 0.1, 0.12), Vector3(0, 2.26, 1.2))
	_Parts.cyl(root_node, 0.07, 0.4, Vector3(-0.7, 2.4, 1.2), Vector3.ZERO, false, 8)
	_Parts.sphere(root_node, 0.13, Vector3(-0.7, 2.62, 1.2))


## D. NEST — it quotes the enemy. The Nest's own proportions (a 2.4 m cube body,
## a capped roof, a tall front hatch, rear vents and a mast with a canted dish)
## stood on four pillar legs and walked out of the fight it used to sit in, with
## a Hatchling coming out of the open hatch.
##
## WHY THIS ONE EXISTS: anyone who has fought a Nest already knows what it does.
## No other option in the batch can be read correctly by a player who has never
## seen the unit before, and that is worth more than originality here.
##
## IT CARRIES NO GUN, deliberately — the Nest has none either, and the eye and
## the pillar legs are what claim the shape as ours rather than captured.
##
## RISK: exactly that. It may read as a captured enemy Nest rather than an issued
## frame, and the faction paint will have to do more work here than anywhere else.
static func vessel_d(root_node: Node3D) -> void:
	var body := K.hull(root_node, Vector3(2.7, 1.9, 2.7), Vector3(0, 1.5, 0))
	body.name = "Hull"
	# The hatch opening, cut through the front face from the floor up.
	var mouth := _Parts.box(body, Vector3(1.5, 1.35, 1.2), Vector3(0, -0.45, -1.1))
	mouth.operation = CSGShape3D.OPERATION_SUBTRACTION
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# PILLAR LEGS: a plinth that walks. The Nest sits on a plinth, and
			# the single cheapest way to say "ours, and it moves" is to put the
			# load-bearing version of the Walker's leg under it.
			K.leg(root_node, Vector3(sx * 0.95, 0.4, sz * 0.95), 0.75, 0.8,
					-sx * 5.0, 0.0, false, 1.6)
	# The cap, and the lip round it — the Nest's own roof.
	_Parts.plate(root_node, 2.3, 2.3, 0.4, 0.16, Vector3(0, 2.72, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.ring(root_node, 1.16, 1.32, Vector3(0, 2.34, 0))
	# THE HATCH, DROPPED FORWARD. Hinged at the sill and rotated -62 degrees
	# about X, the leaf's local +Y lands at (0, 0.47, -0.88): it leans out over
	# the ground in front, which is what a bay door does and a wall does not.
	var hinge := K.node_at(root_node, Vector3(0, 0.58, -1.36), Vector3(-62.0 * K.DEG, 0, 0))
	_Parts.plate(hinge, 1.42, 1.45, 0.14, 0.12, Vector3(0, 0.72, 0))
	_Parts.studs(hinge, 3, Vector3(-0.4, 0.3, -0.1), Vector3(0.4, 0, 0), 0.04)
	_hatchling(root_node, Vector3(0, 1.15, -1.66))
	# Vents aft, standing proud of the rear face so they break the outline
	# instead of disappearing into it.
	for i in 3:
		_Parts.box(root_node, Vector3(1.7, 0.08, 0.14), Vector3(0, 1.1 + float(i) * 0.26, 1.4))
	# Mast and canted dish, lifted straight off the enemy article.
	_Parts.cyl(root_node, 0.08, 0.9, Vector3(0.55, 3.15, 0.5), Vector3.ZERO, false, 8)
	_Parts.plate(root_node, 0.95, 0.55, 0.07, 0.1, Vector3(0.55, 3.6, 0.34),
			Vector3(-55.0 * K.DEG, 0, 0))
	_blind_head(root_node, Vector3(-0.1, 2.74, -0.6), 0.52)
