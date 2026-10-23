extends RefCounted
class_name ConceptsCore2

# ─────────────────────────────────────────────
# CONCEPT BUILDERS — THE COMPUTE CORE, ROUND TWO. Five concepts, three sizes
# each, fifteen builders, plus five more that seat the chosen hack drone on the
# medium of each.
#
# WHY THERE IS A ROUND TWO. Round one (tools/concepts_core.gd,
# docs/concepts/archive/COMPUTE_CORES.md) asked one question — one form scaled or three
# forms — and designed for ONE interface: a face at ground level the player
# walks up to and presses a key. Since then the human has picked a hack drone,
# TICK (docs/concepts/HACK_DRONE.md), and it lands ON TOP. So the core now has
# TWO interfaces and round one only designed for one of them:
#
#   1. THE APPROACH FACE, unchanged and still disqualifying. The interact
#      raycast is 2 m and does not fire when it starts inside the volume, so
#      reach is the core's own footprint. Every builder here carries _console()
#      on its -Z face with the lit plate between y 1.1 and y 2.0.
#   2. THE CAP. New. Something clamps onto it. TICK measures 3.23 x 3.17 x 3.28
#      placed; its four barbs reach 1.82 m out from the axis and 1.67 m down,
#      and it is built with the barb tips at y 0 so it drops onto a cap by one
#      translation.
#
# THE THREE MEASURED FACTS THAT DRIVE THIS ROUND, read off the .map files at
# 32 units/m and the reason the SHIPPED cap is awkward to land on:
#
#   a. THE PAD VARIES 2.4x. The top column is 1.25 / 1.875 / 3.00 m across at
#      small / medium / large. A clamp sized for one is wrong on the others.
#   b. THE CAP IS CUT AT ABOUT 30 DEGREES, so anything flat-bottomed rocks.
#   c. THE ONLY SQUARE, LEVEL PAIR on the whole core is the two front corner
#      posts.
#
# Every cap below is therefore LEVEL (fact b is a fault, not a feature, and no
# concept here reproduces it) and every cap says in its own comment what it does
# about fact a.
#
# AND ONE FACT FROM LOOKING AT hack_tick.png: on the 12.4 m core the Tick is
# about forty pixels of clutter at the top of a tower. Four of the five
# concepts below have a position on that; the fifth (J) argues you should read
# the HACK rather than the DRONE.
#
# THIS IS ARCHITECTURE, NOT A ROBOT. No concept_kit.head(), no legs, no
# chamfered Walker hull. Primitives from mockup_parts.gd only; read every box
# as a brush. A cylinder stands for a 12-sided brush drum, which is what
# compute_chiller_yard already uses.
#
# TWO DRAWING FAULTS FROM ROUND ONE, carried forward so they are not repeated:
#   · A ROTATED BOX SUBTRACTED FROM A CORNER CUTS A CORNER, not a plane. A
#     shear needs a half-space: a box far bigger than the body with ONE FACE on
#     the cut plane. Nothing here shears, deliberately — every cap is level
#     because the Tick has to sit on it — but the note is why.
#   · EVERY LATTICE IN THE FIRST PASS SPLAYED OUTWARD like a derrick stood on
#     its head. A rotation of t about Z takes +Y to (-sin t, cos t), so the +X
#     member needs +t to lean IN; about X, the +Z member needs -t. _batter()
#     below is the only place that matters here and it carries the signs.
#   · AND ONE FROM ROUND TWO OF THE HACK SHEETS: A BORED HOLE DRAWS IDENTICALLY
#     TO A FLAT FACE at fill = 0. The Yoke lost its whole idea to that. So no
#     cap here is "a socket" by being a hole: every one of them breaks its own
#     outline with a kerb, a lip or lugs standing proud.
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const _Hack := preload("res://tools/concepts_hack.gd")
const DEG := PI / 180.0

## The heights the shipped trio is quoted at. Builders are tuned to land on
## these and the renderer prints what they actually measured — if the two
## disagree, believe the renderer.
const H_SMALL := 4.2
const H_MEDIUM := 7.0
const H_LARGE := 12.4

## TICK, as measured in docs/concepts/HACK_DRONE.md. Nothing here scales it;
## these are the numbers every cap is sized against.
const TICK_REACH := 1.82    ## how far a barb lands from the axis
const TICK_DROP := 1.67     ## how far below the drum centre a barb lands


# ─────────────────────────────────────────────
# SHARED FITTINGS
#
# The family tells, lifted out of maps/blocks/compute: a stepped concrete
# plinth, cable risers up the back, drums, trays, rails. Round one's set, minus
# the cage and the lattice (nothing here needs them) and plus the three
# fittings this round is actually about — the deck, the kerb and the lug.
# ─────────────────────────────────────────────

## A bare transform to hang a sub-assembly off, so a part can be written once in
## its own frame and placed four times.
static func _at(to: Node, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	to.add_child(n)
	return n


## A two-step concrete plinth, top face at `h`. The step is what stops a slab
## from looking like it was dropped on the ground.
static func _plinth(to: Node, hw: float, hd: float, h: float) -> void:
	_Parts.box(to, Vector3(hw * 2.0, h * 0.55, hd * 2.0), Vector3(0, h * 0.275, 0))
	_Parts.box(to, Vector3(hw * 1.8, h * 0.5, hd * 1.8), Vector3(0, h * 0.75, 0))


## THE APPROACH FACE, identical on all fifteen builders and the one thing in
## this file that is not up for discussion. A recess cut into a face with the
## lit plate set INTO the recess rather than laid on the wall — two faces on one
## plane fight over which you see.
##
## `into` must be the CSG body being cut: the subtraction is parented to it, and
## a subtraction parented to a bare Node3D cuts nothing and warns about it.
## `face_z` is the body-local z of the face being cut.
##
## THE HEIGHT IS A WORLD HEIGHT, and that is a correction to round one's helper
## rather than a copy of it. The subtraction is a CHILD of the body, so a
## hard-coded local y of 1.55 is 1.55 ABOVE THE BODY'S OWN ORIGIN — and these
## bodies are boxes centred on their own middles, so on a shaft whose centre sat
## at 1.6 the "1.55 m" console came out at 3.15 and the Walker stood under it
## looking at a wall. Measured off the first render of this round; round one's
## cabinets and cassettes have the same offset in them.
static func _console(into: CSGShape3D, face_z: float, w: float = 1.5) -> void:
	if not (into is CSGShape3D):
		push_warning("_console: nothing to cut into, so no approach face was drawn")
		return
	var y := 1.55                       # world height of the plate's centre
	var local: float = y - into.position.y
	var h: float = (into as CSGBox3D).size.y if into is CSGBox3D else 0.0
	if h > 0.0 and absf(local) > h * 0.5:
		push_warning("_console: the band at y %.2f is outside the body it was cut into, so the plate would float" % y)
	var cut := _Parts.box(into, Vector3(w, 0.9, 0.5), Vector3(0, local, face_z + 0.24))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	_Parts.plate(into.get_parent(), w * 0.8, 0.62, 0.1, 0.1,
			Vector3(into.position.x, y, into.position.z + face_z + 0.42))
	# A kick rail under it, so there is a horizontal at knee height saying
	# "stand here" rather than a hole in a wall.
	_Parts.box(into.get_parent(), Vector3(w * 0.95, 0.09, 0.14),
			Vector3(into.position.x, y - 0.53, into.position.z + face_z - 0.06))


## Two cable risers and their tie, up the BACK face. A blank back is the thing
## that makes a slab read as a placeholder.
static func _risers(to: Node, hw: float, back_z: float, y0: float, y1: float,
		r: float) -> void:
	if y1 - y0 <= 0.2:
		push_warning("_risers: %.2f m of run, so no risers were drawn" % (y1 - y0))
		return
	for sx: float in [-1.0, 1.0]:
		_Parts.cyl(to, r, y1 - y0, Vector3(sx * hw * 0.5, (y0 + y1) * 0.5, back_z + r))
	_Parts.box(to, Vector3(hw * 1.1, r * 2.2, r * 2.2), Vector3(0, y1, back_z + r))


## A drum chiller. The fan ring is SUNK INTO the lid: a torus laid on the top
## face stands half its own thickness proud and quietly adds 0.12 m to the
## measured height of anything a drum is the tallest thing on.
static func _drum(to: Node, at: Vector3, r: float, h: float) -> void:
	_Parts.box(to, Vector3(r * 1.9, 0.18, r * 1.9), at + Vector3(0, 0.09, 0))
	_Parts.cyl(to, r, h, at + Vector3(0, 0.18 + h * 0.5, 0), Vector3.ZERO, false, 12)
	_Parts.ring(to, r * 0.42, r * 0.66, at + Vector3(0, 0.18 + h - 0.07, 0))


## A cable tray on stands, running along x at height `y`.
static func _tray(to: Node, x0: float, x1: float, z: float, y: float) -> void:
	var span: float = absf(x1 - x0)
	_Parts.box(to, Vector3(span, 0.12, 0.44), Vector3((x0 + x1) * 0.5, y, z))
	for s: float in [0.12, 0.88]:
		_Parts.box(to, Vector3(0.14, y, 0.14), Vector3(lerpf(x0, x1, s), y * 0.5, z))


## A handrail: posts and two bars. The one fitting that is always robot-scale
## whatever the core is.
static func _rail(to: Node, x0: float, x1: float, z: float, y0: float) -> void:
	var posts: int = maxi(2, int(absf(x1 - x0) / 1.6) + 1)
	for i in posts:
		var x: float = lerpf(x0, x1, float(i) / float(posts - 1))
		_Parts.box(to, Vector3(0.1, 1.05, 0.1), Vector3(x, y0 + 0.525, z))
	for h: float in [0.52, 1.0]:
		_Parts.box(to, Vector3(absf(x1 - x0), 0.07, 0.07),
				Vector3((x0 + x1) * 0.5, y0 + h, z))


## Band courses up a shaft, so a tall box is not one tall box. Spaced at about
## 2 m, which is the course height the compute blocks already use.
static func _bands(to: Node, hw: float, hd: float, y0: float, y1: float) -> void:
	var n: int = maxi(1, int((y1 - y0) / 2.1))
	for i in range(1, n):
		_Parts.box(to, Vector3(hw * 2.0 + 0.16, 0.14, hd * 2.0 + 0.16),
				Vector3(0, y0 + (y1 - y0) * float(i) / float(n), 0))


## FOUR BATTERED POSTS, leaning IN over their rise. The only place in this file
## where the round-one sign note bites: +X needs +t about Z, +Z needs -t about X.
static func _batter(to: Node, hw: float, hd: float, y0: float, y1: float,
		post: float, lean: float) -> void:
	var rise := y1 - y0
	if rise <= 0.0:
		push_warning("_batter: %.2f m of rise, so no posts were drawn" % rise)
		return
	var tilt: float = atan2(lean, rise)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_Parts.box(to, Vector3(post, rise, post),
					Vector3(sx * (hw - lean * 0.5), y0 + rise * 0.5, sz * (hd - lean * 0.5)),
					Vector3(-sz * tilt, 0, sx * tilt))


# ─────────────────────────────────────────────
# THE CAP VOCABULARY — the three fittings this round exists to design.
#
# A cap that is going to be clamped has to be THREE things at once: level (the
# shipped 30-degree cut is the fault, not the style), bounded (something for a
# barb to catch on), and VISIBLE AS A CAP IN OUTLINE — which is the hard one,
# because a hole does not draw and a flat top draws as a line. So every cap
# here is a DECK with a KERB round it and LUGS standing proud at its corners:
# three silhouette breaks, none of which depends on a bore.
# ─────────────────────────────────────────────

const LUG_H := 0.26         ## how far a landing lug stands above its deck
const DECK_T := 0.34        ## deck slab thickness
const KERB_H := 0.15


## A kerb: four bars standing on the deck's edge. This is what stops a deck from
## drawing as a single horizontal line, and it is also the thing a barb that
## slides inward stops against.
static func _kerb(to: Node, hw: float, hd: float, deck_top: float) -> void:
	var t := 0.14
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(t, KERB_H, hd * 2.0),
				Vector3(sx * (hw - t * 0.5), deck_top + KERB_H * 0.5, 0))
	for sz: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(hw * 2.0 - t * 2.0, KERB_H, t),
				Vector3(0, deck_top + KERB_H * 0.5, sz * (hd - t * 0.5)))


## FOUR LANDING LUGS at the deck corners. A chamfered square post, extruded in
## +Y — and the rotation that does that is Rx(+90), NOT Rx(-90).
##
## MEASURED, because it cost a render. CSGPolygon3D extrudes along its own
## NEGATIVE Z: an unrotated plate(0.36, 0.36, 0.26) has AABB position z = -0.26.
## So Rx(-90) takes the extrusion DOWNWARD, through the deck, where it draws as
## nothing at all — and the only symptom was every lugged concept measuring
## 0.11 m short, which is the kerb height, i.e. the kerb had quietly become the
## top of the model.
##
## These are the designed interface. The shipped core has nothing of the kind,
## which is why the hack sheet's §0.3 had to go looking for "the only square
## level pair" and found two corner posts by accident.
static func _lugs(to: Node, hw: float, hd: float, deck_top: float) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_Parts.plate(to, 0.36, 0.36, LUG_H, 0.1,
					Vector3(sx * (hw - 0.26), deck_top, sz * (hd - 0.26)),
					Vector3(PI * 0.5, 0, 0))


## A COMPLETE LANDING PAD in its own frame: lit slot, deck, kerb, lugs, with the
## LUG TOPS at `top`. Everything that measures a concept's height measures the
## lugs, so a pad's quoted height is the height a level designer placed it at.
static func _pad(to: Node, hw: float, top: float) -> void:
	var deck_top: float = top - LUG_H
	# The lit slot UNDER the deck, so the cap stands off its own neck with light
	# beneath it. On the sheets this is the only part of a cap that reads at
	# 40 m, because it is the one horizontal with dark on both sides of it.
	_Parts.box(to, Vector3(hw * 1.78, 0.2, hw * 1.78),
			Vector3(0, deck_top - DECK_T - 0.1, 0))
	_Parts.box(to, Vector3(hw * 2.0, DECK_T, hw * 2.0),
			Vector3(0, deck_top - DECK_T * 0.5, 0))
	_kerb(to, hw, hw, deck_top)
	_lugs(to, hw, hw, deck_top)


# ─────────────────────────────────────────────
# F — CAPITAL.  POSITION: THE CAP IS CONSTANT AND THE CORE GROWS BENEATH IT.
#
# This is the position the brief asked somebody to take. ONE PAD, 2.6 m square,
# at every size — so the Tick is the same size relative to its landing surface
# on a 4.2 m core and on a 12.4 m one, the clamp is one number, the animation is
# one animation, and fact (a) — the 2.4x pad range — simply stops existing.
#
# It is round one's B inverted. B bolted a fixed-size console to the BOTTOM of a
# scaled mast and the sheet showed why that fails: a constant-size cue under
# perspective says "far away" at least as loudly as it says "big". Putting the
# ruler at the TOP may fail the same way. The sheet is the test; §1 of
# COMPUTE_CORES_2.md says what it showed.
#
# What changes with size is the SHAFT, in girth as well as height — 1.5, 2.3,
# 3.6 m across. That is deliberate: hold the shaft constant too and the three
# are one photograph again, which is the fault round one went to find.
# ─────────────────────────────────────────────

const F_PAD := 1.3          ## HALF-WIDTH OF THE PAD. THE RULER. Do not scale it.


static func _capital(to: Node3D, sw: float, target: float) -> void:
	var base := 0.26
	var neck: float = target - 1.26       # where the cap assembly starts
	_plinth(to, sw * 0.64, sw * 0.64, base)
	var shaft := _Parts.box(to, Vector3(sw, neck - base, sw),
			Vector3(0, (neck + base) * 0.5, 0))
	_console(shaft, -sw * 0.5, minf(sw * 0.74, 1.5))
	_bands(to, sw * 0.5, sw * 0.5, base, neck)
	_risers(to, sw * 0.5, sw * 0.5, base, neck - 0.4, clampf(sw * 0.06, 0.07, 0.14))
	# THE CORBEL. A constant pad on a shaft of three different widths needs a
	# transition or two of the three read as a mistake: on the small core the pad
	# overhangs the shaft by half a metre each side, on the large the shaft is
	# wider than the pad. The corbel is what makes both deliberate.
	var ctop: float = target - LUG_H - DECK_T - 0.2
	_Parts.box(to, Vector3(maxf(sw, F_PAD * 1.5) + 0.1, 0.22, maxf(sw, F_PAD * 1.5) + 0.1),
			Vector3(0, neck + 0.11, 0))
	_Parts.box(to, Vector3(F_PAD * 1.6, ctop - neck - 0.22, F_PAD * 1.6),
			Vector3(0, (ctop + neck + 0.22) * 0.5, 0))
	_pad(to, F_PAD, target)


static func f_small(to: Node3D) -> void:
	_capital(to, 1.5, H_SMALL)


static func f_medium(to: Node3D) -> void:
	_capital(to, 2.3, H_MEDIUM)
	_drum(to, Vector3(1.9, 0.0, 1.1), 0.52, 0.8)


static func f_large(to: Node3D) -> void:
	_capital(to, 3.6, H_LARGE)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 2.42, 0.0, 1.7), 0.62, 1.1)
	_rail(to, -2.4, 2.4, -2.6, 0.0)


# ─────────────────────────────────────────────
# G — CHORUS.  POSITION: THE CAP IS CONSTANT AND THERE ARE MORE OF THEM.
#
# F's answer to the 2.4x pad range with the second half of the thought added:
# if the pad cannot grow, let the COUNT grow. One head at 4.2 m, two at 7.0,
# four at 12.4, each an identical 2.1 m pad on its own bracket at its own
# height.
#
# Three things fall out of that and they are the whole concept.
#
#   · THE TICK STOPS VANISHING. The large core's lowest head is at 5.2 m, which
#     is Walker eye level: on a 12.4 m tower there is a drone-sized object
#     within four metres of the ground, and the eye gets the scale of the tower
#     from the thing clamped to it rather than the other way round.
#   · A CORE CAN BE PARTLY TAKEN. Four heads is four hacks, and a core with two
#     Ticks on it and two bare pads is a readable mid-state. No other concept
#     here can say anything about progress.
#   · THE SILHOUETTE IS ASYMMETRIC, which is the one property that survives
#     being 200 m away in bad light.
# ─────────────────────────────────────────────

const G_HEAD := 1.05        ## HALF-WIDTH OF ONE HEAD. Constant, like F's pad.


## One head on its own stem, built in its own frame. `stem_from` is the y the
## stem grows out of — a bracket top, or the trunk's plinth.
static func _head(to: Node, at: Vector3, top: float, stem_from: float) -> void:
	var h := _at(to, Vector3(at.x, 0, at.z))
	var under: float = top - LUG_H - DECK_T - 0.2
	if under - stem_from < 0.3:
		push_warning("_head: %.2f m of stem, so the head would sit on its bracket" % (under - stem_from))
		return
	_Parts.box(h, Vector3(G_HEAD * 1.62, under - stem_from, G_HEAD * 1.62),
			Vector3(0, (under + stem_from) * 0.5, 0))
	# Louvres down the flanks of every head, so four of them are four machines
	# and not four boxes.
	for sx: float in [-1.0, 1.0]:
		for k in maxi(1, int((under - stem_from) / 0.46)):
			_Parts.box(h, Vector3(0.08, 0.13, G_HEAD * 1.2),
					Vector3(sx * (G_HEAD * 0.81 + 0.04), stem_from + 0.3 + float(k) * 0.46, 0))
	_pad(h, G_HEAD, top)


## A bracket off the trunk: a slab and two diagonal struts under it. This is
## what carries a head out to one side, and the struts are not decoration —
## without them a 2.1 m head on a 1 m shelf reads as floating.
static func _bracket(to: Node, sx: float, trunk_hw: float, out: float, y: float) -> void:
	var x0: float = sx * trunk_hw
	var x1: float = sx * (trunk_hw + out)
	_Parts.box(to, Vector3(out + 0.2, 0.3, G_HEAD * 2.1),
			Vector3((x0 + x1) * 0.5, y - 0.15, 0))
	var drop := 1.3
	var ang: float = atan2(drop, out)
	var leng: float = sqrt(drop * drop + out * out)
	for sz: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(leng, 0.16, 0.16),
				Vector3((x0 + x1) * 0.5, y - 0.3 - drop * 0.5, sz * G_HEAD * 0.8),
				Vector3(0, 0, sx * ang))


static func _chorus(to: Node3D, tw: float, target: float, brackets: Array) -> void:
	var base := 0.3
	_plinth(to, tw * 0.72, tw * 0.72, base)
	# The trunk stops UNDER the top head: the head's own stem finishes the
	# height, so the quoted number is a lug top and not a guess.
	var trunk_top: float = target - LUG_H - DECK_T - 0.2 - 0.9
	var trunk := _Parts.box(to, Vector3(tw, trunk_top - base, tw),
			Vector3(0, (trunk_top + base) * 0.5, 0))
	_console(trunk, -tw * 0.5, minf(tw * 0.74, 1.5))
	_bands(to, tw * 0.5, tw * 0.5, base, trunk_top)
	_risers(to, tw * 0.5, tw * 0.5, base, trunk_top - 0.5, clampf(tw * 0.06, 0.07, 0.14))
	_head(to, Vector3.ZERO, target, trunk_top)
	for b: Array in brackets:
		var sx: float = float(b[0])
		var y: float = float(b[1])
		var out: float = tw * 0.5 + G_HEAD * 1.1
		_bracket(to, sx, tw * 0.5, out, y)
		_head(to, Vector3(sx * (tw * 0.5 + out * 0.5 + 0.1), 0, 0), y + 1.5, y)


static func g_small(to: Node3D) -> void:
	# ONE HEAD. At this size the concept is indistinguishable from a plain
	# capped column, and that is correct: the chorus is what being big MEANS.
	_chorus(to, 1.7, H_SMALL, [])


static func g_medium(to: Node3D) -> void:
	_chorus(to, 2.3, H_MEDIUM, [[-1.0, 3.2]])


static func g_large(to: Node3D) -> void:
	# FOUR HEADS, alternating sides so the tower is never symmetrical about any
	# axis the player can stand on. The lowest is at 5.2 — within four metres of
	# the ground on a 12.4 m core, which is the Tick-vanishing answer.
	_chorus(to, 3.0, H_LARGE, [[1.0, 8.6], [-1.0, 6.2], [1.0, 3.7]])


# ─────────────────────────────────────────────
# H — SHOULDER.  POSITION: THE CAP COMES DOWN TO THE PLAYER.
#
# Every other concept on both sheets puts the landing pad at the top because
# that is where tops are. H asks why. THE PAD IS AT A CONSTANT 3.6 m ABOVE
# GROUND on all three sizes — a terrace thrown forward off the tower's front —
# and the tower grows ABOVE AND BEHIND it.
#
# So the player walks up, presses the key standing in a covered porch UNDER the
# terrace, and the Tick is clamped two metres over his head at arm's length,
# the same two metres on a 4.2 m core and on a 12.4 m one. The Tick never
# vanishes because the Tick is never further away.
#
# The cost is the obvious one and it is stated in the doc: a thing clamped to a
# shoulder is not crowning anything, and the tower above it is then decoration
# that the mechanic never touches.
# ─────────────────────────────────────────────

const H_TERRACE := 3.6      ## lug tops of the terrace. CONSTANT at every size.
const H_DECK := 1.7         ## half-width of the terrace deck


static func _shoulder(to: Node3D, tw: float, target: float) -> void:
	var base := 0.3
	var tz: float = tw * 0.5               # the tower's front face
	_plinth(to, tw * 0.6, tw * 0.6, base)
	var tower := _Parts.box(to, Vector3(tw, target - base - 0.3, tw),
			Vector3(0, (target - 0.3 + base) * 0.5, 0))
	_bands(to, tw * 0.5, tw * 0.5, base, target - 0.3)
	# A capped head on the tower, so the top is finished rather than cut off.
	# It is NOT a pad: nothing lands here, and it carries no lugs for exactly
	# that reason — a second lugged deck would be a second promise.
	_Parts.box(to, Vector3(tw + 0.5, 0.3, tw + 0.5), Vector3(0, target - 0.15, 0))
	_risers(to, tw * 0.5, tw * 0.5, base, target - 1.2, clampf(tw * 0.06, 0.07, 0.16))

	# THE TERRACE, thrown forward in -Z. Its own frame, because every number in
	# it is about the ground and not about the tower.
	# IT HAS TO OVERLAP THE TOWER, not stand next to it. The first pass set the
	# deck clear of the front face on four vertical legs and photographed as a
	# TRESTLE TABLE parked beside a tower — look at nothing else on that sheet
	# and you would call it furniture. It now cuts 0.38 into the tower and is
	# carried on raking struts instead of legs, which is what makes it a
	# shoulder of the building rather than a thing standing near it.
	var zc: float = -tz - H_DECK * 0.62
	var deck := _at(to, Vector3(0, 0, zc))
	_pad(deck, H_DECK, H_TERRACE)
	var under: float = H_TERRACE - LUG_H - DECK_T
	# A fascia beam under the front edge: the deck's own slab is 0.34 and reads
	# as a tabletop; a beam under it reads as a floor carried on something.
	_Parts.box(deck, Vector3(H_DECK * 2.0 + 0.2, 0.34, 0.36),
			Vector3(0, under - 0.17, -H_DECK + 0.18))
	# TWO RAKING STRUTS, from the deck's front corners back down to the tower's
	# plinth. A rotation of t about X takes +Y to (0, cos t, sin t), so the angle
	# that lays a box along d is atan2(d.z, d.y) — POSITIVE, and drawn with the
	# sign flipped both struts rake forward and the terrace looks propped by a
	# pair of sticks falling over.
	for sx: float in [-1.0, 1.0]:
		var top := Vector3(sx * (H_DECK - 0.34), under - 0.3, zc - H_DECK + 0.34)
		var foot := Vector3(sx * (tw * 0.5 - 0.22), base + 0.1, -tw * 0.5 + 0.12)
		var d := top - foot
		_Parts.box(to, Vector3(0.3, d.length(), 0.3), (top + foot) * 0.5,
				Vector3(atan2(d.z, d.y), 0, 0))
	# THE CONSOLE IS IN THE PORCH, on the tower's own front face, under the
	# terrace. That is the whole arrangement: one bay holds both interfaces, and
	# a player standing on the interact face is standing directly under the
	# clamp.
	_console(tower, -tw * 0.5, 1.5)
	# NO HANDRAIL ON THE TERRACE, and the first pass had one. A 1.05 m rail on a
	# 3.6 m deck tops out at 4.42, which on the SMALL core is taller than the
	# core — the "4.2 m" object measured 4.41. It is also wrong on its own
	# terms: this deck is a landing pad, and a rail round it is a thing for a
	# clamp to foul.
	_tray(to, -1.1, 1.1, zc + H_DECK - 0.3, 2.3)


static func h_small(to: Node3D) -> void:
	# At 4.2 m the terrace IS very nearly the cap — 0.6 m of tower stands above
	# it. The concept degenerates gracefully at the small size, which is the one
	# thing a constant-height feature has going for it.
	_shoulder(to, 1.9, H_SMALL)


static func h_medium(to: Node3D) -> void:
	_shoulder(to, 2.6, H_MEDIUM)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 2.1, 0.0, 1.9), 0.5, 0.9)


static func h_large(to: Node3D) -> void:
	_shoulder(to, 3.4, H_LARGE)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 2.8, 0.0, 2.3), 0.62, 1.2)
	_tray(to, -2.6, 2.6, 2.6, 4.4)


# ─────────────────────────────────────────────
# J — SEMAPHORE.  POSITION: THE CAP IS A MAST HEAD, AND A HACKED CORE LOOKS
# WRONG FROM A KILOMETRE.
#
# Everything above is trying to make the DRONE visible on a big core. J gives
# that up and makes the HACK visible instead.
#
# The cap is a clamp ring of constant radius 1.45 m with four lugs on it — so
# the 2.4x problem is answered the same way F answers it — and standing out of
# that ring are FOUR VANES, raised blades that DO scale with the core: 1.3 m on
# the small, 2.4 on the medium, 4.4 on the large. They are a third of the large
# core's height and they are the only part of it with any width.
#
# When the Tick clamps, THE VANES DROP. j_ticked() is the same builder with one
# angle changed, and that is the argument: at 300 m you cannot see a
# 3.2 m drone on a 12.4 m tower, but you can absolutely see that a tower which
# had a crown this morning does not have one now. The core loses 3.7 m of
# height and its whole top shape.
#
# A hacked core SHOULD look wrong from a distance, and this is the only concept
# on either sheet where it does.
# ─────────────────────────────────────────────

const J_RING := 1.45        ## clamp-ring radius. Constant, and it is the Tick's
                            ## number: the barbs land 1.82 from the axis, so a
                            ## 1.45 rim puts them 0.37 outside it and UNDER the
                            ## roll, which is what gripping a ring means.
const J_LIVE := 58.0        ## vane angle above horizontal, live
const J_DEAD := -34.0       ## and dead: hanging off the ring, visibly fallen


## ONE VANE. Yawed to its bearing first and tilted INSIDE that frame — swing
## them in the root's frame and all four lean the same way, which is the
## discipline concepts_hack._tick_leg's docstring was written for.
##
## In the yawed frame the blade runs out along -Z, and Rx(t) takes (0,0,-1) to
## (0, sin t, -cos t): POSITIVE t lifts the blade. So `tilt_deg` is literally
## the angle above horizontal and J_DEAD being negative means hanging.
static func _vane(to: Node, bearing_deg: float, y: float, leng: float,
		tilt_deg: float) -> void:
	var hub := _at(to, Vector3(0, y, 0))
	hub.rotation = Vector3(0, bearing_deg * DEG, 0)
	var arm := _at(hub, Vector3(0, 0, -J_RING * 0.86))
	arm.rotation = Vector3(tilt_deg * DEG, 0, 0)
	_Parts.box(arm, Vector3(0.2, 0.2, leng * 0.3), Vector3(0, 0, -leng * 0.15))
	# The blade itself: a tall thin plate, chamfered, standing on the arm. Width
	# across the blade is what carries at range, so it is 0.62 m whatever the
	# length — a long thin spike photographs as a scratch.
	_Parts.plate(arm, leng * 0.74, 0.62, 0.12, 0.14,
			Vector3(0, 0, -leng * 0.65), Vector3(0, PI * 0.5, 0))
	# A lit strip along the blade's outer edge. On the dead vanes this is still
	# there and still lit, which is what stops a dropped crown from reading as
	# battle damage.
	_Parts.box(arm, Vector3(0.1, 0.1, leng * 0.66), Vector3(0, 0.3, -leng * 0.65))


## HOW FAR THE VANES REACH ABOVE THEIR HINGE. Solved once and used by both the
## live and the dead build, because the whole concept is a comparison between
## the two and a fudge factor in one of them would fake the result. The blade
## runs out to 1.02 x its length in the arm's frame (it is drawn centred at
## 0.65 and is 0.74 long), and 0.31 is its own half-height.
static func _vane_rise(leng: float, tilt_deg: float) -> float:
	var t: float = tilt_deg * DEG
	return maxf(leng * 1.02 * sin(t) + 0.31 * absf(cos(t)), 0.0)


static func _semaphore(to: Node3D, bw: float, hinge_y: float, leng: float,
		tilt_deg: float) -> void:
	var base := 0.3
	var neck: float = hinge_y - 0.42
	_plinth(to, bw * 0.66, bw * 0.66, base)
	# The body is battered in — a 2.8 m block under a 2.4 m ring would read as a
	# box with a dish on it, and the taper is what makes the ring the point.
	var seg: float = (neck - base) / 3.0
	var w: float = bw
	for i in 3:
		var y: float = base + seg * float(i)
		var stage := _Parts.box(to, Vector3(w, seg, w), Vector3(0, y + seg * 0.5, 0))
		# THE CONSOLE GOES IN WHICHEVER STAGE CONTAINS y 1.55, not in the bottom
		# one. On the small core the vanes and the ring take 2.1 m of the 4.2, so
		# the three battered stages are 0.73 m each and the bottom one tops out
		# at 1.03 — a console cut into it would have been a plate hanging in the
		# air above a ledge.
		if y <= 1.55 and 1.55 < y + seg:
			_console(stage, -w * 0.5, minf(w * 0.74, 1.5))
		else:
			for sx: float in [-1.0, 1.0]:
				_Parts.box(to, Vector3(0.09, 0.14, w * 0.7),
						Vector3(sx * (w * 0.5 + 0.045), y + seg * 0.5, 0))
		_Parts.box(to, Vector3(w + 0.14, 0.1, w + 0.14), Vector3(0, y + seg, 0))
		# 7% per stage, not 10. Round one's B went to 16% and photographed as a
		# wedding cake; at 10% the large one still had three countable steps.
		w *= 0.93
	_risers(to, bw * 0.4, bw * 0.5, base, neck - 0.6, clampf(bw * 0.06, 0.07, 0.14))
	# THE CLAMP RING. A drum with a rolled rim and four lugs — the same interface
	# F and G use, drawn round instead of square because it is a mast head.
	_Parts.cyl(to, J_RING * 0.86, 0.42, Vector3(0, neck + 0.21, 0), Vector3.ZERO, false, 12)
	_Parts.ring(to, J_RING * 0.88, J_RING * 1.04, Vector3(0, neck + 0.4, 0))
	for i in 4:
		var a: float = TAU * (float(i) + 0.5) / 4.0
		_Parts.plate(to, 0.34, 0.34, LUG_H, 0.1,
				Vector3(sin(a) * J_RING * 0.52, hinge_y - LUG_H, cos(a) * J_RING * 0.52),
				Vector3(PI * 0.5, 0, 0))
	for i in 4:
		_vane(to, 45.0 + 90.0 * float(i), hinge_y, leng, tilt_deg)


## The three sizes, as [body width, vane length]. One table, because j_ticked
## has to rebuild the medium from the same numbers.
const J_SIZE := {"small": [1.5, 1.3], "medium": [2.1, 2.4], "large": [3.1, 4.4]}


static func _j(to: Node3D, which: String, target: float, live: bool) -> void:
	var s: Array = J_SIZE[which]
	var leng: float = float(s[1])
	# THE HINGE IS SOLVED FROM THE LIVE VANES AND THEN HELD. A dead core is
	# built on the same ring at the same height and is simply SHORTER, which is
	# the entire claim; re-solving it to 7.0 m would fake the result away.
	var hinge_y: float = target - _vane_rise(leng, J_LIVE)
	_semaphore(to, float(s[0]), hinge_y, leng, J_LIVE if live else J_DEAD)


static func j_small(to: Node3D) -> void:
	_j(to, "small", H_SMALL, true)


static func j_medium(to: Node3D) -> void:
	_j(to, "medium", H_MEDIUM, true)


static func j_large(to: Node3D) -> void:
	_j(to, "large", H_LARGE, true)


# ─────────────────────────────────────────────
# K — FLARE.  POSITION: LET THE PAD GROW, AND GRIP THE EDGE INSTEAD.
#
# The straight opposite of F, and the only concept here that does not try to
# defeat the 2.4x range — it says the range is only a problem because everyone
# is trying to grip the MIDDLE.
#
# The core is a battered shaft that opens out at the top into a flared head,
# corbelled out in three steps, with a LIP standing 0.34 m proud of the head all
# the way round. The pad therefore scales freely — 2.2, 3.4, 5.2 m across — and
# the Tick does not care, because what it grips is the lip, and the lip is the
# same section at every size. An edge interface is scale-free by construction;
# a pad interface never is.
#
# It also means the Tick lands ON A CORNER of the big one rather than in the
# middle of it, which is a better picture than a crab centred on a cathedral:
# the thing is biting something, and an off-centre load is a silhouette break.
# ─────────────────────────────────────────────

static func _flare(to: Node3D, bw: float, hw: float, target: float) -> void:
	var base := 0.3
	var head_top: float = target - KERB_H   # the dish kerb is the top of the model
	var flare_from: float = head_top - 1.9
	_plinth(to, bw * 0.68, bw * 0.68, base)
	# The shaft, battered IN toward the flare so the head is obviously carried
	# and not just a wider box on a narrower one.
	var seg: float = (flare_from - base) / 3.0
	var w: float = bw
	for i in 3:
		var y: float = base + seg * float(i)
		var stage := _Parts.box(to, Vector3(w, seg, w), Vector3(0, y + seg * 0.5, 0))
		# As in J: the stage that CONTAINS the band, not the first one.
		if y <= 1.55 and 1.55 < y + seg:
			_console(stage, -w * 0.5, minf(w * 0.74, 1.5))
		_Parts.box(to, Vector3(w + 0.12, 0.1, w + 0.12), Vector3(0, y + seg, 0))
		w *= 0.88
	_risers(to, bw * 0.42, bw * 0.5, base, flare_from - 0.4, clampf(bw * 0.06, 0.07, 0.15))
	# THE CORBEL, three steps out to the head. Three is the fewest that reads as
	# a flare rather than as a mushroom cap stuck on a stem.
	for i in 3:
		var t: float = (float(i) + 1.0) / 3.0
		var cw: float = lerpf(w * 1.1, hw * 2.0 - 0.5, t)
		_Parts.box(to, Vector3(cw, 0.42, cw), Vector3(0, flare_from + 0.21 + float(i) * 0.42, 0))
	# The head slab, the lit band under its overhang, and THE LIP — a rolled
	# edge standing 0.34 proud of the slab, which is the thing a barb catches.
	_Parts.box(to, Vector3(hw * 2.0, 0.5, hw * 2.0), Vector3(0, head_top - 0.55, 0))
	_Parts.box(to, Vector3(hw * 2.0 + 0.68, 0.3, hw * 2.0 + 0.68),
			Vector3(0, head_top - 0.15, 0))
	_Parts.box(to, Vector3(hw * 2.0 + 0.3, 0.16, hw * 2.0 + 0.3),
			Vector3(0, head_top - 0.38, 0))
	# A shallow dish on top: a kerb set in from the lip, ribs across it. NOT a
	# bore — a hole in a top face draws identically to a flat top face in this
	# project's line art, which is the fault that nearly killed the Yoke.
	_kerb(to, hw - 0.3, hw - 0.3, head_top)
	for sx: float in [-1.0, 1.0]:
		_Parts.box(to, Vector3(0.16, 0.12, (hw - 0.4) * 2.0),
				Vector3(sx * (hw - 0.9), head_top + 0.06, 0))


static func k_small(to: Node3D) -> void:
	_flare(to, 1.5, 1.1, H_SMALL)


static func k_medium(to: Node3D) -> void:
	_flare(to, 2.2, 1.7, H_MEDIUM)
	_drum(to, Vector3(1.8, 0.0, 1.4), 0.5, 0.9)


static func k_large(to: Node3D) -> void:
	_flare(to, 3.2, 2.6, H_LARGE)
	for sx: float in [-1.0, 1.0]:
		_drum(to, Vector3(sx * 2.15, 0.0, 2.2), 0.6, 1.2)
	_rail(to, -2.2, 2.2, -2.6, 0.0)


# ─────────────────────────────────────────────
# THE SET, for the renderer. Rows are concepts, columns are sizes.
# ─────────────────────────────────────────────

static func sets() -> Array:
	return [
		["F  CAPITAL     constant cap, core grows beneath", f_small, f_medium, f_large],
		["G  CHORUS      constant cap, more of them", g_small, g_medium, g_large],
		["H  SHOULDER    cap at a constant 3.6 m", h_small, h_medium, h_large],
		["J  SEMAPHORE   mast head, and the crown drops", j_small, j_medium, j_large],
		["K  FLARE       pad grows, the clamp takes the lip", k_small, k_medium, k_large],
	]


# ─────────────────────────────────────────────
# THE TICK SEATED ON EVERY MEDIUM.
#
# This is the point of the round, so it is geometry and not a claim.
# ConceptsHack.tick_placed builds with the BARB TIPS AT y 0 and the drum centre
# at 2.0, so seating it is one translation — and the seat is 0.45 BELOW the
# cap's lug tops, which puts the barbs down the flanks and the body on the deck,
# the same straddle the hack sheet's seated renders use.
#
# H and K are offset as well as dropped: H's pad is on the terrace, 2.5 m
# forward of the tower axis, and K's whole argument is that the Tick lands on an
# EDGE, so centring it there would be drawing the opposite of what K says.
# ─────────────────────────────────────────────

const SEAT_DROP := 0.45


static func _seat(to: Node3D, at: Vector3) -> void:
	_Hack.tick_placed(_at(to, at))


static func f_ticked(to: Node3D) -> void:
	f_medium(to)
	_seat(to, Vector3(0, H_MEDIUM - SEAT_DROP, 0))


static func g_ticked(to: Node3D) -> void:
	g_medium(to)
	# BOTH heads, because two heads with one Tick on them is the mid-state and
	# the mid-state is the concept. The low head carries it: that is the one the
	# player can see.
	_seat(to, Vector3(-(2.3 * 0.5 + (2.3 * 0.5 + G_HEAD * 1.1) * 0.5 + 0.1),
			3.2 + 1.5 - SEAT_DROP, 0))


static func h_ticked(to: Node3D) -> void:
	h_medium(to)
	_seat(to, Vector3(0, H_TERRACE - SEAT_DROP, -2.6 * 0.5 - H_DECK * 0.84))


static func j_ticked(to: Node3D) -> void:
	# THE HACKED STATE, not the live one: the vanes are down. This cell is the
	# before-and-after against j_medium in the row above it, and the height
	# difference between the two is the whole argument.
	_j(to, "medium", H_MEDIUM, false)
	_seat(to, Vector3(0, H_MEDIUM - _vane_rise(float(J_SIZE["medium"][1]), J_LIVE)
			- SEAT_DROP, 0))


static func k_ticked(to: Node3D) -> void:
	k_medium(to)
	# OFF CENTRE, biting the lip. The head's lip is 2.04 from the axis and a barb
	# lands 1.82 out, so 0.7 m of offset puts the leading barbs just past the lip
	# and the trailing ones on the deck — which is what an edge grip looks like
	# and what centring it would have hidden.
	_seat(to, Vector3(0.7, H_MEDIUM - 0.3 - SEAT_DROP, 0))


static func tick_set() -> Array:
	return [
		["F CAPITAL", f_ticked],
		["G CHORUS", g_ticked],
		["H SHOULDER", h_ticked],
		["J SEMAPHORE hacked", j_ticked],
		["K FLARE", k_ticked],
	]
