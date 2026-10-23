extends RefCounted
class_name ConceptsA

# ─────────────────────────────────────────────
# CONCEPT BUILDERS — LANCE, SAPPER, KITE. Four options each.
#
# Pure geometry. Each builder takes a Node3D and hangs CSG children off it;
# nothing here renders, measures or touches the tree. The renderer is another
# process and it is the only thing that knows about cameras.
#
# EVERYTHING COMES OUT OF concept_kit.gd, which is the Walker's own geometry.
# That is the point: a new frame has to look ISSUED by this factory, not found
# in another game. The family tells are the chamfered hull with its sloped
# glacis and cut tail, the turret ring, ONE eye offset to the left, and the whip
# antenna. Where a frame cannot have a kit part (the Lance has no turret, so it
# cannot have K.head) the eye and the antenna are built by hand instead, because
# those two carry the resemblance on their own and the ring is what says
# "turret".
#
# TWO CONVENTIONS THIS FILE HOLDS TO, both stated so a reader does not have to
# infer them from the numbers:
#
#   GROUND IS y = 0. Wheels, pads and feet are placed so they touch zero, and
#   the Kite's body sits at y 1.5–2.5 with nothing under it, which is what makes
#   it read as hovering rather than as a frame missing its legs.
#
#   SIGNS. Godot faces -Z and a POSITIVE rotation about X takes +Y to +Z. So:
#     a -Z barrel pitched by a NEGATIVE X angle points DOWN-and-forward
#     a -Z barrel pitched by a POSITIVE X angle points UP-and-forward
#     a torso leaning FORWARD is a NEGATIVE X angle (its top goes to -Z)
#     a cone's apex is +Y, so a muzzle cone wants euler (-PI*0.5, 0, 0) to put
#     its point forward, and the one at the back of a recoilless venturi wants
#     the opposite sign on purpose
#   This is the error that has cost this project the most renders: a gun placed
#   on a limb's local -Z after the limb was already rotated ends up aimed at the
#   sky. Where a weapon hangs off an arm below, the pitch is explicitly undone
#   first, the same way K.tower_shield undoes the forearm droop.
#
# TWO KIT PARTS ARE VEHICLE-SCALE AND MUST NOT GO ON THE SAPPER. K.arm's "gun"
# hand ends in a 1.4 m barrel and its "claw" in 0.5 m jaws — both fixed lengths
# that `thick` does not touch. On a 1.8 m frame they are absurd, so every Sapper
# arm takes hand = "none" and carries kit built to infantry scale by hand.
#
# K.leg's digitigrade foot is 0.86 m long and `thick` does not scale that
# either. On a soldier-sized frame that is a flipper, so the Sappers stand on
# the pillar leg's round pad instead.
# ─────────────────────────────────────────────

const K := preload("res://tools/concept_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")


# ─────────────────────────────────────────────
# LANCE — supply 1, hull 110. The cheapest vehicle in the game.
#
# Fast, fixed forward gun, NO TURRET: it points its whole body to shoot and
# dies to anything that gets a bead on it. The silhouette has to say "fast and
# disposable" before it says anything else, and it must not be read as a Rover
# (4 wheels, closed hull, a proper turret on a ring, 1.7 x 0.75 x 2.4).
#
# So every option below gives up the turret ring, gives up two or more wheels,
# and leaves the frame OPEN. The Rover is a box; these are a chassis with things
# bolted to it. Most are longer than the Rover over the muzzle and a fraction of
# its mass, which is the trade being proposed: the gun is the expensive part and
# the vehicle under it is the cheap part.
# ─────────────────────────────────────────────

## LANCE A — TRIKE. Two big driven wheels on an exposed cross axle, one small
## wheel dragging behind, and the gun lying in the nose between the front
## wheels. Three contact points is a plan nothing else in the roster has, and it
## is the cheapest chassis that can still be steered by pointing it.
##
## RISK: a trike can read as a trailer or as scenery rather than as a unit. The
## eye on its stalk and the aerial are doing the work of saying "this is one of
## ours and it is crewed".
static func lance_a(root_node: Node3D) -> void:
	# A SPINE, NOT A HULL. 0.62 wide, so the chamfered box reads as a beam with
	# equipment hung off it rather than as an armoured body.
	K.hull(root_node, Vector3(0.62, 0.44, 1.40), Vector3(0, 0.74, 0))
	# Front axle, left exposed across the nose — the single clearest "no armour
	# here" signal available, and it breaks the outline at both ends.
	_Parts.cyl(root_node, 0.055, 1.30, Vector3(0, 0.44, -0.55), Vector3(0, 0, PI * 0.5))
	for s: float in [-1.0, 1.0]:
		K.wheel(root_node, Vector3(s * 0.66, 0.44, -0.55), 0.44, 0.26)
		# Drop link from the spine to the axle, canted so it reads as suspension.
		_Parts.box(root_node, Vector3(0.09, 0.42, 0.12),
				Vector3(s * 0.40, 0.58, -0.55), Vector3(0, 0, s * 26.0 * K.DEG))
	# Swing arm and the dragging wheel. Small and offset in size, not position:
	# a trike with three equal wheels reads as a tricycle toy.
	_Parts.box(root_node, Vector3(0.14, 0.14, 0.80), Vector3(0, 0.50, 0.58),
			Vector3(14.0 * K.DEG, 0, 0))
	K.wheel(root_node, Vector3(0, 0.26, 0.88), 0.26, 0.20)
	# THE GUN IS THE NOSE. Bolted into a cradle on the spine's front face, on the
	# centreline, with a muzzle brake — the cone's apex is +Y, so -PI*0.5 about X
	# is what puts its point forward instead of back at the driver.
	_Parts.plate(root_node, 0.34, 0.30, 0.42, 0.07, Vector3(0, 0.80, -0.68))
	_Parts.cyl(root_node, 0.085, 1.00, Vector3(0, 0.80, -1.05), Vector3(PI * 0.5, 0, 0))
	_Parts.cyl(root_node, 0.12, 0.20, Vector3(0, 0.80, -1.56),
			Vector3(-PI * 0.5, 0, 0), true, 10)
	# Ready rounds in an open rack on the starboard flank, standing off the spine
	# so they are in the outline. Flush against it they would be invisible.
	# Seated ON the flank at x 0.26, not at 0.31: a plate turned about Y extrudes
	# its depth along +X, so the inboard edge is where it is placed and the given
	# x is the face that touches the spine, not the centre of the slab.
	_Parts.plate(root_node, 0.46, 0.26, 0.18, 0.06, Vector3(0.26, 0.80, 0.18),
			Vector3(0, PI * 0.5, 0))
	_Parts.studs(root_node, 3, Vector3(0.44, 0.92, -0.02), Vector3(0, 0, 0.20), 0.03)
	# NO TURRET RING, so the family read is the eye and the whip. The eye is on a
	# stalk off to port, clear of the gun and clear of the rack.
	_Parts.cyl(root_node, 0.045, 0.28, Vector3(-0.26, 1.06, -0.26))
	_Parts.sphere(root_node, K.W_EYE_R * 0.78, Vector3(-0.26, 1.26, -0.30),
			Vector3(1, 0.82, 1))
	_Parts.box(root_node, Vector3(0.03, 0.90, 0.03), Vector3(0.26, 1.30, 0.56))


## LANCE B — CHARIOT. One axle, two oversized wheels, the body slung between
## them and a long beak out front with the guns slung under it. The proposition
## is pure speed: two wheels and a dragging skid is the least vehicle that can
## still carry a gun, and the wheels being nearly as tall as the body is what
## says "this is all drivetrain".
##
## RISK: a two-wheeler can read as unstable or comic, and without a long nose it
## has no obvious front. The beak is therefore oversized on purpose.
static func lance_b(root_node: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		K.wheel(root_node, Vector3(s * 0.70, 0.56, 0), 0.56, 0.30)
	_Parts.cyl(root_node, 0.07, 1.36, Vector3(0, 0.56, 0), Vector3(0, 0, PI * 0.5))
	# Body slung between and above the axle line, small enough that the wheels
	# win the silhouette.
	K.hull(root_node, Vector3(0.90, 0.52, 1.00), Vector3(0, 0.88, -0.05))
	# THE BEAK. A chamfered slab turned a quarter turn so its 0.95 m length runs
	# fore-and-aft: rotating a plate about Y puts its width along Z and extrudes
	# its depth along X, hence the x offset that re-centres it.
	_Parts.plate(root_node, 0.95, 0.40, 0.38, 0.11, Vector3(-0.19, 0.74, -0.70),
			Vector3(0, PI * 0.5, 0))
	# Twin barrels UNDER the beak, where they hang in clear air. A single tube on
	# the centreline disappeared into the nose; two below it read as a gun.
	for s: float in [-1.0, 1.0]:
		_Parts.cyl(root_node, 0.065, 0.85, Vector3(s * 0.13, 0.54, -1.18),
				Vector3(PI * 0.5, 0, 0))
	_Parts.plate(root_node, 0.40, 0.20, 0.16, 0.05, Vector3(0, 0.54, -0.82))
	# Tail skid: the bar's +Z end has to drop, which is a POSITIVE X angle.
	_Parts.box(root_node, Vector3(0.14, 0.14, 0.90), Vector3(0, 0.62, 0.72),
			Vector3(22.0 * K.DEG, 0, 0))
	K.wheel(root_node, Vector3(0, 0.18, 1.08), 0.18, 0.16)
	# Eye on the beak root, to port and standing proud of it.
	_Parts.cyl(root_node, 0.045, 0.24, Vector3(-0.28, 1.06, -0.34))
	_Parts.sphere(root_node, K.W_EYE_R * 0.8, Vector3(-0.28, 1.24, -0.38),
			Vector3(1, 0.82, 1))
	_Parts.box(root_node, Vector3(0.03, 1.00, 0.03), Vector3(0.30, 1.34, 0.42))


## LANCE C — RECOILLESS. There is no vehicle: there is a gun, and a cradle on
## two wheels under it. The barrel is the longest thing in the silhouette and
## the breech venturi is the second. This is the option that argues the Lance's
## supply cost is spent on the weapon and nothing else — it reads disposable
## because there is visibly nothing to lose.
##
## RISK: it can read as a towed artillery piece rather than a unit. The nose
## castor and the drive can on the starboard flank are what make it self
## propelled; without them it is a trail waiting for a tractor.
static func lance_c(root_node: Node3D) -> void:
	# THE BARREL IS THE CHASSIS. Everything else is clamped to it.
	_Parts.cyl(root_node, 0.135, 2.20, Vector3(0, 0.88, -0.40), Vector3(PI * 0.5, 0, 0))
	_Parts.box(root_node, Vector3(0.34, 0.34, 0.44), Vector3(0, 0.88, 0.58))
	# The venturi flares to the REAR, so its apex points forward — the opposite
	# sign to the muzzle brake, and the only cone on the frame that is not
	# pointing where the gun points. Back blast is the whole reason this weapon
	# is cheap, so it should be visible.
	_Parts.cyl(root_node, 0.21, 0.42, Vector3(0, 0.88, 0.92),
			Vector3(-PI * 0.5, 0, 0), true, 12)
	_Parts.cyl(root_node, 0.11, 0.18, Vector3(0, 0.88, -1.58),
			Vector3(-PI * 0.5, 0, 0), true, 10)
	# Cradle: two canted legs down to the axle, and nothing else. An A-frame
	# rather than a hull is the point.
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.10, 0.62, 0.14), Vector3(s * 0.30, 0.58, 0.30),
				Vector3(0, 0, s * 22.0 * K.DEG))
		K.wheel(root_node, Vector3(s * 0.52, 0.34, 0.30), 0.34, 0.24)
	_Parts.cyl(root_node, 0.05, 1.04, Vector3(0, 0.34, 0.30), Vector3(0, 0, PI * 0.5))
	# Nose castor on a fork, so it stands on three points instead of resting its
	# muzzle on the ground.
	_Parts.box(root_node, Vector3(0.10, 0.52, 0.10), Vector3(0, 0.52, -0.92))
	K.wheel(root_node, Vector3(0, 0.22, -0.92), 0.22, 0.18)
	# Drive can to starboard, eye to port: the asymmetry is free here and it
	# stops the frame reading as a symmetrical ordnance drawing.
	_Parts.cyl(root_node, 0.17, 0.46, Vector3(0.40, 0.58, 0.44), Vector3(0, 0, PI * 0.5), false, 10)
	_Parts.ring(root_node, 0.17, 0.23, Vector3(0.40, 0.58, 0.44), Vector3(0, 0, PI * 0.5))
	# A breech shield with the barrel through it — the one plate on the frame,
	# and it is where a crew would actually need one.
	_Parts.plate(root_node, 0.62, 0.52, 0.06, 0.10, Vector3(0, 0.96, 0.22))
	# The eye stands on the shield, which is the only structure wide enough to
	# carry it. On a stalk out at x -0.34 it had nothing under it at all — the
	# barrel is only 0.27 across and everything else on this frame is below the
	# gun line.
	_Parts.cyl(root_node, 0.045, 0.26, Vector3(-0.22, 1.28, 0.25))
	_Parts.sphere(root_node, K.W_EYE_R * 0.8, Vector3(-0.22, 1.50, 0.21),
			Vector3(1, 0.82, 1))
	_Parts.box(root_node, Vector3(0.03, 0.90, 0.03), Vector3(0.36, 1.26, 0.30))


## LANCE D — TECHNICAL. An open flatbed on four small wheels, a one-seat cab
## shoved over to port, and a gun clamped to a beam over the nose on two visible
## struts. The silhouette argues the frame was not built for this: it is a cart
## with a weapon strapped to it, which is exactly what supply 1 should look like.
##
## RISK: four wheels is the one thing that invites the Rover comparison. The
## wheels are deliberately small, the deck is open, the cab is off-centre and
## there is no ring anywhere — four separate denials of the Rover's read.
static func lance_d(root_node: Node3D) -> void:
	K.wheels(root_node, 0.58, 0.66, 0.30, 0.30)
	# Exposed chassis rails. Daylight between the rails and the deck is what
	# makes this read as a frame rather than as a hull.
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.09, 0.12, 1.90), Vector3(s * 0.50, 0.44, 0))
	# Flat deck: a plate turned a quarter turn about X lies in the XZ plane with
	# its thickness going down, which is how this project lays every deck.
	_Parts.plate(root_node, 1.10, 1.70, 0.09, 0.12, Vector3(0, 0.56, 0),
			Vector3(PI * 0.5, 0, 0))
	# Cab to PORT, one seat wide, with a vision slot cut through it. The cutter
	# runs well past both faces — a subtraction the same size as the hole leaves
	# a sliver of wall behind.
	var cab := _Parts.box(root_node, Vector3(0.50, 0.54, 0.56), Vector3(-0.28, 0.84, -0.50))
	var slot := _Parts.box(cab, Vector3(0.44, 0.13, 0.90), Vector3(0, 0.08, -0.30))
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	# The eye sits INSIDE the slot and nothing else goes near it.
	_Parts.sphere(root_node, K.W_EYE_R * 0.7, Vector3(-0.38, 0.92, -0.76),
			Vector3(1, 0.82, 1))
	# THE GUN, ON TOP OF THE NOSE BEAM. Standing a hand above the deck on two
	# struts, so it is in the outline from every angle; laid in the deck it would
	# have been a pipe on a tray.
	_Parts.box(root_node, Vector3(0.26, 0.16, 0.34), Vector3(0, 1.02, -0.52))
	_Parts.cyl(root_node, 0.075, 1.40, Vector3(0, 1.02, -1.00), Vector3(PI * 0.5, 0, 0))
	_Parts.cyl(root_node, 0.10, 0.18, Vector3(0, 1.02, -1.78), Vector3(-PI * 0.5, 0, 0), true, 10)
	for z: float in [-0.30, -0.70]:
		_Parts.box(root_node, Vector3(0.08, 0.44, 0.08), Vector3(0, 0.78, z))
	# Roll bar over the open bed. No roof is the whole reading of a technical.
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.07, 0.62, 0.07), Vector3(s * 0.46, 0.88, 0.46))
	_Parts.box(root_node, Vector3(1.06, 0.07, 0.07), Vector3(0, 1.18, 0.46))
	# Load on the bed: two crates and a spare wheel stood on edge, all of it
	# above the deck line where it breaks the outline.
	for s: float in [-1.0, 1.0]:
		_Parts.plate(root_node, 0.30, 0.24, 0.26, 0.05, Vector3(s * 0.30, 0.66, 0.18))
	K.wheel(root_node, Vector3(0.30, 0.84, 0.76), 0.28, 0.10)
	# The whip roots in the deck, not in mid-air above it.
	_Parts.box(root_node, Vector3(0.03, 0.95, 0.03), Vector3(-0.46, 1.02, 0.70))


# ─────────────────────────────────────────────
# SAPPER — supply 1, hull 55. INFANTRY, not a vehicle.
#
# Same size class as a soldier: about 1.8 m to the crown, a whip antenna over
# that. It carries a light weapon AND lays mines, and it has to be separable at
# a glance from the Mechanic, which is a 2 m capsule with TWO UPRIGHT TANKS on
# its back and a welder on its mount. So nothing below puts a pair of vertical
# cylinders on a Sapper's back, and every option makes its equipment a shape the
# Mechanic does not have.
#
# MINES ARE FLAT DISCS WITH A RING ROUND THEM, about 0.26 m across. That shape
# is new to the roster, it reads at icon size, and it is what ties these four
# together as one frame rather than four engineers.
#
# THE LIGHT WEAPON IS THE HEAD'S OWN STUB on the options whose hands are full.
# K.head ships with a short barrel on its mantlet; on a frame holding a spool
# crank or a two-handed tool that stub is the carbine, and inventing a second
# gun would have made every one of these look over-armed for 55 hull.
# ─────────────────────────────────────────────

## SAPPER A — SPOOL. A wire drum across its back, wider than its own shoulders,
## paying a line down to a plough shoe dragging on the ground behind it. The
## proposition is that this frame leaves something BEHIND it: the silhouette has
## a trail, which no other robot in the game does.
##
## RISK: the line to the ground can read as a tail or as a snagged cable. It is
## kept thin and straight, and the shoe at its end is a shaped plate rather than
## a lump, so it reads as deployed kit rather than as damage.
static func sapper_a(root_node: Node3D) -> void:
	# Pillar legs with round pads. The kit's digitigrade foot is 0.86 m long
	# whatever `thick` says, which on a 1.8 m frame is a flipper.
	for s: float in [-1.0, 1.0]:
		K.leg(root_node, Vector3(s * 0.20, 0.95, 0), 0.42, 0.40, s * 4.0, 0.0, false, 0.62)
	# THE HUNCH. Leaning forward puts the torso's top toward -Z, which is a
	# NEGATIVE angle about X. Everything bolted to the back rides this lean,
	# which is what makes the load look heavy instead of parked.
	var spine := K.node_at(root_node, Vector3(0, 1.08, 0.02), Vector3(-17.0 * K.DEG, 0, 0))
	K.hull(spine, Vector3(0.54, 0.60, 0.40), Vector3.ZERO)
	# Head on the spine, so it looks down the lean at the ground it is working —
	# the gaze is the cheapest way to say "this one is doing something here".
	K.head(spine, Vector3(0, 0.40, -0.05), 0.42)
	# THE DRUM. 0.64 across against a 0.54 torso, so it is in the outline from
	# the front as well as in profile. Its flanges are tori whose axis has been
	# turned to X on purpose: a flange on an X-axis drum faces sideways, which is
	# the one case where standing a ring up is correct.
	_Parts.cyl(spine, 0.30, 0.64, Vector3(0, 0.02, 0.36), Vector3(0, 0, PI * 0.5), false, 14)
	for s: float in [-1.0, 1.0]:
		_Parts.ring(spine, 0.26, 0.34, Vector3(s * 0.32, 0.02, 0.36), Vector3(0, 0, PI * 0.5))
	# Crank handle, offset, so the drum reads as something that is wound.
	_Parts.cyl(spine, 0.03, 0.18, Vector3(0.40, 0.16, 0.36), Vector3(0, 0, PI * 0.5))
	# The line and the shoe, both in ROOT space: the wire pays out to the world,
	# so it must not inherit the torso's lean.
	_Parts.cyl(root_node, 0.022, 1.22, Vector3(0, 0.57, 0.72), Vector3(28.0 * K.DEG, 0, 0))
	_Parts.plate(root_node, 0.26, 0.34, 0.07, 0.05, Vector3(0, 0.08, 1.04),
			Vector3(PI * 0.5, 0, 0))
	_Parts.wedge(root_node, 0.26, 0.20, 0.06, 0.08, Vector3(0, 0.08, 1.22),
			Vector3(PI * 0.5, 0, 0))
	# Satchels outboard of the hips. THE EULER TAKES THE SIDE'S SIGN: a plate
	# extrudes along its own +Z, which a fixed quarter turn about Y sends to +X —
	# so the same call that stands a pouch off the starboard flank buries the
	# port one inside the body. Mirroring the rotation extrudes both outboard.
	for s: float in [-1.0, 1.0]:
		_Parts.plate(root_node, 0.28, 0.24, 0.18, 0.06, Vector3(s * 0.27, 0.92, 0.02),
				Vector3(0, s * PI * 0.5, 0))
		_Parts.studs(root_node, 2, Vector3(s * 0.47, 0.99, -0.06), Vector3(0, -0.14, 0), 0.022)
	# Three mines stacked on the starboard satchel.
	for i: int in 3:
		var y: float = 1.06 + float(i) * 0.07
		_Parts.cyl(root_node, 0.12, 0.05, Vector3(0.46, y, 0.02))
		_Parts.ring(root_node, 0.12, 0.15, Vector3(0.46, y, 0.02))
	# One hand on the crank, one hanging. hand = "none" everywhere on this frame:
	# K.arm's gun hand is a 1.4 m barrel, which is vehicle scale.
	K.arm(spine, Vector3(0.32, 0.24, -0.02), 0.28, 0.26, 54.0, 8.0, 18.0, 0.60, "none")
	K.arm(spine, Vector3(-0.32, 0.24, -0.02), 0.28, 0.26, 26.0, -6.0, 6.0, 0.60, "tool")


## SAPPER B — PLANTER. Both hands on a long T-handled tool driven into the
## ground in front of it, with a bandolier of mine discs across the small of its
## back. The proposition is the ACTION: a two-handed pole angled into the deck is
## a pose nothing else in the roster holds, so the frame is legible even when
## the equipment on it is not.
##
## RISK: at distance the shaft can read as a rifle or a spear. The wide shoe at
## the bottom and the cross handle at the top are what stop that, and both are
## oversized for the job for exactly that reason.
static func sapper_b(root_node: Node3D) -> void:
	# Braced stance: positive `reach` swings a limb forward, so the right leg is
	# planted ahead and the left is back. It is leaning on the tool.
	K.leg(root_node, Vector3(0.20, 0.98, 0), 0.44, 0.42, 3.0, 12.0, false, 0.62)
	K.leg(root_node, Vector3(-0.20, 0.98, 0), 0.44, 0.42, -3.0, -10.0, false, 0.62)
	# Only a slight hunch: this one is driving something down, not carrying.
	var spine := K.node_at(root_node, Vector3(0, 1.12, 0.00), Vector3(-10.0 * K.DEG, 0, 0))
	K.hull(spine, Vector3(0.52, 0.62, 0.38), Vector3.ZERO)
	K.head(spine, Vector3(0, 0.40, -0.05), 0.42)
	# THE TOOL IS BUILT IN ROOT SPACE and the hands are brought to it. The other
	# way round — hanging a 1.1 m shaft off a wrist that already carries the
	# arm's droop — is how this project has aimed things at the sky before.
	_Parts.cyl(root_node, 0.035, 1.12, Vector3(0, 0.575, -0.59), Vector3(13.0 * K.DEG, 0, 0))
	_Parts.cyl(root_node, 0.028, 0.34, Vector3(0, 1.10, -0.47), Vector3(0, 0, PI * 0.5))
	# Shoe and spade edge, flat on the ground and wide enough to read as a tool
	# for burying something rather than as the end of a stick.
	_Parts.plate(root_node, 0.32, 0.28, 0.06, 0.05, Vector3(0, 0.07, -0.72),
			Vector3(PI * 0.5, 0, 0))
	_Parts.wedge(root_node, 0.32, 0.18, 0.05, 0.07, Vector3(0, 0.07, -0.88),
			Vector3(PI * 0.5, 0, 0))
	# Both arms forward and down onto the shaft. Grip collars at the two hand
	# heights bridge whatever the arm angles leave over — a hand floating two
	# centimetres off a shaft is the "loose parts" note this project keeps
	# getting back from renders.
	K.arm(spine, Vector3(0.30, 0.22, -0.04), 0.26, 0.26, 44.0, 6.0, 26.0, 0.58, "none")
	K.arm(spine, Vector3(-0.30, 0.22, -0.04), 0.26, 0.26, 20.0, -6.0, 40.0, 0.58, "none")
	for h: Array in [[0.95, -0.55], [0.74, -0.60]]:
		_Parts.cyl(root_node, 0.07, 0.12, Vector3(0, h[0], h[1]), Vector3(13.0 * K.DEG, 0, 0))
	# THE BANDOLIER: four mines on edge across the small of the back. On edge
	# rather than stacked flat, so the disc shape is visible in profile.
	for i: int in 4:
		var x: float = -0.21 + float(i) * 0.14
		_Parts.cyl(spine, 0.11, 0.045, Vector3(x, -0.10, 0.26), Vector3(0, 0, PI * 0.5))
		_Parts.ring(spine, 0.11, 0.14, Vector3(x, -0.10, 0.26), Vector3(0, 0, PI * 0.5))
	# One satchel, port side, to keep the back from being only mines.
	_Parts.plate(root_node, 0.26, 0.22, 0.18, 0.06, Vector3(-0.40, 0.95, 0.14),
			Vector3(0, PI * 0.5, 0))


## SAPPER C — MULE. An external pack frame standing above its own head with
## mines clipped up the rails, hunched hard under the weight, a short carbine in
## one hand. The proposition is LOAD: this is the frame that brings the mines,
## and the silhouette is infantry carrying more than it should.
##
## RISK: a frame standing above the head is close to the Arbiter's mast array.
## It is kept a flat ladder with discs on it and no dish, no ring and no
## antennae, which is the whole difference between carrying and sensing.
static func sapper_c(root_node: Node3D) -> void:
	# Wide and planted. Heavier legs than the other three, because it is the
	# option whose argument is weight.
	for s: float in [-1.0, 1.0]:
		K.leg(root_node, Vector3(s * 0.22, 0.92, 0), 0.40, 0.38, s * 9.0, 0.0, false, 0.70)
	# The hardest lean of the four: 26 degrees forward, which is what a carrier
	# does to get the load over its feet.
	var spine := K.node_at(root_node, Vector3(0, 1.04, 0.04), Vector3(-26.0 * K.DEG, 0, 0))
	K.hull(spine, Vector3(0.58, 0.58, 0.44), Vector3.ZERO)
	K.head(spine, Vector3(0, 0.38, -0.06), 0.44)
	# THE PACK FRAME, on the spine so it rides the lean. Two rails and three
	# rungs: a ladder, not a box, so the load on it is seen THROUGH the frame.
	# z 0.24, against a torso 0.44 deep: the rails have to touch its back face at
	# 0.22. At 0.30 the whole pack hung five centimetres clear of the robot.
	for s: float in [-1.0, 1.0]:
		_Parts.box(spine, Vector3(0.05, 1.10, 0.05), Vector3(s * 0.22, 0.32, 0.24))
	for i: int in 3:
		_Parts.box(spine, Vector3(0.44, 0.045, 0.045), Vector3(0, -0.14 + float(i) * 0.46, 0.24))
	# Mines clipped up the rails, on edge. Four of them, climbing, which is what
	# makes the pack read as cargo rather than as structure.
	for i: int in 4:
		var y: float = -0.06 + float(i) * 0.26
		_Parts.cyl(spine, 0.12, 0.05, Vector3(0, y, 0.36), Vector3(0, 0, PI * 0.5))
		_Parts.ring(spine, 0.12, 0.15, Vector3(0, y, 0.36), Vector3(0, 0, PI * 0.5))
	# Rolled mat lashed across the top of the frame, breaking the outline above
	# the head — the one piece that is wider than everything under it.
	_Parts.cyl(spine, 0.11, 0.62, Vector3(0, 0.86, 0.26), Vector3(0, 0, PI * 0.5), false, 10)
	_Parts.studs(spine, 2, Vector3(-0.22, 0.62, 0.20), Vector3(0.44, 0, 0), 0.024)
	# A SHORT CARBINE, HAND BUILT. The wrist already carries the arm's pitch
	# (fore + droop), so the pitch is undone on the mount before the weapon goes
	# on; built straight onto the wrist's -Z it would point at the sky.
	var wrist := K.arm(spine, Vector3(0.32, 0.22, -0.04), 0.26, 0.24, 58.0, 10.0, 14.0, 0.62, "none")
	var hold := K.node_at(wrist, Vector3(0, -0.06, 0), Vector3(-72.0 * K.DEG, 0, 0))
	# The receiver STRADDLES the hand — a plate extrudes along its own +Z, so
	# placed at the wrist it would have grown out behind the grip and left the
	# barrel floating a hand's width in front of nothing.
	_Parts.plate(hold, 0.09, 0.13, 0.40, 0.03, Vector3(0, 0, -0.26))
	_Parts.cyl(hold, 0.022, 0.34, Vector3(0, 0.01, -0.42), Vector3(PI * 0.5, 0, 0))
	K.arm(spine, Vector3(-0.32, 0.22, -0.04), 0.26, 0.24, 34.0, -8.0, 10.0, 0.62, "none")
	# Satchel on the free hip.
	_Parts.plate(root_node, 0.28, 0.24, 0.18, 0.06, Vector3(-0.40, 0.90, 0.00),
			Vector3(0, PI * 0.5, 0))


## SAPPER D — BOOM. One ordinary arm with a carbine; the other is not an arm at
## all but a heavy articulated boom that reaches out and down to set a mine on
## the ground, with a belt of discs round the waist feeding it. The proposition
## is the asymmetry: ONE SIDE IS EQUIPMENT, which is readable at any size and
## says "engineer" without needing the mines to be legible at all.
##
## RISK: an arm-mounted boom is the closest of the four to the Mechanic's welder
## arm. The clamp holds a visible mine disc and the waist belt carries four more,
## so the payload is what the eye lands on rather than the arm.
static func sapper_d(root_node: Node3D) -> void:
	# Crouched and splayed: it is working at ground level, and the low stance is
	# what separates this from a frame that happens to have a tool.
	for s: float in [-1.0, 1.0]:
		K.leg(root_node, Vector3(s * 0.21, 0.80, 0), 0.34, 0.33, s * 14.0, 0.0, false, 0.64)
	var spine := K.node_at(root_node, Vector3(0, 0.92, 0.02), Vector3(-20.0 * K.DEG, 0, 0))
	K.hull(spine, Vector3(0.56, 0.54, 0.42), Vector3.ZERO)
	K.head(spine, Vector3(0, 0.36, -0.06), 0.42)
	# THE BOOM, in root space. A negative `lift` sends its segments down and
	# forward, because they run along -Z and a negative X angle drops -Z.
	var tip := K.boom(root_node, Vector3(-0.34, 1.00, -0.08), 0.44, 0.38, -34.0, -30.0)
	# The tip inherits 64 degrees of pitch, so the clamp and its mine are levelled
	# back out — the same counter-rotation K.tower_shield uses on the forearm.
	var jaw := K.node_at(tip, Vector3(0, 0, -0.04), Vector3(64.0 * K.DEG, 0, 0))
	for s: float in [-1.0, 1.0]:
		_Parts.wedge(jaw, 0.16, 0.14, 0.05, 0.05, Vector3(s * 0.10, -0.02, 0),
				Vector3(0, 0, s * 20.0 * K.DEG))
	_Parts.cyl(jaw, 0.12, 0.05, Vector3(0, -0.12, 0))
	_Parts.ring(jaw, 0.12, 0.15, Vector3(0, -0.12, 0))
	# THE BELT. A flat torus round the waist — rings already lie flat and
	# standing this one up would arch it over the frame's shoulder.
	_Parts.ring(root_node, 0.23, 0.29, Vector3(0, 0.98, 0.02))
	# Four reloads on the belt's starboard arc, on edge so the disc reads. At
	# radius 0.34 against a 0.28 waist they stand proud of the body; sat on the
	# belt itself they were flush with it and gone from the outline.
	for i: int in 4:
		var a: float = -0.5 + float(i) * 0.34
		_Parts.cyl(root_node, 0.10, 0.045,
				Vector3(0.34 * cos(a), 0.98, 0.34 * sin(a)), Vector3(0, -a, PI * 0.5))
	# The good arm, with the carbine pitch-corrected the same way as SAPPER C.
	var wrist := K.arm(spine, Vector3(0.32, 0.20, -0.04), 0.26, 0.24, 52.0, 8.0, 20.0, 0.60, "none")
	var hold := K.node_at(wrist, Vector3(0, -0.06, 0), Vector3(-72.0 * K.DEG, 0, 0))
	_Parts.plate(hold, 0.09, 0.13, 0.38, 0.03, Vector3(0, 0, -0.25))
	_Parts.cyl(hold, 0.022, 0.32, Vector3(0, 0.01, -0.40), Vector3(PI * 0.5, 0, 0))
	# Detonator case high on the port shoulder, standing clear of the boom's hub.
	# Mirrored quarter turn, so the case extrudes OUTBOARD off the port shoulder
	# instead of burying itself in a torso only 0.56 wide.
	_Parts.plate(spine, 0.20, 0.18, 0.14, 0.05, Vector3(-0.27, 0.18, 0.22),
			Vector3(0, -PI * 0.5, 0))


# ─────────────────────────────────────────────
# KITE — supply 2, hull 90. AERIAL and ARMED.
#
# The first flying thing the player owns that shoots, and it is made of paper.
# Its proposition is ATTACK ANGLE: it fires from where ground frames cannot
# reach, so on every option the LIFT IS HIGH AND THE GUN IS LOW, and the gun is
# canted down rather than held level.
#
# IT MUST NOT BE EITHER DRONE WE ALREADY HAVE. The Spotter is a 0.8 m four-rotor
# X-frame with a camera, and the enemy bomber is a four-rotor quadcopter. So no
# option below is a four-rotor X: one has a single main rotor and a tail, one a
# single shrouded fan, one wings and vectored nozzles, one a coaxial pair. Each
# is about 2.5–3 m across the lift, which is three times the Spotter.
#
# DRAWN AIRBORNE. Bodies sit at y 1.5–2.5 with nothing underneath — no legs, and
# no skids either, because landing gear argues that it lands.
# ─────────────────────────────────────────────

## KITE A — GUNSHIP. One large main rotor on a mast, a tail boom with a sideways
## rotor on the fin, and the turret hung under the chin. The reading is a
## gunship and it is the most immediate of the four: one disc plus one boom is
## not a quadcopter from any angle, and a chin turret is the single most legible
## "armed aircraft" shape there is.
##
## RISK: it is also the most conventional, and the rotor disc is large enough to
## dominate the silhouette and flatten everything under it.
static func kite_a(root_node: Node3D) -> void:
	K.hull(root_node, Vector3(0.80, 0.64, 1.90), Vector3(0, 2.00, -0.10))
	# Mast and gearbox, then the disc. Three blades rather than four: four reads
	# back toward the quadcopters even on a single hub.
	_Parts.box(root_node, Vector3(0.30, 0.20, 0.34), Vector3(0, 2.32, -0.05))
	_Parts.cyl(root_node, 0.09, 0.40, Vector3(0, 2.52, -0.05))
	K.rotor(root_node, Vector3(0, 2.68, -0.05), 1.30, 3)
	# Tail boom, overlapping the hull so it reads as grown out of it rather than
	# parked behind it, with a fin and a sideways rotor on the end. That torus is
	# deliberately turned: its axis goes to X, which is a disc facing sideways —
	# the one orientation a tail rotor can have.
	_Parts.box(root_node, Vector3(0.14, 0.14, 1.30), Vector3(0, 2.04, 1.34))
	# x -0.025 because the slab's depth grows along +X from where it is placed;
	# at x 0 the fin sits a sliver off the boom's centreline.
	_Parts.plate(root_node, 0.44, 0.58, 0.05, 0.09, Vector3(-0.025, 2.28, 1.88),
			Vector3(0, PI * 0.5, 0))
	_Parts.ring(root_node, 0.20, 0.30, Vector3(0.09, 2.28, 1.86), Vector3(0, 0, PI * 0.5))
	_Parts.cyl(root_node, 0.07, 0.12, Vector3(0.11, 2.28, 1.86), Vector3(0, 0, PI * 0.5))
	# THE CHIN TURRET. Hung below the nose, where the hull's glacis cut has
	# already taken the belly away, so it fills a gap instead of sitting on a
	# flat. Its eye ends up forward of the nose with nothing in front of it.
	K.head(root_node, Vector3(0, 1.52, -0.86), 0.55)
	# Stub wings with a pod under each: the second statement of ARMED, and the
	# only thing on the frame that is wider than the fuselage at belly height.
	for s: float in [-1.0, 1.0]:
		_Parts.box(root_node, Vector3(0.56, 0.08, 0.46), Vector3(s * 0.62, 1.86, 0.02))
		_Parts.cyl(root_node, 0.13, 0.58, Vector3(s * 0.62, 1.70, -0.10), Vector3(PI * 0.5, 0, 0))
		_Parts.cyl(root_node, 0.13, 0.16, Vector3(s * 0.62, 1.70, -0.47),
				Vector3(-PI * 0.5, 0, 0), true, 10)


## KITE B — DUCT. One big shrouded fan with the body slung beneath it and the
## turret on a canted gimbal below that. The duct is a 2.5 m hoop seen from any
## angle and the roster has no other shape like it, so this is the option that
## is identifiable at the longest range.
##
## RISK: seen exactly side on, a hoop collapses to a bar. The duct is given a
## fat section and crossed stator bars so there is something inside the circle
## when the circle itself is edge-on.
static func kite_b(root_node: Node3D) -> void:
	# THE DUCT. A torus already lies flat; rotating it would stand it up as an
	# arch, which is the mistake this project has made more than once.
	_Parts.ring(root_node, 0.88, 1.26, Vector3(0, 2.20, 0))
	K.rotor(root_node, Vector3(0, 2.20, 0), 0.84, 4)
	# Stator bars across the duct, carrying the body. They are also what keeps
	# the ring from being empty when it is edge-on.
	for a: float in [45.0, 135.0]:
		_Parts.box(root_node, Vector3(2.14, 0.06, 0.09), Vector3(0, 2.06, 0),
				Vector3(0, a * K.DEG, 0))
	# Body slung UNDER the lift. Lift above, gun below: that stack is the whole
	# argument of the frame.
	K.hull(root_node, Vector3(0.74, 0.52, 1.20), Vector3(0, 1.86, -0.06))
	_Parts.plate(root_node, 0.42, 0.30, 0.20, 0.06, Vector3(0.34, 1.86, 0.10),
			Vector3(0, PI * 0.5, 0))
	_Parts.studs(root_node, 3, Vector3(0.52, 1.96, -0.04), Vector3(0, 0, 0.16), 0.026)
	# THE TURRET, ON A GIMBAL CANTED DOWN. The whole head goes under a node
	# pitched -22 about X, so ring, gun, eye and antenna all tip together: a
	# negative angle drops a -Z barrel, and the eye then looks where the gun
	# looks instead of out over the top of it.
	var mount := K.node_at(root_node, Vector3(0, 1.50, -0.18), Vector3(-22.0 * K.DEG, 0, 0))
	K.head(mount, Vector3.ZERO, 0.58)


## KITE C — JUMP JET. Wings, two nozzles blowing straight down, a belly turret
## between them, and the whole frame nosed over as if it were flying. No rotor at
## all: the proposition is that it has SPEED as well as angle — it arrives,
## hovers long enough to shoot into the back of a position, and leaves.
##
## RISK: with no visible rotor, a still image has to work harder to say
## "flying". The downward bells, the absence of any gear and the nose-down
## attitude are carrying that between them, and if it still reads as a parked
## aeroplane the option has failed.
static func kite_c(root_node: Node3D) -> void:
	# ONE TILT NODE AT THE BODY'S CENTRE, and everything local to it. Tilting
	# about the world origin instead would have swung the whole frame forward by
	# a quarter of a metre as a side effect.
	var air := K.node_at(root_node, Vector3(0, 2.00, 0), Vector3(-7.0 * K.DEG, 0, 0))
	K.hull(air, Vector3(0.72, 0.58, 2.10), Vector3.ZERO)
	# Wing: one chamfered slab laid flat, 2.7 m across, with a fin standing at
	# each tip so the plan has corners rather than being a lozenge.
	_Parts.plate(air, 2.70, 1.00, 0.09, 0.16, Vector3(0, -0.02, 0.10), Vector3(PI * 0.5, 0, 0))
	for s: float in [-1.0, 1.0]:
		_Parts.plate(air, 0.42, 0.36, 0.06, 0.07, Vector3(s * 1.30, 0.16, 0.20),
				Vector3(0, PI * 0.5, 0))
		# NOZZLES BLOWING DOWN. The can's axis is already Y; the bell under it is
		# a cone turned a half turn about X so its point is at -Y. A cone left
		# alone points its apex up, which would read as an intake.
		_Parts.cyl(air, 0.19, 0.52, Vector3(s * 0.58, -0.26, 0.20), Vector3.ZERO, false, 10)
		_Parts.ring(air, 0.19, 0.25, Vector3(s * 0.58, -0.02, 0.20))
		_Parts.cyl(air, 0.19, 0.24, Vector3(s * 0.58, -0.62, 0.20), Vector3(PI, 0, 0), true, 10)
		# Underwing launcher, outboard of the nozzle.
		_Parts.cyl(air, 0.09, 0.68, Vector3(s * 0.98, -0.16, -0.12), Vector3(PI * 0.5, 0, 0))
	# Dorsal intake lip, flat on the spine where a ring belongs flat.
	_Parts.ring(air, 0.16, 0.26, Vector3(0, 0.30, 0.34))
	# BELLY TURRET, between the nozzles and canted down.
	var mount := K.node_at(air, Vector3(0, -0.34, -0.62), Vector3(-18.0 * K.DEG, 0, 0))
	K.head(mount, Vector3.ZERO, 0.52)


## KITE D — SKYHOOK. A coaxial pair of rotors on one mast, a small body under
## them, and the entire weapon in a pod slung well below on a thin pylon, canted
## down. The silhouette is a lift disc, a gap, and a gun: it states the frame's
## job — shooting down into cover — as a diagram rather than as a detail.
##
## RISK: a pod hanging under an aircraft is what the enemy quadcopter bomber's
## load looks like. The pod therefore carries a turret ring, an eye and a
## muzzle brake, so it is unmistakably a gun and not something about to be
## dropped.
static func kite_d(root_node: Node3D) -> void:
	# COAXIAL, NOT A QUAD. Two discs on one mast, the lower one turned 60 degrees
	# so its blades sit between the upper's — from above that is six blades on
	# one hub, which no quadcopter can look like.
	_Parts.cyl(root_node, 0.10, 0.60, Vector3(0, 2.48, 0))
	K.rotor(root_node, Vector3(0, 2.72, 0), 1.10, 3)
	K.rotor(K.node_at(root_node, Vector3(0, 2.46, 0), Vector3(0, 60.0 * K.DEG, 0)),
			Vector3.ZERO, 1.10, 3)
	K.hull(root_node, Vector3(0.70, 0.46, 0.90), Vector3(0, 2.12, 0))
	_Parts.plate(root_node, 0.48, 0.42, 0.05, 0.08, Vector3(-0.025, 2.18, 0.64),
			Vector3(0, PI * 0.5, 0))
	# THE PYLON, thin and short, with daylight either side of it. The gap is the
	# silhouette break: a pod faired into the body would read as a fat fuselage.
	_Parts.box(root_node, Vector3(0.12, 0.46, 0.14), Vector3(0, 1.78, -0.04))
	# THE POD, canted down 24 degrees. Everything in it inherits that, which is
	# the intent: the gun, its eye and its ring all look where it shoots.
	var pod := K.node_at(root_node, Vector3(0, 1.52, -0.08), Vector3(-24.0 * K.DEG, 0, 0))
	var turret := K.head(pod, Vector3(0, -0.12, 0), 0.60)
	# Muzzle brake on the end of the head's own barrel, built in the TURRET's
	# frame so it follows the gun rather than the world. x -0.12 is where that
	# barrel is: the kit offsets it 0.2 before scaling.
	_Parts.cyl(turret, 0.09, 0.18, Vector3(-0.12, 0.01, -1.28), Vector3(-PI * 0.5, 0, 0), true, 10)
	# Ammo drum on the pod's flank, across the airflow, so the pod has a mass to
	# it and reads as fed from above.
	_Parts.cyl(pod, 0.14, 0.34, Vector3(0.22, -0.02, 0.18), Vector3(0, 0, PI * 0.5), false, 10)
	_Parts.ring(pod, 0.14, 0.19, Vector3(0.22, -0.02, 0.18), Vector3(0, 0, PI * 0.5))
