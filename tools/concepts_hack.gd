extends RefCounted
class_name ConceptsHack

# ─────────────────────────────────────────────
# THE HACK DRONE AND ITS PAYLOAD — CONCEPT PASS
#
# Five answers to one problem: a flying machine lifts a large piece of hardware,
# flies to a compute core, and PUTS IT ON TOP. The structure stays and does
# something to the core; the drone is only the delivery.
#
# Each concept is three builders — the thing in flight, the structure alone once
# placed, and the structure seated on a real compute core — plus nothing else.
# Nothing here renders; tools/shoot_hack.gd stages and shoots them.
#
# THE CORE IS MEASURED, NOT IMAGINED. Everything below is read off
# maps/blocks/compute/compute_core*.map at FuncGodot's 32 units per metre, and
# three facts out of that drive every one of these designs:
#
#   1. THE TOP IS A SQUARE COLUMN, and it is 1.25 m across on the small core,
#      1.875 on the medium and 3.00 on the large. That is a 2.4x range. A clamp
#      sized to one of them is wrong on the other two, so every concept here
#      has to say how it spans that, and "scale the prop" is not an answer
#      because it is meant to be ONE object.
#   2. THE TOP IS NOT FLAT. The cap is cut off at about 30 degrees, rising
#      toward the FRONT (-Z): on the medium core the back lip is y 5.56 and the
#      front lip y 6.59. Anything with a flat underside lands on one edge and
#      rocks. Four of the five answer this with visible feet, jacks or shims;
#      the fifth hangs off the posts instead and never touches the cap.
#   3. TWO CORNER POSTS STAND PROUD AT THE FRONT, 0.07 m above the cap apex and
#      about 1.1 m out from the axis on the medium core. They are the only
#      square, level pair on the whole top, which is why one concept grips them
#      and ignores the cap entirely.
#
# CAPS below is [half-width of the top column, y of the LOW back lip, y of the
# HIGH front lip, y of the two front corner posts, half-width of the PLINTH].
#
# ONLY THE FIFTEEN `<name>_flight` / `<name>_placed` / `<name>_seated` FUNCTIONS
# ARE BUILDERS. Everything with a leading underscore is a shared part and takes
# more than a root node.
# ─────────────────────────────────────────────

const K := preload("res://tools/concept_kit.gd")
const _Parts := preload("res://tools/mockup_parts.gd")

const CORE_SMALL := preload("res://maps/blocks/compute/compute_core_small.tscn")
const CORE_MED := preload("res://maps/blocks/compute/compute_core.tscn")
const CORE_LARGE := preload("res://maps/blocks/compute/compute_core_large.tscn")

const CAPS := {
	"small": [0.625, 2.97, 3.81, 3.88, 0.9375],
	"medium": [0.9375, 5.56, 6.59, 6.66, 1.6875],
	"large": [1.50, 10.22, 12.00, 12.06, 2.59375],
}


## THE REAL CORE, INSTANCED — not a stand-in.
##
## It is one baked ArrayMesh under a StaticBody3D, it costs one load, and the
## icon studio already photographs it (that is how the reference sheet for this
## pass was made). A rebuilt stand-in would be a second set of numbers to keep
## honest, and the whole point of the seated renders is to show the fit against
## the thing that actually ships. The collision body comes along and is ignored:
## the studio only collects MeshInstance3D and root CSG.
static func _core(to: Node, which: String) -> Array:
	var packed: PackedScene = CORE_MED
	match which:
		"small":
			packed = CORE_SMALL
		"large":
			packed = CORE_LARGE
	to.add_child(packed.instantiate())
	return CAPS[which]


## The mid-height of the sloped cap: where a level structure's feet average out.
static func _seat(cap: Array) -> float:
	return (float(cap[1]) + float(cap[2])) * 0.5


## A BARE LIFT FAN WITH A DUCT. K.rotor is the blades and hub; this adds the
## ring, because an unducted disc at icon size is three sticks and a dot, and
## every flying thing in this game that reads at range reads because of a hoop.
static func _fan(to: Node, at: Vector3, r: float, blades: int = 3) -> void:
	K.rotor(to, at, r * 2.0, blades)
	_Parts.ring(to, r * 0.96, r * 1.1, at)


## A SCREW JACK: leg, thread, swivel pad. This is the part that answers the
## 30-degree cap on every concept that has a flat underside, so it is shared and
## it is always long enough to be seen — a foot that disappears under the body
## has not made the argument.
static func _jack(to: Node, at: Vector3, drop: float) -> void:
	_Parts.box(to, Vector3(0.17, drop * 0.55, 0.17), at + Vector3(0, -drop * 0.28, 0))
	_Parts.cyl(to, 0.085, drop * 0.6, at + Vector3(0, -drop * 0.68, 0), Vector3.ZERO, false, 8)
	for i in 3:
		_Parts.ring(to, 0.085, 0.14, at + Vector3(0, -drop * (0.5 + float(i) * 0.14), 0))
	_Parts.cyl(to, 0.24, 0.1, at + Vector3(0, -drop + 0.04, 0), Vector3.ZERO, false, 10)


## AN ARGUS LENS POD, borrowed from concepts_c._eye_pod and shortened: this pass
## uses them as instrument heads bolted along a rib rather than as a frame's
## optics, so the socket is a collar instead of a barrel.
static func _lens(to: Node, at: Vector3, r: float, euler: Vector3 = Vector3.ZERO) -> void:
	var pod := K.node_at(to, at, euler)
	_Parts.cyl(pod, r * 0.9, r * 0.7, Vector3(0, 0, -r * 0.3), Vector3(PI * 0.5, 0, 0), false, 10)
	_Parts.sphere(pod, r, Vector3(0, 0, -r * 0.75))
	_Parts.ring(pod, r * 0.96, r * 1.24, Vector3(0, 0, -r * 0.7), Vector3(PI * 0.5, 0, 0))


# ─────────────────────────────────────────────
# A — TICK      Swarm · CLAMPS · the drone becomes the structure
#
# The dissent. The brief asks for something that reads as one object in flight
# and two afterwards; this one argues that the expensive half of that problem —
# making a separation legible — can be deleted by never separating. It arrives
# as a lump under three mismatched fans, drives four barbed legs down the cap's
# flanks, bites, and then STOPS BEING A DRONE: rotors cant down dead against the
# body and become a ragged crown.
#
# The size range is answered by the legs. They are two-segment limbs on yawed
# hubs, so the same four reach a 1.25 m cap and a 3.00 m one by changing one
# angle, which is the only mechanism on the sheet that genuinely scales.
# ─────────────────────────────────────────────

## THE DRUM. Three overlapping spheres, none of them on the axis, with a band
## round the biggest and a drill snout underneath. Swarm: nothing centred,
## nothing matched, and the only machined-looking part is the bit that bites.
static func _tick_drum(to: Node, at: Vector3) -> void:
	_Parts.sphere(to, 0.86, at, Vector3(1.0, 0.64, 1.06))
	_Parts.ring(to, 0.8, 0.99, at + Vector3(0, 0.07, 0))
	_Parts.sphere(to, 0.48, at + Vector3(-0.44, 0.12, 0.32), Vector3(1.0, 0.82, 1.0))
	_Parts.sphere(to, 0.34, at + Vector3(0.48, 0.04, -0.26))
	# THE SNOUT: a collar, a tapered bit and a lock ring. This is the whole
	# "hacking" read — a thing that is driven INTO the cabinet rather than parked
	# on it — so it is the one part with square shoulders on it.
	_Parts.cyl(to, 0.23, 0.44, at + Vector3(0.05, -0.5, -0.04), Vector3.ZERO, false, 8)
	_Parts.ring(to, 0.23, 0.33, at + Vector3(0.05, -0.62, -0.04))
	_Parts.cyl(to, 0.14, 0.78, at + Vector3(0.05, -1.04, -0.04), Vector3.ZERO, true, 8)


## ONE BARBED LEG. Yawed to its own bearing first and swung INSIDE that frame,
## which is the discipline concepts_c._spade's docstring was written for: swing
## them in the root's frame and all four lean the same way, so two drive into
## the body instead of away from it.
static func _tick_leg(to: Node, at: Vector3, yaw_deg: float, out_deg: float,
		knee_deg: float, upper: float, lower: float) -> void:
	var hub := K.node_at(to, at, Vector3(0, yaw_deg * K.DEG, 0))
	# The shoulder stands off the drum's rim rather than on the axis, so the
	# limbs start where a limb would and the four of them do not all pile into
	# the middle of the body.
	var limb := K.node_at(hub, Vector3(0, 0, -0.62), Vector3(out_deg * K.DEG, 0, 0))
	_Parts.sphere(limb, 0.17, Vector3.ZERO)
	_Parts.box(limb, Vector3(0.21, 0.21, upper), Vector3(0, 0, -upper * 0.5))
	var knee := K.node_at(limb, Vector3(0, 0, -upper), Vector3(knee_deg * K.DEG, 0, 0))
	_Parts.sphere(knee, 0.14, Vector3.ZERO)
	_Parts.box(knee, Vector3(0.16, 0.16, lower), Vector3(0, 0, -lower * 0.5))
	# The barb, pointing DOWN out of the ankle. A claw drawn along the limb reads
	# as a longer limb; across it, it reads as a grip.
	_Parts.cyl(knee, 0.12, 0.42, Vector3(0, -0.12, -lower - 0.04),
			Vector3(72.0 * K.DEG, 0, 0), true, 6)


## The four legs, at bearings that are deliberately not on 90s.
static func _tick_legs(to: Node, out_deg: float, knee_deg: float) -> void:
	var bearings: Array = [34.0, 128.0, 212.0, 303.0]
	for i in bearings.size():
		# Uneven lengths, because a matched set of four would be issued hardware.
		var upper: float = 1.16 if i % 2 == 0 else 1.0
		_tick_leg(to, Vector3(0, -0.14, 0), float(bearings[i]), out_deg, knee_deg,
				upper, 1.26)


## The three lift fans, on booms of three different lengths. `droop` swings each
## boom down from the hub and the disc tilts with it, which is what turns a
## flying machine into a dead crown without redrawing it — a disc cocked on a
## level boom photographed as a paddle held up, which was the first attempt.
static func _tick_fans(to: Node, y: float, droop: float) -> void:
	var fans: Array = [[18.0, 1.18, 0.74], [147.0, 0.98, 0.6], [265.0, 1.3, 0.66]]
	for f: Array in fans:
		var a: float = float(f[0]) * K.DEG
		var reach: float = f[1]
		var hub := K.node_at(to, Vector3(0, y, 0), Vector3(0, a, 0))
		var arm := K.node_at(hub, Vector3.ZERO, Vector3(droop * K.DEG, 0, 0))
		_Parts.box(arm, Vector3(0.12, 0.12, reach), Vector3(0, 0, -reach * 0.5))
		_fan(arm, Vector3(0, 0.06, -reach), float(f[2]), 3)


static func tick_flight(root_node: Node3D) -> void:
	# The hub the fans hang off, slung over the drum on three short struts. A
	# lump on a lump: the carrier is not a vehicle, it is more tick.
	_Parts.sphere(root_node, 0.46, Vector3(0.06, 1.46, -0.04), Vector3(1.15, 0.78, 1.1))
	for a_deg in [52.0, 176.0, 291.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.box(root_node, Vector3(0.11, 0.86, 0.11),
				Vector3(sin(a) * 0.4, 1.02, cos(a) * 0.4), Vector3(0, -a, 10.0 * K.DEG))
	_tick_fans(root_node, 1.5, 0.0)
	_tick_drum(root_node, Vector3.ZERO)
	# LEGS FOLDED. Swung up and then broken hard back at the knee, so each limb
	# is a Z tucked against the drum rather than four spikes radiating off it —
	# which is what the first pass drew and what it photographed as.
	_tick_legs(root_node, 46.0, -148.0)


static func tick_placed(root_node: Node3D) -> void:
	# Built with the barb tips at y 0, so the whole thing drops onto a cap by one
	# translation. The drum centre lands 2.0 up: the legs reach 1.82 out from the
	# axis, which clears the LARGE core's 1.50 half-cap, and fold in to grip the
	# small core's 0.625 on the same hinge.
	var body := K.node_at(root_node, Vector3(0, 2.0, 0), Vector3.ZERO)
	_tick_drum(body, Vector3.ZERO)
	_tick_legs(body, -22.0, -62.0)
	# The fans, dead and drooped. They are kept because they are two thirds of
	# the in-flight read and throwing them away would leave a lump nobody could
	# connect to the thing that flew in.
	_Parts.sphere(body, 0.44, Vector3(0.06, 0.72, -0.04), Vector3(1.15, 0.78, 1.1))
	_tick_fans(body, 0.76, -48.0)


static func tick_seated(root_node: Node3D, which: String) -> void:
	var cap: Array = _core(root_node, which)
	# Straddling: the barbs land BELOW the cap's low lip, down the flanks, which
	# is what gripping means and what sitting the body on the apex would not show.
	var at := K.node_at(root_node, Vector3(0, float(cap[1]) - 0.55, 0), Vector3.ZERO)
	tick_placed(at)


# ─────────────────────────────────────────────
# B — PITON     Home Command · DROPS · the drone flies home
#
# The ordnance answer, and the smallest thing on the sheet. No clamp, no
# unfolding, no mechanism at all except mass: a chamfered bolt carried nose-down
# in a four-point rack under a tidy issued quad, released over the cap, and
# driven in by its own fall. Four sprung shoes snap out against the slope and
# that is the installation finished.
#
# The drone is a VEHICLE and it leaves. That is the whole threat difference from
# the Diver: a Diver you can trade one kill for, and this one comes back.
#
# Built out of the player's own vocabulary — _Parts.plate's chamfers, stud rows,
# a blade antenna — because Home Command is the faction that uses it, and
# because the delivery of a standard store from a standard rack is exactly the
# institutional reading.
# ─────────────────────────────────────────────

## THE STORE, nose at local y 0 and everything above it. `deployed` splays the
## four shoes out flat the way they land AND runs the mast up; carried, the
## shoes lie along the body and the mast is a 0.3 m stub.
##
## THE MAST HAS TO TELESCOPE, and finding that out was the point of drawing the
## carry. The store hangs NOSE-DOWN, which puts its mast at the top — straight
## through the carrier's belly. Either the mast stows or the store hangs
## nose-up, and a nose-up store cannot be driven in by its own fall, which is
## the entire concept. So it stows.
static func _piton(to: Node, deployed: bool) -> void:
	# NOSE: a long cone and a hardened tip. It is 0.9 m of the 2.6 and it is what
	# makes a flat-ended canister read as a thing that goes IN.
	_Parts.cyl(to, 0.2, 0.86, Vector3(0, 0.43, 0), Vector3(PI, 0, 0), true, 10)
	_Parts.ring(to, 0.2, 0.3, Vector3(0, 0.84, 0))
	# BODY: a chamfered square block with a bolted band. Square, because every
	# round thing on this sheet belongs to the other two factions.
	_Parts.plate(to, 0.72, 0.72, 0.78, 0.16, Vector3(0, 1.26, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.studs(to, 4, Vector3(-0.27, 1.62, -0.38), Vector3(0.18, 0, 0), 0.034)
	_Parts.plate(to, 0.56, 0.56, 0.2, 0.1, Vector3(0, 1.76, 0), Vector3(PI * 0.5, 0, 0))
	# THE MAST AND THE VANE. Without these the planted store is a 1.1 m stub on a
	# 12 m core and invisible; the vane is a flat blade because a dish here would
	# read as the Nest's and this is not a building.
	_Parts.ring(to, 0.08, 0.17, Vector3(0, 2.02, 0))
	if deployed:
		_Parts.cyl(to, 0.075, 1.3, Vector3(0, 2.45, 0), Vector3.ZERO, false, 8)
		# THE VANE IS THE WHOLE LONG-RANGE READ, so it is 1.1 m of blade and a
		# cross bar rather than the 0.78 flag the first pass drew — on the 12.4 m
		# core a planted store is forty pixels tall and the blade is the only
		# part of it with any width at all.
		_Parts.plate(to, 0.3, 1.1, 0.06, 0.1, Vector3(0, 2.72, 0.05), Vector3(0, 12.0 * K.DEG, 0))
		_Parts.plate(to, 0.62, 0.22, 0.06, 0.05, Vector3(0, 3.12, 0))
		_Parts.cyl(to, 0.05, 0.3, Vector3(0, 3.35, 0), Vector3.ZERO, false, 6)
	else:
		_Parts.cyl(to, 0.11, 0.3, Vector3(0, 2.02, 0), Vector3.ZERO, false, 8)
	# THE FOUR SHOES. Hinged on the band, yawed to their own corner and swung
	# inside that frame; this is the only moving part on the store, which is the
	# point of a payload placed by gravity.
	for i in 4:
		var yaw: float = 45.0 + 90.0 * float(i)
		var hinge := K.node_at(to, Vector3(0, 0.94, 0), Vector3(0, yaw * K.DEG, 0))
		var swing: float = -74.0 if deployed else -4.0
		var shoe := K.node_at(hinge, Vector3(0, 0, -0.3), Vector3(swing * K.DEG, 0, 0))
		_Parts.wedge(shoe, 0.34, 0.62, 0.07, 0.14, Vector3(0, 0, -0.31))
		_Parts.cyl(shoe, 0.05, 0.36, Vector3(0, 0.12, -0.16), Vector3(50.0 * K.DEG, 0, 0), false, 6)


## THE CARRIER: a flat chamfered body, four arms on the diagonals, four matched
## ducted fans, and a release rack under the belly. Everything is a pair and
## everything is on a 90 — the exact opposite of the Tick, and the cheapest way
## to say ISSUED.
static func _piton_drone(to: Node, y: float) -> void:
	_Parts.plate(to, 1.12, 1.12, 0.34, 0.24, Vector3(0, y, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.plate(to, 0.78, 0.78, 0.18, 0.14, Vector3(0, y + 0.24, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.studs(to, 4, Vector3(-0.3, y + 0.34, -0.3), Vector3(0.2, 0, 0), 0.03)
	# Blade antenna on the port shoulder — the one asymmetric thing, and it is
	# the fitting the player's own HARDENED UPLINK already is.
	_Parts.plate(to, 0.1, 0.44, 0.05, 0.09, Vector3(-0.42, y + 0.46, 0.3), Vector3(0, 0, -8.0 * K.DEG))
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		var arm := K.node_at(to, Vector3(0, y, 0), Vector3(0, a, 0))
		_Parts.box(arm, Vector3(0.16, 0.13, 1.3), Vector3(0, 0.02, -0.72))
		_fan(arm, Vector3(0, 0.12, -1.38), 0.62, 4)
		# The leg under each motor, so the carrier can stand. It is a vehicle
		# that goes home and parks, not a one-way store.
		_Parts.box(arm, Vector3(0.09, 0.42, 0.09), Vector3(0, -0.22, -1.3))
		_Parts.cyl(arm, 0.16, 0.06, Vector3(0, -0.44, -1.3), Vector3.ZERO, false, 8)
	# THE RACK. Four legs in a square under the belly reaching down to the store's
	# top block, not to the band halfway down it: with the mast stowed the store
	# is 2.2 m long and the carrier has to stand well clear of it, so the claws
	# are at the end of 1.1 m posts rather than tucked under the hull.
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		_Parts.box(to, Vector3(0.11, 1.1, 0.11),
				Vector3(sin(a) * 0.34, y - 0.68, cos(a) * 0.34))
		_Parts.wedge(to, 0.24, 0.3, 0.14, 0.09,
				Vector3(sin(a) * 0.3, y - 1.3, cos(a) * 0.3), Vector3(0, -a, 0))


static func piton_flight(root_node: Node3D) -> void:
	# Store hung nose-down, mast stowed: its nose sits at y 0.1 and its top block
	# at 1.96, so the carrier rides at 3.2 and its claws close at 1.90.
	var store := K.node_at(root_node, Vector3(0, 0.1, 0), Vector3.ZERO)
	_piton(store, false)
	_piton_drone(root_node, 3.2)


static func piton_placed(root_node: Node3D) -> void:
	# SUNK TO THE SHOES. The nose is in the cabinet, so the store stands 0.78
	# lower than it measures and the four shoes are what it rests on. Drawing it
	# perched on an un-driven spike would be drawing a different proposal — and
	# the first pass, sunk only 0.34, photographed as a dart balanced on its tip.
	var sunk := K.node_at(root_node, Vector3(0, -0.78, 0), Vector3.ZERO)
	_piton(sunk, true)


static func piton_seated(root_node: Node3D, which: String) -> void:
	var cap: Array = _core(root_node, which)
	# Set FORWARD of the axis, up the slope, because the apex is the only part of
	# the cap with the two tall corner posts beside it to read against. Canted 14
	# degrees with it: a store driven into a slope stands normal to the slope,
	# not to the world, and the half-corrected angle is deliberate — the shoes
	# take the rest.
	var at := K.node_at(root_node, Vector3(0, _seat(cap) + 0.42, -float(cap[0]) * 0.3),
			Vector3(-14.0 * K.DEG, 0, 0))
	piton_placed(at)


# ─────────────────────────────────────────────
# C — PARASOL   Argus · UNFOLDS · the drone flies home
#
# The answer to the 2.4x size range, taken head on: the structure's width is set
# by how far it OPENS, not by what it lands on. It arrives as a closed bud, a
# slim cigar slung under a lopsided carrier, and on the cap it throws eight
# ribbed arms out and down past the cap edge until they find something. Folded
# it is 0.95 across; open it is 4.5.
#
# Argus, and it is the only one here that could not be anything else: the ribs
# carry lenses rather than tools, the mast ends in a cluster that does not agree
# about where to look, and the carrier has no face and visibly too much sensor
# for the lift it has.
# ─────────────────────────────────────────────

## THE BUD. A ribbed cigar with the rib edges drawn as longitudinal seams, so
# the closed object already tells you it is made of staves.
static func _parasol_bud(to: Node, at: Vector3) -> void:
	_Parts.sphere(to, 0.46, at + Vector3(0, 0.26, 0), Vector3(1.0, 1.5, 1.0))
	_Parts.cyl(to, 0.47, 1.5, at + Vector3(0, -0.5, 0), Vector3.ZERO, false, 10)
	_Parts.cyl(to, 0.3, 0.62, at + Vector3(0, -1.5, 0), Vector3(PI, 0, 0), true, 10)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_Parts.box(to, Vector3(0.07, 1.9, 0.1),
				at + Vector3(sin(a) * 0.46, -0.4, cos(a) * 0.46), Vector3(0, -a, 0))
	for y in [0.0, -0.94]:
		_Parts.ring(to, 0.47, 0.57, at + Vector3(0, float(y), 0))
	_lens(to, at + Vector3(0, -1.84, 0), 0.16, Vector3(-90.0 * K.DEG, 0, 0))


## THE CARRIER. Four fans, but nothing else about it is a quad: the hub is a
## slab offset from the lift, the fans sit at four different heights, and six
## lens pods look six ways. It does not look like it carries its own weight,
## which is the brief for this faction.
static func _parasol_drone(to: Node, y: float) -> void:
	var slab := _Parts.plate(to, 1.5, 0.9, 0.5, 0.18, Vector3(0, y, 0.1), Vector3(PI * 0.5, 0, 0))
	var slot := _Parts.box(slab, Vector3(1.0, 0.7, 0.16), Vector3(0, 0, -0.18))
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	var fans: Array = [[38.0, 1.42, 0.3, 0.64], [116.0, 1.26, 0.12, 0.56],
			[213.0, 1.5, 0.34, 0.6], [311.0, 1.18, 0.06, 0.5]]
	for f: Array in fans:
		var a: float = float(f[0]) * K.DEG
		var arm := K.node_at(to, Vector3(0, y + float(f[2]) * 0.4, 0.1), Vector3(0, a, 0))
		_Parts.box(arm, Vector3(0.11, 0.1, float(f[1])), Vector3(0, 0, -float(f[1]) * 0.5))
		_fan(arm, Vector3(0, float(f[2]), -float(f[1])), float(f[3]), 4)
	# SIX EYES, NO TWO AGREEING. Four round the slab's rim and two under it
	# looking at the load — which is the unsettling detail: it watches the thing
	# it is carrying.
	for e: Array in [[62.0, -6.0], [154.0, 8.0], [238.0, -22.0], [338.0, 14.0]]:
		var a: float = float(e[0]) * K.DEG
		_lens(to, Vector3(sin(a) * 0.68, y + 0.04, cos(a) * 0.68 + 0.1), 0.17,
				Vector3(float(e[1]) * K.DEG, a + PI, 0))
	_lens(to, Vector3(-0.3, y - 0.26, 0.24), 0.14, Vector3(-62.0 * K.DEG, 0.6, 0))
	_lens(to, Vector3(0.36, y - 0.3, -0.1), 0.12, Vector3(-74.0 * K.DEG, -0.3, 0))


## ONE RIB: hinged at the top of the drum, swung out and down, with instrument
## heads along it and a pad on the end. Yaw first, swing inside — same rule as
## everything else on this sheet.
static func _parasol_rib(to: Node, hinge_y: float, yaw_deg: float, drop_deg: float,
		length: float) -> void:
	var hub := K.node_at(to, Vector3(0, hinge_y, 0), Vector3(0, yaw_deg * K.DEG, 0))
	_Parts.cyl(hub, 0.1, 0.22, Vector3(0, 0, -0.22), Vector3(0, PI * 0.5, 0), false, 8)
	var rib := K.node_at(hub, Vector3(0, 0, -0.22), Vector3(drop_deg * K.DEG, 0, 0))
	_Parts.box(rib, Vector3(0.13, 0.16, length), Vector3(0, 0, -length * 0.5))
	_Parts.box(rib, Vector3(0.09, 0.3, length * 0.5), Vector3(0, -0.1, -length * 0.3))
	_lens(rib, Vector3(0, 0.16, -length * 0.34), 0.15, Vector3(-40.0 * K.DEG, 0, 0))
	_lens(rib, Vector3(0, 0.14, -length * 0.72), 0.12, Vector3(-28.0 * K.DEG, 0.4, 0))
	# The pad. These are the feet, and on a 1.25 m cap all eight of them land off
	# the edge and down the flanks, which is the concept working rather than
	# failing.
	_Parts.sphere(rib, 0.1, Vector3(0, 0, -length))
	_Parts.cyl(rib, 0.2, 0.08, Vector3(0, -0.12, -length), Vector3(-drop_deg * K.DEG, 0, 0), false, 10)


static func parasol_flight(root_node: Node3D) -> void:
	_parasol_bud(root_node, Vector3(0, 1.98, 0))
	# Three thin risers to the carrier. A rigid mount, not a sling: this is the
	# one concept where the payload has to be held square to be released square.
	for a_deg in [30.0, 150.0, 270.0]:
		var a: float = float(a_deg) * K.DEG
		_Parts.box(root_node, Vector3(0.07, 0.7, 0.07),
				Vector3(sin(a) * 0.32, 2.66, cos(a) * 0.32))
	_parasol_drone(root_node, 3.2)


static func parasol_placed(root_node: Node3D) -> void:
	# THE DRUM, standing on the cap. Short on purpose — the ribs are the object
	# and a tall body would compete with them.
	_Parts.cyl(root_node, 0.54, 1.5, Vector3(0, 1.1, 0), Vector3.ZERO, false, 10)
	_Parts.ring(root_node, 0.54, 0.68, Vector3(0, 0.46, 0))
	_Parts.ring(root_node, 0.54, 0.7, Vector3(0, 1.74, 0))
	# EIGHT RIBS at 2.9 m, dropped 41 degrees, which reaches 2.19 out and 1.90
	# down: the pads land level with the drum's foot and the span measures 4.5.
	# Two of them are swung a little further for the same reason nothing on an
	# Argus frame is symmetrical.
	for i in 8:
		var yaw: float = 360.0 * float(i) / 8.0
		var drop: float = -41.0 if i % 4 != 1 else -47.0
		_parasol_rib(root_node, 1.84, yaw, drop, 2.9)
	# THE MAST. Short, and the cluster on it is the only part pointed up — the
	# ribs look at the core, this one talks about it.
	_Parts.cyl(root_node, 0.12, 0.72, Vector3(0, 2.18, 0), Vector3.ZERO, false, 8)
	_Parts.sphere(root_node, 0.26, Vector3(0, 2.6, 0), Vector3(1.0, 0.8, 1.0))
	for e: Array in [[20.0, 24.0], [128.0, 6.0], [246.0, 38.0]]:
		var a: float = float(e[0]) * K.DEG
		_lens(root_node, Vector3(sin(a) * 0.26, 2.68, cos(a) * 0.26), 0.14,
				Vector3(float(e[1]) * K.DEG, a + PI, 0))


static func parasol_seated(root_node: Node3D, which: String) -> void:
	var cap: Array = _core(root_node, which)
	# Seated on the LOW lip, because the ribs hang below the drum's foot and the
	# whole point is that they reach past the cap on every size.
	var at := K.node_at(root_node, Vector3(0, float(cap[1]) + 0.12, 0), Vector3.ZERO)
	parasol_placed(at)


# ─────────────────────────────────────────────
# D — YOKE      Home Command · DROPS OVER · the drone flies home
#
# The big answer, and the only one that never touches the sloped cap. A heavy
# collar is carried flat on four cables under a six-fan lifter, lowered over the
# top of the core like a quoit, and caught by four claws that reach inward off
# its bore until they find the corner posts — the only square, level pair of
# surfaces anywhere on the core.
#
# It is 3.6 m across on every core, which is the argument: the STRUCTURE is a
# constant and the core is the variable. On the large core it is a collar; on
# the small core it is a cage round the whole machine. Both readings are
# correct and neither needs a second model.
# ─────────────────────────────────────────────

## THE COLLAR. An octagonal plate with its middle cut out, a rolled rim top and
## bottom, four masts on the top face and four claws reaching in off the bore.
## Built flat, with the claw pads at y 0.
static func _yoke_collar(to: Node) -> void:
	# THE BODY IS A DRUM, NOT AN EXTRUDED PLATE. It was a chamfered plate with a
	# bored-out middle, because chamfers are Home Command's idiom — and in three
	# renders the hole never appeared. A cylinder bored by a cylinder is the
	# pattern this project already has working (concepts_c.brood_c's chute), so
	# the bevels are given up to get the hole, and the collar earns its Home
	# Command read back from the stud rows, the rolled rims and the square shoes
	# instead.
	#
	# THE HOLE IS THE WHOLE CONCEPT. A collar that looks solid is a lid, and a
	# lid cannot be the thing that was lowered OVER a core.
	var drum := _Parts.cyl(to, 1.8, 0.8, Vector3(0, 0.7, 0), Vector3.ZERO, false, 12)
	var bore := _Parts.cyl(drum, 1.26, 1.1, Vector3.ZERO, Vector3.ZERO, false, 12)
	bore.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.ring(to, 1.78, 1.94, Vector3(0, 1.06, 0))
	_Parts.ring(to, 1.78, 1.94, Vector3(0, 0.34, 0))
	# FOUR RADIAL SLOTS THROUGH THE DRUM. The bore alone was not enough: in line
	# art on black a hole in a top face draws exactly the same as a flat top
	# face, and three renders of this collar came back looking like a lid. Slots
	# cut clean through the wall put daylight across the silhouette, which is the
	# only way "this is a ring you lowered over something" survives the house
	# style. 1.3x the wall thickness, as every cut in this project has to be.
	for i in 4:
		var a: float = (22.0 + 90.0 * float(i)) * K.DEG
		var slot := _Parts.box(drum, Vector3(0.44, 0.52, 1.6),
				Vector3(sin(a) * 1.5, 0.06, cos(a) * 1.5), Vector3(0, -a, 0))
		slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.ring(to, 1.22, 1.36, Vector3(0, 1.06, 0))
	_Parts.ring(to, 1.22, 1.36, Vector3(0, 0.34, 0))
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_Parts.studs(to, 3, Vector3(sin(a) * 1.62, 1.12, cos(a) * 1.62),
				Vector3(sin(a + 0.3) * 0.2, 0, cos(a + 0.3) * 0.2), 0.04)
	# FOUR CLAWS, reaching in and DOWN off the bore to r 0.62, and hanging below
	# the body where they can be seen. This is the part that spans the size
	# range: on the large core they catch the posts at r 1.56 barely bent, and on
	# the small core at r 0.65 fully in — one hinge, three cores.
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		var hub := K.node_at(to, Vector3(0, 0.46, 0), Vector3(0, a, 0))
		_Parts.cyl(hub, 0.13, 0.4, Vector3(0, 0, 1.44), Vector3(0, 0, PI * 0.5), false, 8)
		# DOWN AND IN, so the toes hang clear below the body at y -0.10 where they
		# can be seen and where they have something to land on. Rotating +34
		# instead sends the arm up into the bore, which is where the first pass
		# put it: four claws invisible inside the hole they were meant to grip
		# through.
		var claw := K.node_at(hub, Vector3(0, 0, 1.44), Vector3(-34.0 * K.DEG, 0, 0))
		_Parts.box(claw, Vector3(0.24, 0.18, 1.0), Vector3(0, 0, -0.5))
		var toe := K.node_at(claw, Vector3(0, 0, -1.0), Vector3(34.0 * K.DEG, 0, 0))
		_Parts.plate(toe, 0.46, 0.46, 0.14, 0.1, Vector3(0, 0.08, 0), Vector3(PI * 0.5, 0, 0))
		_Parts.studs(toe, 2, Vector3(-0.1, 0.1, -0.16), Vector3(0.2, 0, 0), 0.034)
	# FOUR HEADS ON THE TOP RIM. A collar with a blank top is a washer; these are
	# what say it is doing something, and they stand where there is clear air
	# whatever it is sitting on. Tall enough to be seen past the rim: the first
	# pass drew 0.84 m pegs and they read as bollards.
	for i in 4:
		var a: float = 90.0 * float(i) * K.DEG
		var at := Vector3(sin(a) * 1.42, 1.1, cos(a) * 1.42)
		_Parts.plate(to, 0.54, 0.54, 0.3, 0.12, at + Vector3(0, 0.3, 0), Vector3(PI * 0.5, 0, 0))
		_Parts.cyl(to, 0.095, 1.3, at + Vector3(0, 1.0, 0), Vector3.ZERO, false, 8)
		_Parts.ring(to, 0.1, 0.2, at + Vector3(0, 1.3, 0))
		_Parts.plate(to, 0.46, 0.44, 0.07, 0.09, at + Vector3(0, 1.74, 0), Vector3(0, -a, 0))
	# The cable eyes, left on the rim. A sling load is recognisable partly by
	# where it was slung from, and these are also the only asymmetry allowed.
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		_Parts.ring(to, 0.07, 0.16, Vector3(sin(a) * 1.56, 1.16, cos(a) * 1.56),
				Vector3(0, -a, PI * 0.5))


## THE LIFTER. Six fans on a hexagonal spar frame, a shallow body, and nothing
## slung rigidly — the load hangs on cables, which is what a crane does and
## what no other flying thing in this game does.
static func _yoke_lifter(to: Node, y: float) -> void:
	_Parts.plate(to, 1.5, 1.1, 0.42, 0.26, Vector3(0, y, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.plate(to, 1.0, 0.7, 0.2, 0.14, Vector3(0, y + 0.3, 0), Vector3(PI * 0.5, 0, 0))
	_Parts.studs(to, 5, Vector3(-0.44, y + 0.4, -0.3), Vector3(0.22, 0, 0), 0.03)
	for i in 6:
		var a: float = (30.0 + 60.0 * float(i)) * K.DEG
		var arm := K.node_at(to, Vector3(0, y, 0), Vector3(0, a, 0))
		_Parts.box(arm, Vector3(0.18, 0.15, 1.5), Vector3(0, 0.02, -0.82))
		_fan(arm, Vector3(0, 0.14, -1.6), 0.66, 4)
		_Parts.box(arm, Vector3(0.1, 0.12, 1.0), Vector3(0, -0.14, -1.1), Vector3(9.0 * K.DEG, 0, 0))
	# THE HOIST: a drum under the belly and four cables to the collar's eyes.
	_Parts.cyl(to, 0.3, 0.34, Vector3(0, y - 0.38, 0), Vector3(0, 0, PI * 0.5), false, 10)


static func yoke_flight(root_node: Node3D) -> void:
	var lift_y := 4.6
	_yoke_lifter(root_node, lift_y)
	_yoke_collar(root_node)
	# FOUR CABLES, converging. Drawn as thin canted boxes rather than cylinders
	# because a cable has to read as a LINE at icon size and a 0.05 m cylinder
	# with 12 sides does not.
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		var top := Vector3(0, lift_y - 0.5, 0)
		var low := Vector3(sin(a) * 1.56, 1.16, cos(a) * 1.56)
		var mid: Vector3 = (top + low) * 0.5
		var span: Vector3 = top - low
		var lean: float = atan2(sqrt(span.x * span.x + span.z * span.z), span.y)
		_Parts.box(root_node, Vector3(0.05, span.length(), 0.05), mid,
				Vector3(lean, -a + PI, 0))


static func yoke_placed(root_node: Node3D) -> void:
	_yoke_collar(root_node)


static func yoke_seated(root_node: Node3D, which: String) -> void:
	var cap: Array = _core(root_node, which)
	# THE CLAWS LAND ON THE CORNER POSTS, so the seat is the post top and not the
	# cap. On the medium and small cores the collar's 2.4 m bore clears the post
	# box and the collar settles with the cap standing up through the hole; on
	# the large core the posts are 3.12 m apart, wider than the bore, so it
	# perches on them instead and the cap stays under it. Both are drawn here
	# rather than argued, which is the only way to find out.
	var at := K.node_at(root_node, Vector3(0, float(cap[3]) + 0.1, 0), Vector3.ZERO)
	yoke_placed(at)


# ─────────────────────────────────────────────
# E — CHRYSALIS  Swarm · SPLITS · the lifter is consumed
#
# The Diver's logic applied to delivery rather than to a kill. The lift is a
# RING of six mismatched fans clamped round the structure's waist, so in flight
# the two halves are one object with the mast passing through the hole — there
# is no payload slung under anything, there is a spire wearing a wheel.
#
# On the cap it blows the collar: four jack feet take the weight, the ring falls
# away dead down the core's flank, and the spire is left with four broken strut
# stubs round its waist. That scar is the whole trick — the structure carries
# the evidence that something was attached to it, so the two objects are
# obviously the one object you watched arrive.
# ─────────────────────────────────────────────

## THE SPIRE. A splayed foot, a tapered mast, a swollen head with vent slots and
## a bundle of emitter stalks. Foot pads at y 0.
static func _chrysalis_spire(to: Node, stubs: bool) -> void:
	# THE LEGS, BUILT INSIDE THEIR OWN ROTATED NODE. The first pass rotated the
	# thigh box in place and then put the jack at an unrotated offset, so all
	# four feet photographed standing a third of a metre away from the legs they
	# belong to — four loose jacks on the floor. The rotation has to be a NODE,
	# and everything below the knee hangs off it.
	for i in 4:
		var a: float = (45.0 + 90.0 * float(i)) * K.DEG
		var hip := K.node_at(to, Vector3(0, 1.26, 0), Vector3(0, a, 0))
		var limb := K.node_at(hip, Vector3(0, 0, -0.3), Vector3(-52.0 * K.DEG, 0, 0))
		_Parts.sphere(limb, 0.15, Vector3.ZERO)
		_Parts.box(limb, Vector3(0.19, 0.19, 1.1), Vector3(0, 0, -0.55))
		# Each foot on its own jack, and that is this concept's answer to the
		# 30-degree cap: four independent screws, visibly at different lengths.
		var ankle := K.node_at(limb, Vector3(0, 0, -1.1), Vector3(52.0 * K.DEG, 0, 0))
		_jack(ankle, Vector3.ZERO, 0.46 if i % 2 == 0 else 0.3)
	_Parts.cyl(to, 0.42, 0.72, Vector3(0, 1.4, 0), Vector3.ZERO, false, 10)
	_Parts.cyl(to, 0.34, 1.5, Vector3(0, 2.3, 0), Vector3.ZERO, false, 10)
	_Parts.ring(to, 0.34, 0.47, Vector3(0, 1.8, 0))
	# THE HEAD. NOT A BALL WITH TWO ANTENNAE ON IT — that is what the first pass
	# drew and it photographed as a face: two stalks for eyes, a vent slot dead
	# centre for a mouth, and the whole concept read as a mascot. The fix is the
	# three rules this project keeps relearning about heads: no bilateral pair,
	# nothing centred on the front, and more than one mass.
	var head := _Parts.sphere(to, 0.6, Vector3(0.1, 3.26, -0.06), Vector3(1.15, 0.78, 1.0))
	# Vents on the FLANKS and the back, at bearings that leave the front blank.
	for a_deg in [74.0, 148.0, 286.0]:
		var a: float = float(a_deg) * K.DEG
		var slot := _Parts.box(head, Vector3(0.5, 0.14, 0.44),
				Vector3(sin(a) * 0.52, -0.04, cos(a) * 0.52), Vector3(0, -a, 0))
		slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.sphere(to, 0.36, Vector3(-0.38, 3.02, 0.28), Vector3(1.0, 0.9, 1.1))
	_Parts.sphere(to, 0.24, Vector3(0.42, 3.5, 0.1))
	_Parts.ring(to, 0.5, 0.66, Vector3(0.1, 3.0, -0.06))
	# FIVE STALKS, clustered off-axis and at five lengths. An odd number with no
	# pair in it is the cheapest thing there is to stop a crown reading as a
	# face, and the cluster is pushed to port so there is no centre line.
	for s: Array in [[12.0, 0.66], [78.0, 0.4], [146.0, 0.56], [214.0, 0.3], [304.0, 0.48]]:
		var a: float = float(s[0]) * K.DEG
		var at := Vector3(sin(a) * 0.3 - 0.12, 3.6, cos(a) * 0.3 + 0.04)
		_Parts.cyl(to, 0.045, float(s[1]), at + Vector3(0, float(s[1]) * 0.5, 0),
				Vector3(6.0 * K.DEG, 0, sin(a) * 11.0 * K.DEG), false, 6)
		_Parts.sphere(to, 0.085, at + Vector3(0, float(s[1]) + 0.04, 0))
	if not stubs:
		return
	# THE SCAR. Four torn strut roots and a split collar at the waist, left
	# behind when the ring went. Without these the placed object is just a spire
	# and the delivery is unreadable.
	_Parts.ring(to, 0.36, 0.52, Vector3(0, 2.44, 0))
	for i in 4:
		var a: float = (20.0 + 90.0 * float(i)) * K.DEG
		var stub := K.node_at(to, Vector3(0, 2.44, 0), Vector3(0, a, 0))
		var l: float = 0.34 if i % 2 == 0 else 0.22
		_Parts.box(stub, Vector3(0.14, 0.14, l), Vector3(0, 0.02, -0.4 - l * 0.5),
				Vector3(float(i) * 4.0 * K.DEG, 0, 0))


## THE LIFT RING. Six fans on a hoop, no two the same size, with six spokes in
## to a split collar. `collar` draws the collar closed round the mast; without
## it the ring is loose and can be laid on its side as wreckage.
static func _chrysalis_ring(to: Node, collar: bool) -> void:
	_Parts.ring(to, 1.74, 1.94, Vector3.ZERO)
	var fans: Array = [[12.0, 0.66], [71.0, 0.52], [138.0, 0.62], [196.0, 0.46],
			[256.0, 0.6], [318.0, 0.54]]
	for f: Array in fans:
		var a: float = float(f[0]) * K.DEG
		_fan(to, Vector3(sin(a) * 1.84, 0.1, cos(a) * 1.84), float(f[1]), 3)
	for i in 6:
		var a: float = (26.0 + 60.0 * float(i)) * K.DEG
		var reach: float = 1.84 if i % 3 != 1 else 1.7
		_Parts.box(to, Vector3(0.11, 0.1, reach),
				Vector3(sin(a) * reach * 0.5, -0.04, cos(a) * reach * 0.5), Vector3(0, -a, 0))
	if not collar:
		return
	_Parts.cyl(to, 0.5, 0.42, Vector3.ZERO, Vector3.ZERO, false, 10)
	_Parts.ring(to, 0.5, 0.64, Vector3(0, 0.14, 0))
	var bore := _Parts.cyl(to, 0.35, 0.7, Vector3.ZERO, Vector3.ZERO, false, 10)
	bore.operation = CSGShape3D.OPERATION_SUBTRACTION


static func chrysalis_flight(root_node: Node3D) -> void:
	# The spire, carried with its feet drawn UP against the mast — it is not
	# walking yet, and legs dangling at full stretch would read as a wreck being
	# lifted rather than as a machine being delivered.
	_chrysalis_spire(root_node, false)
	var ring := K.node_at(root_node, Vector3(0, 2.44, 0), Vector3.ZERO)
	_chrysalis_ring(ring, true)


static func chrysalis_placed(root_node: Node3D) -> void:
	_chrysalis_spire(root_node, true)


static func chrysalis_seated(root_node: Node3D, which: String) -> void:
	var cap: Array = _core(root_node, which)
	var at := K.node_at(root_node, Vector3(0, float(cap[1]) + 0.04, 0), Vector3.ZERO)
	chrysalis_placed(at)
	# THE DEAD RING, on the plinth where it fell. Drawn on purpose: it is the
	# cheapest possible proof that the thing on top arrived as one object, and it
	# is a piece of set dressing the mission can leave lying there afterwards.
	# CLEAR OF THE PLINTH, not on it: measured off cap[4] rather than off the cap
	# width, because the plinth is 2.7x wider than the cap on the small core and
	# the first pass put the wreck inside the building.
	var out: float = float(cap[4]) + 2.7
	var wreck := K.node_at(root_node, Vector3(-out * 0.92, 0.36, out * 0.46),
			Vector3(80.0 * K.DEG, 0.5, 14.0 * K.DEG))
	_chrysalis_ring(wreck, false)
