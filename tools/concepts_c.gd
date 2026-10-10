extends RefCounted
class_name ConceptsC

# ─────────────────────────────────────────────
# ENEMY FRAMES — CONCEPT PASS C
#
# Three hostile frames, four options each. Nothing here renders: these are
# builders that hang CSG off a root, and another process stages and shoots them.
#
#   BROODCARRIER  Swarm,    supply 2, hull 200, AERIAL — a flying hive
#   BASTION       StratCom, supply 3, hull 300        — walks, then plants
#   SEE-ENGINE    Argus,    supply 3, hull 240        — watches and coordinates
#
# THE FACTION IS THE BRIEF. The chamfered hull, the turret ring, the single
# offset eye and the whip antenna in concept_kit.gd are the PLAYER's language —
# and the player's parent is StratCom, so Bastion is built out of that kit and
# should look issued from the same factory: same vocabulary, more of it, better
# finished. The other two reject it on purpose, from raw primitives, without
# leaving this game's world of boxes and cylinders:
#
#   SWARM     accreted, asymmetric, counted badly. No two lift fans match,
#             nothing is centred, nothing is precision-made. Amber.
#   ARGUS     an orbital intelligence that does not think in terms of soldiers.
#             Too many sensors, no face, and proportions that do not look like
#             they carry their own weight. Tyrian purple.
#
# ONLY THE TWELVE `<frame>_<letter>` FUNCTIONS ARE BUILDERS. Everything with a
# leading underscore is a shared part and takes more than a root node.
# ─────────────────────────────────────────────

const K := preload("res://tools/concept_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")


# ─────────────────────────────────────────────
# SHARED PARTS
# ─────────────────────────────────────────────

## The thing in the pods: the small melee drone the carrier spawns, roughly the
## size the Chaser ships at (0.45 m body). Four stub legs and two mandibles, no
## gun — the brood's whole threat is contact, and a hatchling with a barrel on
## it would read as a spare sensor instead.
static func _hatchling(to: Node, at: Vector3, r: float) -> void:
	_Parts.sphere(to, r, at, Vector3(1.0, 0.8, 1.15))
	for s in [-1.0, 1.0]:
		for f in [-1.0, 1.0]:
			_Parts.box(to, Vector3(r * 0.22, r * 1.2, r * 0.22),
					at + Vector3(s * r * 0.62, -r * 0.6, f * r * 0.55),
					Vector3(0, 0, s * 24.0 * K.DEG))
	for s in [-1.0, 1.0]:
		_Parts.box(to, Vector3(r * 0.18, r * 0.18, r * 0.85),
				at + Vector3(s * r * 0.3, 0, -r * 1.05),
				Vector3(0, s * 15.0 * K.DEG, 0))


## ONE BROOD POD. A squashed egg with a band round it and a stalk up into the
## carrier. `open` cracks the bottom off and puts a hatchling half out, which is
## the only part of these frames that says SPAWNS rather than CARRIES.
static func _pod(to: Node, at: Vector3, r: float, open: bool) -> void:
	var shell := _Parts.sphere(to, r, at, Vector3(1.0, 1.2, 1.0))
	# The band LIES FLAT, which is the orientation ring() already has: the pod
	# hangs vertically, so a torus in the XZ plane girdles it. Standing it up
	# here would make an arch over the egg.
	_Parts.ring(to, r * 0.94, r * 1.15, at + Vector3(0, r * 0.26, 0))
	_Parts.cyl(to, r * 0.2, r * 0.85, at + Vector3(0, r * 1.5, 0), Vector3.ZERO, false, 8)
	if not open:
		return
	# The crack: a box 2.6r across against a 2r shell, swung off the bottom
	# front. An undersized cut leaves a sliver of shell across the opening and
	# the pod reads shut, which is the whole point lost. The cut inherits the
	# shell's 1.2 Y squash, which only makes it bigger — harmless here, and the
	# reason not to tune this by eye.
	var cut := _Parts.box(shell, Vector3(r * 2.6, r * 1.7, r * 2.6),
			Vector3(0, -r * 1.45, -r * 0.5), Vector3(26.0 * K.DEG, 0, 0))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	_hatchling(to, at + Vector3(0, -r * 1.1, -r * 0.42), r * 0.46)


## A STRATCOM GROUND SPADE: ram, jack and a blade that bites. This is what makes
## the planted state legible — a frame sitting on its belly reads as broken,
## and a frame nailed down by four of these reads as deployed.
##
## YAW FIRST, THEN LEAN. `yaw_deg` aims the spade (its own -Z at yaw 0 is the
## frame's front), and the lean is applied INSIDE that yawed frame so every
## spade leans along its own radius. Leaning them in the root's frame instead is
## this project's commonest error: all four then lean the same way and two of
## them drive into the hull.
static func _spade(to: Node, at: Vector3, yaw_deg: float, lean_deg: float,
		drop: float) -> void:
	var post := K.node_at(to, at, Vector3(0, yaw_deg * K.DEG, 0))
	var ram := K.node_at(post, Vector3.ZERO, Vector3(lean_deg * K.DEG, 0, 0))
	_Parts.box(ram, Vector3(0.36, drop, 0.32), Vector3(0, -drop * 0.5, 0))
	_Parts.cyl(ram, 0.12, drop * 0.7, Vector3(0, -drop * 0.55, 0), Vector3.ZERO, false, 10)
	# The blade is WIDER than the ram so it reads as a foot rather than the end
	# of a bar, and it is a wedge because a flat pad on soil reads as a stool.
	_Parts.wedge(ram, 0.8, 0.52, 0.36, 0.2, Vector3(0, -drop - 0.08, 0.18),
			Vector3(80.0 * K.DEG, 0, 0))
	_Parts.studs(ram, 3, Vector3(0, -drop * 0.28, -0.18), Vector3(0, -0.24, 0), 0.034)


## A FIELD EMITTER HEAD: post, collar, bead. Small, but it carries the whole
## reason the Bastion exists, so it only ever goes where it stands in clear air
## and breaks the outline. Shared across all four options so they read as one
## frame's variants rather than four different frames.
static func _emitter(to: Node, at: Vector3, h: float) -> void:
	_Parts.cyl(to, 0.085, h, at + Vector3(0, h * 0.5, 0), Vector3.ZERO, false, 8)
	_Parts.ring(to, 0.1, 0.18, at + Vector3(0, h * 0.76, 0))
	_Parts.sphere(to, 0.13, at + Vector3(0, h + 0.1, 0))


## AN ARGUS EYE. A socket laid along -Z, a lens on the end and a bezel round it.
## Aimed by `yaw_deg`/`pitch_deg`, because Argus's eyes do not all look where
## the body points — that is the entire unsettling read.
##
## The bezel is a torus STOOD UP (PI/2 about X) on purpose: it girdles the lens
## axis, which here runs along Z. That is the opposite of the mistake this
## project keeps making with ring(), and it is correct for exactly this reason.
static func _eye_pod(to: Node, at: Vector3, r: float, yaw_deg: float,
		pitch_deg: float) -> void:
	var pod := K.node_at(to, at, Vector3(pitch_deg * K.DEG, yaw_deg * K.DEG, 0))
	_Parts.cyl(pod, r * 0.8, r * 1.2, Vector3(0, 0, -r * 0.45),
			Vector3(PI * 0.5, 0, 0), false, 10)
	_Parts.sphere(pod, r, Vector3(0, 0, -r * 1.05))
	_Parts.ring(pod, r * 0.98, r * 1.28, Vector3(0, 0, -r * 0.95),
			Vector3(PI * 0.5, 0, 0))


## A LEG ON A RADIUS. K.leg's `splay` swings sideways in the PARENT's frame,
## which is right for a hull with legs down its flanks and useless for legs
## spaced round a circle — splay then kicks them tangentially instead of
## outward. So the hip goes inside a yawed node, where outward is +Z, and
## `reach` does the kicking.
static func _radial_leg(to: Node, yaw_deg: float, hip_y: float, radius: float,
		thigh: float, shin: float, out_deg: float, thick: float) -> void:
	var hub := K.node_at(to, Vector3.ZERO, Vector3(0, yaw_deg * K.DEG, 0))
	K.leg(hub, Vector3(0, hip_y, radius), thigh, shin, 0.0, -out_deg, false, thick)


# ─────────────────────────────────────────────
# BROODCARRIER — SWARM, supply 2, hull 200, AERIAL
#
# A flying hive that spawns melee drones until it is killed, and keeps moving —
# so the Nest's counter (walk over and break it) does not apply, and the
# silhouette has to say so. Two things, in this order:
#
#   1. IT FLIES. No legs, no feet, nothing touching the ground, and the mass
#      sits between y 2 and 3 where nothing else in the roster has any.
#   2. IT IS FULL OF THINGS. The brood is shown, not implied: clustered pods,
#      an open underside, at least one pod cracked with a hatchling in it.
#
# All four reject the kit. The Nest is a 2.6 m box with hatches; these are
# lumps, hoops and bunches, because a flying crate reads as cargo.
# ─────────────────────────────────────────────

## A — THE BUNCH. One wide lift hoop overhead with the brood hanging under it
## like fruit. Proposes the simplest readable answer: a ring with a cluster
## slung beneath it, a shape nothing else in the roster has, and an underside
## that is nothing but pods.
## Risks: an even bunch merges into one lump at icon size (sizes and spacing are
## jittered against exactly that), and the two drones already dropping free may
## read as render debris rather than as the frame's behaviour — they are here to
## be judged, and they only appear on this option.
static func brood_a(root_node: Node3D) -> void:
	# THE LIFT IS A HOOP, not a pair of booms. An unbroken ring overhead is the
	# cheapest "this hovers" in the kit and it leaves the whole underside clear,
	# which is the only place the brood can be seen from.
	_Parts.ring(root_node, 1.02, 1.28, Vector3(0, 3.0, 0))
	# Three fans at 14, 139 and 243 degrees. A matched trio on 120s would read
	# as issued hardware; Swarm counts badly on purpose.
	for a_deg in [14.0, 139.0, 243.0]:
		var a: float = float(a_deg) * K.DEG
		K.rotor(root_node, Vector3(sin(a) * 1.15, 2.97, cos(a) * 1.15), 0.72, 3)
	# Struts to the core at angles that match NOTHING above — accretion, not
	# assembly.
	for a_deg in [62.0, 186.0, 300.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.box(root_node, Vector3(0.1, 0.1, 1.15),
				Vector3(sin(a) * 0.58, 2.9, cos(a) * 0.58), Vector3(0, -a, 0))
	# THE CORE IS THREE OVERLAPPING SPHERES, none of them on the axis. A single
	# centred body is a hull, and a hull is what this faction does not have.
	_Parts.sphere(root_node, 0.6, Vector3(0.0, 2.68, 0.0), Vector3(1.25, 0.82, 1.15))
	_Parts.sphere(root_node, 0.42, Vector3(-0.36, 2.54, 0.2))
	_Parts.sphere(root_node, 0.34, Vector3(0.32, 2.58, -0.26))
	# THE BROOD. Nine pods, five sizes, no two gaps equal, and the lowest one
	# cracked open with a hatchling coming out of it.
	var pods: Array = [
		[Vector3(0.0, 2.1, 0.0), 0.44, false],
		[Vector3(-0.52, 2.2, 0.18), 0.33, false],
		[Vector3(0.46, 2.16, -0.22), 0.31, false],
		[Vector3(0.12, 2.26, 0.46), 0.29, false],
		[Vector3(-0.3, 1.86, -0.42), 0.32, false],
		[Vector3(0.38, 1.78, 0.3), 0.29, false],
		[Vector3(0.64, 2.0, -0.02), 0.25, false],
		[Vector3(-0.58, 1.76, 0.36), 0.24, false],
		[Vector3(-0.06, 1.6, 0.02), 0.38, true],
	]
	for p: Array in pods:
		_pod(root_node, p[0], p[1], p[2])
	# Two already away and falling. This is the behaviour drawn rather than
	# described, and the thing to say yes or no to.
	_hatchling(root_node, Vector3(-0.42, 1.44, -0.3), 0.19)
	_hatchling(root_node, Vector3(0.3, 1.1, 0.26), 0.17)


## B — THE BASKET. A lid with lift on it, a ribbed cage hanging off the lid, and
## an open mouth at the bottom with no floor in it. Proposes the literal reading
## of "open underside": you can see through the frame to the brood inside, and
## the hole they come out of is a hole.
## Risks: thin ribs close up into a solid cone at distance, so there are only
## six of them and they are thick. If the render still fills in, the answer is
## fewer ribs, not thinner.
static func brood_b(root_node: Node3D) -> void:
	# The lid: one flat slab carrying everything. Laid flat with the standard
	# PI/2 about X, so its `h` runs along Z.
	_Parts.plate(root_node, 2.1, 2.1, 0.24, 0.42, Vector3(0, 2.98, 0),
			Vector3(PI * 0.5, 0, 0))
	# TWO FANS, DIFFERENT SIZES, ON DIFFERENT ARMS. The big one is outboard to
	# port, the small one aft to starboard — the frame is visibly out of balance
	# and flying anyway, which is more Swarm than any amount of detail.
	_Parts.box(root_node, Vector3(1.1, 0.14, 0.2), Vector3(-1.5, 3.04, -0.1))
	K.rotor(root_node, Vector3(-2.0, 3.06, -0.1), 1.0, 3)
	_Parts.box(root_node, Vector3(0.16, 0.12, 0.8), Vector3(0.95, 2.96, 0.78))
	K.rotor(root_node, Vector3(0.95, 2.98, 1.16), 0.62, 4)
	# THE CAGE. Six ribs from the lid rim down and inward to the mouth ring.
	# Each rib is yawed to its own radius FIRST and leaned INSIDE that frame, so
	# they converge; leaning them in the root's frame would tip all six the same
	# way and three would pass through the brood.
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		var rim := K.node_at(root_node, Vector3(sin(a) * 0.95, 2.9, cos(a) * 0.95),
				Vector3(0, a, 0))
		var hang := K.node_at(rim, Vector3.ZERO, Vector3(30.0 * K.DEG, 0, 0))
		# Alternating lengths, so the cage has a ragged bottom edge rather than
		# a turned one.
		var l: float = 1.3 if i % 2 == 0 else 1.14
		_Parts.box(hang, Vector3(0.13, l, 0.15), Vector3(0, -l * 0.5, 0))
	# THE MOUTH: a ring with nothing in it. The hole is the whole proposal, so
	# it lies flat — ring()'s own orientation — and nothing closes it.
	_Parts.ring(root_node, 0.3, 0.52, Vector3(0, 1.74, 0))
	# Five pods inside the cage, hung off the lid, visible between the ribs.
	var pods: Array = [
		[Vector3(0.0, 2.36, 0.0), 0.42, false],
		[Vector3(-0.44, 2.46, -0.2), 0.3, false],
		[Vector3(0.4, 2.42, 0.26), 0.28, false],
		[Vector3(0.1, 2.14, -0.46), 0.26, false],
		[Vector3(-0.18, 2.02, 0.3), 0.34, true],
	]
	for p: Array in pods:
		_pod(root_node, p[0], p[1], p[2])


## C — THE GRAVID ABDOMEN. A bloated segmented body held nose-down, pods
## barnacled over its skin, and a chute through the belly. Proposes the hive as
## a BODY rather than a machine carrying cargo: the brood is in it, not slung
## under it, and the only engineered-looking part is the chute they leave by.
## Risks: a long horizontal mass reads as an airship. The segment steps, the
## clumped pods and the deliberately mismatched booms are all there to stop
## that; if it still reads as a blimp the answer is to shorten it, not to add
## detail.
static func brood_c(root_node: Node3D) -> void:
	# NOSE DOWN 11 DEGREES. Negative X rotation pitches local -Z toward the
	# ground, so the whole body is built inside this one node and the tilt costs
	# nothing. A level tube is a hull; a tilted one is an animal.
	var seg := K.node_at(root_node, Vector3(0, 2.62, 0.1), Vector3(-11.0 * K.DEG, 0, 0))
	# Three segments, fattest at the back. Wasp order, not aircraft order.
	_Parts.sphere(seg, 0.66, Vector3(0, 0.0, 0.72), Vector3(1.0, 0.92, 1.25))
	_Parts.sphere(seg, 0.58, Vector3(0, -0.02, -0.18), Vector3(1.05, 0.95, 1.1))
	_Parts.sphere(seg, 0.4, Vector3(0, -0.06, -0.92), Vector3(1.0, 0.95, 1.2))
	# Bands between the segments. These rings ARE stood up (PI/2 about X)
	# because this body's axis runs along Z, so a flat torus would be a collar
	# lying across its back. The default orientation is wrong here and this is
	# the one case where rotating it is right.
	for z in [0.34, -0.56]:
		_Parts.ring(seg, 0.52, 0.64, Vector3(0, -0.02, float(z)), Vector3(PI * 0.5, 0, 0))
	# LIFT THAT DOES NOT MATCH ITSELF: a long boom and a big fan outboard to
	# port, a stub and a small fan aft to starboard. Nothing on this frame is a
	# pair.
	_Parts.box(root_node, Vector3(1.4, 0.12, 0.18), Vector3(-1.0, 2.98, -0.1))
	K.rotor(root_node, Vector3(-1.74, 3.0, -0.1), 1.06, 4)
	_Parts.box(root_node, Vector3(0.84, 0.1, 0.14), Vector3(0.72, 2.84, 0.74))
	K.rotor(root_node, Vector3(1.18, 2.86, 0.78), 0.58, 3)
	# THE BROOD, ACCRETED ON THE OUTSIDE. Clumped along the belly and up one
	# flank, because a row would read as a bomb rack.
	var pods: Array = [
		[Vector3(-0.2, 2.02, 0.5), 0.36, false],
		[Vector3(0.16, 1.96, 0.78), 0.32, false],
		[Vector3(-0.44, 2.2, 0.86), 0.28, false],
		[Vector3(0.5, 2.24, 0.44), 0.3, false],
		[Vector3(-0.62, 2.5, 0.3), 0.26, false],
		[Vector3(0.66, 2.56, -0.22), 0.24, false],
		[Vector3(-0.1, 1.88, -0.08), 0.34, true],
		[Vector3(0.28, 2.62, 1.0), 0.22, false],
	]
	for p: Array in pods:
		_pod(root_node, p[0], p[1], p[2])
	# THE CHUTE, hollowed out so it is a hole and not a nipple. The cut is 1.3x
	# the drum's height for the same reason every cut here is: a flush cut
	# leaves a skin across the opening.
	var mouth := _Parts.cyl(root_node, 0.46, 0.52, Vector3(0, 2.0, -0.62),
			Vector3.ZERO, false, 10)
	var bore := _Parts.cyl(mouth, 0.34, 0.68, Vector3.ZERO, Vector3.ZERO, false, 10)
	bore.operation = CSGShape3D.OPERATION_SUBTRACTION
	_hatchling(root_node, Vector3(0.0, 1.62, -0.62), 0.2)


## D — THE HANGING NEST. One big fan on top and the hive hanging under it in
## tiers, with brood tubes pointing straight down out of the bottom. Proposes
## the paper-wasp reading: the thing is a nest first and a vehicle second, and
## the downward tubes make the direction the brood arrives from unambiguous.
## Risks: one big rotor is the most helicopter-like thing on the sheet, and the
## roster already has a helicopter. The nest is kept wider than it is tall and
## the fan deliberately small for its lift so the mass, not the blade, is what
## you see first.
static func brood_d(root_node: Node3D) -> void:
	K.rotor(root_node, Vector3(0, 3.46, 0), 2.5, 4)
	_Parts.cyl(root_node, 0.2, 0.46, Vector3(0, 3.22, 0), Vector3.ZERO, false, 8)
	# THREE DRUMS, EACH NUDGED OFF THE AXIS. A clean turned cone reads as
	# machined; a stack that does not quite line up reads as built up in layers,
	# which is what a nest is.
	var crown := _Parts.cyl(root_node, 1.08, 0.46, Vector3(0, 2.92, 0),
			Vector3.ZERO, false, 10)
	_Parts.ring(root_node, 1.05, 1.19, Vector3(0, 3.1, 0))
	var tiers: Array = [
		[Vector3(0.07, 2.5, -0.05), 0.94, 0.42],
		[Vector3(-0.05, 2.12, 0.06), 0.76, 0.4],
	]
	for t: Array in tiers:
		var at: Vector3 = t[0]
		_Parts.cyl(root_node, t[1], t[2], at, Vector3.ZERO, false, 10)
		_Parts.ring(root_node, float(t[1]) * 0.97, float(t[1]) * 1.1,
				at + Vector3(0, float(t[2]) * 0.4, 0))
	# Vent slots cut into the top drum. Hot, breathing, occupied — and a cut
	# costs nothing where a modelled grille costs twenty boxes. Cut into the
	# drum ITSELF, not into a second copy of it laid over the first: two
	# coincident bodies z-fight, and only one of them would carry the slots.
	for a_deg in [28.0, 150.0, 262.0]:
		var a: float = float(a_deg) * K.DEG
		var slot := _Parts.box(crown, Vector3(0.6, 0.2, 0.5),
				Vector3(sin(a) * 1.0, 0.0, cos(a) * 1.0), Vector3(0, -a, 0))
		slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	# THE BROOD TUBES, pointing down. Seven on a 0.44 radius plus one on the
	# axis — an odd count, uneven lengths, two of them bored out and empty, one
	# with a hatchling in the mouth.
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		var at := Vector3(sin(a) * 0.44, 1.68, cos(a) * 0.44)
		var l: float = 0.68 if i % 3 == 0 else 0.52
		var tube := _Parts.cyl(root_node, 0.16, l, at + Vector3(0, -l * 0.5 + 0.2, 0),
				Vector3.ZERO, false, 8)
		if i == 1 or i == 4:
			var bore := _Parts.cyl(tube, 0.11, l * 1.3, Vector3.ZERO,
					Vector3.ZERO, false, 8)
			bore.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.cyl(root_node, 0.2, 0.8, Vector3(0, 1.5, 0), Vector3.ZERO, false, 8)
	_hatchling(root_node, Vector3(0.44, 1.26, 0.0), 0.2)


# ─────────────────────────────────────────────
# BASTION — STRATCOM, supply 3, hull 300
#
# Walks, then PLANTS: immobile, armoured, projecting a protective field over
# nearby StratCom units. The mirror of the player's Warden, and it is the one
# frame here that should look like it came out of the player's own factory —
# so it is built from concept_kit's hull, head and legs, with more plate, more
# studs and better finish on top.
#
# THE PLANTED STATE IS THE THING TO RECOGNISE, so three of the four are planted
# and one is on the march. Planted means: spades down, skirts to the ground,
# legs locked, emitters up. A frame that has merely stopped reads as broken.
#
# Supply 3, so these are the biggest things on the sheet — Bulwark is
# 2.93 x 3.51 x 2.91 and every option here exceeds it.
# ─────────────────────────────────────────────

## A — THE REDOUBT, PLANTED LOW. It has sat down: legs folded, skirts dropped to
## the soil all round, spades out at the corners, and the field thrown off a
## collar girdling the hull above the deck. Proposes the pillbox reading — low,
## wide, pyramidal, nothing above the turret, obviously not going anywhere.
## Risks: a low wide mass can read as scenery rather than as a unit, the fault
## that killed the Picket tripod. The turret and the collar are what keep it a
## machine; if it still reads as a bunker the collar should go taller.
static func bastion_a(root_node: Node3D) -> void:
	# 3.1 x 2.8 on the deck and 3.7 across the collar. Measured against the
	# Bulwark's 2.93 x 3.51 x 2.91: the first pass of this option came out
	# SHORTER than the Bulwark, which is wrong for a supply-3 frame however
	# squat it is meant to look. It gets its size in footprint, not height.
	K.hull(root_node, Vector3(3.1, 1.6, 2.8), Vector3(0, 1.35, 0))
	# FOLDED, NOT STANDING: short pillar legs splayed hard, thick, with the
	# hull almost on top of them. Digitigrade legs would say "about to run".
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.leg(root_node, Vector3(sx * 1.14, 0.92, sz * 0.86), 0.46, 0.4,
					sx * 26.0, sz * 8.0, false, 1.6)
	# SKIRTS TO THE GROUND. These are what turn a walker into a hardpoint: they
	# occlude the legs, so the frame has no visible gait left. They have to
	# reach from the hull's belly at y 0.55 to the soil, or the daylight under
	# them reads as a vehicle up on blocks.
	for sx in [-1.0, 1.0]:
		_Parts.plate(root_node, 2.6, 1.12, 0.14, 0.14, Vector3(sx * 1.56, 0.57, 0),
				Vector3(0, PI * 0.5, 0))
	_Parts.plate(root_node, 2.9, 1.0, 0.14, 0.14, Vector3(0, 0.52, -1.46))
	_Parts.plate(root_node, 2.9, 0.9, 0.14, 0.14, Vector3(0, 0.48, 1.46))
	_Parts.studs(root_node, 5, Vector3(-0.9, 0.24, -1.54), Vector3(0.45, 0, 0), 0.036)
	# Four spades at the corners, outboard of the skirts so they break the
	# outline instead of hiding behind it.
	_spade(root_node, Vector3(-1.3, 1.0, -1.2), -45.0, 34.0, 0.9)
	_spade(root_node, Vector3(1.3, 1.0, -1.2), 45.0, 34.0, 0.9)
	_spade(root_node, Vector3(-1.3, 1.0, 1.2), -135.0, 34.0, 0.9)
	_spade(root_node, Vector3(1.3, 1.0, 1.2), 135.0, 34.0, 0.9)
	# THE FIELD COLLAR: a 3.7 m hoop on four stanchions off the deck, flat —
	# ring()'s own orientation, and the right one, because the field it stands
	# for lies over the ground. It clears the head by a metre of radius, which
	# is measured, not assumed: the eye sits 0.74 m out from the axis and the
	# collar's inner lip is at 1.6.
	_Parts.ring(root_node, 1.6, 1.84, Vector3(0, 2.3, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_Parts.cyl(root_node, 0.1, 0.36, Vector3(sx * 1.2, 2.12, sz * 1.2),
					Vector3.ZERO, false, 8)
	for a_deg in [45.0, 135.0, 225.0, 315.0]:
		var a: float = float(a_deg) * K.DEG
		_emitter(root_node, Vector3(sin(a) * 1.72, 2.36, cos(a) * 1.72), 0.4)
	K.head(root_node, Vector3(0, 2.17, -0.1), 1.0)


## B — THE PYLON, PLANTED TALL. Legs locked straight, four long outriggers
## hammered into the soil, and the field held overhead on a mast as a canopy.
## Proposes the opposite of A from the same parts: the field is ABOVE the squad
## rather than around the machine, so the silhouette is a parasol over a
## position and reads as cover at any range.
## Risks: height. It out-tops everything on the sheet, which is the objection
## that killed the first Picket umbrella. Here it may be the point — a canopy
## below head height protects nothing — but it is the first thing to cut.
static func bastion_b(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(2.5, 1.3, 2.3), Vector3(0, 2.25, 0))
	# LOCKED STRAIGHT. Pillar legs, barely splayed, thick: columns rather than
	# limbs, which is what a frame that has stopped moving stands on.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.leg(root_node, Vector3(sx * 0.95, 1.75, sz * 0.8), 0.85, 0.8,
					sx * 11.0, sz * 4.0, false, 1.7)
	# Four long outriggers off the belly, at the cardinals so they sit in the
	# gaps between the legs rather than fouling them.
	_spade(root_node, Vector3(0, 1.72, -1.0), 0.0, 40.0, 1.5)
	_spade(root_node, Vector3(0, 1.72, 1.0), 180.0, 40.0, 1.5)
	_spade(root_node, Vector3(-1.1, 1.72, 0), -90.0, 40.0, 1.5)
	_spade(root_node, Vector3(1.1, 1.72, 0), 90.0, 40.0, 1.5)
	# THE MAST AND THE CANOPY. A 2.6 m hoop flat overhead with three stays, and
	# the emitters hanging UNDER it pointing at the ground, which is where the
	# field goes.
	_Parts.cyl(root_node, 0.24, 1.4, Vector3(0, 3.6, 0.1), Vector3.ZERO, false, 10)
	_Parts.ring(root_node, 1.12, 1.32, Vector3(0, 4.26, 0.1))
	for a_deg in [30.0, 150.0, 270.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.box(root_node, Vector3(0.08, 0.08, 1.25),
				Vector3(sin(a) * 0.62, 4.05, cos(a) * 0.62 + 0.1),
				Vector3(28.0 * K.DEG, -a, 0))
		# Emitter beads below the hoop, on the hoop's own radius.
		_Parts.cyl(root_node, 0.075, 0.26,
				Vector3(sin(a) * 1.22, 4.1, cos(a) * 1.22 + 0.1), Vector3.ZERO, false, 8)
		_Parts.sphere(root_node, 0.14, Vector3(sin(a) * 1.22, 3.94, cos(a) * 1.22 + 0.1))
	# Appliqué and bolts on the hull flanks: same vocabulary as the player's
	# veteran kit, which is the point of this faction.
	for sx in [-1.0, 1.0]:
		_Parts.plate(root_node, 1.9, 0.6, 0.1, 0.12, Vector3(sx * 1.26, 2.2, 0),
				Vector3(0, PI * 0.5, 0))
		_Parts.studs(root_node, 4, Vector3(sx * 1.32, 2.44, -0.6), Vector3(0, 0, 0.4), 0.032)
	# HEAD OFF-CENTRE, so the mast owns the middle. The mast is 0.48 across at
	# the axis and the eye lands 0.77 out to port, so nothing crosses it.
	K.head(root_node, Vector3(-0.5, 2.9, -0.3), 0.8)


## C — ON THE MARCH. The only option that is still walking: digitigrade legs,
## hull high, and the whole hardpoint stowed — spades folded up the flanks as
## masts, canopy hoop lying flat on the back deck. Proposes the other half of
## the frame's story, and tells you at a glance what the planted options have
## unpacked.
## Risks: it is a big Walker. The stowed spades standing proud above the deck
## are the only thing keeping the outline distinct, which is why they are
## blade-up rather than tucked.
static func bastion_c(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(2.6, 1.35, 2.9), Vector3(0, 2.5, 0))
	# HIP AT 2.0, WHICH IS MEASURED. A digitigrade leg drops thigh + shin + the
	# foot plate below its hip — 1.97 for these lengths — so the 1.55 this was
	# first written at buried all four feet 0.4 m in the ground, where the
	# render would simply have shown a frame standing in a hole.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			K.leg(root_node, Vector3(sx * 1.0, 2.0, sz * 0.95), 0.9, 1.0,
					sx * 6.0, sz * 7.0, true, 1.3)
	# SPADES STOWED BLADE-UP. Folded flat to the hull they vanish into the
	# silhouette; standing them on end breaks the outline upward, which is the
	# one direction this frame has clear air.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * 1.38, 3.0, sz * 0.9)
			_Parts.box(root_node, Vector3(0.3, 1.5, 0.28), at)
			_Parts.wedge(root_node, 0.74, 0.5, 0.32, 0.2, at + Vector3(0, 0.88, 0.16),
					Vector3(80.0 * K.DEG, 0, 0))
			_Parts.studs(root_node, 3, at + Vector3(0, -0.4, -0.16),
					Vector3(0, 0.3, 0), 0.032)
	# THE CANOPY, PACKED: the hoop lying flat on the back deck with its mast
	# laid fore-and-aft beside it. Flat is correct here for the literal reason —
	# it is stowed on a flat deck.
	_Parts.ring(root_node, 0.78, 0.96, Vector3(0, 3.24, 0.7))
	_Parts.cyl(root_node, 0.2, 1.2, Vector3(0, 3.26, 0.7), Vector3(PI * 0.5, 0, 0), false, 10)
	_emitter(root_node, Vector3(-0.86, 3.2, 0.7), 0.34)
	_emitter(root_node, Vector3(0.86, 3.2, 0.7), 0.34)
	# Appliqué on the flanks and the glacis, bolted. More of it than the player
	# gets, and better finished — that is the whole StratCom tell.
	for sx in [-1.0, 1.0]:
		_Parts.plate(root_node, 2.4, 0.62, 0.11, 0.13, Vector3(sx * 1.32, 2.46, 0),
				Vector3(0, PI * 0.5, 0))
		_Parts.studs(root_node, 5, Vector3(sx * 1.4, 2.7, -0.9), Vector3(0, 0, 0.46), 0.032)
	_Parts.plate(root_node, 2.1, 0.5, 0.12, 0.13, Vector3(0, 2.22, -1.5))
	# One weapon, on the starboard bevel. It defends the position; it is not
	# what the frame is for, so there is only the one.
	K.arm(root_node, Vector3(1.42, 3.0, -0.1), 0.6, 0.6, 74.0, -8.0, 0.0, 1.2, "gun")
	K.head(root_node, Vector3(0, 3.18, -0.2), 0.95)


## D — THE LAAGER. Planted, and the field is given a physical armature: four
## armour panels unfolded off the hull corners, emitters along their top edges,
## a jack screwed through the belly. Proposes the plan-view silhouette as the
## tell — an X of walls where everything else on the sheet is a lump on legs —
## and it is the only option where the protection looks like cover rather than
## like a halo.
## Risks: the panels are big enough to swallow the frame. They are on the
## DIAGONALS for that reason, which leaves the fore-and-aft lanes open so the
## turret, the eye and the gun are all still visible between them.
static func bastion_d(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(2.3, 1.6, 2.2), Vector3(0, 1.5, 0))
	# Two legs, knelt and splayed wide; the belly jack takes the rest. Four legs
	# under the panels would never be seen.
	for sx in [-1.0, 1.0]:
		K.leg(root_node, Vector3(sx * 0.9, 1.0, 0.1), 0.52, 0.46, sx * 30.0, 0.0,
				false, 1.7)
	_Parts.cyl(root_node, 0.22, 0.86, Vector3(0, 0.52, -0.3), Vector3.ZERO, false, 10)
	_Parts.cyl(root_node, 0.52, 0.16, Vector3(0, 0.08, -0.3), Vector3.ZERO, false, 12)
	# FOUR PANELS ON THE DIAGONALS. Yawed to its own corner first, then leaned
	# out INSIDE that frame — the same discipline as the spades, for the same
	# reason: leaned in the root's frame, two of the four would fold inward
	# through the hull.
	for a_deg in [45.0, 135.0, 225.0, 315.0]:
		var hinge := K.node_at(root_node, Vector3(0, 1.1, 0),
				Vector3(0, float(a_deg) * K.DEG, 0))
		# Negative X rotation takes the panel's top outward (local -Z), which is
		# the lean a deployed wall has. Positive would fold it over the hull.
		var panel := K.node_at(hinge, Vector3(0, 0, -1.0), Vector3(-22.0 * K.DEG, 0, 0))
		_Parts.plate(panel, 1.9, 2.1, 0.17, 0.2, Vector3(0, 0.95, 0))
		_Parts.studs(panel, 4, Vector3(-0.66, 0.2, -0.12), Vector3(0.44, 0, 0), 0.036)
		# Emitter heads along the top edge — the panels are the armature, and
		# without these they are just shields.
		for x in [-0.62, 0.0, 0.62]:
			_emitter(panel, Vector3(float(x), 1.98, 0), 0.3)
		# The hinge ram, so the panel reads as DEPLOYED rather than welded on.
		_Parts.cyl(hinge, 0.11, 0.9, Vector3(0, 0.3, -0.52),
				Vector3(52.0 * K.DEG, 0, 0), false, 8)
	K.head(root_node, Vector3(0, 2.32, -0.15), 0.9)


# ─────────────────────────────────────────────
# SEE-ENGINE — ARGUS, supply 3, hull 240
#
# A command intelligence with a body. While it lives, nearby Argus units aim
# better and share contacts; it barely fights. So its threat has to be legible
# WITHOUT A GUN, and the only thing it can be legible as is a thing that is
# watching and coordinating.
#
# NO FACE, in the Walker's sense. The kit's head — turret ring, cut cheeks, one
# offset eye, whip antenna — is the player's and StratCom's, and putting it on
# Argus would make the overlord a cousin. None of these four has a head. They
# have optics, and the optics do not agree about where to look.
#
# Supply 3: the biggest and the most expensive-looking things on the sheet.
# ─────────────────────────────────────────────

## A — THE OCULUS. One enormous eye in a gimbal on a column, on four thin
## overlong legs. Proposes the single-shape answer: a 2.3 m lens is a silhouette
## nothing else in the game can be confused with, and the spindly legs make the
## proportions wrong on purpose — too much eye, not enough machine.
## Risks: an eyeball on a stick can read comic. The gimbal is heavy and the
## pupil is off-centre and low, which is what moves it from cartoon to
## unsettling; if it still reads as a mascot, the pupil should go.
static func argus_a(root_node: Node3D) -> void:
	_Parts.sphere(root_node, 1.15, Vector3(0, 3.0, 0))
	# THE GIMBAL IS TWO HOOPS IN PERPENDICULAR PLANES. The equatorial one lies
	# flat, which is ring()'s own orientation; the yoke IS stood up on purpose,
	# because a gimbal is exactly the case where an upright torus is right.
	_Parts.ring(root_node, 1.18, 1.42, Vector3(0, 3.0, 0))
	_Parts.ring(root_node, 1.22, 1.46, Vector3(0, 3.0, 0), Vector3(PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_Parts.cyl(root_node, 0.16, 0.5, Vector3(sx * 1.3, 3.0, 0),
				Vector3(0, 0, PI * 0.5), false, 8)
	# THE PUPIL, OFF-CENTRE AND LOW. A centred pupil is a face; this one is
	# looking somewhere you are not, which is the whole character of the
	# faction. Nothing is allowed to cross it, so the gimbal hoops pass well
	# outboard and the column stops below it.
	_Parts.sphere(root_node, 0.44, Vector3(0.22, 2.84, -0.98))
	_Parts.ring(root_node, 0.46, 0.62, Vector3(0.22, 2.84, -1.0), Vector3(PI * 0.5, 0, 0))
	# The column: too slender for the mass on top of it.
	_Parts.cyl(root_node, 0.3, 2.0, Vector3(0, 1.05, 0), Vector3.ZERO, false, 10)
	_Parts.ring(root_node, 0.3, 0.46, Vector3(0, 1.9, 0))
	for a_deg in [40.0, 130.0, 220.0, 310.0]:
		_radial_leg(root_node, float(a_deg), 1.8, 0.4, 1.0, 1.0, 30.0, 0.55)
	# Two small eyes on the column looking BACKWARD and DOWN, at its own units.
	# One enormous eye is the proposal; these say what the eye is for.
	_eye_pod(root_node, Vector3(-0.42, 1.5, 0.3), 0.2, 160.0, -24.0)
	_eye_pod(root_node, Vector3(0.38, 1.16, 0.34), 0.17, 205.0, -38.0)


## B — THE CHANDELIER. No hull at all: a spine with three tiers of optics round
## it, fifteen eyes pointing fifteen ways, and a relay hoop on top. Proposes the
## many-eyes answer — the frame has no front, so there is no angle from which it
## is not looking at you, and the tier count reads before any single eye does.
## Risks: fifteen small spheres can turn to texture at distance. Each tier keeps
## one larger eye for that reason, and the tiers step in radius so the outline
## is a stack of discs rather than a fuzzy cone.
static func argus_b(root_node: Node3D) -> void:
	_Parts.cyl(root_node, 0.34, 3.0, Vector3(0, 2.2, 0), Vector3.ZERO, false, 10)
	# Three tiers: 7, 5 and 3 eyes. Odd counts, shrinking radius, each tier
	# pitched a little further down than the one above — the lower tiers watch
	# the ground its own units are standing on.
	var tiers: Array = [
		[1.5, 1.46, 7, 0.2, -14.0],
		[2.34, 1.12, 5, 0.24, -8.0],
		[3.12, 0.8, 3, 0.3, 4.0],
	]
	for t: Array in tiers:
		var y: float = t[0]
		var rad: float = t[1]
		var n: int = t[2]
		var er: float = t[3]
		var pitch: float = t[4]
		_Parts.ring(root_node, rad - 0.14, rad, Vector3(0, y, 0))
		for i in n:
			var a: float = TAU * float(i) / float(n)
			# yaw 180+A points the pod OUTWARD: at yaw 180 its -Z is +Z, which
			# is the radius at A = 0. Yaw -A looks correct and is not — it
			# mirrors the Z component and half the tier stares inward.
			var yaw: float = 180.0 + rad_to_deg(a)
			# One eye per tier is oversized, so the tier has a reading order.
			var r: float = er * (1.5 if i == 0 else 1.0)
			_eye_pod(root_node, Vector3(sin(a) * rad, y, cos(a) * rad), r, yaw, pitch)
	# THE RELAY: a flat hoop and four whips. This is the coordinate half of the
	# frame — the eyes gather, this is what shares.
	_Parts.ring(root_node, 0.46, 0.66, Vector3(0, 3.78, 0))
	for a_deg in [25.0, 115.0, 205.0, 295.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.box(root_node, Vector3(0.04, 0.9, 0.04),
				Vector3(sin(a) * 0.5, 4.1, cos(a) * 0.5))
	# FIVE LEGS. Nothing else in the game stands on an odd number, the stance
	# never looks settled, and that is the cheapest unease available. The hip
	# is at 1.24 because 1.32 of leg kicked out 28 degrees drops 1.17 — at the
	# 1.15 this was first written at, all five pads sat under the ground.
	for i in 5:
		_radial_leg(root_node, 360.0 * float(i) / 5.0, 1.24, 0.42, 0.62, 0.7, 28.0, 0.5)


## C — THE SLAB. A blank monolith whose front face carries nothing but a
## letterbox slot full of lenses, with four booms reaching out around it, each
## ending in an eye pointed somewhere different. Proposes the most hostile
## reading on the sheet: the body does not look at you, its limbs do, and there
## is no part of it you could call a face.
## Risks: a flat slab is a billboard from the side and may vanish in profile.
## The booms are at four different yaws and heights to give it depth from every
## angle; if it still flattens, the slab wants to be a wedge.
static func argus_c(root_node: Node3D) -> void:
	# A drum base on six stubby feet. Six, because four would read as a vehicle
	# and three as a tripod — both of which are things this game already has.
	_Parts.cyl(root_node, 1.45, 0.68, Vector3(0, 0.62, 0), Vector3.ZERO, false, 8)
	_Parts.ring(root_node, 1.42, 1.62, Vector3(0, 0.84, 0))
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		_Parts.cyl(root_node, 0.17, 0.5, Vector3(sin(a) * 1.2, 0.26, cos(a) * 1.2),
				Vector3.ZERO, false, 8)
		_Parts.cyl(root_node, 0.26, 0.1, Vector3(sin(a) * 1.2, 0.05, cos(a) * 1.2),
				Vector3.ZERO, false, 10)
	# THE SLAB, leaning back 8 degrees. Its front face is deliberately EMPTY:
	# every rib, bolt and conduit goes on the back, because a blank wall the
	# height of a house is the unsettling part and anything applied to it would
	# start to read as features.
	var slab := _Parts.plate(root_node, 2.2, 3.0, 0.42, 0.34, Vector3(0, 2.4, 0.1),
			Vector3(8.0 * K.DEG, 0, 0))
	# The letterbox. The cut is 1.3x the slab's depth so it goes clean through
	# instead of leaving a membrane across the slot.
	var slot := _Parts.box(slab, Vector3(1.5, 0.4, 0.56), Vector3(0, 0.5, -0.1))
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	# NINE LENSES IN THE SLOT, which is the only place on the whole frame that
	# looks forward. A row of them in a dark letterbox reads as a compound eye;
	# one big lens there would read as a visor, and a visor is a face.
	for i in 9:
		_Parts.sphere(slab, 0.13, Vector3(-0.6 + float(i) * 0.15, 0.5, -0.24))
	for i in 4:
		_Parts.box(slab, Vector3(1.9, 0.14, 0.2), Vector3(0, -1.1 + float(i) * 0.6, 0.3))
	_Parts.studs(slab, 5, Vector3(-0.8, -1.3, 0.42), Vector3(0.4, 0, 0), 0.04)
	# FOUR BOOMS, NO TWO ALIKE. Each is yawed to its own bearing and the boom is
	# built inside that frame, so its lift and bend stay in its own plane —
	# hanging a bend off the root's X axis after a yaw is what sends an arm
	# sideways into the slab.
	var booms: Array = [
		[-52.0, 1.9, 1.3, 1.0, 18.0, -34.0, 0.3, -12.0],
		[64.0, 2.6, 1.6, 1.2, 8.0, -46.0, 0.26, 20.0],
		[148.0, 1.2, 1.1, 0.9, 26.0, -28.0, 0.22, -40.0],
		[-142.0, 2.2, 0.9, 1.1, 14.0, -52.0, 0.2, 35.0],
	]
	for b: Array in booms:
		var hub := K.node_at(root_node, Vector3.ZERO, Vector3(0, float(b[0]) * K.DEG, 0))
		var wrist := K.boom(hub, Vector3(0, float(b[1]), -0.9), float(b[2]),
				float(b[3]), float(b[4]), float(b[5]))
		_eye_pod(wrist, Vector3.ZERO, float(b[6]), float(b[7]), -18.0)


## D — THE CANOPY. A mass that is heaviest at the top, balanced on one column,
## with the underside crowded with eyes staring down and a halo above it.
## Proposes the overlord reading literally: the frame is a roof over its own
## units, every optic looks DOWN at them, and the proportions are wrong in a way
## no soldier's machine would be — it does not look like it could take a step.
## Risks: an inverted cone on a post can read as a lamp or a tree. The eye grid
## breaking the lower rim and the halo above are what keep it machine; if it
## still reads as furniture, the three outriggers want to be legs.
static func argus_d(root_node: Node3D) -> void:
	# One column, and three outriggers too slight to be holding anything up.
	_Parts.cyl(root_node, 0.42, 1.5, Vector3(0, 0.8, 0), Vector3.ZERO, false, 10)
	_Parts.cyl(root_node, 0.9, 0.2, Vector3(0, 0.12, 0), Vector3.ZERO, false, 12)
	for a_deg in [20.0, 140.0, 260.0]:
		var a: float = float(a_deg) * K.DEG
		var out := K.node_at(root_node, Vector3(0, 1.3, 0), Vector3(0, a, 0))
		_Parts.box(out, Vector3(0.1, 0.1, 1.5), Vector3(0, -0.52, 0.72),
				Vector3(-42.0 * K.DEG, 0, 0))
		_Parts.cyl(out, 0.16, 0.08, Vector3(0, 0.03, 1.28), Vector3.ZERO, false, 8)
	# THE MASS, INVERTED. A cone rotated PI about X puts its apex at the bottom
	# where the column ends and its 3.5 m base at the top — top-heavy by
	# construction, which no amount of detail elsewhere would achieve.
	_Parts.cyl(root_node, 1.75, 1.35, Vector3(0, 2.22, 0), Vector3(PI, 0, 0), true, 10)
	_Parts.cyl(root_node, 1.75, 0.5, Vector3(0, 3.14, 0), Vector3.ZERO, false, 10)
	_Parts.ring(root_node, 1.72, 1.94, Vector3(0, 2.9, 0))
	# THE EYE GRID, STARING DOWN. Eleven, in two uneven rings, pitched between
	# 58 and 80 degrees below horizontal — negative pitch looks down. They hang
	# under the rim, where they break the lower outline; inboard of it they
	# would be invisible from any angle a player sees this from.
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		_eye_pod(root_node, Vector3(sin(a) * 1.4, 2.08, cos(a) * 1.4), 0.22,
				180.0 + rad_to_deg(a), -58.0)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		_eye_pod(root_node, Vector3(sin(a) * 0.76, 1.84, cos(a) * 0.76), 0.16,
				180.0 + rad_to_deg(a), -80.0)
	_Parts.studs(root_node, 6, Vector3(-0.7, 1.72, -0.5), Vector3(0.28, 0, 0), 0.05)
	# THE HALO: a flat hoop floating over the cap on three thin masts. The
	# coordinate half of the frame, and the one part of it pointed at the sky
	# rather than at the ground.
	for a_deg in [0.0, 120.0, 240.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.cyl(root_node, 0.05, 0.6, Vector3(sin(a) * 0.9, 3.66, cos(a) * 0.9),
				Vector3.ZERO, false, 6)
	_Parts.ring(root_node, 0.95, 1.14, Vector3(0, 3.96, 0))
	_Parts.sphere(root_node, 0.2, Vector3(0, 3.96, 0))
