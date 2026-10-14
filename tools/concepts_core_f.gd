extends RefCounted
class_name ConceptsCoreF

# ─────────────────────────────────────────────
# CONCEPT BUILDERS — THE COMPUTE CORE, F REFINED. Five variants of F, three
# sizes each, fifteen builders, plus five that seat TICK on every medium.
#
# WHY THERE IS A REFINEMENT ROUND. Round two (tools/concepts_core2.gd,
# docs/concepts/COMPUTE_CORES_2.md) put up five concepts and the human chose
# F — CAPITAL, the constant-cap position: ONE 2.60 m lugged pad at every size,
# the shaft growing beneath it in girth as well as height. The argument is in
# COMPUTE_CORES_2.md §1 and it is not reopened here. A cap is a TERMINATOR
# rather than a neighbour, so the eye compares cap width to shaft width in the
# same part of the picture at the same depth — which is why a constant cue at
# the TOP works where round one's B failed with a constant cue at the bottom.
#
# TWO NOTES CAME BACK WITH THE CHOICE, and this file is those two notes:
#
#   1. "IT NEEDS TO HAVE CLEARLY DEFINED AND LOTS OF PLACES TO HAVE FACTION
#      COLOUR." A compute core is a capture objective and who holds it has to
#      be readable across a map. Env/world_objects/core_signal.gd fakes that
#      today with a procedural collar, a climb band, an OmniLight and a beam,
#      tinted from HUDPalette by owner, and its own header says it is
#      placeholder presentation that "the real art can replace without touching
#      the state machine". These variants are that real art.
#   2. "IT ALSO NEEDS TO HAVE A BASE." F stood more or less straight on the
#      ground on a two-step plinth. Each variant here has a different, real
#      foundation and each one does a job beyond looking right.
#
# THE CONSTRAINT NOBODY HAD WRITTEN DOWN, and it governs every paint decision
# below: IN THIS PROJECT'S LINE ART A COLOUR ZONE THAT IS NOT ALSO A SHAPE IS
# INVISIBLE. FactionLivery works on the robots because the painted pieces are
# separate meshes with their own edges — a flat face tinted a different colour
# reads as nothing at all in the icon studio and reads as nothing at 60 m in
# game either. So nothing here is "a panel to paint". Every painted zone is a
# raised plate, a recessed bay, a collar, a band, a fin or a shoulder: a thing
# with an EDGE, which happens to be the thing that takes the colour.
#
# Every painted part is named `Paint_<tag>` by _paint(). That is not decoration:
# tools/shoot_core_f.gd walks for the prefix and prints each variant's painted
# share of the projected picture, so "lots of places" is a measurement in this
# round rather than a claim.
#
# WHERE THE PAINT HAS TO GO, three places, and each variant names its three:
#   · HIGH, so a core reads as held from across the bowl.
#   · AT THE APPROACH FACE, at eye level, where the player actually stands.
#   · BELOW THE CAP, because the Tick lands ON the cap and occludes the top.
#     Measured: tick_placed is built with the barb tips at y 0 and is seated at
#     `target - SEAT_DROP`, so the barbs reach down only to target - 0.45 and
#     the drone's body sits above that. ANYTHING AT OR BELOW THE CORBEL SLAB
#     (y = target - 1.26) IS CLEAR OF THE DRONE AT EVERY SIZE. That number is
#     why the collars, bands and shoulders in this file sit where they do.
#
# WHAT IS HELD CONSTANT ACROSS ALL FIVE, so the comparison is about the base
# and the colour and nothing else: F_PAD (1.3 half-width), the shaft widths
# 1.5 / 2.3 / 3.6, the corbel, the console, the band courses, the back risers
# and the drums. The variants differ in their FOUNDATION and in WHERE THE
# COLOUR LIVES. Nothing here re-argues the cap.
#
# THIS IS ARCHITECTURE, NOT A ROBOT. No concept_kit.head(), no legs. Primitives
# from mockup_parts.gd only; read every box as a brush.
#
# THE TRAPS, all paid for in earlier rounds and none of them rediscovered here:
#   · CSGPolygon3D EXTRUDES ALONG ITS OWN NEGATIVE Z. A lug stands up with
#     Rx(+90); at Rx(-90) it extrudes down through its own deck, draws as
#     nothing, and the only symptom is measuring 0.11 m short. Every lug in
#     this file comes from ConceptsCore2._lugs, which carries the right sign.
#   · _console()'s HEIGHT IS WORLD, NOT BODY-LOCAL. These bodies are centred on
#     their own middles, so a naive local 1.55 puts the plate over the Walker's
#     head. ConceptsCore2._console takes a world height and warns; it is reused
#     rather than copied for exactly that reason.
#   · A HANDRAIL IS THE TALLEST THING ON ANYTHING SHORT. There is no rail in
#     this file. F-large had one; it is dropped because the base is the hero of
#     this round and a 1.05 m rail standing on a 0.55 m dais is a measuring
#     hazard for no gain.
#   · A BORED HOLE DRAWS IDENTICALLY TO A FLAT FACE at fill = 0. F4's well is
#     therefore a KERB standing proud, not a pit sunk in; the recessed bays in
#     F3 carry a set-in back plate and a lintel over them so the recess has
#     three edges and does not depend on the hole surviving the photograph.
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const _F := preload("res://tools/concepts_core2.gd")
const _Hack := preload("res://tools/concepts_hack.gd")
const DEG := PI / 180.0

## Straight out of round two and not re-derived. If these ever disagree with
## ConceptsCore2 the renderer's measurement is the thing to believe.
const F_PAD := _F.F_PAD
const H_SMALL := _F.H_SMALL
const H_MEDIUM := _F.H_MEDIUM
const H_LARGE := _F.H_LARGE

## The shaft widths, held across all five variants. Round two's F numbers.
const SHAFT := {"small": 1.5, "medium": 2.3, "large": 3.6}

## How far below the lug tops the Tick is seated — ConceptsCore2.SEAT_DROP.
const SEAT_DROP := 0.45


# ─────────────────────────────────────────────
# PAINT
# ─────────────────────────────────────────────

## Tag a part as faction-painted. The name is the contract with the renderer
## and with whoever builds the real thing: these meshes get the owner colour,
## everything else stays plant-grey.
##
## IT RENAMES RATHER THAN TINTING. The sheets are line art — a tint would
## photograph as nothing, which is the very fault this round exists to avoid
## designing into. What the sheet has to show is that each painted zone is a
## SHAPE, and a shape shows up whether or not anybody has coloured it yet.
static func _paint(n: Node, tag: String) -> Node:
	n.name = "Paint_" + tag
	return n


static func _paint_all(parts: Array, tag: String) -> void:
	if parts.is_empty():
		push_warning("_paint_all: nothing to paint for '%s', so this zone is missing" % tag)
		return
	for p in parts:
		_paint(p as Node, tag)


# ─────────────────────────────────────────────
# SHARED FITTINGS — the ones round two does not already own
# ─────────────────────────────────────────────

## FOUR BARS ON A RECTANGLE'S EDGE. ConceptsCore2._kerb does this at one fixed
## height and thickness; everything in this file that wants a collar, a capping
## course, a lip or a riser band wants its own. Returned as an array so the
## caller can paint the whole ring in one call.
##
## The bars are INSET by half their thickness, so the ring's outer face lies on
## the rectangle it is given and the ring reads as a band ON something rather
## than a box AROUND it.
static func _rim(to: Node, hw: float, hd: float, y0: float, h: float,
		t: float) -> Array:
	if h <= 0.0 or t <= 0.0:
		push_warning("_rim: %.2f x %.2f section, so no band was drawn" % [h, t])
		return []
	var made: Array = []
	for sx: float in [-1.0, 1.0]:
		made.append(_Parts.box(to, Vector3(t, h, hd * 2.0),
				Vector3(sx * (hw - t * 0.5), y0 + h * 0.5, 0)))
	for sz: float in [-1.0, 1.0]:
		made.append(_Parts.box(to, Vector3(hw * 2.0 - t * 2.0, h, t),
				Vector3(0, y0 + h * 0.5, sz * (hd - t * 0.5))))
	return made


## A short post with a domed cap — a cleat, a bollard, a tie-down. The one
## fitting in this file that is always robot-scale whatever the core is, which
## is what makes a base read as somewhere a machine works.
static func _bollard(to: Node, at: Vector3, h: float = 0.72) -> void:
	_Parts.cyl(to, 0.13, h, at + Vector3(0, h * 0.5, 0), Vector3.ZERO, false, 8)
	_Parts.ring(to, 0.13, 0.19, at + Vector3(0, h * 0.78, 0))
	_Parts.cyl(to, 0.1, 0.09, at + Vector3(0, h + 0.04, 0), Vector3.ZERO, false, 8)


## A conduit run: a pipe along one axis with saddles under it, ending in a
## gland box. This is the fitting that says the core is PLUGGED INTO SOMETHING
## rather than parked on the ground, and it is the reason three of the five
## bases below are worth more than a slab would be.
static func _conduit(to: Node, from: Vector3, to_p: Vector3, r: float) -> Array:
	var d: Vector3 = to_p - from
	var leng: float = d.length()
	if leng < 0.4:
		push_warning("_conduit: %.2f m of run, so no pipe was drawn" % leng)
		return []
	var mid: Vector3 = (from + to_p) * 0.5
	# Along X or along Z; this file never needs a diagonal one and a general
	# solution here would be three lines of trigonometry nobody reads.
	var along_x: bool = absf(d.x) >= absf(d.z)
	var euler: Vector3 = Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
	var made: Array = [_Parts.cyl(to, r, leng, mid, euler, false, 8)]
	var saddles: int = maxi(2, int(leng / 1.8) + 1)
	for i in saddles:
		var t: float = float(i) / float(saddles - 1)
		var p: Vector3 = from.lerp(to_p, t)
		_Parts.box(to, Vector3(r * 2.4, p.y, r * 2.4), Vector3(p.x, p.y * 0.5, p.z))
	made.append(_Parts.box(to, Vector3(r * 3.0, r * 3.0, r * 3.0), to_p))
	return made


# ─────────────────────────────────────────────
# THE TRUNK — everything above the base, identical in all five variants.
#
# This is round two's _capital with the plinth taken out and the ground level
# made an argument, because the whole refinement is about what is UNDER it.
# Every number in here is round two's, lifted rather than re-tuned: the neck at
# target - 1.26, the corbel slab at neck + 0.11, the corbel neck up to
# target - 0.80, the pad's lug tops at target.
#
# THE CORBEL IS NOT OPTIONAL and the reason is in COMPUTE_CORES_2.md: a
# constant pad on a shaft of three different widths needs a transition, or two
# of the three read as a mistake — on the small core the pad overhangs the
# shaft by half a metre each side, on the large the shaft is wider than the pad.
# ─────────────────────────────────────────────

static func _trunk(to: Node3D, sw: float, target: float, ground: float) -> Dictionary:
	var neck: float = target - 1.26
	if neck - ground < 1.2:
		push_warning("_trunk: %.2f m of shaft above a base at %.2f, so the console has nowhere to go" % [neck - ground, ground])
	var shaft := _Parts.box(to, Vector3(sw, neck - ground, sw),
			Vector3(0, (neck + ground) * 0.5, 0))
	_F._console(shaft, -sw * 0.5, minf(sw * 0.74, 1.5))
	_F._bands(to, sw * 0.5, sw * 0.5, ground, neck)
	_F._risers(to, sw * 0.5, sw * 0.5, ground, neck - 0.4, clampf(sw * 0.06, 0.07, 0.14))
	var ctop: float = target - _F.LUG_H - _F.DECK_T - 0.2
	var cw: float = maxf(sw, F_PAD * 1.5) + 0.1
	_Parts.box(to, Vector3(cw, 0.22, cw), Vector3(0, neck + 0.11, 0))
	_Parts.box(to, Vector3(F_PAD * 1.6, ctop - neck - 0.22, F_PAD * 1.6),
			Vector3(0, (ctop + neck + 0.22) * 0.5, 0))
	_F._pad(to, F_PAD, target)
	return {"neck": neck, "ctop": ctop, "corbel_hw": cw * 0.5, "shaft": shaft}


# THERE ARE NO CHILLER DRUMS ON THESE, AND ROUND TWO'S F HAD THEM. They were
# here for one render and came straight back out, because of what they did to
# the one number this round exists to compare.
#
# Measured: with a drum stood off each flank of F1-large the body came out
# 10.72 m wide, against 8.08 for the base alone — so a third of the quoted
# footprint was a piece of dressing lifted from another round, and the five
# bases could not be compared with each other at all. Every width below is now
# THE BASE'S OWN WIDTH plus whatever paint stands proud of it, which is the
# figure a level designer has to leave room for.
#
# They are a dressing decision and they belong to whoever builds the selected
# variant, not to the comparison.


# ═════════════════════════════════════════════
# F1 — APRON.  BASE: A CAST APRON. COLOUR: A LIP, A COLLAR AND TWO PILASTERS.
#
# THE BASE. A single cast slab laid on the ground, well wider than the shaft,
# with a raised lip all the way round it and cable ducts cast into its face
# running out to both flanks. The shaft stands on a low pedestal in the middle
# of it.
#
# WHAT THE APRON IS FOR, beyond looking right. It DRAWS THE INTERACT FOOTPRINT
# ON THE GROUND. The raycast is 2 m and does not fire from inside the volume,
# so reach is the core's own footprint and not a metre more — which today is an
# invisible rule the player discovers by failing. An apron with a lip is that
# rule made of concrete: stand inside the lip and it works. It is also the
# flattest of the five bases, which matters because playable ground has to be
# flat and this is ground the squad walks over.
#
# THE COLOUR, three zones, and this is the most conservative distribution in
# the set:
#   · THE LIP, a 0.26 m rim round the whole apron. Ground level, 360 degrees,
#     never occluded by anything including the Tick, and it is the one painted
#     ring you are standing inside when you take the objective. This is the
#     direct replacement for core_signal's DeckCollar, which is a procedural
#     tube at the deck doing exactly this job badly.
#   · THE COLLAR, a 0.44 m band standing proud just under the corbel. High,
#     reads at range, and at y = neck it is a full metre below the Tick's
#     lowest barb.
#   · TWO PILASTERS framing the console bay on the approach face, from 0.9 up
#     to just under the collar. Eye level, at the exact spot the player stands.
# ═════════════════════════════════════════════

static func _apron(to: Node3D, sw: float, target: float) -> void:
	var ar: float = sw * 0.95 + 0.62        # apron half-width
	var ground := 0.44                      # pedestal top, where the shaft starts
	# THE SLAB. Thin on purpose: an apron is a pour, not a plinth, and the
	# moment it gets thick it reads as the stepped plinth F already had.
	_Parts.box(to, Vector3(ar * 2.0, 0.18, ar * 2.0), Vector3(0, 0.09, 0))
	# Ducts cast into it, running out to both flanks. Raised, not scribed —
	# a scribed line on a top face is the flat-face fault in another costume.
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(0.34, 0.12, ar * 1.5),
				Vector3(sx * (ar - 0.55), 0.24, 0))
	# The pedestal: one square step off the apron, which is what stops the shaft
	# from reading as a post pushed through a sheet of card.
	_Parts.box(to, Vector3(sw + 0.56, ground, sw + 0.56), Vector3(0, ground * 0.5, 0))
	_Parts.box(to, Vector3(sw + 0.78, 0.14, sw + 0.78), Vector3(0, 0.25, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_bollard(to, Vector3(sx * (ar - 0.34), 0.18, sz * (ar - 0.34)), 0.6)

	var t := _trunk(to, sw, target, ground)
	var neck: float = float(t["neck"])

	# ── PAINT ────────────────────────────────────────────────────────────────
	_paint_all(_rim(to, ar, ar, 0.18, 0.26, 0.24), "apron_lip")
	_paint_all(_rim(to, sw * 0.5 + 0.13, sw * 0.5 + 0.13, neck - 0.66, 0.44, 0.26),
			"collar")
	# The pilasters. Set at the shaft's own front corners and standing 0.15
	# proud of the face, so they frame the console recess instead of competing
	# with it — two verticals and a lit slot between them.
	# PLACED AGAINST THE FACE, NOT NEAR IT. _Parts.plate extrudes along its own
	# NEGATIVE Z, so a plate spans [z - depth, z] — put its origin at the face's
	# own z (plus a bite) and it stands proud outward; put it at z - depth and it
	# floats a hand's width off the wall, which is the fault the kit's own
	# "armour hovering off the hull" note was written about.
	for sx: float in [-1.0, 1.0]:
		_paint(_Parts.plate(to, 0.28, neck - 1.2, 0.15, 0.06,
				Vector3(sx * (sw * 0.5 - 0.15), (neck - 0.3 + 0.9) * 0.5,
						-sw * 0.5 + 0.02)), "pilaster")


static func f1_small(to: Node3D) -> void:
	_apron(to, SHAFT["small"], H_SMALL)


static func f1_medium(to: Node3D) -> void:
	_apron(to, SHAFT["medium"], H_MEDIUM)


static func f1_large(to: Node3D) -> void:
	_apron(to, SHAFT["large"], H_LARGE)


# ═════════════════════════════════════════════
# F2 — RAFT.  BASE: A BOLTED RAFT. COLOUR: FOUR FULL-HEIGHT CORNER FINS.
#
# THE BASE. A steel raft plate carried on four short pads with a shadow gap
# under it, its edges bolted with stud rows, a lip round it, and two conduit
# trunks leaving it at the back.
#
# WHAT THE RAFT IS FOR. It is the only base here that is obviously PORTABLE —
# a thing that was craned in and bolted down, not cast in place. That is the
# right fiction for a machine StratCom plants to take ground, and it is also
# the one base that survives being put on a slope, because a raft on pads can
# shim and an apron cannot. It gives the player a 0.3 m step up, which is low
# enough not to be a pathing event and high enough to say "on" and "off".
#
# THE COLOUR, and this is the maximalist answer in the set. FOUR BLADE FINS AT
# THE SHAFT'S CORNERS, each one standing 0.25 m proud on the diagonal and
# running the WHOLE height of the shaft, from a flared foot on the raft to a
# flared head under the corbel. The fins are set on the diagonals so no two
# faces are ever hidden at once: from any bearing on the ground at least two
# fins are in profile and one is in plan.
#   · HIGH — the fin heads reach the corbel at target - 1.26, the exact height
#     the Tick cannot reach down to.
#   · EYE LEVEL — the fins pass through 1.55 on both sides of the console bay.
#   · UNDER THE CAP — the heads again. Nothing in this variant is on the pad.
# This is the variant that answers "lots of places" with "one place, enormous".
# ═════════════════════════════════════════════

const F2_FIN_T := 0.2       ## fin thickness
const F2_FIN_W := 0.62      ## how far a fin runs out along its diagonal


## ONE FIN, on the corner (sx, sz). Built in a YAWED FRAME and not by eye.
##
## The blade has to lie in the plane that contains the vertical and the OUTWARD
## DIAGONAL, or it is a plate stuck to a corner at a random angle. A rotation
## of t about Y takes +X to (cos t, 0, -sin t), so the yaw that points local +X
## outward along (sx, 0, sz) is atan2(-sz, sx) — and getting that sign wrong
## lays all four fins across their corners instead of through them, which is
## the same family of fault as round one's splayed lattice.
static func _fin(to: Node, sx: float, sz: float, sw: float, y0: float,
		y1: float) -> Array:
	var yaw: float = atan2(-sz, sx)
	var r: float = sw * 0.5 - 0.08
	var at := Vector3(sx * r, 0, sz * r)
	var made: Array = []
	made.append(_Parts.box(to, Vector3(F2_FIN_W, y1 - y0, F2_FIN_T),
			at + Vector3(0, (y0 + y1) * 0.5, 0), Vector3(0, yaw, 0)))
	# THE FOOT. A fin that meets a deck at a right angle reads as a sheet
	# standing in a slot; a flare at the bottom reads as something welded.
	made.append(_Parts.box(to, Vector3(F2_FIN_W + 0.3, 0.34, F2_FIN_T + 0.16),
			at + Vector3(0, y0 + 0.17, 0), Vector3(0, yaw, 0)))
	# THE HEAD, under the corbel. This is the high read and it is deliberately
	# the heaviest section of the fin: at 12.4 m the shaft's own courses carry
	# the middle and only the head is still a shape.
	made.append(_Parts.box(to, Vector3(F2_FIN_W + 0.22, 0.46, F2_FIN_T + 0.1),
			at + Vector3(0, y1 - 0.23, 0), Vector3(0, yaw, 0)))
	return made


static func _raft(to: Node3D, sw: float, target: float) -> void:
	var rw: float = sw * 0.72 + 0.56        # raft half-width
	var ground := 0.52
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_Parts.box(to, Vector3(0.52, 0.3, 0.52),
					Vector3(sx * (rw - 0.42), 0.15, sz * (rw - 0.42)))
	# THE SHADOW GAP IS THE WHOLE TELL. The plate's underside is at 0.3 and its
	# top at 0.52, so there is 0.3 m of daylight under a 0.22 m plate — which is
	# what separates "bolted down" from "poured".
	_Parts.box(to, Vector3(rw * 2.0, 0.22, rw * 2.0), Vector3(0, 0.41, 0))
	for sz: float in [-1.0, 1.0]:
		_Parts.studs(to, 6, Vector3(-rw + 0.4, 0.53, sz * (rw - 0.22)),
				Vector3((rw * 2.0 - 0.8) / 5.0, 0, 0), 0.055)
	_paint_all(_rim(to, rw, rw, 0.52, 0.16, 0.18), "raft_lip")
	# Two conduit trunks leaving the raft at the back, over the lip and away.
	for sx: float in [-0.5, 0.5]:
		_paint_all(_conduit(to, Vector3(sx * sw, 0.78, sw * 0.5),
				Vector3(sx * sw, 0.78, rw + 0.7), 0.17), "conduit")

	var t := _trunk(to, sw, target, ground)
	var neck: float = float(t["neck"])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_paint_all(_fin(to, sx, sz, sw, ground, neck), "fin")


static func f2_small(to: Node3D) -> void:
	_raft(to, SHAFT["small"], H_SMALL)


static func f2_medium(to: Node3D) -> void:
	_raft(to, SHAFT["medium"], H_MEDIUM)


static func f2_large(to: Node3D) -> void:
	_raft(to, SHAFT["large"], H_LARGE)


# ═════════════════════════════════════════════
# F3 — DAIS.  BASE: A STEPPED DAIS. COLOUR: RISER BANDS AND RECESSED BAYS.
#
# THE BASE. Two 0.22 m steps, square, with a third wider step thrown out at the
# approach face so the dais has a FRONT, and two bollards at the top step's
# front corners.
#
# WHAT THE DAIS IS FOR. It is the only base that moves the player's FEET. On
# the other four you walk up to the core; on this one you step up onto it, and
# a 0.44 m rise is the cheapest way to say "you are on the objective now"
# without a trigger volume or a line of UI. It also lifts the console's user
# clear of ground clutter at the one face where a squad will be stood around
# him. The price is in §3 of the doc and it is real: two steps is two more
# things for a nav bake to quantise.
#
# THE COLOUR, and this is the DISTRIBUTED answer — small zones, many of them:
#   · RISER BANDS. A proud band on each of the two step risers. Ankle and knee
#     height, 360 degrees, and the thing you look down at while standing on the
#     objective. This is the ground-level read.
#   · RECESSED BAYS. A stacked column of bays cut into each flank, with a
#     painted back plate set INTO each one and a lintel over it. Three edges
#     per bay, so the colour is bounded whether or not the recess survives the
#     photograph — a bored hole on its own draws identically to a flat face and
#     that is what killed the Yoke. The bays run the shaft's whole height, so
#     the count grows with the core: one on the small, three on the medium,
#     six on the large. THE COLOUR ZONE COUNT IS ITSELF A SIZE CUE.
#   · THE LINTEL COURSE, a painted band immediately under the corbel. High, and
#     below the Tick.
# ═════════════════════════════════════════════

const F3_BAY_H := 0.62
const F3_BAY_STEP := 1.32


## ONE RECESSED BAY in a flank. The subtraction is parented to the SHAFT and
## positioned in the shaft's own frame; the painted back and the lintel are
## parented to the body, because they are placed against the ground.
static func _bay(to: Node3D, shaft: CSGBox3D, sx: float, sw: float, y: float) -> void:
	var bw: float = sw * 0.52
	var cut := _Parts.box(shaft, Vector3(0.36, F3_BAY_H, bw),
			Vector3(sx * (sw * 0.5 - 0.1), y - shaft.position.y, 0))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# The back plate, laid against the back of the recess so it has its own
	# shadow line. The yaw carries the sign: _Parts.plate extrudes along its own
	# -Z, and Ry(t) takes (0,0,-1) to (-sin t, 0, -cos t), so yaw = sx * 90 deg
	# extrudes INTO the body on both flanks. One fixed +90 would have left the
	# -X plate floating in the middle of its own bay.
	_paint(_Parts.plate(to, bw * 0.84, F3_BAY_H - 0.16, 0.1, 0.07,
			Vector3(sx * (sw * 0.5 - 0.18), y, 0),
			Vector3(0, sx * PI * 0.5, 0)), "bay")
	# The lintel: a bar over the opening, standing proud. Without it the bay's
	# top edge is a line in a flat face and the whole thing is a hole again.
	_Parts.box(to, Vector3(0.18, 0.14, bw + 0.24),
			Vector3(sx * (sw * 0.5 + 0.03), y + F3_BAY_H * 0.5 + 0.07, 0))


static func _dais(to: Node3D, sw: float, target: float) -> void:
	var ground := 0.44
	var d0: float = sw * 0.8 + 0.92         # lower step half-width
	var d1: float = sw * 0.8 + 0.52         # upper step half-width
	_Parts.box(to, Vector3(d0 * 2.0, 0.22, d0 * 2.0), Vector3(0, 0.11, 0))
	_Parts.box(to, Vector3(d1 * 2.0, 0.22, d1 * 2.0), Vector3(0, 0.33, 0))
	# THE FRONT. A dais with four identical sides has no approach; one wider
	# tread at -Z is what makes the console face the way in rather than a way in.
	_Parts.box(to, Vector3(d1 * 1.5, 0.22, 0.9), Vector3(0, 0.11, -d0 - 0.34))
	for sx: float in [-1.0, 1.0]:
		_bollard(to, Vector3(sx * (d1 - 0.26), 0.44, -d1 + 0.26), 0.78)

	var t := _trunk(to, sw, target, ground)
	var neck: float = float(t["neck"])
	var shaft: CSGBox3D = t["shaft"]

	# ── PAINT ────────────────────────────────────────────────────────────────
	# The riser bands, standing 0.05 proud of each step's face.
	_paint_all(_rim(to, d0 + 0.05, d0 + 0.05, 0.03, 0.15, 0.1), "riser")
	_paint_all(_rim(to, d1 + 0.05, d1 + 0.05, 0.25, 0.15, 0.1), "riser")
	# The bays. Counted from the shaft's real run, so the number is a
	# consequence of the size rather than a table somebody has to keep in step.
	var bays: int = maxi(1, int((neck - ground - 1.3) / F3_BAY_STEP))
	for sx: float in [-1.0, 1.0]:
		for k in bays:
			_bay(to, shaft, sx, sw, ground + 1.0 + float(k) * F3_BAY_STEP)
	_paint_all(_rim(to, sw * 0.5 + 0.1, sw * 0.5 + 0.1, neck - 0.42, 0.3, 0.2),
			"lintel")


static func f3_small(to: Node3D) -> void:
	_dais(to, SHAFT["small"], H_SMALL)


static func f3_medium(to: Node3D) -> void:
	_dais(to, SHAFT["medium"], H_MEDIUM)


static func f3_large(to: Node3D) -> void:
	_dais(to, SHAFT["large"], H_LARGE)


# ═════════════════════════════════════════════
# F4 — WELL.  BASE: A SUNKEN WELL. COLOUR: THE KERB, THE RUNS AND A LAMP HOOD.
#
# THE BASE. The shaft rises out of a kerbed well: a square kerb wall standing
# 0.55 m above ground with a capping course on it, a grating bridging the gap
# between the kerb and the shaft's footing, and two conduit runs climbing out
# over the kerb and away across the ground.
#
# IT IS A KERB AND NOT A HOLE, AND THAT IS DELIBERATE. A bored pit draws
# identically to a flat face at fill = 0 — the fault that nearly killed the
# Yoke on the hack sheets. So what makes this read as a well is the thing
# standing PROUD of the ground, not the thing missing from it. In a built level
# the TERRAIN lane can sink the floor inside; the drawing does not depend on it.
#
# WHAT THE WELL IS FOR. It is the only base that says the core is the TOP OF
# SOMETHING. A compute core that is plugged into buried plant is a better
# object than one bolted to a slab: it explains why it is here, it explains why
# the enemy built it here and not forty metres left, and it gives a mission
# designer a reason to put one where the ground is already dug. It is also the
# one base with a built-in piece of cover — a 0.55 m kerb is prone-height for
# the squad holding the objective.
#
# THE COLOUR, and this one is the literal replacement for the placeholder:
#   · THE KERB CAPPING, a painted course on top of the kerb wall, waist high,
#     360 degrees, surrounding the player. core_signal._build puts a procedural
#     DeckCollar at exactly this height for exactly this reason, and this is
#     that collar made of architecture.
#   · THE CONDUIT RUNS, painted pipe sections leaving the well and running off
#     across the ground. GROUND-LEVEL COLOUR THAT LEAVES THE FOOTPRINT: the
#     only zone in the set that is readable from a bearing where the core
#     itself is behind cover.
#   · THE LAMP HOOD, a hooded signal box high on the approach face just under
#     the corbel, with its own brackets. High and clear of the drone.
# ═════════════════════════════════════════════

static func _well(to: Node3D, sw: float, target: float) -> void:
	var kw: float = sw * 0.5 + 1.2          # kerb half-width, outer
	var kh := 0.64                          # how far the kerb stands proud
	var ground := 0.0
	# The footing the shaft stands on, down in the well.
	_Parts.box(to, Vector3(sw + 0.42, 0.34, sw + 0.42), Vector3(0, 0.17, 0))
	# THE KERB WALL. Unpainted — the wall is structure and the capping course on
	# top of it is the colour, which is the whole rule this round is built on:
	# the paint goes on the thing with the edge, not on the thing with the area.
	#
	# 0.64 AND NOT 0.55, measured off the first render: at 0.55 with a 0.2 cap
	# the ring photographed as a planter box round a post rather than as a kerb
	# a figure stands behind, and the two conduit runs reaching 1.4 m past it
	# finished the job by reading as a guardrail. Taller wall, heavier cap,
	# shorter runs.
	_rim(to, kw, kw, 0.0, kh, 0.38)
	# THE GRATING. Bars spanning kerb to footing, which is what makes the gap
	# between them read as a gap rather than as missing geometry.
	var inner: float = kw - 0.38
	for sx: float in [-1.0, 1.0]:
		var span: float = inner - (sw * 0.5 + 0.21)
		var n: int = maxi(2, int((sw + 0.42) / 0.42))
		for i in n:
			var z: float = lerpf(-sw * 0.5, sw * 0.5, float(i) / float(n - 1))
			_Parts.box(to, Vector3(span, 0.09, 0.1),
					Vector3(sx * (inner + sw * 0.5 + 0.21) * 0.5, kh - 0.14, z))

	var t := _trunk(to, sw, target, ground)
	var neck: float = float(t["neck"])

	# ── PAINT ────────────────────────────────────────────────────────────────
	_paint_all(_rim(to, kw + 0.07, kw + 0.07, kh, 0.26, 0.52), "kerb_cap")
	# The runs: one out to -X, one out to +Z, over the kerb and away. Different
	# bearings on purpose — two parallel pipes read as one object.
	_paint_all(_conduit(to, Vector3(-sw * 0.5, kh + 0.34, 0.0),
			Vector3(-kw - 1.0, kh + 0.34, 0.0), 0.21), "run")
	_paint_all(_conduit(to, Vector3(0.0, kh + 0.34, sw * 0.5),
			Vector3(0.0, kh + 0.34, kw + 0.8), 0.21), "run")
	# THE LAMP HOOD, on the approach face under the corbel. Two brackets, a box
	# and a hood plate raked over it — the hood is what gives it a top edge, and
	# a box flush on a wall has none.
	var hy: float = neck - 0.62
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(0.12, 0.12, 0.4),
				Vector3(sx * 0.42, hy - 0.26, -sw * 0.5 - 0.2))
	_paint(_Parts.plate(to, 1.12, 0.42, 0.3, 0.08,
			Vector3(0, hy, -sw * 0.5 + 0.05)), "lamp")
	_paint(_Parts.plate(to, 1.32, 0.5, 0.09, 0.07,
			Vector3(0, hy + 0.32, -sw * 0.5 - 0.06),
			Vector3(34.0 * DEG, 0, 0)), "lamp")


static func f4_small(to: Node3D) -> void:
	_well(to, SHAFT["small"], H_SMALL)


static func f4_medium(to: Node3D) -> void:
	_well(to, SHAFT["medium"], H_MEDIUM)


static func f4_large(to: Node3D) -> void:
	_well(to, SHAFT["large"], H_LARGE)


# ═════════════════════════════════════════════
# F5 — BUTTRESS.  BASE: A PLINTH WITH FOUR RAKING BUTTRESSES.
#                 COLOUR: FOUR CANTILEVERED SHOULDERS, CAPS AND A BANNER.
#
# THE BASE. F's own two-step plinth, kept, with four buttresses raking out from
# the shaft's corners down to ground pads — and a capping plate along each
# buttress's back.
#
# WHAT THE BUTTRESSES ARE FOR. They widen the FOOTPRINT without widening the
# SHAFT. That matters because the shaft's width is the size cue — it is the
# thing the constant cap is compared against — so any base that fattens the
# shaft to look planted is spending the concept's only ruler on its foundation.
# Buttresses buy the planted read on the diagonals, where the eye is not
# measuring. They are on the CORNERS and not the faces for the same reason the
# fins are: the approach face stays clear for the console, and all four
# elevations keep a readable flat.
#
# THE COLOUR, and this is the answer aimed squarely at the occlusion problem:
#   · FOUR SHOULDERS, cantilevered out to 2.1 m from the axis at the corbel.
#     MEASURED AGAINST THE DRONE: the Tick's barbs land 1.82 m from the axis
#     and its placed box is 3.23 across, so a shoulder reaching 2.1 m stands
#     OUTSIDE the drone in plan as well as below it. This is the only painted
#     zone in the set that is visible from directly above a hacked core.
#   · THE BUTTRESS CAPS, four raking painted strips running down to the ground
#     pads. They put colour on the DIAGONALS, which is the bearing every other
#     variant is weakest on, and they are the lowest painted thing here.
#   · THE BANNER, a tall painted plate standing proud beside the console bay.
#     Eye level at the approach face.
# ═════════════════════════════════════════════

const F5_SHOULDER_R := 2.1      ## how far a shoulder reaches from the axis


## ONE BUTTRESS on the corner (sx, sz), built in a YAWED FRAME.
##
## In the hub's frame the buttress runs out along -Z, so the whole thing is one
## Rx. A rotation of t about X takes +Y to (0, cos t, sin t), so the angle that
## lays a box along d is atan2(d.z, d.y) — POSITIVE. Drawn with the sign flipped
## all four buttresses rake INWARD and the core reads as standing on a tripod of
## sticks falling over, which is round two's H-strut note in a new place.
static func _buttress(to: Node, sx: float, sz: float, sw: float, foot_r: float,
		top_y: float) -> void:
	var hub := Node3D.new()
	hub.rotation = Vector3(0, atan2(-sx, -sz), 0)
	to.add_child(hub)
	var r0: float = sw * 0.5 * 1.28
	var foot := Vector3(0, 0.12, -foot_r)
	var top := Vector3(0, top_y, -r0)
	var d: Vector3 = top - foot
	var ang: float = atan2(d.z, d.y)
	_Parts.box(hub, Vector3(0.42, d.length(), 0.34), (top + foot) * 0.5,
			Vector3(ang, 0, 0))
	# The ground pad it lands on. A rake that stops in mid-air at the bottom is
	# a strut; one that lands on a pad is a buttress.
	_Parts.box(hub, Vector3(0.78, 0.24, 0.7), Vector3(0, 0.12, -foot_r))
	_Parts.studs(hub, 3, Vector3(-0.24, 0.25, -foot_r), Vector3(0.24, 0, 0), 0.05)
	# THE CAP, painted: a strip lying on the buttress's outer back, offset along
	# the rake's own normal so it sits ON the member rather than inside it.
	var n := Vector3(0, sin(ang), -cos(ang))
	_paint(_Parts.box(hub, Vector3(0.22, d.length() - 0.3, 0.12),
			(top + foot) * 0.5 + n * 0.22, Vector3(ang, 0, 0)), "buttress_cap")


## ONE SHOULDER off the face (sx, sz) — a horizontal bracket with a raised fin
## standing on its outer end. The fin is the part that carries: a flat
## cantilever seen from the ground is a line, and a blade on the end of it is a
## shape.
static func _shoulder(to: Node, bearing_deg: float, sw: float, y: float) -> Array:
	var hub := Node3D.new()
	hub.rotation = Vector3(0, bearing_deg * DEG, 0)
	to.add_child(hub)
	var r0: float = sw * 0.5
	var out: float = F5_SHOULDER_R - r0
	var made: Array = []
	made.append(_Parts.box(hub, Vector3(0.86, 0.26, out),
			Vector3(0, y, -(r0 + out * 0.5))))
	# THE BLADE. Unrotated, because in the hub's frame _Parts.plate's broad face
	# already looks along -Z, which IS the radial direction — a yaw of 90 would
	# have turned the sign edge-on to the only bearing it is there to be seen
	# from.
	made.append(_Parts.plate(hub, 0.74, 0.58, 0.16, 0.12,
			Vector3(0, y + 0.32, -F5_SHOULDER_R + 0.08)))
	# A knee brace under it, unpainted: structure is grey, the colour is the
	# thing the structure carries. Rx(t) takes +Y to (0, cos t, sin t), so the
	# angle that lays a box along d is atan2(d.z, d.y).
	var foot := Vector3(0, y - 0.95, -r0 - 0.05)
	var head := Vector3(0, y - 0.14, -(r0 + out * 0.82))
	var d: Vector3 = head - foot
	_Parts.box(hub, Vector3(0.2, d.length(), 0.2), (foot + head) * 0.5,
			Vector3(atan2(d.z, d.y), 0, 0))
	return made


static func _buttressed(to: Node3D, sw: float, target: float) -> void:
	var ground := 0.46
	var foot_r: float = sw * 0.5 + 1.25
	_F._plinth(to, sw * 0.62, sw * 0.62, ground)
	var t := _trunk(to, sw, target, ground)
	var neck: float = float(t["neck"])
	# The buttresses stop a third of the way up: any higher and they read as a
	# pylon's legs and the shaft stops being the thing that is tall.
	var btop: float = ground + (neck - ground) * 0.34
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_buttress(to, sx, sz, sw, foot_r, btop)

	# ── PAINT ────────────────────────────────────────────────────────────────
	for i in 4:
		_paint_all(_shoulder(to, 90.0 * float(i), sw, neck - 0.45), "shoulder")
	# THE BANNER, beside the console bay rather than over it. A painted plate on
	# top of the lit plate would be two things fighting for one patch of wall.
	_paint(_Parts.plate(to, 0.4, minf(neck - 1.4, 3.2), 0.16, 0.08,
			Vector3(sw * 0.5 - 0.26, 1.9, -sw * 0.5 + 0.02)), "banner")


static func f5_small(to: Node3D) -> void:
	_buttressed(to, SHAFT["small"], H_SMALL)


static func f5_medium(to: Node3D) -> void:
	_buttressed(to, SHAFT["medium"], H_MEDIUM)


static func f5_large(to: Node3D) -> void:
	_buttressed(to, SHAFT["large"], H_LARGE)


# ─────────────────────────────────────────────
# THE SET, for the renderer. Rows are variants, columns are sizes.
# ─────────────────────────────────────────────

static func sets() -> Array:
	return [
		["F1 APRON      cast apron · lip, collar, pilasters", f1_small, f1_medium, f1_large],
		["F2 RAFT       bolted raft · four full-height fins", f2_small, f2_medium, f2_large],
		["F3 DAIS       stepped dais · riser bands, bays", f3_small, f3_medium, f3_large],
		["F4 WELL       sunken well · kerb cap, runs, lamp", f4_small, f4_medium, f4_large],
		["F5 BUTTRESS   raking buttresses · shoulders, caps", f5_small, f5_medium, f5_large],
	]


# ─────────────────────────────────────────────
# THE TICK SEATED ON EVERY MEDIUM.
#
# The cap is identical in all five, so this row is not asking whether the drone
# FITS — round two settled that. It is asking WHAT IS LEFT TO SEE once the top
# of the core is covered by a 3.23 m drone, which is the question the human's
# first note actually raises. Any painted zone still visible in this row is a
# zone that survives the hack.
# ─────────────────────────────────────────────

static func _seat(to: Node3D, at: Vector3) -> void:
	var n := Node3D.new()
	n.position = at
	to.add_child(n)
	_Hack.tick_placed(n)


static func f1_ticked(to: Node3D) -> void:
	f1_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func f2_ticked(to: Node3D) -> void:
	f2_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func f3_ticked(to: Node3D) -> void:
	f3_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func f4_ticked(to: Node3D) -> void:
	f4_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func f5_ticked(to: Node3D) -> void:
	f5_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func tick_set() -> Array:
	return [
		["F1 APRON", f1_ticked],
		["F2 RAFT", f2_ticked],
		["F3 DAIS", f3_ticked],
		["F4 WELL", f4_ticked],
		["F5 BUTTRESS", f5_ticked],
	]
